extends SkillDefinition

## 【解构】技能源码。出牌阶段可重铸一张非延时锦囊牌，然后若该牌牌名未被记录则记录之。
## 记录写入持有者的公开容器，供【灵感】选择与【看破】条件判定读取。
##
## 可重铸与可记录是两个不同范围：【无懈可击】属于非延时锦囊，因此**可以被重铸**，
## 但它是响应类锦囊而不是普通锦囊，**不能被记录**，从而不会进入【灵感】的视为使用候选。

## 可重铸的卡牌大类；只有锦囊牌。响应类锦囊同样满足本条件。
const RECASTABLE_TYPE: String = "trick"

## 可记录的锦囊子类；只有普通锦囊进入记录容器，响应类锦囊（counter）被排除。
const RECORDABLE_SUBTYPE: String = "normal"

## 选牌请求类别；用于在恢复回调中区分本技能自己的请求。
const CHOICE_KIND: String = "jiegou_recast"

## 单次请求需要选择的牌张数；原文为“一张非延时锦囊牌”。
const SELECT_COUNT: int = 1

## 首次记录一个牌名时叠加给AI的额外收益；记录越多样，后续【灵感】的可选牌名越丰富。
const FIRST_RECORD_AI_BONUS: float = 2.0

## 重铸一次的基础AI收益；与通用重铸尺度保持一致，避免技能自造第二套估值标准。
const RECAST_AI_BASE: float = 1.0

## 查看已记录牌名的角标按钮条目ID；稳定来源标识保证重复声明时原位更新而不是叠加第二行。
const CORNER_BUTTON_ENTRY_ID: String = "jiegou:recorded_names"

## 角标按钮的显示文本；固定为技能名，玩家一眼可知该按钮由哪个技能提供。
const CORNER_BUTTON_TEXT: String = "解构"

## 角标按钮的排序值；排在“酩酊”“永劫”等状态提示(50)之后、“安可”等数值提示(100)之前。
const CORNER_BUTTON_ORDER: int = 60

## 角标按钮的中性类型标识；表现层据此决定打开哪种只读界面，技能与控制器都不解释其含义。
const CORNER_BUTTON_VIEW_KIND: String = "recorded_card_names"


## 写入主动技静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"jiegou",
		"name":"解构",
		"trigger":"active/phaseUse",
		"enable":"phaseUse",
		"ui_enabled":true,
		"description":"出牌阶段，你可以重铸一张非延时锦囊牌，然后若该锦囊牌的牌名未被记录，你记录该牌牌名。",
	})


## 检查出牌阶段归属与可重铸锦囊候选；原文没有次数上限，因此只判断候选是否存在。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	return not _get_recastable_hand_uids(owner).is_empty()


## 请求选择一张要重铸的锦囊；重铸与记录都在恢复回调中完成。
func activate(_context: Dictionary = {}) -> String:
	# 技能持有者；权威状态在异步选择期间可能变化，因此每次都要重新取得。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not can_activate():
		return "【解构】当前不满足发动条件。"
	# 可重铸手牌候选；包含【无懈可击】等响应类锦囊，它们可以重铸但不能被记录。
	var candidates: Array[Dictionary] = _get_recastable_hand_candidates(owner)
	if candidates.is_empty():
		return "【解构】当前没有可重铸的非延时锦囊牌。"
	request_card_selection("解构", "选择一张非延时锦囊牌重铸，若其牌名未被记录则记录之", candidates, SELECT_COUNT, SELECT_COUNT, true, {"kind":CHOICE_KIND})
	return ""


## 恢复【解构】选牌：先重铸，再按原文顺序记录牌名。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null or str(context.get("kind", "")) != CHOICE_KIND:
		return false
	# 取消或未选中恰好一张牌时不做任何事：原文要求先完成重铸才可能记录。
	if not response.confirmed or response.card_ids.size() != SELECT_COUNT:
		return true
	# 技能持有者；重铸与记录都以其为权威主体。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return true
	# 待重铸实体；必须先取到牌面定义，因为重铸成功后该牌会离开手牌区。
	var target_card: CardInstance = owner.find_hand_card(response.card_ids[0])
	if target_card == null or not _is_recastable_trick(target_card.definition_id):
		return true
	# 记录用的稳定牌名；在重铸前固化，避免重铸后实体易主或进入弃牌堆导致读不到定义。
	var recorded_definition_id: String = target_card.definition_id
	# 权威重铸端口；只接受普通手牌区实体，失败时不产生任何后续效果。
	if not bool(host.call("recast_hand_card", owner_player_id, response.card_ids[0])):
		return true
	# 记录范围比可重铸范围更窄：只有普通锦囊进入记录容器。
	# 【无懈可击】在这里被有意跳过——它可以被重铸，但不能被【灵感】视为使用。
	if _is_recordable_definition(recorded_definition_id):
		host.call("record_card_name", owner_player_id, recorded_definition_id)
		# 首次记录时在武将牌上声明查看按钮；条目常驻，是否渲染由表现层按“记录是否为空”决定，
		# 因此清空记录的【看破】不需要知道【解构】的存在，两个技能保持互不引用。
		_ensure_record_button_entry(owner)
	announce_activation({"card_definition_id":recorded_definition_id, "recorded":_is_recordable_definition(recorded_definition_id)})
	return true


## 在武将牌左上角声明“查看已记录牌名”按钮条目；已存在时不重复写入，避免每次记录都触发一次公开快照广播。
func _ensure_record_button_entry(owner: PlayerState) -> void:
	# 技能持有者；缺失时无法定位角标归属，直接跳过。
	if owner == null:
		return
	# 宿主角标端口；缺少端口时静默跳过，保持技能在无界面环境下仍可正常结算。
	if host == null or not host.has_method("set_character_corner_text_entry"):
		return
	# 已存在的条目直接返回；按钮的显隐由记录容器是否为空决定，不依赖条目本身的增删。
	if owner.character_corner_text_entries.has(CORNER_BUTTON_ENTRY_ID):
		return
	host.call("set_character_corner_text_entry", owner_player_id, CORNER_BUTTON_ENTRY_ID, CORNER_BUTTON_TEXT, CORNER_BUTTON_ORDER, CORNER_BUTTON_VIEW_KIND)


## 为AI枚举本技能在本出牌阶段的候选动作；具体重铸哪张牌由后续选牌请求决定。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})


## 评估【解构】的选牌：重铸换牌是基础收益，首次记录新牌名额外加分。
## 按设计参考“几乎可以无脑重铸”：只要存在候选，评分必须严格为正，避免AI因保守而永不记录牌名。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND:
		return 0.0
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 取消动作不加成；由通用策略保留为0分，本技能不奖励“什么都不做”。
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 被选中牌UID；AI只会在权威候选内选择，这里取首张即可。
	var selected_uids: Array = payload.get("selected_card_uids", []) as Array
	if selected_uids.is_empty():
		return 0.0
	var selected_uid: int = int(selected_uids[0])
	# 被重铸牌的保留价值；价值越低，换成一张未知牌的净收益越高。
	var card_value: float = float(evaluator.call("get_owned_card_value_by_uid", authoritative_snapshot, owner_player_id, selected_uid)) if evaluator.has_method("get_owned_card_value_by_uid") else 0.0
	var score: float = RECAST_AI_BASE - card_value
	# 候选牌名是否尚未记录；只有可记录牌名才享有该加成，响应类锦囊不会解锁【灵感】。
	for candidate_variant: Variant in choice_request.get("candidates", []) as Array:
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) != selected_uid:
			continue
		var candidate_definition_id: String = _candidate_definition_id(candidate)
		if _is_recordable_definition(candidate_definition_id) and not get_recorded_card_names_for_ai(authoritative_snapshot).has(candidate_definition_id):
			score += FIRST_RECORD_AI_BONUS
		break
	return maxf(score, 0.5)


## 从权威快照读取技能持有者已记录的牌名；AI钩子没有宿主，只能通过快照判断记录状态。
func get_recorded_card_names_for_ai(authoritative_snapshot: Dictionary) -> Array:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		var player_snapshot: Dictionary = player_variant as Dictionary
		if int(player_snapshot.get("player_id", -1)) == owner_player_id:
			return player_snapshot.get("recorded_card_names", []) as Array
	return []


## 从权威候选字典读取牌名稳定ID；牌面信息位于 card_data 内，隐私裁剪时为空字符串。
func _candidate_definition_id(candidate: Dictionary) -> String:
	return str((candidate.get("card_data", {}) as Dictionary).get("definition_id", ""))


## 判断是否可被【解构】重铸：非延时锦囊。【无懈可击】满足本条件。
func _is_recastable_trick(definition_id: String) -> bool:
	# 牌面定义；未知或不存在的定义一律不可重铸。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	if definition.is_empty():
		return false
	if str(definition.get("type", "")) != RECASTABLE_TYPE:
		return false
	return not bool(definition.get("delayed", false))


## 判断是否可被记录：先可重铸，再要求子类为普通锦囊，因此排除【无懈可击】等响应类锦囊。
func _is_recordable_definition(definition_id: String) -> bool:
	if not _is_recastable_trick(definition_id):
		return false
	return str(GameDatabase.get_card(definition_id).get("subtype", "")) == RECORDABLE_SUBTYPE


## 返回持有者手中可重铸锦囊的实体UID；用于判断是否开放技能入口。
func _get_recastable_hand_uids(owner: PlayerState) -> Array[int]:
	# 可重铸实体结果；顺序与手牌顺序一致，便于界面稳定展示。
	var result: Array[int] = []
	for card: CardInstance in owner.hand:
		if card != null and _is_recastable_trick(card.definition_id):
			result.append(card.uid)
	return result


## 返回持有者手中可重铸锦囊的权威候选字典；额外附带 definition_id 供AI读取牌名。
func _get_recastable_hand_candidates(owner: PlayerState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate_variant: Variant in host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array:
		var candidate: Dictionary = (candidate_variant as Dictionary).duplicate(true)
		if not _is_recastable_trick(_candidate_definition_id(candidate)):
			continue
		result.append(candidate)
	return result
