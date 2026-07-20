extends CardDefinition

## 【桃园结义】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。

## AI在场上没有受伤角色时使用【桃园结义】的固定降权；4分足以抵消纯出牌顺序，不影响存在有效回复目标时的正常评估。
const AI_NO_WOUNDED_TARGET_PENALTY: float = 4.0


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "taoyuan",
		"original_name": "桃园结义",
		"custom_name": "丰饶馈赠",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "heal_all",
		"nature": "normal",
		"target_mode": "all_players",
		"min_targets": 0,
		"max_targets": 99,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "所有已受伤角色依次回复1点体力。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":10.0, "value":0.0, "target_result":2.0, "recover":true, "multitarget":true, "beneficial":true},
		"ai_use_value": 4.0,
		"ai_beneficial": true,
	})


## 执行【桃园结义】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.recover(actor_id, target_id, 1, card.definition_id)
	return resolver.default_destination()


## 过滤满体力角色的实际结算目标；满体力目标不会回复，也不再创建无懈链和逐目标事件，从而降低多人局结算卡顿。
func validate_target_selection(_rule_service: Object, _actor: PlayerState, target_id: int, _all_target_ids: Array[int]) -> String:
	# 当前目标；全体目标规范化阶段会逐名调用本接口，缺失对象由通用规则继续处理。
	var target: PlayerState = _rule_service.state.get_player(target_id) if _rule_service != null else null
	if target != null and target.hp >= target.max_hp:
		return "目标未受伤。"
	return ""


## 当场上没有任何受伤角色时压低主动使用评分；避免AI消耗无实际效果的群体回复牌。
func modify_ai_action_score(authoritative_snapshot: Dictionary, _action: Dictionary, current_score: float, _evaluator: Object) -> float:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；死亡或离场角色不属于本牌可结算的有效回复目标。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)) and int(player.get("hp", 0)) < int(player.get("max_hp", 0)):
			return current_score
	return current_score - AI_NO_WOUNDED_TARGET_PENALTY
