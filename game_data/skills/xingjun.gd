extends SkillDefinition

## 【行军】技能源码。技能在 phaseUseBegin 内直接询问持有者，确认后立即结束该阶段。

## 当前出牌阶段是否仍处于可发动窗口；每次 phaseUseBegin 恢复，使用牌或其他技能后关闭。
var _phase_window_open: bool = false

## 本回合是否通过本技能跳过了出牌阶段；为 true 时在 phaseEnd 询问额外回合目标。
var _skipped_play_phase_this_turn: bool = false


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "xingjun",
		"name": "行军",
		"trigger": "phaseUseBegin",
		"enable": "phaseUse",
		"ui_enabled": false,
		"description": "出牌阶段开始时，你可以跳过该阶段。若如此做，本回合结束时，你可令一名其他角色执行一个额外的回合。",
	})


## 订阅出牌阶段 Begin 与回合结束时机；旧用牌窗口订阅保留兼容状态清理，但不再提供延迟主动按钮。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")
	subscribe_timing("useCard", _on_owner_used_card, "source")
	subscribe_timing("useSkillAfter", _on_owner_used_skill, "source")
	subscribe_timing("phaseEnd", _on_phase_end, "player")


## 阶段开始技能不通过常规主动按钮发动；权威询问只由 phaseUseBegin 回调创建。
func can_activate(_context: Dictionary = {}) -> bool:
	return false


## 旧主动入口保持不可用；阶段 Begin 询问的确认结果由 continue_selection 直接处理。
func activate(_context: Dictionary = {}) -> String:
	return "【行军】只能在出牌阶段 Begin 询问中发动。"


## 常规出牌阶段不追加技能动作；AI 与玩家都在 Begin 询问中使用同一 ChoiceResponse。
func append_play_phase_actions(_result: Array[Dictionary]) -> void:
	pass


## 新的出牌阶段进入 Begin 时立即创建发动询问，并在新回合首次阶段清理旧跳过标记。
func _on_phase_use_begin(event: RuleEvent) -> void:
	_phase_window_open = true
	# 当前阶段所属回合已经由控制器切换；旧标记若仍存在，说明它来自此前完整回合而非本阶段。
	if not bool(event.data.get("extra_phase", false)):
		_skipped_play_phase_this_turn = false
	# Begin 发动确认；零牌布尔请求同时服务本地玩家、AI、网络和回放，不等待常规 chooseToUse 建立。
	request_card_selection("行军", "是否发动【行军】跳过本出牌阶段？", [], 0, 0, true, {"kind":"xingjun_phase_use_begin", "ai_allow_confirm":true})
	_phase_window_open = false


## 持有者声明使用任意牌后关闭“阶段开始时”窗口。
func _on_owner_used_card(_event: RuleEvent) -> void:
	_phase_window_open = false


## 持有者发动其他技能后关闭窗口；本技能自身在 activate 中已经主动关闭。
func _on_owner_used_skill(event: RuleEvent) -> void:
	if str(event.data.get("skill_id", "")) != get_id():
		_phase_window_open = false


## 本回合因【行军】跳过出牌阶段时，在回合结束时询问一名其他角色执行额外回合。
func _on_phase_end(_event: RuleEvent) -> void:
	if not _skipped_play_phase_this_turn:
		return
	_skipped_play_phase_this_turn = false
	# 其他存活角色；定义为所有不等于技能持有者的角色，不依据阵营关系筛选。
	var target_ids: Array[int] = host.call("get_other_alive_player_ids", owner_player_id) as Array[int]
	if target_ids.is_empty():
		return
	request_target_selection("【行军】请选择一名其他角色执行额外回合", target_ids, 0, 1, true, {"kind":"xingjun_extra_turn"})


## 恢复 Begin 发动确认或回合结束目标选择；两类请求都使用统一 ChoiceResponse。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；Begin 确认与回合结束选目标分别处理，避免取消发动被误当作取消额外回合目标。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "xingjun_phase_use_begin":
		if response.confirmed and not _skipped_play_phase_this_turn:
			_skipped_play_phase_this_turn = true
			if not bool(host.call("end_current_play_phase", owner_player_id)):
				_skipped_play_phase_this_turn = false
		return true
	if choice_kind == "xingjun_extra_turn":
		if response.confirmed and response.target_ids.size() == 1:
			get_skill_player(response.target_ids[0]).addPhase()
		return true
	return false


## 评估跳过当前出牌阶段换取友方额外回合的收益；友方越强且自身手牌越少越值得发动。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	return _score_skip_play_phase(authoritative_snapshot, evaluator)


## 计算跳过当前出牌阶段换取友方额外回合的净收益；主动动作兼容钩子与 Begin 确认共用本函数。
func _score_skip_play_phase(authoritative_snapshot: Dictionary, evaluator: Object) -> float:
	# 技能持有者快照；手牌越多，放弃当前出牌阶段的机会成本越高。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty():
		return 0.0
	# 最佳额外回合目标收益；态度与目标综合强度共同决定。
	var best_target_score: float = 0.0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前其他存活角色；技能不能令自己执行额外回合。
		var target: Dictionary = player_variant as Dictionary
		# 当前目标 ID；用于态度和 condition 查询。
		var target_id: int = int(target.get("player_id", -1))
		if target_id == owner_player_id or not bool(target.get("alive", false)):
			continue
		# 目标额外回合收益；只把正态度角色视为候选收益。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		if attitude > 0.0:
			best_target_score = maxf(best_target_score, attitude / 4.0 + evaluator.get_condition(authoritative_snapshot, target_id) * 0.35)
	# 当前阶段机会成本；每张手牌按0.45分估算潜在出牌价值。
	var play_phase_cost: float = float(owner.get("hand_count", 0)) * 0.45
	return best_target_score - play_phase_cost


## 评估 Begin 发动确认或额外回合目标；取消保持0分，确认必须产生严格正收益才会被 AI 选择。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；区分阶段 Begin 发动确认与回合结束目标选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 动作确认状态；取消动作不应获得技能收益。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if str(context.get("kind", "")) == "xingjun_phase_use_begin":
		return _score_skip_play_phase(authoritative_snapshot, evaluator) if bool(payload.get("confirmed", false)) else 0.0
	if str(context.get("kind", "")) != "xingjun_extra_turn":
		return 0.0
	# 已选目标数组；空目标表示取消。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if selected_targets.size() != 1:
		return 0.0
	# 目标 ID；额外回合收益同时取决于阵营态度与当前综合强度。
	var target_id: int = int(selected_targets[0])
	return evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) / 2.0 + evaluator.get_condition(authoritative_snapshot, target_id)
