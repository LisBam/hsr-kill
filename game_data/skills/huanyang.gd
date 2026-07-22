extends SkillDefinition

## 【还阳】技能源码。持有者对当前距离1以内的角色造成伤害后固定回复1点体力。

## 每次满足条件固定回复的体力值；多次独立伤害分别触发。
const RECOVER_AMOUNT: int = 1


## 写入锁定技静态信息；技能描述严格保持设计原文。
func _init() -> void:
	super({
		"id": "huanyang",
		"name": "还阳",
		"trigger": "damage",
		"ui_enabled": false,
		"lock": true,
		"description": "锁定技，当你对距离为1以内的角色造成伤害时，你回复1点体力。",
	})


## 订阅持有者造成伤害后的来源尾部时机；技能伤害、卡牌伤害与连环传导使用相同距离判断。
## damageSource 会在濒死救援完整结束后派发，因此目标脱离濒死时仍会稳定触发本技能。
func install() -> void:
	subscribe_timing("damageSource", _on_owner_damage_source, "source")


## 对距离1以内目标造成正数伤害后回复体力；满体力时回复端口安全返回且不伪造发动记录。
func _on_owner_damage_source(event: RuleEvent) -> void:
	# 技能持有者状态；用于校验存活、距离与回复前后的实际体力变化。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or int(event.data.get("amount", 0)) <= 0 or event.target_id < 0:
		return
	if host.card_rules.calculate_distance(owner_player_id, event.target_id) > 1:
		return
	# 回复前体力；公开回复端口没有返回值，因此通过前后状态差确认是否产生实际效果。
	var previous_hp: int = owner.hp
	host.call("recover", owner_player_id, owner_player_id, RECOVER_AMOUNT, get_id())
	if owner.hp > previous_hp:
		announce_activation({"damage_target_id":event.target_id, "recover":RECOVER_AMOUNT})


## 修正伤害牌AI：受伤时按统一1点体力收益优先攻击距离1以内目标，并允许在安全体力下利用属性连环对自己造成可回复伤害。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	if str(action.get("action_type", "")) != "use_card":
		return current_score
	# 当前牌定义；只有实际伤害牌能触发还阳。
	var definition: Dictionary = GameDatabase.get_card(str(action.get("card_definition_id", "")))
	# 当前牌AI标签；damage与nature_damage分别描述伤害和属性伤害语义。
	var ai_profile: Dictionary = definition.get("ai", {}) as Dictionary
	if not bool(ai_profile.get("damage", false)):
		return current_score
	# 持有者快照；满体力时没有回复收益，但仍保留通用伤害牌评分。
	var owner: Dictionary = _snapshot_player(authoritative_snapshot, owner_player_id)
	# 已损失体力；最低为0，只有正数时还阳回复才具有额外价值。
	var missing_hp: int = maxi(int(owner.get("max_hp", 0)) - int(owner.get("hp", 0)), 0)
	if missing_hp <= 0:
		return current_score
	# 修正后动作评分；从通用卡牌收益起累加距离与自伤联动价值。
	var result: float = current_score
	for target_variant: Variant in action.get("target_ids", []) as Array:
		# 当前伤害目标稳定ID；用于距离与自身目标判断。
		var target_id: int = int(target_variant)
		if evaluator.get_distance(authoritative_snapshot, owner_player_id, target_id) <= 1:
			result += evaluator.score_resource_change(authoritative_snapshot, owner_player_id, owner_player_id, 0, RECOVER_AMOUNT)
		# 1点体力时禁止AI用伤害牌攻击自己，避免在还阳触发前先进入无法救援的濒死流程。
		if target_id == owner_player_id:
			if int(owner.get("hp", 0)) <= 1:
				result -= 20.0
			elif bool(owner.get("chained", false)) and bool(ai_profile.get("nature_damage", false)):
				result += 3.5
	return result


## 从权威快照读取指定玩家；不存在时返回空字典。
func _snapshot_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前遍历玩家快照；匹配稳定ID后返回。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}
