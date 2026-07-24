extends SkillDefinition

## 【百折】技能源码。非锁定前段消耗“斗志”视为使用【决斗】，锁定后段按每个伤害点获得标记。

## “斗志”公开标记的稳定ID；百折与制动共享同一资源池。
const DOUZHI_MARK_ID: String = "douzhi"

## “斗志”公开标记的单字图标；界面标记组件只显示首个字符。
const DOUZHI_MARK_ICON: String = "斗"

## 百折主动使用固定消耗的“斗志”数量；每次为2枚且没有主动发动次数限制。
const DUEL_MARK_COST: int = 2

## 锁定后段在每个全局回合内最多获得的“斗志”数量；逐点伤害超过上限时剩余点不再获得。
const GAIN_LIMIT_PER_TURN: int = 3

## 百折生成的虚拟牌稳定定义ID；使用完整【决斗】目标、响应和伤害流程。
const DUEL_DEFINITION_ID: String = "juedou"

## 百折虚拟【决斗】固定目标数；技能每次只能选择1名其他合法角色。
const DUEL_TARGET_COUNT: int = 1

## “斗志”公开标记的显示排序；固定20使共享资源稳定排列在普通状态标记之前。
const DOUZHI_MARK_ORDER: int = 20

## AI对每枚“斗志”的基础机会成本；默认1.0分，使百折会比较【决斗】收益与后续制动资源。
const AI_DOUZHI_VALUE: float = 1.0

## AI上报百折目标的基础负面牌效；默认-1.5分并声明伤害与【杀】响应语义。
const AI_DUEL_TARGET_RESULT: float = -1.5

## 当前统计标记获得次数对应的全局回合号；默认-1表示尚未在本局触发。
var _tracked_turn_number: int = -1

## 当前全局回合已经通过百折锁定后段获得“斗志”的次数；范围为0至3。
var _gains_this_turn: int = 0


## 写入技能静态信息；技能正文逐字保持设计原文，half_locked明确标注前后段规则边界。
func _init() -> void:
	super({
		"id":"baizhe",
		"name":"百折",
		"trigger":"active/damagePointAfter",
		"enable":"phaseUse",
		"ui_enabled":true,
		"half_locked":true,
		"sell_blood_value":1.0,
		"description":"你可以消耗2枚“斗志”标记并视为使用一张【决斗】。锁定技，当你受到或造成1点伤害后，你获得一枚“斗志”标记，每回合限3次。",
	})


## 订阅逐点伤害后时机；locked_segment为true保证“非锁定技失效”时仅保留获得标记的锁定后段。
func install() -> void:
	subscribe_timing("damagePointAfter", _on_damage_point_after, "global", 0, false, false, Callable(), true)


## 每受到或造成1点伤害后获得1枚“斗志”；自己对自己造成伤害时“或”条件只结算一次。
func _on_damage_point_after(event: RuleEvent) -> void:
	if event.source_id != owner_player_id and event.target_id != owner_player_id:
		return
	_reset_gain_count_if_needed()
	if _gains_this_turn >= GAIN_LIMIT_PER_TURN:
		return
	# 修改后的“斗志”数量；统一标记端口负责公开快照、上限与界面刷新。
	var changed_count: int = int(host.call("change_player_mark_count", owner_player_id, DOUZHI_MARK_ID, 1, _build_douzhi_mark_data()))
	if changed_count <= 0:
		return
	_gains_this_turn += 1
	announce_activation({
		"mark_id":DOUZHI_MARK_ID,
		"mark_count":changed_count,
		"damage_point_index":int(event.data.get("damage_point_index", 1)),
		"damage_total_amount":int(event.data.get("damage_total_amount", 1)),
	})


## 判断当前出牌阶段是否至少拥有2枚“斗志”且存在一个合法【决斗】目标。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；主动前段只能在自己的出牌阶段使用。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game \
		and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" \
		and _get_douzhi_count() >= DUEL_MARK_COST and not _get_legal_duel_targets().is_empty()


## 发动百折前段；直接动作携带目标时立即复核并结算，否则打开单目标确认流程。
func activate(context: Dictionary = {}) -> String:
	# 已提交目标数组；AI与网络动作通过相同字段进入权威复核。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if target_ids.size() == DUEL_TARGET_COUNT:
		return "" if _execute_duel(target_ids) else "【百折】的“斗志”不足或【决斗】目标已经失效。"
	# 合法【决斗】目标；距离不限，但仍排除自己、死亡、离场和技能免疫目标。
	var legal_target_ids: Array[int] = _get_legal_duel_targets()
	if legal_target_ids.is_empty():
		return "当前没有合法的【决斗】目标。"
	request_target_selection("【百折】请选择【决斗】目标", legal_target_ids, DUEL_TARGET_COUNT, DUEL_TARGET_COUNT, true, {"kind":"baizhe_duel_target"})
	return ""


## 恢复百折的【决斗】目标选择；取消不消耗“斗志”。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "baizhe_duel_target" or response == null:
		return false
	if response.confirmed and response.target_ids.size() == DUEL_TARGET_COUNT:
		_execute_duel(response.target_ids)
	return true


## 复核目标、消耗2枚“斗志”并建立无材料【决斗】；执行入口异常失败时返还已扣标记。
func _execute_duel(target_ids: Array[int]) -> bool:
	if _get_douzhi_count() < DUEL_MARK_COST or str(host.card_rules.validate_virtual_use(owner_player_id, DUEL_DEFINITION_ID, target_ids)) != "":
		return false
	# 支付后标记数量；先支付再建立牌事件，避免响应与伤害时机看到尚未消费的旧资源。
	var remaining_count: int = int(host.call("change_player_mark_count", owner_player_id, DOUZHI_MARK_ID, -DUEL_MARK_COST))
	if bool(host.call("execute_cardless_virtual_card_use", owner_player_id, DUEL_DEFINITION_ID, target_ids, "")):
		announce_activation({"target_ids":target_ids.duplicate(), "mark_cost":DUEL_MARK_COST, "remaining_mark_count":remaining_count, "virtual_card_id":DUEL_DEFINITION_ID})
		observe_identity_behavior(target_ids, {"target_result":AI_DUEL_TARGET_RESULT, "damage":true, "respond_sha":true})
		return true
	host.call("change_player_mark_count", owner_player_id, DOUZHI_MARK_ID, DUEL_MARK_COST, _build_douzhi_mark_data())
	return false


## 返回当前全部合法【决斗】单目标；统一规则服务同时处理目标数量、免疫和存活状态。
func _get_legal_duel_targets() -> Array[int]:
	return host.card_rules.list_legal_virtual_targets(owner_player_id, DUEL_DEFINITION_ID)


## 返回持有者当前“斗志”数量；没有标记时为0。
func _get_douzhi_count() -> int:
	return maxi(int((host.call("get_player_mark", owner_player_id, DOUZHI_MARK_ID) as Dictionary).get("count", 0)), 0)


## 构造首次创建“斗志”标记所需的公开说明；后续数量修改会保留同一元数据。
func _build_douzhi_mark_data() -> Dictionary:
	return {
		"icon":DOUZHI_MARK_ICON,
		"name":"斗志",
		"description":"卢卡通过【百折】获得的共享资源，可由【百折】和【制动】消耗。",
		"count":1,
		"source_player_id":owner_player_id,
		"order":DOUZHI_MARK_ORDER,
	}


## 在首次逐点伤害或进入新全局回合时重置每回合获得次数。
func _reset_gain_count_if_needed() -> void:
	if _tracked_turn_number == host.state.turn_number:
		return
	_tracked_turn_number = host.state.turn_number
	_gains_this_turn = 0


## 为AI枚举每名合法【决斗】目标；资源不足或非当前出牌阶段时不追加动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for target_id: int in _get_legal_duel_targets():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id]}})


## 评估百折主动动作；复用【决斗】完整牌效评分并扣除2枚可供制动使用的资源机会成本。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 百折虚拟牌动作；目标与技能动作保持一致，交给通用响应和伤害估值。
	var duel_action: Dictionary = build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
	return evaluator.score_action(authoritative_snapshot, duel_action, owner_player_id) - float(DUEL_MARK_COST) * AI_DOUZHI_VALUE


## 构造百折实际生成的无材料【决斗】代理动作，供其他锁定技和通用牌效AI共同修正。
func build_ai_virtual_card_action(_authoritative_snapshot: Dictionary, action: Dictionary, _evaluator: Object) -> Dictionary:
	return {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":DUEL_DEFINITION_ID, "target_ids":(action.get("target_ids", []) as Array).duplicate()}
