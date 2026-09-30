extends CardDefinition

## 【铁索连环】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。

## AI把本次连环切换判定为不利时的固定惩罚；0.75分会压过纯出牌顺序，仍允许多目标组合以更高收益覆盖。
const AI_UNFAVORABLE_CHAIN_TARGET_PENALTY: float = 0.75

## AI使用效果必须至少比同一张牌的重铸收益高出的最小分差；避免微弱出牌顺序压过真实的换牌收益。
const AI_RECAST_USE_ADVANTAGE_MARGIN: float = 0.15

## 视为1v1局面的在场角色数量；恰好2名存活在场角色时固定选择重铸，不评估连环切换收益。
const DUEL_ACTIVE_PLAYER_COUNT: int = 2

## 连环生效所需的最少“可承受属性伤害角色”数；不足2名时横置无法把属性伤害传导给第二个人，本次使用没有传导收益。
## 对应无名杀 ai.result.target 中对 game.filterPlayer 计数小于2直接返回0的硬门槛。
const MIN_ELEMENTAL_DAMAGE_CAPABLE_COUNT: int = 2

## 横置策略所需的最少同阵营角色数；敌方不足该数量且仍有未横置敌人时不再横置敌人，
## 友方不足该数量时也不解除场上唯一已横置的队友。对应无名杀 es < 2 / fs < 2 的同一阈值。
const AI_MIN_SAME_SIDE_COUNT_FOR_CHAIN: int = 2

## 目标只能承受单一属性伤害时的连环收益折扣；直接取自无名杀 0.45 相对 0.9 的同一比例，不引入独立数值口径。
const AI_SINGLE_NATURE_CHAIN_MULTIPLIER: float = 0.5


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tiesuo",
		"original_name": "铁索连环",
		"custom_name": "命运连结",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "chain",
		"nature": "normal",
		"target_mode": "one_or_two",
		"min_targets": 1,
		"max_targets": 2,
		"allow_self_target": true,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": true,
		"delayed": false,
		"description": "令一至两名角色横置或重置；也可重铸并摸一张牌。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":7.3, "value":4.0, "target_result":-0.5, "multitarget":true},
		"ai_use_value": 1.0,
	})


## 执行【铁索连环】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		# 当前目标状态；每次生效都通过统一连环端口在横置与重置之间切换一次。
		var target: PlayerState = resolver.state.get_player(target_id)
		if target == null:
			continue
		resolver.host.toggle_player_linked(target_id, actor_id, card.definition_id)
		resolver.host.add_log("%s%s。" % [target.display_name, "进入连环状态" if target.chained else "解除连环状态"])
	return resolver.default_destination()


## 返回【铁索连环】当前目标的动态身份观察牌效；施加横置为负，解除横置为等量正收益。
func get_identity_observation_target_result(authoritative_snapshot: Dictionary, _actor_id: int, target_id: int, current_result: float) -> float:
	# 基础牌效绝对值；静态配置为-0.5，取绝对值后可按目标当前状态反转方向。
	var result_magnitude: float = absf(current_result)
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前目标快照；已横置表示本次效果将解除连环，因此由负面转为正面。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == target_id:
			return result_magnitude if bool(player.get("chained", false)) else -result_magnitude
	return current_result


## 为基础 AI 枚举一目标与二目标的全部合法组合；玩家与 AI 共用同一权威目标校验。
func append_play_phase_card_actions(match_host: Object, actor_id: int, card: CardInstance, result: Array[Dictionary]) -> bool:
	# 当前全部合法单目标；包含使用者本人，因为【铁索连环】允许选择自己。
	var legal_target_ids: Array[int] = match_host.card_rules.list_legal_targets(actor_id, card)
	for first_index: int in range(legal_target_ids.size()):
		# 单目标动作；保留规则允许只横置或重置一名角色的用法。
		var single_target_ids: Array[int] = [legal_target_ids[first_index]]
		match_host.append_card_action_if_legal(result, actor_id, card, single_target_ids)
		for second_index: int in range(first_index + 1, legal_target_ids.size()):
			# 双目标动作；组合只生成一次，最终结算顺序仍由规则服务按行动座次规范化。
			var double_target_ids: Array[int] = [legal_target_ids[first_index], legal_target_ids[second_index]]
			match_host.append_card_action_if_legal(result, actor_id, card, double_target_ids)
	return true


## 修正铁索连环切换状态的动作价值；解除横置与施加横置的收益方向必须相反。
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 动作发起者ID；态度查询、重铸评分与目标统计都以它为基准。
	var actor_id: int = int(action.get("actor_id", -1))
	# 同一实体牌的重铸动作与评分；多个否决分支都要落到“压到重铸之下”，因此先算一次并全程复用。
	var recast_score: float = evaluator.score_action(authoritative_snapshot, _build_recast_action(action), actor_id)
	# 使用动作被否决时的返回值；高于任何出牌顺序带来的伪收益，但仍严格低于同牌重铸。
	var suppressed_use_score: float = recast_score - AI_RECAST_USE_ADVANTAGE_MARGIN
	# 当前存活在场角色数；死亡和离场角色不参与1v1局面判定。
	var active_player_count: int = 0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；只有存活且未离场的角色构成实际对局人数。
		var player_snapshot: Dictionary = player_variant as Dictionary
		if bool(player_snapshot.get("alive", false)) and not bool(player_snapshot.get("out_of_game", false)):
			active_player_count += 1
	if active_player_count == DUEL_ACTIVE_PLAYER_COUNT:
		# 1v1固定重铸；无名杀没有该分支，此为本项目专属规则，先把使用动作压到重铸之后再由策略层取舍。
		return suppressed_use_score
	# 传导门槛：场上可承受属性伤害的角色不足2名时，横置最多只影响一个人，属性伤害无法传导给第二人。
	# 无名杀在同一位置直接返回0（即“这张牌用不出去”），本项目把使用动作压到同牌重铸之下，让重铸成为唯一正收益选择。
	if _count_elemental_damage_capable_players(authoritative_snapshot, evaluator) < MIN_ELEMENTAL_DAMAGE_CAPABLE_COUNT:
		return suppressed_use_score
	# 目标否决：敌方不足2名且仍有未横置敌人时不再横置敌人；友方不足2名时不要解除场上唯一已横置的队友。
	if _should_veto_link_targets(authoritative_snapshot, evaluator, action):
		return suppressed_use_score
	# 目标横置收益的基础幅度；直接读取本卡元数据的 target_result 绝对值，避免在评分逻辑中复制同一数值。
	var base_target_magnitude: float = absf(float(get_ai_profile().get("target_result", -0.5)))
	# 修正后评分；逐目标检查当前是否已经横置。
	var score: float = current_score
	# 本次使用是否至少有一名实际受益目标；没有时同牌重铸一定优先，不能让出牌顺序形成伪收益。
	var has_positive_target_effect: bool = false
	for target_id_variant: Variant in action.get("target_ids", []) as Array:
		# 当前目标 ID；用于读取连环状态与身份态度。
		var target_id: int = int(target_id_variant)
		# 当前目标快照；未横置时通用负面目标评分已经正确。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		if target.is_empty():
			continue
		# 当前目标态度；正值为友方，负值为敌方，0为中立。
		var target_attitude: float = evaluator.get_attitude(authoritative_snapshot, actor_id, target_id)
		# 目标横置收益幅度；只能承受单一属性时折半，公开防具放大属性伤害时同步放大。
		var target_magnitude: float = base_target_magnitude * _get_target_chain_magnitude_multiplier(authoritative_snapshot, evaluator, target_id)
		# 通用层已经计入的目标分量；施加横置对敌方为正、对友方为负，方向由 target_result 元数据决定。
		var generic_apply_score: float = -base_target_magnitude * target_attitude / 5.0
		# 本次实际结算后该目标的分量；未横置是“施加横置”，已横置是“解除横置”，两者方向必然相反。
		var resolved_target_score: float = target_magnitude * target_attitude / 5.0 if bool(target.get("chained", false)) else -target_magnitude * target_attitude / 5.0
		# 把通用分量替换为实际分量；幅度相同时即等价于原来的整体反号。
		score += resolved_target_score - generic_apply_score
		if resolved_target_score > 0.0:
			has_positive_target_effect = true
		# 敌方已横置时解除连环属于帮助，不得再被出牌顺序的微弱正分驱动为无脑使用。
		# 友方未横置时强行施加连环同样是不利目标；多目标动作只有整体收益足够高才会保留。
		if resolved_target_score < 0.0:
			score -= AI_UNFAVORABLE_CHAIN_TARGET_PENALTY
	# 同一实体牌始终同时提供重铸合法动作；使用效果没有明显高于换牌收益时，明确把本动作压到重铸之后。
	if not has_positive_target_effect:
		return suppressed_use_score
	if score <= recast_score + AI_RECAST_USE_ADVANTAGE_MARGIN:
		return suppressed_use_score
	return score


## 构造同一张实体牌的重铸动作；使用与重铸必须引用同一 card_uid 才能形成直接比较。
func _build_recast_action(action: Dictionary) -> Dictionary:
	return {
		"action_type":"recast_card",
		"actor_id":int(action.get("actor_id", -1)),
		"card_uid":int(action.get("card_uid", -1)),
		"card_definition_id":get_id(),
	}


## 统计当前能够承受属性伤害的角色数量；该数量不足2时横置没有任何传导对象。
## 判定完全委托评估器的公开查询，卡牌文件不硬编码任何防具ID或属性免疫名单。
func _count_elemental_damage_capable_players(authoritative_snapshot: Dictionary, evaluator: Object) -> int:
	# 可承受属性伤害的角色数；只有存活、未离场且至少能被一种属性伤害命中的角色才计入。
	var capable_count: int = 0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；玩家ID用于委托评估器读取公开防具能力。
		var player: Dictionary = player_variant as Dictionary
		if evaluator.get_capable_damage_natures(authoritative_snapshot, int(player.get("player_id", -1))).is_empty():
			continue
		capable_count += 1
	return capable_count


## 计算目标横置收益的幅度倍率：只能承受单一属性伤害时按无名杀同一比例减半，公开防具放大该属性伤害时按防具倍率放大。
## 目标完全无法承受任何属性伤害时返回0，使该目标不产生任何横置收益。
func _get_target_chain_magnitude_multiplier(authoritative_snapshot: Dictionary, evaluator: Object, target_id: int) -> float:
	# 目标当前可承受的属性伤害类型；空集合表示该目标与连环收益无关。
	var capable_natures: Array[String] = evaluator.get_capable_damage_natures(authoritative_snapshot, target_id)
	if capable_natures.is_empty():
		return 0.0
	# 属性覆盖倍率；两种属性都能承受时连环完全有效，只能承受一种时按无名杀 0.45/0.9 的同一比例折半。
	var magnitude_multiplier: float = 1.0 if capable_natures.size() >= MIN_ELEMENTAL_DAMAGE_CAPABLE_COUNT else AI_SINGLE_NATURE_CHAIN_MULTIPLIER
	# 属性伤害放大；【藤甲】等公开防具提高属性伤害时，横置该角色的传导也会同步变痛。
	for nature: String in capable_natures:
		magnitude_multiplier *= maxf(evaluator.get_incoming_damage_multiplier(authoritative_snapshot, target_id, nature), 1.0)
	return magnitude_multiplier


## 复刻无名杀的横置目标否决：敌方不足2名且场上仍有未横置敌人时不再横置敌人，
## 友方不足2名且场上已有横置队友时不要解除这名唯一的传导导体。
## 差异说明：无名杀只用第一个目标触发整张牌的否决，本项目以整组合评分，因此对本动作的首个目标做同样判定。
func _should_veto_link_targets(authoritative_snapshot: Dictionary, evaluator: Object, action: Dictionary) -> bool:
	# 本动作声明的目标；空目标动作没有可否决的对象。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.is_empty():
		return false
	# 动作发起者与首个目标ID；首个目标决定整张牌是否值得使用。
	var actor_id: int = int(action.get("actor_id", -1))
	var first_target_id: int = int(target_ids[0])
	# 敌我计数与场上状态；只统计能够承受属性伤害的角色，与无名杀的 curs 集合保持一致。
	var enemy_count: int = 0
	var friend_count: int = 0
	var has_unlinked_enemy: bool = false
	var has_linked_friend: bool = false
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；免疫属性伤害的角色不构成传导对象，因此不参与敌我计数。
		var player: Dictionary = player_variant as Dictionary
		var player_id: int = int(player.get("player_id", -1))
		# 使用者本人不参与敌我计数；本项目对自身态度为固定的最高友方值，
		# 若把本人计入友方，任何局面都会得到至少1名友方，使“唯一友方导体”的判定失去意义。
		if player_id == actor_id:
			continue
		if evaluator.get_capable_damage_natures(authoritative_snapshot, player_id).is_empty():
			continue
		# 当前阵营态度与连环状态；态度为0的中立角色既不算敌方也不算友方。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, actor_id, player_id)
		var linked: bool = bool(player.get("chained", false))
		if attitude > 0.0:
			friend_count += 1
			if linked:
				has_linked_friend = true
		elif attitude < 0.0:
			enemy_count += 1
			if not linked:
				has_unlinked_enemy = true
	# 敌方已经足够多或场上没有未横置敌人时，本次使用不受该否决约束。
	if enemy_count >= AI_MIN_SAME_SIDE_COUNT_FOR_CHAIN or not has_unlinked_enemy:
		return false
	# 对敌方目标：只有一名敌人时横置它不产生传导价值，直接放弃本次使用。
	if evaluator.get_attitude(authoritative_snapshot, actor_id, first_target_id) <= 0.0:
		return true
	# 对友方目标：场上已有横置队友且友方不足2名时不要解除这名唯一的传导导体。
	return has_linked_friend and friend_count < AI_MIN_SAME_SIDE_COUNT_FOR_CHAIN
