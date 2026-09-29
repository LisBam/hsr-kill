extends SkillDefinition

## 【好戏】欢愉技源码。阿哈时刻按参演编号144驱动：先令至多两名其他角色各弃置一张随机手牌，再从摸牌堆中获得X张基本牌。

## 可选其他角色数量下限；固定0，对应原文“0-2名”，此时X取2张基本牌。
const MIN_TARGET_COUNT: int = 0

## 可选其他角色数量上限；固定2，与技能原文一致。
const MAX_TARGET_COUNT: int = 2

## 基本牌获得数量的计算基数；原文“X为2-本次选择的目标数”，因此X=基数-目标数。
const BASIC_DRAW_BASE: int = 2

## 目标选择请求种类；恢复时按该值分流到结算入口。
const TARGET_CHOICE_KIND: String = "haoxi_targets"

## 随机弃置手牌的随机历史种类；固定kind便于测试与复盘检索，与获得牌分开记录。
const RANDOM_DISCARD_HISTORY_KIND: String = "haoxi_random_hand_discard"

## 随机获得基本牌的随机历史种类；与弃置分开，便于分别复现两步各自的随机流。
const RANDOM_GAIN_HISTORY_KIND: String = "haoxi_gain_basic"

## AI：一张确定基本牌的估值；与统一资源尺度的一牌价值保持一致。
const AI_BASIC_DRAW_VALUE: float = NonameAIEvaluator.CARD_RESOURCE_VALUE

## AI：令一名其他角色随机失去一张未知手牌的估值；使用未知牌等效价值。
const AI_DISCARDED_HAND_VALUE: float = NonameAIEvaluator.RECAST_DRAW_VALUE


## 写入欢愉技静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"haoxi",
		"name":"好戏",
		"trigger":"passive",
		"joy_skill":true,
		"performance_number":144,
		"description":"欢愉技，参演编号144，你可弃置0-2名其他角色各一张随机手牌，然后从牌堆中获得X张基本牌。（X为2-本次选择的目标数）",
	})


## 阿哈时刻的唯一执行入口：先选择0至2名其他角色，再依次完成弃置与获得。
func perform_joy_skill(context: Dictionary) -> void:
	# 直接动作目标；由调试或回放入口显式给出时跳过选择窗口，正常演出路径不携带该字段。
	var direct_target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		direct_target_ids.append(int(target_variant))
	if context.has("target_ids"):
		_execute_haoxi(direct_target_ids)
		return
	# 可作为弃置目标的其他角色；必须有普通手牌，否则“各一张随机手牌”无从结算。
	var candidate_target_ids: Array[int] = _get_discardable_target_ids()
	if candidate_target_ids.is_empty():
		# 没有可弃置目标时直接按X=2结算，保证技能仍然完整演出而不是被静默跳过。
		_execute_haoxi([])
		return
	request_target_selection("【好戏】请选择0至2名其他角色各弃置一张随机手牌", candidate_target_ids, MIN_TARGET_COUNT, mini(MAX_TARGET_COUNT, candidate_target_ids.size()), true, {"kind":TARGET_CHOICE_KIND})


## 恢复目标选择；未确认表示放弃弃置，按0名目标结算并继续获得基本牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	if str(context.get("kind", "")) != TARGET_CHOICE_KIND:
		return false
	# 已确认目标列表；未确认时为空，对应X取最大值。
	var selected_target_ids: Array[int] = []
	if response.confirmed:
		selected_target_ids = response.target_ids
	_execute_haoxi(selected_target_ids)
	return true


## 结算好戏：逐名目标随机弃置一张手牌，再按X从摸牌堆无放回获得基本牌，最后回报演出结束。
func _execute_haoxi(selected_target_ids: Array[int]) -> void:
	# 实际参与弃置的其他角色；等待期间死亡、离场或已经没有手牌的目标被剔除。
	# 该名单只影响“谁被弃置”，不影响X：原文明确X按“本次选择的目标数”计算。
	var valid_target_ids: Array[int] = []
	for target_id: int in selected_target_ids:
		# 当前目标角色；必须仍是存活在场的其他角色且至少持有一张普通手牌。
		var target: PlayerState = host.state.get_player(target_id) if host != null and host.get("state") != null else null
		if target == null or target.player_id == owner_player_id or not target.alive or target.out_of_game or target.hand.is_empty():
			continue
		if valid_target_ids.has(target_id):
			continue
		valid_target_ids.append(target_id)
	# 实际被弃置的实体UID；逐名目标独立等概率抽取，随机历史记录候选规模与命中下标。
	var discarded_card_uids: Array[int] = []
	for target_id: int in valid_target_ids:
		# 目标手牌；抽取前重新读取，保证读取的是当前真实手牌而不是过期快照。
		var target_player: PlayerState = host.state.get_player(target_id)
		var picked_index: int = int(host.call("pick_random_candidate_index", target_player.hand.size(), RANDOM_DISCARD_HISTORY_KIND, {"player_id":owner_player_id, "target_id":target_id}))
		if picked_index < 0:
			continue
		# 选中的实体牌；弃置走统一端口，因此装备离开、保护规则与动画逻辑全部沿用既有实现。
		var picked_uid: int = target_player.hand[picked_index].uid
		var single_card_uids: Array[int] = [picked_uid]
		if int(host.call("discard_selected_player_cards", target_id, single_card_uids, owner_player_id)) <= 0:
			continue
		discarded_card_uids.append(picked_uid)
	# X = 2 - 本次选择的目标数；按选择数而非实际弃置数计算，避免目标中途失效反而多摸牌。
	var basic_draw_count: int = maxi(BASIC_DRAW_BASE - selected_target_ids.size(), 0)
	announce_activation({
		"target_ids":selected_target_ids.duplicate(),
		"discarded_target_ids":valid_target_ids.duplicate(),
		"discarded_card_uids":discarded_card_uids,
		"basic_draw_count":basic_draw_count,
	})
	_gain_random_basic_cards(basic_draw_count)
	finish_joy_skill_performance()


## 从摸牌堆中无放回随机获得指定数量的基本牌；牌堆内基本牌不足时按现有数量获得。
func _gain_random_basic_cards(draw_count: int) -> void:
	if draw_count <= 0:
		return
	# 摸牌堆中仍属于基本牌的实体UID；需求要求“从牌堆中获得”，因此只检索摸牌堆，不检索弃牌堆。
	var basic_card_uids: Array[int] = []
	for pile_card: CardInstance in host.state.draw_pile:
		if _is_basic_card(pile_card.definition_id):
			basic_card_uids.append(pile_card.uid)
	# 逐张无放回抽取；每抽取一张就从候选中移除，保证不会重复获得同一实体。
	for draw_index: int in range(draw_count):
		if basic_card_uids.is_empty():
			break
		var picked_index: int = int(host.call("pick_random_candidate_index", basic_card_uids.size(), RANDOM_GAIN_HISTORY_KIND, {"player_id":owner_player_id, "draw_index":draw_index}))
		if picked_index < 0:
			break
		var picked_uid: int = basic_card_uids[picked_index]
		basic_card_uids.remove_at(picked_index)
		host.call("gain_draw_pile_card_by_uid", owner_player_id, picked_uid, get_id())


## 判断卡牌定义是否属于基本牌；只读取静态类型，不读取当前牌名设置。
func _is_basic_card(definition_id: String) -> bool:
	return str(GameDatabase.get_card(definition_id).get("type", "")) == "basic"


## 返回当前可作为弃置目标的其他角色稳定玩家ID；必须存活在场且至少持有一张普通手牌。
func _get_discardable_target_ids() -> Array[int]:
	# 目标结果；保持权威座次顺序，界面、AI与回放据此稳定复现。
	var target_ids: Array[int] = []
	if host == null or host.get("state") == null:
		return target_ids
	for player: PlayerState in host.state.players:
		if player.player_id != owner_player_id and player.alive and not player.out_of_game and not player.hand.is_empty():
			target_ids.append(player.player_id)
	return target_ids


## 为AI评估好戏的目标选择动作；先按X取基本牌收益，再按敌我逐一加减弃置收益。
##
## 动作分数有意使用统一资源尺度：X张基本牌按 CARD_RESOURCE_VALUE 计，
## 每名敌方目标随机失去一张未知手牌按 RECAST_DRAW_VALUE 计，因此
## “弃置两名敌人并放弃两张基本牌”会稳定高于“不弃置而取两张基本牌”，
## 与需求用X换取干扰的设计意图一致；友方目标按同样数值反向计入，避免AI误伤队友。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理好戏的目标选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != TARGET_CHOICE_KIND:
		return 0.0
	# 动作负载；未确认等价于不弃置任何角色，此时X取最大值。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return float(BASIC_DRAW_BASE) * AI_BASIC_DRAW_VALUE
	# 已选目标；超出上限或包含自己的动作由权威端拒绝，AI不应主动提交。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if selected_targets.size() > MAX_TARGET_COUNT:
		return -20.0
	# X收益；每多选一名目标就少获得一张基本牌。
	var total_score: float = float(maxi(BASIC_DRAW_BASE - selected_targets.size(), 0)) * AI_BASIC_DRAW_VALUE
	for target_variant: Variant in selected_targets:
		# 当前目标ID；自己不是合法对象，出现即判为无效动作。
		var target_id: int = int(target_variant)
		if target_id == owner_player_id:
			return -20.0
		# 态度；令敌方失去手牌是收益，令友方失去手牌按同等数值的负收益计入。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		if attitude < 0.0:
			total_score += AI_DISCARDED_HAND_VALUE
		elif attitude > 0.0:
			total_score -= AI_DISCARDED_HAND_VALUE
	return total_score
