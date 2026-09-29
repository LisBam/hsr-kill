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

## 【无懈可击】的稳定牌名ID；它可被重铸但不会被记录，因此不参与“扩充记录池”的发动判定。
const WUXIE_DEFINITION_ID: String = "wuxie"

## 确认重铸一张“可记录锦囊”的收益；必须显著高于任何单张手牌的保留价值。
## 通用选牌评分对手牌费用按“选中牌面价值”的负数计分（见 NonameAIEvaluator.score_choice_action），
## 而取消动作恒为0分，因此技能给出的加分若小于牌面价值，AI 就会选择取消。
## 取消既不消耗次数也不移动任何牌，AI 便会在同一出牌阶段反复“发动→取消”，
## 直到撞上 max_ai_actions_per_turn 被强制结束回合——这正是“AI大黑塔把自己卡住”的直接原因。
const RECAST_COMMIT_REWARD: float = 100.0

## 尚未记录牌名的排序加分；只在多个候选之间排出先后，不改变“必定完成一次重铸”的结论。
const UNRECORDED_NAME_ORDER_BONUS: float = 10.0

## 不可记录锦囊（当前只有【无懈可击】）的确认分；仍保持为正分，用于兜底防止空转。
## 发动判定已排除这类牌名，正常流程不会选中它；一旦因为协议异常仍被询问，AI 也必须完成一次真实重铸。
const UNRECORDABLE_COMMIT_REWARD: float = 5.0

## 【解构】的发动优先分；用于落实“先重铸尚未记录的锦囊，再考虑直接使用锦囊”的出牌口径。
## 通用用牌评分由 `player_result + 出牌顺序×0.12 - 牌面价值×0.08 + 逐目标收益` 组成，
## 其中目标收益上限为个位数，因此整条用牌评分不超过十分量级；这里取一个明显更高的固定值，
## 使AI在手中仍有“尚未被记录的可记录锦囊”时始终优先完成一次重铸，而不是先把锦囊打出去。
## 该分值不会造成死循环：每次重铸都真实消耗一张锦囊并记录牌名（确认分恒为正），
## 当手中不再有符合条件的锦囊时本技能评分立即回到0，AI随即恢复正常出牌。
const RECAST_PRIORITY_AI_SCORE: float = 50.0


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


## 计算【解构】发动动作本身的AI评分。
## 基类的 score_ai_action 默认返回 0.0，若不覆盖，AI 会把该动作视为毫无价值而**永不发动**，
## 表现为技能在整局中一次都不出现。这是本技能曾经完全不被 AI 使用的直接原因。
## 原文没有次数上限，且技能设计口径为“几乎可以无脑重铸”，因此只要动作能进入评分
## （说明 append_play_phase_actions 已用真实状态确认手中存在可重铸锦囊），就给出稳定正分。
## 尚未建立记录时额外叠加记录加成，促使 AI 优先解锁【灵感】的牌名池。
## 口径补充：只有手中确实存在“尚未被记录、且不是【无懈可击】”的可重铸锦囊时才给出正分。
## 【无懈可击】重铸后不会进入记录容器，为它消耗一次出牌动作属于纯亏，因此 AI 不发动；
## 手中只剩已记录牌名时同样不发动，避免把还有使用价值的锦囊无脑换掉。
## 出牌优先级补充：满足条件时在评分上叠加 RECAST_PRIORITY_AI_SCORE，
## 使【解构】排在任何一次直接使用锦囊之前——先把牌名记进容器扩充【灵感】素材，再谈出牌。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	# 尚未记录的可重铸锦囊牌名；为空说明本次发动不会带来任何新素材，直接保持0分。
	if _get_unrecorded_recastable_hand_names_for_ai(authoritative_snapshot).is_empty():
		return 0.0
	# 已记录牌名；记录为空说明尚未解锁任何【灵感】素材，此时给出更高的发动倾向。
	var recorded_names: Array = get_recorded_card_names_for_ai(authoritative_snapshot)
	if recorded_names.is_empty():
		return RECAST_PRIORITY_AI_SCORE + RECAST_AI_BASE + FIRST_RECORD_AI_BONUS
	return RECAST_PRIORITY_AI_SCORE + RECAST_AI_BASE


## 评估【解构】的选牌：重铸换牌是基础收益，首次记录新牌名额外加分。
## 按设计参考“几乎可以无脑重铸”：只要存在候选，评分必须严格为正，避免AI因保守而永不记录牌名。
## 口径补充：上面的“基础收益 - 牌面价值”尺度会被通用选牌评分的手牌费用再次抵消，
## 实测中【南蛮入侵】这类高面值锦囊的确认分仍为负数，AI 于是选择取消并触发上文所述的死循环。
## 因此本节改为“无脑重铸”口径：确认动作一律给出显著高于任何手牌价值的保底分，
## 牌名是否已记录只作为候选之间的排序依据——未记录的可记录锦囊最高，已记录其次，
## 【无懈可击】等不可记录锦囊最低但仍为正分（保证AI一旦发动必然完成一次真实重铸）。
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
	# 候选牌名是否尚未记录；只有可记录牌名才享有该加成，响应类锦囊不会解锁【灵感】。
	for candidate_variant: Variant in choice_request.get("candidates", []) as Array:
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) != selected_uid:
			continue
		var candidate_definition_id: String = _candidate_definition_id(candidate)
		if not _is_recordable_definition(candidate_definition_id):
			return UNRECORDABLE_COMMIT_REWARD
		if get_recorded_card_names_for_ai(authoritative_snapshot).has(candidate_definition_id):
			return RECAST_COMMIT_REWARD
		return RECAST_COMMIT_REWARD + UNRECORDED_NAME_ORDER_BONUS
	# 候选缺失（协议异常或牌已离手）时仍给出保底正分，确保AI一旦发动就必然完成一次真实重铸。
	return UNRECORDABLE_COMMIT_REWARD


## 从权威快照读取技能持有者手中“尚未被记录、且可以被【解构】重铸并记录”的锦囊牌名。
## 【无懈可击】虽可重铸，但子类不是普通锦囊、永远不会进入记录容器，因此在这里被显式排除：
## 重铸它不会扩充【灵感】的牌名池，不属于本技能的发动收益来源。
func _get_unrecorded_recastable_hand_names_for_ai(authoritative_snapshot: Dictionary) -> Array:
	# 已记录牌名；重复记录同一牌名不会带来任何新素材，因此已经在记录中的牌名不参与本判定。
	var recorded_names: Array = get_recorded_card_names_for_ai(authoritative_snapshot)
	# 结果集合；沿用快照手牌顺序，保持AI枚举稳定，不引入任何随机化。
	var result: Array = []
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		var player_snapshot: Dictionary = player_variant as Dictionary
		if int(player_snapshot.get("player_id", -1)) != owner_player_id:
			continue
		for card_variant: Variant in player_snapshot.get("hand", []) as Array:
			# 当前手牌实体；AI只读取公开与本人可见的牌名，不猜测牌面以外的信息。
			var card_snapshot: Dictionary = card_variant as Dictionary
			var definition_id: String = str(card_snapshot.get("definition_id", ""))
			if definition_id == WUXIE_DEFINITION_ID:
				continue
			if not _is_recordable_definition(definition_id):
				continue
			if recorded_names.has(definition_id):
				continue
			if not result.has(definition_id):
				result.append(definition_id)
	return result


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
