extends SkillDefinition

## 【连戏】技能源码。出牌阶段开始时：把手牌中的所有基本牌一次性重铸，可重复至多九次，最后对一名其他角色造成Y点伤害。

## 重铸流程的次数上限；原文“至多重铸九次”，达到上限后不再提供继续重铸选项。
const MAX_RECAST_TIMES: int = 9

## 伤害计算的除数；原文“Y为你本次重铸的次数/3，向下取整”。
const DAMAGE_DIVISOR: int = 3

## 重铸流程选择的请求种类；恢复时按该值分流。
const RECAST_CHOICE_KIND: String = "lianxi_recast"

## 伤害目标选择的请求种类；恢复时按该值分流。
const TARGET_CHOICE_KIND: String = "lianxi_target"

## 继续重铸的稳定控制选项ID；与结束选项互斥，界面与AI提交同一种控制ID。
const RECAST_OPTION_ID: String = "recast"

## 结束重铸并进入伤害步骤的稳定控制选项ID。
const FINISH_OPTION_ID: String = "finish"

## AI：每点伤害按体力资源价值折算时的系数；伤害不是即时回复，因此略低于纯体力收益。
const AI_DAMAGE_VALUE_RATIO: float = 0.85

## AI：每一轮重铸的手牌质量折损；重铸虽等量补摸，但会失去基本牌的确定价值。
const AI_RECAST_QUALITY_COST: float = NonameAIEvaluator.CARD_RESOURCE_VALUE * 0.35

## AI：继续重铸的无条件基础分；远高于任何伤害收益与取消动作的0分，确保只要窗口仍提供“重铸”就一定继续。运行时无需动态修改。
## 取值参照项目既有“无脑发动”写法（【星启】的 AI_ALWAYS_ACTIVATE_SCORE = 10000.0），保证不会被其它技能新增的正收益项反超。
const AI_UNCONDITIONAL_RECAST_SCORE: float = 10000.0


## 写入阶段开始技能静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"lianxi",
		"name":"连戏",
		"trigger":"phaseUseBegin",
		"enable":["phaseUse"],
		"ui_enabled":false,
		"description":"出牌阶段开始时，你可以重铸你手牌中的所有基本牌，你可以重复此流程（至多重铸九次），最后对一名其他角色造成Y点伤害。（Y为你本次重铸的次数/3，向下取整）",
	})


## 订阅出牌阶段 Begin；技能的权威入口只有该时机创建的询问，不再提供主动按钮。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player", 100)


## 出牌阶段进入 Begin 时创建发动询问。
## 手牌中没有基本牌时重铸不会发生任何事，因此不创建空窗口，与改动前的入口关闭口径一致。
## 每个出牌阶段（含额外出牌阶段）都重新询问：原文时机是“出牌阶段开始时”，不是“限一次”。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	if _get_hand_basic_card_uids().is_empty():
		return
	_request_recast_choice(0, true)


## 阶段开始技能不通过常规主动按钮发动；权威询问只由 phaseUseBegin 回调创建。
func can_activate(_context: Dictionary = {}) -> bool:
	return false


## 旧主动入口保持不可用；Begin 询问与后续每一轮重铸都由 continue_selection 处理。
func activate(_context: Dictionary = {}) -> String:
	return "【连戏】只能在出牌阶段开始时发动。"


## 恢复重铸流程选择或伤害目标选择。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；重铸流程与伤害目标分别恢复。
	var choice_kind: String = str(context.get("kind", ""))
	# 已完成的流程次数；由上下文携带，避免用可变字段跨选择追踪进度。
	var recast_count: int = int(context.get("recast_count", 0))
	if choice_kind == RECAST_CHOICE_KIND:
		# 取消只可能出现在第一次窗口，表示不发动：不消耗阶段额度、不移动任何牌。
		if not response.confirmed:
			return true
		if response.control_id == RECAST_OPTION_ID:
			_execute_recast_round(recast_count)
			return true
		if response.control_id == FINISH_OPTION_ID:
			_begin_damage_target_selection(recast_count)
			return true
		return true
	if choice_kind == TARGET_CHOICE_KIND:
		if response.confirmed and response.target_ids.size() == 1:
			_execute_damage(response.target_ids[0], recast_count)
		else:
			# 目标失效或取消时仍要收尾，避免遗留未消费的演出窗口。
			_finish_lianxi(recast_count, -1)
		return true
	return false


## 建立重铸流程选择窗口；第一次允许取消（表示不发动），后续必须二选一。
func _request_recast_choice(recast_count: int, allow_cancel: bool) -> void:
	# 本轮可选控制项；仍有额度且手中还有基本牌时才提供“继续重铸”。
	var options: Array[Dictionary] = []
	if recast_count < MAX_RECAST_TIMES and not _get_hand_basic_card_uids().is_empty():
		options.append({"id":RECAST_OPTION_ID, "label":"重铸"})
	# 至少完成一次重铸后才提供结束选项，保证发动后必然产生一次真实重铸。
	if recast_count > 0:
		options.append({"id":FINISH_OPTION_ID, "label":"结束"})
	# 没有可执行选项时不创建空窗口，按已完成次数直接进入伤害步骤。
	if options.is_empty():
		_begin_damage_target_selection(recast_count)
		return
	var prompt: String = "【连戏】是否重置手牌中的所有基本牌？" if recast_count <= 0 else "你已重铸%d次，是否继续发动？" % recast_count
	request_control_selection("连戏", prompt, options, allow_cancel, {"kind":RECAST_CHOICE_KIND, "recast_count":recast_count})


## 执行一轮多张重铸：把当前全部基本牌一次置入弃牌堆并等量补摸，然后回到流程选择。
## 使用多张重铸入口而不是逐张循环，才能真正表达“多张牌置入弃牌堆然后摸等量的牌”。
func _execute_recast_round(recast_count: int) -> bool:
	if host == null or host.get("state") == null or recast_count >= MAX_RECAST_TIMES:
		return false
	# 本轮重铸材料；只包含当前普通手牌区的基本牌，装备与判定牌不参与。
	var basic_card_uids: Array[int] = _get_hand_basic_card_uids()
	if basic_card_uids.is_empty():
		_begin_damage_target_selection(recast_count)
		return false
	# 实际重铸张数；由多张重铸入口回报，实际为0时不累计流程次数，避免空转。
	var recast_card_count: int = int(host.call("recast_hand_cards", owner_player_id, basic_card_uids))
	if recast_card_count <= 0:
		_begin_damage_target_selection(recast_count)
		return false
	# 真实重铸完成后取消不再成立；这一点由下一轮窗口的 allow_cancel=false 保证，无需额外的额度标记。
	_request_recast_choice(recast_count + 1, false)
	return true


## 进入最后一步：按已完成次数计算Y并选择一名其他角色；Y为0时不创建目标选择。
func _begin_damage_target_selection(recast_count: int) -> bool:
	# 伤害点数；原文“Y为你本次重铸的次数/2，向下取整”。
	var damage_amount: int = _resolve_damage_amount(recast_count)
	if damage_amount <= 0:
		_finish_lianxi(recast_count, -1)
		return true
	# 可选其他角色；伤害目标不需要手牌，只要是存活在场的其他角色。
	var target_ids: Array[int] = _get_damage_target_ids()
	if target_ids.is_empty():
		_finish_lianxi(recast_count, -1)
		return false
	request_target_selection("【连戏】请选择一名其他角色造成%d点伤害" % damage_amount, target_ids, 1, 1, true, {"kind":TARGET_CHOICE_KIND, "recast_count":recast_count})
	return true


## 结算最后的伤害；等待期间重算Y并复核目标，保证数值与目标都在提交时仍然合法。
func _execute_damage(target_id: int, recast_count: int) -> bool:
	# 伤害点数；与目标选择阶段使用同一算式，因此等待期间数值不会变化。
	var damage_amount: int = _resolve_damage_amount(recast_count)
	if damage_amount <= 0 or not _get_damage_target_ids().has(target_id):
		_finish_lianxi(recast_count, -1)
		return false
	_finish_lianxi(recast_count, target_id)
	host.call("damage", owner_player_id, target_id, damage_amount, "normal", get_id())
	return true


## 记录本次发动并收尾；未造成伤害时同样记录，便于复盘查看实际重铸次数。
func _finish_lianxi(recast_count: int, damage_target_id: int) -> void:
	announce_activation({"recast_times":recast_count, "damage":_resolve_damage_amount(recast_count), "damage_target_id":damage_target_id})


## 计算Y：重铸次数除以2并向下取整；负数按0处理，避免异常上下文产生负伤害。
func _resolve_damage_amount(recast_count: int) -> int:
	return floori(float(maxi(recast_count, 0)) / float(DAMAGE_DIVISOR))


## 返回持有者当前普通手牌区中全部基本牌的实体UID；保持手牌原顺序，便于回放稳定复现。
func _get_hand_basic_card_uids() -> Array[int]:
	# 材料结果；持有者无效时返回空数组，由调用方按“无材料”处理。
	var card_uids: Array[int] = []
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return card_uids
	for card: CardInstance in owner.hand:
		if _is_basic_card(card.definition_id):
			card_uids.append(card.uid)
	return card_uids


## 判断卡牌定义是否属于基本牌；只读取静态类型，不读取当前牌名设置。
func _is_basic_card(definition_id: String) -> bool:
	return str(GameDatabase.get_card(definition_id).get("type", "")) == "basic"


## 返回当前可作为伤害目标的其他角色稳定玩家ID；必须存活在场。
func _get_damage_target_ids() -> Array[int]:
	# 目标结果；保持权威座次顺序，界面与AI据此稳定展示同一份候选。
	var target_ids: Array[int] = []
	if host == null or host.get("state") == null:
		return target_ids
	for player: PlayerState in host.state.players:
		if player.player_id != owner_player_id and player.alive and not player.out_of_game:
			target_ids.append(player.player_id)
	return target_ids


## 常规出牌阶段不追加技能动作；AI 与玩家都在 Begin 询问中使用同一 ChoiceResponse。
func append_play_phase_actions(_result: Array[Dictionary]) -> void:
	pass


## 评估连戏的窗口与目标选择；继续重铸在Y将提高时优于立即结束，结束与目标按目标态度计分。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；重铸流程与伤害目标分别评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 动作负载；取消只出现在第一次窗口，等价于不发动。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 已完成流程次数；与规则上下文同名，保证AI与结算对“第几轮”的理解一致。
	var recast_count: int = int(context.get("recast_count", 0))
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == RECAST_CHOICE_KIND:
		if not bool(payload.get("confirmed", false)):
			return 0.0
		var control_id: String = str(payload.get("selected_control_id", ""))
		if control_id == RECAST_OPTION_ID:
			# 无条件继续重铸：只要窗口仍提供“重铸”就必须继续，直到重铸次数上限或手中不再有基本牌。
			# 只有达到 MAX_RECAST_TIMES 或手中无基本牌时窗口才会撤掉“重铸”选项，此时才由结束分支收尾。
			# 手牌质量折损只作为同分排序修正保留，不再作为“是否继续”的判据，因此 AI 的发动率不再受 Y 是否提高影响。
			return AI_UNCONDITIONAL_RECAST_SCORE - AI_RECAST_QUALITY_COST
		if control_id == FINISH_OPTION_ID:
			# 立即结束：按当前Y取全部候选目标中的最高伤害收益。
			return _estimate_finish_value(authoritative_snapshot, recast_count, evaluator)
		return 0.0
	if choice_kind == TARGET_CHOICE_KIND:
		if not bool(payload.get("confirmed", false)):
			return 0.0
		# 已选目标；必须恰好一名其他角色。
		var selected_targets: Array = payload.get("selected_target_ids", []) as Array
		if selected_targets.size() != 1:
			return -20.0
		return _estimate_damage_value(authoritative_snapshot, int(selected_targets[0]), recast_count, evaluator)
	return 0.0


## 估算立即结束时的最佳伤害收益；遍历全部存活其他角色取最大值。
func _estimate_finish_value(authoritative_snapshot: Dictionary, recast_count: int, evaluator: Object) -> float:
	# 最佳收益；没有合法目标或Y为0时保持0分，交给取消分支兜底。
	var best_value: float = 0.0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；跳过自己、已死亡与已离场角色。
		var player: Dictionary = player_variant as Dictionary
		var target_id: int = int(player.get("player_id", -1))
		if target_id == owner_player_id or not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
			continue
		best_value = maxf(best_value, _estimate_damage_value(authoritative_snapshot, target_id, recast_count, evaluator))
	return best_value


## 估算对指定目标造成Y点伤害的收益；友方目标按负收益计入，避免AI把伤害打向队友。
func _estimate_damage_value(authoritative_snapshot: Dictionary, target_id: int, recast_count: int, evaluator: Object) -> float:
	# 伤害点数；与规则使用同一算式。
	var damage_amount: int = _resolve_damage_amount(recast_count)
	if damage_amount <= 0 or target_id == owner_player_id:
		return 0.0
	# 态度；范围约 ±5，除以5后作为伤害收益的强度系数，友方目标因此得到负分。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	return float(damage_amount) * NonameAIEvaluator.HP_RESOURCE_VALUE * AI_DAMAGE_VALUE_RATIO * (-attitude / 5.0)
