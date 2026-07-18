extends CardDefinition

## 【兵粮寸断】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "bingliang",
		"original_name": "兵粮寸断",
		"custom_name": "补给封锁",
		"type": "trick",
		"subtype": "delayed",
		"effect_id": "skip_draw",
		"nature": "normal",
		"target_mode": "single_other",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "one",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": true,
		"description": "判定结果不为梅花时，跳过摸牌阶段。",
		"resolution_mode": "whole",
		"final_zone": "judgment",
		"provided_response_pattern": "",
		"ai": {"order":1.0, "value":4.0, "target_result":-2.7, "skip_draw":true},
		"ai_target_attitude": "hostile",
	})


## 执行【兵粮寸断】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.is_empty():
		return "discard"
	resolver.host.place_delayed_trick(target_ids[0], card)
	return "judgment"


## 结算【兵粮寸断】判定；未被无懈抵消且结果不为梅花时跳过本回合摸牌阶段。
func resolve_delayed_judgment(match_host: Object, player_id: int, card: CardInstance, negated: bool) -> void:
	if not negated:
		# 【兵粮寸断】判定牌；梅花表示通过，其他三种花色均记录跳过摸牌阶段。
		var judgment_card: CardInstance = match_host.perform_judgment(player_id, "【兵粮寸断】")
		if judgment_card != null and judgment_card.suit != "club":
			match_host.mark_player_phase_skipped(player_id, "draw")
	match_host.discard_delayed_card(card)
