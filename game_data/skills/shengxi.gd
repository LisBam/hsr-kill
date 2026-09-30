extends SkillDefinition

## 【生息】技能源码。持有者使用基本牌时可摸一张牌，或令本回合结束后永久累加X。
## X 初始为1、只增不减、无上限；每个回合内最多发动X次，额度按该角色的每个回合刷新。

## 摸牌选项的稳定ID；仅用于选择协议与回放，玩家可见文本由选项label提供。
const DRAW_OPTION_ID: String = "shengxi_draw"

## 累加X选项的稳定ID；该选项只登记“待累加次数”，实际累加发生在回合完全结束之后。
const INCREASE_OPTION_ID: String = "shengxi_increase"

## 本技能选择窗口的上下文类型；用于把两段控制选择与目标/牌选择区分开。
const CHOICE_KIND: String = "shengxi_option"

## 累计X在角色私有形态状态中的稳定键名；该字段随权威存档往返且不进入公开快照。
## 键名变更会使旧存档中的累加进度失效，因此必须保持稳定。
const ACCUMULATED_X_STATE_KEY: String = "shengxi_accumulated_x"

## 当前发动额度所属全局回合号在角色私有形态状态中的稳定键名；用于惰性刷新每回合额度。
const TURN_NUMBER_STATE_KEY: String = "shengxi_turn_number"

## 本回合已发动次数在角色私有形态状态中的稳定键名；跨回合时归零。
const USES_THIS_TURN_STATE_KEY: String = "shengxi_uses_this_turn"

## 尚未同步回合号时的哨兵值；取-1，保证0号回合（测试构造）也能被正确识别为“已同步”。
const UNSYNCED_TURN_NUMBER: int = -1

## X 的初始值；与技能原文“X初始为1”一致，仅在角色尚未写入累加值时生效。
const INITIAL_ACCUMULATED_X: int = 1

## 每次发动至少消耗的额度；固定为1，原文“每回合限X次”按次数计数。
const USES_PER_ACTIVATION: int = 1

## 摸牌选项固定摸牌张数；与原文“你可摸1张牌”一致。
const DRAW_OPTION_CARD_COUNT: int = 1

## 从本回合结束起永久累加X的次数；与原文“令本回合结束后X+1”一致。
const INCREASE_AMOUNT_PER_ACTIVATION: int = 1

## AI 对“摸一张已知未知手牌”的基础资源估值；复用统一单牌资源值，不另立一套换算比例。
const AI_DRAW_OPTION_VALUE: float = NonameAIEvaluator.CARD_RESOURCE_VALUE

## AI 判断“X已经足够支撑本回合剩余用牌”的手牌密度下限；X超过手牌数时摸牌收益更高。
const AI_INCREASE_PREFER_HAND_DIVISOR: float = 1.0

## 生息文本在武将牌左上角组合条目中的排序值；固定100，与【逐风】【安可】等数值类提示同层级，
## 使「生息 X」排在【酩酊】【追歼】【永劫】【凶星】等角色状态类提示（排序值50）之后。
## 修改该值会改变同一武将牌上多条提示同时存在时的竖排顺序，运行时不应动态调整。
const CORNER_TEXT_ORDER: int = 100

## 本回合结束时需要累加到X上的待生效次数；键为**登记时所在回合的角色ID**，值为该回合的待累加次数。
## 用按回合分桶的字典而不是单个计数，是因为持有者可能在**不同角色的回合**里各登记一笔
## （最典型的是在别人回合打出【闪】【桃】这类基本牌）；每一笔都必须在自己所属的那个回合结束时兑现，
## 若合并成一个计数，先结束的那个回合会把另一个回合的待累加一起提前吃掉。
## 换将或重装技能会丢弃该值：此时“本回合结束后”的窗口已随旧实例生命周期失效。
var _pending_increase_by_turn: Dictionary = {}


## 写入技能静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"shengxi",
		"name":"生息",
		"ui_enabled":false,
		"description":"每回合限X次，当你使用基本牌时，你可摸1张牌，或令本回合结束后X+1。（X初始为1）",
	})


## 订阅整牌用牌时机与回合结束之后时机；前者判定是否创建二选一，后者兑现待累加的X。
## useCard 是整牌时机，每条用牌只派发一次，因此无需额外的按牌幂等集合。
## phaseAfter 必须使用 global 关系：原文的“本回合结束后”指**使用基本牌时所在的那个回合**，
## 而持有者完全可能在他人回合里打出【闪】【桃】等基本牌；若只订阅持有者自己的回合（role="player"），
## 那一笔累加会被一直推迟到自己回合结束，导致本回合内后续用牌读到偏小的X，
## 也和“每回合额度按全局回合号刷新”的口径自相矛盾（额度已经按任何人的回合刷新，累加却只认自己的回合）。
func install() -> void:
	subscribe_timing("useCard", _on_owner_card_used, "source")
	subscribe_timing("phaseAfter", _on_owner_turn_finished, "global")
	# 武将牌左上角角标；只要持有本技能就必须显示当前X，因此安装当刻即写入初始值「生息 1」。
	_refresh_corner_text()


## 卸载技能时移除生息自己的公开文本条目；其他技能与状态类角标由各自的来源ID独立维护。
## 与 install() 成对出现，保证换将、失去技能或重装技能后不会残留过期的X角标。
func uninstall() -> void:
	# 待累加记录随实例一起作废：技能已经不在场，之后任何回合结束都不应再改这个角色的X。
	_pending_increase_by_turn.clear()
	if host != null and host.has_method("remove_character_corner_text_entry"):
		host.call("remove_character_corner_text_entry", owner_player_id, _get_corner_entry_id())
	super()


## 持有者使用基本牌时按剩余额度创建二选一；额度耗尽或牌不是基本牌时不询问。
func _on_owner_card_used(event: RuleEvent) -> void:
	# 本次使用的逻辑牌名；视为使用的基本牌同样在此命中，符合项目统一用牌事件口径。
	var card_id: String = str(event.data.get("card_id", ""))
	if not _is_basic_card(card_id):
		return
	_sync_turn_state()
	# 剩余额度；达到上限后不再创建窗口，避免出现必然无效的选择。
	if _get_uses_this_turn() >= _get_accumulated_x():
		return
	# 文字选项；两项互斥，顺序固定为“摸牌”在前，与原文叙述顺序一致。
	var options: Array[Dictionary] = [
		{"id":DRAW_OPTION_ID, "label":"摸一张牌"},
		{"id":INCREASE_OPTION_ID, "label":"令本回合结束后X+1"},
	]
	# 选择上下文；只保存可序列化字段，不持有任何运行时对象。
	var choice_context: Dictionary = {
		"kind":CHOICE_KIND,
		"card_uid":int(event.data.get("card_uid", -1)),
		"card_id":card_id,
		"accumulated_x":_get_accumulated_x(),
		"uses_this_turn":_get_uses_this_turn(),
	}
	request_control_selection("生息", "【生息】请选择一项", options, true, choice_context)


## 恢复生息的二选一；取消视为不发动，不消耗额度也不产生任何效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null or str(context.get("kind", "")) != CHOICE_KIND:
		return false
	if not response.confirmed:
		return true
	# 已选分支ID；未知选项不消耗额度，避免异常提交吞掉本回合的发动机会。
	var option_id: String = response.control_id
	if option_id != DRAW_OPTION_ID and option_id != INCREASE_OPTION_ID:
		return true
	_sync_turn_state()
	# 等待期间额度可能已被其他用牌消耗；此时本次选择按未发动处理。
	if _get_uses_this_turn() >= _get_accumulated_x():
		return true
	_set_uses_this_turn(_get_uses_this_turn() + USES_PER_ACTIVATION)
	announce_activation({"option_id":option_id, "card_id":str(context.get("card_id", "")), "accumulated_x":_get_accumulated_x()})
	if option_id == DRAW_OPTION_ID:
		# 标准摸牌端口；与其他摸牌技能共用同一权威入口，因此在牌堆耗尽时会走统一的洗牌与重开逻辑。
		host.call("draw", owner_player_id, DRAW_OPTION_CARD_COUNT)
		return true
	# 累加X只在“登记时所在的那个回合”完全结束后生效；本回合已消耗的额度不会因此返还。
	# 按回合角色ID分桶，因此他人回合里打出的基本牌会在那个回合结束时兑现，不会被推迟到自己回合。
	var pending_turn_player_id: int = _get_turn_player_id()
	_pending_increase_by_turn[pending_turn_player_id] = int(_pending_increase_by_turn.get(pending_turn_player_id, 0)) + INCREASE_AMOUNT_PER_ACTIVATION
	return true


## 登记的那一笔所属回合完全结束之后兑现待累加的X；只写数值，不创建选择、不摸牌、不发布用牌事件。
## 只兑现“结束回合同属一个角色”的那一桶，因此他人回合与自己回合的登记互不干扰、也不会被提前结算。
func _on_owner_turn_finished(event: RuleEvent) -> void:
	if not _pending_increase_by_turn.has(event.player_id):
		return
	# 本次实际累加次数；先取后清，保证同一个回合的登记只兑现一遍。
	var increase_count: int = int(_pending_increase_by_turn.get(event.player_id, 0))
	_pending_increase_by_turn.erase(event.player_id)
	if increase_count <= 0:
		return
	var next_x: int = _get_accumulated_x() + increase_count
	_set_accumulated_x(next_x)
	# X 是角标显示的唯一数值来源；累加成功后必须立即刷新，避免角标停在上一回合的旧值。
	_refresh_corner_text()
	announce_activation({"increase_count":increase_count, "accumulated_x":next_x})


## 评估生息的二选一；按需求给出的口径决定“摸牌”还是“X+1”。
## 需求口径：X大于手牌数时选择摸一张牌，否则选择X+1。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理本技能的二选一。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND:
		return 0.0
	# 动作负载；未确认的动作表示取消，取消不消耗额度，按中性0分处理。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 当前选择的选项ID；未知选项不给分，避免产生无法执行的动作。
	var option_id: String = str(payload.get("selected_control_id", ""))
	# 技能持有者公开快照；用于读取手牌数与该角色是否仍存活。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty():
		return -100.0
	# 当前累计X；上下文优先，缺失时回退到角色私有状态，保证AI与规则读到同一个数值。
	var accumulated_x: int = int(context.get("accumulated_x", _get_accumulated_x()))
	# 持有者当前手牌数；需求口径中的比较基准。
	var hand_count: int = int(owner.get("hand_count", 0))
	# 需求口径的分支判定；相等时按“不大于”处理，即选择X+1。
	var draw_preferred: bool = float(accumulated_x) > float(hand_count) * AI_INCREASE_PREFER_HAND_DIVISOR
	if option_id == DRAW_OPTION_ID:
		return AI_DRAW_OPTION_VALUE if draw_preferred else 0.0
	if option_id == INCREASE_OPTION_ID:
		# 累加X的收益是无上限的长期额度：需求口径下未被摸牌分支压制时给予固定正向分，
		# 但该分必须严格低于“摸牌更优”时的摸牌收益，保证两个分支不会互相抵消成0分平局。
		return 0.0 if draw_preferred else AI_DRAW_OPTION_VALUE * 0.5
	return 0.0


## 判断一张逻辑牌是否为基本牌；未知牌名按非基本牌处理。
func _is_basic_card(card_id: String) -> bool:
	if card_id.is_empty():
		return false
	# 卡牌静态定义；本技能只按统一的 type 字段判定牌大类，不列举具体牌名。
	var definition: Dictionary = GameDatabase.get_card(card_id)
	return str(definition.get("type", "")) == "basic"


## 跨全局回合惰性刷新每回合额度；不依赖回合开始订阅的时序，额外回合拥有独立回合号因而各自刷新。
func _sync_turn_state() -> void:
	# 技能持有者；角色不存在时无从记账。
	var owner: PlayerState = _get_owner()
	if owner == null:
		return
	# 当前全局回合号；服务端权威回合号是额度归属的唯一依据。
	var turn_number: int = _get_turn_number()
	if int(owner.character_form_state.get(TURN_NUMBER_STATE_KEY, UNSYNCED_TURN_NUMBER)) != turn_number:
		owner.character_form_state[TURN_NUMBER_STATE_KEY] = turn_number
		owner.character_form_state[USES_THIS_TURN_STATE_KEY] = 0


## 返回当前累计X；角色不存在或尚未写入时返回初始值1。
func _get_accumulated_x() -> int:
	# 技能持有者；角色不存在时按初始值回答，保证纯查询不因缺少状态而报错。
	var owner: PlayerState = _get_owner()
	if owner == null:
		return INITIAL_ACCUMULATED_X
	return maxi(int(owner.character_form_state.get(ACCUMULATED_X_STATE_KEY, INITIAL_ACCUMULATED_X)), 0)


## 写入累计X；数值同时决定本回合的可发动次数上限。
func _set_accumulated_x(value: int) -> void:
	# 技能持有者；角色不存在时静默跳过，不建立无法清理的状态。
	var owner: PlayerState = _get_owner()
	if owner == null:
		return
	owner.character_form_state[ACCUMULATED_X_STATE_KEY] = maxi(value, 0)


## 按当前累计X刷新武将牌左上角角标；与【酩酊】共用同一套公开文本通道，由控制器按排序值合成竖排提示。
## 与【逐风】的差异：逐风在0次时隐藏条目，而本技能的X初始为1、只增不减，因此不存在需要隐藏的状态，
## 只要技能实例存活就始终显示完整文本「生息 X」。
## 宿主角标端口缺失时静默跳过，保证纯规则环境（无界面测试）仍可正常结算技能效果。
func _refresh_corner_text() -> void:
	if host == null or not host.has_method("set_character_corner_text_entry"):
		return
	host.call("set_character_corner_text_entry", owner_player_id, _get_corner_entry_id(), "生息 %d" % _get_accumulated_x(), CORNER_TEXT_ORDER)


## 返回本技能实例的稳定武将牌文本条目ID；玩家ID让多名持有【生息】的角色各自维护独立条目。
func _get_corner_entry_id() -> String:
	return "shengxi:%d" % owner_player_id


## 返回本回合已发动次数；角色不存在时返回0。
func _get_uses_this_turn() -> int:
	# 技能持有者；角色不存在时视为没有消耗过额度。
	var owner: PlayerState = _get_owner()
	if owner == null:
		return 0
	return maxi(int(owner.character_form_state.get(USES_THIS_TURN_STATE_KEY, 0)), 0)


## 写入本回合已发动次数。
func _set_uses_this_turn(value: int) -> void:
	# 技能持有者；角色不存在时静默跳过。
	var owner: PlayerState = _get_owner()
	if owner == null:
		return
	owner.character_form_state[USES_THIS_TURN_STATE_KEY] = maxi(value, 0)


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


## 返回当前回合角色ID；未开始对局时回退 UNSYNCED_TURN_NUMBER，与回合号哨兵保持同一“没有有效回合”语义。
## 使用基本牌当刻调用：他人回合里打出的响应基本牌会登记为该回合角色的桶，从而在那个回合结束时兑现。
func _get_turn_player_id() -> int:
	if host == null or host.get("state") == null:
		return UNSYNCED_TURN_NUMBER
	return int(host.state.current_player_id)
