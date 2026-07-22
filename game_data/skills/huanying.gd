extends SkillDefinition

## 【幻影】技能源码。持有者在回合外受到伤害后移出游戏，并在该回合的结束边界返回。

## 触发离场时的全局回合号；默认-1表示当前没有等待返回的离场效果。
var _removed_turn_number: int = -1


## 写入锁定技静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"huanying",
		"name":"幻影",
		"trigger":"damageAfter",
		"ui_enabled":false,
		"lock":true,
		"description":"锁定技，你的回合外，当你受到伤害后，你移出游戏直到本回合结束。",
	})


## 订阅受伤离场、回合结束返场与回合切换兜底监听；兜底只处理遗漏结束边界的异常状态。
func install() -> void:
	subscribe_timing("damageAfter", _on_owner_damaged, "target")
	subscribe_timing("phaseAfter", _on_turn_finished, "global")
	subscribe_timing("phaseOver", _on_turn_finished, "global")
	subscribe_timing("phaseBefore", _on_next_turn_started, "global")


## 允许技能在持有者离场后继续接收唯一的返回时机；其他回调仍会自行核对等待回合号。
func can_trigger_while_owner_inactive(event: RuleEvent) -> bool:
	return _removed_turn_number >= 0 and event.name in ["phaseAfter", "phaseOver", "phaseBefore"]


## 回合外受到正数伤害后立即离场；同一伤害尾部只会建立一次返回标记。
func _on_owner_damaged(event: RuleEvent) -> void:
	if int(event.data.get("amount", 0)) <= 0 or host.state.current_player_id == owner_player_id or _removed_turn_number >= 0:
		return
	# 技能持有者；伤害尾部已经死亡或被其他效果离场时不重复写入状态。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	_removed_turn_number = host.state.turn_number
	announce_activation({"damage_event_id":int(event.data.get("damage_event_id", -1))})
	host.call("remove_player_from_game", owner_player_id, get_id())


## 匹配原触发回合的正常或中断结束边界并返回游戏；必须读取事件回合号，不能依赖可能已经切换的全局状态。
func _on_turn_finished(event: RuleEvent) -> void:
	if _removed_turn_number < 0 or int(event.data.get("turn_number", -1)) != _removed_turn_number:
		return
	_restore_owner_after_removed_turn()


## 在新回合开始时检查遗漏的结束边界；正常流程已在phaseAfter或phaseOver返场，因此不会进入本兜底分支。
func _on_next_turn_started(event: RuleEvent) -> void:
	if _removed_turn_number < 0 or int(event.data.get("turn_number", -1)) <= _removed_turn_number:
		return
	_restore_owner_after_removed_turn()


## 尝试返场并仅在成功后清除等待状态；异常时保留令牌以便下一条全局边界继续补偿，杜绝永久离场。
func _restore_owner_after_removed_turn() -> void:
	if bool(host.call("restore_player_to_game", owner_player_id, get_id())):
		_removed_turn_number = -1
