extends SkillDefinition

## 【堪杀】技能源码。三个轮回节依次弃置红牌、弃置黑牌或对其他角色造成1点伤害，每节每出牌阶段限一次。

## 弃置红色牌所在的①轮回节零基索引；固定0对应玩家可见的①。
const RED_DISCARD_SECTION_INDEX: int = 0

## 弃置黑色牌所在的②轮回节零基索引；固定1对应玩家可见的②。
const BLACK_DISCARD_SECTION_INDEX: int = 1

## 造成伤害所在的③轮回节零基索引；固定2对应玩家可见的③。
const DAMAGE_SECTION_INDEX: int = 2

## ③轮回节对目标造成的固定普通伤害；数值1来自技能原文。
const DAMAGE_AMOUNT: int = 1


## 写入三轮回节主动技能静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"kansha",
		"name":"堪杀",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"reincarnation":true,
		"reincarnation_section_count":3,
		"reincarnation_has_explicit_sections":true,
		"reincarnation_each_section_once_per_play_phase":true,
		"description":"轮回技，出牌阶段每个轮回节限一次，你可①弃置一张红色牌；②弃置一张黑色牌；③对一名其他角色造成1点伤害。",
	})


## 按当前轮回节检查阶段、通用额度、颜色费用或伤害目标是否存在。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or host.state.current_player_id != owner_player_id or host.state.current_phase != "play" or not can_activate_reincarnation():
		return false
	# 当前轮回节；①②需要对应颜色牌，③需要至少一名其他存活目标。
	var section_index: int = get_reincarnation_section_index()
	if section_index == RED_DISCARD_SECTION_INDEX:
		return not _get_color_candidates("red").is_empty()
	if section_index == BLACK_DISCARD_SECTION_INDEX:
		return not _get_color_candidates("black").is_empty()
	return section_index == DAMAGE_SECTION_INDEX and not _get_damage_target_ids().is_empty()


## 读取直接动作中的牌或目标并执行；缺失参数时创建与当前轮回节对应的统一选择请求。
func activate(context: Dictionary = {}) -> String:
	if not can_activate():
		return "【堪杀】当前轮回节没有合法费用或目标。"
	# 当前轮回节；动作提交与选择标题均以本次快照为准。
	var section_index: int = get_reincarnation_section_index()
	if section_index in [RED_DISCARD_SECTION_INDEX, BLACK_DISCARD_SECTION_INDEX]:
		# 直接提交的费用牌UID；基础AI动作携带该字段，人类动作通常进入选择窗口。
		var card_uid: int = int(context.get("card_uid", -1))
		if card_uid >= 0:
			return "" if _execute_discard_section(card_uid, section_index) else "【堪杀】所选颜色牌已经失效。"
		# 当前要求颜色；供候选过滤、提示与恢复上下文复核。
		var required_color: String = "red" if section_index == RED_DISCARD_SECTION_INDEX else "black"
		request_card_selection("堪杀", "请选择一张%s牌弃置" % ("红色" if required_color == "red" else "黑色"), _get_color_candidates(required_color), 1, 1, true, {"kind":"kansha_discard", "section_index":section_index, "required_color":required_color})
		return ""
	# ③直接目标；必须保持唯一其他角色。
	var target_ids: Array[int] = _int_array(context.get("target_ids", []) as Array)
	if target_ids.size() == 1:
		return "" if _execute_damage_section(target_ids[0]) else "【堪杀】的伤害目标已经失效。"
	request_target_selection("【堪杀】请选择伤害目标", _get_damage_target_ids(), 1, 1, true, {"kind":"kansha_damage"})
	return ""


## 恢复①②费用牌或③伤害目标选择；取消不会推进轮回节。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 选择业务类型；只消费堪杀自身建立的两类请求。
	var kind: String = str(context.get("kind", ""))
	if kind == "kansha_discard":
		if response.confirmed and response.card_ids.size() == 1:
			_execute_discard_section(response.card_ids[0], int(context.get("section_index", -1)))
		return true
	if kind == "kansha_damage":
		if response.confirmed and response.target_ids.size() == 1:
			_execute_damage_section(response.target_ids[0])
		return true
	return false


## 支付当前①或②的一张对应颜色牌；费用实际弃置成功后才记录发动并推进轮回。
func _execute_discard_section(card_uid: int, expected_section_index: int) -> bool:
	if not can_activate() or get_reincarnation_section_index() != expected_section_index or not _candidate_uids(_get_color_candidates("red" if expected_section_index == RED_DISCARD_SECTION_INDEX else "black")).has(card_uid) or not begin_reincarnation_activation():
		return false
	# 单张费用UID数组；显式强类型保证动态控制器调用与公开端口签名一致。
	var selected_uids: Array[int] = [card_uid]
	if int(host.call("discard_selected_hand_equipment", owner_player_id, selected_uids)) != 1:
		return false
	announce_activation({"section_number":expected_section_index + 1, "round_count":get_reincarnation_round_count(), "discarded_card_uid":card_uid})
	complete_reincarnation_activation()
	return true


## 执行③固定1点普通伤害；目标与轮回状态最终复核后才推进。
func _execute_damage_section(target_id: int) -> bool:
	if not can_activate() or get_reincarnation_section_index() != DAMAGE_SECTION_INDEX or not _get_damage_target_ids().has(target_id) or not begin_reincarnation_activation():
		return false
	get_owner_skill_player().damage(DAMAGE_AMOUNT, get_skill_player(target_id))
	announce_activation({"section_number":DAMAGE_SECTION_INDEX + 1, "round_count":get_reincarnation_round_count(), "target_id":target_id, "target_ids":[target_id], "damage":DAMAGE_AMOUNT})
	observe_identity_behavior([target_id], {"target_result":-1.0, "damage":true})
	complete_reincarnation_activation()
	return true


## 返回持有者手牌区与装备区中指定颜色的公开候选；红色为红桃/方片，黑色为黑桃/梅花。
func _get_color_candidates(required_color: String) -> Array[Dictionary]:
	# 过滤结果；候选牌面由持有者本人查看，因此包含真实花色供颜色判断。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]:
		# 当前候选花色；不存在或none不属于红黑任一颜色。
		var suit: String = str(((candidate.get("card_data", {}) as Dictionary).get("suit", "none")))
		# 当前候选的红黑颜色；非四种实体花色统一记为none并被过滤。
		var color: String = "red" if suit in ["heart", "diamond"] else ("black" if suit in ["spade", "club"] else "none")
		if color == required_color:
			result.append(candidate.duplicate(true))
	return result


## 返回除持有者外全部存活在场角色，供③目标选择。
func _get_damage_target_ids() -> Array[int]:
	return host.call("get_other_alive_player_ids", owner_player_id) as Array[int]


## 从选择候选提取稳定UID数组；等待期间最终弃置仍会再次复核实体位置。
func _candidate_uids(candidates: Array[Dictionary]) -> Array[int]:
	# UID结果；保持候选顺序供AI稳定枚举。
	var result: Array[int] = []
	for candidate: Dictionary in candidates:
		result.append(int(candidate.get("uid", -1)))
	return result


## 为AI按当前轮回节枚举每张合法颜色费用牌或每名伤害目标。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	# 当前轮回节；①②枚举牌，③枚举目标。
	var section_index: int = get_reincarnation_section_index()
	if section_index in [RED_DISCARD_SECTION_INDEX, BLACK_DISCARD_SECTION_INDEX]:
		# 当前所需颜色；与权威费用执行使用同一过滤器。
		var required_color: String = "red" if section_index == RED_DISCARD_SECTION_INDEX else "black"
		for candidate: Dictionary in _get_color_candidates(required_color):
			# 当前费用牌UID；动作只携带稳定ID，不持有牌对象。
			var card_uid: int = int(candidate.get("uid", -1))
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "card_uid":card_uid, "payload":{"skill_id":get_id(), "card_uid":card_uid}})
		return
	for target_id: int in _get_damage_target_ids():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id]}})


## AI在①②倾向弃置低价值牌以推进至伤害节，③按统一伤害资源收益选择目标。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 当前轮回节；评分时动作来自同一帧合法枚举，不修改轮回状态。
	var section_index: int = get_reincarnation_section_index()
	if section_index in [RED_DISCARD_SECTION_INDEX, BLACK_DISCARD_SECTION_INDEX]:
		# 费用牌价值；低价值牌成本更低，同时给予轮回推进固定收益以实现“不打伤害也可弃牌”。
		var card_uid: int = int(action.get("card_uid", (action.get("payload", {}) as Dictionary).get("card_uid", -1)))
		return 6.0 - evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, card_uid) * 0.45
	# ③目标；敌方受1点伤害通常为正收益，友方为负收益。
	var target_ids: Array = action.get("target_ids", []) as Array
	return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, int(target_ids[0]), 0, -DAMAGE_AMOUNT) + 2.0 if target_ids.size() == 1 else -100.0


## 把弱类型数组收敛为整数数组；动作与网络输入共用该防御性转换。
func _int_array(values: Array) -> Array[int]:
	# 转换结果；保留原顺序，由最终技能规则判断数量。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result
