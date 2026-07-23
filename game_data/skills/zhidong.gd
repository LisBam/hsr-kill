extends SkillDefinition

## 【制动】技能源码。非锁定前段消耗“斗志”视为使用或打出【杀】，锁定后段按单目标牌的直接响应数增加伤害。

## “斗志”公开标记的稳定ID；制动与百折共享同一资源池。
const DOUZHI_MARK_ID: String = "douzhi"

## “斗志”公开标记的单字图标；与百折首次创建的标记保持一致。
const DOUZHI_MARK_ICON: String = "斗"

## “斗志”公开标记的显示排序；固定20保证任一技能返还并重建标记时界面位置一致。
const DOUZHI_MARK_ORDER: int = 20

## 制动每次视为使用或打出【杀】固定消耗的“斗志”数量。
const SLASH_MARK_COST: int = 1

## 制动生成的普通【杀】稳定定义ID；响应、距离、次数与装备联动均走标准杀流程。
const SLASH_DEFINITION_ID: String = "sha"

## 制动主动【杀】固定目标数；每次只能选择1名攻击范围内的合法角色。
const SLASH_TARGET_COUNT: int = 1

## 制动锁定增伤要求的原牌目标数；只有逻辑目标数恰为1的牌可以获得响应数加值。
const SINGLE_DAMAGE_CARD_TARGET_COUNT: int = 1

## AI对每枚“斗志”的基础机会成本；默认1.0分，让虚拟【杀】收益覆盖资源成本后才优先发动。
const AI_DOUZHI_VALUE: float = 1.0

## AI上报制动主动目标的基础负面牌效；默认-1.5分并声明伤害与【闪】响应语义。
const AI_SLASH_TARGET_RESULT: float = -1.5


## 写入技能静态信息；技能正文逐字保持设计原文，half_locked明确标注锁定后段。
func _init() -> void:
	super({
		"id":"zhidong",
		"name":"制动",
		"trigger":"active/damageBegin3",
		"enable":["phaseUse", "chooseToRespond"],
		"ui_enabled":true,
		"half_locked":true,
		"description":"你可以消耗1枚“斗志”标记并视为使用或打出一张【杀】。锁定技，当你因一张目标数为1的牌造成伤害时，你令此伤害+X。（X为响应此牌的牌数）",
	})


## 订阅第三伤害修改时机；locked_segment为true保证非锁定前段失效时仍执行锁定增伤后段。
func install() -> void:
	subscribe_timing("damageBegin3", _on_damage_begin_three, "source", 0, false, false, Callable(), true)


## 当伤害来自目标数为1的牌时，按该牌收到的直接响应牌数量增加本次伤害。
func _on_damage_begin_three(event: RuleEvent) -> void:
	# 来源牌UID；没有父牌上下文的技能伤害和规则伤害不属于“因一张牌造成伤害”。
	var parent_card_uid: int = int(event.data.get("parent_card_uid", -1))
	if parent_card_uid < 0:
		return
	# 实际造成伤害的逻辑牌目标数；优先使用伤害组件快照，缺失时回退当前使用牌最终目标数组。
	var target_count: int = int(event.data.get("damage_card_target_count", host.call("get_card_use_target_count", parent_card_uid)))
	if target_count != SINGLE_DAMAGE_CARD_TARGET_COUNT:
		return
	# 原牌收到的直接响应数；反响应只属于其直接父响应牌，不递归计入原牌。
	var direct_response_count: int = int(host.call("get_card_direct_response_count", parent_card_uid))
	if direct_response_count <= 0:
		return
	event.data["amount"] = maxi(int(event.data.get("amount", 0)), 0) + direct_response_count
	announce_activation({"parent_card_uid":parent_card_uid, "direct_response_count":direct_response_count, "damage_bonus":direct_response_count, "damage_target_id":event.target_id})


## 判断制动在主动使用或打出【杀】入口是否有至少1枚“斗志”并满足对应牌规则。
func can_activate(context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或资源不足时两个入口均不可用。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or _get_douzhi_count() < SLASH_MARK_COST:
		return false
	if str(context.get("active_entry", "")) == "chooseToRespond":
		return (context.get("response_patterns", []) as Array).has("sha")
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 用任一合法目标复核【杀】次数、距离与技能限制；不存在目标时按钮不亮起。
	var legal_target_ids: Array[int] = _get_legal_slash_targets()
	return not legal_target_ids.is_empty()


## 发动制动；响应入口立即支付1枚“斗志”，主动入口则先选择【杀】目标再支付。
func activate(context: Dictionary = {}) -> String:
	if str(context.get("active_entry", "")) == "chooseToRespond":
		if _get_douzhi_count() < SLASH_MARK_COST:
			return "【制动】需要1枚“斗志”标记。"
		host.call("change_player_mark_count", owner_player_id, DOUZHI_MARK_ID, -SLASH_MARK_COST)
		return ""
	# 已提交目标数组；AI和网络动作通过相同字段进入权威复核。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if target_ids.size() == SLASH_TARGET_COUNT:
		return "" if _execute_slash(target_ids) else "【制动】的“斗志”不足或【杀】目标已经失效。"
	# 当前合法【杀】目标；普通【杀】的距离、次数与目标技能限制均已经过滤。
	var legal_target_ids: Array[int] = _get_legal_slash_targets()
	if legal_target_ids.is_empty():
		return "当前没有合法的【杀】目标。"
	request_target_selection("【制动】请选择【杀】目标", legal_target_ids, SLASH_TARGET_COUNT, SLASH_TARGET_COUNT, true, {"kind":"zhidong_slash_target"})
	return ""


## 恢复制动的【杀】目标选择；取消不消耗“斗志”。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "zhidong_slash_target" or response == null:
		return false
	if response.confirmed and response.target_ids.size() == SLASH_TARGET_COUNT:
		_execute_slash(response.target_ids)
	return true


## 复核目标、支付1枚“斗志”并建立无材料【杀】；异常失败时返还已扣资源。
func _execute_slash(target_ids: Array[int]) -> bool:
	if _get_douzhi_count() < SLASH_MARK_COST or str(host.card_rules.validate_virtual_use(owner_player_id, SLASH_DEFINITION_ID, target_ids)) != "":
		return false
	# 支付后的剩余“斗志”；成功记录中公开该值供回放和学习调试。
	var remaining_count: int = int(host.call("change_player_mark_count", owner_player_id, DOUZHI_MARK_ID, -SLASH_MARK_COST))
	if bool(host.call("execute_cardless_virtual_card_use", owner_player_id, SLASH_DEFINITION_ID, target_ids, "")):
		announce_activation({"target_ids":target_ids.duplicate(), "mark_cost":SLASH_MARK_COST, "remaining_mark_count":remaining_count, "virtual_card_id":SLASH_DEFINITION_ID})
		observe_identity_behavior(target_ids, {"target_result":AI_SLASH_TARGET_RESULT, "damage":true, "respond_shan":true})
		return true
	host.call("change_player_mark_count", owner_player_id, DOUZHI_MARK_ID, SLASH_MARK_COST, _build_douzhi_mark_data())
	return false


## 返回无材料响应提供的普通【杀】定义；费用已由activate在本次chooseToRespond入口支付。
func get_cardless_response_definition_id(response_patterns: Array[String]) -> String:
	return SLASH_DEFINITION_ID if response_patterns.has("sha") else ""


## 无材料【杀】实际打出后记录制动响应发动；标记费用不会在此重复扣除。
func on_cardless_response_consumed(response_pattern: String, virtual_definition_id: String) -> void:
	announce_activation({"response_pattern":response_pattern, "mark_cost":SLASH_MARK_COST, "remaining_mark_count":_get_douzhi_count(), "virtual_card_id":virtual_definition_id})


## 返回普通【杀】当前全部合法单目标；统一规则服务处理攻击范围、次数和来牌限制。
func _get_legal_slash_targets() -> Array[int]:
	return host.card_rules.list_legal_virtual_targets(owner_player_id, SLASH_DEFINITION_ID)


## 返回持有者当前“斗志”数量；没有标记时为0。
func _get_douzhi_count() -> int:
	return maxi(int((host.call("get_player_mark", owner_player_id, DOUZHI_MARK_ID) as Dictionary).get("count", 0)), 0)


## 构造制动异常返还资源时首次创建“斗志”所需的公开说明。
func _build_douzhi_mark_data() -> Dictionary:
	return {
		"icon":DOUZHI_MARK_ICON,
		"name":"斗志",
		"description":"卢卡通过【百折】获得的共享资源，可由【百折】和【制动】消耗。",
		"count":1,
		"source_player_id":owner_player_id,
		"order":DOUZHI_MARK_ORDER,
	}


## 为AI枚举每名合法【杀】目标；基础AI仍会叠加酒、武器、伤害技能和目标防御价值。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for target_id: int in _get_legal_slash_targets():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id]}})


## 评估制动主动【杀】；复用普通【杀】完整牌效评分并扣除1枚“斗志”的机会成本。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 制动虚拟牌动作；通用AI会继续估算命中、酒、装备和目标关系。
	var slash_action: Dictionary = build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
	return evaluator.score_action(authoritative_snapshot, slash_action, owner_player_id) - float(SLASH_MARK_COST) * AI_DOUZHI_VALUE


## 构建制动实际生成的无材料【杀】代理动作，供通用卡牌评分与其他技能修正复用。
func build_ai_virtual_card_action(_authoritative_snapshot: Dictionary, action: Dictionary, _evaluator: Object) -> Dictionary:
	return {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":SLASH_DEFINITION_ID, "target_ids":(action.get("target_ids", []) as Array).duplicate()}
