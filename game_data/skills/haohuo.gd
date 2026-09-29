extends SkillDefinition

## 【好活】欢愉技源码。阿哈时刻按参演编号120强制驱动：弃置场上的一张牌。
## “场上”按需求口径指所有角色的装备区与判定区，不包括任何角色的手牌区，且包含持有者自己的区域。

## 弃置牌数量；固定1张，原文为“一张牌”。
const DISCARD_CARD_COUNT: int = 1

## 牌选择请求种类；恢复时按该值分流到结算入口。
const CARD_CHOICE_KIND: String = "haohuo_card"

## 牌选择窗口是否允许取消；固定false，欢愉技强制发动且必须选定一张场上的牌。
const ALLOW_CARD_CANCEL: bool = false

## 判定区区域名；与核心候选序列化使用的稳定区域名一致。
const JUDGMENT_ZONE: String = "judgment"

## 装备区区域名；与核心候选序列化使用的稳定区域名一致。
const EQUIPMENT_ZONE: String = "equipment"

## AI：我方判定区牌的价值上限档；清掉自己人的延时锦囊是最高收益。
const AI_ALLY_JUDGMENT_VALUE: float = 9.0

## AI：敌方装备区牌的收益档；拆掉敌人的装备次之。
const AI_HOSTILE_EQUIPMENT_VALUE: float = 6.0

## AI：其余场上牌的基础收益档；保证AI在只有普通场上牌时仍然愿意发动。
const AI_DEFAULT_FIELD_CARD_VALUE: float = 1.0

## AI：判定“我方”的态度下界；态度不小于该值的角色视为友方。
const AI_ALLY_ATTITUDE_THRESHOLD: float = 0.0

## AI：非法选牌的评分；低于任何合法动作。
const AI_INVALID_CARD_SCORE: float = -20.0


## 写入欢愉技静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"haohuo",
		"name":"好活",
		"trigger":"passive",
		"joy_skill":true,
		"performance_number":120,
		"description":"欢愉技，参演编号120，你弃置场上的一张牌。",
	})


## 阿哈时刻的唯一执行入口：从全部角色的装备区与判定区中弃置一张牌。
func perform_joy_skill(_context: Dictionary) -> void:
	# 场上候选；由核心端口按装备槽顺序与判定区顺序生成，并按需求口径排除所有手牌区。
	var candidates: Array[Dictionary] = host.call("get_field_card_candidates", owner_player_id, true) as Array[Dictionary]
	if candidates.is_empty():
		# 场上没有任何可弃置的牌时立即回报演出结束，避免阿哈时刻队列停在这一项。
		finish_joy_skill_performance()
		return
	request_card_selection("好活", "请弃置场上的一张牌", candidates, DISCARD_CARD_COUNT, DISCARD_CARD_COUNT, ALLOW_CARD_CANCEL, {"kind":CARD_CHOICE_KIND})


## 恢复牌选择；窗口不可取消，异常输入按没有合法牌处理，本次演出空过但仍回报结束。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != CARD_CHOICE_KIND or response == null:
		return false
	if not response.confirmed or response.card_ids.size() != DISCARD_CARD_COUNT:
		finish_joy_skill_performance()
		return true
	# 已选场上牌；按UID在权威候选里重新定位归属角色，避免等待期间区域变化导致误弃。
	var selected_uid: int = response.card_ids[0]
	var located: Dictionary = _locate_field_card(selected_uid)
	if located.is_empty():
		finish_joy_skill_performance()
		return true
	# 牌的归属角色与所在区域；只用于公告与日志，实际移动一律由核心端口二次校验。
	var target_owner_id: int = int(located.get("owner_id", -1))
	var zone: String = str(located.get("zone", ""))
	announce_activation({"target_id":target_owner_id, "card_uid":selected_uid, "zone":zone})
	host.call("discard_selected_player_card", owner_player_id, target_owner_id, selected_uid)
	finish_joy_skill_performance()
	return true


## 在权威场上候选里按UID重新定位一张牌；找不到时返回空字典。
func _locate_field_card(card_uid: int) -> Dictionary:
	for candidate_variant: Variant in host.call("get_field_card_candidates", owner_player_id, true) as Array:
		# 当前场上候选；匹配稳定UID后返回其归属与区域。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) == card_uid:
			return candidate
	return {}


## 为AI评估好活的选牌；按“我方判定区延时锦囊 → 敌方装备 → 其余场上牌”的需求口径给分。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理好活的选牌。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CARD_CHOICE_KIND:
		return 0.0
	# 动作负载；好活必须选定一张牌，未确认或数量不符由权威端拒绝。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选牌；数量不等于1时判为无效动作。
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.size() != DISCARD_CARD_COUNT:
		return AI_INVALID_CARD_SCORE
	# 候选条目；从请求自带的候选集合中读取区域与归属，不额外查询权威状态。
	var candidate: Dictionary = _find_request_candidate(choice_request, int(selected_cards[0]))
	if candidate.is_empty():
		return AI_INVALID_CARD_SCORE
	# 牌的归属角色、所在区域与卡牌定义；三者共同决定收益档位。
	var owner_id: int = int(candidate.get("owner_id", -1))
	var zone: String = str(candidate.get("zone", ""))
	var definition_id: String = str((candidate.get("card_data", {}) as Dictionary).get("definition_id", ""))
	# 归属角色对持有者的态度；正值为友方。
	var attitude: float = float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, owner_id))
	# 最高收益档：我方判定区里的延时锦囊；按delayed标签判定类别而不是匹配具体牌名。
	if zone == JUDGMENT_ZONE and attitude > AI_ALLY_ATTITUDE_THRESHOLD and bool(evaluator.is_delayed_trick_definition(definition_id)):
		return AI_ALLY_JUDGMENT_VALUE
	# 次高收益档：敌方装备区里的牌。
	if zone == EQUIPMENT_ZONE and attitude <= AI_ALLY_ATTITUDE_THRESHOLD:
		return AI_HOSTILE_EQUIPMENT_VALUE
	return AI_DEFAULT_FIELD_CARD_VALUE


## 从选择请求自带的候选集合中取出一条候选；不存在时返回空字典。
func _find_request_candidate(choice_request: Dictionary, card_uid: int) -> Dictionary:
	for candidate_variant: Variant in choice_request.get("candidates", []) as Array:
		# 当前请求候选；匹配稳定UID后原样返回只读字典。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) == card_uid:
			return candidate
	return {}
