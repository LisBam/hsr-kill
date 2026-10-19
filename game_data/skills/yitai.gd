extends SkillDefinition

## 【以太】技能源码。限定技：出牌阶段创造并获得一张自定义牌名的卡牌；任意角色回合结束时，
## 若弃牌堆中存在由本技能创造的牌，持有者成为「主演」并把那些牌洗回摸牌堆。
##
## 【玩法定位】银狼的招牌动作：把一张「不存在的牌」带进对局，并为它安排一条回到牌堆的通路。
## 造出的牌在效果层面完全等同于被复制的那张牌（沿用其牌效、类别与目标模式），只有牌名是新的；
## 因此「以太」牌不是一种新牌效，而是「一张改了名字的既有牌」。
##
## 【识别口径】「以太」牌按**铸造来源**识别（`CardInstance.minted_skill_id == "yitai"`），
## **不是**按牌名识别：牌名由玩家自由输入，两张以太牌完全可能重名，同名撞车是设计内允许的。
##
## 【回流口径】原文用单数「若“以太”牌在弃牌堆中」；本实现取「弃牌堆中**所有**由本技能创造的牌」，
## 逐张洗回摸牌堆，只要至少洗入一张就让持有者成为主演。限定技一局一次，常规情形下只有一张，
## 行为与原文单数表述一致；之所以按多张实现，是因为武将复原（`restore_limited_use`）后可能再造一张。
##
## 【翻面跳过回合不派发 phaseAfter】翻面跳过整个回合时核心走 `_complete_face_down_skipped_turn`，
## 不派发 `phaseAfter`，因此该回合不触发回流，也不补偿到下一个回合。这是刻意保留的：原文限定的是
## 「一名角色的回合结束时」，跳过回合并不产生该时机。

## 以太造牌的铸造来源标记；同时用于「找出由本技能创造的牌」，必须与控制器端口参数保持一致。
const MINTED_SKILL_ID: String = "yitai"

## 造牌窗口的控制项前缀；与控制器常量同源，避免两侧各写一份字面量后失配。
const MINT_CONTROL_PREFIX: String = MatchController.YINLANG_MINT_CONTROL_PREFIX

## 造牌窗口控制项的分隔符；与控制器常量同源。
const CONTROL_SEPARATOR: String = MatchController.YINLANG_CONTROL_SEPARATOR

## 造牌窗口控制项的分段数量：前缀两段 + 牌名 + 花色 + 点数 + 被复制牌定义ID。
const MINT_CONTROL_FIELD_COUNT: int = MatchController.YINLANG_MINT_CONTROL_FIELD_COUNT

## 造牌窗口的业务类型；用于把本技能的造牌选择与其它选择区分开。
const CHOICE_KIND_MINT: String = "yitai_mint"

## AI 自动生成的牌名前缀；后接序号，保证不与任何静态牌名冲突且每次不同。
const AI_CARD_NAME_PREFIX: String = "以太造物"

## AI 自动生成牌名时尝试的序号上限；超过则放弃本次自动命名，避免死循环。
const AI_CARD_NAME_MAX_ATTEMPTS: int = 64

## AI 造牌默认使用的花色；红桃与「桃」的直觉一致，且不影响任何规则判定。
const AI_DEFAULT_SUIT: String = "heart"

## AI 造牌默认使用的点数；取中间值，使牌在点数比较类判定中保持中性。
const AI_DEFAULT_RANK: int = 7

## 造牌窗口请求上下文中「已有牌名」的键名；界面据此做即时唯一性提示。
const CONTEXT_KEY_EXISTING_NAMES: String = "existing_card_names"

## 造牌窗口请求上下文中「牌名长度上限」的键名；界面据此限制输入长度。
const CONTEXT_KEY_NAME_MAX_LENGTH: String = "card_name_max_length"

## 造牌窗口请求上下文中「可选被复制牌」的键名；界面按基本牌 → 锦囊牌 → 装备牌顺序分组展示。
const CONTEXT_KEY_COPYABLE_CARDS: String = "copyable_cards"

## 可被复制的卡牌类别顺序；与界面分组顺序、需求原文的列举顺序一致，不得调整。
const COPYABLE_TYPE_ORDER: Array[String] = ["basic", "trick", "equipment"]

## 回合结束回流的发动公告中「洗入牌数」的键名。
const ACTIVATION_WASHED_COUNT_KEY: String = "washed_card_count"

## AI 发动以太的固定基准价值；一局一次的限定技，只要还能发动就高于「什么都不做」。
const AI_ACTION_BASE_VALUE: float = 2.0

## AI 复制不同类别卡牌时的类别偏好加分；锦囊牌通常带来最大节奏收益，装备牌次之，基本牌最稳定。
const AI_COPY_TYPE_BONUS: Dictionary = {"trick":2.0, "equipment":1.0, "basic":0.0}


## 写入技能静态信息；玩家可见描述严格保持需求提供的原文。
## 「限定技」出现在正文开头，SkillDefinition 据此自动标记 limited，无需显式声明。
func _init() -> void:
	super({
		"id":"yitai",
		"name":"以太",
		"trigger":"phaseAfter",
		"enable":"phaseUse",
		"ui_enabled":true,
		"description":"限定技，出牌阶段，你可以创造并获得一张卡牌，该牌牌名不可与已有牌相同。一名角色的回合结束时，若“以太”牌在弃牌堆中，你成为“主演”并将其洗入牌堆。",
	})


## 订阅任意角色的回合结束之后时机；回流与回合归属无关，因此使用 global 角色。
func install() -> void:
	subscribe_timing("phaseAfter", _on_phase_after, "global")


## 判断限定技是否可发动：持有者存活未离场、仍有固有额度、且正处于自己的出牌阶段。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场、额度用尽或不在自己出牌阶段时均不可用。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and has_available_intrinsic_use() \
		and host.state.current_player_id == owner_player_id and host.state.current_phase == "play"


## 发动以太；打开造牌窗口，四项选择齐全后由 continue_selection 落地造牌。
##
## 【为什么在窗口而不是在 activate 里直接造牌】牌名是自由文本，规则层无法替玩家决定；
## 直接动作携带完整参数时也走同一套解析，保证界面、AI 与网络三条路径共用一份实现。
func activate(context: Dictionary = {}) -> String:
	# 已提交的完整控制项；直接动作（AI 或网络重放）携带时立即落地。
	var submitted_control_id: String = str(context.get("control_id", ""))
	if not submitted_control_id.is_empty():
		return "" if _execute_mint(submitted_control_id) else "【以太】造牌参数无效或牌名已被占用。"
	# 牌名唯一性快照；界面据此即时提示重名，最终仍由造牌端口权威复核。
	var existing_names: Array[String] = host.call("collect_taken_card_display_names") as Array[String]
	# 请求上下文；只放可序列化值，界面据此渲染，AI 短名单由本技能给出。
	var mint_context: Dictionary = {
		"kind":CHOICE_KIND_MINT,
		MatchController.YINLANG_WINDOW_CONTEXT_KEY:MatchController.YINLANG_WINDOW_AETHER,
		CONTEXT_KEY_EXISTING_NAMES:existing_names,
		CONTEXT_KEY_NAME_MAX_LENGTH:MatchController.MINT_CARD_NAME_MAX_LENGTH,
		CONTEXT_KEY_COPYABLE_CARDS:_build_copyable_card_options(),
		"ai_candidate_control_ids":_build_ai_shortlist(),
	}
	request_free_control_selection("【以太】创造卡牌", "输入牌名并选择花色、点数与要复制的牌，确认后该牌进入你的手牌", MatchController.YINLANG_MINT_CHOICE_TYPE, true, mint_context)
	return ""


## 恢复造牌选择；取消不消耗限定技额度，也不产生任何牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != CHOICE_KIND_MINT or response == null:
		return false
	if not response.confirmed:
		return true
	_execute_mint(str(response.control_id))
	return true


## 任意角色回合结束时检查弃牌堆；存在本技能创造的牌则成为主演并把这些牌洗回摸牌堆。
##
## 【顺序】先成为主演再洗牌：原文的表述顺序是「你成为主演并将其洗入牌堆」，
## 且洗牌本身可能触发其它时机，先落定主演状态可以让那些时机读到正确的公开状态。
func _on_phase_after(_event: RuleEvent) -> void:
	if host == null or host.get("state") == null or host.state.game_over:
		return
	# 技能持有者权威状态；死亡或离场后不再回流。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 弃牌堆中由本技能创造的牌 UID；按铸造来源识别，不按牌名。
	var minted_uids: Array[int] = host.call("get_discard_pile_card_uids_by_skill", MINTED_SKILL_ID) as Array[int]
	if minted_uids.is_empty():
		return
	host.call("set_starring_role", owner_player_id)
	# 实际洗入的牌数；逐张洗入，每张都独立写随机历史，保证回放能复原同一牌序。
	var washed_count: int = 0
	for card_uid: int in minted_uids:
		if bool(host.call("shuffle_discard_card_into_draw_pile", card_uid)):
			washed_count += 1
	if washed_count <= 0:
		return
	announce_activation({ACTIVATION_WASHED_COUNT_KEY:washed_count, "card_uids":minted_uids.duplicate()})


## 执行造牌；解析控制项并调用造牌端口，失败时不消耗限定技额度。
##
## 【为什么失败不消耗额度】牌名冲突、参数非法都属于「玩家输入问题」，而不是「技能已经发动」；
## 若在这里消耗额度，玩家一次误输入就会永久失去限定技，这是不可接受的。
func _execute_mint(control_id: String) -> bool:
	if not control_id.begins_with(MINT_CONTROL_PREFIX):
		return false
	# 分段结果；前缀两段固定，随后是牌名、花色、点数与被复制牌定义ID。
	var segments: PackedStringArray = control_id.split(CONTROL_SEPARATOR)
	if segments.size() != MINT_CONTROL_FIELD_COUNT:
		return false
	# 牌名、花色、点数与被复制牌定义ID。
	var custom_name: String = segments[2]
	var suit: String = segments[3]
	var rank: int = int(segments[4])
	var source_definition_id: String = segments[5]
	# 造牌端口是唯一权威判据：牌名格式与唯一性、花色点数合法性、定义存在性都在其中复核。
	var minted_uid: int = int(host.call("mint_card_for_player", owner_player_id, source_definition_id, custom_name, suit, rank, MINTED_SKILL_ID))
	if minted_uid < 0:
		host.call("add_log", "【以太】未能创造卡牌：%s" % str(host.call("get_card_name_rejection_reason", custom_name)))
		return false
	# 记录发动；此时才消耗限定技的固有额度。
	announce_activation({"minted_card_uid":minted_uid, "custom_name":custom_name, "suit":suit, "rank":rank, "source_definition_id":source_definition_id})
	return true


## 构造可被复制的卡牌选项；按「基本牌 → 锦囊牌 → 装备牌」分组，组内保持数据库声明顺序。
##
## 【为什么由技能给出而不是界面自己查库】界面不得读取规则/内容层（窗口只接收普通字典）；
## 同时这也保证联机与回放拿到的是同一份只读快照，不会因为两端数据库加载顺序不同而出现差异。
func _build_copyable_card_options() -> Array[Dictionary]:
	# 结果选项；每项含稳定定义ID、玩家可见牌名与分组类别。
	var result: Array[Dictionary] = []
	for card_type: String in COPYABLE_TYPE_ORDER:
		for card_id_variant: Variant in GameDatabase.get_card_ids_by_type(card_type):
			# 当前定义ID；空值不进入候选。
			var card_id: String = str(card_id_variant)
			if card_id.is_empty():
				continue
			result.append({"id":card_id, "name":GameSettings.resolve_card_display_name(GameDatabase.get_card(card_id)), "type":card_type})
	return result


## 构造 AI 作答用的造牌短名单；自动生成一个唯一牌名，并给出若干候选被复制牌。
##
## 【为什么 AI 需要短名单】牌名是自由文本，AI 无法从「合法选项枚举」里挑；
## 因此由技能生成一个保证唯一的牌名，再把花色、点数与候选被复制牌组合成有限个控制项交给 AI 排序。
func _build_ai_shortlist() -> Array[String]:
	# 自动生成的唯一牌名；生成失败时放弃短名单（AI 只能取消），绝不提交一个必然被拒绝的牌名。
	var ai_card_name: String = _build_ai_card_name()
	if ai_card_name.is_empty():
		return []
	# 结果控制项；按「优先复制锦囊牌、其次装备牌、最后基本牌」的粗粒度顺序给出。
	# 内层循环在达到上限时 break，外层循环随后会因为上限已满而在内层第一次判断处立即 break，
	# 因此总数严格不超过 YINLANG_AI_CANDIDATE_LIMIT；改动这里的循环结构时必须重新确认这一点。
	var result: Array[String] = []
	for card_type: String in ["trick", "equipment", "basic"]:
		for card_id_variant: Variant in GameDatabase.get_card_ids_by_type(card_type):
			if result.size() >= MatchController.YINLANG_AI_CANDIDATE_LIMIT:
				break
			result.append(_build_mint_control_id(ai_card_name, AI_DEFAULT_SUIT, AI_DEFAULT_RANK, str(card_id_variant)))
	return result


## 按协议格式拼出一条造牌控制项；分段数必须与控制器解析规则严格一致。
##
## 【为什么必须集中拼接】造牌控制项是六段定长协议（前缀两段 + 牌名 + 花色 + 点数 + 被复制牌定义ID），
## 少一个分隔符就会退化成五段并被权威侧静默拒绝——表现为「AI 的造牌请求永远提交不上去」。
## 因此这里只保留一处拼接实现，花色与点数各自占用独立分段。
func _build_mint_control_id(card_name: String, suit: String, rank: int, definition_id: String) -> String:
	return "%s%s%s%s%s%d%s%s" % [MINT_CONTROL_PREFIX, card_name, CONTROL_SEPARATOR, suit, CONTROL_SEPARATOR, rank, CONTROL_SEPARATOR, definition_id]


## 生成一个保证可用的 AI 牌名；连续尝试直到造牌端口的判据认为可用，全部失败时返回空字符串。
func _build_ai_card_name() -> String:
	for attempt: int in range(AI_CARD_NAME_MAX_ATTEMPTS):
		# 当前候选牌名；带序号以保证与已有牌名不冲突。
		var candidate_name: String = "%s%d" % [AI_CARD_NAME_PREFIX, attempt + 1]
		if bool(host.call("is_card_name_available", candidate_name)):
			return candidate_name
	return ""


## 以太没有可枚举的主动目标；主动动作由 append_play_phase_actions 提供单一「打开窗口」动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[], "payload":{"skill_id":get_id(), "target_ids":[]}})


## 以太的主动动作价值：造牌本身是纯收益，但价值取决于被复制牌；
## 由于 AI 动作不带被复制牌信息，这里给出一个稳定的正基准分，具体选择由造牌窗口的选择评分决定。
func score_ai_action(_authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 非以太主动动作不参与评分。
	if str(action.get("skill_id", "")) != get_id():
		return 0.0
	# 基准分；限定技一局一次，只要还能发动就值得发动（造出的牌至少等价于一张普通牌）。
	return evaluator.score_action(_authoritative_snapshot, {"action_type":"draw_card", "actor_id":owner_player_id, "card_count":1}, owner_player_id) + AI_ACTION_BASE_VALUE


## 造牌窗口选择评分；只处理本技能创建的请求，其余请求返回0不干扰通用评分。
##
## 口径：被复制牌的类别决定粗粒度价值（锦囊 > 装备 > 基本）；牌名、花色与点数不参与评分，
## 因为它们完全不影响牌效。之所以不逐张牌做精细估值：AI 短名单里的候选来自全部卡牌定义，
## 为每张牌写专属权重既无法维护，收益也远低于「先选对类别」。
func score_ai_choice(_authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, _evaluator: Object) -> float:
	# 请求上下文；非造牌选择不修改通用评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND_MINT:
		return 0.0
	# 标准选择负载；取消保持0分，由通用策略决定是否取消。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 控制项；格式非法时返回0。
	var control_id: String = str(payload.get("selected_control_id", payload.get("control_id", "")))
	if not control_id.begins_with(MINT_CONTROL_PREFIX):
		return 0.0
	# 分段结果；被复制牌定义ID是最后一段。
	var segments: PackedStringArray = control_id.split(CONTROL_SEPARATOR)
	if segments.size() != MINT_CONTROL_FIELD_COUNT:
		return 0.0
	# 被复制牌定义类别；未知定义按0分处理，不会误选。
	var copied_type: String = str(GameDatabase.get_card(segments[5]).get("type", ""))
	return float(AI_COPY_TYPE_BONUS.get(copied_type, 0.0))
