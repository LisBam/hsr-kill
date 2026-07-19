extends CardDefinition

## 【白银狮子】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "baiyin",
		"original_name": "白银狮子",
		"custom_name": "光能盾牌",
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
		"description": "锁定技，受到大于1点的伤害时改为1点；失去此防具后回复1点体力。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":9.5, "value":5.0, "equip_value":5.0, "recover":true},
		"ai_use_value": 5.0,
	})


## 执行【白银狮子】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 白银狮子将一次大于1点的伤害固定压缩为1点。
func modify_incoming_damage(match_host: Object, owner: PlayerState, context: Dictionary, amount: int) -> int:
	return 1 if amount > 1 else amount


## 白银狮子离开装备区后，若持有者已受伤且仍存活则回复1点体力。
func on_leave_equipment(match_host: Object, owner: PlayerState, trigger_loss_effects: bool) -> void:
	if trigger_loss_effects and owner.alive and owner.hp < owner.max_hp:
		match_host.recover(owner.player_id, owner.player_id, 1, "baiyin")
