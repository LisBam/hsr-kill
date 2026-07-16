extends CardDefinition

## 【闪电】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "shandian",
		"original_name": "闪电",
		"custom_name": "雷暴奇点",
		"type": "trick",
		"subtype": "delayed",
		"effect_id": "lightning",
		"nature": "thunder",
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": true,
		"description": "判定结果为黑桃2至9时受到3点无来源雷电伤害，否则移动到下一名合法角色的判定区。",
		"resolution_mode": "whole",
		"final_zone": "judgment",
		"provided_response_pattern": "",
	})


## 执行【闪电】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.is_empty():
		return "discard"
	resolver.host.place_delayed_trick(target_ids[0], card)
	return "judgment"


## 结算【闪电】判定；黑桃2至9造成3点无来源雷电伤害，否则向下一名无闪电角色传递。
func resolve_delayed_judgment(match_host: Object, player_id: int, card: CardInstance, negated: bool) -> void:
	if negated:
		match_host.pass_lightning_card(player_id, card)
		return
	# 【闪电】判定牌；只有黑桃2至9命中，其他结果均执行传递。
	var judgment_card: CardInstance = match_host.perform_judgment(player_id, "【闪电】")
	if judgment_card != null and judgment_card.suit == "spade" and judgment_card.rank >= 2 and judgment_card.rank <= 9:
		match_host.discard_delayed_card(card)
		match_host.damage(-1, player_id, 3, "thunder", "shandian")
	else:
		match_host.pass_lightning_card(player_id, card)
