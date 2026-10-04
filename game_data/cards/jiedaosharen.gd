extends CardDefinition

## 【借刀杀人】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 强制【杀】使用的卡牌定义ID；声明期的目标资格查询与持刀者真实提供【杀】后的目标复核读取同一份稳定值，
## 取值必须与【杀】卡牌文件（`game_data/cards/sha.gd`）的静态 `id` 保持一致，取值范围为非空卡牌定义ID。
## 修改影响：改动本常量会让本牌强制要求另一种牌型，属于牌面规则变更，必须同步卡牌文档与全部借刀用例。
const SLASH_DEFINITION_ID: String = "sha"

## 声明期合法【杀】目标查询使用的纯数据覆写；两个键都是核心层已有的公开覆写，不引入任何新语义。
## ignore_phase_limit：与虚拟牌查询保持同一口径，声明期持刀者可能不是当前行动者；
## ignore_play_count_limit：声明期只回答“是否存在合法目标”，阶段次数必须留到真实用牌时判定。
## 取值范围为布尔字典，默认值即本常量；修改影响：去掉任一项都会让声明期判据与正常用牌链路口径不一致。
const LEGAL_SLASH_TARGET_QUERY_OVERRIDES: Dictionary = {"ignore_phase_limit":true, "ignore_play_count_limit":true}


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
## requires_actor_choice=true：结算结果必须回到使用者本人（持刀者未打出【杀】时其武器交给使用者），
## 使用者在结算前阵亡后无法承接武器或决定后续，本牌整体失效。
func _init() -> void:
	super({
		"id": "jiedao",
		"original_name": "借刀杀人",
		"custom_name": "借刀杀人",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "borrow_sword",
		"nature": "normal",
		"target_mode": "weapon_holder",
		"min_targets": 2,
		"max_targets": 2,
		"distance_limit": "special",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "令一名装备武器的角色对合法目标使用【杀】，否则其将武器交给你。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"requires_actor_choice": true,
		"provided_response_pattern": "",
		"ai": {"order":8.0, "value":2.0, "player_result":0.2, "target_result":-1.0, "gain":true, "use_sha":true},
	})


## 执行【借刀杀人】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	# 旧的整牌结算入口仅兼容已完整声明的两个目标；常规 per_target 流程由 resolve_target() 读取结算上下文，绝不能在此补开第二次选目标。
	if target_ids.size() >= 1 and not resolver.host.resolve_trick_negation(actor_id, target_ids[0], card.definition_id):
		if not resolver.is_resolution_stopped():
			# 第一名声明角色；其为实际进入本牌目标时机的持刀者。
			var weapon_holder_id: int = target_ids[0]
			# 第二名声明角色；仅供持刀者响应【杀】使用，不属于本牌目标。
			var victim_id: int = target_ids[1] if target_ids.size() >= 2 else -1
			if _get_legal_slash_target_ids(resolver.host.card_rules, weapon_holder_id).has(victim_id):
				_resolve_borrow_sword(resolver, card.uid, actor_id, weapon_holder_id, victim_id)
			else:
				resolver.host.transfer_equipment(weapon_holder_id, actor_id, "weapon")
	return resolver.default_destination()


## 结算【借刀杀人】唯一的持刀者目标；被【杀】者已在使用牌时指定并保存在共享上下文，不再创建第二次目标选择。
func resolve_target(resolver: Object, card: CardInstance, actor_id: int, target_id: int, resolution_context: Dictionary) -> String:
	if not resolver.host.resolve_trick_negation(actor_id, target_id, card.definition_id) and not resolver.is_resolution_stopped():
		# 使用时已指定的被【杀】者；上下文缺失时安全转入交出武器，避免旧存档或无效动作卡死。
		var victim_id: int = int(resolution_context.get("borrow_sword_victim_id", -1))
		if _get_legal_slash_target_ids(resolver.host.card_rules, target_id).has(victim_id):
			_resolve_borrow_sword(resolver, card.uid, actor_id, target_id, victim_id)
		else:
			resolver.host.transfer_equipment(target_id, actor_id, "weapon")
	return resolver.default_destination()


## 【借刀杀人】保留“持刀者、被【杀】者”的玩家点击顺序；实际用牌时机与目标数组只保留首名持刀者。
func preserves_requested_target_order() -> bool:
	return true


## 返回真正进入【借刀杀人】目标时机的唯一持刀者；第二名角色只作为强制【杀】的已声明对象保存。
func get_resolution_target_ids(requested_target_ids: Array[int]) -> Array[int]:
	# 实际结算目标；显式构造强类型数组，避免条件表达式推断为无类型 Array 后违反返回值契约。
	var result: Array[int] = []
	if requested_target_ids.size() >= 1:
		result.append(requested_target_ids[0])
	return result


## 将第二名已声明角色写入共享上下文；后续牌效直接要求持刀者对其使用【杀】，不再弹出二次选目标窗口。
func configure_requested_target_context(_match_host: Object, _card: CardInstance, _actor_id: int, requested_target_ids: Array[int], resolution_context: Dictionary) -> void:
	if requested_target_ids.size() == 2:
		resolution_context["borrow_sword_victim_id"] = requested_target_ids[1]


## 本牌不再改写共享目标上下文；CardUseEvent 的全部目标时机只处理唯一持刀者。
func configure_resolution_context(_match_host: Object, _card: CardInstance, _actor_id: int, _resolution_context: Dictionary) -> void:
	pass


## 返回借刀杀人的两段顺序指示线；先由使用者指向持刀者，再由持刀者指向被要求出【杀】者。
func get_presentation_indicator_stages(actor_id: int, requested_target_ids: Array[int], _resolution_target_ids: Array[int]) -> Array[Dictionary]:
	# 分阶段指示结果；目标不足两个时回退通用单段表现，避免旧存档伪造第二段。
	var result: Array[Dictionary] = []
	if requested_target_ids.size() != 2:
		return result
	result.append({"actor_id":actor_id, "target_ids":[requested_target_ids[0]]})
	result.append({"actor_id":requested_target_ids[0], "target_ids":[requested_target_ids[1]]})
	return result


## 校验已声明的持刀者与被【杀】者；第一名必须持武器，第二名必须是其攻击范围内的其他存活角色。
func validate_target_selection(rule_service: Object, actor: PlayerState, target_id: int, all_target_ids: Array[int]) -> String:
	if all_target_ids.is_empty():
		return ""
	# 持刀者状态；第一名必须是装备武器的其他存活角色。
	var weapon_holder_id: int = int(all_target_ids[0])
	var weapon_holder: PlayerState = rule_service.state.get_player(weapon_holder_id)
	if weapon_holder == null or weapon_holder_id == actor.player_id or weapon_holder.get_weapon() == null:
		return "借刀杀人的目标必须是装备武器的其他角色。"
	if _get_legal_slash_target_ids(rule_service, weapon_holder_id).is_empty():
		return "借刀杀人的目标当前没有可使用【杀】的合法角色。"
	if all_target_ids.size() >= 2:
		# 被【杀】者；第二名必须由第一名持刀者合法攻击，不能用锦囊使用者的距离替代。
		var victim_id: int = int(all_target_ids[1])
		if victim_id == weapon_holder_id or not _get_legal_slash_target_ids(rule_service, weapon_holder_id).has(victim_id):
			return "借刀杀人的第二个目标必须在持刀者的攻击范围内。"
	return ""


## 为基础 AI 枚举“持刀者、被【杀】者”的完整合法组合；使用时已同时声明两个目标，不再等待牌效内二次选择。
func append_play_phase_card_actions(match_host: Object, actor_id: int, card: CardInstance, result: Array[Dictionary]) -> bool:
	for holder: PlayerState in match_host.state.players:
		# 当前持刀者可攻击角色；每名合法受害者都与持刀者组成一条完整标准出牌动作。
		for victim_id: int in _get_legal_slash_target_ids(match_host.card_rules, holder.player_id):
			var requested_target_ids: Array[int] = [holder.player_id, victim_id]
			match_host.append_card_action_if_legal(result, actor_id, card, requested_target_ids)
	return true


## 修正无懈估值：队友对响应者使用借刀时，无论响应者攻击合法目标还是拒绝后把武器交给队友，团队都不会因锦囊生效受损。
func modify_ai_negation_effect_utility(authoritative_snapshot: Dictionary, responder_id: int, context: Dictionary, current_utility: float, evaluator: Object) -> float:
	# 当前锦囊实际目标；只有持刀者本人评估队友对自己使用借刀时应用复合收益语义。
	var target_id: int = int(context.get("target_id", -1))
	# 当前锦囊来源；缺失来源或不是响应者友方时继续使用通用负面锦囊估值。
	var source_id: int = int(context.get("source_id", -1))
	if target_id == responder_id and source_id >= 0 and evaluator.get_attitude(authoritative_snapshot, responder_id, source_id) > 0.0:
		return absf(current_utility) if not is_zero_approx(current_utility) else 1.0
	return current_utility


## 返回持刀者攻击范围内的全部其他存活角色；自身永远不是其【杀】的合法目标。
## 补充：本函数已退化为 CardRuleService 权威目标资格查询的纯包装，不再自行拼装“存活+非自身+攻击范围”三条件。
## 原实现只做距离与存活判断，绕过了项目既有的通用目标合法性契约（卡牌目标模式、使用者技能目标限制、
## 目标持有技能的来牌限制），因此【琥珀】这类“不可指定目标”的规则在借刀声明期完全失效；
## 改为复用同一条权威查询后，此类限制对“借刀要求使用的【杀】”与正常使用【杀】完全一致，
## 且核心层不需要任何牌名或技能白名单。
## 语义与无名杀 `multicheck` / `filterAddedTarget` 对齐：声明期只查目标资格与攻击范围，不查使用次数。
## 颜色型限制（【琥珀】只拒绝黑色【杀】）在声明期必然通过：此刻只有无色的抽象【杀】，
## 真实颜色要等持刀者交出实体牌之后才可判定，由 _apply_borrow_sword_response() 中的强制复核负责。
func _get_legal_slash_target_ids(rule_service: Object, weapon_holder_id: int) -> Array[int]:
	# 合法【杀】目标结果；规则服务无效时保持空数组，调用方会安全转入交出武器分支。
	var result: Array[int] = []
	if rule_service == null or rule_service.state == null:
		return result
	# 权威查询返回的无类型数组；动态调用下不能直接当作 Array[int] 外泄，逐项转 int 后再写入结果。
	var legal_targets: Array = rule_service.list_legal_targets_for_definition(weapon_holder_id, SLASH_DEFINITION_ID, LEGAL_SLASH_TARGET_QUERY_OVERRIDES)
	for legal_target_variant: Variant in legal_targets:
		# 当前合法被【杀】者ID；转换后维持本函数的 Array[int] 返回契约。
		result.append(int(legal_target_variant))
	return result


## 要求持刀者使用【杀】；拒绝或无法响应时将其武器交给锦囊使用者。
## 补充：原文效果是“令其对你指定的另一名角色使用一张【杀】”，因此这里的【杀】属于**使用**而不是打出，
## 响应上下文声明 CARD_ACTION_USE，主体时机为 useCard；本行早期写作“打出”是动作类别修正前的旧口径。
func _resolve_borrow_sword(resolver: Object, parent_card_uid: int, source_id: int, weapon_holder_id: int, victim_id: int) -> void:
	# 借刀响应上下文；父牌 UID 使异步恢复重新定位本卡牌源码。
	# 动作类别为“使用”：持刀者被本牌要求“对合法目标使用【杀】”，这段【杀】因此必须与手动使用走同一条整牌时机链路。
	# 补充修正：原实现声明为 CARD_ACTION_PLAY（打出），控制器只派发 respond/respondEnd/respondAfter，
	# 使【生息】等订阅“使用”时机的技能对借刀【杀】完全不触发；修正后由 _get_card_action_main_timing() 派发 useCard/useCardAfter。
	# 该改动不改变这张【杀】的最终去向与弃置批次归属：实体回收统一走 _move_played_card_to_discard，
	# 该函数对 USE 与 PLAY 的处理完全同构，只把动作名写入移牌原因，因此不会把这张【杀】变成“弃置”而误触发弃置类技能。
	var response_context: Dictionary = {"kind":"borrow_sword_response", "parent_card_uid":parent_card_uid, "responder_id":weapon_holder_id, "source_id":source_id, "victim_id":victim_id, "complete_parent_target_after_response":true, "response_action":CARD_ACTION_USE}
	# 持刀者实际提供的【杀】；为空表示交出武器。
	# 补充：该【杀】按动作类别属于“使用”，因此本行旧文案“打出”仅指“提供响应牌”这一动作，不代表规则上的打出。
	# 响应询问文案与动作类别保持一致：这段【杀】是“使用”，不是“打出”。
	var slash: CardInstance = resolver.host.request_response_card(weapon_holder_id, "sha", "请响应借刀杀人并使用【杀】。", response_context)
	if resolver.host.has_pending_card_choice() or resolver.is_resolution_stopped():
		return
	_apply_borrow_sword_response(resolver, response_context, slash)


## 应用【借刀杀人】响应结果；实体【杀】复用牌族组件的完整武器、防具和伤害流程。
func _apply_borrow_sword_response(resolver: Object, context: Dictionary, slash: CardInstance) -> void:
	# 借刀使用者（来源）ID；持刀者未提供【杀】时武器本应交给该角色。
	# 补充：判据是“持刀者有没有交出一张【杀】”，与这张【杀】按“使用”还是“打出”记账无关。
	var source_id: int = int(context.get("source_id", -1))
	# 来源有效性复核；使用者在响应等待期间阵亡时本牌已经整体失效：
	# 既不能把武器交给已经阵亡的角色，也不再继续强制【杀】的后续流程。
	if resolver.effective_source_id(source_id) < 0:
		return
	# 持刀者 ID；其酒加值只在实际提供【杀】时消耗。
	var weapon_holder_id: int = int(context.get("responder_id", -1))
	if slash == null:
		resolver.host.transfer_equipment(weapon_holder_id, source_id, "weapon")
		return
	# 本次强制【杀】的已声明被【杀】者ID；声明期已固定，此处只读取，不再创建任何目标选择。
	var victim_id: int = int(context.get("victim_id", -1))
	# 真实牌目标资格复核结果；空字符串表示这张【杀】确实可以指定被【杀】者。
	# 补充：这是颜色型来牌限制（【琥珀】只拒绝黑色【杀】）唯一能生效的时机——声明期只有无色的抽象【杀】，
	# 真实颜色要等持刀者交出这张实体牌之后才可判定，与无名杀在目标选择阶段用 `game.Check.target` 复跑一致。
	# 复核入口刻意传单元素目标数组：二元组会命中 CardRuleService._validate_target 针对
	# preserves_requested_target_order() 的提前返回，使被【杀】者重新绕过全部来牌限制，正是本次修复的缺陷本身。
	var target_legality_error: String = resolver.host.card_rules.validate_entity_card_target(weapon_holder_id, slash, victim_id)
	if not target_legality_error.is_empty():
		# 复核失败：本次强制【杀】不成立，不造成伤害，也不消耗持刀者的酒加值（该【杀】并未真正使用）。
		# 按无名杀 result.bool == false 的语义回落到“持刀者将武器交给借刀杀人使用者”分支。
		# 该【杀】的实体已由响应窗口按“使用”完成消费与回收，此处不得再次移动，避免同一张牌被回收两次。
		resolver.host.add_log("借刀杀人：%s无法对%s使用%s，%s" % [resolver.host.format_player_log_name(weapon_holder_id), resolver.host.format_player_log_name(victim_id), resolver.host.format_card_log_name(slash), target_legality_error])
		resolver.host.transfer_equipment(weapon_holder_id, source_id, "weapon")
		return
	# 持刀者状态；用于读取并清空本回合下一张【杀】的酒加值。
	var weapon_holder: PlayerState = resolver.state.get_player(weapon_holder_id)
	if weapon_holder == null:
		return
	# 本次借刀【杀】消耗的酒加值；读取后立即清除公开状态，确保红色滤镜不延续到响应或伤害结算。
	var consumed_wine_bonus: int = weapon_holder.wine_bonus
	# 本次借刀【杀】伤害基数；固定基础1点并叠加一次酒加值。
	var damage_amount: int = 1 + consumed_wine_bonus
	weapon_holder.wine_bonus = 0
	if consumed_wine_bonus > 0:
		resolver.host.refresh_public_state_snapshot()
	# 持刀者当前武器定义；借刀【杀】同样读取武器源码决定是否忽略防具。
	var weapon_definition: CardDefinition = resolver.host.get_equipment_definition(weapon_holder_id, "weapon")
	SlashCardEffect.new(resolver).resolve_external_target(slash, weapon_holder_id, int(context.get("victim_id", -1)), damage_amount, str(GameDatabase.get_card(slash.definition_id).get("nature", "normal")), weapon_definition != null and weapon_definition.slash_ignores_armor(), int(context.get("parent_card_uid", -1)))


## 恢复持刀者的【杀】响应；响应牌已由控制器完成消费和模式校验。
func continue_response(resolver: Object, context: Dictionary, response_card: CardInstance) -> bool:
	# 响应用途；借刀初始出杀由本文件处理，随后产生的【闪】和武器响应委托【杀】牌族组件。
	var response_kind: String = str(context.get("kind", ""))
	if response_kind == "borrow_sword_response":
		_apply_borrow_sword_response(resolver, context, response_card)
		return true
	return SlashCardEffect.new(resolver).continue_response(context, response_card)


## 恢复借刀【杀】内部武器创建的普通选牌请求。
func continue_choice(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	return SlashCardEffect.new(resolver).continue_choice(context, selected_uids)
