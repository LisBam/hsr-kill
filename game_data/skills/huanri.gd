extends SkillDefinition

## 【换日】技能源码。持有者每个出牌阶段可移除全部“币”，并对一名其他角色造成等量普通伤害。

## 与聚寇共享的“币”公开标记稳定ID；换日只读取并移除该标记。
const COIN_MARK_ID: String = "bi"

## 换日对目标的公开身份行为值；负数表示明确伤害行为，不改变实际伤害数值。
const IDENTITY_TARGET_RESULT: float = -1.0

## 当前出牌阶段是否已经成功发动；每个phaseUseBegin重置，复原武将牌技能时新实例也恢复false。
var _used_this_play_phase: bool = false


## 写入主动技能静态信息；技能描述逐字保持主公提供的原文。
func _init() -> void:
	super({
		"id":"huanri",
		"name":"换日",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"description":"出牌阶段限一次，你可移除你的所有“币”并对一名其他角色造成等量点伤害。",
	})


## 订阅自身每个出牌阶段开始时机；普通、额外与转换出牌阶段均恢复一次额度。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")


## 仅在自身出牌阶段、尚未发动、至少有一枚“币”且存在其他存活目标时开放技能。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡或离场角色不开放主动入口。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and not _used_this_play_phase \
		and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" \
		and _get_coin_count() > 0 and not _get_target_ids().is_empty()


## 直接动作携带唯一目标时立即执行，否则创建统一单目标选择请求。
func activate(context: Dictionary = {}) -> String:
	# 已提交目标数组；AI和网络动作可以直接携带唯一目标，仍由执行函数完整复核。
	var target_ids: Array[int] = []
	for target_id_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_id_variant))
	if target_ids.size() == 1:
		return "" if _execute_huanri(target_ids[0]) else "【换日】的目标、币或阶段次数已经失效。"
	request_target_selection("【换日】请选择伤害目标", _get_target_ids(), 1, 1, true, {"kind":"huanri_target"})
	return ""


## 恢复目标选择；取消不移除“币”也不消耗阶段次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "huanri_target" or response == null:
		return false
	if response.confirmed and response.target_ids.size() == 1:
		_execute_huanri(response.target_ids[0])
	return true


## 最终复核目标与“币”，移除全部标记和对应手牌上限后造成等量伤害。
func _execute_huanri(target_id: int) -> bool:
	if not can_activate() or not _get_target_ids().has(target_id):
		return false
	# 本次移除的全部“币”数量；也是最终造成的普通伤害点数。
	var coin_count: int = _get_coin_count()
	if coin_count <= 0:
		return false
	_used_this_play_phase = true
	host.call("change_player_mark_count", owner_player_id, COIN_MARK_ID, -coin_count)
	host.call("change_hand_limit_bonus", owner_player_id, -coin_count, get_id())
	announce_activation({"target_id":target_id, "removed_coin_count":coin_count, "damage":coin_count})
	observe_identity_behavior([target_id], {"target_result":IDENTITY_TARGET_RESULT, "damage":true})
	get_owner_skill_player().damage(coin_count, get_skill_player(target_id))
	return true


## 每个新的自身出牌阶段恢复一次发动额度。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 返回当前公开“币”数量；标记不存在时为0。
func _get_coin_count() -> int:
	return maxi(int((host.call("get_player_mark", owner_player_id, COIN_MARK_ID) as Dictionary).get("count", 0)), 0)


## 返回除持有者外全部存活在场角色；保持权威座次顺序供UI、AI与回放共用。
func _get_target_ids() -> Array[int]:
	return host.call("get_other_alive_player_ids", owner_player_id) as Array[int]


## 为AI逐一枚举所有合法目标，避免进入选择窗口后才发现没有敌方候选。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for target_id: int in _get_target_ids():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id]}})


## AI按移除的全部“币”计算目标伤害价值；敌方为正收益，友方为负收益。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作目标数组；换日必须且只能包含一名其他角色。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return -100.0
	# 目标稳定ID；使用统一资源变化估值处理阵营、濒死与目标状态。
	var target_id: int = int(target_ids[0])
	return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 0, -_get_coin_count())
