class_name PlayerEffectService
extends RefCounted

## 角色持续效果服务：托管“挂在角色身上”的持续效果实例，并负责按角色状态重建它们。
##
## 存在的理由：有些效果一旦施加就属于被施加的角色，而不是施放它的技能。
## 技能实例会随施放者阵亡、换将或被“非锁定技失效”压制而停止接收时机，
## 这些情况都不应撤回已经挂在目标身上的效果，因此效果实例必须由本服务独立托管。
##
## 职责边界：只维护实例注册表与生命周期，不读任何具体技能或效果 ID，
## 不决定何时施加效果，也不修改角色状态以外的任何字段；具体效果由 game_data/effects 目录下的
## PlayerEffect 子类实现，因此新增效果不需要修改本服务或控制器。

## 本局权威状态；用于遍历角色并按角色自己的持久状态重建效果实例。
var state: GameState = null

## 规则宿主对象（本项目为 MatchController）；效果实例通过它读取权威状态并调用公开端口。
var host: Object = null

## 按“承载角色ID → 效果ID → PlayerEffect”索引的效果实例表。
## 服务持有强引用：效果是 RefCounted，失去引用会被回收，其时机订阅也会被判定为失效。
var _effects_by_player: Dictionary = {}

## 已登记订阅所属的高级触发器；对局重建或测试重装会整体替换该对象，届时全部旧订阅立即失效。
var _bound_trigger_manager: TriggerManager = null


## 写入本局权威状态；服务只读取玩家数组与角色身上的持久状态，不修改任何字段。
func _init(match_state: GameState) -> void:
	state = match_state


## 绑定规则宿主；效果实例订阅时机时需要宿主提供当前对局的高级触发器。
func configure(match_host: Object) -> void:
	host = match_host


## 释放全部效果实例并清空注册表；对局重建、重新开局或整局结束时调用。
## 必须先卸载再清空：直接清空字典会让实例失去引用，未退订的时机将残留到下一次开局。
func reset() -> void:
	for effects_variant: Variant in _effects_by_player.values():
		for effect_variant: Variant in (effects_variant as Dictionary).values():
			# 当前效果实例；无效实例跳过，避免场景释放期间重复访问。
			var effect: PlayerEffect = effect_variant as PlayerEffect
			if effect != null:
				effect.uninstall()
	_effects_by_player.clear()


## 确认当前对局的高级触发器仍是登记订阅时的同一个；被整体替换时丢弃全部实例并重新登记。
## 效果实例订阅的是具体触发器对象，而重新开局（含测试重装最小状态）会替换该对象；
## 若不在此校验，旧实例会保留在已经废弃的触发器上，效果看起来“还在”却不再收到任何时机。
func _sync_trigger_manager() -> void:
	if host == null:
		return
	# 当前对局高级触发器；与登记时同一个时无需任何处理，避免每次施加效果都重建实例。
	var current_manager: TriggerManager = host.get("trigger_manager") as TriggerManager
	if current_manager == _bound_trigger_manager:
		return
	reset()
	_bound_trigger_manager = current_manager


## 为一名承载角色创建或复用一个效果实例；同一角色同一效果只保留一个实例。
## 返回 null 表示该效果 ID 未登记，调用方应按内容配置错误处理。
func install_effect(player_id: int, effect_id: String) -> PlayerEffect:
	if effect_id.is_empty():
		return null
	_sync_trigger_manager()
	# 该角色已有的效果表；不存在时创建，保证同一角色可以同时承载多个不同效果。
	var effects: Dictionary = _effects_by_player.get(player_id, {}) as Dictionary
	# 已存在的同一效果实例；直接复用，避免重复施加时叠加出两套订阅。
	var existing: PlayerEffect = effects.get(effect_id) as PlayerEffect
	if existing != null:
		return existing
	# 当前效果实例；数据库静态定义不保存角色状态，因此必须从脚本重新创建。
	var effect: PlayerEffect = GameDatabase.create_player_effect(effect_id)
	if effect == null:
		return null
	effect.bind(host, player_id)
	effects[effect_id] = effect
	_effects_by_player[player_id] = effects
	effect.install()
	return effect


## 移除一名角色身上的指定效果实例并释放其订阅；承载者死亡或效果自然结束时调用。
func remove_effect(player_id: int, effect_id: String) -> void:
	# 该角色的效果表；不存在表示该效果已经被移除或从未创建。
	var effects: Dictionary = _effects_by_player.get(player_id, {}) as Dictionary
	# 待移除实例；先取出再删除，保证卸载期间再次查询也读不到半卸载实例。
	var effect: PlayerEffect = effects.get(effect_id) as PlayerEffect
	if effect == null:
		return
	effects.erase(effect_id)
	if effects.is_empty():
		_effects_by_player.erase(player_id)
	effect.uninstall()


## 返回一名角色身上的指定效果实例；不存在时返回 null，调用方据此决定是否创建。
func get_effect(player_id: int, effect_id: String) -> PlayerEffect:
	var effects: Dictionary = _effects_by_player.get(player_id, {}) as Dictionary
	return effects.get(effect_id) as PlayerEffect


## 判断一名角色身上是否存在指定效果实例；供技能快速查询自己施加过的持续效果。
func has_effect(player_id: int, effect_id: String) -> bool:
	return get_effect(player_id, effect_id) != null


## 汇总一名角色身上全部效果声明的 AI 手牌压力；没有效果或全部为0时返回0.0。
## 本查询是纯只读的：不创建实例、不修改状态、不发布快照，因此可以被 AI 决策在任意时刻安全调用。
## 多个效果同时存在时求和，使“多个原因都希望该角色少留牌”自然叠加，而不需要在服务里维护优先级表。
func get_ai_hand_pressure(player_id: int) -> float:
	# 该角色的效果表；没有效果时压力为0，AI 行为与不存在本机制时逐字一致。
	var effects: Dictionary = _effects_by_player.get(player_id, {}) as Dictionary
	if effects.is_empty():
		return 0.0
	# 压力合计；逐个效果读取自身声明，服务不识别任何具体效果 ID。
	var total_pressure: float = 0.0
	for effect_variant: Variant in effects.values():
		# 当前效果实例；无效实例跳过，避免场景释放期间的瞬时状态影响决策。
		var effect: PlayerEffect = effect_variant as PlayerEffect
		if effect != null:
			total_pressure += effect.get_ai_hand_pressure()
	return total_pressure


## 移除一名角色身上的全部效果实例；角色需要完整清空自身持续效果时调用。
func clear_player_effects(player_id: int) -> void:
	# 该角色的效果表副本；先复制再逐个移除，避免遍历期间修改原字典。
	var effects: Dictionary = (_effects_by_player.get(player_id, {}) as Dictionary).duplicate()
	for effect_id_variant: Variant in effects.keys():
		remove_effect(player_id, str(effect_id_variant))


## 按角色身上的持久状态重建效果实例；新开一局与存档恢复共用本入口。
## 重建依据是角色自己的 character_form_state（随存档往返），因此不依赖施加者是否在场：
## 施加者已经换将甚至已经失去技能时，挂在目标身上的效果依然会被完整恢复。
func restore_effects() -> void:
	if state == null:
		return
	_sync_trigger_manager()
	# 全部已登记效果 ID；顺序继承数据库目录扫描结果，保证重建顺序稳定可复现。
	var effect_ids: Array[String] = GameDatabase.get_player_effect_ids()
	if effect_ids.is_empty():
		return
	for player: PlayerState in state.players:
		if player == null:
			continue
		for effect_id: String in effect_ids:
			# 探测实例；has_persisted_state 是纯只读查询，不需要绑定端口也不需要订阅时机。
			var probe: PlayerEffect = GameDatabase.create_player_effect(effect_id)
			if probe == null or not probe.has_persisted_state(player):
				continue
			install_effect(player.player_id, effect_id)
