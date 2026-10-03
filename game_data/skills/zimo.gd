extends SkillDefinition

## 【自摸】技能源码。出牌阶段主动技，按当前手牌花色数分成两条互斥分支：
## 分支A（手牌花色数少于4）：摸一张牌，然后视为使用一张【杀】或任意本局尚未以此法使用过的普通锦囊牌。
## 分支B（手牌花色数不少于4）：弃置一种花色的所有手牌，并把本技能改为“出牌阶段限两次”直到回合结束。
##
## 两条分支共用同一个发动计数：原文**没有**“出牌阶段限一次”表述，因此基础状态下不限次；
## 分支A在发动瞬间计数、分支B在弃置完成后计数，并在本回合内把上限改写为原文声明的两次。
## 因此“先发动分支B、再发动分支A”恰好用满两次，而且分支B之前的任何发动都计入这“两次”之内。

## 未改写前的出牌阶段发动上限；-1表示原文基础状态的“不限次”，比较时只有非负上限才参与拦截。
const UNLIMITED_PLAY_PHASE_LIMIT: int = -1

## 改写后的出牌阶段发动上限；数值2来自原文“改为出牌阶段限两次”。
const EXTENDED_PLAY_PHASE_LIMIT: int = 2

## 花色数阈值；手牌花色数少于该值时走分支A，否则走分支B。
const SUIT_COUNT_THRESHOLD: int = 4

## 参与花色统计与分支B选项的实体花色；无花色（none）手牌不计入花色数，也不会成为分支B的选项。
const CARD_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]

## 花色符号；仅用于分支B的内联选项文本。
const SUIT_SYMBOLS: Dictionary = {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦"}

## 花色中文名；仅用于分支B的内联选项文本。
const SUIT_NAMES: Dictionary = {"spade":"黑桃", "heart":"红桃", "club":"梅花", "diamond":"方块"}

## 分支A的固定摸牌数；数值1来自原文“摸一张牌”。
const DRAW_COUNT: int = 1

## 视为使用的基本牌牌名；原文为“一张【杀】”，固定使用普通【杀】定义。
const SLASH_DEFINITION_ID: String = "sha"

## 视为使用的牌大类：锦囊牌。
const TRICK_TYPE: String = "trick"

## 视为使用的锦囊子类：普通锦囊牌。延时锦囊与响应类锦囊（【无懈可击】）都不在原文范围内。
const NORMAL_TRICK_SUBTYPE: String = "normal"

## 由核心层自动展开目标的模式；这些牌的目标集合由规则唯一确定，界面只需预填、玩家直接确认。
const AUTO_TARGET_MODES: Array[String] = ["all_others", "all_players", "self", "self_wounded"]

## 视为使用不修改任何牌面规则；统一使用空覆写让核心层走标准虚拟牌校验。
const EMPTY_OVERRIDES: Dictionary = {}

## 选择类别：分支A的“选牌并选目标”虚拟手牌请求。
const CHOICE_PICK_EFFECT: String = "zimo_pick_effect"

## 选择类别：分支B的花色内联选项。
const CHOICE_PICK_SUIT: String = "zimo_pick_suit"

## 技能选择请求的标题；界面交互面板与提示文本共用同一来源。
const SELECTION_TITLE: String = "自摸"

## 分支A的请求提示；说明候选来源与目标规则，避免玩家误以为真的获得了这些牌。
const SELECTION_PROMPT: String = "请选择视为使用的牌，并为其指定目标"

## 分支B的请求提示；明确弃置范围是该花色的全部手牌。
const SUIT_PROMPT: String = "请选择要弃置全部手牌的花色"

## 已使用牌名展示的前缀；存在本局记录时追加到技能描述末尾。
const USED_NAMES_PREFIX: String = "（已以此法使用："

## 已使用牌名展示的后缀。
const USED_NAMES_SUFFIX: String = "）"

## AI主动发动评分；取值足够大，使AI在自己出牌阶段满足条件时稳定选择发动。
const AI_ACTION_BASE: float = 20.0

## AI确认提交选择的固定收益；必须严格大于取消得到的0分，保证AI不会因为保守而放弃效果。
const AI_COMMIT_REWARD: float = 100.0

## AI对分支B弃置花色的惩罚系数；每张被弃置的手牌按该系数降低偏好，使AI优先弃置张数最少的花色。
const AI_SUIT_DISCARD_PENALTY: float = 0.6

## AI对【杀】的额外偏好；【杀】能直接造成伤害，其他条件相同时优先选择。
const AI_SLASH_BONUS: float = 0.5

## 当前出牌阶段已经发动的次数；进入每个出牌阶段时归零，基础状态不作为拦截条件，只有本回合完成过分支B后才与改写后的上限比较。
var _used_this_play_phase: int = 0

## 已经把上限改写为“出牌阶段限两次”的回合号；-1表示本局尚未改写，与当前回合号比较实现“直到回合结束”的到期。
var _extended_limit_turn_number: int = -1


## 写入主动技静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"zimo",
		"name":"自摸",
		"trigger":"active/phaseUse",
		"enable":"phaseUse",
		"ui_enabled":true,
		"description":"出牌阶段，若你手牌中的牌花色数少于4，你可以摸一张牌，然后你视为使用一张【杀】或任意未以此法使用过的普通锦囊牌。若你手牌中的牌花色数不少于4，你可以弃置其中一种花色的所有手牌，并令此技能改为“出牌阶段限两次”直到回合结束。",
	})


## 订阅出牌阶段开始以复原阶段额度；技能描述里的已使用记录在安装时同步一次，避免旧对局文本残留。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")
	_refresh_display_description()


## 每个出牌阶段把发动计数归零；基础状态不限次因此归零只服务“改写为限两次”后的计数，
## 改写状态本身由回合号控制到期，不在此处复原。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = 0


## 检查出牌阶段归属、改写后的额度与当前分支是否至少存在一个可执行的完整效果。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	if host == null or host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 阶段额度；基础状态为-1（不限次），只有本回合完成过分支B后才按改写后的上限拦截。
	var play_phase_limit: int = _get_play_phase_limit()
	if play_phase_limit >= 0 and _used_this_play_phase >= play_phase_limit:
		return false
	if get_hand_suit_count(owner) < SUIT_COUNT_THRESHOLD:
		# 分支A：至少要有一种“视为使用”的完整合法选择，否则发动后只能白摸一张牌。
		return not _build_effect_selection_data().is_empty()
	# 分支B：至少要有一张实体花色的手牌可以弃置。
	return not _collect_suit_groups(owner).is_empty()


## 发动技能；按当前手牌花色数进入分支A或分支B。
func activate(_context: Dictionary = {}) -> String:
	if not can_activate():
		return "【自摸】当前不满足发动条件。"
	# 技能持有者；can_activate 已确认存在且存活。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if get_hand_suit_count(owner) < SUIT_COUNT_THRESHOLD:
		_activate_draw_branch()
		return ""
	_activate_suit_branch(owner)
	return ""


## 本技能当前的出牌阶段发动上限；-1表示原文基础状态的“不限次”，只有本回合完成过分支B时才改写为2。
func _get_play_phase_limit() -> int:
	if _extended_limit_turn_number >= 0 and host != null and _extended_limit_turn_number == host.state.turn_number:
		return EXTENDED_PLAY_PHASE_LIMIT
	return UNLIMITED_PLAY_PHASE_LIMIT


## 统计一份玩家状态手牌中的实体花色数；无花色手牌不计入，结果范围0到4。
func get_hand_suit_count(owner: PlayerState) -> int:
	# 已出现花色集合；用字典去重，避免同花色多张手牌被重复计数。
	var suits: Dictionary = {}
	if owner == null:
		return 0
	for card: CardInstance in owner.hand:
		if CARD_SUITS.has(card.suit):
			suits[card.suit] = true
	return suits.size()


## 分支A：先摸一张牌，再进入“选牌并选目标”的虚拟手牌交互。
##
## 计次时机：发动瞬间即计入本阶段已发动次数。基础状态不限次，但计数始终保留，
## 因此本回合稍后完成分支B改写上限时，这次发动同样占掉“限两次”中的一次；
## 之后的取消或目标失效只会重新选牌，既不重新摸牌也不再次计次。
func _activate_draw_branch() -> void:
	_used_this_play_phase += 1
	host.call("draw", owner_player_id, DRAW_COUNT)
	_reopen_effect_selection()


## 分支B：弹出包含每种花色的内联选项，玩家选择一种后弃置该花色全部手牌并把上限改写为2。
func _activate_suit_branch(owner: PlayerState) -> void:
	var suit_groups: Dictionary = _collect_suit_groups(owner)
	# 内联选项；只在确实有该花色手牌时出现，避免生成点了没有任何效果的空选项。
	var options: Array[Dictionary] = []
	for suit: String in CARD_SUITS:
		var suit_uids: Array = suit_groups.get(suit, []) as Array
		if suit_uids.is_empty():
			continue
		options.append({"id":suit, "label":"%s %s（%d张）" % [str(SUIT_SYMBOLS.get(suit, "")), str(SUIT_NAMES.get(suit, suit)), suit_uids.size()]})
	if options.is_empty():
		return
	# 花色到张数的映射；只用于AI评估弃置代价，不会泄露给其他玩家（选择请求只对持有者可见）。
	var suit_card_counts: Dictionary = {}
	for suit_variant: Variant in suit_groups.keys():
		suit_card_counts[str(suit_variant)] = (suit_groups[suit_variant] as Array).size()
	request_control_selection(SELECTION_TITLE, SUIT_PROMPT, options, true, {"kind":CHOICE_PICK_SUIT, "suit_card_counts":suit_card_counts})


## 建立或重新建立分支A的虚拟手牌选择请求；取消与目标失效都会回到这里且不重新摸牌。
func _reopen_effect_selection() -> void:
	# 当前可用效果数据；每次重新枚举都会重新过滤“本局已用过”的牌名与失效目标。
	var selection_data: Dictionary = _build_effect_selection_data()
	var entries: Array[Dictionary] = selection_data.get("entries", []) as Array[Dictionary]
	if entries.is_empty():
		# 已经没有可视为使用的牌：视为使用规则整体跳过，本次发动只结算摸牌。
		_refresh_display_description()
		return
	# 目标数量范围：单目标牌为1，【借刀杀人】等需要至少两名目标的牌由各自组合映射精确约束。
	request_virtual_hand_card_target_selection(SELECTION_TITLE, SELECTION_PROMPT, entries, selection_data.get("min_targets", 1), selection_data.get("max_targets", 1), true, {"kind":CHOICE_PICK_EFFECT})


## 建立分支A的候选数据；返回条目数组与请求级目标数量范围，候选与目标都由权威规则枚举产生。
func _build_effect_selection_data() -> Dictionary:
	# 虚拟候选条目；顺序即手牌区显示顺序，【杀】固定排在首位。
	var entries: Array[Dictionary] = []
	# 全部候选的目标数量下限与上限；请求级范围必须覆盖所有候选，具体约束由每张牌的组合映射收紧。
	var min_targets: int = 1
	var max_targets: int = 1
	for definition_id: String in _get_effect_definition_ids():
		# 当前牌面定义；定义缺失或不在数据库登记时跳过，不生成无法校验的候选。
		var definition: Dictionary = GameDatabase.get_card(definition_id)
		if definition.is_empty():
			continue
		# 当前候选的完整合法目标组合；没有任何合法组合的牌不进入候选，避免玩家选中后无目标可选。
		var target_combinations: Array = _collect_target_combinations(definition_id, definition)
		if target_combinations.is_empty():
			continue
		# 当前候选条目；目标组合与自动目标都由请求端口翻译成占位UID键，技能侧不接触占位UID。
		var entry: Dictionary = {
			"definition_id":definition_id,
			"label":GameSettings.resolve_card_name(definition),
			"target_combinations":target_combinations,
		}
		if AUTO_TARGET_MODES.has(str(definition.get("target_mode", ""))):
			# 自动目标模式：整张牌的目标由规则唯一确定，界面预填后玩家直接确认。
			entry["auto_target_ids"] = (target_combinations[0] as Array).duplicate()
		entries.append(entry)
		min_targets = mini(min_targets, maxi(int(definition.get("min_targets", 1)), 1))
		max_targets = maxi(max_targets, maxi(int(definition.get("max_targets", 1)), 1))
	if entries.is_empty():
		return {}
	return {"entries":entries, "min_targets":min_targets, "max_targets":max_targets}


## 返回本局当前仍可“视为使用”的牌名 ID 列表；【杀】固定第一，其余普通锦囊按牌名稳定排序。
func _get_effect_definition_ids() -> Array[String]:
	# 结果列表；【杀】永远可用（只要有合法目标），普通锦囊受“未以此法使用过”约束。
	var result: Array[String] = []
	result.append(SLASH_DEFINITION_ID)
	# 本局已以此法使用过的普通锦囊牌名；【杀】不写入该名单，因此可以重复使用。
	var used_names: Array = host.call("get_skill_used_card_names", owner_player_id, get_id()) as Array
	# 全部已登记牌名；排序后遍历保证候选顺序在本地、AI与网络三端完全一致。
	var all_card_ids: Array = GameDatabase.cards.keys()
	all_card_ids.sort()
	for card_id_variant: Variant in all_card_ids:
		# 当前牌名；【杀】已固定排在首位，此处跳过避免重复。
		var card_id: String = str(card_id_variant)
		if card_id == SLASH_DEFINITION_ID:
			continue
		# 当前牌面定义；只有普通锦囊才满足原文，延时锦囊与响应类锦囊都被排除。
		var definition: Dictionary = GameDatabase.get_card(card_id)
		if str(definition.get("type", "")) != TRICK_TYPE or str(definition.get("subtype", "")) != NORMAL_TRICK_SUBTYPE:
			continue
		if bool(definition.get("delayed", false)) or used_names.has(card_id):
			continue
		result.append(card_id)
	return result


## 枚举一张虚拟牌当前的完整合法目标组合；单目标牌为单元素组合，双目标牌为有序双元素组合。
func _collect_target_combinations(definition_id: String, definition: Dictionary) -> Array:
	# 合法目标 ID 列表；顺序沿用核心层座次顺序，组合生成因此稳定可复现。
	var legal_target_ids: Array[int] = host.card_rules.list_legal_virtual_targets(owner_player_id, definition_id)
	if legal_target_ids.is_empty():
		return []
	if AUTO_TARGET_MODES.has(str(definition.get("target_mode", ""))):
		# 自动目标模式：执行时核心层会忽略提交的目标数组并按行动顺序统一展开，
		# 因此这里只需给出展开后的完整集合；界面据此预填并让玩家直接确认。
		var auto_target_ids: Array[int] = []
		auto_target_ids.assign(legal_target_ids)
		return [auto_target_ids]
	return _enumerate_target_combinations(definition_id, legal_target_ids, maxi(int(definition.get("max_targets", 1)), 1))


## 按目标上限枚举完整有序组合，并逐条用权威虚拟牌校验筛选；借刀杀人等双目标牌因此只会生成双元素组合。
func _enumerate_target_combinations(definition_id: String, legal_target_ids: Array[int], maximum_target_count: int) -> Array:
	# 完整目标组合结果；每条组合都必须能通过 validate_virtual_use 的完整校验。
	var result: Array = []
	for target_id: int in legal_target_ids:
		var single_combination: Array[int] = [target_id]
		if host.card_rules.validate_virtual_use(owner_player_id, definition_id, single_combination).is_empty():
			result.append(single_combination)
	if maximum_target_count < 2:
		return result
	for first_target_id: int in legal_target_ids:
		for second_target_id: int in legal_target_ids:
			if first_target_id == second_target_id:
				continue
			var pair_combination: Array[int] = [first_target_id, second_target_id]
			if host.card_rules.validate_virtual_use(owner_player_id, definition_id, pair_combination).is_empty():
				result.append(pair_combination)
	return result


## 按花色收集持有者手牌 UID；无花色手牌不进入任何分组，也不会成为分支B的选项。
func _collect_suit_groups(owner: PlayerState) -> Dictionary:
	# 花色到手牌 UID 数组的映射；数组在字典中按引用共享，后续追加即可。
	var groups: Dictionary = {}
	if owner == null:
		return groups
	for card: CardInstance in owner.hand:
		if not CARD_SUITS.has(card.suit):
			continue
		if not groups.has(card.suit):
			groups[card.suit] = []
		(groups[card.suit] as Array).append(card.uid)
	return groups


## 恢复本技能创建的选择请求；返回 true 表示本次响应已由本技能处理。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == CHOICE_PICK_EFFECT:
		_continue_effect_selection(context, response)
		return true
	if choice_kind == CHOICE_PICK_SUIT:
		_continue_suit_selection(response)
		return true
	return false


## 恢复分支A的选牌与目标；取消或组合失效时重新选牌，不重新摸牌、不额外计次。
func _continue_effect_selection(context: Dictionary, response: ChoiceResponse) -> void:
	if not response.confirmed or response.card_ids.size() != 1:
		_reopen_effect_selection()
		return
	# 所选虚拟牌对应的真实牌名；占位UID由请求端口写入映射，技能侧不保存任何运行时状态。
	var definition_id: String = _resolve_virtual_definition_id(context, response.card_ids[0])
	if definition_id.is_empty():
		_reopen_effect_selection()
		return
	# 提交的目标数组；自动目标模式由核心层在执行时统一展开，这里只做完整合法性复核。
	var target_ids: Array[int] = []
	target_ids.assign(response.target_ids)
	if not host.card_rules.validate_virtual_use(owner_player_id, definition_id, target_ids).is_empty():
		_reopen_effect_selection()
		return
	if not bool(host.call("execute_cardless_virtual_card_use", owner_player_id, definition_id, target_ids, "", EMPTY_OVERRIDES, {"source_skill_id":get_id()})):
		_reopen_effect_selection()
		return
	# 使用记录：只有普通锦囊计入“未以此法使用过”的名单，【杀】可以重复使用。
	if definition_id != SLASH_DEFINITION_ID:
		host.call("add_skill_used_card_name", owner_player_id, get_id(), definition_id)
	announce_activation({"effect_definition_id":definition_id, "target_ids":target_ids.duplicate()})
	_refresh_display_description()


## 恢复分支B的花色选择；确认后弃置该花色全部手牌并把本阶段上限扩展为2。
func _continue_suit_selection(response: ChoiceResponse) -> void:
	if not response.confirmed:
		return
	# 所选花色；为空或不是实体花色时视为取消，不消耗任何手牌与次数。
	var suit: String = str(response.control_id)
	if not CARD_SUITS.has(suit):
		return
	# 技能持有者；异步选择期间可能已经死亡或离场。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 再枚举一次花色分组：选择期间手牌可能已经被其他效果改变，只弃置当前仍在手牌区的该花色牌。
	var suit_groups: Dictionary = _collect_suit_groups(owner)
	var suit_uids: Array[int] = []
	suit_uids.assign(suit_groups.get(suit, []) as Array)
	if suit_uids.is_empty():
		return
	# 本次发动计次与上限改写时机：弃置真正落地后才消耗次数并扩展上限，避免弃置被中断时白吃一次额度。
	var discarded_count: int = int(host.call("discard_selected_hand_cards", owner_player_id, suit_uids))
	if discarded_count <= 0:
		return
	_used_this_play_phase += 1
	_extended_limit_turn_number = host.state.turn_number
	announce_activation({"discarded_suit":suit, "discarded_count":discarded_count, "play_phase_limit":EXTENDED_PLAY_PHASE_LIMIT})


## 把占位UID翻译成真实牌名；普通实体UID不属于本技能的虚拟候选，返回空字符串由调用方按失效处理。
func _resolve_virtual_definition_id(context: Dictionary, candidate_uid: int) -> String:
	if candidate_uid < VIRTUAL_HAND_CANDIDATE_UID_BASE:
		return ""
	return str((context.get("virtual_hand_definition_ids_by_uid", {}) as Dictionary).get(str(candidate_uid), ""))


## 刷新技能描述中的已使用牌名展示；没有记录时还原为基础描述，避免残留上一局的旧文本。
func _refresh_display_description() -> void:
	if host == null or not host.has_method("set_skill_display_description"):
		return
	# 本局已以此法使用过的普通锦囊牌名；【杀】不写入名单，因此不会出现在提示中。
	var used_names: Array = host.call("get_skill_used_card_names", owner_player_id, get_id()) as Array
	if used_names.is_empty():
		host.call("set_skill_display_description", owner_player_id, get_id(), "")
		return
	# 展示用的中文牌名列表；顺序沿用记录顺序，玩家可以据此判断还剩哪些锦囊可用。
	var display_names: Array[String] = []
	for used_name_variant: Variant in used_names:
		display_names.append(GameSettings.resolve_card_name(GameDatabase.get_card(str(used_name_variant))))
	host.call("set_skill_display_description", owner_player_id, get_id(), "%s%s%s%s" % [str(get_metadata().get("description", "")), USED_NAMES_PREFIX, "、".join(display_names), USED_NAMES_SUFFIX])


## 为AI枚举本技能在当前出牌阶段的候选动作；只要 can_activate 成立就提供一个无参数技能动作。
##
## 基础状态不限次，因此AI在自己回合内会持续提供该动作，直到条件不再成立为止：
## 可用普通锦囊被逐个用尽、花色数达到4而转入分支B（分支B之后上限被改写为2）、
## 或不再存在带合法目标的候选项。全局的每回合AI动作上限是兜底保护，本技能不再自设上限。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})


## 本技能主动动作的AI评分；固定正收益，使AI在回合内满足条件时直接发动，不额外权衡花色分布。
func score_ai_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return AI_ACTION_BASE


## 本技能选择的AI评分；确认提交固定高于取消，花色选项优先弃置张数最少的花色。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, _evaluator: Object) -> float:
	# 当前选择请求上下文；非本技能创建的请求不参与评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind != CHOICE_PICK_EFFECT and choice_kind != CHOICE_PICK_SUIT:
		return 0.0
	# 当前动作负载；取消提交得到0分，因此确认提交一定能胜出。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	if choice_kind == CHOICE_PICK_SUIT:
		# 花色选项：弃置张数越少越好；张数相同时保持选项声明顺序给出的稳定偏好。
		# 控制类动作的选项字段是 selected_control_id，与 ChoiceResponse.control_id 是两个不同层级的稳定字段。
		var suit: String = str(payload.get("selected_control_id", ""))
		# 花色到张数的映射由请求上下文提供，AI只读取公开选择信息，不访问对局状态。
		var suit_card_counts: Dictionary = context.get("suit_card_counts", {}) as Dictionary
		return AI_COMMIT_REWARD - float(int(suit_card_counts.get(suit, 0))) * AI_SUIT_DISCARD_PENALTY
	# 选牌并选目标：优先选择能直接造成伤害的【杀】，其余效果按固定收益处理。
	var selected_card_uids: Array = payload.get("selected_card_uids", []) as Array
	if selected_card_uids.size() != 1:
		return 0.0
	# 所选虚拟牌对应的真实牌名；映射由请求端口写入，AI与玩家读取同一份可序列化数据。
	var definition_id: String = str((context.get("virtual_hand_definition_ids_by_uid", {}) as Dictionary).get(str(int(selected_card_uids[0])), ""))
	if definition_id.is_empty():
		return 0.0
	return AI_COMMIT_REWARD + (AI_SLASH_BONUS if definition_id == SLASH_DEFINITION_ID else 0.0)
