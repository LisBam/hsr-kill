class_name SkillPlayer
extends RefCounted

## 技能角色操作对象。技能通过本对象使用角色语法，实际状态修改仍统一委托给权威对局控制器。

## 当前角色的稳定玩家 ID；正式对局范围为0至9，无效对象使用-1且所有规则操作都会安全失败。
var player_id: int = -1

## 当前角色操作对象绑定的权威规则端口；只调用公开体力与伤害函数，不直接修改 PlayerState。
var _host: Object

## 创建本对象的技能稳定 ID；写入伤害、护盾和失去体力记录，便于日志、触发与回放追溯来源。
var _reason: String = ""


## 绑定角色、对局端口与技能来源；技能应通过 SkillDefinition.get_skill_player() 创建对象，不手动构造共享实例。
func _init(match_host: Object = null, bound_player_id: int = -1, reason: String = "") -> void:
	_host = match_host
	player_id = bound_player_id
	_reason = reason


## 返回当前角色的只读权威状态；技能只能查询该对象，体力与护盾变化必须继续使用本类规则语法。
func get_state() -> PlayerState:
	if _host == null or _host.get("state") == null:
		return null
	return _host.state.get_player(player_id) as PlayerState


## 使当前角色获得指定点数护盾；source 表示护盾来源角色，成功时返回实际增加的非负护盾值。
func shield(count: int, source: SkillPlayer) -> int:
	if _host == null or not _host.has_method("shield"):
		return 0
	# 护盾来源玩家 ID；没有有效来源对象时按无来源效果记录为-1。
	var source_id: int = source.player_id if source != null else -1
	return int(_host.call("shield", player_id, count, source_id, _reason))


## 使当前角色失去指定点数护盾；该操作只改变护盾，不触发失去体力、受到伤害或体力减少事件。
func loseShield(count: int, source: SkillPlayer) -> int:
	if _host == null or not _host.has_method("change_hujia") or count <= 0:
		return 0
	# 护盾变化来源玩家 ID；没有有效来源对象时按无来源效果记录为-1。
	var source_id: int = source.player_id if source != null else -1
	# 控制器返回带符号变化量；技能语法对外返回实际失去的非负护盾点数。
	return -int(_host.call("change_hujia", player_id, -count, source_id, _reason))


## 使当前角色失去指定点数体力；该操作绕过护盾且不触发造成伤害或受到伤害事件。
func loseHp(count: int, source: SkillPlayer) -> int:
	if _host == null or not _host.has_method("lose_hp"):
		return 0
	# 失去体力来源玩家 ID；只用于独立事件、日志和回放，不作为伤害来源或死亡击杀者。
	var source_id: int = source.player_id if source != null else -1
	return int(_host.call("lose_hp", source_id, player_id, count, _reason))


## 由当前角色对目标造成指定点数伤害；默认造成普通伤害，护盾、装备、连环与濒死均由权威控制器处理。
func damage(count: int, target: SkillPlayer, nature: String = "normal") -> void:
	if _host == null or target == null or not _host.has_method("damage"):
		return
	_host.call("damage", player_id, target.player_id, count, nature, _reason)


## 使当前角色获得一个额外的完整回合；额外回合按加入队列的顺序执行，结束后恢复原本的行动顺序。
func addPhase() -> bool:
	if _host == null or not _host.has_method("add_phase"):
		return false
	return bool(_host.call("add_phase", player_id, _reason))


## 使当前角色在本次出牌阶段结束后获得一个额外的出牌阶段；该接口不包含其他标准回合阶段。
## 在弃牌阶段调用时，额外出牌阶段改在当前弃牌阶段完整结束后执行，随后直接进入结束阶段且不重复弃牌。
func addPlayPhase() -> bool:
	if _host == null or not _host.has_method("add_play_phase"):
		return false
	return bool(_host.call("add_play_phase", player_id, _reason))
