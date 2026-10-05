extends SkillDefinition

## 【巡礼】技能源码。
##
## 一、附加三阶段（非锁定前段，每轮限一次）
##   任意角色的回合开始时，持有者可以依次执行一个额外的摸牌阶段、出牌阶段与弃牌阶段。
##   三个阶段由控制器的额外阶段端口逐个执行：额外摸牌阶段使用本技能配套的 `request_extra_draw_phase`，
##   额外出牌与额外弃牌阶段复用既有端口。每一段**完整结束**后控制器才回调 `continue_extra_phase`，
##   因此三段严格串行，不会与正在等待的阶段叠加。
##   额度按**轮号**记账：额外阶段不会改变 `round_number`，同一轮的后续回合开始时额度已消耗；
##   新的一轮开始后额度自动恢复（惰性比较，不需要轮开始时机）。
##
## 二、阶段内距离改写
##   三个阶段内，持有者与「当前回合角色距离为1的其他角色」之间的距离为1。
##   目标集合在**发动瞬间一次性快照**：快照之后即使座次、坐骑或回合角色变化，本次改写仍按快照生效。
##   实现使用既有 `modify_distance_to_target` 钩子（只对“以持有者为来源”的距离查询生效），
##   不改写任何全局距离数值，也不影响其他角色之间的计算。
##
## 三、武将牌始终背面向上（锁定后段）
##   由 `locks_face_down()` 向核心声明，核心在翻面入口、换将、复活与回合开始窗口统一落实；
##   因此“非锁定技失效”只压制前段的三阶段效果，不会解除背面锁定。
##   持有者自己的回合仍然按统一规则被整体跳过，所以他的判定区永远不会结算——这正是本技能
##   为延时锦囊写下“收益为0”AI 口径的原因（见 `modify_ai_incoming_card_effect`）。
##
## AI：发动确认严格正分（无脑发动），取消保持中性 0 分。

## 发动确认窗口的种类键值；用于在选择恢复时区分本技能的询问。
const CHOICE_KIND_ACTIVATE: String = "xunli_activate"

## 发动确认选项的稳定ID；仅用于选择协议与回放，玩家可见文本由选项label提供。
const CONFIRM_OPTION_ID: String = "xunli_activate_yes"

## 延后启动阶段链的结算种类；确认窗口仍在等待响应时不能立即创建新请求。
const SETTLEMENT_KIND_START_CHAIN: String = "xunli_start_chain"

## 阶段完成上下文中的种类键值；控制器据此把额外阶段完成通知交回本技能。
const CHAIN_COMPLETION_KIND: String = "xunli_extra_phase"

## 阶段完成上下文中携带阶段标识的键名。
const CHAIN_STAGE_KEY: String = "stage"

## 阶段顺序中的摸牌阶段标识。
const STAGE_DRAW: String = "draw"

## 阶段顺序中的出牌阶段标识。
const STAGE_PLAY: String = "play"

## 阶段顺序中的弃牌阶段标识。
const STAGE_DISCARD: String = "discard"

## 额外阶段的来源标记；写入运行时事件与日志，便于回溯阶段归属。
const REASON_XUNLI: String = "xunli"

## 距离改写后的固定距离；与原文“距离1”一致，运行时不得修改。
const DISTANCE_ONE: int = 1

## 尚未发动过任何一轮的轮号哨兵；取-1，保证0号轮（测试构造）也能被识别为未发动。
const NO_ROUND: int = -1

## 尚未记录回合角色的哨兵；与轮号哨兵保持同一“没有有效回合”语义。
const NO_TURN_PLAYER: int = -1

## 发动确认的固定正分；“无脑发动”口径下条件成立即确认，取消保持中性0分。
const AI_ACTIVATE_VALUE: float = 1.0

## 条件已失效却仍提交确认时的惩罚分；防止等待期间持有者死亡后AI继续发动。
const AI_INVALID_PENALTY: float = -100.0

## 延时锦囊对持有者的收益分；其判定永远不会结算，因此恒为0。
const AI_DELAYED_TRICK_VALUE: float = 0.0

## 本技能已经发动过的轮号；等于当前轮号时本轮额度已消耗。
var _used_round_number: int = NO_ROUND

## 阶段链当前阶段标识；空串表示没有进行中的阶段链。
var _chain_stage: String = ""

## 本次发动快照的距离改写目标集合；键为目标玩家ID，值为true。
## 使用字典而不是数组，使距离查询（每次用牌都会询问）保持常数时间命中判断。
var _override_target_ids: Dictionary = {}

## 距离改写是否生效；只在阶段链进行期间为true，链结束或卸载时必须复位。
var _distance_override_active: bool = false

## 本次发动的当前回合角色ID；只用于日志与完成上下文，不参与距离计算。
var _turn_player_id: int = NO_TURN_PLAYER


## 写入技能静态信息；玩家可见描述严格保持需求提供的原文。
## half_locked 明确“非锁定前段（三阶段与距离改写） + 锁定后段（武将牌始终背面向上）”的规则边界。
func _init() -> void:
	super({
		"id":"xunli",
		"name":"巡礼",
		"trigger":"phaseBefore",
		"ui_enabled":false,
		"half_locked":true,
		"description":"每轮限一次，一名角色的回合开始时，你可以依次执行额外的摸牌阶段、出牌阶段、弃牌阶段，这些阶段内，你计算与所有和当前回合角色距离为1的其他角色的距离1。锁定技，你的武将牌始终背面向上。",
	})


## 订阅全局回合开始窗口；"global"关系使任何角色的回合开始都会询问，包含持有者自己。
## 本订阅是半锁定技前段：locked_segment保持默认false，“非锁定技失效”期间不再创建询问；
## 后段的背面锁定由 locks_face_down() 独立声明，不受该压制影响。
func install() -> void:
	subscribe_timing("phaseBefore", _on_any_turn_before, "global")


## 卸载时清除阶段链与距离改写；换将、失去技能或重新获得技能都不会残留旧改写。
## 只清理本技能的运行时字段，不撤销核心已经创建、并且会自行结束的额外阶段。
func uninstall() -> void:
	_finalize_chain()
	super()


## 任意角色的回合开始时询问是否发动；额度已用、持有者失效或前段被压制时完全不询问。
func _on_any_turn_before(event: RuleEvent) -> void:
	if not _can_request_activation():
		return
	# 正在开始回合的角色；phaseBefore的player_id即该角色，距离快照以它为原点。
	var turn_player_id: int = int(event.player_id)
	if turn_player_id < 0:
		return
	_turn_player_id = turn_player_id
	# 确认选项；只有一项，取消表示本次不发动。
	var options: Array[Dictionary] = [{"id":CONFIRM_OPTION_ID, "label":"确定"}]
	request_control_selection("巡礼", "【巡礼】是否依次执行额外的摸牌阶段、出牌阶段、弃牌阶段？", options, true, {"kind":CHOICE_KIND_ACTIVATE, "turn_player_id":turn_player_id})


## 恢复发动确认：确认时消耗本轮额度、快照距离改写目标并启动三阶段链。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != CHOICE_KIND_ACTIVATE:
		return false
	if response == null or not response.confirmed or response.control_id != CONFIRM_OPTION_ID:
		return true
	# 等待期间额度、持有者或前段可用性都可能变化；失效时本次确认按未发动处理，不消耗额度。
	if not _can_request_activation():
		return true
	# 等待期间可能已经开始别的回合；此时以上下文记录的回合角色为原点，不能用最新一次询问的字段。
	var turn_player_id: int = int(context.get("turn_player_id", NO_TURN_PLAYER))
	if turn_player_id < 0 or host.state.current_player_id != turn_player_id:
		return true
	_turn_player_id = turn_player_id
	_used_round_number = int(host.state.round_number)
	_snapshot_override_targets(turn_player_id)
	# 快照完成后才开启改写，保证接下来的三个阶段都使用同一份目标集合。
	_distance_override_active = true
	announce_activation({"turn_player_id":_turn_player_id, "round_number":_used_round_number, "distance_target_ids":_override_target_ids.keys()})
	# 本确认窗口此刻仍在等待响应，控制器会拒绝“已有待响应选择”期间创建的新请求，
	# 而额外阶段一开始就要派发自己的阶段窗口，因此先延后到统一结算管线清空后再启动阶段链。
	if host.has_pending_card_choice():
		defer_settlement({"kind":SETTLEMENT_KIND_START_CHAIN})
		return true
	_start_chain()
	return true


## 恢复延后的阶段链启动；统一结算管线清空后才创建第一项额外阶段。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != SETTLEMENT_KIND_START_CHAIN:
		return false
	_start_chain()
	return true


## 接收额外阶段完整结束通知并按顺序推进下一阶段；三个阶段彼此独立，因此被取消不终止整条链。
func continue_extra_phase(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != CHAIN_COMPLETION_KIND:
		return false
	# 只处理本技能自己创建的阶段通知；阶段标识不匹配时视为过期通知。
	var stage: String = str(context.get(CHAIN_STAGE_KEY, ""))
	if stage.is_empty() or stage != _chain_stage:
		return false
	# 持有者失效或离场时立即收尾，不再创建后续阶段。
	if not _is_owner_usable():
		_finalize_chain()
		return true
	var next_stage: String = _get_next_stage(stage)
	if next_stage.is_empty():
		_finalize_chain()
		return true
	# 下一阶段创建失败（例如核心已有同类活动阶段）时同样收尾，避免改写状态悬挂。
	if not _request_chain_stage(next_stage):
		_finalize_chain()
	return true


## 阶段链进行期间把快照目标与持有者的距离固定为1；其他目标与其他时间点保持通用座次结果。
## 本钩子只对“以持有者为来源”的距离查询生效，因此不改变其他角色之间的距离计算。
func modify_distance_to_target(target_id: int, current_distance: int) -> int:
	# 持有者自身不受改写；原文只改写“与其他角色”的距离。
	if target_id == owner_player_id:
		return current_distance
	if not _distance_override_active:
		return current_distance
	return DISTANCE_ONE if _override_target_ids.has(target_id) else current_distance


## 声明本技能令持有者的武将牌**始终背面向上**；核心在翻面入口、换将、复活与回合开始窗口统一查询。
## 该声明属于锁定后段：即使“非锁定技失效”压制了前段的三阶段效果，背面锁定仍然成立。
func locks_face_down() -> bool:
	return true


## 评估发动确认；条件成立即确认，取消保持中性0分。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理本技能的发动确认。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND_ACTIVATE:
		return 0.0
	# 动作负载；未确认或选项不是发动项时不产生收益。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)) or str(payload.get("selected_control_id", "")) != CONFIRM_OPTION_ID:
		return 0.0
	# 持有者公开快照；等待期间死亡或离场时不得提交确认。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty() or not bool(owner.get("alive", false)) or bool(owner.get("out_of_game", false)):
		return AI_INVALID_PENALTY
	return AI_ACTIVATE_VALUE


## 修正其他角色对持有者的来牌估值：延时锦囊对持有者的收益恒为0。
##
## 原因：持有者的回合开始时武将牌始终背面向上，该回合被整体跳过，因此他**永远不会进入判定阶段**；
## 延时锦囊进入其判定区后既不会结算也不会自行弃置，对本角色没有产生任何收益。
## 判定按牌定义元数据（delayed）进行，不写死任何牌ID，新增延时锦囊自动适用。
func modify_ai_incoming_card_effect(_authoritative_snapshot: Dictionary, _actor_id: int, target_id: int, definition: Dictionary, _ai_profile: Dictionary, _target_result: float, _expected_damage_amount: int, current_score: float, _evaluator: Object) -> float:
	if target_id != owner_player_id:
		return current_score
	# 非延时锦囊维持通用估值；普通牌与【杀】仍然可以正常指向持有者。
	if not bool(definition.get("delayed", false)):
		return current_score
	return AI_DELAYED_TRICK_VALUE


## 判断此刻是否可以创建发动询问：额度、持有者状态与非锁定前段可用性都要成立。
func _can_request_activation() -> bool:
	if host == null or host.state == null or host.state.game_over:
		return false
	if _used_round_number == int(host.state.round_number):
		return false
	if not _is_owner_usable():
		return false
	return can_use_effect()


## 判断持有者此刻是否可以承载技能效果；死亡或离场的持有者不再创建询问与阶段。
func _is_owner_usable() -> bool:
	var owner: PlayerState = _get_owner()
	return owner != null and owner.alive and not owner.out_of_game


## 启动三阶段链；第一项额外阶段创建失败时直接收尾并解除距离改写。
func _start_chain() -> void:
	if not _is_owner_usable():
		_finalize_chain()
		return
	if not _request_chain_stage(STAGE_DRAW):
		_finalize_chain()


## 请求执行阶段链中的指定阶段；完成上下文绑定本技能实例与武将代次，控制器据此回调 continue_extra_phase。
func _request_chain_stage(stage: String) -> bool:
	_chain_stage = stage
	# 完成上下文；只保存稳定ID与可序列化基础值，不持有任何运行时对象。
	var completion_context: Dictionary = _build_completion_context(stage)
	match stage:
		STAGE_DRAW:
			return bool(host.call("request_extra_draw_phase", owner_player_id, owner_player_id, REASON_XUNLI, completion_context))
		STAGE_PLAY:
			return bool(host.call("request_extra_play_phase", owner_player_id, owner_player_id, REASON_XUNLI, completion_context))
		STAGE_DISCARD:
			return bool(host.call("request_extra_discard_phase", owner_player_id, owner_player_id, REASON_XUNLI, completion_context))
	return false


## 返回阶段链中指定阶段的下一个阶段；末项返回空串表示链已走完。
func _get_next_stage(stage: String) -> String:
	match stage:
		STAGE_DRAW:
			return STAGE_PLAY
		STAGE_PLAY:
			return STAGE_DISCARD
	return ""


## 快照「与当前回合角色距离为1的其他角色」。
##
## 必须在开启距离改写之前调用：快照本身要用核心的距离查询，而该查询会串联全部技能，
## 开着改写会让快照把本轮改写算进去，形成自我污染。
## 只快照存活且未离场的其他角色；持有者本人不是“其他角色”，因此不入集合。
func _snapshot_override_targets(turn_player_id: int) -> void:
	_override_target_ids.clear()
	_distance_override_active = false
	# 权威角色列表；顺序即座次顺序，AI与回放据此稳定复现。
	var players: Array = host.state.players as Array
	for player_variant: Variant in players:
		var player: PlayerState = player_variant as PlayerState
		if player == null or player.player_id == owner_player_id:
			continue
		if not player.alive or player.out_of_game:
			continue
		if int(host.card_rules.calculate_distance(turn_player_id, player.player_id)) == DISTANCE_ONE:
			_override_target_ids[player.player_id] = true


## 构建阶段完成上下文；控制器用技能持有者与稳定技能ID定位本实例。
func _build_completion_context(stage: String) -> Dictionary:
	return {
		"kind":CHAIN_COMPLETION_KIND,
		CHAIN_STAGE_KEY:stage,
		"turn_player_id":_turn_player_id,
		"skill_owner_id":owner_player_id,
		"skill_id":get_id(),
		"skill_character_generation":get_bound_character_generation(),
	}


## 结束本次阶段链并解除距离改写；重复调用安全，阶段链外的调用不产生任何副作用。
func _finalize_chain() -> void:
	_chain_stage = ""
	_distance_override_active = false
	_override_target_ids.clear()
	_turn_player_id = NO_TURN_PLAYER


## 返回技能持有者的权威状态；未绑定权威端口或角色不存在时返回null。
func _get_owner() -> PlayerState:
	if host == null or host.get("state") == null:
		return null
	return host.state.get_player(owner_player_id)
