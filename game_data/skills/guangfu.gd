extends SkillDefinition

## 【光覆】技能源码。限定发动后令一名角色摸牌，并在本回合结束时为其复原一项已经发动的限定技。

## 光覆立即令目标摸取的牌数；固定1张，来自技能原文且不在运行时动态修改。
const DRAW_COUNT: int = 1

## AI选择自己作为目标时计入的光覆自复原价值；默认6.0使通常局面优先形成可再次发动的循环。
const AI_SELF_RESTORE_VALUE: float = 6.0

## AI按友方每项已发动限定技计入的可复原价值；默认4.0，最多统计两项以允许高收益队友超过通常的自身优先级。
const AI_ALLY_LIMITED_SKILL_VALUE: float = 4.0

## AI计入队友复原收益的限定技数量上限；默认2避免扩展模式叠加大量技能时评分无限增长。
const AI_ALLY_LIMITED_SKILL_COUNT_CAP: int = 2

## AI在文字选择中复原光覆自身的固定优先分；默认100保证自目标时严格按设计优先复原本技能。
const AI_SELF_GUANGFU_RESTORE_PRIORITY: float = 100.0

## AI在文字选择中复原普通主动限定技的额外分；默认2.0优先恢复可由玩家主动规划的技能。
const AI_ACTIVE_LIMITED_SKILL_PRIORITY: float = 2.0

## 光覆对目标的公开身份行为值；正1表示摸牌与复原均属于帮助行为，不改变实际阵营。
const IDENTITY_TARGET_RESULT: float = 1.0

## 本次光覆指定的目标玩家ID；默认-1表示没有等待回合结束的复原效果。
var _recipient_player_id: int = -1

## 本次光覆发动时的全局回合号；默认-1，用于拒绝异常跨回合残留状态在未来回合错误复原技能。
var _activation_turn_number: int = -1


## 写入技能静态信息；技能正文逐字保持主公提供的原文。
func _init() -> void:
	super({
		"id":"guangfu",
		"name":"光覆",
		"trigger":["active", "phaseEnd"],
		"enable":"phaseUse",
		"ui_enabled":true,
		"limited":true,
		"description":"限定技，出牌阶段，你可令一名角色摸一张牌。本回合结束时，若其有已发动的限定技，你复原其中一项限定技。",
	})


## 订阅持有者回合结束时机；只有本技能实际发动后保存的目标才会进入复原选择。
func install() -> void:
	subscribe_timing("phaseEnd", _on_owner_phase_end, "player")


## 仅在自身出牌阶段、限定额度未用且至少存在一名存活在场角色时开放主动入口。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或限定额度已经消耗时不得继续发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and has_available_intrinsic_use() \
		and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" \
		and not _get_target_ids().is_empty()


## 发动光覆；动作已经携带唯一目标时直接复核，否则创建统一单目标选择请求。
func activate(context: Dictionary = {}) -> String:
	# 已提交目标数组；目标允许为停云自己，始终通过稳定玩家ID传递。
	var target_ids: Array[int] = []
	for target_id_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_id_variant))
	if target_ids.size() == 1:
		return "" if _execute_guangfu(target_ids[0]) else "【光覆】的目标、阶段或限定次数已经失效。"
	request_target_selection("【光覆】请选择摸一张牌的角色", _get_target_ids(), 1, 1, true, {"kind":"guangfu_target"})
	return ""


## 恢复光覆的目标选择或回合尾限定技选择；目标选择可取消，已经满足条件的复原选择不可取消。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；主动目标和回合尾技能选项使用两个稳定kind隔离。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "guangfu_target":
		if response.confirmed and response.target_ids.size() == 1:
			_execute_guangfu(response.target_ids[0])
		return true
	if choice_kind != "guangfu_restore_limited":
		return false
	if not response.confirmed:
		return true
	# 待复原角色；使用回合尾上下文而非易失成员变量，保证异步选择恢复后目标归属稳定。
	var recipient_id: int = int(context.get("recipient_id", -1))
	# 选择的限定技ID；必须仍在当前角色已发动候选中，等待期间复原或死亡会令旧选项安全失效。
	var selected_skill_id: String = str(response.control_id)
	# 当前仍已发动的限定技；权威运行时状态是最终依据，客户端选项不能伪造普通技能或觉醒技。
	var used_limited_skill_ids: Array[String] = host.call("get_used_limited_skill_ids", recipient_id) as Array[String]
	if used_limited_skill_ids.has(selected_skill_id):
		host.call("restore_limited_skill_use", recipient_id, selected_skill_id, get_id())
	return true


## 最终复核目标、登记回合尾效果并摸1张牌；记录发动后限定额度立即消耗，供同回合尾识别光覆自身已发动。
func _execute_guangfu(target_id: int) -> bool:
	if not can_activate() or not _get_target_ids().has(target_id):
		return false
	_recipient_player_id = target_id
	_activation_turn_number = host.state.turn_number
	announce_activation({"target_id":target_id, "draw_count":DRAW_COUNT})
	observe_identity_behavior([target_id], {"target_result":IDENTITY_TARGET_RESULT})
	host.call("draw", target_id, DRAW_COUNT)
	return true


## 本回合结束时读取目标当前已发动限定技；有候选则强制由停云选择一项精确复原，没有候选则效果自然结束。
func _on_owner_phase_end(_event: RuleEvent) -> void:
	if _recipient_player_id < 0 or _activation_turn_number != host.state.turn_number:
		_recipient_player_id = -1
		_activation_turn_number = -1
		return
	# 本次复原目标；成员状态在创建选择前清空，防止阶段恢复或重复时机生成第二个相同请求。
	var recipient_id: int = _recipient_player_id
	_recipient_player_id = -1
	_activation_turn_number = -1
	# 复原目标当前状态；死亡或离场角色不再创建必然失败的强制选择，也不会获得新的限定技额度。
	var recipient: PlayerState = host.state.get_player(recipient_id)
	if recipient == null or not recipient.alive or recipient.out_of_game:
		return
	# 目标当前已发动限定技；普通限定技进入候选，觉醒技按规则不属于“限定技”文字选择。
	var used_limited_skill_ids: Array[String] = host.call("get_used_limited_skill_ids", recipient_id) as Array[String]
	if used_limited_skill_ids.is_empty():
		return
	# 玩家可见技能选项；稳定ID提交，中文名只用于显示，不参与恢复判断。
	var options: Array[Dictionary] = []
	for skill_id: String in used_limited_skill_ids:
		# 当前技能定义；缺失名称时回退稳定ID，仍允许权威状态中的合法实例被复原。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		options.append({"id":skill_id, "label":"复原【%s】" % str(skill_definition.get("name", skill_id))})
	# AI偏好选项；自身目标固定优先光覆，其他角色按主动性与稳定顺序选择最值得复原的一项。
	var preferred_skill_id: String = _select_preferred_limited_skill(recipient_id, used_limited_skill_ids)
	request_control_selection("光覆", "请选择为目标复原的一项限定技", options, false, {"kind":"guangfu_restore_limited", "recipient_id":recipient_id, "limited_skill_ids":used_limited_skill_ids.duplicate(), "ai_prefer_control_id":preferred_skill_id})


## 返回场上全部存活在场角色；光覆可以选择停云自己，也不按阵营限制玩家的合法目标。
func _get_target_ids() -> Array[int]:
	# 合法目标结果；保持权威座次顺序供界面、AI与回放稳定复用。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game:
			result.append(player.player_id)
	return result


## 为AI逐一枚举全部合法目标；自身、友方与敌方仍通过同一权威动作结构提交。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for target_id: int in _get_target_ids():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id]}})


## 评估光覆目标；通常优先自己以在回合尾复原光覆，友方拥有多项已发动限定技时可超过自身循环收益。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作目标；光覆必须且只能选择一名存活在场角色。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return -100.0
	# 目标稳定ID；用于读取公开资源、限定技状态和阵营态度。
	var target_id: int = int(target_ids[0])
	# 目标公开快照；缺失或离场目标不应获得任何发动收益。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or not bool(target.get("alive", false)) or bool(target.get("out_of_game", false)):
		return -100.0
	# 立即摸1张的统一资源收益；友方为正、敌方为负，继承濒死与身份估值。
	var score: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, DRAW_COUNT, 0)
	if target_id == owner_player_id:
		return score + AI_SELF_RESTORE_VALUE
	# 目标态度；复原敌方限定技应形成负收益，不因候选数量转为正分。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 已发动限定技数量；快照由权威控制器补充，不从普通禁用按钮或历史记录推断。
	var used_limited_skill_count: int = (target.get("used_limited_skill_ids", []) as Array).size()
	# 队友复原收益；最多统计2项，使通常仍优先自己，但多项高潜力队友可以成为合理目标。
	var restore_value: float = float(mini(used_limited_skill_count, AI_ALLY_LIMITED_SKILL_COUNT_CAP)) * AI_ALLY_LIMITED_SKILL_VALUE
	return score + attitude / 5.0 * restore_value


## 评估回合尾限定技文字选项；自身严格优先光覆，其他目标优先可主动发动的限定技并保持稳定顺序。
func score_ai_choice(_authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, _evaluator: Object) -> float:
	# 请求上下文；非光覆复原选择不提供额外评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "guangfu_restore_limited":
		return 0.0
	# 标准选择负载；强制请求必须确认并携带一个稳定控制项ID。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return -100.0
	# 选择的限定技ID；兼容统一协议的selected_control_id与旧控制项字段。
	var selected_skill_id: String = str(payload.get("selected_control_id", payload.get("control_id", "")))
	# 请求建立时的候选ID；不在候选中的伪造技能获得严格负分。
	var limited_skill_ids: Array = context.get("limited_skill_ids", []) as Array
	if not limited_skill_ids.has(selected_skill_id):
		return -100.0
	# 复原目标；选择自己时光覆拥有最高固定优先级，符合通常先给自己再复原本技能的策略。
	var recipient_id: int = int(context.get("recipient_id", -1))
	if recipient_id == owner_player_id and selected_skill_id == get_id():
		return AI_SELF_GUANGFU_RESTORE_PRIORITY
	# 当前技能元数据；主动限定技在基础正分上获得小幅加成，被动限定技仍是合法且有价值的复原项。
	var skill_definition: Dictionary = GameDatabase.get_skill(selected_skill_id)
	return 10.0 + (AI_ACTIVE_LIMITED_SKILL_PRIORITY if bool(skill_definition.get("ui_enabled", false)) else 0.0)


## 选出AI在回合尾最希望复原的限定技；自身目标先找光覆，其他角色优先主动限定技且不依赖具体武将ID。
func _select_preferred_limited_skill(recipient_id: int, used_limited_skill_ids: Array[String]) -> String:
	if recipient_id == owner_player_id and used_limited_skill_ids.has(get_id()):
		return get_id()
	for skill_id: String in used_limited_skill_ids:
		# 当前技能元数据；主动限定技通常能立即创造下一次策略选择，因此优先于纯触发限定技。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		if bool(skill_definition.get("ui_enabled", false)):
			return skill_id
	return used_limited_skill_ids[0] if not used_limited_skill_ids.is_empty() else ""
