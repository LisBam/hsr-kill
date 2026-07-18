extends CardDefinition

## 【古锭刀】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "guding",
		"original_name": "古锭刀",
		"custom_name": "虚数古刃",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 2,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "锁定技，你以【杀】对没有手牌的目标造成伤害时，伤害+1。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":2.0, "equip_value":2.0},
		"ai_use_value": 4.0,
	})


## 执行【古锭刀】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 古锭刀使持有者以【杀】伤害无手牌目标时伤害固定增加1点。
func modify_outgoing_damage(match_host: Object, owner: PlayerState, target: PlayerState, context: Dictionary, amount: int) -> int:
	return amount + 1 if str(context.get("card_id", "")) in ["sha", "sha_fire", "sha_thunder"] and target.hand.is_empty() else amount
