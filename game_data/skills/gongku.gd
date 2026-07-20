extends SkillDefinition

## 【共苦】技能源码。当队友死亡后，可回复1点体力或摸两张牌。


## 写入技能静态信息；技能描述必须与主公提供的原文完全一致。
func _init() -> void:
	super({
		"id": "gongku",
		"name": "共苦",
		"trigger": "dieAfter",
		"ui_enabled": false,
		"description": "当队友死亡后，你可以回复1点体力或摸两张牌。",
	})


## 订阅全局死亡后时机；队友关系由身份规则判定，不依赖界面标记。
func install() -> void:
	subscribe_timing("dieAfter", _on_die_after, "global")


## 任意角色死亡后检查是否为持有者的队友；游戏已结束时不再创建选择。
func _on_die_after(event: RuleEvent) -> void:
	if host == null or host.state == null or host.state.game_over:
		return
	# 死亡角色 ID；优先读取事件目标字段，回退 data 中的 victim_id。
	var victim_id: int = event.target_id if event.target_id >= 0 else int(event.data.get("victim_id", -1))
	if victim_id < 0 or victim_id == owner_player_id:
		return
	# 持有者与死者状态；队友关系不包括自己，且只看身份。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	var victim: PlayerState = host.state.get_player(victim_id)
	if owner == null or victim == null or not owner.alive or owner.out_of_game:
		return
	if not bool(host.call("are_teammates", owner_player_id, victim_id)):
		return
	# 可选项：回复1点体力或摸两张牌；满体力时仍可选择回复（规则允许0实际回复）或摸牌，由玩家自决。
	var options: Array[Dictionary] = [
		{"id":"recover", "label":"回复1点体力"},
		{"id":"draw_two", "label":"摸两张牌"},
	]
	request_control_selection("共苦", "队友已阵亡，请选择一项效果", options, true, {"kind":"gongku_choice", "victim_id":victim_id, "ai_prefer_control_id":_prefer_control_id(owner)})


## 恢复共苦选项；取消表示不发动，确认后执行对应效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "gongku_choice" or response == null:
		return false
	if not response.confirmed:
		return true
	# 选择项稳定 ID；仅接受 recover 与 draw_two。
	var control_id: String = str(response.control_id)
	if control_id == "recover":
		announce_activation({"choice":"recover", "victim_id":int(context.get("victim_id", -1))})
		host.call("recover", owner_player_id, owner_player_id, 1, "gongku")
		return true
	if control_id == "draw_two":
		announce_activation({"choice":"draw_two", "victim_id":int(context.get("victim_id", -1))})
		host.call("draw", owner_player_id, 2)
		return true
	return true


## 为共苦文字选项评分；受伤时优先回复，满血时优先摸两张。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非共苦选择不修改通用评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "gongku_choice":
		return 0.0
	# 标准选择负载；取消保持 0 分。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 持有者快照；用于判断是否受伤。
	var owner: Dictionary = {}
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == owner_player_id:
			owner = player
			break
	# 当前选项稳定 ID；统一选择协议写入 selected_control_id，不能读取不存在的 control_id。
	var control_id: String = str(payload.get("selected_control_id", payload.get("control_id", "")))
	# 是否受伤；满体力时回复收益为0，必须低于摸牌，避免AI无脑点回复。
	var missing_hp: int = maxi(int(owner.get("max_hp", 0)) - int(owner.get("hp", 0)), 0)
	if control_id == "recover":
		return 4.0 if missing_hp > 0 else 0.0
	if control_id == "draw_two":
		return 3.5 if missing_hp <= 0 else 2.0
	return 0.0


## 返回 AI 偏好的控制项 ID；受伤优先回复，否则摸牌。
func _prefer_control_id(owner: PlayerState) -> String:
	if owner != null and owner.hp < owner.max_hp:
		return "recover"
	return "draw_two"
