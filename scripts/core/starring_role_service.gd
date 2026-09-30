class_name StarringRoleService
extends RefCounted

## 「主演」权威状态服务。集中维护“场上至多一名主演”这一全局不变量，
## 并复用与【酩酊】【追歼】【永劫】【凶星】完全相同的武将牌左上角公开文本通道显示。
## 服务不执行任何技能效果、不持有技能实例，也不读取 UI 节点。

## 「主演」在武将牌左上角公开文本中的稳定条目ID。
## 主演是角色级唯一状态，每名角色至多保留一个条目，因此条目ID不按技能或来源拆分成多份。
const CORNER_ENTRY_ID: String = "zhuyan"

## 「主演」条目固定显示文本；与概念名保持一致，不附加层数、角色名或技能名。
const CORNER_TEXT: String = "主演"

## 「主演」条目的排序值；固定50，与【酩酊】【追歼】【永劫】【凶星】同档，
## 使全部“角色当前状态”类提示排在【安可】等数值类提示之前。
## 修改该值会改变多名角色同时存在多条提示时的竖排顺序，运行时不应动态调整。
const CORNER_TEXT_ORDER: int = 50

## 当前绑定的对局控制器；服务只调用宿主稳定端口，不直接持有界面节点或技能运行时实例。
## 未被 configure() 绑定时保持 null，全部公开入口在该状态下安全失败且不产生任何副作用。
var _host: Object


## 绑定当前对局控制器；每次重建规则服务与打开新对局时重新配置，旧局状态不会泄漏到新局。
## 主演状态本身保存在 PlayerState.character_corner_text_entries 中并随权威存档往返，
## 因此本函数不缓存也不迁移任何主演数据，只替换宿主引用。
func configure(match_host: Object) -> void:
	_host = match_host


## 返回当前主演的稳定玩家ID；场上没有主演、状态缺失或宿主未绑定时统一返回 -1。
## 判定依据是“该角色的武将牌左上角条目中存在主演条目”，而不是服务内部缓存，
## 因此读档恢复、换将重装技能与回放重演之后都能直接得到权威答案。
func get_starring_player_id() -> int:
	# 当前权威状态；缺失时没有任何角色可以是主演。
	var state: Variant = _get_state()
	if state == null:
		return -1
	# 玩家座次数组；按固定座次顺序扫描，保证多人同时异常携带条目时结果仍然确定。
	for player_variant: Variant in state.players:
		# 当前角色状态；旧存档或测试构造的异常条目按无角色处理。
		var player: PlayerState = player_variant as PlayerState
		if player == null:
			continue
		if player.character_corner_text_entries.has(CORNER_ENTRY_ID):
			return player.player_id
	return -1


## 判断指定角色当前是否为主演；纯查询，不写入状态也不发布快照。
func is_starring(player_id: int) -> bool:
	return player_id >= 0 and get_starring_player_id() == player_id


## 令指定角色成为主演，并保证“至多一名主演”的全局不变量。
## 原子语义：先摘除原主演的主演条目，再写入新主演的主演条目；
## 两次写入都只改 PlayerState 角标条目，由控制器在每次写入后统一刷新公开快照，
## 因此外界不会观察到“两名主演”同时成立的中间状态。
## 除旧主演之外的任何其他角标条目（【酩酊】【永劫】等）不受影响。
## 返回值：新主演角色不存在、已死亡或已离场时返回 false，且不产生任何副作用。
func set_starring(player_id: int) -> bool:
	if _host == null or not _host.has_method("set_character_corner_text_entry"):
		return false
	# 新主演角色；死亡或离场角色不能携带主演状态，避免出现无法通过规则兑现的主演。
	var target_player: PlayerState = _get_player(player_id)
	if target_player == null or not target_player.alive or target_player.out_of_game:
		return false
	# 原主演ID；与新主演相同表示本次调用是幂等刷新，不需要摘除动作。
	var previous_player_id: int = get_starring_player_id()
	if previous_player_id >= 0 and previous_player_id != player_id:
		# 原主演角色；此刻可能已经死亡并清空过条目，条目不存在时移除入口保持幂等失败。
		var previous_player: PlayerState = _get_player(previous_player_id)
		if previous_player != null:
			_host.call("remove_character_corner_text_entry", previous_player_id, CORNER_ENTRY_ID)
	_host.call("set_character_corner_text_entry", player_id, CORNER_ENTRY_ID, CORNER_TEXT, CORNER_TEXT_ORDER)
	return true


## 显式清除主演状态；player_id 小于0表示“清除当前任意主演”，否则只在该角色确实是主演时清除。
## 主演本人死亡、复活换将与技能主动撤销都通过本入口清空；死亡流程在公开标记清理的同一位置调用，
## 因此“场上至多一名主演”在角色离场后同样成立，不会有死者长期占据主演身份。
## 返回值：确实移除了一个主演条目时返回 true；没有主演或宿主未绑定时返回 false。
func clear_starring(player_id: int = -1) -> bool:
	if _host == null or not _host.has_method("remove_character_corner_text_entry"):
		return false
	# 需要清除的主演ID；未指定时按权威状态解析当前主演。
	var current_player_id: int = get_starring_player_id()
	if current_player_id < 0:
		return false
	if player_id >= 0 and player_id != current_player_id:
		return false
	return bool(_host.call("remove_character_corner_text_entry", current_player_id, CORNER_ENTRY_ID))


## 返回宿主持有的权威对局状态；宿主未绑定或尚未创建状态时返回 null。
## 服务不缓存状态引用，保证重开局替换 GameState 后立即读取到新对象。
func _get_state() -> Variant:
	return _host.state if _host != null and _host.get("state") != null else null


## 返回指定稳定玩家ID对应的角色状态；无效ID或状态缺失时返回 null。
func _get_player(player_id: int) -> PlayerState:
	# 权威状态；缺失时无法解析任何角色。
	var state: Variant = _get_state()
	if state == null:
		return null
	return state.get_player(player_id) as PlayerState
