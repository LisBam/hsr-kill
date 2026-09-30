extends SkillDefinition

## 【万死】技能源码。持有者受到伤害后体力恰为1时，可于本回合结束后成为「主演」并执行一个额外的回合。
## 效果按“先登记、后执行”两段实现：伤害当刻只确认意愿，真正的两段效果都在本回合结束后兑现。

## 本技能选择窗口的上下文类型；用于把发动确认与后续可选选择区分开。
const CHOICE_KIND: String = "wansi_confirm"

## 发动确认的稳定选项ID；仅用于选择协议与回放，玩家可见文本由选项label提供。
const CONFIRM_OPTION_ID: String = "wansi_confirm_yes"

## 判定体力值是否满足条件的固定值；与原文“若你的体力值为1”一致，运行时不得修改。
const REQUIRED_HP: int = 1

## 每回合允许发动的次数上限；与原文“每回合限一次”一致。
const USES_PER_TURN: int = 1

## 尚未登记待执行效果的回合号哨兵值；取-1，保证0号回合（测试构造）也能被正确识别。
const NO_PENDING_TURN: int = -1

## AI对“确认发动”的基础正向估值；一个额外完整回合加一次主演身份的长期收益稳定为正，
## 因此取1.0（等价于一张牌的通用资源值），既能压过取消的0分，也不与卡牌资源换算体系冲突。
const AI_CONFIRM_VALUE: float = 1.0

## 当前额度所属全局回合号；默认-1表示尚未同步，额外回合同样拥有独立回合号因而各自刷新额度。
var _tracked_turn_number: int = -1

## 本回合已经发动过的标记；true表示本回合额度已消耗。
var _used_this_turn: bool = false

## 已登记但尚未执行的“本回合结束后”回合号；等于当前回合号时表示本回合结束后需要兑现。
var _pending_turn_number: int = NO_PENDING_TURN

## 已登记但尚未执行的“本回合结束后”所属回合角色ID；与回合号一起唯一确定登记的那个回合。
## 本技能可能在**他人回合**受伤（这是最常见的触发方式：被对手打到1点体力），
## 因此必须记录登记时的回合角色，而不能假设“本回合”就是持有者自己的回合。
var _pending_turn_player_id: int = NO_PENDING_TURN


## 写入技能静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"wansi",
		"name":"万死",
		"ui_enabled":false,
		"description":"每回合限一次，当你受到伤害后，若你的体力值为1，你可于本回合结束后成为“主演”并执行一个额外的回合。",
	})


## 订阅持有者受到伤害之后与本回合结束之后两个时机。
## damageAfter 负责条件判定与意愿确认，phaseAfter 负责兑现“成为主演 + 额外回合”。
## phaseAfter 必须使用 global 关系：原文的“本回合”是**受伤当时所在的那个回合**，
## 而持有者绝大多数是在他人回合被打到1点体力；若只订阅持有者自己的回合（role="player"），
## 那次登记在对手回合结束时收不到任何时机，而等到自己回合时回合号早已变化，两段效果永远不会兑现。
func install() -> void:
	subscribe_timing("damageAfter", _on_owner_damaged, "target")
	subscribe_timing("phaseAfter", _on_owner_turn_finished, "global")


## 持有者受到伤害后体力恰为1时请求发动确认；不满足条件或本回合额度已用时完全不询问。
func _on_owner_damaged(_event: RuleEvent) -> void:
	_sync_turn_state()
	if _used_this_turn:
		return
	# 持有者权威状态；死亡或离场的持有者不再创建任何选择窗口。
	var owner: PlayerState = _get_owner()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 体力条件；只有恰好等于1时才可能发动，高于1或已进入濒死都不成立。
	if owner.hp != REQUIRED_HP:
		return
	# 确认选项；只有一项，取消即表示本次不发动。
	var options: Array[Dictionary] = [{"id":CONFIRM_OPTION_ID, "label":"确定"}]
	# 选择上下文；只保存可序列化字段，本回合结束时据此复核是否仍然有效。
	var choice_context: Dictionary = {"kind":CHOICE_KIND, "turn_number":_get_turn_number()}
	request_control_selection("万死", "【万死】是否于本回合结束后成为“主演”并执行一个额外的回合？", options, true, choice_context)


## 恢复万死的发动确认；确认时只登记待执行标记并消耗本回合额度，不在伤害当刻执行任何效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null or str(context.get("kind", "")) != CHOICE_KIND:
		return false
	if not response.confirmed or response.control_id != CONFIRM_OPTION_ID:
		return true
	_sync_turn_state()
	# 等待期间本回合额度可能已被消耗；此时本次确认按未发动处理。
	if _used_this_turn:
		return true
	# 登记待执行回合号与回合角色；只有“登记的那个回合”真正结束时才会兑现。
	var turn_number: int = _get_turn_number()
	_used_this_turn = true
	_pending_turn_number = turn_number
	_pending_turn_player_id = _get_turn_player_id()
	announce_activation({"turn_number":turn_number})
	return true


## 登记的那个回合完全结束之后兑现两段效果：先成为「主演」，再执行一个额外的完整回合。
## 匹配条件是“登记的回合角色 + 登记的回合号”，因此自己回合受伤与对手回合受伤都能在正确的回合尾兑现；
## 只按持有者自己的回合匹配会让对手回合的登记永远落空，只按回合号匹配则会在交换座位后误兑现到别的角色身上。
## 额外回合由权威端口按既有队列执行（addPhase），结束后自动恢复正常行动顺序，本技能不参与调度。
func _on_owner_turn_finished(event: RuleEvent) -> void:
	if _pending_turn_player_id != event.player_id or _pending_turn_number != _get_turn_number():
		return
	# 先清除待执行标记；无论后续两步是否成功，本回合的登记都只兑现一次。
	_pending_turn_number = NO_PENDING_TURN
	_pending_turn_player_id = NO_PENDING_TURN
	# 持有者权威状态；等待期间死亡或离场时两段效果均不执行。
	var owner: PlayerState = _get_owner()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 成为主演；由主演服务保证“场上至多一名主演”，原主演会在此被同步顶替。
	host.call("set_starring_role", owner_player_id)
	# 额外回合；权威端口自行处理排队、重复登记与行动顺序恢复。
	get_owner_skill_player().addPhase()


## 评估万死的发动确认；需求口径为“无脑发动”，即条件满足即确认，取消保持中性0分。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理本技能的发动确认。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND:
		return 0.0
	# 动作负载；未确认即取消，取消不消耗额度也不产生收益。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 当前选项ID；只有确认项被视为有效发动。
	if str(payload.get("selected_control_id", "")) != CONFIRM_OPTION_ID:
		return 0.0
	# 持有者公开快照；体力条件在等待期间可能变化，AI不得在条件已失效时提交确认。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty() or int(owner.get("hp", 0)) != REQUIRED_HP:
		return -100.0
	# 确认分；额外回合加一次主演身份的长期收益稳定为正，因此条件成立即发动。
	return AI_CONFIRM_VALUE


## 跨全局回合惰性刷新每回合额度；额外回合拥有独立回合号因此在其中可以再次发动。
func _sync_turn_state() -> void:
	# 当前全局回合号；服务端权威回合号是额度归属的唯一依据。
	var turn_number: int = _get_turn_number()
	if _tracked_turn_number != turn_number:
		_tracked_turn_number = turn_number
		_used_this_turn = false


## 返回技能持有者的权威状态；未绑定权威端口或角色不存在时返回null。
func _get_owner() -> PlayerState:
	if host == null or host.get("state") == null:
		return null
	return host.state.get_player(owner_player_id)


## 返回当前全局回合号；未开始对局时回退0，与项目既有技能口径一致。
func _get_turn_number() -> int:
	if host == null or host.get("state") == null:
		return 0
	return int(host.state.turn_number)


## 返回当前回合角色ID；未开始对局时回退 NO_PENDING_TURN，与回合号哨兵保持同一“没有有效回合”语义。
## 受伤当刻调用：对手回合受伤时该值是对手，因此登记可以精确绑定到那个回合的结束时机。
func _get_turn_player_id() -> int:
	if host == null or host.get("state") == null:
		return NO_PENDING_TURN
	return int(host.state.current_player_id)
