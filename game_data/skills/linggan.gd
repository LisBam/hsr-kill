extends SkillDefinition

## 【灵感】技能源码。出牌阶段限一次，视为使用一张【解构】记录的牌名的牌，
## 然后可令该牌的目标按另一张【解构】记录牌名的牌的目标结算；该牌结算完毕后移除【解构】中记录的这两张牌名。
##
## 原文中“另一张『解读』记录牌名的牌”里的【解读】在本武将技能表中并不存在，
## 按项目“技能描述原文一字不得改”的铁律保留原样，实际记录容器统一为【解构】的 recorded_card_names。

## 视为使用的效果牌名选择；控制项ID即牌名稳定ID。
const CHOICE_PICK_EFFECT: String = "linggan_pick_effect"

## 是否按另一张记录牌名结算目标的确认；取消表示沿用效果牌名自身的目标规则。
const CHOICE_CONFIRM_RETARGET: String = "linggan_confirm_retarget"

## 目标模式牌名选择；控制项ID即牌名稳定ID。
const CHOICE_PICK_TARGET_MODE: String = "linggan_pick_target_mode"

## 目标选择；目标ID来自权威虚拟牌目标枚举。
const CHOICE_SELECT_TARGETS: String = "linggan_select_targets"

## 每个出牌阶段的发动上限；数值1来自技能原文“出牌阶段限一次”。
const PLAY_PHASE_LIMIT: int = 1

## 禁止被记录与禁止作为候选的牌名；【无懈可击】是响应类锦囊，既不可被【解构】记录，
## 也不允许被【灵感】当作视为使用的牌名，此处再做一层防御性排除。
const WUXIE_DEFINITION_ID: String = "wuxie"

## 由整牌逻辑自行决定目标的模式；这些模式不询问玩家，直接交给权威目标规范化。
## 全体模式：【南蛮入侵】等群体锦囊不会打到使用者自己，也不会被玩家拆成“只指定部分目标”。
## 自指模式：【无中生有】等牌自动以使用者为目标，玩家不需要再点一下自己。
const AUTO_TARGET_MODES: Array[String] = ["all_others", "all_players", "self", "self_wounded"]

## 目标重定向补丁覆盖的定义字段；只覆盖目标规则，不触碰效果、次数与响应模式。
const TARGET_RULE_FIELDS: Array[String] = ["target_mode", "min_targets", "max_targets", "distance_limit"]

## 未提供补丁时使用的空覆写；抽取为常量避免每次结算重复构造空字典。
const EMPTY_OVERRIDES: Dictionary = {}

## AI对“把单体锦囊改成群体目标”的偏好系数；数值越高，AI越倾向把记录到的单体牌当群体牌使用。
const AI_MULTITARGET_BONUS: float = 1.5

## AI对“把群体锦囊改成单体目标”的偏好系数；用于避免误伤队友时的保守选择。
const AI_SINGLE_TARGET_RETREAT: float = 1.0

## 当前出牌阶段已发动次数；进入每个出牌阶段复原，实现原文“出牌阶段限一次”。
var _used_this_play_phase: int = 0


## 写入主动技静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"linggan",
		"name":"灵感",
		"trigger":"active/phaseUse",
		"enable":"phaseUse",
		"ui_enabled":true,
		"description":"出牌阶段限一次，你可以视为使用一张“解构”记录的牌名的牌，然后可令该牌的目标按另一张“解读”记录牌名的牌的目标结算。该牌结算完毕后，移除“解构”中记录的这两张牌名。",
	})


## 订阅出牌阶段开始以复原阶段额度。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")


## 每个出牌阶段复原“限一次”额度；普通与额外出牌阶段一视同仁。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = 0


## 检查出牌阶段归属、阶段额度与记录中是否存在可选牌名；目标合法性在目标选择阶段判断。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	if _used_this_play_phase >= PLAY_PHASE_LIMIT:
		return false
	# 已存在待处理选择时不再开放入口；控制器会拒绝第二个请求，提前拦下可避免按钮空点。
	# 该检查同时保证“选择过程中取消”之后按钮立即恢复可用。
	if host.has_pending_card_choice():
		return false
	return not _get_effect_name_options(owner, []).is_empty()


## 询问以哪一张记录的牌名作为视为使用的效果；后续步骤在恢复回调中推进。
func activate(_context: Dictionary = {}) -> String:
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not can_activate():
		return "【灵感】当前不满足发动条件。"
	var options: Array[Dictionary] = _get_effect_name_options(owner, [])
	if options.is_empty():
		return "【灵感】没有可用的记录牌名。"
	request_control_selection_for_player(owner_player_id, "灵感", "选择一张记录的牌名作为视为使用的牌", options, true, {"kind":CHOICE_PICK_EFFECT}, true)
	return ""


## 分步恢复【灵感】的四个选择步骤；任何一步取消都不消耗次数、不移除记录。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	var context_kind: String = str(context.get("kind", ""))
	# 技能持有者；权威状态在异步选择期间可能变化，每一步都要复核。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return true
	if context_kind == CHOICE_PICK_EFFECT:
		# 第一步取消：整体放弃，不消耗次数、不移除记录。
		if not response.confirmed or response.control_id.is_empty():
			return true
		var effect_id: String = response.control_id
		if not owner.recorded_card_names.has(effect_id):
			return true
		# 记录中若不存在其他可用牌名，原文的“另一张记录牌名”无从选择，
		# 此时跳过第二步询问，直接按效果牌名自身的目标规则结算，避免出现无意义的确认。
		if _get_effect_name_options(owner, [effect_id]).is_empty():
			_begin_target_selection(effect_id, "")
			return true
		# 第二步：询问是否改按另一张记录牌名的目标结算。
		request_card_selection("灵感", "是否令该牌的目标按另一张记录的牌名的牌结算？", [], 0, 0, true, {"kind":CHOICE_CONFIRM_RETARGET, "effect_id":effect_id, "ai_allow_confirm":true})
		return true
	if context_kind == CHOICE_CONFIRM_RETARGET:
		var effect_definition_id: String = str(context.get("effect_id", ""))
		if effect_definition_id.is_empty() or not owner.recorded_card_names.has(effect_definition_id):
			return true
		# 第二步取消：不使用目标重定向，直接按效果牌名自身的目标规则进入目标选择。
		if not response.confirmed:
			_begin_target_selection(effect_definition_id, "")
			return true
		# 第三步：选择决定目标模式的牌名，必须排除无懈可击与第一步已选的牌名。
		var options: Array[Dictionary] = _get_effect_name_options(owner, [effect_definition_id])
		if options.is_empty():
			_begin_target_selection(effect_definition_id, "")
			return true
		request_control_selection_for_player(owner_player_id, "灵感", "选择决定目标结算方式的记录牌名", options, true, {"kind":CHOICE_PICK_TARGET_MODE, "effect_id":effect_definition_id}, true)
		return true
	if context_kind == CHOICE_PICK_TARGET_MODE:
		var effect_id: String = str(context.get("effect_id", ""))
		if effect_id.is_empty() or not owner.recorded_card_names.has(effect_id):
			return true
		# 第三步取消：与第二步取消等价，回退到不重定向。
		var target_mode_id: String = response.control_id if response.confirmed else ""
		if not target_mode_id.is_empty() and (target_mode_id == effect_id or not owner.recorded_card_names.has(target_mode_id)):
			target_mode_id = ""
		_begin_target_selection(effect_id, target_mode_id)
		return true
	if context_kind == CHOICE_SELECT_TARGETS:
		# 目标选择取消：不消耗次数、不移除记录，玩家可以重新发动【灵感】。
		if not response.confirmed:
			return true
		var final_effect_id: String = str(context.get("effect_id", ""))
		var final_target_mode_id: String = str(context.get("target_mode_id", ""))
		_execute_virtual_use(final_effect_id, final_target_mode_id, response.target_ids)
		return true
	return false


## 建立目标选择请求；全体模式直接交给整牌逻辑展开，其余模式走权威目标枚举。
func _begin_target_selection(effect_id: String, target_mode_id: String) -> void:
	if effect_id.is_empty():
		return
	# 合并后的最终定义；目标模式可能已被另一张记录牌名覆写。
	# 目标数量与模式必须与最终提交校验读取同一份定义，否则会出现“可选但提交被拒”。
	var definition: Dictionary = _resolve_target_definition(effect_id, target_mode_id)
	var target_mode: String = str(definition.get("target_mode", ""))
	# 自动决定目标的模式：目标由执行入口的 normalize_targets 统一展开，不询问玩家。
	# 这既保证“所有其他角色”不会包含使用者自己，也避免群体锦囊被拆成“只指定部分目标”，
	# 同时让【无中生有】这类自指牌自动选中使用者，不需要玩家再点一下自己。
	if AUTO_TARGET_MODES.has(target_mode):
		_execute_virtual_use(effect_id, target_mode_id, [])
		return
	# 非全体模式：只有存在合法目标才建立请求，避免空效果。
	var rule_overrides: Dictionary = _build_rule_overrides(effect_id, target_mode_id)
	var legal_target_ids: Array[int] = host.card_rules.list_legal_virtual_targets(owner_player_id, effect_id, rule_overrides)
	if legal_target_ids.is_empty():
		return
	request_target_selection("选择【灵感】视为使用的牌的目标", legal_target_ids, maxi(int(definition.get("min_targets", 0)), 1), maxi(int(definition.get("max_targets", 0)), 1), true, {"kind":CHOICE_SELECT_TARGETS, "effect_id":effect_id, "target_mode_id":target_mode_id})


## 执行视为使用；成功结算后按原文移除【解构】中记录的本次使用的牌名。
func _execute_virtual_use(effect_id: String, target_mode_id: String, target_ids: Array[int]) -> void:
	if effect_id.is_empty():
		return
	var rule_overrides: Dictionary = _build_rule_overrides(effect_id, target_mode_id)
	var used: bool = bool(host.call("execute_cardless_virtual_card_use", owner_player_id, effect_id, target_ids, "", rule_overrides, {"source_skill_id":get_id()}))
	if not used:
		return
	# 次数消费时机：只有“视为使用”真正成立才占用“出牌阶段限一次”额度。
	# 放在这里而不是建立选择请求时，使任何一步取消（含目标选择取消）都不消耗次数。
	_used_this_play_phase += 1
	# 移除时机：该牌已进入结算流程后才摘除记录，避免结算中断导致记录提前丢失。
	host.call("remove_recorded_card_name", owner_player_id, effect_id)
	if not target_mode_id.is_empty() and target_mode_id != effect_id:
		host.call("remove_recorded_card_name", owner_player_id, target_mode_id)
	announce_activation({"effect_definition_id":effect_id, "target_mode_definition_id":target_mode_id})


## 构造虚拟牌覆写；目标重定向通过通用定义补丁实现，核心层不含任何牌名特例。
func _build_rule_overrides(effect_id: String, target_mode_id: String) -> Dictionary:
	if target_mode_id.is_empty() or target_mode_id == effect_id:
		return EMPTY_OVERRIDES
	var effect_definition: Dictionary = GameDatabase.get_card(effect_id)
	if effect_definition.is_empty():
		return EMPTY_OVERRIDES
	return {"definition_patch":_build_target_rule_patch(effect_definition, target_mode_id)}


## 返回效果牌名与目标牌名合并后的定义；目标牌名为空或与效果相同时返回效果牌自身定义。
func _resolve_target_definition(effect_id: String, target_mode_id: String) -> Dictionary:
	var effect_definition: Dictionary = GameDatabase.get_card(effect_id)
	if target_mode_id.is_empty() or target_mode_id == effect_id:
		return effect_definition
	return _merge_target_rules(effect_definition, target_mode_id)


## 按目标模式牌名抽取目标规则补丁；只覆盖目标相关字段，效果与次数仍由效果牌名决定。
func _build_target_rule_patch(effect_definition: Dictionary, target_mode_id: String) -> Dictionary:
	var target_definition: Dictionary = GameDatabase.get_card(target_mode_id)
	if target_definition.is_empty():
		return {}
	var patch: Dictionary = {}
	for field_name: String in TARGET_RULE_FIELDS:
		if target_definition.has(field_name):
			patch[field_name] = target_definition[field_name]
	return patch


## 生成用于读取数量区间的合并定义；与核心层 _resolve_definition 使用同一套按键覆写语义。
func _merge_target_rules(effect_definition: Dictionary, target_mode_id: String) -> Dictionary:
	var merged: Dictionary = effect_definition.duplicate(true)
	merged.merge(_build_target_rule_patch(effect_definition, target_mode_id), true)
	return merged


## 返回可选的记录牌名控制项；排除无懈可击与调用方指定的已用牌名。
func _get_effect_name_options(owner: PlayerState, excluded_ids: Array) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for definition_id: String in owner.recorded_card_names:
		if definition_id == WUXIE_DEFINITION_ID or excluded_ids.has(definition_id):
			continue
		var definition: Dictionary = GameDatabase.get_card(definition_id)
		if definition.is_empty():
			continue
		# 展示名跟随当前名称模式；不同模式下手牌与选项使用同一套译名。
		var label: String = GameSettings.resolve_card_name(definition)
		options.append({"id":definition_id, "label":label})
	return options


## 为AI枚举候选动作；本技能只提交一个空负载动作，具体选择交给后续选牌/选目标请求。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})


## 评估【灵感】四步选择的每一项；牌面收益取自卡牌定义自带的 ai.value，并叠加目标模式变化。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var context_kind: String = str(context.get("kind", ""))
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var selected_control_id: String = str(payload.get("selected_control_id", ""))
	if context_kind == CHOICE_PICK_EFFECT:
		# 取消不加成；选择牌名时按该牌自身的AI价值排序，并额外奖励“能解锁目标重定向”的牌名。
		if not bool(payload.get("confirmed", false)) or selected_control_id.is_empty():
			return 0.0
		return _score_definition_name(selected_control_id) + _count_retarget_partners(choice_request)
	if context_kind == CHOICE_PICK_TARGET_MODE:
		# 目标模式评分相对效果牌名计算：单体变群体加分，群体变单体适度加分（避免误伤）。
		if not bool(payload.get("confirmed", false)) or selected_control_id.is_empty():
			return 0.0
		return _score_target_mode(str(context.get("effect_id", "")), selected_control_id)
	if context_kind == CHOICE_CONFIRM_RETARGET:
		# 确认重定向的基础分为正；没有任何可用伙伴牌名时由第一步的伙伴计数拉低整体期望。
		return 1.0 if bool(payload.get("confirmed", false)) else 0.0
	if context_kind == CHOICE_SELECT_TARGETS:
		# 目标选择交由通用策略按态度与收益评分，本技能不重复干预。
		return 0.0
	return 0.0


## 读取卡牌定义自带的AI价值；缺失时回退到中性值，保证选项之间仍可比较。
func _score_definition_name(definition_id: String) -> float:
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	if definition.is_empty():
		return 0.0
	var ai_data: Dictionary = definition.get("ai", {}) as Dictionary
	return float(ai_data.get("value", 1.0))


## 统计可作为目标模式伙伴的牌名数量；越多说明重定向的选择空间越大。
func _count_retarget_partners(choice_request: Dictionary) -> float:
	var partner_count: int = 0
	for candidate_variant: Variant in choice_request.get("control_options", []) as Array:
		var option: Dictionary = candidate_variant as Dictionary
		if not str(option.get("id", "")).is_empty():
			partner_count += 1
	return 0.1 * float(maxi(partner_count - 1, 0))


## 评估目标模式变化：目标上限提高视为单体转群体，目标上限降低视为群体转单体。
func _score_target_mode(effect_id: String, target_mode_id: String) -> float:
	var effect_definition: Dictionary = GameDatabase.get_card(effect_id)
	var target_definition: Dictionary = GameDatabase.get_card(target_mode_id)
	if effect_definition.is_empty() or target_definition.is_empty():
		return 0.0
	var effect_maximum: int = int(effect_definition.get("max_targets", 1))
	var target_maximum: int = int(target_definition.get("max_targets", 1))
	var score: float = _score_definition_name(target_mode_id)
	if target_maximum > effect_maximum:
		score += AI_MULTITARGET_BONUS
	elif target_maximum < effect_maximum:
		score += AI_SINGLE_TARGET_RETREAT
	return maxf(score, 0.5)
