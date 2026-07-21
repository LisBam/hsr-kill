class_name PlayerMarkService
extends RefCounted

## 角色公开标记服务。规则技能只通过稳定标记ID写入数量与说明，网络快照和界面统一读取PlayerState.public_marks。

## 单个标记允许保存的最大数量；默认999兼顾常规计数显示与异常输入保护，修改会影响所有标记的权威上限。
const MAX_MARK_COUNT: int = 999

## 当前服务绑定的权威对局状态；每局创建独立实例，重新开局后不得继续复用旧状态。
var state: GameState


## 绑定当前对局状态；服务不拥有GameState生命周期，也不直接发送界面信号。
func _init(game_state: GameState = null) -> void:
	state = game_state


## 为角色设置一项公开标记；count小于等于0时等价于移除，globally_unique为true时会先清除其他角色的同ID标记。
func set_mark(player_id: int, mark_id: String, mark_data: Dictionary, globally_unique: bool = false) -> bool:
	if state == null or mark_id.is_empty():
		return false
	# 标记持有者；死亡角色不再获得新标记，离场角色仍保留已有公开状态并允许规则明确写入。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return false
	# 标记数量；0表示删除，正数限制在统一显示与存档安全范围内。
	var count: int = clampi(int(mark_data.get("count", 1)), 0, MAX_MARK_COUNT)
	if count <= 0:
		return remove_mark(player_id, mark_id)
	if globally_unique:
		for other_player: PlayerState in state.players:
			if other_player.player_id != player_id:
				other_player.public_marks.erase(mark_id)
	# 标记图标；界面规范只显示单个字，空值使用问号保证错误数据仍有可见占位。
	var icon_text: String = str(mark_data.get("icon", "?"))
	icon_text = icon_text.substr(0, 1) if not icon_text.is_empty() else "?"
	# 规范化标记快照；仅保留可序列化字段，技能对象、节点或Callable不会进入网络与回放状态。
	var normalized_mark: Dictionary = {
		"id":mark_id,
		"icon":icon_text,
		"name":str(mark_data.get("name", mark_id)),
		"description":str(mark_data.get("description", "")),
		"count":count,
		"source_player_id":int(mark_data.get("source_player_id", -1)),
		"order":int(mark_data.get("order", 0)),
	}
	player.public_marks[mark_id] = normalized_mark
	return true


## 移除角色的一项公开标记；标记不存在时返回false且不改写其他角色状态。
func remove_mark(player_id: int, mark_id: String) -> bool:
	if state == null or mark_id.is_empty():
		return false
	# 标记持有者；死亡角色仍可在死亡结算尾部清理旧标记，因此这里只校验对象存在。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.public_marks.has(mark_id):
		return false
	player.public_marks.erase(mark_id)
	return true


## 返回角色指定标记的深拷贝；空字典表示角色或标记不存在，调用方不能借返回值修改权威状态。
func get_mark(player_id: int, mark_id: String) -> Dictionary:
	if state == null:
		return {}
	# 标记持有者；查询允许读取死亡与离场角色的公开历史状态。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return {}
	return (player.public_marks.get(mark_id, {}) as Dictionary).duplicate(true)


## 查找拥有指定标记且来源匹配的角色ID；source_player_id小于0时忽略来源限制，未找到返回-1。
func find_mark_owner(mark_id: String, source_player_id: int = -1) -> int:
	if state == null or mark_id.is_empty():
		return -1
	for player: PlayerState in state.players:
		# 当前角色标记；只有数量为正且来源满足条件时才视为有效拥有者。
		var mark_data: Dictionary = player.public_marks.get(mark_id, {}) as Dictionary
		if int(mark_data.get("count", 0)) <= 0:
			continue
		if source_player_id >= 0 and int(mark_data.get("source_player_id", -1)) != source_player_id:
			continue
		return player.player_id
	return -1


## 清理一名死亡角色自身持有及由其作为来源创建的全部公开标记；返回是否实际移除了任一项。
func clear_marks_for_dead_player(player_id: int) -> bool:
	if state == null:
		return false
	# 是否发生变化；调用方可据此决定是否需要额外刷新快照。
	var changed: bool = false
	for player: PlayerState in state.players:
		# 死亡角色自身全部标记失效；其他角色只移除来源指向该死者的标记。
		if player.player_id == player_id:
			if not player.public_marks.is_empty():
				player.public_marks.clear()
				changed = true
			continue
		for mark_id_variant: Variant in player.public_marks.keys():
			# 当前标记来源；来源死亡后不再保留无法生效的归属状态。
			var mark_id: String = str(mark_id_variant)
			var mark_data: Dictionary = player.public_marks.get(mark_id_variant, {}) as Dictionary
			if int(mark_data.get("source_player_id", -1)) == player_id:
				player.public_marks.erase(mark_id)
				changed = true
	return changed
