extends SkillDefinition

## 【泛音】技能源码。四个轮回节依次弃置黑桃、红桃、梅花、方块牌；
## 锁定后段在持有者弃置牌时整批判定“这些牌”的黑红组成，先执行黑色效果再执行红色效果。

## 四个轮回节依次要求弃置的花色；索引即零基轮回节序号，与描述中的①②③④一一对应。
const SECTION_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]

## 四个轮回节的花色显示名；仅用于询问提示与日志文本，顺序必须与 SECTION_SUITS 严格一致。
const SECTION_SUIT_NAMES: Array[String] = ["黑桃", "红桃", "梅花", "方块"]

## 视为“黑色牌”的花色；原文黑色效果由黑桃与梅花触发。
const BLACK_SUITS: Array[String] = ["spade", "club"]

## 视为“红色牌”的花色；原文红色效果由红桃与方块触发。
const RED_SUITS: Array[String] = ["heart", "diamond"]

## 黑色效果要求目标弃置的手牌数量；数值1来自技能原文“弃置一张手牌”。
const BLACK_DISCARD_COUNT: int = 1

## 红色效果让持有者摸取的牌数；数值1来自技能原文“你摸一张牌”。
const RED_DRAW_COUNT: int = 1

## 轮回节费用牌的选择业务类型；与锁定后段的两段选择共用同一技能实例，三者取值必须互不相同。
const SECTION_DISCARD_KIND: String = "fanyin_section_discard"

## 锁定后段黑色效果的目标角色选择业务类型。
const BLACK_TARGET_KIND: String = "fanyin_black_target"

## 锁定后段黑色效果中由目标本人选择弃置手牌的业务类型。
const BLACK_DISCARD_KIND: String = "fanyin_black_discard"

## 正在等待后续结算的弃置批次；键为权威批次号，值记录该批次是否还欠一次红色摸牌。
## 使用字典按键定位而非单个变量：黑色效果引发的弃置会同步产生新批次，两层批次必须各自完成互不覆盖。
var _pending_batches: Dictionary = {}


## 写入四轮回节主动技能静态信息；技能正文逐字保持设计原文，half_locked 标明“非锁定前段 + 锁定后段”的规则边界。
func _init() -> void:
	super({
		"id":"fanyin",
		"name":"泛音",
		"trigger":"active/cardsDiscardedBatchAfter",
		"enable":"phaseUse",
		"ui_enabled":true,
		"half_locked":true,
		"reincarnation":true,
		"reincarnation_section_count":4,
		"reincarnation_has_explicit_sections":true,
		"description":"轮回技，出牌阶段，你可弃置一张①黑桃②红桃③梅花④方块牌。锁定技，当你弃置牌时，若这些牌中有黑色牌，你令一名角色弃置一张手牌；若这些牌中有红色牌，你摸一张牌。",
	})


## 订阅弃置批次完成时机；locked_segment 为 true 保证“非锁定技失效”判定下锁定后段仍然生效。
func install() -> void:
	subscribe_timing("cardsDiscardedBatchAfter", _on_cards_discarded_batch, "player", 0, false, false, Callable(), true)


## 卸载时清空跨异步步骤的批次登记；时机订阅由基类统一解绑。
func uninstall() -> void:
	_pending_batches.clear()
	super()


## 检查出牌阶段、轮回额度与当前轮回节对应花色费用牌是否齐备。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or host.state.current_player_id != owner_player_id or host.state.current_phase != "play" or not can_activate_reincarnation():
		return false
	# 当前轮回节；只有存在对应花色费用牌时才开放入口，与既有轮回技费用节保持一致。
	return not _get_section_candidates(get_reincarnation_section_index()).is_empty()


## 读取直接动作中的费用牌或创建当前轮回节的花色选择请求。
func activate(context: Dictionary = {}) -> String:
	if not can_activate():
		return "【泛音】当前轮回节没有对应花色的费用牌。"
	# 当前轮回节；动作提交与选择标题均以本次快照为准。
	var section_index: int = get_reincarnation_section_index()
	# 直接提交的费用牌UID；基础AI动作携带该字段，人类动作通常进入选择窗口。
	var card_uid: int = int(context.get("card_uid", -1))
	if card_uid >= 0:
		return "" if _execute_section(card_uid, section_index) else "【泛音】所选的费用牌已经失效。"
	request_card_selection("泛音", "请选择一张%s牌弃置" % SECTION_SUIT_NAMES[section_index], _get_section_candidates(section_index), 1, 1, true, {"kind":SECTION_DISCARD_KIND, "section_index":section_index})
	return ""


## 恢复轮回节费用选择或锁定后段的逐步选择；取消不会推进轮回节，也不会吞掉待结算的黑红效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 选择业务类型；本技能共有三段选择，必须按 kind 分派防止旧响应进入错误分支。
	var kind: String = str(context.get("kind", ""))
	if kind == SECTION_DISCARD_KIND:
		if response.confirmed and response.card_ids.size() == 1:
			_execute_section(response.card_ids[0], int(context.get("section_index", -1)))
		return true
	if kind == BLACK_TARGET_KIND:
		if response.confirmed and response.target_ids.size() == 1:
			_request_black_discard(int(context.get("batch_id", -1)), response.target_ids[0])
		else:
			_finish_batch(int(context.get("batch_id", -1)))
		return true
	if kind == BLACK_DISCARD_KIND:
		if response.confirmed and response.card_ids.size() == 1:
			# 黑色效果目标；等待期间该角色可能已死亡或手牌被清空，只有实际弃置成功才记录发动。
			var black_target_id: int = int(context.get("target_id", -1))
			if int(host.call("discard_selected_hand_cards", black_target_id, _int_array(response.card_ids))) > 0:
				announce_activation({"effect":"black", "target_id":black_target_id, "discard_batch_id":int(context.get("batch_id", -1))})
		_finish_batch(int(context.get("batch_id", -1)))
		return true
	return false


## 支付当前轮回节的一张对应花色牌；费用实际弃置成功后才记录发动并推进轮回。
func _execute_section(card_uid: int, expected_section_index: int) -> bool:
	if not can_activate() or get_reincarnation_section_index() != expected_section_index or not _candidate_uids(_get_section_candidates(expected_section_index)).has(card_uid) or not begin_reincarnation_activation():
		return false
	# 单张费用UID数组；显式强类型保证动态控制器调用与公开端口签名一致。
	var selected_uids: Array[int] = [card_uid]
	if int(host.call("discard_selected_hand_equipment", owner_player_id, selected_uids)) != 1:
		return false
	announce_activation({"section_number":expected_section_index + 1, "round_count":get_reincarnation_round_count(), "discarded_card_uid":card_uid})
	complete_reincarnation_activation()
	return true


## 锁定后段入口；把一次弃置动作的全部牌整体判定黑红，并永远先结算黑色效果再结算红色效果。
func _on_cards_discarded_batch(event: RuleEvent) -> void:
	if event == null:
		return
	# 技能持有者；死亡或离场后锁定后段不再生效，但已登记的批次仍会由对应分支收尾。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 本批次是否含黑色牌；只要有一张黑桃或梅花即成立。
	var has_black: bool = false
	# 本批次是否含红色牌；只要有一张红桃或方块即成立。
	var has_red: bool = false
	for card_uid: int in _int_array(event.data.get("card_uids", []) as Array):
		# 本次弃置实体当前花色；已离开弃牌堆的牌无法回查，按 none 处理而不臆测颜色。
		var suit: String = _resolve_discarded_suit(card_uid)
		if BLACK_SUITS.has(suit):
			has_black = true
		elif RED_SUITS.has(suit):
			has_red = true
	if not has_black and not has_red:
		return
	# 批次稳定标识；同一批次内黑色效果引发的弃置会生成新批次号，因此两条登记互不覆盖。
	var batch_id: int = int(event.data.get("discard_batch_id", -1))
	_pending_batches[batch_id] = {"has_red":has_red}
	if has_black and not _get_black_target_ids().is_empty():
		request_target_selection("【泛音】请选择一名角色弃置一张手牌", _get_black_target_ids(), 1, 1, false, {"kind":BLACK_TARGET_KIND, "batch_id":batch_id})
		return
	_finish_batch(batch_id)


## 请求黑色效果目标本人选择要弃置的手牌；目标手牌在等待期间已空时直接进入红色收尾。
func _request_black_discard(batch_id: int, target_id: int) -> void:
	# 目标手牌候选；选择者只能看见并交出自己普通手牌区的牌，不包含装备或木牛“粮”。
	var candidates: Array[Dictionary] = host.call("get_hand_candidates", target_id, target_id) as Array[Dictionary]
	if candidates.is_empty():
		_finish_batch(batch_id)
		return
	# 目标手牌中的红色牌UID；供AI在被迫自弃时优先交出可通过红色效果摸回的牌。
	var red_card_uids: Array[int] = []
	for candidate: Dictionary in candidates:
		if str(((candidate.get("card_data", {}) as Dictionary).get("suit", "none"))) in RED_SUITS:
			red_card_uids.append(int(candidate.get("uid", -1)))
	request_card_selection_for_player(target_id, "泛音", "请选择一张手牌弃置", candidates, 1, 1, false, {"kind":BLACK_DISCARD_KIND, "batch_id":batch_id, "target_id":target_id, "red_card_uids":red_card_uids})


## 收尾一个批次：紧跟黑色效果之后结算该批次欠下的红色摸牌；顺序由登记时的有无红色决定。
func _finish_batch(batch_id: int) -> void:
	if not _pending_batches.has(batch_id):
		return
	# 该批次的待结算内容；先取出并从登记表移除，避免黑色效果引发的弃置回头重复结算本批红色。
	var pending: Dictionary = _pending_batches[batch_id] as Dictionary
	_pending_batches.erase(batch_id)
	if not bool(pending.get("has_red", false)):
		return
	# 红色效果结算者；以当前持有者为准，避免等待期间换将后把摸牌发给旧角色。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	host.call("draw", owner_player_id, RED_DRAW_COUNT)
	announce_activation({"effect":"red", "round_count":get_reincarnation_round_count(), "draw_count":RED_DRAW_COUNT, "discard_batch_id":batch_id})


## 返回持有者手牌区与装备区中当前轮回节要求花色的候选；公开花色由持有者本人查看。
func _get_section_candidates(section_index: int) -> Array[Dictionary]:
	# 过滤结果；起手先排除越界节号，避免索引到花色表之外。
	var result: Array[Dictionary] = []
	if section_index < 0 or section_index >= SECTION_SUITS.size():
		return result
	# 当前轮回节要求花色；只有该花色的牌可以支付本轮回节费用。
	var required_suit: String = SECTION_SUITS[section_index]
	for candidate: Dictionary in host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]:
		if str(((candidate.get("card_data", {}) as Dictionary).get("suit", "none"))) == required_suit:
			result.append(candidate.duplicate(true))
	return result


## 返回全部存活在场且手中仍有牌的角色；原文“一名角色”不限阵营，故包含持有者本人与队友。
func _get_black_target_ids() -> Array[int]:
	# 目标结果；按座位顺序输出，保证AI枚举稳定。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player != null and player.alive and not player.out_of_game and not player.hand.is_empty():
			result.append(player.player_id)
	return result


## 按UID在弃牌堆回查实体花色；牌已不在弃牌堆时返回none，绝不按牌名猜测颜色。
func _resolve_discarded_suit(card_uid: int) -> String:
	for discarded_card: CardInstance in host.state.discard_pile:
		if discarded_card != null and discarded_card.uid == card_uid:
			return discarded_card.suit
	return "none"


## 从选择候选提取稳定UID数组；等待期间最终弃置仍会再次复核实体位置。
func _candidate_uids(candidates: Array[Dictionary]) -> Array[int]:
	# UID结果；保持候选顺序供AI稳定枚举。
	var result: Array[int] = []
	for candidate: Dictionary in candidates:
		result.append(int(candidate.get("uid", -1)))
	return result


## 把弱类型数组收敛为整数数组；动作与响应输入共用该防御性转换。
func _int_array(values: Array) -> Array[int]:
	# 转换结果；保留原顺序，由最终规则判断数量。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result


## 为AI枚举当前轮回节中每一张合法花色费用牌；无合法费用时不追加动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for candidate: Dictionary in _get_section_candidates(get_reincarnation_section_index()):
		# 当前费用牌UID；动作只携带稳定ID，不持有牌对象。
		var card_uid: int = int(candidate.get("uid", -1))
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "card_uid":card_uid, "payload":{"skill_id":get_id(), "card_uid":card_uid}})


## AI按“优先弃置自己没用的牌”评估主动动作：牌价值越低，触发锁定后段的相对收益越高。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 费用牌UID；评分只读取快照与动作，不修改轮回状态。
	var card_uid: int = int(action.get("card_uid", (action.get("payload", {}) as Dictionary).get("card_uid", -1)))
	return 6.0 - evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, card_uid) * 0.45


## AI评估泛音三段交互：费用牌偏好低价值，黑色目标偏好敌方，被迫自弃时偏好能摸回的红色牌。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理泛音自身建立的三类选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 动作负载；取消保持0分。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 选择业务类型；与 continue_selection 使用同一组稳定值。
	var kind: String = str(context.get("kind", ""))
	if kind == SECTION_DISCARD_KIND:
		var section_card_uids: Array = payload.get("selected_card_uids", []) as Array
		if section_card_uids.size() != 1:
			return -20.0
		return 6.0 - evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(section_card_uids[0])) * 0.45
	if kind == BLACK_TARGET_KIND:
		var selected_targets: Array = payload.get("selected_target_ids", []) as Array
		if selected_targets.size() != 1:
			return -20.0
		return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, int(selected_targets[0]), -BLACK_DISCARD_COUNT, 0) + 2.0
	if kind == BLACK_DISCARD_KIND:
		var discard_card_uids: Array = payload.get("selected_card_uids", []) as Array
		if discard_card_uids.size() != 1:
			return -20.0
		# 红色牌被弃置后仍会通过锁定后段摸回一张，因此场上无人可弃而必须自弃时优先交出红色牌。
		var red_card_uids: Array = context.get("red_card_uids", []) as Array
		return 2.0 if red_card_uids.has(int(discard_card_uids[0])) else 0.1
	return 0.0
