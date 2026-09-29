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

## 卡牌未声明可用AI价值（或声明为空数组、非数值）时使用的保底牌面价值。
## 取 1.0 是为了让该牌名仍可参与组合排序，而不是因为缺失就被判成“毫无价值的组合”；
## 与 touxia / xifa 两个技能的同名常量保持同一口径。
const AI_DEFAULT_CARD_VALUE: float = 1.0

## 发动【灵感】的基础AI评分；只要记录中存在可用于“视为使用”的牌名就给严格正分。
## 基类 score_ai_action 默认返回 0.0，不覆盖会让AI判定本技能毫无价值而永不发动，
## 使【解构】记录下来的牌名完全用不上。
const AI_ACTIVATION_BASE: float = 2.0

## 选择“视为使用的效果牌名”与“决定目标结算方式的牌名”时的保底确认分。
## 这两步一旦取消，技能就退回未发动状态（不消耗次数、不移除记录），
## 而取消动作在通用策略里恒为0分；技能若不给显著正分，AI 会在同一出牌阶段反复“发动→取消”，
## 直到撞上 max_ai_actions_per_turn 被强制结束回合。保底分取一个远高于任何牌面收益的固定值，
## 具体组合之间的优劣由叠加的收益小数决定，排序结果不受影响。
const AI_COMBINATION_COMMIT_REWARD: float = 100.0

## 目标选择的保底确认分；走到这一步说明组合已经选定，取消同样不消耗次数，必须避免AI在此空转。
const AI_TARGET_COMMIT_REWARD: float = 100.0

## 目标收益权重；单个目标的收益按 `效果目标方向 × 敌我态度 × 权重` 计算。
## 权重必须足够大，才能压过通用目标评分“只读取首个目标态度、且不乘效果方向”带来的偏差：
## 通用项的量级是 `态度 / 5.0`，即对自己约 `+2.0`、对敌人约 `-0.8`，而目标组合之间的
## 真实差异只有零点几分，因此必须放大。取 `2.0` 后，一名敌人（态度 `-4`）贡献 `+4.0`、
## 使用者自己（态度 `+10`）贡献 `-10.0`，于是“两名敌人”的组合必然高于“一名敌人加一名自己”，
## 也高于任何包含自己或队友的组合。该权重只影响目标组合之间的排序，不影响“确认还是取消”。
const AI_TARGET_RESULT_WEIGHT: float = 2.0

## 组合不可结算时使用的哨兵值；AI 必须完全跳过这类组合，因为技能在无合法目标时会静默返回。
const AI_COMBINATION_UNAVAILABLE: float = -INF

## 二段不优于单段时的取消分；必须为负分才能让“取消”真正胜出。
## 通用选择评分对“已确认但无牌无目标”的动作有一条 `+0.1` 的兜底分，而“取消”恒为 `0.0`；
## 因此技能若在放弃二段时只给 `0.0`，确认动作仍会以 `0.1` 胜出，AI 会无条件启用二段。
## 取一个绝对值明显大于该兜底分的固定惩罚，确保“二段只在严格更优时才启用”这一口径真实生效。
const AI_RETARGET_DECLINE_PENALTY: float = 5.0

## 目标规模的每目标系数；在“目标上限提高”的固定加分之外，按实际多覆盖的角色数线性追加收益。
## 对目标不利的效果（伤害、拆牌、牵牌、横置、跳阶段）多覆盖一名角色就多一份收益，
## 且**获得队友的牌同样不是负收益**（牌进入使用者手中，队伍总资源不减少），因此这类效果的目标数量
## 应当单调递增计价：例如【顺手牵羊】的效果配上【铁索连环】的目标规则从 1 人变为 2 人、
## 配上【南蛮入侵】的目标规则在 8 人局里覆盖 7 名其他角色，后者的收益必须明显更高。
## 对目标有利的增益效果不使用该系数：它多覆盖的目标里可能包含对手，净收益改由
## _score_group_targets_for_ai 按接受者敌我关系计价。
const AI_TARGET_SCALE_STEP: float = 1.0

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
		"description":"出牌阶段限一次，你可以视为使用一张“解构”记录的牌名的牌，然后可令该牌的目标按另一张“解构”记录牌名的牌的目标结算。该牌结算完毕后，移除“解构”中记录的这两张牌名。",
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


## 计算【灵感】发动动作本身的AI评分。
## 基类 score_ai_action 默认返回 0.0，不覆盖会让AI认为本技能毫无价值而永不发动，
## 使【解构】记录的牌名全部闲置。记录中存在可用于“视为使用”的牌名时才给正分；
## 【无懈可击】虽可被重铸但不能被记录，过滤口径与 _get_effect_name_options 保持一致。
## 口径补充：这里进一步要求“至少存在一个能被真正结算的效果×目标组合”。
## 组合不可结算时技能会在建立目标请求前静默返回，既不消耗次数也不移除记录，
## AI 若按“记录非空”就发动，就会反复选中同一个不可结算的组合直到撞上动作上限。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	var usable_names: Array = _get_recorded_names_for_ai(authoritative_snapshot)
	if usable_names.is_empty():
		return 0.0
	for recorded_name_variant: Variant in usable_names:
		# 当前记录牌名的可结算性；只要有一个牌名可结算就发动，避免无谓的全组合遍历。
		if _has_feasible_combination_for_ai(authoritative_snapshot, str(recorded_name_variant), evaluator):
			return AI_ACTIVATION_BASE
	return 0.0


## 从权威快照读取持有者可用于【灵感】的记录牌名；AI钩子没有宿主，只能按稳定玩家ID在快照中定位自己。
## 排除【无懈可击】的口径与 _get_effect_name_options 完全一致，避免AI按“存在候选”发动、实际却选不出效果。
func _get_recorded_names_for_ai(authoritative_snapshot: Dictionary) -> Array:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		var player_snapshot: Dictionary = player_variant as Dictionary
		if int(player_snapshot.get("player_id", -1)) != owner_player_id:
			continue
		var usable_names: Array = []
		for name_variant: Variant in player_snapshot.get("recorded_card_names", []) as Array:
			# 当前记录牌名；响应类锦囊不参与“视为使用”，必须排除。
			var definition_id: String = str(name_variant)
			if definition_id == WUXIE_DEFINITION_ID:
				continue
			usable_names.append(definition_id)
		return usable_names
	return []


## 为AI枚举候选动作；本技能只提交一个空负载动作，具体选择交给后续选牌/选目标请求。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})


## 评估【灵感】四步选择的每一项；牌面收益取自卡牌定义自带的 ai.value，并叠加目标模式变化。
## 口径补充：先遍历“效果牌名 × 目标牌名”的全部组合，选出收益最高且能真正结算的组合，再让每一步按同一组合作答：
## ①选择效果牌名时给出“该牌名能达成的最优组合收益”；
## ②确认重定向时只在“二段严格优于单段”才确认，否则保持0分让通用策略取消，即只用一种牌名结算；
## ③选择目标牌名时给出该组合自身的收益，保证与第一步选中的是同一个组合；
## ④目标选择给出保底正分，保证选中的组合一定完成一次真实结算。
## 前两步的保底分远高于任何牌面收益，因此“是否确认”不受通用手牌费用评分影响，只受组合优劣影响。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var context_kind: String = str(context.get("kind", ""))
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var selected_control_id: String = str(payload.get("selected_control_id", ""))
	var confirmed: bool = bool(payload.get("confirmed", false))
	if context_kind == CHOICE_PICK_EFFECT:
		# 取消不加成；选择牌名时按该牌自身的AI价值排序，并额外奖励“能解锁目标重定向”的牌名。
		if not confirmed or selected_control_id.is_empty():
			return 0.0
		# 该效果牌名在整个组合空间中的最高收益；没有任何可结算组合时返回哨兵值。
		var best_combination: float = _score_best_combination_for_ai(authoritative_snapshot, selected_control_id, evaluator)
		if not is_finite(best_combination):
			return 0.0
		return AI_COMBINATION_COMMIT_REWARD + best_combination + _count_retarget_partners(choice_request)
	if context_kind == CHOICE_PICK_TARGET_MODE:
		# 目标模式评分相对效果牌名计算：单体变群体加分，群体变单体适度加分（避免误伤）。
		if not confirmed or selected_control_id.is_empty():
			return 0.0
		# 第一步已经选定效果牌名；这里只在该效果牌名之下比较目标牌名，保证两次选择指向同一个组合。
		var target_mode_combination: float = _score_combination_for_ai(authoritative_snapshot, str(context.get("effect_id", "")), selected_control_id, evaluator)
		if not is_finite(target_mode_combination):
			return 0.0
		return AI_COMBINATION_COMMIT_REWARD + target_mode_combination
	if context_kind == CHOICE_CONFIRM_RETARGET:
		# 确认重定向的基础分为正；没有任何可用伙伴牌名时由第一步的伙伴计数拉低整体期望。
		if not confirmed:
			return 0.0
		# 只有二段严格优于单段才确认；否则保持0分，由通用策略取消并改用一种牌名单独结算。
		# 口径补充：通用评分给“已确认”动作的兜底分是 +0.1、给“取消”动作是 0.0，
		# 因此这里必须给出负分，取消才会真正成为更优解；只返回0会让二段被无条件启用。
		if not _should_retarget_for_ai(authoritative_snapshot, str(context.get("effect_id", "")), evaluator):
			return -AI_RETARGET_DECLINE_PENALTY
		return AI_COMBINATION_COMMIT_REWARD
	if context_kind == CHOICE_SELECT_TARGETS:
		# 目标选择交由通用策略按态度与收益评分，本技能不重复干预。
		# 但取消会让技能退回未发动状态，因此确认动作必须给出保底正分，避免AI在“选目标→取消”之间空转。
		# 口径补充：通用目标评分只读取首个目标的态度、且不乘效果自身的目标方向，
		# 对【铁索连环】这类“对目标不利”的效果会把目标判给态度最高的使用者自己。
		# 因此这里必须覆盖：按效果方向逐目标累加收益，多目标组合自然高于少目标组合。
		if not confirmed:
			return 0.0
		return AI_TARGET_COMMIT_REWARD + _score_selected_targets_for_ai(authoritative_snapshot, context, payload, evaluator)
	return 0.0


## 判断指定效果牌名是否存在至少一个可结算组合；找到第一个即返回，用于发动判定做快速预筛。
## 与 _score_best_combination_for_ai 判定同一套可行性规则，但不需要算出具体收益，因此提前退出。
func _has_feasible_combination_for_ai(authoritative_snapshot: Dictionary, effect_id: String, evaluator: Object) -> bool:
	if effect_id.is_empty():
		return false
	# 效果牌静态定义；所有候选目标牌名都要与它合并，取一次即可复用到每个组合。
	var effect_definition: Dictionary = GameDatabase.get_card(effect_id)
	if effect_definition.is_empty():
		return false
	if _is_combination_feasible_for_ai(authoritative_snapshot, effect_definition, "", evaluator):
		return true
	for target_mode_id_variant: Variant in _get_retarget_name_options_for_ai(authoritative_snapshot, [effect_id]):
		if _is_combination_feasible_for_ai(authoritative_snapshot, effect_definition, str(target_mode_id_variant), evaluator):
			return true
	return false


## 遍历“效果牌名 × 目标牌名”的全部组合，返回该效果牌名能达到的最高收益。
## 单段（只使用效果牌名自身的目标规则）始终参与比较，因为原文允许不使用第二张牌名。
## 所有组合都不可结算时返回哨兵值，调用方据此判定该牌名不能选。
func _score_best_combination_for_ai(authoritative_snapshot: Dictionary, effect_id: String, evaluator: Object) -> float:
	if effect_id.is_empty():
		return AI_COMBINATION_UNAVAILABLE
	var best_score: float = _score_combination_for_ai(authoritative_snapshot, effect_id, "", evaluator)
	for target_mode_id_variant: Variant in _get_retarget_name_options_for_ai(authoritative_snapshot, [effect_id]):
		best_score = maxf(best_score, _score_combination_for_ai(authoritative_snapshot, effect_id, str(target_mode_id_variant), evaluator))
	return best_score


## 判断二段方案是否严格优于单段；只有严格更优才让AI确认重定向。
## 单段不可结算而二段可结算时同样返回真：此时二段是唯一能完成结算的方案。
func _should_retarget_for_ai(authoritative_snapshot: Dictionary, effect_id: String, evaluator: Object) -> bool:
	if effect_id.is_empty():
		return false
	var single_score: float = _score_combination_for_ai(authoritative_snapshot, effect_id, "", evaluator)
	var best_retarget_score: float = AI_COMBINATION_UNAVAILABLE
	for target_mode_id_variant: Variant in _get_retarget_name_options_for_ai(authoritative_snapshot, [effect_id]):
		best_retarget_score = maxf(best_retarget_score, _score_combination_for_ai(authoritative_snapshot, effect_id, str(target_mode_id_variant), evaluator))
	if not is_finite(best_retarget_score):
		return false
	if not is_finite(single_score):
		return true
	return best_retarget_score > single_score


## 返回可以充当目标模式的记录牌名；排除调用方指定的已用牌名，口径与 _get_effect_name_options 一致。
## AI钩子没有宿主，只能从权威快照读取记录容器，因此这里不依赖选择请求提供的控制项列表。
func _get_retarget_name_options_for_ai(authoritative_snapshot: Dictionary, excluded_ids: Array) -> Array[String]:
	var result: Array[String] = []
	for definition_id_variant: Variant in _get_recorded_names_for_ai(authoritative_snapshot):
		var definition_id: String = str(definition_id_variant)
		if excluded_ids.has(definition_id):
			continue
		result.append(definition_id)
	return result


## 评估一个“效果牌名 × 目标牌名”组合的收益；不可结算的组合返回哨兵值，使其永远不会被选中。
## 目标牌名为空表示不使用二段，收益完全由效果牌名自身的牌面价值决定。
## 收益由两部分组成：目标规则变化带来的牌面差异，以及“无法挑选目标”的群体模式实际会把效果送给谁。
func _score_combination_for_ai(authoritative_snapshot: Dictionary, effect_id: String, target_mode_id: String, evaluator: Object) -> float:
	if effect_id.is_empty():
		return AI_COMBINATION_UNAVAILABLE
	var effect_definition: Dictionary = GameDatabase.get_card(effect_id)
	if effect_definition.is_empty():
		return AI_COMBINATION_UNAVAILABLE
	if not _is_combination_feasible_for_ai(authoritative_snapshot, effect_definition, target_mode_id, evaluator):
		return AI_COMBINATION_UNAVAILABLE
	# 合并后的最终定义；目标模式来自另一张牌名时只覆盖目标规则，与结算读取同一套补丁语义。
	var merged_definition: Dictionary = effect_definition
	if not target_mode_id.is_empty() and target_mode_id != effect_id:
		merged_definition = _merge_target_rules(effect_definition, target_mode_id)
	if target_mode_id.is_empty() or target_mode_id == effect_id:
		return _score_definition_name(effect_id) + _score_group_targets_for_ai(authoritative_snapshot, merged_definition, evaluator)
	return _score_target_mode(effect_id, target_mode_id) + _score_target_scale_for_ai(authoritative_snapshot, effect_definition, merged_definition, evaluator) + _score_group_targets_for_ai(authoritative_snapshot, merged_definition, evaluator)


## 按“实际能多覆盖几名角色”追加目标规模收益；只对目标不利的效果生效。
## `_score_target_mode` 已经为“目标上限提高”这件事给过一次固定加分，因此这里只计算**超出第一个目标之外**
## 的部分，两者相加后“覆盖所有角色”才会明显高于“只多覆盖一个人”，落实“目标越多收益越高”的直觉。
## 目标候选数按当前快照实算，所以距离限制、目标区域是否为空、对手是否已阵亡都会真实反映在规模上。
func _score_target_scale_for_ai(authoritative_snapshot: Dictionary, effect_definition: Dictionary, merged_definition: Dictionary, evaluator: Object) -> float:
	# 效果对目标的方向；只有伤害、拆牌、牵牌、横置、跳阶段这类不利效果才随目标数量线性增长。
	var effect_target_result: float = float((effect_definition.get("ai", {}) as Dictionary).get("target_result", 0.0))
	if effect_target_result >= 0.0:
		return 0.0
	# 使用者快照；目标候选统计需要按模式排除自己，并读取距离与攻击范围。
	var owner_snapshot: Dictionary = _get_owner_snapshot_for_ai(authoritative_snapshot)
	if owner_snapshot.is_empty():
		return 0.0
	# 效果自身规则能覆盖的角色数；作为“不做二段”时的规模基准。
	var effect_scale: int = _count_coverable_targets_for_ai(authoritative_snapshot, owner_snapshot, effect_definition, evaluator)
	# 合并后规则能覆盖的角色数；差值即本次二段带来的规模变化。
	var merged_scale: int = _count_coverable_targets_for_ai(authoritative_snapshot, owner_snapshot, merged_definition, evaluator)
	# 规模增量；正数表示覆盖更多角色，负数表示被收窄。首个目标的变化已由 _score_target_mode 计价，故先扣除1。
	var scale_delta: int = merged_scale - effect_scale
	if scale_delta > 0:
		return float(scale_delta - 1) * AI_TARGET_SCALE_STEP
	if scale_delta < 0:
		return float(scale_delta + 1) * AI_TARGET_SCALE_STEP
	return 0.0


## 统计某套目标规则在“能覆盖多少角色”意义上的目标规模；只用于比较组合前后的规模变化。
## 自动展开的群体模式按**实际覆盖的存活角色数**计（而不是配置里写的上限 `99`），
## 显式目标模式取“配置上限”与“当前候选数”的较小值，因此距离、手牌、装备等限制都会体现在该值上。
## 自指模式固定为 `1`：使用者永远是自己这唯一目标，与候选数无关。
func _count_coverable_targets_for_ai(authoritative_snapshot: Dictionary, owner_snapshot: Dictionary, definition: Dictionary, evaluator: Object) -> int:
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode == "self" or target_mode == "self_wounded":
		return 1
	# 当前候选目标数；内部已按存活、离场、目标区域条件与距离限制过滤。
	var candidate_count: int = _count_target_candidates_for_ai(authoritative_snapshot, owner_snapshot, definition, target_mode, evaluator)
	if target_mode == "all_others" or target_mode == "all_players":
		return candidate_count
	return mini(maxi(int(definition.get("max_targets", 1)), 1), candidate_count)


## 评估“不询问目标、由整牌逻辑自动展开”的群体模式实际会把效果送给谁。
## 这类模式（`all_others`、`all_players`）无法挑选目标，因此“目标更多”不等于“收益更高”：
## 对目标有利的增益与回复（`target_result > 0`）一旦送给敌方就是净亏损，
## 于是这里按与其他目标评分相同的公式逐角色累加 `效果方向 × 敌我态度 × 权重`，
## 队友多时为正、对手多时为负，使 AI 不会为了追求目标数量而把摸牌与回复交给对手。
## 对目标不利的效果不需要该修正：送给敌方本来就是正收益，目标数量已由目标上限变化量体现。
func _score_group_targets_for_ai(authoritative_snapshot: Dictionary, definition: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode != "all_others" and target_mode != "all_players":
		return 0.0
	# 效果对目标的方向；只有增益类才需要按接受者敌我关系计价。
	var target_result: float = float((definition.get("ai", {}) as Dictionary).get("target_result", 0.0))
	if target_result <= 0.0:
		return 0.0
	# 逐角色累加收益；all_others 排除使用者自身，all_players 包含自身（使用者对自身态度为正）。
	var score: float = 0.0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		var player_snapshot: Dictionary = player_variant as Dictionary
		if not bool(player_snapshot.get("alive", false)) or bool(player_snapshot.get("out_of_game", false)):
			continue
		var player_id: int = int(player_snapshot.get("player_id", -1))
		if target_mode == "all_others" and player_id == owner_player_id:
			continue
		score += target_result * float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, player_id)) * AI_TARGET_RESULT_WEIGHT
	return score


## 判断一个效果×目标组合在当前权威快照下能否真正完成结算。
## 技能在“没有合法目标”时会静默返回（不消耗次数、不移除记录），AI 一旦选中这种组合，
## 就会在同一出牌阶段反复发动同一个组合，因此这里必须在评分阶段就把它排除。
## 判断只读取快照与卡牌静态定义，任何无法确认的情况都按“不可结算”处理，宁可少发动也不空转。
func _is_combination_feasible_for_ai(authoritative_snapshot: Dictionary, effect_definition: Dictionary, target_mode_id: String, evaluator: Object) -> bool:
	# 合并后的最终定义；目标模式取自另一张记录牌名时只覆盖目标规则，与技能结算读取同一套补丁语义。
	var definition: Dictionary = effect_definition
	if not target_mode_id.is_empty() and target_mode_id != str(effect_definition.get("id", "")):
		definition = _merge_target_rules(effect_definition, target_mode_id)
	if definition.is_empty():
		return false
	# 次数上限：阶段/回合额度用尽时权威目标枚举会直接返回空，组合不可结算。
	if not _is_play_limit_available_for_ai(authoritative_snapshot, definition):
		return false
	var owner_snapshot: Dictionary = _get_owner_snapshot_for_ai(authoritative_snapshot)
	if owner_snapshot.is_empty():
		return false
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode == "self":
		return true
	if target_mode == "self_wounded":
		# 自指受伤牌在满体力时没有任何合法目标，属于不可结算组合。
		return int(owner_snapshot.get("hp", 0)) < int(owner_snapshot.get("max_hp", 0))
	if target_mode == "all_players":
		return true
	if target_mode == "all_others":
		# 群体牌至少要有一名其他存活角色，否则展开后目标为空、视为使用会直接失败。
		return _count_target_candidates_for_ai(authoritative_snapshot, owner_snapshot, definition, target_mode, evaluator) >= 1
	# 显式目标模式：候选目标数必须达到原文要求的最低目标数。
	var required_targets: int = maxi(int(definition.get("min_targets", 1)), 1)
	return _count_target_candidates_for_ai(authoritative_snapshot, owner_snapshot, definition, target_mode, evaluator) >= required_targets


## 统计快照中满足目标模式基础条件的候选目标数量；只复刻可在快照层面确定的条件，
## 距离与状态限制之外的特殊校验仍由权威目标枚举在结算前复核。
func _count_target_candidates_for_ai(authoritative_snapshot: Dictionary, owner_snapshot: Dictionary, definition: Dictionary, target_mode: String, evaluator: Object) -> int:
	var owner_id: int = int(owner_snapshot.get("player_id", -1))
	# 不允许以自己为目标的模式；与权威目标校验的排除范围保持一致。
	var others_only_modes: Array[String] = ["all_others", "single_other", "single_other_with_cards", "weapon_holder"]
	var candidate_count: int = 0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		var target_snapshot: Dictionary = player_variant as Dictionary
		if not bool(target_snapshot.get("alive", false)) or bool(target_snapshot.get("out_of_game", false)):
			continue
		var target_id: int = int(target_snapshot.get("player_id", -1))
		if others_only_modes.has(target_mode) and target_id == owner_id:
			continue
		if target_mode == "single_other_with_cards":
			var target_hand: Array = target_snapshot.get("hand", []) as Array
			var target_equipment: Dictionary = target_snapshot.get("equipment", {}) as Dictionary
			var target_judgment: Array = target_snapshot.get("judgment_area", []) as Array
			if target_hand.is_empty() and target_equipment.is_empty() and target_judgment.is_empty():
				continue
		if target_mode == "single_with_hand" and (target_snapshot.get("hand", []) as Array).is_empty():
			continue
		if target_mode == "weapon_holder" and (target_snapshot.get("equipment", {}) as Dictionary).get("weapon", null) == null:
			continue
		if target_mode in ["wounded", "self_wounded"] and int(target_snapshot.get("hp", 0)) >= int(target_snapshot.get("max_hp", 0)):
			continue
		if not _is_distance_available_for_ai(authoritative_snapshot, owner_snapshot, definition, target_snapshot, evaluator):
			continue
		candidate_count += 1
	return candidate_count


## 判断目标是否满足卡牌定义的距离限制；只读取快照与评估器的只读查询，无法判断时按不满足处理。
func _is_distance_available_for_ai(authoritative_snapshot: Dictionary, owner_snapshot: Dictionary, definition: Dictionary, target_snapshot: Dictionary, evaluator: Object) -> bool:
	var distance_limit: String = str(definition.get("distance_limit", "none"))
	if distance_limit.is_empty() or distance_limit == "none":
		return true
	if evaluator == null or not evaluator.has_method("get_distance"):
		return false
	var owner_id: int = int(owner_snapshot.get("player_id", -1))
	var target_id: int = int(target_snapshot.get("player_id", -1))
	var distance: int = int(evaluator.call("get_distance", authoritative_snapshot, owner_id, target_id))
	if distance_limit == "one":
		return distance <= 1
	if distance_limit == "attack_range":
		if not evaluator.has_method("get_attack_range"):
			return false
		return distance <= int(evaluator.call("get_attack_range", authoritative_snapshot, owner_id))
	# 未识别的距离口径保守判为不可达，避免AI选中一个不会被权威枚举认可的组合。
	return false


## 判断该虚拟牌在当前作用域内的配置化次数上限是否还有剩余。
## 额度和用尽后权威目标枚举不会返回任何目标，AI 若仍选中该效果牌名就会陷入空转。
func _is_play_limit_available_for_ai(authoritative_snapshot: Dictionary, definition: Dictionary) -> bool:
	var play_limit: int = int(definition.get("play_limit", 0))
	if play_limit <= 0:
		return true
	var owner_snapshot: Dictionary = _get_owner_snapshot_for_ai(authoritative_snapshot)
	if owner_snapshot.is_empty():
		return false
	# 次数作用域；phase 使用独立出牌阶段历史，其余沿用回合历史，与核心层 _get_grouped_play_count 一致。
	var scope: String = str(definition.get("play_limit_scope", "turn"))
	var use_history_key: String = "play_phase_card_use_history" if scope == "phase" else "card_use_history"
	var exempt_history_key: String = "play_phase_card_use_limit_exempt_history" if scope == "phase" else "card_use_limit_exempt_history"
	var use_history: Dictionary = owner_snapshot.get(use_history_key, {}) as Dictionary
	var exempt_history: Dictionary = owner_snapshot.get(exempt_history_key, {}) as Dictionary
	var play_limit_group: String = str(definition.get("play_limit_group", definition.get("id", "")))
	var used_count: int = 0
	for used_definition_id_variant: Variant in use_history.keys():
		var used_definition_id: String = str(used_definition_id_variant)
		var used_definition: Dictionary = GameDatabase.get_card(used_definition_id)
		var used_group: String = str(used_definition.get("play_limit_group", used_definition_id))
		if used_group == play_limit_group:
			used_count += int(use_history.get(used_definition_id, 0)) - int(exempt_history.get(used_definition_id, 0))
	# 技能与武器提供的次数加成无法在快照层面判断，因此按未加成计算：宁可少发动，也不选中一个已经用尽的组合。
	return maxi(used_count, 0) < play_limit


## 从权威快照读取技能持有者自身状态；AI钩子没有宿主，只能按稳定玩家ID定位自己。
func _get_owner_snapshot_for_ai(authoritative_snapshot: Dictionary) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		var player_snapshot: Dictionary = player_variant as Dictionary
		if int(player_snapshot.get("player_id", -1)) == owner_player_id:
			return player_snapshot
	return {}


## 读取卡牌定义自带的AI价值；缺失时回退到中性值，保证选项之间仍可比较。
## ai.value 允许写成“按同名牌持有数量递减”的档位数组（【杀】【闪】【火攻】等基础牌即如此），
## 而【灵感】是“视为使用”一张牌名的牌、并不真的打出手牌，不存在同名牌张数这一上下文，
## 因此统一取数组首项作为该牌名的基准价值，口径与 touxia / xifa / xingqi 三个技能的既有实现一致。
## 注意：GDScript 对 Array 调用 float() 会抛 “Nonexistent 'float' constructor” 运行时报错，
## 该报错会中断整轮AI决策（技能不再产出任何动作，表现为AI毫无反应），因此必须先判型再转换。
func _score_definition_name(definition_id: String) -> float:
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	if definition.is_empty():
		return 0.0
	var ai_data: Dictionary = definition.get("ai", {}) as Dictionary
	# 配置价值；可能是单值，也可能是按持有数量递减的数组，取值前必须先判型。
	var configured_value: Variant = ai_data.get("value", AI_DEFAULT_CARD_VALUE)
	if configured_value is Array:
		var value_steps: Array = configured_value as Array
		# 空数组与首项非数值都属于配置不完整；回退中性值，不让异常数据中断AI决策。
		if value_steps.is_empty() or not (value_steps[0] is float or value_steps[0] is int):
			return AI_DEFAULT_CARD_VALUE
		return float(value_steps[0])
	# 非数值配置（字典、字符串等）同样按配置有误处理，回退中性值而不是抛出类型转换异常。
	if not (configured_value is float or configured_value is int):
		return AI_DEFAULT_CARD_VALUE
	return float(configured_value)


## 统计可作为目标模式伙伴的牌名数量；越多说明重定向的选择空间越大。
func _count_retarget_partners(choice_request: Dictionary) -> float:
	var partner_count: int = 0
	for candidate_variant: Variant in choice_request.get("control_options", []) as Array:
		var option: Dictionary = candidate_variant as Dictionary
		if not str(option.get("id", "")).is_empty():
			partner_count += 1
	return 0.1 * float(maxi(partner_count - 1, 0))


## 评估目标模式变化：目标上限提高视为单体转群体，目标上限降低视为群体转单体。
## 口径补充一：基准收益改用**效果牌名自身**的牌面价值，而不是目标牌名的价值。
## 实际结算的效果始终由效果牌名决定，目标牌名只提供目标规则；只有让“单段”与“二段”共用同一基准，
## 两者的收益才可比。否则一张高价值目标牌名（例如【无中生有】的 `value` 为 9.2）会让任何二段组合
## 凭空胜出，AI 就会把【南蛮入侵】的效果配上【无中生有】的目标规则送给所有角色。
## 口径补充二：方向必须结合效果牌自身的目标收益，不能一律把“目标变少”当成好事。
## 对目标“不利”的效果（伤害、横置、拆牌、跳阶段，`target_result < 0`）来说，
## 目标上限降低等于削弱这次结算本身——例如【铁索连环】的价值恰恰在于一次横置两名敌人，
## 因此这里改为扣分；只有对目标“有利”的效果（增益、回复，`target_result > 0`）才保留原有的
## “拆成单体以避免把增益送给敌人”的保守加分。扩大目标同理：只有不利效果才值得额外加分，
## 增益效果扩大目标会同时覆盖对手，其净收益改由 _score_group_targets_for_ai 按接受者计价。
func _score_target_mode(effect_id: String, target_mode_id: String) -> float:
	var effect_definition: Dictionary = GameDatabase.get_card(effect_id)
	var target_definition: Dictionary = GameDatabase.get_card(target_mode_id)
	if effect_definition.is_empty() or target_definition.is_empty():
		return 0.0
	var effect_maximum: int = int(effect_definition.get("max_targets", 1))
	var target_maximum: int = int(target_definition.get("max_targets", 1))
	# 效果对目标的方向；负值代表伤害、横置、拆牌等不利效果，正值代表增益与回复。
	var effect_target_result: float = float((effect_definition.get("ai", {}) as Dictionary).get("target_result", 0.0))
	# 基准收益；与单段共用效果牌名价值，使“要不要二段”只比较目标规则本身的差异。
	var score: float = _score_definition_name(effect_id)
	if target_maximum > effect_maximum:
		if effect_target_result < 0.0:
			score += AI_MULTITARGET_BONUS
	elif target_maximum < effect_maximum:
		if effect_target_result < 0.0:
			score -= AI_SINGLE_TARGET_RETREAT
		else:
			score += AI_SINGLE_TARGET_RETREAT
	return maxf(score, 0.5)


## 评估本次选定的目标集合收益；口径与通用出牌评分的目标收益同源，即逐目标累加
## `效果目标方向 × 敌我态度 × 权重`。态度对友方为正、对敌方为负，因此：
## ①伤害、横置、拆牌等对目标不利的效果在敌方身上得正分，在自己或队友身上得负分；
## ②增益与回复类效果方向相反，仍会正确地选择自己或队友；
## ③收益按目标逐个累加，于是“两名敌人”天然高于“一名敌人”，也天然高于“一名敌人加一名队友”。
## 通用选择评分在该分支只读取首个目标的态度、且不乘效果方向，会把【铁索连环】这类不利效果判给
## 态度最高的使用者自己，且其加分足以盖过真实差异，因此这里必须用放大后的权重覆盖它。
func _score_selected_targets_for_ai(authoritative_snapshot: Dictionary, context: Dictionary, payload: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	# 最终使用定义；目标方向必须读取效果牌名与目标牌名合并后的定义，与结算读取同一份数据。
	var definition: Dictionary = _resolve_target_definition(str(context.get("effect_id", "")), str(context.get("target_mode_id", "")))
	if definition.is_empty():
		return 0.0
	# 效果对目标的方向；缺失时按中性0处理，此时所有目标组合同分，由通用策略决定。
	var target_result: float = float((definition.get("ai", {}) as Dictionary).get("target_result", 0.0))
	# 逐目标累加收益；空目标数组（协议异常）自然得到0分，不会影响确认保底分。
	var score: float = 0.0
	for target_id_variant: Variant in payload.get("selected_target_ids", []) as Array:
		var target_id: int = int(target_id_variant)
		score += target_result * float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)) * AI_TARGET_RESULT_WEIGHT
	return score
