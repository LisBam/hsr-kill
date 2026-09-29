extends CardDefinition

## 【青龙偃月刀】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "qinglong",
		"original_name": "青龙偃月刀",
		"custom_name": "石火梦身",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 3,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "你的【杀】被【闪】抵消时，可对该目标再使用一张无距离限制的【杀】。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":3.5, "equip_value":3.5},
		"ai_use_value": 4.0,
	})


## 执行【青龙偃月刀】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 【杀】被【闪】抵消后，可继续打出一张实体【杀】攻击同一目标。
func on_slash_dodged(slash_effect: Object, context: Dictionary) -> bool:
	if not bool(context.get("dodged", false)):
		return false
	# 攻击者状态；用于日志与响应牌归属。
	var actor: PlayerState = slash_effect.state.get_player(int(context.get("actor_id", -1)))
	# 目标状态；记录原【闪】抵消结果。
	var target: PlayerState = slash_effect.state.get_player(int(context.get("target_id", -1)))
	if actor == null or target == null:
		return true
	# 文案固定使用“使用【闪】”：【闪】响应【杀】属于“使用”，不能写成“打出”。
	slash_effect.host.add_log("%s使用了【闪】抵消了【杀】。" % target.display_name)
	# 追击响应上下文；装备定义 ID 使异步恢复回到本文件。
	var response_context: Dictionary = context.duplicate(true)
	response_context["kind"] = "qinglong_response"
	response_context["responder_id"] = actor.player_id
	response_context["equipment_definition_id"] = get_id()
	response_context["complete_parent_target_after_response"] = true
	# 动作类别为“打出”：追击【杀】不产生牌面效果，只用于继续发起一次新的【杀】。
	response_context["response_action"] = CARD_ACTION_PLAY
	# 追加打出的实体【杀】；空值表示放弃发动。
	var follow_slash: CardInstance = slash_effect.host.request_response_card(actor.player_id, "sha", "是否发动【青龙偃月刀】继续打出【杀】？", response_context)
	if slash_effect.host.has_pending_card_choice():
		return true
	_apply_follow_slash(slash_effect, response_context, follow_slash)
	return true


## 使用追击【杀】重新进入完整单目标流程；伤害固定从基础1点开始。
func _apply_follow_slash(slash_effect: Object, context: Dictionary, follow_slash: CardInstance) -> void:
	if follow_slash == null:
		return
	# 追击者 ID；与响应者保持一致。
	var actor_id: int = int(context.get("actor_id", context.get("responder_id", -1)))
	slash_effect.host.add_log("%s发动【青龙偃月刀】追击。" % slash_effect.state.get_player(actor_id).display_name)
	slash_effect.resolve_external_target(follow_slash, actor_id, int(context.get("target_id", -1)), 1, str(GameDatabase.get_card(follow_slash.definition_id).get("nature", "normal")), bool(context.get("ignore_armor", false)), int(context.get("parent_card_uid", -1)))


## 恢复青龙偃月刀追加【杀】响应。
func continue_slash_response(slash_effect: Object, context: Dictionary, response_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "qinglong_response":
		return false
	_apply_follow_slash(slash_effect, context, response_card)
	return true
