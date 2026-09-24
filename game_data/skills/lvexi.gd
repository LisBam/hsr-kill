extends SkillDefinition

## 【掠袭】技能源码。围绕来源属于自己的【猎物】标记提供固定距离、不可响应、受伤追击与死亡收益。

## 猎物标记稳定ID；必须与【幽锋】保持一致，修改任一处都会切断技能联动。
const HUNT_MARK_ID: String = "liewu"

## 猎物受伤后追加的普通伤害值；固定为1，与技能原文一致。
const FOLLOW_UP_DAMAGE: int = 1

## 猎物死亡后摸牌数；固定为2，与技能原文一致。
const DEATH_DRAW_COUNT: int = 2

## AI对猎物目标不可响应价值的基础加分；只调整用牌优先级，不改变规则效果。
const AI_DIRECT_HIT_VALUE: float = 2.5


## 写入离场锁定技静态信息；技能描述严格保持需求钦定原文。
func _init() -> void:
	super({
		"id":"lvexi",
		"name":"掠袭",
		"trigger":"damageAfter",
		"ui_enabled":false,
		"lock":true,
		"out_of_game_skill":true,
		"description":"离场技，锁定技，你计算与拥有“猎物”标记的角色距离为1，且其不可响应你使用的牌。当拥有“猎物”标记的角色受到伤害后，若你处于离场状态，你返场并对其造成1点伤害。当拥有“猎物”标记的角色死亡时，你摸两张牌并返场。",
	})


## 订阅用牌指定、伤害后与死亡后时机；离场技元数据保证貊泽离场期间仍执行后两项效果。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_card_targeted, "source")
	subscribe_timing("damageAfter", _on_hunt_target_damaged, "global")
	subscribe_timing("dieAfter", _on_hunt_target_died, "global")


## 对来源属于自己的猎物固定计算距离为1；其他目标保持通用座次与坐骑结果。
func modify_distance_to_target(target_id: int, current_distance: int) -> int:
	return 1 if _is_hunt_target(target_id) else current_distance


## 持有者使用牌指定猎物时把该目标加入本牌直击集合，使其跳过【闪】或锦囊响应窗口。
func _on_card_targeted(event: RuleEvent) -> void:
	# 最终目标ID；逐目标时机优先读取data中的稳定字段。
	var target_id: int = int(event.data.get("target_id", event.target_id))
	if not _is_hunt_target(target_id):
		return
	# 当前逻辑牌UID；只有仍在使用生命周期中的牌才能写入直击目标。
	var card_uid: int = int(event.data.get("card_uid", -1))
	if card_uid < 0 or not bool(host.call("add_card_direct_hit_target", card_uid, target_id, get_id())):
		return
	announce_activation({"card_uid":card_uid, "target_id":target_id, "direct_hit":true})


## 猎物受到正数伤害后，离场中的貊泽先返场，再对仍存活在场的猎物造成1点普通伤害。
func _on_hunt_target_damaged(event: RuleEvent) -> void:
	if int(event.data.get("amount", 0)) <= 0 or not _is_hunt_target(event.target_id):
		return
	# 貊泽状态；只有存活且确实离场时触发返场追击。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	if owner == null or not owner.alive or not owner.out_of_game:
		return
	# 猎物状态；濒死流程已经在damageAfter之前完成，死亡或另行离场时不再追加伤害。
	var target: PlayerState = host.state.get_player(event.target_id)
	if target == null or not target.alive or target.out_of_game:
		return
	if not bool(host.call("restore_player_to_game", owner_player_id, get_id())):
		return
	announce_activation({"target_id":event.target_id, "follow_up_damage":FOLLOW_UP_DAMAGE})
	get_owner_skill_player().damage(FOLLOW_UP_DAMAGE, get_skill_player(event.target_id))


## 猎物死亡后先按离场技规则摸两张牌，再返场并清除已经失去宿主的猎物标记。
func _on_hunt_target_died(event: RuleEvent) -> void:
	# 死亡角色ID；dieAfter的player与target都指向死者，优先读取target保持角色语义一致。
	var target_id: int = event.target_id
	if not _is_hunt_target(target_id):
		return
	# 貊泽状态；技能持有者死亡时基类不会允许本回调执行。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	if owner == null or not owner.alive:
		return
	announce_activation({"target_id":target_id, "draw_count":DEATH_DRAW_COUNT})
	# 离场技摸牌显式允许离场持有者获得牌；普通摸牌入口仍继续拒绝其他离场角色。
	host.call("draw", owner_player_id, DEATH_DRAW_COUNT, true, true)
	host.call("restore_player_to_game", owner_player_id, get_id())
	host.call("remove_player_mark", target_id, HUNT_MARK_ID)


## 判断目标是否持有来源属于当前貊泽的有效猎物标记；同名武将不会共享后续触发归属。
func _is_hunt_target(target_id: int) -> bool:
	if host == null or target_id < 0:
		return false
	# 目标标记快照；数量为1且来源匹配时才属于本技能。
	var mark_data: Dictionary = host.call("get_player_mark", target_id, HUNT_MARK_ID) as Dictionary
	return int(mark_data.get("count", 0)) > 0 and int(mark_data.get("source_player_id", -1)) == owner_player_id


## AI提高对猎物使用伤害牌与控制牌的优先级，并按阵营态度避免把直击收益浪费在友方目标上。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 动作目标；没有猎物目标时保持其他卡牌与技能的既有评分。
	var target_ids: Array = action.get("target_ids", []) as Array
	# 最终附加分；多目标牌只对实际包含的猎物计算一次。
	var result: float = current_score
	for target_variant: Variant in target_ids:
		# 当前目标ID；快照中的公开标记用于确认其是否属于本技能来源。
		var target_id: int = int(target_variant)
		# 目标公开标记；AI只读取所有玩家均可见的标记信息。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		var mark_data: Dictionary = (target.get("public_marks", {}) as Dictionary).get(HUNT_MARK_ID, {}) as Dictionary
		if int(mark_data.get("count", 0)) <= 0 or int(mark_data.get("source_player_id", -1)) != owner_player_id:
			continue
		# 对猎物的态度；敌方负态度转化为正向集火收益，友方则降低误伤优先级。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		result += AI_DIRECT_HIT_VALUE - attitude * 0.45
		break
	return result
