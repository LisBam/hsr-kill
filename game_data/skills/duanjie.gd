extends SkillDefinition

## 【断界】技能源码。出牌阶段限一次：选择一项改变一名角色的横置或翻面状态；选择完毕后删除最后一项可选操作。

## 选项①"将一名武将牌竖置的角色横置"的稳定控制ID；用原文序号作为ID，使"删除最后一项"的语义直接可见。
const OPTION_LINK_TARGET: String = "1"

## 选项②"将一名武将牌横置的角色竖置"的稳定控制ID。
const OPTION_UNLINK_TARGET: String = "2"

## 选项③"将一名武将牌背面向上的角色翻至正面"的稳定控制ID。
const OPTION_TURN_FACE_UP: String = "3"

## 选项④"将一名武将牌正面向上的角色翻至背面"的稳定控制ID。
const OPTION_TURN_FACE_DOWN: String = "4"

## 初始选项总数；数值4来自技能原文的四项操作。
const INITIAL_OPTION_COUNT: int = 4

## 已删除选项记录在 character_form_state 中的稳定键名。
## 该键随权威存档往返、不进入公开快照；键“缺失”即代表尚未删除任何选项，因此安装时无需写入初值。
const REMAINING_OPTIONS_STATE_KEY: String = "duanjie_remaining_options"

## 需要识别为“整体复原”的武将牌技能变更类型；只有这两类才应清空已删除的选项。
## restore_limited_skill_use（单项复原限定额度）派发同一个时机，但它不应重置选项列表，因此必须按类型过滤。
const RESTORE_CHANGE_TYPES: Array[String] = ["restore_character_card_skills", "replace_character_card"]

## 选项选择请求种类；恢复时按该值分流。
const OPTION_CHOICE_KIND: String = "duanjie_option"

## 目标选择请求种类；上下文携带已选定的选项ID。
const TARGET_CHOICE_KIND: String = "duanjie_target"

## 当前出牌阶段是否已经发动；普通与额外出牌阶段分别限一次。
var _used_current_play_phase: bool = false

## AI：对敌方施加横置或翻背面的收益折算系数；跳过对方回合属于强干扰。
const AI_DISRUPT_VALUE: float = 1.6

## AI：为队友解除横置或翻回正面的收益折算系数；等于把队友的回合还给他。
const AI_ASSIST_VALUE: float = 1.2

## AI：④仍可用时的额外加成；④位于列表末尾，首次发动后就会被删除，因此是唯一的使用窗口。
const AI_LAST_CHANCE_BONUS: float = 1.0


## 写入主动技能静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"duanjie",
		"name":"断界",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"description":"出牌阶段限一次，你可以选择：1.将一名武将牌竖置的角色横置；2.将一名武将牌横置的角色竖置；3.将一名武将牌背面向上的角色翻至正面；4.将一名武将牌正面向上的角色翻至背面。选择完毕后，你删除最后一项。",
	})


## 订阅出牌阶段开始与武将牌技能变更；后者用于让「复原武将牌上的技能」清零已删除的选项。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player", 100)
	subscribe_timing("changeSkillsAfter", _on_change_skills_after, "player")


## 每个出牌阶段开始时恢复本阶段的发动额度。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	_used_current_play_phase = false


## 武将牌技能被整体复原或替换时清空已删除的选项，让技能回到完整的四项选择。
## 本技能的选项进度存放在 character_form_state 中，项目不会在读档或复原时自动清空该字段，
## 因此必须由技能自己订阅本时机补上这一行为；这也是“复原武将牌可以复原”这一需求的落点。
func _on_change_skills_after(event: RuleEvent) -> void:
	if not RESTORE_CHANGE_TYPES.has(str(event.data.get("change_type", ""))):
		return
	# 本次变更涉及的技能ID；只有确实复原了本技能时才清空，避免被其他武将的复原波及。
	if not (event.data.get("skill_ids", []) as Array).has(get_id()):
		return
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner != null:
		owner.character_form_state.erase(REMAINING_OPTIONS_STATE_KEY)


## 仅在自己的出牌阶段、仍有额度且至少有一项存在合法目标时开放技能。
## 所有剩余选项都没有合法目标时技能熄灭：这符合“没有能做的事”的直觉，也不涉及轮回推进，不存在卡死风险。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or host.state.current_player_id != owner_player_id or host.state.current_phase != "play" or _used_current_play_phase:
		return false
	return not _collect_available_options().is_empty()


## 读取直接动作中的选项与目标并执行；缺失参数时依次创建选项选择与目标选择窗口。
func activate(context: Dictionary = {}) -> String:
	if not can_activate():
		return "【断界】当前没有可执行的操作。"
	# 直接动作选项ID；AI合法动作与调试入口通过它跳过选项窗口。
	var direct_option_id: String = str(context.get("option_id", context.get("control_id", "")))
	if direct_option_id.is_empty():
		_request_option_choice()
		return ""
	# 直接目标；必须保持唯一角色。
	var target_ids: Array[int] = _int_array(context.get("target_ids", []) as Array)
	if target_ids.size() == 1:
		return "" if _execute_option(direct_option_id, target_ids[0]) else "【断界】所选目标已经失效。"
	return "" if _request_option_target(direct_option_id) else "【断界】该选项当前没有合法目标。"


## 恢复选项选择或目标选择；取消任一步都不删除列表项、也不消耗本阶段额度。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 选择业务类型；只消费断界自身建立的两类请求。
	var kind: String = str(context.get("kind", ""))
	if kind == OPTION_CHOICE_KIND:
		if response.confirmed and not response.control_id.is_empty():
			_request_option_target(response.control_id)
		return true
	if kind == TARGET_CHOICE_KIND:
		if response.confirmed and response.target_ids.size() == 1:
			_execute_option(str(context.get("option_id", "")), response.target_ids[0])
		return true
	return false


## 建立选项选择窗口；只列出当前确实存在合法目标的选项，避免选中后无目标可指。
func _request_option_choice() -> void:
	# 可选控制项；顺序保持与剩余列表一致，界面展示顺序因此稳定。
	var options: Array[Dictionary] = []
	for option_id: String in _collect_available_options():
		options.append({"id":option_id, "label":_option_label(option_id)})
	if options.is_empty():
		return
	request_control_selection("断界", "请选择一项", options, true, {"kind":OPTION_CHOICE_KIND})


## 为已选定的选项建立目标选择窗口；该选项当前没有合法目标时返回false。
func _request_option_target(option_id: String) -> bool:
	if not _get_remaining_options().has(option_id):
		return false
	var target_ids: Array[int] = _get_target_ids_for_option(option_id)
	if target_ids.is_empty():
		return false
	request_target_selection("【断界】%s" % _option_label(option_id), target_ids, 1, 1, true, {"kind":TARGET_CHOICE_KIND, "option_id":option_id})
	return true


## 执行一项效果，然后删除列表最后一项；删除只发生在效果实际成立之后。
func _execute_option(option_id: String, target_id: int) -> bool:
	if not can_activate() or not _get_remaining_options().has(option_id) or not _get_target_ids_for_option(option_id).has(target_id):
		return false
	# 效果执行结果；三种状态变更端口都以返回值表示是否受理。
	var applied: bool = false
	if option_id == OPTION_LINK_TARGET:
		applied = bool(host.call("set_player_linked", target_id, true, owner_player_id, get_id()))
	elif option_id == OPTION_UNLINK_TARGET:
		applied = bool(host.call("set_player_linked", target_id, false, owner_player_id, get_id()))
	else:
		# 翻面没有绝对设置端口，只有切换；因此必须在此复核目标当前朝向，避免等待期间状态被改动。
		var target: PlayerState = get_skill_player(target_id).get_state()
		if target == null:
			return false
		# 选项③要求目标当前背面向上，选项④要求当前正面向上。
		var expected_face_down: bool = option_id == OPTION_TURN_FACE_UP
		if target.face_down != expected_face_down:
			return false
		applied = bool(host.call("turn_over_player", target_id, owner_player_id, get_id()))
	if not applied:
		return false
	# 效果成立后才消耗额度并删除列表最后一项；第四项因此只在第一次发动时可用。
	_used_current_play_phase = true
	_delete_last_option()
	announce_activation({"target_id":target_id, "target_ids":[target_id], "option_id":option_id})
	return true


## 返回剩余的选项列表；键缺失即代表尚未删除过任何选项，此时返回完整初始列表。
func _get_remaining_options() -> Array[String]:
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return _initial_options()
	# 已删除记录；只有形状为数组时才视为有效进度，其余情况一律惰性回退到完整列表。
	var stored: Variant = owner.character_form_state.get(REMAINING_OPTIONS_STATE_KEY)
	if not (stored is Array):
		return _initial_options()
	# 过滤结果；旧存档或被外部改写的内容可能含非法项，逐项过滤保证只保留合法选项ID。
	var result: Array[String] = []
	for option_variant: Variant in stored as Array:
		var option_id: String = str(option_variant)
		if _initial_options().has(option_id):
			result.append(option_id)
	return result


## 从剩余列表中删除最后一项并写回权威状态；列表已空时本调用不产生变化。
func _delete_last_option() -> void:
	var remaining: Array[String] = _get_remaining_options()
	if remaining.is_empty():
		return
	remaining.pop_back()
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner != null:
		owner.character_form_state[REMAINING_OPTIONS_STATE_KEY] = remaining


## 返回四项操作的初始顺序；每次调用都新建数组，避免调用方误改共享常量引用。
func _initial_options() -> Array[String]:
	return [OPTION_LINK_TARGET, OPTION_UNLINK_TARGET, OPTION_TURN_FACE_UP, OPTION_TURN_FACE_DOWN]


## 返回当前剩余选项里确实存在合法目标的选项ID；没有任何合法目标时技能不可发动。
func _collect_available_options() -> Array[String]:
	# 可用选项结果；保持剩余列表顺序，界面与AI据此稳定展示同一份候选。
	var result: Array[String] = []
	for option_id: String in _get_remaining_options():
		if not _get_target_ids_for_option(option_id).is_empty():
			result.append(option_id)
	return result


## 返回指定选项当前的全部合法目标；包含持有者自己，因为原文没有排除自己。
func _get_target_ids_for_option(option_id: String) -> Array[int]:
	# 目标结果；保持权威座次顺序，界面与AI据此稳定展示同一份候选。
	var result: Array[int] = []
	if host == null or host.get("state") == null:
		return result
	for player: PlayerState in host.state.players:
		if not player.alive or player.out_of_game:
			continue
		if _is_target_legal_for_option(player, option_id):
			result.append(player.player_id)
	return result


## 判断一名角色是否满足指定选项的前置状态；翻面只有切换端口，因此必须前置判断朝向。
func _is_target_legal_for_option(player: PlayerState, option_id: String) -> bool:
	if option_id == OPTION_LINK_TARGET:
		return not player.chained
	if option_id == OPTION_UNLINK_TARGET:
		return player.chained
	if option_id == OPTION_TURN_FACE_UP:
		return player.face_down
	return option_id == OPTION_TURN_FACE_DOWN and not player.face_down


## 返回选项的玩家可见标签；四项描述与原文逐字一致。
func _option_label(option_id: String) -> String:
	if option_id == OPTION_LINK_TARGET:
		return "将一名武将牌竖置的角色横置"
	if option_id == OPTION_UNLINK_TARGET:
		return "将一名武将牌横置的角色竖置"
	if option_id == OPTION_TURN_FACE_UP:
		return "将一名武将牌背面向上的角色翻至正面"
	return "将一名武将牌正面向上的角色翻至背面"


## 把弱类型数组收敛为整数数组；动作与网络输入共用该防御性转换。
func _int_array(values: Array) -> Array[int]:
	# 转换结果；保留原顺序，由技能规则判断数量。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result


## 为AI枚举当前每个可用选项；目标由AI在随后的目标窗口中评分选定。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for option_id: String in _collect_available_options():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id(), "option_id":option_id}})


## 评估一个选项的最佳目标收益；同一选项下取全部合法目标中的最大值。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载中的选项ID；缺失时视为非法动作。
	var option_id: String = str((action.get("payload", {}) as Dictionary).get("option_id", ""))
	if option_id.is_empty():
		return -100.0
	return _score_option(authoritative_snapshot, option_id, evaluator)


## 评估选项选择或目标选择；两类窗口共用同一套方向性评分。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；目标窗口需要其中的选项ID。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 动作负载；取消一律按0分处理，让AI保持不发动。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var kind: String = str(context.get("kind", ""))
	if not bool(payload.get("confirmed", false)):
		return 0.0
	if kind == OPTION_CHOICE_KIND:
		return _score_option(authoritative_snapshot, str(payload.get("selected_control_id", "")), evaluator)
	if kind == TARGET_CHOICE_KIND:
		var selected_target_ids: Array = payload.get("selected_target_ids", []) as Array
		return _score_option_target(authoritative_snapshot, str(context.get("option_id", "")), int(selected_target_ids[0]), evaluator) if selected_target_ids.size() == 1 else -100.0
	return 0.0


## 评估一个选项的最佳目标收益；候选来自权威快照中的存活在场角色。
func _score_option(authoritative_snapshot: Dictionary, option_id: String, evaluator: Object) -> float:
	# 最佳收益；初值取负值，使“没有任何合法目标”自然落到不发动一侧。
	var best_value: float = -100.0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；跳过已死亡与已离场角色。
		var player: Dictionary = player_variant as Dictionary
		var target_id: int = int(player.get("player_id", -1))
		if target_id < 0 or not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
			continue
		if not _is_snapshot_player_legal_for_option(option_id, player):
			continue
		best_value = maxf(best_value, _score_option_target(authoritative_snapshot, option_id, target_id, evaluator))
	return best_value


## 从公开快照判断一名角色是否满足选项的前置状态；与实时扫描使用同一套朝向与横置语义。
func _is_snapshot_player_legal_for_option(option_id: String, player: Dictionary) -> bool:
	if option_id == OPTION_LINK_TARGET:
		return not bool(player.get("chained", false))
	if option_id == OPTION_UNLINK_TARGET:
		return bool(player.get("chained", false))
	if option_id == OPTION_TURN_FACE_UP:
		return bool(player.get("face_down", false))
	return option_id == OPTION_TURN_FACE_DOWN and not bool(player.get("face_down", false))


## 评估对指定目标执行指定选项的方向性收益；横置与翻背面是干扰，竖置与翻正面是协助。
## 需求给出的AI提示：对队友发动②或③，对敌人发动①；④只在首次发动（仍在列表中）时额外优先。
func _score_option_target(authoritative_snapshot: Dictionary, option_id: String, target_id: int, evaluator: Object) -> float:
	# 目标快照；无效目标直接拒绝。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return -100.0
	# 态度；正为队友，负为敌人，范围约 ±5。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 该选项是否属于“让对方跳过回合”的干扰方向。
	var is_disruptive: bool = option_id == OPTION_LINK_TARGET or option_id == OPTION_TURN_FACE_DOWN
	# 方向性收益；干扰方向对敌人为正，协助方向对队友为正。
	var value: float = (-attitude / 5.0 * AI_DISRUPT_VALUE) if is_disruptive else (attitude / 5.0 * AI_ASSIST_VALUE)
	# ④位于列表末尾：首次发动后它就会被删除，因此仍在完整列表时给予额外加成，优先用掉唯一窗口。
	if option_id == OPTION_TURN_FACE_DOWN and _get_remaining_options().size() >= INITIAL_OPTION_COUNT:
		value += AI_LAST_CHANCE_BONUS
	return value
