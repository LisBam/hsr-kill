extends SkillDefinition

## 【酩酊】技能源码。限定发动时翻面并对其他角色视为使用【杀】，随后令攻击该目标的伤害来源按每点伤害回复体力。

## 酩酊生成的普通【杀】稳定定义ID；完整复用目标响应、武器与伤害流程。
const SLASH_DEFINITION_ID: String = "sha"

## 酩酊固定选择的其他角色数量；限定技每次只建立1名持续目标。
const SLASH_TARGET_COUNT: int = 1

## 酩酊先选择任意其他角色再视为使用【杀】；该规则覆盖选择和实际使用两个阶段的距离限制。
const VIRTUAL_RULE_OVERRIDES: Dictionary = {"ignore_distance_limit":true}

## 酩酊对每个伤害点固定回复的体力；逐点伤害时连续执行等量次。
const RECOVER_AMOUNT: int = 1

## 酩酊文本在目标武将牌左上角条目中的排序值；与追歼使用相同优先级语义。
const CORNER_TEXT_ORDER: int = 50

## AI发动酩酊时计入的下回合跳过机会成本；默认4分，需由团队回复与本次【杀】收益覆盖。
const AI_TURN_OVER_COST: float = 4.0

## AI按我方每点已损失体力计算的持续治疗潜力；默认每点1.2分。
const AI_ALLIED_MISSING_HP_VALUE: float = 1.2

## AI由我方损失体力获得的最高持续治疗加分；默认7分避免多人长局中估值无限增长。
const AI_HEALING_POTENTIAL_CAP: float = 7.0

## AI上报酩酊首张【杀】目标的基础负面牌效；默认-1.5分并声明伤害与【闪】响应语义。
const AI_SLASH_TARGET_RESULT: float = -1.5

## 本局是否已经成功发动限定技；true后永久关闭主动入口。
var _used: bool = false

## 当前被酩酊指定的目标玩家ID；默认-1表示没有持续效果。
var _marked_target_id: int = -1


## 写入技能静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"mingding",
		"name":"酩酊",
		"trigger":"active/damagePointAfter",
		"enable":"phaseUse",
		"ui_enabled":true,
		"limited":true,
		"description":"限定技，出牌阶段，你可以将武将牌翻面并选择一名其他角色，然后视为对其使用一张【杀】；当一名角色对目标角色造成1点伤害时，造成伤害的角色回复1点体力，直到你的下个回合开始。",
	})


## 订阅逐点伤害、持有者下个实际回合开始与死亡时机；翻面跳过不会发布phaseBegin，因此不会提前清除效果。
func install() -> void:
	subscribe_timing("damagePointAfter", _on_damage_point_after, "global")
	subscribe_timing("phaseBegin", _on_owner_turn_begin, "player", 0, false, false, Callable(), false, true)
	subscribe_timing("dieAfter", _on_player_died, "global", 0, false, false, Callable(), false, true)


## 卸载技能时清除仍存在的目标提示，再释放基类管理的全部订阅。
func uninstall() -> void:
	_clear_mark()
	super()


## 仅允许自身或当前目标死亡后的维护回调越过死亡状态；伤害收益不会在持有者死亡后继续触发。
func can_trigger_while_owner_inactive(event: RuleEvent) -> bool:
	return event.name == "dieAfter"


## 判断限定技尚未使用、处于自身出牌阶段并存在合法的其他【杀】目标。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场、已经发动或不在出牌阶段时均不可用。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and not _used \
		and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" \
		and not _get_legal_slash_targets().is_empty()


## 发动酩酊；直接动作携带目标时立即复核，否则打开单目标确认流程。
func activate(context: Dictionary = {}) -> String:
	# 已提交目标数组；限定技固定选择一名其他角色。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if target_ids.size() == SLASH_TARGET_COUNT:
		return "" if _execute_mingding(target_ids[0]) else "【酩酊】目标已经失效或限定次数已用尽。"
	# 当前合法【杀】目标；酩酊忽略距离，次数与来牌限制仍由统一规则服务复核。
	var legal_target_ids: Array[int] = _get_legal_slash_targets()
	if legal_target_ids.is_empty():
		return "当前没有合法的【杀】目标。"
	request_target_selection("【酩酊】请选择【杀】目标", legal_target_ids, SLASH_TARGET_COUNT, SLASH_TARGET_COUNT, true, {"kind":"mingding_slash_target"})
	return ""


## 恢复酩酊的目标选择；取消不翻面也不消耗限定次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "mingding_slash_target" or response == null:
		return false
	if response.confirmed and response.target_ids.size() == SLASH_TARGET_COUNT:
		_execute_mingding(response.target_ids[0])
	return true


## 最终复核目标，翻面、建立酩酊目标并视为使用【杀】；翻面成功后即消耗限定次数。
func _execute_mingding(target_id: int) -> bool:
	if _used:
		return false
	# 唯一目标数组；使用强类型数组供虚拟牌规则服务复核。
	var target_ids: Array[int] = [target_id]
	if str(host.card_rules.validate_virtual_use(owner_player_id, SLASH_DEFINITION_ID, target_ids, VIRTUAL_RULE_OVERRIDES)) != "":
		return false
	if not bool(host.call("turn_over_player", owner_player_id, owner_player_id, get_id())):
		return false
	_used = true
	_apply_mark(target_id)
	announce_activation({"target_id":target_id, "face_down":true, "virtual_card_id":SLASH_DEFINITION_ID})
	observe_identity_behavior(target_ids, {"target_result":AI_SLASH_TARGET_RESULT, "damage":true, "respond_shan":true})
	# 标记必须早于虚拟【杀】建立，使本次【杀】造成的每点伤害也能令来源回复。
	host.call("execute_cardless_virtual_card_use", owner_player_id, SLASH_DEFINITION_ID, target_ids, "", VIRTUAL_RULE_OVERRIDES)
	return true


## 目标每受到1点正数伤害后，令仍存活在场的伤害来源回复1点体力。
func _on_damage_point_after(event: RuleEvent) -> void:
	if _marked_target_id < 0 or event.target_id != _marked_target_id or event.source_id < 0:
		return
	# 伤害来源角色；无来源伤害、死亡来源和离场来源均不能获得回复。
	var damage_source: PlayerState = host.state.get_player(event.source_id)
	if damage_source == null or not damage_source.alive or damage_source.out_of_game:
		return
	# 回复前体力；仅在实际回复成立时记录技能发动，满体力调用保持无副作用。
	var previous_hp: int = damage_source.hp
	host.call("recover", owner_player_id, event.source_id, RECOVER_AMOUNT, get_id())
	if damage_source.hp > previous_hp:
		announce_activation({"damage_source_id":event.source_id, "marked_target_id":_marked_target_id, "recover":RECOVER_AMOUNT, "damage_point_index":int(event.data.get("damage_point_index", 1)), "damage_total_amount":int(event.data.get("damage_total_amount", 1))})


## 持有者下个实际回合进入phaseBegin时令酩酊效果到期；翻面跳过整个回合时不会触发本回调。
func _on_owner_turn_begin(_event: RuleEvent) -> void:
	_clear_mark()


## 持有者或目标死亡后移除持续效果与武将牌左上角提示。
func _on_player_died(event: RuleEvent) -> void:
	# 死亡角色ID；dieAfter标准时机以player_id表达死亡主体。
	var dead_player_id: int = event.player_id
	if dead_player_id == owner_player_id or dead_player_id == _marked_target_id:
		_clear_mark()


## 写入当前酩酊目标与“追歼”同款左上角文本；再次写入前先清理旧目标。
func _apply_mark(target_id: int) -> void:
	# 最终目标；必须仍为存活在场的其他角色。
	var target: PlayerState = host.state.get_player(target_id) if host != null and host.get("state") != null else null
	if target == null or not target.alive or target.out_of_game or target_id == owner_player_id:
		return
	_clear_mark()
	_marked_target_id = target_id
	host.call("set_character_corner_text_entry", target_id, _get_corner_entry_id(), "酩酊", CORNER_TEXT_ORDER)


## 清除本实例的持续目标与公开文本；重复调用保持幂等且不影响其他技能条目。
func _clear_mark() -> void:
	if host != null and _marked_target_id >= 0 and host.has_method("remove_character_corner_text_entry"):
		host.call("remove_character_corner_text_entry", _marked_target_id, _get_corner_entry_id())
	_marked_target_id = -1


## 返回本技能实例的稳定左上角条目ID；玩家ID区分多名加拉赫同时施加的酩酊。
func _get_corner_entry_id() -> String:
	return "mingding:%d" % owner_player_id


## 返回酩酊当前全部合法目标；“其他角色”由标准single_other模式保证，距离限制由技能规则覆盖。
func _get_legal_slash_targets() -> Array[int]:
	return host.card_rules.list_legal_virtual_targets(owner_player_id, SLASH_DEFINITION_ID, VIRTUAL_RULE_OVERRIDES)


## 为AI枚举每名合法【杀】目标；限定次数已用尽后不再产生动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for target_id: int in _get_legal_slash_targets():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id]}})


## 评估酩酊主动动作；复用【杀】评分，并在我方受伤角色较多时提高持续回复收益。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 酩酊虚拟【杀】动作；通用评分负责命中、装备与目标关系。
	var slash_action: Dictionary = build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
	# 我方已损失体力总量；每点代表后续攻击酩酊目标时可能兑现的一次回复空间。
	var allied_missing_hp: int = 0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；只统计AI态度为正的存活在场友方。
		var player: Dictionary = player_variant as Dictionary
		# 当前角色稳定ID；用于查询技能持有者对其公开态度。
		var player_id: int = int(player.get("player_id", -1))
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)) and evaluator.get_attitude(authoritative_snapshot, owner_player_id, player_id) > 0.0:
			allied_missing_hp += maxi(int(player.get("max_hp", 0)) - int(player.get("hp", 0)), 0)
	# 翻面会跳过下个回合，因此施加固定机会成本；多人受伤时持续治疗预期逐步覆盖该成本。
	return evaluator.score_action(authoritative_snapshot, slash_action, owner_player_id) - AI_TURN_OVER_COST + minf(float(allied_missing_hp) * AI_ALLIED_MISSING_HP_VALUE, AI_HEALING_POTENTIAL_CAP)


## 构造酩酊实际生成的无材料【杀】代理动作，供通用卡牌与被动技能评分链复用。
func build_ai_virtual_card_action(_authoritative_snapshot: Dictionary, action: Dictionary, _evaluator: Object) -> Dictionary:
	return {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":SLASH_DEFINITION_ID, "target_ids":(action.get("target_ids", []) as Array).duplicate()}
