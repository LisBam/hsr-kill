extends CardDefinition

## 【朱雀羽扇】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "zhuque",
		"original_name": "朱雀羽扇",
		"custom_name": "普罗米修斯",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 4,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "你可将普通【杀】按火【杀】使用。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":2.0, "equip_value":2.0},
		"ai_use_value": 4.0,
	})


## 执行【朱雀羽扇】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 使用普通【杀】建立共享上下文后，可选择将整张牌的属性改为火焰。
func on_slash_resolution_started(match_host: Object, card: CardInstance, actor_id: int, resolution_context: Dictionary) -> bool:
	if str(resolution_context.get("slash_nature", "normal")) != "normal":
		return false
	# 当前武器实体；必须仍是本张朱雀羽扇。
	var equipment_card: CardInstance = match_host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.definition_id != get_id():
		return false
	# 发动上下文；父牌 UID 用于返回对应【杀】源码，装备 UID 防止等待期间换装。
	var trigger_context: Dictionary = {
		"kind":"zhuque_trigger",
		"parent_card_uid":card.uid,
		"actor_id":actor_id,
		"equipment_definition_id":get_id(),
		"equipment_uid":equipment_card.uid,
		"ai_prefer_select":true,
	}
	# 是否发动选择；装备牌只作为公开开关，不会被移动或消耗。
	var activated: bool = match_host.request_equipment_trigger(actor_id, get_id(), "朱雀羽扇", "是否发动【朱雀羽扇】将此普通【杀】改为火【杀】？", trigger_context, true)
	if match_host.has_pending_card_choice():
		return true
	if activated:
		_apply_conversion(match_host, trigger_context)
	return false


## 应用属性转换；必须仍装备创建请求时的同一张朱雀羽扇。
func _apply_conversion(match_host: Object, context: Dictionary) -> void:
	# 发动者 ID；用于复核当前武器和记录日志。
	var actor_id: int = int(context.get("actor_id", -1))
	# 当前武器实体；等待期间换装时选择自动失效。
	var equipment_card: CardInstance = match_host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.uid != int(context.get("equipment_uid", -1)):
		return
	if match_host.set_active_card_resolution_value(int(context.get("parent_card_uid", -1)), "slash_nature", "fire"):
		match_host.add_log("%s发动【朱雀羽扇】，将普通【杀】转为火【杀】。" % match_host.state.get_player(actor_id).display_name)


## 恢复朱雀羽扇发动选择；选中装备实体才执行属性转换。
func continue_slash_choice(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	if str(context.get("kind", "")) != "zhuque_trigger":
		return false
	if selected_uids.has(int(context.get("equipment_uid", -1))):
		_apply_conversion(slash_effect.host, context)
	slash_effect.host.continue_card_after_preparation(int(context.get("parent_card_uid", -1)))
	return true
