extends SkillDefinition

## 【勘测】技能源码。每个出牌阶段限一次，私下观看一名其他角色的全部手牌并从牌堆检索属性【杀】或【桃】。

## “获得属性【杀】”文字选项稳定ID；具体筛选同时要求slash牌效与火焰或雷属性。
const NATURE_SLASH_OPTION_ID: String = "nature_slash"

## “获得【桃】”文字选项稳定ID；牌堆检索使用稳定定义ID tao。
const TAO_OPTION_ID: String = "tao"

## AI观看敌方每张手牌的信息价值；只影响目标选择，不公开或修改目标牌面知识状态。
const AI_HOSTILE_HAND_INFORMATION_VALUE: float = 0.18

## AI获得属性【杀】的基础行动价值；额外结合当前手牌数与敌方存活情况调整。
const AI_NATURE_SLASH_VALUE: float = 2.2

## AI在已受伤时获得【桃】的基础生存价值；体力越低会继续叠加奖励。
const AI_TAO_WOUNDED_VALUE: float = 4.0

## 当前出牌阶段是否已经成功完成勘测；每次普通或额外phaseUseBegin重置。
var _used_this_play_phase: bool = false


## 写入技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"kance",
		"name":"勘测",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"ai_extra_play_phase_value":1.4,
		"description":"出牌阶段限一次，你可以观看一名其他角色的手牌，然后选择并获得牌堆中的一张属性【杀】或【桃】。",
	})


## 安装出牌阶段次数重置；每个额外出牌阶段同样拥有独立的一次发动额度。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player")


## 新出牌阶段开始时恢复勘测发动次数。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 判断当前是否处于持有者自己的出牌阶段、尚未发动且存在一名其他存活角色。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非当前行动角色不能发动主动技能。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and not _used_this_play_phase and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" and not (host.call("get_other_alive_player_ids", owner_player_id) as Array[int]).is_empty()


## 发动勘测；AI可直接提交目标与牌类选项，玩家按钮路径先进入目标选择。
func activate(context: Dictionary = {}) -> String:
	# 直接动作目标ID；负数表示需要创建交互选择。
	var target_id: int = int(context.get("target_id", -1))
	# 直接动作牌类选项；AI合法动作会明确提供稳定ID。
	var option_id: String = str(context.get("control_id", context.get("option_id", "")))
	if target_id >= 0 and option_id in [NATURE_SLASH_OPTION_ID, TAO_OPTION_ID]:
		return "" if _execute_gain(target_id, option_id) else "【勘测】所选目标或牌类已经失效。"
	# 其他存活角色；保持权威座次顺序供界面和回放稳定展示。
	var target_ids: Array[int] = host.call("get_other_alive_player_ids", owner_player_id) as Array[int]
	if target_ids.is_empty():
		return "当前没有可观看手牌的其他角色。"
	request_target_selection("【勘测】请选择一名其他角色观看其手牌", target_ids, 1, 1, true, {"kind":"kance_target"})
	return ""


## 恢复目标选择或牌类选择；第二步不可取消，保证观看后必须完成原文规定的获得选择。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；目标与牌类分别恢复。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "kance_target":
		if not response.confirmed or response.target_ids.size() != 1:
			return true
		# 被观看目标ID；等待期间必须仍为存活在场的其他角色。
		var target_id: int = response.target_ids[0]
		if not (host.call("get_other_alive_player_ids", owner_player_id) as Array[int]).has(target_id):
			return true
		# 完整手牌牌面仅进入玲可本人的定向请求，不修改实体公开与已知状态。
		var display_candidates: Array[Dictionary] = host.call("get_private_hand_view_candidates", owner_player_id, target_id) as Array[Dictionary]
		# 两项获得按钮；同一模态窗口在牌面下方直接提交稳定控制ID。
		var options: Array[Dictionary] = [
			{"id":NATURE_SLASH_OPTION_ID, "label":"获得属性【杀】"},
			{"id":TAO_OPTION_ID, "label":"获得【桃】"},
		]
		request_control_selection("勘测", "请选择获得属性【杀】或【桃】", options, false, {"kind":"kance_gain_option", "target_id":target_id, "display_candidates":display_candidates})
		return true
	if choice_kind == "kance_gain_option":
		if response.confirmed and response.control_id in [NATURE_SLASH_OPTION_ID, TAO_OPTION_ID]:
			_execute_gain(int(context.get("target_id", -1)), response.control_id)
		return true
	return false


## 最终复核目标与阶段次数，记录发动并从摸牌堆顶向下取得所选类别的首张牌。
func _execute_gain(target_id: int, option_id: String) -> bool:
	if _used_this_play_phase or not (host.call("get_other_alive_player_ids", owner_player_id) as Array[int]).has(target_id):
		return false
	if option_id not in [NATURE_SLASH_OPTION_ID, TAO_OPTION_ID]:
		return false
	_used_this_play_phase = true
	announce_activation({"target_id":target_id, "gain_option":option_id})
	# 牌堆过滤条件；属性【杀】排除普通【杀】，桃使用精确定义ID。
	var filter: Dictionary = {"effect_id":"slash", "natures":["fire", "thunder"]} if option_id == NATURE_SLASH_OPTION_ID else {"definition_id":"tao"}
	host.call("gain_top_draw_card_matching", owner_player_id, filter, get_id())
	return true


## 为AI枚举全部“观看目标×获得牌类”组合；动作仍由activate最终复核阶段、目标与次数。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for target_id: int in host.call("get_other_alive_player_ids", owner_player_id) as Array[int]:
		for option_id: String in [NATURE_SLASH_OPTION_ID, TAO_OPTION_ID]:
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id(), "target_id":target_id, "control_id":option_id}})


## 评估勘测主动动作；低体力优先桃，具备攻击目标时属性【杀】更有行动价值，并偏好观看敌方多手牌角色。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载；保存观看目标与获得牌类。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 观看目标ID；敌方手牌越多，私有信息价值越高。
	var target_id: int = int(payload.get("target_id", -1))
	# 所选牌类稳定ID；异常值应低于结束出牌动作。
	var option_id: String = str(payload.get("control_id", ""))
	if target_id < 0 or option_id not in [NATURE_SLASH_OPTION_ID, TAO_OPTION_ID]:
		return -20.0
	# 目标快照与态度；观看友方也合法，但通常不如了解敌方手牌有价值。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	var information_value: float = maxf(-attitude, 0.0) / 5.0 * float(maxi(int(target.get("hand_count", 0)), 0)) * AI_HOSTILE_HAND_INFORMATION_VALUE
	return information_value + _estimate_gain_option_value(authoritative_snapshot, option_id, evaluator)


## 评估交互路径中的目标或牌类选择；与直接主动动作使用同一信息和资源倾向。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理勘测两步选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 动作负载；取消保持0分。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	if str(context.get("kind", "")) == "kance_target":
		# 目标选择；偏好敌方与手牌较多角色。
		var selected_targets: Array = payload.get("selected_target_ids", []) as Array
		if selected_targets.size() != 1:
			return -20.0
		var target_id: int = int(selected_targets[0])
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		return maxf(-attitude, 0.0) / 5.0 * (1.0 + float(maxi(int(target.get("hand_count", 0)), 0)) * AI_HOSTILE_HAND_INFORMATION_VALUE)
	if str(context.get("kind", "")) == "kance_gain_option":
		return _estimate_gain_option_value(authoritative_snapshot, str(payload.get("selected_control_id", "")), evaluator)
	return 0.0


## 估算获得属性【杀】或【桃】的自身收益；仅使用权威快照中的公开体力与本人手牌状态。
func _estimate_gain_option_value(authoritative_snapshot: Dictionary, option_id: String, evaluator: Object) -> float:
	# 玲可快照；自身完整状态用于判断受伤、低体力与已有手牌数量。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty():
		return 0.0
	if option_id == TAO_OPTION_ID:
		# 已损失体力；每点提高桃的即时回复与濒死保留价值，满体力时仍保留救援资源价值。
		var missing_hp: int = maxi(int(owner.get("max_hp", 0)) - int(owner.get("hp", 0)), 0)
		return 1.2 + (AI_TAO_WOUNDED_VALUE if missing_hp > 0 else 0.0) + float(maxi(2 - int(owner.get("hp", 0)), 0)) * 1.5
	if option_id == NATURE_SLASH_OPTION_ID:
		# 场上敌对角色数量；存在敌人时属性【杀】具有直接攻击和连环潜力。
		var hostile_target_count: int = 0
		for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
			# 当前候选角色；只统计存活在场且对玲可为负态度的其他角色。
			var player: Dictionary = player_variant as Dictionary
			var player_id: int = int(player.get("player_id", -1))
			if player_id != owner_player_id and bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)) and evaluator.get_attitude(authoritative_snapshot, owner_player_id, player_id) < 0.0:
				hostile_target_count += 1
		return AI_NATURE_SLASH_VALUE + minf(float(hostile_target_count) * 0.45, 1.8)
	return -20.0
