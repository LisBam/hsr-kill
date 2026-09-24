extends SkillDefinition

## 【轮回】技能源码。任意角色回合结束后检查12枚火种，强制完成区域废除、友方离场、翻面、特殊换形态与额外回合。

## “火种”公开标记稳定ID；达到觉醒阈值后移除全部数量。
const FIRE_SEED_MARK_ID: String = "huozhong"

## 觉醒所需最少“火种”数量；数值12来自技能原文。
const AWAKEN_FIRE_SEED_THRESHOLD: int = 12

## 觉醒后替换的特殊武将稳定ID；该定义不会进入普通选将与随机抽取池。
const TRANSFORM_CHARACTER_ID: String = "kaesilanna"

## 跨形态保存离场友方ID的私有状态键；永劫回到白厄时只恢复本次轮回实际移出的角色。
const REMOVED_ALLY_IDS_STATE_KEY: String = "baie_removed_ally_ids"


## 写入觉醒技静态信息；技能描述逐字保持需求提供的原文，基类自动赋予锁定与限定语义。
func _init() -> void:
	super({
		"id":"lunhui",
		"name":"轮回",
		"trigger":"phaseAfter",
		"ui_enabled":false,
		"awakening":true,
		"description":"觉醒技，一名角色回合结束时，若拥有的“火种”不少于12，你移除所有“火种”，废除装备区与判定区，令所有友方角色离场，将所有其他角色的武将牌翻面，将你的武将牌替换为“卡厄斯兰那”，将体力值回复至体力上限，然后进行一个额外回合。",
	})


## 订阅全场完整回合结束时机；觉醒技满足条件后不可取消且全局仅发动一次。
func install() -> void:
	subscribe_timing("phaseAfter", _on_any_turn_after, "global")


## 执行觉醒完整状态转换；顺序严格遵循技能原文，友方列表在换形态前写入角色私有状态。
func _on_any_turn_after(event: RuleEvent) -> void:
	# 白厄状态；必须仍存活在场、拥有觉醒额度并达到12枚火种。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 当前火种数量；大于阈值时同样移除全部而非只移除12枚。
	var fire_seed_count: int = _get_fire_seed_count()
	if owner == null or not owner.alive or owner.out_of_game or not has_available_intrinsic_use() or fire_seed_count < AWAKEN_FIRE_SEED_THRESHOLD:
		return
	# 本次实际离场的其他友方；自身必须留场以继续完成换形态和额外回合。
	var removed_ally_ids: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.player_id != owner_player_id and player.alive and not player.out_of_game and bool(host.call("is_friendly", owner_player_id, player.player_id)):
			removed_ally_ids.append(player.player_id)
	announce_activation({"turn_player_id":event.player_id if event != null else -1, "removed_fire_seed_count":fire_seed_count, "removed_ally_ids":removed_ally_ids.duplicate(), "new_character_id":TRANSFORM_CHARACTER_ID})
	host.call("change_player_mark_count", owner_player_id, FIRE_SEED_MARK_ID, -fire_seed_count)
	host.call("set_player_zones_abolished", owner_player_id, true, true, get_id())
	owner.character_form_state[REMOVED_ALLY_IDS_STATE_KEY] = removed_ally_ids.duplicate()
	for ally_id: int in removed_ally_ids:
		host.call("remove_player_from_game", ally_id, get_id(), false)
	# 其他仍在场角色；已离场友方不再属于“所有其他角色”的翻面集合。
	for other_player: PlayerState in host.state.players:
		if other_player.player_id != owner_player_id and other_player.alive and not other_player.out_of_game:
			host.call("turn_over_player", other_player.player_id, owner_player_id, get_id())
	if not bool(host.call("replace_player_character_card", owner_player_id, TRANSFORM_CHARACTER_ID, get_id(), true)):
		return
	# 换形态后的同一角色状态；基础上限已经切换为卡厄斯兰那并保留局内独立修正。
	var transformed_owner: PlayerState = host.state.get_player(owner_player_id) as PlayerState
	if transformed_owner != null and transformed_owner.hp < transformed_owner.max_hp:
		host.call("recover", owner_player_id, owner_player_id, transformed_owner.max_hp - transformed_owner.hp, get_id())
	host.call("add_phase", owner_player_id, get_id())


## 返回当前“火种”数量；标记不存在时按0处理。
func _get_fire_seed_count() -> int:
	return maxi(int((host.call("get_player_mark", owner_player_id, FIRE_SEED_MARK_ID) as Dictionary).get("count", 0)), 0)
