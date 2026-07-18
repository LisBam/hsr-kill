class_name IdentityRules
extends RefCounted

## 标准身份局规则服务。身份分配、胜负判定与死亡奖惩集中于此，不依赖界面或控制器实现。

## 2至10人标准身份配置；数组索引等于人数，空项表示不支持的人数。
const DISTRIBUTIONS: Dictionary = {
	2: ["leader", "rebel"],
	3: ["leader", "renegade", "rebel"],
	4: ["leader", "loyalist", "renegade", "rebel"],
	5: ["leader", "loyalist", "renegade", "rebel", "rebel"],
	6: ["leader", "loyalist", "renegade", "rebel", "rebel", "rebel"],
	7: ["leader", "loyalist", "loyalist", "renegade", "rebel", "rebel", "rebel"],
	8: ["leader", "loyalist", "loyalist", "renegade", "rebel", "rebel", "rebel", "rebel"],
	9: ["leader", "loyalist", "loyalist", "loyalist", "renegade", "rebel", "rebel", "rebel", "rebel"],
	10: ["leader", "loyalist", "loyalist", "loyalist", "renegade", "renegade", "rebel", "rebel", "rebel", "rebel"],
}


## 返回指定人数的身份数组副本；人数不在2至10范围时返回空数组。
func get_distribution(player_count: int) -> Array[String]:
	# 原始身份配置；复制后可安全洗牌而不修改常量。
	var raw: Array = DISTRIBUTIONS.get(player_count, []) as Array
	# 强类型身份结果；逐项转换保证调用方获得字符串数组。
	var result: Array[String] = []
	for identity_variant: Variant in raw:
		result.append(str(identity_variant))
	return result


## 检查当前存活身份并返回获胜方；空字符串表示对局继续。
func evaluate_winner(state: GameState) -> String:
	# 领袖状态；身份局必须且只能存在一名领袖。
	var leader: PlayerState = _find_identity(state, "leader")
	if leader == null or not leader.alive:
		# 领袖死亡时的存活玩家；若仅剩内奸，则内奸单独获胜。
		var survivors: Array[PlayerState] = state.get_alive_players()
		if survivors.size() == 1 and survivors[0].identity == "renegade":
			return "renegade"
		return "rebels"

	# 存活反贼数量；只要仍有反贼，对局不能判定领忠胜利。
	var rebel_count: int = 0
	# 存活内奸数量；领忠方必须同时消灭全部内奸。
	var renegade_count: int = 0
	for player: PlayerState in state.players:
		if not player.alive:
			continue
		if player.identity == "rebel":
			rebel_count += 1
		elif player.identity == "renegade":
			renegade_count += 1
	if rebel_count == 0 and renegade_count == 0:
		return "leader_and_loyalists"
	return ""


## 返回死亡奖惩类型，由控制器执行具体移动：draw_three、leader_penalty 或空字符串。
func get_death_reward(killer: PlayerState, victim: PlayerState) -> String:
	if killer == null or victim == null:
		return ""
	if victim.identity == "rebel":
		return "draw_three"
	if killer.identity == "leader" and victim.identity == "loyalist":
		return "leader_penalty"
	return ""


## 查找指定身份的首名玩家；身份不存在时返回 null。
func _find_identity(state: GameState, identity: String) -> PlayerState:
	for player: PlayerState in state.players:
		if player.identity == identity:
			return player
	return null
