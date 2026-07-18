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
		"ai": {"order":1.0, "value":0.0, "target_result":-1.0, "damage":true, "thunder_damage":true, "nature_damage":true},
	})


## 执行【闪电】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.is_empty():
		return "discard"
	resolver.host.place_delayed_trick(target_ids[0], card)
	return "judgment"


## 依据身份局势修正【闪电】的使用价值；优势方通常不愿引入随机伤害，劣势方与内奸更愿意制造变量。
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 使用者 ID；闪电只能置入自己的判定区。
	var actor_id: int = int(action.get("actor_id", -1))
	# 使用者状态；身份决定局势方向偏好。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, actor_id)
	if actor.is_empty():
		return current_score
	# 主忠方局势；正值主忠优势，负值反贼优势。
	var situation: int = evaluator.get_situation(authoritative_snapshot)
	# 使用者身份；内奸始终偏好适度随机性，其他阵营仅在自身阵营明显劣势时使用。
	var identity: String = str(actor.get("identity", ""))
	if identity == "renegade":
		return 1.0
	if identity == "rebel":
		return 1.0 if situation > 1 else -1.0
	if identity in ["lord", "loyalist"]:
		return 1.0 if situation < -1 else -1.0
	return current_score


## 结算【闪电】判定；黑桃2至9造成3点无来源雷电伤害，否则向下一名无闪电角色传递。
func resolve_delayed_judgment(match_host: Object, player_id: int, card: CardInstance, negated: bool) -> void:
	if negated:
		match_host.pass_delayed_card(player_id, card)
		return
	# 【闪电】判定牌；只有黑桃2至9命中，其他结果均执行传递。
	var judgment_card: CardInstance = match_host.perform_judgment(player_id, "【闪电】")
	if judgment_card != null and judgment_card.suit == "spade" and judgment_card.rank >= 2 and judgment_card.rank <= 9:
		match_host.discard_delayed_card(card)
		match_host.damage(-1, player_id, 3, "thunder", "shandian")
	else:
		match_host.pass_delayed_card(player_id, card)
