extends SkillDefinition

## 【山倾】技能源码。持有者每回合可将两张自有牌组成按材料花色与颜色聚合的【杀】，并按材料花色集合获得四项独立效果。

## 山倾生成的虚拟牌定义 ID；固定使用普通【杀】，伤害属性为 normal。
const SLASH_DEFINITION_ID: String = "sha"

## 山倾每次必须消耗的实体材料数量；固定为2，与技能原文一致。
const MATERIAL_COUNT: int = 2

## 四种实体花色的稳定顺序；用于去重、存储、日志与 AI 计算，修改顺序只影响展示确定性。
const SUIT_ORDER: Array[String] = ["heart", "diamond", "spade", "club"]

## AI 计算两张材料保留成本时使用的权重；数值越高越倾向保留桃、闪和关键装备。
const AI_MATERIAL_COST_WEIGHT: float = 0.45

## 方块花色在使用山倾【杀】时固定摸牌数；固定为1，与技能原文一致，运行时无需动态修改。
const DIAMOND_DRAW_COUNT: int = 1

## 梅花花色对每名目标固定弃置的区域牌数量；固定为1，多张梅花材料不会增加该数量。
const CLUB_DISCARD_COUNT: int = 1

## AI 对红桃效果采用的基础预期回复量；普通【杀】基准造成1点伤害，实际结算仍按最终伤害等量回复。
const AI_EXPECTED_HEART_RECOVERY: int = 1

## AI 对梅花稳定弃置1张目标区域牌的基础控制价值；仅在目标确有区域牌时按阵营方向计入。
const AI_CLUB_DISCARD_VALUE: float = 1.5

## 项目身份态度绝对值的标准满量程；用于把敌友态度规范化后乘梅花控制价值。
const AI_ATTITUDE_FULL_SCALE: float = 5.0

## 山倾【杀】公开身份观察中的单目标负面强度；只影响身份推断，不改变伤害或弃牌数值。
const AI_IDENTITY_TARGET_RESULT: float = -1.5

## 当前额度对应的全局回合号；默认-1表示尚未同步，额外出牌阶段不会改变该编号。
var _tracked_turn_number: int = -1

## 当前全局回合是否已经成功使用山倾；只有虚拟【杀】通过最终校验并进入使用流程后才设为 true。
var _used_this_turn: bool = false


## 写入主动技能静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"shanqing",
		"name":"山倾",
		"trigger":"active",
		"enable":["phaseUse"],
		"ui_enabled":true,
		"description":"你可将两张牌当【杀】使用，这些牌中的每种花色使此【杀】获得对应效果：红桃，造成伤害后回复等量的体力值；方块，使用时你摸一张牌；黑桃，此【杀】无距离限制；梅花，使用时你弃置目标的一张牌。每回合限一次。",
	})


## 订阅方块摸牌、梅花弃牌与红桃回复三个规则时机；黑桃距离效果在目标枚举与最终使用校验时生效。
func install() -> void:
	subscribe_timing("useCard", _on_shanqing_used, "source")
	subscribe_timing("useCardToTargeted", _on_shanqing_targeted, "source")
	subscribe_timing("damageSource", _on_shanqing_damage_source, "source")


## 仅在自己的出牌阶段、回合额度未用、至少有两张材料且存在完整合法材料目标组合时开放按钮。
func can_activate(_context: Dictionary = {}) -> bool:
	_sync_turn_state()
	if host == null or _used_this_turn or host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 当前全部自有材料；包含手牌、木牛“粮”与装备区，符合“牌”的通用项目语义。
	var candidates: Array[Dictionary] = _get_material_candidates()
	if candidates.size() < MATERIAL_COUNT:
		return false
	for first_index: int in range(candidates.size() - 1):
		for second_index: int in range(first_index + 1, candidates.size()):
			# 当前材料组合 UID；目标枚举会根据是否含黑桃立即应用无距离限制。
			var material_uids: Array[int] = [int(candidates[first_index].get("uid", -1)), int(candidates[second_index].get("uid", -1))]
			if not _list_legal_targets(material_uids).is_empty():
				return true
	return false


## 发动山倾；AI动作可直接携带两张材料和目标，玩家按钮先选两张牌再按已选花色枚举目标。
func activate(context: Dictionary = {}) -> String:
	_sync_turn_state()
	# 动作指定的两张材料；空数组表示玩家尚未完成第一步选牌。
	var material_uids: Array[int] = _int_values(context.get("material_card_uids", []) as Array)
	# 动作指定的目标；普通山倾【杀】要求恰好一名其他角色。
	var target_ids: Array[int] = _int_values(context.get("target_ids", []) as Array)
	if material_uids.size() == MATERIAL_COUNT and target_ids.size() == 1:
		return "" if _execute_shanqing(material_uids, target_ids) else "【山倾】材料或目标已不合法。"
	# 第一阶段材料候选；只有当前仍归持有者所有的牌进入权威选择窗口。
	var candidates: Array[Dictionary] = _get_material_candidates()
	if candidates.size() < MATERIAL_COUNT:
		return "当前没有足够的两张牌发动【山倾】。"
	# 复合材料选择数据；只把至少存在一个合法目标的两牌组合放入权威合法集合。
	var selection_data: Dictionary = _build_material_selection_data(candidates)
	# 当前目标并集；材料尚未完成前先展示所有可行组合的目标，选牌完成后仍由控制器与技能入口复核具体组合。
	var legal_target_ids: Array[int] = selection_data.get("target_ids", []) as Array[int]
	if legal_target_ids.is_empty():
		return "当前没有可用的两张牌或【杀】目标。"
	# 同一 card_target 请求同时承载两张材料与一名目标，避免先关掉选牌窗口再打开独立目标窗口。
	request_card_target_selection("山倾", "请选择两张牌和一名【杀】目标", candidates, legal_target_ids, MATERIAL_COUNT, MATERIAL_COUNT, 1, 1, true, {
		"kind":"shanqing_materials",
		"valid_card_combinations":selection_data.get("valid_card_combinations", []),
		"target_combinations_by_card_combination":selection_data.get("target_combinations_by_card_combination", {}),
	})
	return ""


## 恢复材料、目标或梅花弃牌选择；每一步都按最新区域和目标状态再次复核。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；三个步骤分别保存两张材料、单一目标或目标区域牌 UID。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "shanqing_materials":
		# 复合请求一次返回两张材料与一名目标；取消或数量不完整时不消耗额度，也不创建第二个目标窗口。
		if response.confirmed and response.card_ids.size() == MATERIAL_COUNT and response.target_ids.size() == 1:
			_execute_shanqing(_int_values(response.card_ids), _int_values(response.target_ids))
		return true
	if choice_kind == "shanqing_target":
		if response.confirmed and response.target_ids.size() == 1:
			_execute_shanqing(_int_values(context.get("material_card_uids", []) as Array), response.target_ids)
		return true
	if choice_kind == "shanqing_club_discard":
		if response.confirmed and response.card_ids.size() == 1:
			host.call("discard_selected_player_cards", int(context.get("target_id", -1)), response.card_ids, owner_player_id)
		return true
	return false


## 根据已选两张材料的真实花色列出虚拟【杀】目标；黑桃无距离限制在本目标窗口创建前即生效。
func _request_target_for_materials(material_uids: Array[int]) -> void:
	# 当前合法目标；材料等待期间失效或不存在目标时本次发动安全结束且不消耗额度。
	var target_ids: Array[int] = _list_legal_targets(material_uids)
	if target_ids.is_empty():
		return
	request_target_selection("【山倾】请选择【杀】的目标", target_ids, 1, 1, true, {"kind":"shanqing_target", "material_card_uids":material_uids.duplicate()})


## 权威复核两张材料、花色集合、目标与回合额度，成功后通过统一多材料虚拟牌入口使用【杀】。
func _execute_shanqing(material_uids: Array[int], target_ids: Array[int]) -> bool:
	_sync_turn_state()
	if _used_this_turn or material_uids.size() != MATERIAL_COUNT or material_uids[0] == material_uids[1] or target_ids.size() != 1:
		return false
	# 当前材料实体；必须仍归持有者所有，且两张牌在移动前全部存在。
	var material_cards: Array[CardInstance] = _get_material_cards(material_uids)
	if material_cards.size() != MATERIAL_COUNT:
		return false
	# 去重后的花色集合；同花色多张材料只产生一次对应效果。
	var suits: Array[String] = _get_unique_suits(material_cards)
	# 虚拟牌规则覆写；黑桃材料使目标阶段和最终提交都忽略距离，颜色按两张材料聚合。
	var rule_overrides: Dictionary = _build_rule_overrides(material_cards, suits)
	if str(host.card_rules.validate_virtual_use(owner_player_id, SLASH_DEFINITION_ID, target_ids, rule_overrides)) != "":
		return false
	# 逻辑牌扩展存储；后续 useCard、目标与 damageSource 时机只读取该纯数据快照。
	var virtual_storage: Dictionary = {"source_skill_id":get_id(), "suits":suits.duplicate()}
	if not bool(host.call("execute_virtual_card_use", owner_player_id, SLASH_DEFINITION_ID, material_uids, target_ids, "", rule_overrides, virtual_storage)):
		return false
	_used_this_turn = true
	announce_activation({"material_card_uids":material_uids.duplicate(), "target_ids":target_ids.duplicate(), "suits":suits.duplicate(), "virtual_card_id":SLASH_DEFINITION_ID})
	observe_identity_behavior(target_ids, {"target_result":AI_IDENTITY_TARGET_RESULT, "damage":true, "respond_shan":true})
	return true


## 方块效果：山倾虚拟【杀】进入 useCard 时持有者固定摸1张牌；同花色已在存储阶段去重。
func _on_shanqing_used(event: RuleEvent) -> void:
	if not _is_shanqing_event(event) or not _event_suits(event).has("diamond"):
		return
	host.call("draw", owner_player_id, DIAMOND_DRAW_COUNT)


## 梅花效果：每名实际目标在 useCardToTargeted 时由持有者选择并弃置其区域内一张当前可弃牌。
func _on_shanqing_targeted(event: RuleEvent) -> void:
	if not _is_shanqing_event(event) or not _event_suits(event).has("club"):
		return
	# 当前目标区域候选；手牌保持牌背，装备与判定牌公开，保护技能在候选与提交阶段各复核一次。
	var candidates: Array[Dictionary] = host.call("get_opportunity_discard_candidates", owner_player_id, event.target_id) as Array[Dictionary]
	if candidates.is_empty():
		return
	request_card_selection("山倾", "请选择弃置目标区域内的一张牌", candidates, CLUB_DISCARD_COUNT, CLUB_DISCARD_COUNT, false, {"kind":"shanqing_club_discard", "target_id":event.target_id, "parent_card_uid":int(event.data.get("card_uid", -1))})


## 红桃效果：山倾【杀】每次完成正数伤害后，持有者回复与该次最终伤害值相同的体力。
func _on_shanqing_damage_source(event: RuleEvent) -> void:
	if not _is_shanqing_event(event) or not _event_suits(event).has("heart"):
		return
	# 本次最终伤害值；包含酒、剑势、防具与伤害修改时机的最终结果，至少为1才产生回复。
	var damage_amount: int = int(event.data.get("amount", 0))
	if damage_amount > 0:
		host.call("recover", owner_player_id, owner_player_id, damage_amount, get_id())


## 判断规则时机是否来自本技能创建的逻辑【杀】；普通实体【杀】与其他转化技能不会误触发花色效果。
func _is_shanqing_event(event: RuleEvent) -> bool:
	if event == null or event.source_id != owner_player_id:
		return false
	# 虚拟扩展存储；稳定 source_skill_id 是山倾效果的唯一归属标记。
	var virtual_storage: Dictionary = event.data.get("virtual_storage", {}) as Dictionary
	return str(virtual_storage.get("source_skill_id", "")) == get_id()


## 从规则事件读取已去重的四花色数组；异常值会被过滤，避免伪造花色触发额外效果。
func _event_suits(event: RuleEvent) -> Array[String]:
	# 事件扩展存储；由虚拟牌使用入口从山倾发动时的快照传递。
	var virtual_storage: Dictionary = event.data.get("virtual_storage", {}) as Dictionary
	# 有效花色结果；顺序固定为技能文本顺序，重复值只保留一次。
	var result: Array[String] = []
	for suit: String in SUIT_ORDER:
		if (virtual_storage.get("suits", []) as Array).has(suit):
			result.append(suit)
	return result


## 返回技能持有者当前全部自有材料候选；手牌、木牛“粮”和装备均可作为“两张牌”。
func _get_material_candidates() -> Array[Dictionary]:
	return host.call("get_skill_material_candidates", owner_player_id) as Array[Dictionary]


## 按 UID 顺序取得两张仍归持有者所有的实体材料；任一缺失时返回不完整数组交由调用方拒绝。
func _get_material_cards(material_uids: Array[int]) -> Array[CardInstance]:
	# 实体材料结果；顺序与玩家选择或 AI 动作保持一致，用于稳定移动历史。
	var result: Array[CardInstance] = []
	for material_uid: int in material_uids:
		# 当前实体材料；基类查询支持手牌、木牛“粮”与装备区。
		var material_card: CardInstance = get_owned_conversion_material_card(material_uid)
		if material_card == null:
			return result
		result.append(material_card)
	return result


## 从两张材料生成稳定去重花色集合；无花色异常牌不会触发任何额外效果，但仍可作为普通材料。
func _get_unique_suits(material_cards: Array[CardInstance]) -> Array[String]:
	# 去重花色结果；固定顺序保证网络、回放与技能提示一致。
	var result: Array[String] = []
	for suit: String in SUIT_ORDER:
		for material_card: CardInstance in material_cards:
			if material_card.suit == suit:
				result.append(suit)
				break
	return result


## 构造山倾虚拟【杀】的规则覆写；黑桃存在时开启无距离限制，颜色按两张材料聚合。
## 两张同花色材料视为该花色，同色不同花色材料视为该颜色无花色，异色材料视为无色；
## 因此两张黑色牌（黑桃或梅花任意组合）转化的【杀】都会以 black 走通用来牌目标过滤。
func _build_rule_overrides(material_cards: Array[CardInstance], suits: Array[String]) -> Dictionary:
	return host.card_rules.build_material_rule_overrides(material_cards, {"ignore_distance_limit":suits.has("spade")})


## 返回指定两张材料能够合法指定的全部【杀】目标；黑桃距离覆写与聚合颜色在目标枚举时立即参与计算。
func _list_legal_targets(material_uids: Array[int]) -> Array[int]:
	# 当前两张材料；全部存在后才能读取真实花色构建规则覆写。
	var material_cards: Array[CardInstance] = _get_material_cards(material_uids)
	if material_cards.size() != MATERIAL_COUNT:
		return []
	# 去重花色集合；用于黑桃无距离目标枚举。
	var suits: Array[String] = _get_unique_suits(material_cards)
	return host.card_rules.list_legal_virtual_targets(owner_player_id, SLASH_DEFINITION_ID, _build_rule_overrides(material_cards, suits)) as Array[int]


## 枚举山倾复合选择窗口的合法材料组合、目标并集和材料组合专属目标映射。
## 目标映射使用规范化UID键，供界面在已选材料变化时即时收窄目标，也供控制器复核AI与网络提交。
func _build_material_selection_data(candidates: Array[Dictionary]) -> Dictionary:
	# 所有至少拥有一个合法目标的两牌组合；界面用它限制材料前缀，防止选到必然失败的组合。
	var valid_card_combinations: Array = []
	# 所有合法材料组合目标的并集；尚未选完材料时用于保持目标区可操作。
	var target_ids: Array[int] = []
	# 规范化材料组合键到完整目标组合数组；每个山倾目标是一名角色，因此值形如[[target_id], ...]。
	var target_combinations_by_card_combination: Dictionary = {}
	for first_index: int in range(candidates.size() - 1):
		for second_index: int in range(first_index + 1, candidates.size()):
			# 当前两张材料UID；组合顺序只用于稳定候选顺序，规则语义按无序材料集合处理。
			var material_uids: Array[int] = [int(candidates[first_index].get("uid", -1)), int(candidates[second_index].get("uid", -1))]
			# 当前组合的真实合法目标；黑桃无距离等花色覆写在此查询时已经生效。
			var combination_target_ids: Array[int] = _list_legal_targets(material_uids)
			if combination_target_ids.is_empty():
				continue
			valid_card_combinations.append(material_uids.duplicate())
			# 当前组合的有序目标组合；控制器可直接生成完整 ChoiceResponse 动作并再次校验。
			var target_combinations: Array = []
			for target_id: int in combination_target_ids:
				target_combinations.append([target_id])
				if not target_ids.has(target_id):
					target_ids.append(target_id)
			target_combinations_by_card_combination[_make_material_combination_key(material_uids)] = target_combinations
	return {
		"target_ids":target_ids,
		"valid_card_combinations":valid_card_combinations,
		"target_combinations_by_card_combination":target_combinations_by_card_combination,
	}


## 将两张材料UID规范化为稳定组合键；排序只影响选择协议查找，不改变材料实体顺序记录。
func _make_material_combination_key(material_uids: Array[int]) -> String:
	# 排序后的UID副本；不改写玩家点击顺序或最终移动历史。
	var normalized_uids: Array[int] = material_uids.duplicate()
	normalized_uids.sort()
	# 字符串键；网络序列化字典后仍能用同一格式读取。
	var key_parts: Array[String] = []
	for material_uid: int in normalized_uids:
		key_parts.append(str(material_uid))
	return ",".join(key_parts)


## 全局回合号变化时恢复一次发动额度；同一回合内的额外出牌阶段继续共享已使用状态。
func _sync_turn_state() -> void:
	if host == null or host.state == null or _tracked_turn_number == host.state.turn_number:
		return
	_tracked_turn_number = host.state.turn_number
	_used_this_turn = false


## 向 AI 合法动作列表追加每组两张材料与其当前合法目标；目标已包含黑桃无距离规则。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	# 当前全部材料候选；每个无序二元组合只枚举一次。
	var candidates: Array[Dictionary] = _get_material_candidates()
	for first_index: int in range(candidates.size() - 1):
		for second_index: int in range(first_index + 1, candidates.size()):
			# 当前两张材料 UID；动作负载保留稳定选择顺序。
			var material_uids: Array[int] = [int(candidates[first_index].get("uid", -1)), int(candidates[second_index].get("uid", -1))]
			for target_id: int in _list_legal_targets(material_uids):
				# 当前单目标动作；最终提交仍会复核材料归属、花色、次数与目标合法性。
				var target_ids: Array[int] = [target_id]
				result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":target_ids.duplicate(), "payload":{"skill_id":get_id(), "material_card_uids":material_uids.duplicate(), "target_ids":target_ids.duplicate()}})


## 评估山倾主动动作；复用普通【杀】收益，叠加花色效果预期并扣除两张材料的保留价值。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载；包含两张材料 UID 与单一目标。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 两张材料 UID；用于读取真实牌值与花色。
	var material_uids: Array[int] = _int_values(payload.get("material_card_uids", []) as Array)
	# 虚拟普通【杀】动作；通用评估器负责目标态度、闪响应、防具和伤害价值。
	var slash_action: Dictionary = build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
	# 山倾基础收益；后续 BasicAIPolicy 还会补入持有者其他技能对该虚拟【杀】的联动差额。
	var score: float = evaluator.score_action(authoritative_snapshot, slash_action, owner_player_id)
	# 材料花色集合；从 AI 私有权威快照读取，避免依赖运行时 host 实体。
	var suits: Array[String] = _get_snapshot_material_suits(authoritative_snapshot, material_uids, evaluator)
	# 动作目标；梅花弃牌估值需要结合目标阵营与区域牌数量。
	var target_ids: Array[int] = _int_values(action.get("target_ids", payload.get("target_ids", [])) as Array)
	if suits.has("diamond"):
		score += evaluator.score_resource_change(authoritative_snapshot, owner_player_id, owner_player_id, DIAMOND_DRAW_COUNT, 0)
	if suits.has("heart"):
		score += evaluator.score_resource_change(authoritative_snapshot, owner_player_id, owner_player_id, 0, AI_EXPECTED_HEART_RECOVERY)
	if suits.has("club") and not target_ids.is_empty():
		# 当前目标快照；区域牌越多，梅花稳定弃置一张牌的预期控制收益越高。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_ids[0])
		# 目标区域牌数量；手牌、装备与判定区都可被山倾梅花效果选择。
		var target_zone_card_count: int = int(target.get("hand_count", 0)) + int((target.get("equipment", {}) as Dictionary).size()) + int((target.get("judgment_area", []) as Array).size())
		if target_zone_card_count > 0:
			score += -evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_ids[0]) / AI_ATTITUDE_FULL_SCALE * AI_CLUB_DISCARD_VALUE
	for material_uid: int in material_uids:
		score -= evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, material_uid) * AI_MATERIAL_COST_WEIGHT
	return score


## 构造山倾实际生成的普通【杀】代理动作；基础 AI 会继续应用卡牌本体和持有者其他技能的完整评分链。
func build_ai_virtual_card_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> Dictionary:
	# 动作负载；标准主动动作把目标同时保存于顶层与 payload。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 两张材料 UID；用于按 AI 私有权威快照推导本次虚拟【杀】的聚合颜色。
	var material_uids: Array[int] = _int_values(payload.get("material_card_uids", []) as Array)
	# 本次虚拟【杀】聚合颜色；黑色材料转化让通用评估器按黑色【杀】预判【琥珀】与颜色型防具。
	var card_color: String = str(VirtualCard.resolve_suit_aggregate(_get_snapshot_material_raw_suits(authoritative_snapshot, material_uids, evaluator)).get("color", "none"))
	return {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":SLASH_DEFINITION_ID, "card_color":card_color, "target_ids":(action.get("target_ids", payload.get("target_ids", [])) as Array).duplicate()}


## 梅花弃牌选择优先目标区域内价值最高的牌；其他山倾步骤由直接 AI 动作或唯一合法目标处理。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只对梅花目标区域弃牌步骤追加专属评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "shanqing_club_discard":
		return 0.0
	# 选择负载；强制选择应恰好包含一张候选牌。
	var selected_cards: Array = (action.get("payload", {}) as Dictionary).get("selected_card_uids", []) as Array
	if selected_cards.size() != 1:
		return -100.0
	# 梅花弃牌目标；敌方选择最高价值牌，友方若因其他收益成为目标则选择最低价值牌减少损失。
	var target_id: int = int(context.get("target_id", -1))
	# 所选区域牌对目标的保留价值；与身份态度相乘后转换为技能持有者视角收益。
	var selected_card_value: float = evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), target_id)
	return -evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) / AI_ATTITUDE_FULL_SCALE * selected_card_value


## 从 AI 权威快照读取两张材料的去重花色；找不到的 UID 不猜测花色。
func _get_snapshot_material_suits(authoritative_snapshot: Dictionary, material_uids: Array[int], evaluator: Object) -> Array[String]:
	# 花色结果；按技能文本顺序稳定输出。
	var result: Array[String] = []
	for material_uid: int in material_uids:
		# 当前自有牌快照；评估器支持手牌、木牛“粮”与装备材料。
		var card: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, owner_player_id, material_uid)
		# 当前实体花色；重复或无效花色不会进入结果。
		var suit: String = str(card.get("suit", "none"))
		if suit in SUIT_ORDER and not result.has(suit):
			result.append(suit)
	# 按 SUIT_ORDER 重排；材料点击顺序不会改变 AI 对相同花色集合的判断。
	var ordered_result: Array[String] = []
	for suit: String in SUIT_ORDER:
		if result.has(suit):
			ordered_result.append(suit)
	return ordered_result


## 从 AI 权威快照读取两张材料的原始花色序列；保持材料顺序并保留无效花色，用于颜色聚合。
func _get_snapshot_material_raw_suits(authoritative_snapshot: Dictionary, material_uids: Array[int], evaluator: Object) -> Array[String]:
	# 原始花色结果；顺序与材料选择一致，无效花色交由聚合函数按无色处理。
	var result: Array[String] = []
	for material_uid: int in material_uids:
		# 当前自有牌快照；评估器支持手牌、木牛“粮”与装备材料。
		var card: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, owner_player_id, material_uid)
		result.append(str(card.get("suit", "none")))
	return result


## 将弱类型数组转换为稳定整数数组；网络、AI 与本地选择统一使用相同转换规则。
func _int_values(values: Array) -> Array[int]:
	# 转换结果；保持原数组顺序，不执行排序或去重。
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result
