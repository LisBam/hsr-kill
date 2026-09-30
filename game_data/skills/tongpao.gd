extends SkillDefinition

## 【同袍】技能源码。四个轮回节依次自伤1点、令其他角色获得1点护盾、弃置自己一张手牌、弃置其他角色区域内一张牌，每节每出牌阶段限一次。

## ①对自己造成伤害所在的轮回节零基索引；固定0对应玩家可见的①。
const DAMAGE_SELF_SECTION_INDEX: int = 0

## ②令其他角色获得护盾所在的轮回节零基索引；固定1对应玩家可见的②。
const SHIELD_SECTION_INDEX: int = 1

## ③弃置自己一张手牌所在的轮回节零基索引；固定2对应玩家可见的③。
const DISCARD_HAND_SECTION_INDEX: int = 2

## ④弃置其他角色区域内一张牌所在的轮回节零基索引；固定3对应玩家可见的④。
const DISCARD_ZONE_SECTION_INDEX: int = 3

## ①轮回节对持有者本人造成的固定普通伤害；数值1来自技能原文。
## 原文用“造成1点伤害”而非“失去1点体力”，因此护盾可以吸收，伤害来源与目标都是持有者本人。
const SELF_DAMAGE_AMOUNT: int = 1

## ②轮回节给予目标的固定护盾点数；数值1来自技能原文。
const SHIELD_AMOUNT: int = 1

## ③轮回节要求弃置的手牌张数；数值1来自技能原文，装备区的牌不能充当本费用。
const DISCARD_HAND_COUNT: int = 1

## ④轮回节要求弃置的区域牌张数；数值1来自技能原文，手牌、装备与判定三区均可被选。
const DISCARD_ZONE_COUNT: int = 1

## ②轮回节的目标选择请求种类；恢复时按该值分流。
const SHIELD_CHOICE_KIND: String = "tongpao_shield"

## ③轮回节的费用牌选择请求种类；恢复时按该值分流。
const DISCARD_HAND_CHOICE_KIND: String = "tongpao_discard_hand"

## ④轮回节第一步的角色选择请求种类；确认后进入该角色的区域选牌窗口。
const DISCARD_ZONE_TARGET_CHOICE_KIND: String = "tongpao_zone_target"

## ④轮回节第二步的区域牌选择请求种类；上下文携带第一步选定的角色ID。
const DISCARD_ZONE_CARD_CHOICE_KIND: String = "tongpao_zone_card"

## AI：队友残血阈值；需求给出的AI提示为“队友血量不大于2”，因此只给体力不高于该值的队友补盾。
const AI_LOW_HP_THRESHOLD: int = 2

## AI：①自伤前要求自己至少保有的体力；低于该值时自伤会把自己推向濒死，属于负收益。
const AI_SELF_DAMAGE_MIN_HP: int = 2

## AI：空节推进的固定收益；②③④在客观上没有可执行内容时是零代价的，不推进反而会让轮回永久卡死。
const AI_EMPTY_SECTION_VALUE: float = 0.5

## AI：③弃牌为④开路时的固定预期收益；④可以弃置敌方手牌或队友判定区的牌，价值稳定为正。
## 该值高于一张普通牌的代价，因此AI只有在手里确实有低价值牌时才会付费用推进。
const AI_SECTION_ADVANCE_VALUE: float = 1.2

## AI：④为队友解除判定区延时锦囊的固定收益；属于需求AI提示明确要求的正向协助行为。
const AI_ALLY_JUDGMENT_RESCUE_VALUE: float = 1.5

## AI：④第二步的区域权重；判定区牌直接决定目标的下个回合，价值最高，装备次之，手牌最低。
const AI_ZONE_WEIGHT_JUDGMENT: float = 1.6

## AI：④第二步的装备区权重；装备是持续收益来源，价值高于单张手牌。
const AI_ZONE_WEIGHT_EQUIPMENT: float = 1.1

## AI：④第二步的手牌区权重；单张手牌的信息与用途都最不确定，权重最低。
const AI_ZONE_WEIGHT_HAND: float = 0.7

## ④第二步选牌请求声明的选牌语义；统一选择评分据此把“选中的牌”理解为拆解他人区域的收益，
## 而不是自己支付出去的代价。取值与统一评估器既有的“操作他人区域”语义同名，两处必须保持一致。
## 缺少该声明时，通用层会按牌面价值取负，AI 会对任何目标都给出负分并取消，轮回节因此无法推进。
const AI_CARD_SEMANTICS_DISCARD_TARGET: String = "discard_target"


## 写入四轮回节主动技能静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"tongpao",
		"name":"同袍",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"reincarnation":true,
		"reincarnation_section_count":4,
		"reincarnation_has_explicit_sections":true,
		"reincarnation_each_section_once_per_play_phase":true,
		"description":"轮回技，出牌阶段每个轮回节各限一次，你可以①对自己造成1点伤害，②令一名其他角色获得1点护盾，③弃置一张手牌，④弃置一名其他角色区域内的一张牌。",
	})


## 检查阶段、轮回额度与当前轮回节的可发动性。
## ②③④即使客观上没有可执行内容也必须返回true：轮回节只能顺序推进，一旦此处返回false，
## 该轮回就会永久停在本节，玩家的④永远无法到达。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or host.state.current_player_id != owner_player_id or host.state.current_phase != "play" or not can_activate_reincarnation():
		return false
	return true


## 按当前轮回节执行动作或创建统一选择请求；无可执行内容时直接完成空节。
func activate(context: Dictionary = {}) -> String:
	if not can_activate():
		return "【同袍】当前轮回节不可发动。"
	# 当前轮回节；动作提交与选择标题均以本次快照为准。
	var section_index: int = get_reincarnation_section_index()
	if section_index == DAMAGE_SELF_SECTION_INDEX:
		# ①没有可选内容，发动即执行；AI与调试入口都通过同一路径提交。
		return "" if _execute_self_damage_section() else "【同袍】自伤结算失败。"
	if section_index == SHIELD_SECTION_INDEX:
		# ②直接目标；基础AI动作携带该字段，人类动作通常进入选择窗口。
		var shield_target_ids: Array[int] = _int_array(context.get("target_ids", []) as Array)
		if shield_target_ids.size() == 1:
			return "" if _execute_shield_section(shield_target_ids[0]) else "【同袍】所选角色已经失效。"
		# 没有其他存活角色时本节无内容；直接完成空节，不创建空窗口。
		if _get_shield_target_ids().is_empty():
			return "" if _complete_empty_section(SHIELD_SECTION_INDEX) else "【同袍】空节推进失败。"
		request_target_selection("【同袍】请选择获得1点护盾的角色", _get_shield_target_ids(), 1, 1, true, {"kind":SHIELD_CHOICE_KIND})
		return ""
	if section_index == DISCARD_HAND_SECTION_INDEX:
		# ③直接费用牌；与选择窗口共用同一份候选过滤器。
		var hand_card_uid: int = int(context.get("card_uid", -1))
		if hand_card_uid >= 0:
			return "" if _execute_discard_hand_section(hand_card_uid) else "【同袍】所选手牌已经失效。"
		# 自己没有任何手牌时本节无内容；装备区的牌不作费用，因此此处不看装备。
		if _get_hand_card_candidates().is_empty():
			return "" if _complete_empty_section(DISCARD_HAND_SECTION_INDEX) else "【同袍】空节推进失败。"
		request_card_selection("同袍", "请选择一张手牌弃置", _get_hand_card_candidates(), DISCARD_HAND_COUNT, DISCARD_HAND_COUNT, true, {"kind":DISCARD_HAND_CHOICE_KIND})
		return ""
	# ④是两步交互：先选角色，再选该角色区域内的一张牌。
	var zone_target_ids: Array[int] = _int_array(context.get("target_ids", []) as Array)
	if zone_target_ids.size() == 1:
		return "" if _begin_zone_card_selection(zone_target_ids[0]) else "【同袍】所选角色区域内没有可弃置的牌。"
	if _get_zone_target_ids().is_empty():
		return "" if _complete_empty_section(DISCARD_ZONE_SECTION_INDEX) else "【同袍】空节推进失败。"
	request_target_selection("【同袍】请选择一名区域内至少有牌的角色", _get_zone_target_ids(), 1, 1, true, {"kind":DISCARD_ZONE_TARGET_CHOICE_KIND})
	return ""


## 恢复②目标、③费用牌、④角色与④区域牌四类选择；取消不会推进轮回节。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 选择业务类型；只消费同袍自身建立的请求。
	var kind: String = str(context.get("kind", ""))
	if kind == SHIELD_CHOICE_KIND:
		if response.confirmed and response.target_ids.size() == 1:
			_execute_shield_section(response.target_ids[0])
		return true
	if kind == DISCARD_HAND_CHOICE_KIND:
		if response.confirmed and response.card_ids.size() == 1:
			_execute_discard_hand_section(response.card_ids[0])
		return true
	if kind == DISCARD_ZONE_TARGET_CHOICE_KIND:
		if response.confirmed and response.target_ids.size() == 1:
			_begin_zone_card_selection(response.target_ids[0])
		return true
	if kind == DISCARD_ZONE_CARD_CHOICE_KIND:
		if response.confirmed and response.card_ids.size() == 1:
			_execute_discard_zone_section(int(context.get("target_id", -1)), response.card_ids[0])
		return true
	return false


## 执行①：对自己造成1点普通伤害；伤害来源与目标都是本人，护盾可以吸收。
func _execute_self_damage_section() -> bool:
	if not can_activate() or get_reincarnation_section_index() != DAMAGE_SELF_SECTION_INDEX or not begin_reincarnation_activation():
		return false
	# 持有者技能端口；伤害与受击对象都是本人。
	var owner_player: SkillPlayer = get_owner_skill_player()
	owner_player.damage(SELF_DAMAGE_AMOUNT, owner_player)
	announce_activation({"section_number":DAMAGE_SELF_SECTION_INDEX + 1, "round_count":get_reincarnation_round_count(), "target_id":owner_player_id, "damage":SELF_DAMAGE_AMOUNT})
	complete_reincarnation_activation()
	return true


## 执行②：令指定其他角色获得1点护盾；目标在等待期间失效时本节不推进。
func _execute_shield_section(target_id: int) -> bool:
	if not can_activate() or get_reincarnation_section_index() != SHIELD_SECTION_INDEX or not _get_shield_target_ids().has(target_id) or not begin_reincarnation_activation():
		return false
	# 实际获得量；护盾上限或免疫规则可能使其低于请求值，但本节仍然照常完成。
	var granted_shield: int = get_skill_player(target_id).shield(SHIELD_AMOUNT, get_owner_skill_player())
	announce_activation({"section_number":SHIELD_SECTION_INDEX + 1, "round_count":get_reincarnation_round_count(), "target_id":target_id, "target_ids":[target_id], "shield":granted_shield})
	observe_identity_behavior([target_id], {"target_result":1.0})
	complete_reincarnation_activation()
	return true


## 执行③：弃置自己一张手牌；费用实际弃置成功后本节才推进。
func _execute_discard_hand_section(card_uid: int) -> bool:
	if not can_activate() or get_reincarnation_section_index() != DISCARD_HAND_SECTION_INDEX or not _candidate_uids(_get_hand_card_candidates()).has(card_uid) or not begin_reincarnation_activation():
		return false
	# 单张费用UID数组；显式强类型保证动态控制器调用与公开端口签名一致。
	var selected_uids: Array[int] = [card_uid]
	if int(host.call("discard_selected_hand_cards", owner_player_id, selected_uids)) != DISCARD_HAND_COUNT:
		return false
	announce_activation({"section_number":DISCARD_HAND_SECTION_INDEX + 1, "round_count":get_reincarnation_round_count(), "discarded_card_uid":card_uid})
	complete_reincarnation_activation()
	return true


## 执行④：弃置指定角色区域内的一张牌；走带保护校验的通用弃牌端口，不绕过防具与技能保护。
func _execute_discard_zone_section(target_id: int, card_uid: int) -> bool:
	if not can_activate() or get_reincarnation_section_index() != DISCARD_ZONE_SECTION_INDEX or not _get_zone_target_ids().has(target_id) or not _candidate_uids(_get_zone_card_candidates(target_id)).has(card_uid) or not begin_reincarnation_activation():
		return false
	if not bool(host.call("discard_selected_player_card", owner_player_id, target_id, card_uid)):
		return false
	announce_activation({"section_number":DISCARD_ZONE_SECTION_INDEX + 1, "round_count":get_reincarnation_round_count(), "target_id":target_id, "target_ids":[target_id], "discarded_card_uid":card_uid})
	observe_identity_behavior([target_id], {"target_result":-1.0})
	complete_reincarnation_activation()
	return true


## 完成一个客观上没有可执行内容的轮回节；只记录发动事实，不产生任何牌效。
## 这是轮回技顺序推进的必要出口：没有它，②③④在无内容时会让整个轮回永久停在当前节。
func _complete_empty_section(expected_section_index: int) -> bool:
	if not can_activate() or get_reincarnation_section_index() != expected_section_index or not begin_reincarnation_activation():
		return false
	announce_activation({"section_number":expected_section_index + 1, "round_count":get_reincarnation_round_count(), "empty_section":true})
	complete_reincarnation_activation()
	return true


## ④第二步：进入目标角色区域内的选牌窗口；目标在等待期间失去全部区域牌时改走空节推进。
func _begin_zone_card_selection(target_id: int) -> bool:
	if host == null or not _get_zone_target_ids().has(target_id):
		return false
	# 目标区域候选；含手牌、装备与判定三区，可见性由控制器按查看关系决定。
	var candidates: Array[Dictionary] = _get_zone_card_candidates(target_id)
	if candidates.is_empty():
		return _complete_empty_section(DISCARD_ZONE_SECTION_INDEX)
	request_card_selection("同袍", "请选择要弃置的牌", candidates, DISCARD_ZONE_COUNT, DISCARD_ZONE_COUNT, true, {"kind":DISCARD_ZONE_CARD_CHOICE_KIND, "target_id":target_id, "ai_choice_card_semantics":AI_CARD_SEMANTICS_DISCARD_TARGET})
	return true


## 返回除持有者外全部存活在场角色，供②的护盾目标选择。
func _get_shield_target_ids() -> Array[int]:
	return host.call("get_other_alive_player_ids", owner_player_id) as Array[int]


## 返回持有者自己的手牌候选；③明确规定弃置手牌，因此装备区的牌不进入候选。
func _get_hand_card_candidates() -> Array[Dictionary]:
	return host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]


## 返回区域内至少有一张牌的其他存活角色，供④第一步的角色选择。
func _get_zone_target_ids() -> Array[int]:
	# 目标结果；保持权威座次顺序，界面与AI据此稳定展示同一份候选。
	var result: Array[int] = []
	if host == null or host.get("state") == null:
		return result
	for player: PlayerState in host.state.players:
		if player.player_id == owner_player_id or not player.alive or player.out_of_game:
			continue
		if not (player.hand.is_empty() and player.equipment.is_empty() and player.judgment_area.is_empty()):
			result.append(player.player_id)
	return result


## 返回指定角色区域内全部可被查看的牌候选，供④第二步选择。
func _get_zone_card_candidates(target_id: int) -> Array[Dictionary]:
	return host.call("get_player_zone_candidates", owner_player_id, target_id) as Array[Dictionary]


## 从选择候选提取稳定UID数组；等待期间最终弃置仍会再次复核实体位置。
func _candidate_uids(candidates: Array[Dictionary]) -> Array[int]:
	# UID结果；保持候选顺序供AI稳定枚举。
	var result: Array[int] = []
	for candidate: Dictionary in candidates:
		result.append(int(candidate.get("uid", -1)))
	return result


## 把弱类型数组收敛为整数数组；动作与网络输入共用该防御性转换。
func _int_array(values: Array) -> Array[int]:
	# 转换结果；保留原顺序，由最终技能规则判断数量。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result


## 为AI按当前轮回节枚举全部合法动作；空节同样枚举一个零参数动作，让AI可以推进轮回。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	# 当前轮回节；各节枚举各自的动作形态。
	var section_index: int = get_reincarnation_section_index()
	if section_index == DAMAGE_SELF_SECTION_INDEX:
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id(), "confirm_self":true, "reincarnation_section":section_index}})
		return
	if section_index == SHIELD_SECTION_INDEX:
		# ②候选角色；没有其他存活角色时只枚举空节推进动作。
		var shield_target_ids: Array[int] = _get_shield_target_ids()
		if shield_target_ids.is_empty():
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id(), "reincarnation_section":section_index}})
			return
		for target_id: int in shield_target_ids:
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id], "reincarnation_section":section_index}})
		return
	if section_index == DISCARD_HAND_SECTION_INDEX:
		# ③候选费用牌；没有手牌时只枚举空节推进动作。
		var hand_candidates: Array[Dictionary] = _get_hand_card_candidates()
		if hand_candidates.is_empty():
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id(), "reincarnation_section":section_index}})
			return
		for candidate: Dictionary in hand_candidates:
			# 当前费用牌UID；动作只携带稳定ID，不持有牌对象。
			var card_uid: int = int(candidate.get("uid", -1))
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "card_uid":card_uid, "payload":{"skill_id":get_id(), "card_uid":card_uid, "reincarnation_section":section_index}})
		return
	# ④第一步只枚举角色；具体弃哪张牌由第二步窗口的 score_ai_choice 决定。
	var zone_target_ids: Array[int] = _get_zone_target_ids()
	if zone_target_ids.is_empty():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id(), "reincarnation_section":section_index}})
		return
	for target_id: int in zone_target_ids:
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id], "reincarnation_section":section_index}})


## 评估同袍当前轮回节动作的价值；各节的收益口径不同，分别交由对应的评分函数处理。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 当前轮回节；直接取枚举该动作时写入的节号，而不是运行时轮回状态。
	# AI评分运行在 host 为 null 的只读技能实例上（basic_ai_policy 以 bind(null, player_id) 建立评分实例），
	# 该路径下 get_reincarnation_section_index() 恒返回0（①自伤节），会让②③④的动作全部被按①定价。
	# 后果是AI选出一个与当前节不匹配的动作：它提交后停在④第二步的选牌窗口，因收益口径错误而取消，
	# 轮回节不推进、额度不消耗，同一个动作被反复提交，表现为AI长时间“思考”而游戏无法继续。
	# 动作负载里的节号由 append_play_phase_actions 在枚举时写入，是同一帧内与合法动作完全对应的稳定事实。
	var section_index: int = int((action.get("payload", {}) as Dictionary).get("reincarnation_section", DAMAGE_SELF_SECTION_INDEX))
	if section_index == DAMAGE_SELF_SECTION_INDEX:
		return _score_self_damage(authoritative_snapshot, evaluator)
	if section_index == SHIELD_SECTION_INDEX:
		# ②目标动作；零目标表示空节推进。
		var shield_target_ids: Array = action.get("target_ids", []) as Array
		if shield_target_ids.size() != 1:
			return AI_EMPTY_SECTION_VALUE
		return _score_shield_target(authoritative_snapshot, int(shield_target_ids[0]), evaluator)
	if section_index == DISCARD_HAND_SECTION_INDEX:
		# ③费用牌动作；零牌表示空节推进。
		var hand_card_uid: int = int(action.get("card_uid", (action.get("payload", {}) as Dictionary).get("card_uid", -1)))
		if hand_card_uid < 0:
			return AI_EMPTY_SECTION_VALUE
		return _score_discard_hand_action(authoritative_snapshot, hand_card_uid, evaluator)
	# ④角色动作；零目标表示空节推进。
	var zone_target_ids: Array = action.get("target_ids", []) as Array
	if zone_target_ids.size() != 1:
		return AI_EMPTY_SECTION_VALUE
	return _score_zone_target(authoritative_snapshot, int(zone_target_ids[0]), evaluator)


## 评估①自伤的净价值：只有自身体力足够、且确实存在需要护盾的队友时才值得。
## 有序推进下不发动①就永远到不了②，这是原文的固有代价；AI不得为了单纯推进而自伤。
func _score_self_damage(authoritative_snapshot: Dictionary, evaluator: Object) -> float:
	# 本人快照；体力不足以承受1点伤害时直接放弃。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty() or int(owner.get("hp", 0)) < AI_SELF_DAMAGE_MIN_HP:
		return -100.0
	# 最佳受盾队友收益；遍历全部其他存活角色取最大值。
	var best_ally_value: float = 0.0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；跳过自己、已死亡与已离场角色。
		var player: Dictionary = player_variant as Dictionary
		var target_id: int = int(player.get("player_id", -1))
		if target_id == owner_player_id or not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
			continue
		best_ally_value = maxf(best_ally_value, _score_shield_target(authoritative_snapshot, target_id, evaluator))
	if best_ally_value <= 0.0:
		return -100.0
	# 自伤代价；按公开体力资源价值折算，护盾收益必须严格超过代价才发动。
	return best_ally_value - float(SELF_DAMAGE_AMOUNT) * NonameAIEvaluator.HP_RESOURCE_VALUE


## 评估②给指定角色加盾的收益：只给态度为正且体力不高于残血阈值的队友，已有护盾越多边际收益越低。
func _score_shield_target(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	# 目标快照；体力与当前护盾共同决定补盾的边际收益。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or not bool(target.get("alive", false)):
		return 0.0
	# 残血判定；需求AI提示明确只对“血量不大于2”的队友发动。
	if int(target.get("hp", 0)) > AI_LOW_HP_THRESHOLD:
		return 0.0
	# 态度；非队友不加盾，避免把护盾送给敌方。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if attitude <= 0.0:
		return 0.0
	# 已有护盾；护盾越多边际收益越低，避免把护盾重复堆在同一角色上。
	var existing_shield: int = maxi(int(target.get("shield", 0)), 0)
	return attitude / 5.0 * float(SHIELD_AMOUNT) * NonameAIEvaluator.HP_RESOURCE_VALUE / float(existing_shield + 1)


## 评估③弃置自己的指定手牌：弃牌本身是纯代价，靠为④开路带来的固定收益抵消。
func _score_discard_hand_action(authoritative_snapshot: Dictionary, card_uid: int, evaluator: Object) -> float:
	# 费用代价；用统一资源评估器表达“自己少一张牌”，不自行声明牌值换算比例。
	var card_cost: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, owner_player_id, -DISCARD_HAND_COUNT, 0)
	return AI_SECTION_ADVANCE_VALUE + card_cost


## 评估④第一步的角色选择：优先敌方；队友只在判定区需要解围时才是正收益。
func _score_zone_target(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	# 目标快照；无效目标直接拒绝。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or not bool(target.get("alive", false)):
		return 0.0
	# 态度；对敌人弃牌是正收益，对队友弃牌通常是负收益。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if attitude < 0.0:
		return (-attitude / 5.0) * AI_ZONE_WEIGHT_HAND
	# 队友方向；只有其判定区存在延时锦囊时才值得协助解围。
	if _has_judgment_card(authoritative_snapshot, target_id, evaluator):
		return AI_ALLY_JUDGMENT_RESCUE_VALUE
	return -AI_ZONE_WEIGHT_HAND


## 评估④第二步选中的区域牌：判定区延时锦囊优先，其次敌方装备，最后敌方手牌。
func _score_zone_card(authoritative_snapshot: Dictionary, target_id: int, card_uid: int, evaluator: Object) -> float:
	if target_id < 0 or card_uid < 0:
		return -20.0
	# 牌所在区域；不同区域对目标的影响差异很大。
	var zone: String = _resolve_card_zone(authoritative_snapshot, target_id, card_uid, evaluator)
	# 区域权重；判定区牌直接决定目标的下个回合，因此权重最高。
	var zone_weight: float = AI_ZONE_WEIGHT_JUDGMENT if zone == "judgment" else (AI_ZONE_WEIGHT_EQUIPMENT if zone == "equipment" else AI_ZONE_WEIGHT_HAND)
	# 态度；对敌人弃牌是正收益，态度越负收益越高。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if attitude < 0.0:
		return (-attitude / 5.0) * zone_weight
	# 队友方向；只有判定区的延时锦囊才是正收益，弃队友的装备或手牌一律视为负收益。
	return zone_weight if zone == "judgment" else -zone_weight


## 评估同袍的选择窗口；②③④的窗口与④第二步的选牌各自评分。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；第二步选牌需要其中的目标ID。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 动作负载；取消一律按0分处理，让AI保持不发动。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var kind: String = str(context.get("kind", ""))
	if not bool(payload.get("confirmed", false)):
		return 0.0
	if kind == SHIELD_CHOICE_KIND:
		var shield_targets: Array = payload.get("selected_target_ids", []) as Array
		return _score_shield_target(authoritative_snapshot, int(shield_targets[0]), evaluator) if shield_targets.size() == 1 else -20.0
	if kind == DISCARD_HAND_CHOICE_KIND:
		# 弃置自己的手牌：按牌面价值取负，AI会自动选择价值最低的那张。
		var hand_cards: Array = payload.get("selected_card_uids", []) as Array
		return -evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(hand_cards[0])) if hand_cards.size() == 1 else -20.0
	if kind == DISCARD_ZONE_TARGET_CHOICE_KIND:
		var zone_targets: Array = payload.get("selected_target_ids", []) as Array
		return _score_zone_target(authoritative_snapshot, int(zone_targets[0]), evaluator) if zone_targets.size() == 1 else -20.0
	if kind == DISCARD_ZONE_CARD_CHOICE_KIND:
		var zone_cards: Array = payload.get("selected_card_uids", []) as Array
		return _score_zone_card(authoritative_snapshot, int(context.get("target_id", -1)), int(zone_cards[0]), evaluator) if zone_cards.size() == 1 else -20.0
	return 0.0


## 判断指定角色的判定区是否存在牌；判定区只可能存放延时锦囊，因此非空即视为需要解围。
## 只读权威快照，不通过 get_skill_player 访问运行时状态：AI评分使用 host 为 null 的只读技能实例，
## 该路径下运行时状态恒不可用，会让“队友判定区需要解围”这条唯一给队友正收益的分支永远不可达。
func _has_judgment_card(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> bool:
	# 目标公开快照；判定区是所有玩家可见的公共信息，任何观察者都能读到同一份内容。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	return not target.is_empty() and not (target.get("judgment_area", []) as Array).is_empty()


## 解析一张牌当前所在的区域；供④的区域权重评分使用，找不到时按手牌处理。
## 与 _has_judgment_card 同理：判定区与装备区都是公开信息，必须从快照读取而不是运行时状态。
func _resolve_card_zone(authoritative_snapshot: Dictionary, target_id: int, card_uid: int, evaluator: Object) -> String:
	# 目标公开快照；对手的手牌在快照中只保留数量，因此暗手牌会自然落回“hand”默认分支。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return "hand"
	if _snapshot_contains_card_uid(target.get("judgment_area", []) as Array, card_uid):
		return "judgment"
	# 装备区是按装备槽位索引的字典，必须遍历取值而不能当作数组处理。
	for card_variant: Variant in (target.get("equipment", {}) as Dictionary).values():
		# 当前装备实体快照；只按稳定UID比对，不依赖槽位名称。
		var equipped_card: Dictionary = card_variant as Dictionary
		if int(equipped_card.get("uid", -1)) == card_uid:
			return "equipment"
	return "hand"


## 判断实体牌快照数组是否包含指定UID；只读查询，不移动任何牌。
## 原先直接遍历 CardInstance 数组的等价查询已由本函数取代：AI评分只能拿到可序列化快照，
## 运行时牌对象在该路径下不可用，保留两套查询会重新引入“规则层与AI层口径不一致”的风险。
func _snapshot_contains_card_uid(cards: Array, card_uid: int) -> bool:
	for card_variant: Variant in cards:
		if int((card_variant as Dictionary).get("uid", -1)) == card_uid:
			return true
	return false
