extends SkillDefinition

## 【焕发】技能源码。任意角色回合结束时，若其本回合使用过【桃/药】，持有者可令其执行额外出牌阶段。

## 当前轮是否已经成功发动；roundStart重置，确认但阶段登记失败时不消耗次数。
var _used_this_round: bool = false

## 额外出牌阶段的基础行动价值；默认1分只在目标存在可用手牌时加入，避免空手阶段凭空获得收益。
const BASE_EXTRA_PLAY_PHASE_VALUE: float = 1.0

## 每张可用手牌提供的额外阶段价值；默认0.7分反映更多牌带来更多可选行动。
const HAND_CARD_EXTRA_PLAY_PHASE_VALUE: float = 0.7

## 手牌行动空间的最大附加值；默认3.5分避免高数量手牌无限抬高单次额外阶段收益。
const MAX_HAND_CARD_EXTRA_PLAY_PHASE_VALUE: float = 3.5

## 自身没有任何可用手牌或满足条件的主动技能时的确认评分；固定-20分确保可取消询问选择放弃。
const SELF_NO_PLAY_PHASE_OPPORTUNITY_SCORE: float = -20.0


## 写入技能静态信息；技能描述严格保持设计原文。
func _init() -> void:
	super({
		"id": "huanfa",
		"name": "焕发",
		"trigger": "phaseEnd",
		"ui_enabled": false,
		"description": "一名角色的回合结束时，若本回合内其使用过【药】，你可令其执行一个额外的出牌阶段。每轮限一次。",
	})


## 安装每轮次数重置与全局回合结束监听；额外回合的结束同样属于合法触发时机。
func install() -> void:
	subscribe_timing("roundStart", _on_round_start, "global")
	subscribe_timing("phaseEnd", _on_any_phase_end, "global")


## 新轮开始时恢复一次发动额度。
func _on_round_start(_event: RuleEvent) -> void:
	_used_this_round = false


## 检查回合角色本回合是否使用过【药】，并由娜塔莎决定是否给予额外出牌阶段。
func _on_any_phase_end(event: RuleEvent) -> void:
	if _used_this_round or not bool(host.call("has_used_card_this_turn", event.player_id, "tao")) or not bool(host.call("can_add_play_phase", event.player_id)):
		return
	request_card_selection("焕发", "是否令该角色执行一个额外的出牌阶段？", [], 0, 0, true, {"kind":"huanfa_confirm", "target_id":event.player_id, "ai_allow_confirm":true})


## 恢复焕发确认；阶段成功进入显式队列后才消费每轮次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "huanfa_confirm" or response == null:
		return false
	if response.confirmed and not _used_this_round:
		# 获得额外阶段的回合角色；等待期间死亡、离场或回合变化时核心端口会拒绝登记。
		var target_id: int = int(context.get("target_id", -1))
		if get_skill_player(target_id).addPlayPhase():
			_used_this_round = true
			announce_activation({"target_id":target_id})
			observe_identity_behavior([target_id], {"target_result":1.0})
	return true


## 评估当前角色的额外出牌收益，并在本轮后续存在更高价值持药友方时保留次数。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非焕发确认不改变通用选择评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "huanfa_confirm":
		return 0.0
	# 取消动作保持0分；确认只有严格正收益时才会被基础策略选中。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 当前回合角色；额外阶段价值乘娜塔莎对其的当前可感知态度。
	var target_id: int = int(context.get("target_id", -1))
	# 当前目标的实际额外阶段机会；空手、仅响应牌或技能材料不满足时会返回0。
	var extra_play_phase_value: float = _estimate_extra_play_phase_value(authoritative_snapshot, target_id)
	# 娜塔莎自身没有可用行动时不能为消耗次数而发动；药理必须持有红色普通手牌才算可用机会。
	if target_id == owner_player_id and is_zero_approx(extra_play_phase_value):
		return SELF_NO_PLAY_PHASE_OPPORTUNITY_SCORE
	# 当前发动收益；正值表示立即使用本轮额度比取消更有利。
	var current_value: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) / 5.0 * extra_play_phase_value
	# 后续保留价值；只考虑本轮尚未行动、手中明确拥有【药】且对娜塔莎友好的角色。
	var future_value: float = _best_future_candidate_value(authoritative_snapshot, target_id, evaluator)
	return current_value - future_value


## 返回本轮当前角色之后、下一次roundStart之前的最佳持药友方额外阶段价值。
func _best_future_candidate_value(authoritative_snapshot: Dictionary, current_target_id: int, evaluator: Object) -> float:
	# 玩家快照数组；项目以数组顺序表达稳定座次，末位之后的0号位会开启新轮并重置技能。
	var players: Array = authoritative_snapshot.get("players", []) as Array
	# 当前角色座次索引；默认-1表示快照缺失该角色并直接返回零收益。
	var current_index: int = -1
	for index: int in range(players.size()):
		if int((players[index] as Dictionary).get("player_id", -1)) == current_target_id:
			current_index = index
			break
	if current_index < 0:
		return 0.0
	# 最佳未来收益；只扫描当前座次之后，不跨越新轮边界。
	var result: float = 0.0
	for index: int in range(current_index + 1, players.size()):
		# 当前后续角色快照；只读存活、手牌与武将配置。
		var player: Dictionary = players[index] as Dictionary
		# 当前后续角色稳定ID；正式范围为0至9。
		var player_id: int = int(player.get("player_id", -1))
		if not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)) or not _snapshot_has_medicine(player):
			continue
		# 娜塔莎对当前后续角色的可感知态度；正值才保留技能额度。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, player_id)
		if attitude > 0.0:
			result = maxf(result, attitude / 5.0 * _estimate_extra_play_phase_value(authoritative_snapshot, player_id))
	return result


## 判断AI权威快照中的角色是否明确持有至少一张【药】；药理赋予的临时牌名已进入实体序列化数据。
func _snapshot_has_medicine(player: Dictionary) -> bool:
	for card_variant: Variant in player.get("hand", []) as Array:
		if str((card_variant as Dictionary).get("definition_id", "")) == "tao":
			return true
	return false


## 估算指定角色执行额外出牌阶段的收益；只计算实际可用手牌和满足材料条件的主动技能，不把空阶段视为固定收益。
func _estimate_extra_play_phase_value(authoritative_snapshot: Dictionary, target_id: int) -> float:
	# 目标角色快照；空字典表示目标不存在，额外阶段没有收益。
	var target: Dictionary = _snapshot_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return 0.0
	# 额外阶段收益；可用手牌和可发动技能分别累计，空手且技能材料不满足时保持0分。
	var result: float = 0.0
	if _snapshot_has_playable_hand_card(authoritative_snapshot, target):
		# 可用手牌数量；使用公开计数避免权威快照对非自身角色未附完整手牌时低估行动空间。
		var hand_count: int = maxi(int(target.get("hand_count", 0)), 0)
		result += BASE_EXTRA_PLAY_PHASE_VALUE + minf(float(hand_count) * HAND_CARD_EXTRA_PLAY_PHASE_VALUE, MAX_HAND_CARD_EXTRA_PLAY_PHASE_VALUE)
	# 目标武将定义；技能可通过通用元数据声明额外出牌阶段价值。
	var character: Dictionary = GameDatabase.get_character(str(target.get("character_id", "")))
	for skill_id_variant: Variant in character.get("skills", []) as Array:
		# 当前技能定义；数值与材料条件均由技能自身元数据声明，焕发不维护技能 ID 白名单。
		var skill_definition: Dictionary = GameDatabase.get_skill(str(skill_id_variant))
		# 当前技能额外阶段价值；没有正值声明的技能不会被凭空视为主动机会。
		var skill_value: float = float(skill_definition.get("ai_extra_play_phase_value", 0.0))
		# 当前技能材料条件；为空表示该技能自行声明无需手牌材料。
		var requirements: Dictionary = skill_definition.get("ai_extra_play_phase_requirements", {}) as Dictionary
		if skill_value > 0.0 and _are_extra_play_phase_requirements_satisfied(target, requirements):
			result += skill_value
	return result


## 判断快照中的手牌是否存在可在额外出牌阶段使用的机会；响应专用牌、满体力【桃】等不把空阶段误判为可行动。
func _snapshot_has_playable_hand_card(authoritative_snapshot: Dictionary, target: Dictionary) -> bool:
	# 已序列化的完整手牌；AI自身通常可见，其他角色缺失完整数据时按公开手牌数保守保留机会。
	var hand_cards: Array = target.get("hand", []) as Array
	if hand_cards.is_empty():
		return int(target.get("hand_count", 0)) > 0
	for card_variant: Variant in hand_cards:
		# 当前手牌快照；临时视为牌已将 definition_id 改为当前逻辑定义。
		var card: Dictionary = card_variant as Dictionary
		# 当前卡牌定义；数据缺失时不声称该牌可以在出牌阶段使用。
		var definition: Dictionary = GameDatabase.get_card(str(card.get("definition_id", "")))
		if _is_snapshot_card_playable(authoritative_snapshot, target, definition):
			return true
	return false


## 判断一张已知手牌是否具有基础出牌阶段机会；只按通用目标模式与公开存活状态过滤，不替代规则层最终校验。
func _is_snapshot_card_playable(authoritative_snapshot: Dictionary, target: Dictionary, definition: Dictionary) -> bool:
	if definition.is_empty():
		return false
	# 卡牌目标模式；response_only 只可在响应窗口打出，不能构成额外出牌阶段行动。
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode == "response_only":
		return false
	if target_mode == "self_wounded":
		return int(target.get("hp", 0)) < int(target.get("max_hp", 0))
	if target_mode in ["self", "all_players"]:
		return true
	if target_mode == "single_with_hand":
		return _has_snapshot_alive_player_with_hand(authoritative_snapshot)
	return _has_snapshot_other_alive_player(authoritative_snapshot, int(target.get("player_id", -1)))


## 判断目标是否满足技能声明的额外阶段材料条件；当前支持最少手牌数与指定手牌颜色，新增条件由数据字段扩展。
func _are_extra_play_phase_requirements_satisfied(target: Dictionary, requirements: Dictionary) -> bool:
	# 所需最少手牌数；默认0表示技能不要求普通手牌数量。
	var minimum_hand_count: int = maxi(int(requirements.get("minimum_hand_count", 0)), 0)
	if int(target.get("hand_count", 0)) < minimum_hand_count:
		return false
	# 所需手牌颜色；空字符串表示没有颜色限制。
	var required_hand_color: String = str(requirements.get("required_hand_color", ""))
	if required_hand_color.is_empty():
		return true
	# 已序列化手牌；颜色材料必须真实可见，不能依据其他角色的未知手牌数量猜测。
	for card_variant: Variant in target.get("hand", []) as Array:
		# 当前候选手牌；花色转换或临时视为不会改变实体的颜色字段。
		var card: Dictionary = card_variant as Dictionary
		if str(card.get("color", "none")) == required_hand_color:
			return true
	return false


## 判断快照中是否存在目标以外的存活角色；单目标他人牌与群体对他人牌至少需要该条件才有行动机会。
func _has_snapshot_other_alive_player(authoritative_snapshot: Dictionary, target_id: int) -> bool:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前候选角色；死亡或离场者不能成为出牌阶段目标。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) != target_id and bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)):
			return true
	return false


## 判断快照中是否存在手牌非空的存活角色；火攻等要求目标有手牌的通用目标模式使用该条件。
func _has_snapshot_alive_player_with_hand(authoritative_snapshot: Dictionary) -> bool:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前候选角色；必须在场且公开手牌数量大于0才能满足目标模式。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)) and int(player.get("hand_count", 0)) > 0:
			return true
	return false


## 从权威快照读取指定玩家；不存在时返回空字典。
func _snapshot_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前遍历玩家快照；匹配稳定ID后原样返回只读字典。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}
