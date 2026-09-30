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
		"description": "所有角色依次回复1点体力。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":10.0, "value":0.0, "target_result":2.0, "recover":true, "multitarget":true, "beneficial":true},
		"ai_use_value": 4.0,
		"ai_beneficial": true,
	})


## 执行【桃园结义】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
## 目标为全部存活角色：满体力角色同样是本牌目标（照常进入目标时机与表现），但它不会产生任何体力变化，
## 因此也不为它创建【无懈可击】询问链——无懈只服务于“确实会改变结果”的回复，满血目标被询问无懈没有规则意义。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.is_resolution_stopped():
			break
		# 当前目标是否仍需回复；满体力、已死亡与已离场角色都不进入无懈链与回复流程。
		if not _needs_recovery(resolver, target_id):
			continue
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.recover(actor_id, target_id, 1, card.definition_id)
	return resolver.default_destination()


## 判断一个已进入本牌目标的角色是否仍需回复；满体力角色虽然仍是合法目标，但不产生任何结算。
## 该判定只影响无懈链与回复本身，不参与目标合法性筛选，因此满血角色仍会保留在目标数组与目标时机中。
func _needs_recovery(resolver: Object, target_id: int) -> bool:
	# 当前目标权威状态；死亡或离场角色不创建无懈窗口，避免对已经无效的目标产生问询。
	var target: PlayerState = resolver.state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game:
		return false
	return target.hp < target.max_hp


## 当场上没有任何受伤角色时压低主动使用评分；避免AI消耗无实际效果的群体回复牌。
func modify_ai_action_score(authoritative_snapshot: Dictionary, _action: Dictionary, current_score: float, _evaluator: Object) -> float:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；死亡或离场角色不属于本牌可结算的有效回复目标。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)) and int(player.get("hp", 0)) < int(player.get("max_hp", 0)):
			return current_score
	return current_score - AI_NO_WOUNDED_TARGET_PENALTY
