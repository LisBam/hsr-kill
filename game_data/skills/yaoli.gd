extends SkillDefinition

## 【药理】技能源码。持有者每个出牌阶段可把一张红色手牌交给任意角色，并令该实体在离开其手牌区前视为【桃】。

## 临时视为牌的稳定定义ID；【桃】在《崩铁杀》名称模式下显示为【药】。
const MEDICINE_DEFINITION_ID: String = "tao"

## 当前出牌阶段是否已经成功交牌；每次普通或额外phaseUseBegin都会重置。
var _used_this_play_phase: bool = false


## 写入技能静态信息；技能描述严格保持设计原文，不混入提示或AI说明。
func _init() -> void:
	super({
		"id": "yaoli",
		"name": "药理",
		"trigger": "active",
		"enable": "phaseUse",
		"ui_enabled": true,
		"ai_extra_play_phase_value": 1.5,
		"description": "出牌阶段限一次，你可交给一名角色一张红色手牌，然后此牌视为【药】直到离开其手牌区。",
	})


## 安装阶段次数重置；额外出牌阶段拥有独立的一次发动额度。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player")


## 新出牌阶段开始时恢复本阶段发动次数。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 判断当前是否存在一张红色普通手牌与至少一名合法接收者。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；主动技能只允许在其自己的出牌阶段发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and not _used_this_play_phase and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" and not _get_red_hand_candidates().is_empty() and not _get_alive_target_ids().is_empty()


## 发动药理；AI可直接提交牌与目标，玩家按钮则进入统一牌目标组合选择。
func activate(context: Dictionary = {}) -> String:
	# 直接动作材料UID；负数表示需要打开交互选择。
	var card_uid: int = int(context.get("card_uid", context.get("material_card_uid", -1)))
	# 直接动作目标；药理固定选择一名角色且允许选择自己。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if card_uid >= 0 and target_ids.size() == 1:
		return "" if _execute_gift(card_uid, target_ids[0]) else "【药理】所选手牌或目标已经失效。"
	# 红色普通手牌候选；木牛“粮”和装备不属于技能原文要求的手牌。
	var candidates: Array[Dictionary] = _get_red_hand_candidates()
	# 合法接收者；所有存活且在场角色均可选择，包括技能持有者自己。
	var target_ids_for_choice: Array[int] = _get_alive_target_ids()
	if candidates.is_empty() or target_ids_for_choice.is_empty():
		return "当前没有可交出的红色手牌或合法角色。"
	request_card_target_selection("药理", "请选择一张红色手牌和一名角色", candidates, target_ids_for_choice, 1, 1, 1, 1, true, {"kind":"yaoli_gift"})
	return ""


## 恢复药理的牌与目标组合选择；取消不消耗本阶段次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "yaoli_gift" or response == null:
		return false
	if response.confirmed and response.card_ids.size() == 1 and response.target_ids.size() == 1:
		_execute_gift(response.card_ids[0], response.target_ids[0])
	return true


## 复核红色手牌与接收者并执行交牌；只有实体成功进入目标手牌后才消耗次数。
func _execute_gift(card_uid: int, target_id: int) -> bool:
	if _used_this_play_phase or not _get_alive_target_ids().has(target_id):
		return false
	# 当前红色手牌；等待期间花色不会改变，但实体可能已经离开手牌区。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 被交出的实体牌；不存在或不再为红色时本次发动失效。
	var card: CardInstance = owner.find_hand_card(card_uid) if owner != null else null
	if card == null or card.get_color() != "red":
		return false
	if not bool(host.call("transfer_hand_card_as", owner_player_id, target_id, card_uid, MEDICINE_DEFINITION_ID, get_id())):
		return false
	_used_this_play_phase = true
	announce_activation({"card_uid":card_uid, "target_id":target_id})
	observe_identity_behavior([target_id], {"target_result":1.0, "gain":true})
	return true


## 返回技能持有者当前全部红色普通手牌候选；候选顺序与手牌区一致。
func _get_red_hand_candidates() -> Array[Dictionary]:
	# 红色候选结果；候选牌面对持有者本人完全可见。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]:
		# 候选牌面；颜色由CardInstance序列化统一计算。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(card_data.get("color", "none")) == "red":
			result.append(candidate)
	return result


## 返回全部存活且在场角色ID；“一名角色”不排除技能持有者本人。
func _get_alive_target_ids() -> Array[int]:
	# 合法目标结果；保持权威座次顺序以稳定UI、AI与回放。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game:
			result.append(player.player_id)
	return result


## 为AI枚举每张红色手牌与每名角色的合法组合；所有动作仍会经过主动技能权威复核。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for candidate: Dictionary in _get_red_hand_candidates():
		# 当前红色手牌UID；用于动作成本估值和最终实体转移。
		var card_uid: int = int(candidate.get("uid", -1))
		for target_id: int in _get_alive_target_ids():
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "card_uid":card_uid, "target_ids":[target_id]}})


## 评估药理交牌动作；优先残血、较早行动、手牌较多且额外出牌阶段收益较高的友方角色。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载；保存红色手牌UID与唯一目标。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 目标数组；直接动作与通用动作字段均允许提供。
	var target_ids: Array = action.get("target_ids", payload.get("target_ids", [])) as Array
	if target_ids.size() != 1:
		return -20.0
	# 目标ID；敌对角色通常不应获得可用作回复或救援的【药】。
	var target_id: int = int(target_ids[0])
	# 娜塔莎对目标的可感知态度；负值目标会被显著降权。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if attitude < 0.0:
		return attitude - 6.0
	# 目标状态；残血、较多手牌与额外阶段收益共同决定交牌价值。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	# 目标已损失体力；最低为0，每点提供固定救援倾向。
	var missing_hp: int = maxi(int(target.get("max_hp", 0)) - int(target.get("hp", 0)), 0)
	# 当前动作综合评分；由态度、体力与手牌安全性构成基础值。
	var score: float = attitude / 2.5 + float(missing_hp) * 2.2 + minf(float(target.get("hand_count", 0)) * 0.25, 1.5)
	# 行动顺序奖励；同一轮中越早行动的残血友方越可能及时使用【药】并避免被敌方干扰。
	var current_index: int = _snapshot_player_index(authoritative_snapshot, int(authoritative_snapshot.get("current_player_id", -1)))
	# 目标座次索引；无效时不加入行动顺序修正。
	var target_index: int = _snapshot_player_index(authoritative_snapshot, target_id)
	# 当前玩家总数；用于计算不跨负数的环形行动距离。
	var player_count: int = (authoritative_snapshot.get("players", []) as Array).size()
	if player_count > 0 and current_index >= 0 and target_index >= 0:
		# 从当前角色到目标的环形座次距离；范围为0至玩家数减1。
		var action_distance: int = posmod(target_index - current_index, player_count)
		score += float(player_count - action_distance) * 0.15 if missing_hp > 0 else 0.0
	# 焕发联动；只有娜塔莎确实拥有焕发时才把目标额外出牌阶段的潜在收益计入。
	if _owner_has_skill(authoritative_snapshot, "huanfa"):
		score += _estimate_extra_play_phase_value(authoritative_snapshot, target_id) * 0.7
	# 自己红色手牌很少且未受伤时保留给队友；自身受伤时【药】的即时回复价值覆盖该保留倾向。
	var red_hand_count: int = _get_red_hand_candidates().size()
	if target_id == owner_player_id and red_hand_count <= 1 and missing_hp <= 0:
		score -= 3.0
	# 交出材料的机会成本；优先选择低保留价值红牌，向友方转移只折算部分资源成本。
	score -= evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("card_uid", -1))) * 0.3
	return score


## 返回指定玩家在快照玩家数组中的座次索引；无效ID返回-1。
func _snapshot_player_index(authoritative_snapshot: Dictionary, player_id: int) -> int:
	# 玩家快照数组；数组顺序就是稳定座次顺序。
	var players: Array = authoritative_snapshot.get("players", []) as Array
	for index: int in range(players.size()):
		if int((players[index] as Dictionary).get("player_id", -1)) == player_id:
			return index
	return -1


## 判断技能持有者的武将配置是否包含指定技能；AI不读取其他运行时技能实例私有状态。
func _owner_has_skill(authoritative_snapshot: Dictionary, skill_id: String) -> bool:
	# 技能持有者快照；武将静态技能列表用于确认联动存在。
	var owner: Dictionary = _snapshot_player(authoritative_snapshot, owner_player_id)
	return (GameDatabase.get_character(str(owner.get("character_id", ""))).get("skills", []) as Array).has(skill_id)


## 估算目标额外出牌阶段收益；手牌资源与技能元数据中的阶段价值均通过通用字段累计。
func _estimate_extra_play_phase_value(authoritative_snapshot: Dictionary, target_id: int) -> float:
	# 目标角色快照；空字典表示目标无效且没有额外阶段收益。
	var target: Dictionary = _snapshot_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return 0.0
	# 基础阶段价值；每张手牌提供有限行动空间，避免单纯按手牌数无限放大。
	var result: float = minf(float(target.get("hand_count", 0)) * 0.55, 3.0)
	# 目标武将定义；各技能可通过通用元数据声明额外阶段收益。
	var character: Dictionary = GameDatabase.get_character(str(target.get("character_id", "")))
	for skill_id_variant: Variant in character.get("skills", []) as Array:
		result += float(GameDatabase.get_skill(str(skill_id_variant)).get("ai_extra_play_phase_value", 0.0))
	return result


## 从权威快照读取指定玩家；技能AI仅使用序列化数据，不持有PlayerState引用。
func _snapshot_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前遍历玩家快照；匹配稳定ID后返回。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}
