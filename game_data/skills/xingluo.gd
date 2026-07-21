extends SkillDefinition

## 【星落】技能源码。持有者依次重铸自己与至多两名其他角色的手牌，并按共同类型与颜色摸牌。

## 最多可选择的其他角色数量；固定为2，与技能原文一致。
const MAX_OTHER_TARGETS: int = 2

## 全部重铸牌均为锦囊时的摸牌数；固定2张。
const ALL_TRICK_DRAW_COUNT: int = 2

## 全部重铸牌均为红色时的摸牌数；固定1张，可与锦囊奖励叠加。
const ALL_RED_DRAW_COUNT: int = 1

## 当前出牌阶段是否已经成功发动；普通与额外出牌阶段分别限一次。
var _used_current_play_phase: bool = false


## 写入主动技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"xingluo",
		"name":"星落",
		"trigger":"active",
		"enable":["phaseUse"],
		"ui_enabled":true,
		"description":"出牌阶段限一次，你可以重铸你与至多两名其他角色各一张手牌。若这些牌：类型均为锦囊牌，你摸两张牌；颜色均为红色，你摸一张牌。",
	})


## 每个出牌阶段开始时恢复发动额度。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player", 100)


## 清空本阶段发动标记。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	_used_current_play_phase = false


## 仅在自己的出牌阶段、仍有额度且自己至少有一张普通手牌时开放技能。
func can_activate(_context: Dictionary = {}) -> bool:
	var owner: PlayerState = get_owner_skill_player().get_state()
	return host != null and not _used_current_play_phase and owner != null and owner.alive and not owner.out_of_game and not owner.hand.is_empty() and host.state.current_player_id == owner_player_id and host.state.current_phase == "play"


## 发动星落；先选择0至2名有手牌的其他角色，再进入固定顺序的逐人重铸。
func activate(context: Dictionary = {}) -> String:
	var direct_targets: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		direct_targets.append(int(target_variant))
	if context.has("target_ids"):
		return "" if _begin_recast_sequence(direct_targets) else "【星落】目标已经失效。"
	var target_ids: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.player_id != owner_player_id and player.alive and not player.out_of_game and not player.hand.is_empty():
			target_ids.append(player.player_id)
	request_target_selection("【星落】请选择至多两名其他角色", target_ids, 0, mini(MAX_OTHER_TARGETS, target_ids.size()), true, {"kind":"xingluo_targets"})
	return ""


## 恢复目标选择或当前角色的重铸选牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "xingluo_targets":
		if response.confirmed:
			_begin_recast_sequence(response.target_ids)
		return true
	if choice_kind == "xingluo_recast":
		if response.confirmed and response.card_ids.size() == 1:
			_continue_recast_card(context, response.card_ids[0])
		return true
	return false


## 标记本阶段额度并从技能持有者开始逐名请求一张手牌。
func _begin_recast_sequence(other_target_ids: Array[int]) -> bool:
	if _used_current_play_phase or other_target_ids.size() > MAX_OTHER_TARGETS:
		return false
	var ordered_player_ids: Array[int] = [owner_player_id]
	for target_id: int in other_target_ids:
		var target: PlayerState = host.state.get_player(target_id)
		if target == null or not target.alive or target.out_of_game or target.player_id == owner_player_id or target.hand.is_empty() or ordered_player_ids.has(target_id):
			return false
		ordered_player_ids.append(target_id)
	_used_current_play_phase = true
	_request_recast_at_index({"kind":"xingluo_recast", "player_ids":ordered_player_ids, "player_index":0, "all_trick":true, "all_red":true, "recast_count":0})
	return true


## 为序列中的当前角色建立一牌选择；技能持有者负责选择，其他角色手牌保持牌背未知。
func _request_recast_at_index(context: Dictionary) -> void:
	# 相邻重铸选牌之间的表现间隔；重铸效果和嵌套技能已经结算完毕后再显示下一张手牌选择，避免多个弹窗无缝替换。
	if bool(context.get("wait_before_next_recast", false)):
		context.erase("wait_before_next_recast")
		_schedule_next_recast_request(context)
		return
	var player_ids: Array[int] = _int_values(context.get("player_ids", []) as Array)
	var player_index: int = int(context.get("player_index", 0))
	while player_index < player_ids.size():
		var target_id: int = player_ids[player_index]
		var target: PlayerState = host.state.get_player(target_id)
		if target != null and target.alive and not target.out_of_game and not target.hand.is_empty():
			context["player_index"] = player_index
			context["current_player_id"] = target_id
			var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, target_id) as Array[Dictionary]
			request_card_selection("星落", "请选择%s的一张手牌重铸" % host.call("format_player_log_name", target_id), candidates, 1, 1, false, context)
			return
		player_index += 1
	_finish_recast_sequence(context)


## 使用对局统一流程节奏器延后下一次重铸请求；测试或零速度模式保持同步推进，规则状态不依赖计时器。
func _schedule_next_recast_request(context: Dictionary) -> void:
	# 延时恢复的上下文副本；回调不能继续持有调用链会修改的字典引用。
	var scheduled_context: Dictionary = context.duplicate(true)
	# 下一弹窗恢复回调；统一基类会使用当前游戏速度安排或在零速度模式同步执行。
	var resume_callback: Callable = Callable(self, "_resume_paced_recast").bind(scheduled_context)
	if not schedule_after_flow_interval("next_recast", resume_callback):
		_request_recast_at_index(context)


## 到达表现间隔后恢复下一名角色的重铸选牌；玩家和手牌状态仍在请求创建前逐项复核。
func _resume_paced_recast(context: Dictionary) -> void:
	_request_recast_at_index(context)


## 在移动前读取重铸牌类型与颜色，执行重铸后等待其嵌套触发，再继续下一名角色。
func _continue_recast_card(context: Dictionary, card_uid: int) -> void:
	var target_id: int = int(context.get("current_player_id", -1))
	var target: PlayerState = host.state.get_player(target_id)
	var card: CardInstance = target.find_hand_card(card_uid) if target != null else null
	if card == null:
		return
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	context["all_trick"] = bool(context.get("all_trick", true)) and str(definition.get("type", "")) == "trick"
	context["all_red"] = bool(context.get("all_red", true)) and card.get_color() == "red"
	context["recast_count"] = int(context.get("recast_count", 0)) + 1
	context["player_index"] = int(context.get("player_index", 0)) + 1
	# 下一名仍有手牌的重铸对象存在时，给相邻弹窗留出统一流程间隔；最后一次重铸直接结算奖励，不产生无意义等待。
	context["wait_before_next_recast"] = _has_remaining_recast_candidate(context)
	if not bool(host.call("recast_hand_card", target_id, card_uid)):
		return
	if host.has_pending_card_choice():
		var deferred_context: Dictionary = context.duplicate(true)
		deferred_context["kind"] = "xingluo_continue_sequence"
		defer_settlement(deferred_context)
	else:
		_request_recast_at_index(context)


## 检查当前序列后方是否仍有有效重铸对象；离场、死亡或失去全部手牌的角色会被正常跳过且不产生空白延时。
func _has_remaining_recast_candidate(context: Dictionary) -> bool:
	# 本次固定重铸顺序；数组只保存稳定玩家ID，不持有角色节点。
	var player_ids: Array[int] = _int_values(context.get("player_ids", []) as Array)
	# 下一次待处理的数组位置；该位置之前的角色都已经完成重铸。
	var next_player_index: int = int(context.get("player_index", 0))
	for player_index: int in range(next_player_index, player_ids.size()):
		# 当前后续目标；必须仍在场且至少有一张手牌，才能产生下一条选牌请求。
		var player: PlayerState = host.state.get_player(player_ids[player_index]) if host != null else null
		if player != null and player.alive and not player.out_of_game and not player.hand.is_empty():
			return true
	return false


## 恢复某次重铸移动产生的嵌套选择，然后继续稳定玩家序列。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "xingluo_continue_sequence":
		return false
	context["kind"] = "xingluo_recast"
	_request_recast_at_index(context)
	return true


## 全部重铸完成后分别结算锦囊与红色奖励；两项同时满足时累计摸3张牌。
func _finish_recast_sequence(context: Dictionary) -> void:
	var draw_count: int = 0
	if int(context.get("recast_count", 0)) > 0 and bool(context.get("all_trick", false)):
		draw_count += ALL_TRICK_DRAW_COUNT
	if int(context.get("recast_count", 0)) > 0 and bool(context.get("all_red", false)):
		draw_count += ALL_RED_DRAW_COUNT
	announce_activation({"target_ids":_int_values(context.get("player_ids", []) as Array), "recast_count":int(context.get("recast_count", 0)), "draw_count":draw_count})
	if draw_count > 0:
		host.call("draw", owner_player_id, draw_count)
	# 序列可能结束在流程间隔回调中，此时没有选择提交栈去自动恢复出牌窗口，需显式重新开放。
	if host != null and host.has_method("resume_play_phase_choice"):
		host.call("resume_play_phase_choice")


## 将弱类型数组转换为稳定整数数组。
func _int_values(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


## 为AI枚举不选、单选与双选其他角色的动作；目标必须当前有手牌。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	var target_ids: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.player_id != owner_player_id and player.alive and not player.out_of_game and not player.hand.is_empty():
			target_ids.append(player.player_id)
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[], "payload":{"skill_id":get_id(), "target_ids":[]}})
	for first_index: int in range(target_ids.size()):
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_ids[first_index]], "payload":{"skill_id":get_id(), "target_ids":[target_ids[first_index]]}})
		for second_index: int in range(first_index + 1, target_ids.size()):
			var pair: Array[int] = [target_ids[first_index], target_ids[second_index]]
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":pair, "payload":{"skill_id":get_id(), "target_ids":pair}})


## 评估重铸对象数量与关系；自身重铸提供基础换牌收益，友方换废牌和敌方扰乱均提供较小局面收益。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var score: float = 0.65
	for target_variant: Variant in action.get("target_ids", []) as Array:
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, int(target_variant))
		score += 0.35 if attitude > 0.0 else 0.18
	return score


## 重铸选牌优先低价值牌，并在已知牌面可形成全锦囊或全红奖励时追加组合收益。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if str(context.get("kind", "")) == "xingluo_targets":
		return 0.1
	if str(context.get("kind", "")) != "xingluo_recast":
		return 0.0
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.size() != 1:
		return -100.0
	var target_id: int = int(context.get("current_player_id", owner_player_id))
	return -evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), target_id)
