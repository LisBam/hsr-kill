extends SkillDefinition

## 【亲酿】技能源码。每个出牌阶段展示并交出一张黑色牌，使其持续视为【酒】直到接收者下个回合结束。

## 亲酿赋予的临时牌名稳定定义ID；使用与打出规则均复用标准【酒】。
const WINE_DEFINITION_ID: String = "jiu"

## 亲酿每次固定选择的黑色牌数量；普通手牌与本人装备都必须恰好选择1张。
const GIFT_CARD_COUNT: int = 1

## 亲酿每次固定选择的接收角色数量；技能持有者本人也属于合法的1名角色。
const GIFT_TARGET_COUNT: int = 1

## AI在额外出牌阶段中拥有亲酿入口的基础价值；默认1.4分，仅用于其他技能评估额外阶段收益。
const AI_EXTRA_PLAY_PHASE_VALUE: float = 1.4

## AI遇到缺少唯一目标等非法动作时的固定拒绝分；默认-20分保证取消优先。
const AI_INVALID_ACTION_SCORE: float = -20.0

## AI把亲酿交给敌方时追加的惩罚；默认7分避免资助敌方酒【杀】或濒死自救。
const AI_HOSTILE_TARGET_PENALTY: float = 7.0

## AI按接收者每点已损失体力增加的保命价值；默认1.3分体现临时【酒】的濒死自救潜力。
const AI_MISSING_HP_VALUE: float = 1.3

## AI按接收者每张手牌增加的酒【杀】兑现概率；默认每张0.25分。
const AI_HAND_CARD_VALUE: float = 0.25

## AI由接收者手牌数量获得的最高加分；默认1.5分避免手牌优势压过阵营与材料成本。
const AI_HAND_CARD_VALUE_CAP: float = 1.5

## AI按残血友方距离其下个回合的每个座次增加的保命价值；默认每席0.35分。
const AI_TURN_DISTANCE_VALUE: float = 0.35

## AI由回合距离获得的最高加分；默认1.4分，长桌不会无限放大同一张【酒】的价值。
const AI_TURN_DISTANCE_VALUE_CAP: float = 1.4

## AI确认接收者拥有【杀】且能命中敌方时的酒【杀】机会加分；默认2分。
const AI_HITTABLE_WINE_SLASH_VALUE: float = 2.0

## AI自己拥有【杀】时对自身发动的额外优先值；默认3分保证需要酒【杀】时优先自用。
const AI_SELF_WINE_SLASH_VALUE: float = 3.0

## AI计算交出黑色牌机会成本时使用的保留价值倍率；默认0.3优先选低价值牌，但允许团队收益覆盖费用。
const AI_MATERIAL_COST_MULTIPLIER: float = 0.3

## AI上报亲酿目标的基础正面牌效；默认1分表示公开交给目标1张可用手牌。
const AI_TARGET_RESULT: float = 1.0

## 当前出牌阶段是否已经成功发动亲酿；普通和额外出牌阶段分别重置。
var _used_this_play_phase: bool = false


## 写入技能静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"qinniang",
		"name":"亲酿",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"ai_extra_play_phase_value":AI_EXTRA_PLAY_PHASE_VALUE,
		"ai_extra_play_phase_requirements":{"minimum_hand_count":GIFT_CARD_COUNT, "required_hand_color":"black"},
		"description":"出牌阶段限一次，你可以展示并交给一名角色一张黑色牌，此牌视为【酒】直到其下个回合结束。",
	})


## 订阅出牌阶段开始时机；额外出牌阶段同样拥有独立的一次发动额度。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player")


## 新出牌阶段开始时恢复本阶段发动次数。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 判断当前是否存在黑色手牌或装备，以及至少一名合法接收角色。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；主动技能只允许在自己的出牌阶段发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and not _used_this_play_phase \
		and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" \
		and not _get_black_candidates().is_empty() and not _get_alive_target_ids().is_empty()


## 发动亲酿；直接动作携带牌和目标时立即复核，否则打开带材料专属目标映射的组合选择。
func activate(context: Dictionary = {}) -> String:
	# 直接动作材料UID；负数表示需要打开交互选择。
	var card_uid: int = int(context.get("card_uid", context.get("material_card_uid", -1)))
	# 直接动作目标；亲酿固定交给一名角色且允许选择自己。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if card_uid >= 0 and target_ids.size() == GIFT_TARGET_COUNT:
		return "" if _execute_gift(card_uid, target_ids[0]) else "【亲酿】所选黑色牌或目标已经失效。"
	# 当前黑色手牌与装备候选；装备牌只允许与自身目标组成合法组合。
	var candidates: Array[Dictionary] = _get_black_candidates()
	# 全部存活在场角色；手牌可以交给任意一名，装备只能收回自己手牌。
	var target_ids_for_choice: Array[int] = _get_alive_target_ids()
	if candidates.is_empty() or target_ids_for_choice.is_empty():
		return "当前没有可交出的黑色牌或合法角色。"
	# 单材料到目标集合映射；AI和UI使用target_ids_by_card_id，提交端使用完整组合映射再次校验。
	var selection_maps: Dictionary = _build_candidate_target_maps(candidates, target_ids_for_choice)
	request_card_target_selection("亲酿", "请选择一张黑色牌和一名角色", candidates, target_ids_for_choice, GIFT_CARD_COUNT, GIFT_CARD_COUNT, GIFT_TARGET_COUNT, GIFT_TARGET_COUNT, true, {
		"kind":"qinniang_gift",
		"target_ids_by_card_id":selection_maps.get("target_ids_by_card_id", {}),
		"target_combinations_by_card_id":selection_maps.get("target_combinations_by_card_id", {}),
	})
	return ""


## 恢复亲酿的牌与目标组合选择；取消不消耗本阶段次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "qinniang_gift" or response == null:
		return false
	if response.confirmed and response.card_ids.size() == GIFT_CARD_COUNT and response.target_ids.size() == GIFT_TARGET_COUNT:
		_execute_gift(response.card_ids[0], response.target_ids[0])
	return true


## 最终复核黑色牌与目标，展示手牌并完成交付；装备牌只能由持有者选择自己后收回手牌。
func _execute_gift(card_uid: int, target_id: int) -> bool:
	if _used_this_play_phase or not _get_alive_target_ids().has(target_id):
		return false
	# 技能持有者；最终执行前重新取得权威角色，避免等待选择期间角色状态失效。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 所选牌实体；技能只允许选择持有者的普通手牌或装备区。
	var selected_card: CardInstance = _find_owned_hand_or_equipment(card_uid)
	if owner == null or selected_card == null or selected_card.get_color() != "black":
		return false
	# 选择装备区实体时只能交给自己；该规则避免装备直接转移到他人手牌。
	if selected_card.zone == "equipment" and target_id != owner_player_id:
		return false
	# 普通手牌在移动前公开展示；装备区本就属于公开信息，无需伪造展示事件。
	if selected_card.zone == "hand" and host.call("reveal_hand_card", owner_player_id, card_uid, get_id()) == null:
		return false
	if not bool(host.call("transfer_hand_or_self_equipment_card_as_until_next_turn_end", owner_player_id, target_id, card_uid, WINE_DEFINITION_ID, get_id())):
		return false
	_used_this_play_phase = true
	announce_activation({"card_uid":card_uid, "target_id":target_id, "view_as_definition_id":WINE_DEFINITION_ID})
	observe_identity_behavior([target_id], {"target_result":AI_TARGET_RESULT, "gain":true})
	return true


## 返回技能持有者当前全部黑色普通手牌与装备候选；花色从实体快照读取，不依赖牌名。
func _get_black_candidates() -> Array[Dictionary]:
	# 黑色候选结果；本人选择自己的牌时手牌与装备牌面均完整可见。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]:
		# 候选牌面；颜色由CardInstance序列化统一计算。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(card_data.get("color", "none")) == "black":
			result.append(candidate)
	return result


## 按UID查找持有者的普通手牌或装备实体；不包含木牛“粮”和判定区。
func _find_owned_hand_or_equipment(card_uid: int) -> CardInstance:
	# 技能持有者；无效状态没有合法实体。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return null
	# 普通手牌实体；优先返回以保持与候选顺序一致。
	var hand_card: CardInstance = owner.find_hand_card(card_uid)
	if hand_card != null:
		return hand_card
	for equipment_variant: Variant in owner.equipment.values():
		# 当前装备实体；UID匹配时返回原对象供颜色与区域复核。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card != null and equipment_card.uid == card_uid:
			return equipment_card
	return null


## 返回全部存活且在场角色ID；“一名角色”包含技能持有者本人。
func _get_alive_target_ids() -> Array[int]:
	# 合法目标结果；保持权威座次顺序以稳定UI、AI与回放。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game:
			result.append(player.player_id)
	return result


## 构造每张候选牌专属的合法目标集合与完整组合；装备只映射自己，手牌映射全部角色。
func _build_candidate_target_maps(candidates: Array[Dictionary], target_ids: Array[int]) -> Dictionary:
	# 牌UID到目标ID集合；用于界面动态高亮和AI组合枚举。
	var target_ids_by_card_id: Dictionary = {}
	# 牌UID到完整单目标组合；用于权威提交复核，禁止伪造装备交给他人。
	var target_combinations_by_card_id: Dictionary = {}
	for candidate: Dictionary in candidates:
		# 当前候选UID；作为目标映射和最终提交复核的稳定键。
		var card_uid: int = int(candidate.get("uid", -1))
		# 当前候选合法目标；装备候选只允许目标为技能持有者。
		# 强类型构造补充：逐项写入Array[int]，避免duplicate返回无类型Array而在出牌阶段候选构造时触发类型错误。
		var legal_target_ids: Array[int] = []
		if str(candidate.get("zone", "")) == "equipment":
			legal_target_ids.append(owner_player_id)
		else:
			for target_id: int in target_ids:
				legal_target_ids.append(target_id)
		target_ids_by_card_id[str(card_uid)] = legal_target_ids.duplicate()
		# 当前候选完整组合数组；每个目标以单元素数组表达。
		var combinations: Array[Array] = []
		for target_id: int in legal_target_ids:
			combinations.append([target_id])
		target_combinations_by_card_id[str(card_uid)] = combinations
	return {"target_ids_by_card_id":target_ids_by_card_id, "target_combinations_by_card_id":target_combinations_by_card_id}


## 为AI枚举每张黑色牌与其合法接收者组合；装备牌不会生成交给他人的非法动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	# 当前黑色候选；主动动作始终来自同一权威候选集合。
	var candidates: Array[Dictionary] = _get_black_candidates()
	# 材料专属目标映射；装备与手牌分别读取自己的合法接收者集合。
	var selection_maps: Dictionary = _build_candidate_target_maps(candidates, _get_alive_target_ids())
	# 按牌UID保存的目标集合；AI只枚举权威映射中的组合。
	var targets_by_card: Dictionary = selection_maps.get("target_ids_by_card_id", {}) as Dictionary
	for candidate: Dictionary in candidates:
		# 当前黑色牌UID；用于最终交付与AI机会成本估值。
		var card_uid: int = int(candidate.get("uid", -1))
		for target_id_variant: Variant in targets_by_card.get(str(card_uid), []) as Array:
			# 当前合法接收者；动作目标和payload目标保持一致。
			var target_id: int = int(target_id_variant)
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "card_uid":card_uid, "target_ids":[target_id]}})


## 评估亲酿交付；优先自己有【杀】时自用，也照顾低体力、回合较远且有手牌的友方角色。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载；保存黑色牌UID与唯一目标。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 目标数组；直接动作与通用动作字段均允许提供。
	var target_ids: Array = action.get("target_ids", payload.get("target_ids", [])) as Array
	if target_ids.size() != GIFT_TARGET_COUNT:
		return AI_INVALID_ACTION_SCORE
	# 亲酿接收者；敌对角色通常不应获得可强化【杀】或濒死自救的【酒】。
	var target_id: int = int(target_ids[0])
	# 技能持有者对接收者的公开态度；负值角色不会获得团队资源。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if attitude < 0.0:
		return attitude - AI_HOSTILE_TARGET_PENALTY
	# 目标公开状态；低体力与较多手牌分别提高自救和成功使用酒杀的机会。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	# 目标已损失体力；每点提高临时【酒】作为濒死自救资源的价值。
	var missing_hp: int = maxi(int(target.get("max_hp", 0)) - int(target.get("hp", 0)), 0)
	# 当前动作综合评分；先计入交牌、残血与手牌资源价值，再叠加行动距离和酒【杀】机会。
	var score: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 1, 0) + float(missing_hp) * AI_MISSING_HP_VALUE + minf(float(target.get("hand_count", 0)) * AI_HAND_CARD_VALUE, AI_HAND_CARD_VALUE_CAP)
	# 接收者距离其下个回合的座次数；残血友方等待越久，临时【酒】覆盖敌方行动的保命价值越高。
	var target_turn_distance: int = _get_snapshot_turn_distance(authoritative_snapshot, target_id)
	if target_id != owner_player_id and missing_hp > 0:
		score += minf(float(target_turn_distance) * AI_TURN_DISTANCE_VALUE, AI_TURN_DISTANCE_VALUE_CAP)
	# 接收者已知【杀】数量；拥有【杀】且攻击范围内存在敌方时，提高其兑现酒【杀】的收益。
	var target_sha_count: int = evaluator.get_known_response_count(authoritative_snapshot, target_id, "sha")
	if target_sha_count > 0 and _has_hittable_enemy(authoritative_snapshot, target_id, evaluator):
		score += AI_HITTABLE_WINE_SLASH_VALUE
	if target_id == owner_player_id and evaluator.get_known_response_count(authoritative_snapshot, owner_player_id, "sha") > 0:
		score += AI_SELF_WINE_SLASH_VALUE
	# 材料机会成本；优先把低保留价值黑牌酿为酒。
	score -= evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("card_uid", -1))) * AI_MATERIAL_COST_MULTIPLIER
	return score


## 返回从当前回合角色到目标下个回合的存活座次数；目标不在场或快照异常时返回0。
func _get_snapshot_turn_distance(authoritative_snapshot: Dictionary, target_id: int) -> int:
	# 存活在场角色ID；死亡和离场角色不占用后续回合距离。
	var alive_player_ids: Array[int] = []
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；保持权威座次顺序以计算环形距离。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)):
			alive_player_ids.append(int(player.get("player_id", -1)))
	# 当前回合角色索引；缺失时无法可靠估算等待长度。
	var current_index: int = alive_player_ids.find(int(authoritative_snapshot.get("current_player_id", -1)))
	# 接收者索引；死亡、离场或缺失时不提供距离收益。
	var target_index: int = alive_player_ids.find(target_id)
	if current_index < 0 or target_index < 0 or alive_player_ids.is_empty():
		return 0
	return posmod(target_index - current_index, alive_player_ids.size())


## 判断接收者是否能以当前公开攻击范围命中至少一名敌对角色；只用于亲酿的酒【杀】机会评分。
func _has_hittable_enemy(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> bool:
	# 接收者攻击范围；武器范围与坐骑距离由通用AI只读接口统一计算。
	var attack_range: int = evaluator.get_attack_range(authoritative_snapshot, target_id)
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 候选受击角色；从权威快照读取存活、离场和阵营信息。
		var candidate: Dictionary = player_variant as Dictionary
		# 候选受击角色稳定ID；必须不同于接收者且能被接收者识别为敌方。
		var candidate_id: int = int(candidate.get("player_id", -1))
		if candidate_id == target_id or not bool(candidate.get("alive", false)) or bool(candidate.get("out_of_game", false)):
			continue
		if evaluator.get_attitude(authoritative_snapshot, target_id, candidate_id) < 0.0 and evaluator.get_distance(authoritative_snapshot, target_id, candidate_id) <= attack_range:
			return true
	return false
