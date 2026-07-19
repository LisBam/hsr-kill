extends CardDefinition

## 【藤甲】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tengjia",
		"original_name": "藤甲",
		"custom_name": "建木藤甲",
		"type": "equipment",
		"subtype": "armor",
		"effect_id": "equip",
		"slot": "armor",
		"attack_range": 0,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "锁定技，普通【杀】、【南蛮入侵】和【万箭齐发】对你无效；受到火焰伤害时伤害+1。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":3.0, "equip_value":3.0},
		"ai_use_value": 4.0,
	})


## 执行【藤甲】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 藤甲令普通属性【杀】无效，火【杀】与雷【杀】仍进入伤害流程。
func blocks_slash(card: CardInstance, nature: String) -> bool:
	return nature == "normal"


## 按只读伤害属性预判【杀】是否被藤甲拦截；藤甲不依赖实体牌颜色，供AI在无CardInstance时复用。
func blocks_slash_by_color(_card_color: String, nature: String) -> bool:
	return nature == "normal"


## 藤甲令【南蛮入侵】与【万箭齐发】对持有者无效。
func blocks_aoe(card_definition_id: String) -> bool:
	return card_definition_id in ["nanman", "wanjian"]


## 藤甲令火焰伤害的AI预期值按2倍估算；常规1点火焰伤害实际会增加为2点。
func get_ai_incoming_damage_multiplier(nature: String) -> float:
	return 2.0 if nature == "fire" else 1.0


## 藤甲使持有者受到的火焰伤害固定增加1点。
func modify_incoming_damage(match_host: Object, owner: PlayerState, context: Dictionary, amount: int) -> int:
	return amount + 1 if str(context.get("nature", "normal")) == "fire" else amount
