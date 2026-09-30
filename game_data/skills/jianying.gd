extends SkillDefinition

## 【鉴映】技能源码。出牌阶段限一次：先展示自己的一张手牌A，再展示一名有护盾角色的一张手牌B，
## 若B不是装备牌，则A连同牌名、花色与点数一起视为B，直到A离开技能持有者手牌区。
## 三个选择严格按顺序进行，不合并展示；A已展示后不再提供取消，避免已经公开的牌出现半途撤销。

## A 与 B 每次固定选择的实体牌数量；两段展示各自独立选1张。
const CARD_SELECT_COUNT: int = 1

## 第二段固定选择的角色数量；原文“一名有护盾的角色”即恰好一名。
const TARGET_SELECT_COUNT: int = 1

## 目标角色必须拥有的最低护盾值；原文要求“一名有护盾的角色”，因此护盾为0的角色不是合法目标。
const MIN_SHIELD_FOR_TARGET: int = 1

## A 选择窗口是否允许取消；固定true，未确认前取消不消耗本阶段次数、也不展示任何牌。
const ALLOW_CANCEL_MATERIAL: bool = true

## A 展示之后的两个窗口是否允许取消；固定false，已经公开的A不能被撤销。
const ALLOW_CANCEL_AFTER_REVEAL: bool = false

## 不能作为视为对象的牌类型；原文明确“若B不为装备牌”，因此装备牌只展示不建立视为。
const EQUIPMENT_CARD_TYPE: String = "equipment"

## A 选择请求种类；同时作为该步骤的AI评分标识。
const CARD_CHOICE_KIND_MATERIAL: String = "jianying_material"

## 有护盾角色选择请求种类；同时作为该步骤的AI评分标识。
const TARGET_CHOICE_KIND: String = "jianying_shield_target"

## B 选择请求种类；同时作为该步骤的AI评分标识。
const CARD_CHOICE_KIND_REVEAL: String = "jianying_revealed_card"

## AI：自身有护盾时发动的基础价值；此时可以把确定的最低价值手牌换成确定的最高价值手牌。
const AI_SELF_UPGRADE_TARGET_VALUE: float = 3.0

## AI：自身没有护盾、只能从他人不可见手牌中抽取B时的基础价值；收益不确定，因此明显低于自身升级。
const AI_HOSTILE_TARGET_VALUE: float = 1.2

## AI：友方目标的基础价值；只展示队友一张手牌，收益最低。
const AI_FRIENDLY_TARGET_VALUE: float = 0.2

## AI：材料保留价值的成本倍率；与既有转化技能一致，优先使用低价值手牌。
const AI_MATERIAL_COST_MULTIPLIER: float = 0.3

## AI：判定“手牌中存在明显高低价值差”的阈值；达到该差值才认为自身升级确实成立。
const AI_VALUE_GAP_THRESHOLD: float = 2.0

## AI：B 与 A 是同一张实体牌时的拒绝分；视为自己没有意义，AI不应主动选择。
const AI_SELF_CARD_PENALTY: float = 6.0

## AI：向他人展示手牌属于信息外泄，身份行为观察取轻微负值；不改变任何规则状态。
const AI_REVEAL_TARGET_RESULT: float = -0.4

## 本出牌阶段是否已经发动鉴映；普通与额外出牌阶段分别拥有独立的一次额度。
var _used_this_play_phase: bool = false

## 本次发动已经展示的手牌A的实体UID；负数表示尚未展示，用于禁止A之后的取消与自我视为。
var _revealed_material_uid: int = -1

## 本次发动已经展示的手牌A的稳定牌名；只用于日志与自校验，不参与规则判定。
var _revealed_material_definition_id: String = ""


## 写入技能静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"jianying",
		"name":"鉴映",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"description":"出牌阶段限一次，你可以展示你的一张手牌A，然后展示一名有护盾的角色的一张手牌B，若B不为装备牌，则A视为B直到离开你的手牌区。",
	})


## 订阅出牌阶段开始时机；额外出牌阶段同样拥有独立的一次发动额度。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player")


## 新出牌阶段开始时恢复本阶段发动次数与本次发动缓存。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false
	_revealed_material_uid = -1
	_revealed_material_definition_id = ""


## 判断当前是否可以发动：自己的出牌阶段、本阶段未发动、有手牌，且场上存在有护盾且有手牌的角色。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；主动技能只允许在自己的出牌阶段发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and not _used_this_play_phase \
		and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" \
		and not owner.hand.is_empty() and not _get_available_target_ids().is_empty()


## 发动鉴映；直接动作同时携带材料、目标与目标手牌时立即复核，否则展开严格顺序的三段选择。
func activate(context: Dictionary = {}) -> String:
	if not can_activate():
		return "当前无法发动【鉴映】。"
	# 直接动作材料UID；负数表示需要打开交互选择。
	var direct_material_uid: int = int(context.get("card_uid", context.get("material_card_uid", -1)))
	# 直接动作目标；本技能固定一名角色。
	var direct_target_ids: Array = context.get("target_ids", []) as Array
	# 直接动作的目标手牌UID；负数表示需要打开交互选择。
	var direct_revealed_uid: int = int(context.get("revealed_card_uid", -1))
	if direct_material_uid >= 0 and direct_target_ids.size() == TARGET_SELECT_COUNT and direct_revealed_uid >= 0:
		if _execute_jianying(direct_material_uid, int(direct_target_ids[0]), direct_revealed_uid):
			return ""
		return "【鉴映】所选牌或目标已经失效。"
	run_steps([_choose_material, _reveal_material, _choose_shield_target, _choose_revealed_card, _apply_view_as], {})
	return ""


## 第一步：选择自己的一张手牌A；未确认前可以取消，取消不消耗本阶段次数。
func _choose_material(sequence: RuleStepSequence) -> void:
	request_step_cards(sequence, "鉴映", "请选择你的一张手牌A", _get_owner_hand_candidates(), CARD_SELECT_COUNT, CARD_SELECT_COUNT, ALLOW_CANCEL_MATERIAL, {"kind":CARD_CHOICE_KIND_MATERIAL})


## 第二步：确认后立即公开展示A并消费本阶段次数；取消或牌已失效则技能直接结束。
func _reveal_material(sequence: RuleStepSequence) -> void:
	# 第一步选择结果；取消表示本次不发动技能。
	var response: ChoiceResponse = sequence.choice_response
	if response == null or not response.confirmed or response.card_ids.size() != CARD_SELECT_COUNT:
		sequence.finish()
		return
	# 所选材料实体；必须仍是技能持有者的普通手牌，等待期间已移动的牌不能继续展示。
	var material_card: CardInstance = _find_hand_card(owner_player_id, response.card_ids[0])
	if material_card == null:
		sequence.finish()
		return
	# 次数在A确认展示时消费；此后两步不可取消，费用不返还。
	_used_this_play_phase = true
	_revealed_material_uid = material_card.uid
	_revealed_material_definition_id = material_card.definition_id
	sequence.context["material_uid"] = material_card.uid
	if host.call("reveal_hand_card", owner_player_id, material_card.uid, get_id()) == null:
		sequence.finish()


## 第三步：选择一名有护盾且有普通手牌的角色；已经展示A，因此该窗口不可取消。
func _choose_shield_target(sequence: RuleStepSequence) -> void:
	# 合法来源角色；必须有护盾且至少有一张普通手牌，包含技能持有者本人。
	var candidate_target_ids: Array[int] = _get_available_target_ids()
	if candidate_target_ids.is_empty():
		# 等待期间已经没有合法角色：本次技能以“展示A但不建立视为”收尾，次数已经消费。
		sequence.finish()
		return
	request_step_targets(sequence, "【鉴映】请选择一名有护盾且有手牌的角色", candidate_target_ids, TARGET_SELECT_COUNT, TARGET_SELECT_COUNT, ALLOW_CANCEL_AFTER_REVEAL, {"kind":TARGET_CHOICE_KIND})


## 第四步：由技能持有者从所选角色的手牌中选择B；目标不是自己时候选按观察者裁剪为不可见牌面。
func _choose_revealed_card(sequence: RuleStepSequence) -> void:
	# 目标选择结果；结构异常或目标已经失效时直接收尾，不建立视为。
	var response: ChoiceResponse = sequence.choice_response
	if response == null or response.target_ids.size() != TARGET_SELECT_COUNT:
		sequence.finish()
		return
	# 已选角色ID；必须仍然满足“有护盾且有手牌”。
	var target_id: int = response.target_ids[0]
	if not _get_available_target_ids().has(target_id):
		sequence.finish()
		return
	sequence.context["revealed_target_id"] = target_id
	# 候选手牌；视角固定为技能持有者，因此他人手牌只会下发不可见牌面，避免泄漏隐私信息。
	var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, target_id) as Array[Dictionary]
	if candidates.is_empty():
		sequence.finish()
		return
	request_step_cards(sequence, "鉴映", "请选择该角色的一张手牌B", candidates, CARD_SELECT_COUNT, CARD_SELECT_COUNT, ALLOW_CANCEL_AFTER_REVEAL, {"kind":CARD_CHOICE_KIND_REVEAL, "target_id":target_id})


## 第五步：展示B并建立视为；B是装备牌、或B就是A本体时只展示不建立视为。
func _apply_view_as(sequence: RuleStepSequence) -> void:
	# B选择结果；结构异常时直接收尾，A已经展示的事实保持不变。
	var response: ChoiceResponse = sequence.choice_response
	if response == null or not response.confirmed or response.card_ids.size() != CARD_SELECT_COUNT:
		sequence.finish()
		return
	_execute_jianying(int(sequence.context.get("material_uid", -1)), int(sequence.context.get("revealed_target_id", -1)), response.card_ids[0])


## 结算最后一段：公开展示B，并在B不是装备牌时令A连同花色点数一起视为B。
func _execute_jianying(material_uid: int, target_id: int, revealed_card_uid: int) -> bool:
	# 材料牌；必须仍是技能持有者的普通手牌，否则本次不建立视为。
	var material_card: CardInstance = _find_hand_card(owner_player_id, material_uid)
	if material_card == null:
		return false
	# 来源角色合法性复核；等待期间失去护盾或手牌的角色的牌不再展示。
	if not _get_available_target_ids().has(target_id):
		return false
	# 目标手牌实体；必须是该角色普通手牌区中的牌。
	var revealed_card: CardInstance = _find_hand_card(target_id, revealed_card_uid)
	if revealed_card == null:
		return false
	if host.call("reveal_hand_card", target_id, revealed_card_uid, get_id()) == null:
		return false
	# B的静态定义；只读取类型判断是否为装备牌。
	var revealed_definition: Dictionary = GameDatabase.get_card(revealed_card.definition_id)
	# 是否建立视为；装备牌按原文排除，B与A是同一张实体牌时“视为自己”没有任何变化，同样跳过。
	var can_view_as: bool = str(revealed_definition.get("type", "")) != EQUIPMENT_CARD_TYPE and revealed_card_uid != material_uid
	# 视为写入结果；花色与点数来自B的实体牌面，写入后所有既有规则读取点都会读到逻辑牌面。
	var applied_view_as: bool = can_view_as and bool(host.call("set_hand_card_view_as_with_face", owner_player_id, material_uid, revealed_card.definition_id, revealed_card.suit, revealed_card.rank, get_id()))
	announce_activation({
		"card_uid":material_uid,
		"target_id":target_id,
		"revealed_card_uid":revealed_card_uid,
		"view_as_definition_id":revealed_card.definition_id if applied_view_as else "",
		"view_as_suit":revealed_card.suit if applied_view_as else "",
		"view_as_rank":revealed_card.rank if applied_view_as else 0,
	})
	if target_id != owner_player_id:
		observe_identity_behavior([target_id], {"target_result":AI_REVEAL_TARGET_RESULT})
	return true


## 返回技能持有者当前全部普通手牌候选；本人视角下牌面完整可见。
func _get_owner_hand_candidates() -> Array[Dictionary]:
	return host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]


## 按UID查找指定角色的普通手牌实体；不包含装备区与木牛“粮”。
func _find_hand_card(player_id: int, card_uid: int) -> CardInstance:
	# 持有者权威状态；无效ID没有合法实体。
	var player: PlayerState = host.state.get_player(player_id) if host != null and host.get("state") != null else null
	return player.find_hand_card(card_uid) if player != null else null


## 返回当前可作为B来源的角色ID；必须存活在场、护盾不少于下限且至少持有一张普通手牌。
func _get_available_target_ids() -> Array[int]:
	# 目标结果；保持权威座次顺序，界面、AI与回放据此稳定复现。
	var result: Array[int] = []
	if host == null or host.get("state") == null:
		return result
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game and player.shield >= MIN_SHIELD_FOR_TARGET and not player.hand.is_empty():
			result.append(player.player_id)
	return result


## 为AI追加主动发动动作；条件成立时才提供入口，具体材料与目标由后续选择步骤评分。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[], "payload":{"skill_id":get_id()}})


## 评估鉴映的主动发动；自身有护盾时收益确定，之后扣除最低价值手牌的材料机会成本。
## 本函数在AI评估期间不持有host，因此只读取权威快照与估值接口。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	if str(action.get("action_type", "")) != "use_skill":
		return 0.0
	# 技能持有者快照；用于读取自身护盾与手牌。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	# 基础收益；自身有护盾时可以把确定的最低价值手牌换成最高价值手牌，否则只能赌对手的不可见手牌。
	var gross_value: float = AI_HOSTILE_TARGET_VALUE
	if int(owner.get("shield", 0)) >= MIN_SHIELD_FOR_TARGET:
		# 自身手牌的最高最低价值差；差值不足时升级并不成立，本次发动只剩公开信息，价值按友方目标处理。
		gross_value = AI_SELF_UPGRADE_TARGET_VALUE if _get_hand_value_gap(authoritative_snapshot, owner, evaluator) >= AI_VALUE_GAP_THRESHOLD else AI_FRIENDLY_TARGET_VALUE
	# 材料机会成本；材料在技能内部选择，因此用当前手牌最低保留价值代表最可能支付的成本。
	return gross_value - _get_cheapest_hand_value(authoritative_snapshot, owner, evaluator) * AI_MATERIAL_COST_MULTIPLIER


## 返回快照手牌中的最低保留价值；空手牌返回0，表示没有可用材料。
func _get_cheapest_hand_value(authoritative_snapshot: Dictionary, owner: Dictionary, evaluator: Object) -> float:
	# 当前最低价值；首个候选直接赋值，避免用0作为哨兵值与真实的0价值牌混淆。
	var cheapest_value: float = 0.0
	# 是否已经读到至少一张手牌。
	var has_value: bool = false
	for card_variant: Variant in owner.get("hand", []) as Array:
		# 当前手牌快照；只读取定义ID交给统一估值接口。
		var card: Dictionary = card_variant as Dictionary
		var card_value: float = evaluator.get_card_value_by_id(str(card.get("definition_id", "")), authoritative_snapshot, owner_player_id)
		if not has_value or card_value < cheapest_value:
			cheapest_value = card_value
			has_value = true
	return cheapest_value


## 为AI评估鉴映的三段选择。
##
## 材料段优先选择保留价值最低的手牌；自身有护盾且手牌存在明显高低价值差时进一步压低低价值牌，
## 形成“低价值A换高价值B”的升级对。角色段在自身有护盾时优先选自己，否则优先选敌人，最后才考虑队友。
## 目标手牌段只有来源是自己时才能读到真实价值，因此他人手牌按未知资源均等处理，并避免把A选成B。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；按三段选择各自的kind分流。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 当前步骤种类；空值表示不是本技能的请求。
	var choice_kind: String = str(context.get("kind", ""))
	match choice_kind:
		CARD_CHOICE_KIND_MATERIAL:
			return _score_ai_material_choice(authoritative_snapshot, choice_request, action, evaluator)
		TARGET_CHOICE_KIND:
			return _score_ai_target_choice(authoritative_snapshot, action, evaluator)
		CARD_CHOICE_KIND_REVEAL:
			return _score_ai_reveal_choice(authoritative_snapshot, context, action, evaluator)
	return 0.0


## 评估材料段选择：优先选择保留价值最低的手牌作为A。
func _score_ai_material_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载；未确认表示取消发动，不消耗次数也不展示任何牌，按0分处理。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选实体牌；本步骤恰好选择一张。
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.size() != CARD_SELECT_COUNT:
		return -AI_SELF_CARD_PENALTY
	# 所选材料价值；数值越低越适合作为转化材料，因此直接取负值作为评分。
	return -evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)


## 评估角色段选择：自身有护盾优先自己，否则优先敌人，最后才是队友。
func _score_ai_target_choice(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载；窗口不可取消，未确认按无效动作拒绝。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return -AI_SELF_CARD_PENALTY
	# 已选角色；本步骤恰好选择一名。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if selected_targets.size() != TARGET_SELECT_COUNT:
		return -AI_SELF_CARD_PENALTY
	# 目标角色ID与当前态度；正值友方、负值敌方。
	var target_id: int = int(selected_targets[0])
	# 技能持有者自身护盾；自身有护盾时选择自己可以确保B来自可见手牌。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if target_id == owner_player_id:
		return AI_SELF_UPGRADE_TARGET_VALUE if int(owner.get("shield", 0)) >= MIN_SHIELD_FOR_TARGET else 0.0
	if evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) < 0.0:
		return AI_HOSTILE_TARGET_VALUE
	return AI_FRIENDLY_TARGET_VALUE


## 评估B选择：来源是自己时取高价值牌并避免选中A本体，来源是他人时牌面不可见，按均等处理。
func _score_ai_reveal_choice(authoritative_snapshot: Dictionary, context: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载；窗口不可取消，未确认按无效动作拒绝。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return -AI_SELF_CARD_PENALTY
	# 已选实体牌；本步骤恰好选择一张。
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.size() != CARD_SELECT_COUNT:
		return -AI_SELF_CARD_PENALTY
	# 所选实体牌UID；用于排除“A视为自己”的空转选择。
	var selected_uid: int = int(selected_cards[0])
	if selected_uid == _revealed_material_uid:
		return -AI_SELF_CARD_PENALTY
	# 来源角色；只有来源是技能持有者本人时手牌牌面对AI可见。
	if int(context.get("target_id", -1)) != owner_player_id:
		return 0.0
	# 所选牌保留价值；自身手牌作为B时取高价值牌即为本次发动的全部收益。
	return evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, selected_uid)


## 返回技能持有者手牌中最高与最低保留价值之差；少于两张手牌时返回0。
func _get_hand_value_gap(authoritative_snapshot: Dictionary, owner: Dictionary, evaluator: Object) -> float:
	# 当前最高与最低价值；首个候选同时初始化两者。
	var highest_value: float = 0.0
	var lowest_value: float = 0.0
	# 已读取的手牌数；不足两张时不存在价值差。
	var counted_cards: int = 0
	for card_variant: Variant in owner.get("hand", []) as Array:
		# 当前手牌快照；只读取定义ID交给统一估值接口。
		var card: Dictionary = card_variant as Dictionary
		var card_value: float = evaluator.get_card_value_by_id(str(card.get("definition_id", "")), authoritative_snapshot, owner_player_id)
		if counted_cards == 0:
			highest_value = card_value
			lowest_value = card_value
		else:
			highest_value = maxf(highest_value, card_value)
			lowest_value = minf(lowest_value, card_value)
		counted_cards += 1
	return 0.0 if counted_cards < 2 else highest_value - lowest_value
