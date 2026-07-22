extends SkillDefinition

## 【倾力】技能源码。持有者以失去1点体力为代价，视为使用或打出一张雷【杀】。

## 倾力生成的雷【杀】定义ID；无实体材料，因此花色与点数均为none和0。
const THUNDER_SLASH_DEFINITION_ID: String = "sha_thunder"

## 每次发动倾力固定失去的体力值；该费用绕过护盾且不是伤害。
const HP_COST: int = 1


## 写入主动技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"qingli",
		"name":"倾力",
		"trigger":"active",
		"enable":["phaseUse", "chooseToRespond"],
		"ui_enabled":true,
		"description":"你可以失去1点体力并视为使用或打出一张雷【杀】。",
	})


## 分别校验主动使用与响应入口；1点体力也可支付固定费用，费用后的濒死流程仍由统一续接管线处理。
## 主动入口必须复用虚拟雷【杀】完整合法性（含阶段次数上限），保证用杀次数用尽后按钮立即熄灭。
func can_activate(context: Dictionary = {}) -> bool:
	if host == null:
		return false
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or owner.hp <= 0:
		return false
	if str(context.get("active_entry", "")) == "chooseToRespond":
		return owner.hp >= HP_COST and (context.get("response_patterns", []) as Array).has("sha")
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 当前仍可选的雷【杀】目标；空列表表示距离或状态上已无目标。
	var legal_target_ids: Array[int] = _get_legal_target_ids()
	if legal_target_ids.is_empty():
		return false
	# 用任意一名合法目标复核虚拟用牌规则；play_limit 用尽时 validate 会失败，按钮同步熄灭。
	# 必须构造 typed Array[int]；字面量 [int] 在 GDScript 中是无类型 Array，会触发 validate_virtual_use 参数类型错误。
	var preview_target_ids: Array[int] = [legal_target_ids[0]]
	return str(host.card_rules.validate_virtual_use(owner_player_id, THUNDER_SLASH_DEFINITION_ID, preview_target_ids)) == ""


## 发动倾力；响应入口只支付费用，控制器随后建立无材料虚拟响应，主动入口则选择雷【杀】目标。
func activate(context: Dictionary = {}) -> String:
	if str(context.get("active_entry", "")) == "chooseToRespond":
		return "" if get_owner_skill_player().loseHp(HP_COST, get_owner_skill_player()) == HP_COST else "【倾力】未能失去体力。"
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if target_ids.size() == 1:
		return "" if _execute_use(target_ids) else "【倾力】目标已经失效。"
	var legal_target_ids: Array[int] = _get_legal_target_ids()
	if legal_target_ids.is_empty():
		return "当前没有合法的雷【杀】目标。"
	request_target_selection("【倾力】请选择雷【杀】目标", legal_target_ids, 1, 1, true, {"kind":"qingli_target"})
	return ""


## 恢复主动使用的目标选择；取消不支付体力。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "qingli_target" or response == null:
		return false
	if response.confirmed and response.target_ids.size() == 1:
		_execute_use(response.target_ids)
	return true


## 支付失去体力费用并执行无材料雷【杀】；费用产生的嵌套濒死流程完成后才继续用牌。
func _execute_use(target_ids: Array[int]) -> bool:
	if host.card_rules.validate_virtual_use(owner_player_id, THUNDER_SLASH_DEFINITION_ID, target_ids) != "":
		return false
	if get_owner_skill_player().loseHp(HP_COST, get_owner_skill_player()) != HP_COST:
		return false
	if host.has_pending_card_choice():
		return defer_settlement({"kind":"qingli_deferred_use", "target_ids":target_ids.duplicate()})
	return _finish_use(target_ids)


## 在费用完整结算后建立雷【杀】CardUseEvent；持有者死亡或离场时统一入口会拒绝。
func _finish_use(target_ids: Array[int]) -> bool:
	if not bool(host.call("execute_cardless_virtual_card_use", owner_player_id, THUNDER_SLASH_DEFINITION_ID, target_ids, "")):
		return false
	announce_activation({"target_ids":target_ids.duplicate(), "virtual_card_id":THUNDER_SLASH_DEFINITION_ID})
	observe_identity_behavior(target_ids, {"target_result":-1.5, "damage":true, "respond_shan":true, "nature_damage":true})
	return true


## 恢复因费用濒死或其他嵌套选择暂停的主动雷【杀】使用。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "qingli_deferred_use":
		return false
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	_finish_use(target_ids)
	return true


## 返回无材料响应提供的雷【杀】定义；只有当前响应明确接受【杀】时生效。
func get_cardless_response_definition_id(response_patterns: Array[String]) -> String:
	return THUNDER_SLASH_DEFINITION_ID if response_patterns.has("sha") else ""


## 无材料雷【杀】已经实际响应成功后记录倾力发动；用于公开日志与机缘授予的每回合三次额度。
func on_cardless_response_consumed(response_pattern: String, virtual_definition_id: String) -> void:
	announce_activation({"response_pattern":response_pattern, "virtual_card_id":virtual_definition_id})


## 返回主动使用雷【杀】的全部合法单目标。
func _get_legal_target_ids() -> Array[int]:
	return host.card_rules.list_legal_virtual_targets(owner_player_id, THUNDER_SLASH_DEFINITION_ID)


## 为AI枚举每名合法雷【杀】目标。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for target_id: int in _get_legal_target_ids():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id]}})


## 使用雷【杀】标准牌效并扣除1点体力的统一资源价值；低体力风险由通用评估器进一步体现。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var slash_action: Dictionary = build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
	return evaluator.score_action(authoritative_snapshot, slash_action, owner_player_id) + evaluator.score_resource_change(authoritative_snapshot, owner_player_id, owner_player_id, 0, -HP_COST)


## 构造倾力实际生成的无材料雷【杀】代理动作；其完整用牌联动收益与1点体力费用分别结算。
func build_ai_virtual_card_action(_authoritative_snapshot: Dictionary, action: Dictionary, _evaluator: Object) -> Dictionary:
	# 雷【杀】目标数组；动作已由规则层确认满足距离和次数限制。
	var target_ids: Array = (action.get("target_ids", []) as Array).duplicate()
	return {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":THUNDER_SLASH_DEFINITION_ID, "target_ids":target_ids}
