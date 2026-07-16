extends CardDefinition

## 【木牛流马】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "muniu",
		"original_name": "木牛流马",
		"custom_name": "自动物流机巧",
		"type": "equipment",
		"subtype": "treasure",
		"effect_id": "equip",
		"slot": "treasure",
		"attack_range": 0,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段限一次，可将一张手牌扣置为“粮”；可使用或打出“粮”，并可将此装备移动给其他角色。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
	})


## 执行【木牛流马】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 木牛流马离开装备区时将其全部“粮”置入弃牌堆，并清空附属存储区。
func on_leave_equipment(match_host: Object, owner: PlayerState, trigger_loss_effects: bool) -> void:
	for stored_card: CardInstance in owner.wooden_ox_storage:
		match_host.discard_card_instance(stored_card)
	owner.wooden_ox_storage.clear()
