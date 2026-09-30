extends SkillDefinition

## 【好活】欢愉技源码。阿哈时刻按参演编号120强制驱动：弃置场上的一张牌。
## “场上”按需求口径指所有角色的装备区与判定区，不包括任何角色的手牌区，且包含持有者自己的区域。
## 操作按两步交互实现：先由玩家选择一名场上（判定区或装备区）有牌的角色，再弃置其场上的一张牌。

## 弃置牌数量；固定1张，原文为“一张牌”。
const DISCARD_CARD_COUNT: int = 1

## 角色选择数量；固定1名，两步交互的第一步只允许选定一名场上有牌的角色。
const TARGET_COUNT: int = 1

## 第一步角色选择请求种类；确认后进入该角色的场上选牌窗口。
const TARGET_CHOICE_KIND: String = "haohuo_target"

## 第二步牌选择请求种类；恢复时按该值分流到结算入口。
const CARD_CHOICE_KIND: String = "haohuo_card"

## 角色选择窗口是否允许取消；固定false，欢愉技强制发动且必须选定一名场上有牌的角色。
const ALLOW_TARGET_CANCEL: bool = false

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

## AI：非法选牌或非法选人的评分；低于任何合法动作。
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


## 阿哈时刻的唯一执行入口第一步：请求玩家选择一名场上（装备区或判定区）有牌的角色。
func perform_joy_skill(_context: Dictionary) -> void:
	# 场上拥有可弃置牌的角色；由核心端口按权威座次顺序生成，并按需求口径排除所有手牌区。
	var target_ids: Array[int] = host.call("get_field_card_owner_ids", owner_player_id, true) as Array[int]
	if target_ids.is_empty():
		# 场上没有任何可弃置的牌时立即回报演出结束，避免阿哈时刻队列停在这一项。
		finish_joy_skill_performance()
		return
	request_target_selection("【好活】请选择一名场上有牌的角色", target_ids, TARGET_COUNT, TARGET_COUNT, ALLOW_TARGET_CANCEL, {"kind":TARGET_CHOICE_KIND})


## 恢复两步选择；窗口均不可取消，异常输入按没有合法内容处理，本次演出空过但仍回报结束。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；好活使用两个连续请求并共享同一技能实例恢复。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == TARGET_CHOICE_KIND:
		if not response.confirmed or response.target_ids.size() != TARGET_COUNT:
			finish_joy_skill_performance()
			return true
		# 已选角色；等待期间其场上牌可能已经全部离区，此时按本次演出空过收尾。
		_begin_field_card_selection(response.target_ids[0])
		return true
	if choice_kind != CARD_CHOICE_KIND:
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


## 进入第二步：为目标角色的场上牌创建选牌窗口；其场上已无牌时直接收尾结束本次演出。
func _begin_field_card_selection(target_id: int) -> void:
	# 目标角色场上候选；只含装备区与判定区，手牌区永远不进入候选。
	var candidates: Array[Dictionary] = _get_player_field_candidates(target_id)
	if candidates.is_empty():
		finish_joy_skill_performance()
		return
	# 第二步上下文携带第一步选定的角色ID；它只用于交互定位与日志排查，实际归属仍按UID重新定位。
	request_card_selection("好活", "请弃置该角色场上的一张牌", candidates, DISCARD_CARD_COUNT, DISCARD_CARD_COUNT, ALLOW_CARD_CANCEL, {"kind":CARD_CHOICE_KIND, "target_id":target_id})


## 返回指定角色装备区与判定区的权威候选；由核心端口统一完成废除栏位与保护技能过滤。
func _get_player_field_candidates(target_id: int) -> Array[Dictionary]:
	return host.call("get_player_field_candidates", owner_player_id, target_id) as Array[Dictionary]


## 在权威场上候选里按UID重新定位一张牌；找不到时返回空字典。
func _locate_field_card(card_uid: int) -> Dictionary:
	for candidate_variant: Variant in host.call("get_field_card_candidates", owner_player_id, true) as Array:
		# 当前场上候选；匹配稳定UID后返回其归属与区域。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) == card_uid:
			return candidate
	return {}


## 为AI评估好活的两步选择；两步共用同一套单牌收益口径，避免选出“实际没有好牌可弃”的角色。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理好活自身建立的两类选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 当前选择步骤；第一步选角色、第二步选牌。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind not in [TARGET_CHOICE_KIND, CARD_CHOICE_KIND]:
		return 0.0
	# 动作负载；好活必须选定一张牌或一名角色，未确认由权威端拒绝。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	if choice_kind == TARGET_CHOICE_KIND:
		# 已选角色；数量不等于1时判为无效动作。
		var selected_targets: Array = payload.get("selected_target_ids", []) as Array
		if selected_targets.size() != TARGET_COUNT:
			return AI_INVALID_CARD_SCORE
		return _score_target_field_cards(authoritative_snapshot, int(selected_targets[0]), evaluator)
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
	return _score_field_card(attitude, zone, definition_id, evaluator)


## 评估第一步选中的角色：从权威快照读取其场上牌，取其中收益最高的一张作为该角色的分。
## 两步必须共用同一套单牌收益口径，否则AI会在第一步选出“角色本身不错、但实际没有好牌可弃”的目标。
func _score_target_field_cards(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	# 目标角色快照；只读取公开的装备区与判定区，不使用任何私有的技能实例状态。
	var target: Dictionary = _find_snapshot_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return AI_INVALID_CARD_SCORE
	# 归属角色对持有者的态度；正值为友方。
	var attitude: float = float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id))
	# 最高单牌收益；遍历后仍为非法分表示该角色场上没有任何可弃置的牌。
	var best_score: float = AI_INVALID_CARD_SCORE
	# 判定区候选；判定区只存放延时锦囊，牌面定义用于识别延时锦囊类别。
	if not bool(target.get("judgment_area_abolished", false)):
		for judgment_variant: Variant in target.get("judgment_area", []) as Array:
			# 当前判定区牌；只读取公开牌面定义。
			var judgment_card: Dictionary = judgment_variant as Dictionary
			best_score = maxf(best_score, _score_field_card(attitude, JUDGMENT_ZONE, str(judgment_card.get("definition_id", "")), evaluator))
	# 装备区候选；已废除的栏位不参与评分，与核心候选口径保持一致。
	for slot_variant: Variant in (target.get("equipment", {}) as Dictionary).keys():
		# 当前装备槽；整区废除与单栏废除都必须与核心候选保持同一过滤结论。
		var slot: String = str(slot_variant)
		if bool((target.get("abolished_equipment_slots", {}) as Dictionary).get(slot, false)):
			continue
		# 当前槽位装备牌；只读取公开牌面定义。
		var equipment_card: Dictionary = (target.get("equipment", {}) as Dictionary).get(slot, {}) as Dictionary
		best_score = maxf(best_score, _score_field_card(attitude, EQUIPMENT_ZONE, str(equipment_card.get("definition_id", "")), evaluator))
	return best_score


## 计算一张场上牌的收益档；装备与判定区共用，选角色与选牌两步因此得到完全一致的口径。
## attitude 为牌的归属角色对持有者的态度，zone 为稳定区域名，definition_id 为卡牌定义ID。
func _score_field_card(attitude: float, zone: String, definition_id: String, evaluator: Object) -> float:
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


## 从权威快照读取指定玩家；不存在时返回空字典。
func _find_snapshot_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前遍历玩家快照；匹配稳定ID后原样返回只读字典。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}
