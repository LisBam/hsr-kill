extends SkillDefinition

## 【振旗】技能源码。贝洛伯格角色回合开始时可选择一项费用，再由领袖选择另一名同势力角色获得对应效果。

## 贝洛伯格势力稳定 ID；修改后会改变本技能的触发者与受益者范围，不应在运行时动态修改。
const FACTION_ID: String = "beiluoboge"

## 弃置手牌费用的稳定选项 ID；该选项按斜杠同位规则对应摸1张牌。
const DISCARD_OPTION_ID: String = "discard_hand"

## 失去体力费用的稳定选项 ID；该选项按斜杠同位规则对应回复1点体力。
const LOSE_HP_OPTION_ID: String = "lose_hp"

## 弃牌分支的后续效果稳定 ID；只在选择目标后决定摸牌结算，不直接公开给界面。
const DRAW_EFFECT_ID: String = "draw"

## 失去体力分支的后续效果稳定 ID；只在选择目标后决定回复结算，不直接公开给界面。
const RECOVER_EFFECT_ID: String = "recover"

## 失去体力分支的固定费用；默认1点，修改后必须同步技能原文与玩法数值文档。
const HP_COST: int = 1

## 对应分支的固定摸牌或回复数量；默认1，两个同位效果共用该数值。
const EFFECT_AMOUNT: int = 1

## 身份观察中的受益结果；正1表示领袖成功令目标获得资源或回复，不改变实际效果数值。
const IDENTITY_TARGET_RESULT: float = 1.0

## AI 估算弃置一张未知手牌的基础费用；仅影响是否选择该分支，不修改真实卡牌数量。
const AI_DISCARD_COST: float = 1.0

## AI 估算失去1点体力的基础费用；仅影响是否选择该分支，不修改真实体力变化。
const AI_LOSE_HP_COST: float = 2.0

## AI 将身份态度换算为可选发动收益的除数；数值越小，AI 越愿意为友方支付费用。
const AI_ATTITUDE_DIVISOR: float = 2.0


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "zhenqi",
		"name": "振旗",
		"trigger": "phaseBefore",
		"ui_enabled": false,
		"leader_skill": true,
		"description": "领袖技，“贝洛伯格”势力的角色的回合开始时，其可弃置一张手牌/失去1点体力，然后你令另一名“贝洛伯格”势力的角色摸一张牌/回复1点体力。",
	})


## 订阅全部角色的回合开始时机；实际触发者与目标均由贝洛伯格势力规则过滤。
func install() -> void:
	subscribe_timing("phaseBefore", _on_any_turn_begin, "global")


## 判断技能持有者能否继续提供领袖技；死亡或离场后保留的全局订阅不能再创建或恢复技能选择。
func _is_owner_available() -> bool:
	# 技能持有者权威状态；未知玩家、死亡或离场均视为本技能当前失效。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game


## 贝洛伯格角色回合开始时请求其选择费用；没有另一名合法同势力角色时不创建无效询问。
func _on_any_turn_begin(event: RuleEvent) -> void:
	if not _is_owner_available():
		return
	# 本回合角色 ID；phaseBefore 的 player_id 是唯一权威回合来源，不使用当前界面操作者推断。
	var turn_player_id: int = event.player_id
	# 本回合角色；死亡、离场或非贝洛伯格角色不能触发领袖技。
	var turn_player: PlayerState = host.state.get_player(turn_player_id) as PlayerState
	if turn_player == null or not turn_player.alive or turn_player.out_of_game or not _is_faction_player(turn_player, FACTION_ID):
		return
	if _get_recipient_ids(turn_player_id).is_empty():
		return
	# 当前合法费用选项；没有手牌时不显示无法支付的弃置分支，失去1点体力仍保持可选。
	var options: Array[Dictionary] = []
	if not turn_player.hand.is_empty():
		options.append({"id":DISCARD_OPTION_ID, "label":"弃置一张手牌，然后令目标摸一张牌"})
	options.append({"id":LOSE_HP_OPTION_ID, "label":"失去1点体力，然后令目标回复1点体力"})
	request_control_selection_for_player(turn_player_id, "振旗", "请选择【振旗】的费用；斜杠前后选项按位置对应", options, true, {"kind":"zhenqi_cost_option", "turn_player_id":turn_player_id})


## 恢复费用选项、弃置手牌和领袖目标选择；只有费用与目标同时仍合法时才按同位分支结算。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	if not _is_owner_available():
		return true
	# 当前选择步骤；三个步骤共享本技能实例，但使用独立 kind 防止旧响应进入错误结算分支。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "zhenqi_cost_option":
		return _continue_cost_option(context, response)
	if choice_kind == "zhenqi_discard_card":
		return _continue_discard_card(context, response)
	if choice_kind == "zhenqi_recipient":
		return _continue_recipient(context, response)
	return false


## 处理触发角色选择的费用分支；取消不支付费用，弃牌分支继续选牌，失去体力分支直接进入领袖选目标。
func _continue_cost_option(context: Dictionary, response: ChoiceResponse) -> bool:
	if not response.confirmed:
		return true
	# 触发角色 ID；等待期间必须仍为存活、未离场的贝洛伯格角色。
	var turn_player_id: int = int(context.get("turn_player_id", -1))
	var turn_player: PlayerState = host.state.get_player(turn_player_id) as PlayerState
	if turn_player == null or not turn_player.alive or turn_player.out_of_game or not _is_faction_player(turn_player, FACTION_ID):
		return true
	if response.control_id == DISCARD_OPTION_ID:
		# 普通手牌候选；选择者只能看见并支付自己的手牌，不包含木牛“粮”或其他区域牌。
		var candidates: Array[Dictionary] = host.call("get_hand_candidates", turn_player_id, turn_player_id) as Array[Dictionary]
		if candidates.is_empty():
			return true
		request_card_selection_for_player(turn_player_id, "振旗", "请选择一张手牌作为【振旗】费用", candidates, 1, 1, false, {"kind":"zhenqi_discard_card", "turn_player_id":turn_player_id})
		return true
	if response.control_id == LOSE_HP_OPTION_ID:
		_request_recipient(turn_player_id, LOSE_HP_OPTION_ID, -1)
		return true
	return true


## 保存触发角色选定的弃置手牌 UID，再由领袖选择受益角色；实际弃置推迟到最终结算时复核。
func _continue_discard_card(context: Dictionary, response: ChoiceResponse) -> bool:
	if not response.confirmed or response.card_ids.size() != 1:
		return true
	# 触发角色与费用牌；最终目标确认后仍会再次验证牌位于该角色普通手牌区。
	var turn_player_id: int = int(context.get("turn_player_id", -1))
	_request_recipient(turn_player_id, DISCARD_OPTION_ID, response.card_ids[0])
	return true


## 请求技能持有者选择另一名贝洛伯格角色；费用分支和待弃实体 UID 通过序列化上下文传递。
func _request_recipient(turn_player_id: int, cost_option_id: String, cost_card_uid: int) -> void:
	# 合法受益者；“另一名”固定排除本回合支付费用的角色，允许技能持有者在自己不是触发者时成为目标。
	var recipient_ids: Array[int] = _get_recipient_ids(turn_player_id)
	if recipient_ids.is_empty():
		return
	request_target_selection("【振旗】请选择另一名“贝洛伯格”势力角色", recipient_ids, 1, 1, false, {"kind":"zhenqi_recipient", "turn_player_id":turn_player_id, "cost_option_id":cost_option_id, "cost_card_uid":cost_card_uid})


## 在目标确认后支付所选费用并执行严格同位效果：弃牌对应摸牌，失去体力对应回复。
func _continue_recipient(context: Dictionary, response: ChoiceResponse) -> bool:
	if not response.confirmed or response.target_ids.size() != 1:
		return true
	# 支付费用的本回合角色；死亡、离场或势力改变后不再继续旧技能请求。
	var turn_player_id: int = int(context.get("turn_player_id", -1))
	var turn_player: PlayerState = host.state.get_player(turn_player_id) as PlayerState
	if turn_player == null or not turn_player.alive or turn_player.out_of_game or not _is_faction_player(turn_player, FACTION_ID):
		return true
	# 最终受益角色；必须仍存活、未离场、属于贝洛伯格且不是费用支付者。
	var recipient_id: int = response.target_ids[0]
	var recipient: PlayerState = host.state.get_player(recipient_id) as PlayerState
	if recipient == null or not recipient.alive or recipient.out_of_game or recipient_id == turn_player_id or not _is_faction_player(recipient, FACTION_ID):
		return true
	# 已选费用分支；只有完整支付成功才执行与其位置对应的后续效果。
	var cost_option_id: String = str(context.get("cost_option_id", ""))
	var effect_id: String = ""
	if cost_option_id == DISCARD_OPTION_ID:
		if not bool(host.call("discard_card_from_hand", turn_player_id, int(context.get("cost_card_uid", -1)))):
			return true
		effect_id = DRAW_EFFECT_ID
	elif cost_option_id == LOSE_HP_OPTION_ID:
		if get_skill_player(turn_player_id).loseHp(HP_COST, get_skill_player(turn_player_id)) <= 0:
			return true
		effect_id = RECOVER_EFFECT_ID
	else:
		return true
	if host.state.game_over:
		return true
	observe_identity_behavior([recipient_id], {"target_result":IDENTITY_TARGET_RESULT})
	if effect_id == DRAW_EFFECT_ID:
		host.call("draw", recipient_id, EFFECT_AMOUNT)
	else:
		host.call("recover", owner_player_id, recipient_id, EFFECT_AMOUNT, get_id())
	return true


## 返回除费用支付者外的全部存活贝洛伯格角色 ID；顺序沿用权威座次，保证 UI、AI 和回放稳定。
func _get_recipient_ids(excluded_player_id: int) -> Array[int]:
	# 受益者结果；只保存稳定玩家 ID，不跨选择持有 PlayerState 引用。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.player_id != excluded_player_id and player.alive and not player.out_of_game and _is_faction_player(player, FACTION_ID):
			result.append(player.player_id)
	return result


## 判断权威玩家当前武将是否属于指定势力；势力只读取武将元数据，不把身份阵营与展示势力混为一谈。
func _is_faction_player(player: PlayerState, faction_id: String) -> bool:
	if player == null:
		return false
	# 当前武将定义；空武将或未知定义会得到空势力并安全返回 false。
	var character: Dictionary = GameDatabase.get_character(player.character_id)
	return str(character.get("faction", "")) == faction_id


## 为三段选择提供本地 AI 评分；触发角色决定费用，技能持有者决定受益目标，强制选牌优先低价值实体。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文与动作负载；稳定 kind 决定当前评分使用哪名角色的态度。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "zhenqi_cost_option":
		# 费用支付者；其只在存在对自己有利的潜在同势力受益者时主动发动。
		var turn_player_id: int = int(context.get("turn_player_id", -1))
		var best_recipient_attitude: float = _get_best_snapshot_recipient_attitude(authoritative_snapshot, turn_player_id, evaluator)
		var option_id: String = str(payload.get("selected_control_id", ""))
		if option_id == DISCARD_OPTION_ID:
			return best_recipient_attitude / AI_ATTITUDE_DIVISOR - AI_DISCARD_COST
		if option_id == LOSE_HP_OPTION_ID:
			return best_recipient_attitude / AI_ATTITUDE_DIVISOR - AI_LOSE_HP_COST
		return 0.0
	if choice_kind == "zhenqi_discard_card":
		# 强制弃置费用；返回负保留价值，使 AI 在合法候选中选择价值最低的一张。
		var selected_cards: Array = payload.get("selected_card_uids", []) as Array
		return -evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), int(context.get("turn_player_id", -1))) if selected_cards.size() == 1 else -100.0
	if choice_kind == "zhenqi_recipient":
		# 领袖选择受益者；强制目标中优先选择当前身份态度最高的角色。
		var selected_targets: Array = payload.get("selected_target_ids", []) as Array
		return evaluator.get_attitude(authoritative_snapshot, owner_player_id, int(selected_targets[0])) if selected_targets.size() == 1 else -100.0
	return 0.0


## 返回费用支付者对其他贝洛伯格角色的最高可感知态度；没有合法受益者时保持0分并取消发动。
func _get_best_snapshot_recipient_attitude(authoritative_snapshot: Dictionary, turn_player_id: int, evaluator: Object) -> float:
	# 最佳态度结果；负态度不会抬高可选技能的发动收益。
	var result: float = 0.0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前公开玩家快照；只使用角色、存活、离场和稳定 ID 字段，不读取隐藏身份分支。
		var player: Dictionary = player_variant as Dictionary
		var player_id: int = int(player.get("player_id", -1))
		if player_id == turn_player_id or not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
			continue
		var character: Dictionary = GameDatabase.get_character(str(player.get("character_id", "")))
		if str(character.get("faction", "")) == FACTION_ID:
			result = maxf(result, evaluator.get_attitude(authoritative_snapshot, turn_player_id, player_id))
	return result
