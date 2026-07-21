extends SkillDefinition

## 【影出】技能源码。在当前有效上家的回合结束时让离场貊泽返场，并在貊泽随后完成自己的回合时再次离场。

## 是否已经由上家回合结束触发返场并等待貊泽自己的回合结束；默认false表示没有待执行的再次离场。
var _waiting_owner_turn_end: bool = false


## 写入离场锁定技静态信息；技能描述严格保持主公钦定原文。
func _init() -> void:
	super({
		"id":"yingchu",
		"name":"影出",
		"trigger":"phaseEnd",
		"ui_enabled":false,
		"lock":true,
		"out_of_game_skill":true,
		"description":"离场技，锁定技，当你上家的回合结束时，若你处于离场状态，你返场；该回合结束时，你再次离场。",
	})


## 订阅回合结束触发点与完整回合尾部；phaseOver覆盖貊泽回合被中断时已经离场的清理语义。
func install() -> void:
	subscribe_timing("phaseEnd", _on_phase_end, "global")
	subscribe_timing("phaseAfter", _on_turn_completed, "global")
	subscribe_timing("phaseOver", _on_turn_completed, "global")


## 当前有效上家的回合结束时让离场貊泽返场，使正常下家计算能够把貊泽纳入下一行动角色。
func _on_phase_end(event: RuleEvent) -> void:
	# 貊泽状态；只有存活且离场时需要判断上家并返场。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	if owner == null or not owner.alive or not owner.out_of_game:
		return
	# 当前有效上家；死亡与离场角色由GameState统一跳过。
	var previous_player: PlayerState = host.state.get_previous_alive_player(owner_player_id)
	if previous_player == null or previous_player.player_id != event.player_id:
		return
	if not bool(host.call("restore_player_to_game", owner_player_id, get_id())):
		return
	_waiting_owner_turn_end = true
	announce_activation({"previous_player_id":event.player_id, "returned":true})


## 貊泽由影出返场后的自身回合完整结束或中断时再次离场；其他角色的phaseAfter不会消费等待标记。
func _on_turn_completed(event: RuleEvent) -> void:
	if not _waiting_owner_turn_end or event.player_id != owner_player_id:
		return
	_waiting_owner_turn_end = false
	# 貊泽状态；回合中已经被其他效果离场时只清理等待标记，不重复派发移出时机。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	if owner == null or not owner.alive or owner.out_of_game:
		return
	announce_activation({"returned":false})
	# phaseAfter已经处于自然回合尾部；关闭中断调度，避免与控制器随后正常下家调度重复启动两个回合。
	host.call("remove_player_from_game", owner_player_id, get_id(), false)
