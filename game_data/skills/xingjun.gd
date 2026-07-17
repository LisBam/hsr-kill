extends SkillDefinition

## 【行军】技能源码。技能按钮仅在持有者出牌阶段尚未执行其他动作时可用，发动后立即结束该阶段。

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
		"ui_enabled": true,
		"description": "出牌阶段开始时，你可以跳过该阶段。若如此做，本回合结束时，你可令一名其他角色执行一个额外的回合。",
	})


## 订阅出牌阶段、用牌、技能和回合结束时机，保证发动窗口与额外回合结算互不耦合。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")
	subscribe_timing("useCard", _on_owner_used_card, "source")
	subscribe_timing("useSkillAfter", _on_owner_used_skill, "source")
	subscribe_timing("phaseEnd", _on_phase_end, "player")


## 仅允许持有者在自己的出牌阶段开始窗口发动一次跳过效果。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者状态；阵亡角色和非当前行动角色不能发动主动技能。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" and _phase_window_open and not _skipped_play_phase_this_turn


## 标记本回合跳过出牌阶段，并通过控制器公开端口立即结束当前阶段。
func activate(_context: Dictionary = {}) -> String:
	_phase_window_open = false
	_skipped_play_phase_this_turn = true
	if not bool(host.call("end_current_play_phase", owner_player_id)):
		_skipped_play_phase_this_turn = false
		return "当前出牌阶段无法被跳过。"
	return ""


## 向 AI 合法动作列表追加标准技能动作；具体是否发动仍由策略选择。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if can_activate():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[]})


## 新的出牌阶段开始时重新开放窗口，并在新回合首次阶段清理旧跳过标记。
func _on_phase_use_begin(event: RuleEvent) -> void:
	_phase_window_open = true
	# 当前阶段所属回合已经由控制器切换；旧标记若仍存在，说明它来自此前完整回合而非本阶段。
	if not bool(event.data.get("extra_phase", false)):
		_skipped_play_phase_this_turn = false


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


## 恢复回合结束时的目标选择；取消不产生额外回合，确认后使用标准 `who.addPhase()` 语法排队。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "xingjun_extra_turn" or response == null:
		return false
	if response.confirmed and response.target_ids.size() == 1:
		get_skill_player(response.target_ids[0]).addPhase()
	return true
