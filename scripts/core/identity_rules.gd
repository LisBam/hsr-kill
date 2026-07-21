class_name IdentityRules
extends RefCounted

## 身份与模式规则服务。身份分配、胜负判定、死亡奖惩与队友关系集中于此，不依赖界面或控制器实现。

## 标准身份局模式稳定 ID；主菜单与对局状态均使用该字符串标识。
const MODE_IDENTITY: String = "identity"

## 斗地主模式稳定 ID；仅支持三人与五人局，使用地主与农民身份。
const MODE_DOUDIZHU: String = "doudizhu"

## 2v2 模式稳定 ID；固定四人，两名蓝方与两名红方，座次一号位与四号位同队、二号位与三号位同队。
const MODE_TEAM2V2: String = "team2v2"

## 2至10人标准身份配置；数组索引等于人数，空项表示不支持的人数。
const IDENTITY_DISTRIBUTIONS: Dictionary = {
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

## 斗地主人数到身份表；键为总人数，值为开局固定座次顺序的身份数组（1号位起）。
## 三人：一名地主与两名农民；五人：两名地主与三名农民，地主固定一号位与三号位。
const DOUDIZHU_DISTRIBUTIONS: Dictionary = {
	3: ["landlord", "peasant", "peasant"],
	5: ["landlord", "peasant", "landlord", "peasant", "peasant"],
}

## 2v2 基准身份表；一号位与四号位同队、二号位与三号位同队。开局时按 50% 概率整表互换蓝红。
const TEAM2V2_DISTRIBUTION_BASE: Array[String] = ["blue", "red", "red", "blue"]

## 兼容旧常量名；外部若仍引用 DISTRIBUTIONS 时指向标准身份表。
const DISTRIBUTIONS: Dictionary = IDENTITY_DISTRIBUTIONS


## 规范化模式 ID；未知或空值回退到标准身份局。
func normalize_mode(mode_id: String) -> String:
	if mode_id == MODE_DOUDIZHU:
		return MODE_DOUDIZHU
	if mode_id == MODE_TEAM2V2:
		return MODE_TEAM2V2
	return MODE_IDENTITY


## 返回指定模式支持的人数列表；顺序为升序，供菜单与校验复用。
func get_supported_player_counts(mode_id: String) -> Array[int]:
	# 规范化模式；避免调用方拼写差异导致空支持列表。
	var mode: String = normalize_mode(mode_id)
	# 升序人数结果；调用方可安全修改返回数组。
	var result: Array[int] = []
	if mode == MODE_DOUDIZHU:
		result.append(3)
		result.append(5)
		return result
	if mode == MODE_TEAM2V2:
		result.append(4)
		return result
	for player_count: int in range(2, 11):
		if IDENTITY_DISTRIBUTIONS.has(player_count):
			result.append(player_count)
	return result


## 检查人数是否被指定模式支持。
func supports_player_count(mode_id: String, player_count: int) -> bool:
	return get_supported_player_counts(mode_id).has(player_count)


## 返回指定人数与模式的身份数组副本；人数不支持时返回空数组。
## 斗地主返回已按一号位（及五人三号位）排好的固定身份表，调用方只需整表洗牌玩家或直接按座次应用。
func get_distribution(player_count: int, mode_id: String = MODE_IDENTITY) -> Array[String]:
	# 规范化模式；缺省为标准身份局以保持旧调用兼容。
	var mode: String = normalize_mode(mode_id)
	# 原始身份配置；复制后可安全洗牌或按座次应用而不修改常量。
	var raw: Array = []
	if mode == MODE_DOUDIZHU:
		raw = DOUDIZHU_DISTRIBUTIONS.get(player_count, []) as Array
	elif mode == MODE_TEAM2V2:
		raw = TEAM2V2_DISTRIBUTION_BASE.duplicate() if player_count == 4 else []
	else:
		raw = IDENTITY_DISTRIBUTIONS.get(player_count, []) as Array
	# 强类型身份结果；逐项转换保证调用方获得字符串数组。
	var result: Array[String] = []
	for identity_variant: Variant in raw:
		result.append(str(identity_variant))
	return result


## 返回模式开局首回合与首任公开选将角色的身份 ID；身份局为 leader，斗地主为 landlord。
## 2v2 以一号位固定开局，不绑定单一身份；调用方应优先按座次 1 取首回合角色。
func get_first_player_identity(mode_id: String) -> String:
	if normalize_mode(mode_id) == MODE_DOUDIZHU:
		return "landlord"
	if normalize_mode(mode_id) == MODE_TEAM2V2:
		return ""
	return "leader"


## 返回模式是否固定按一号位开始首回合；2v2 固定 true，其他模式 false（由首任身份决定）。
func starts_from_first_seat(mode_id: String) -> bool:
	return normalize_mode(mode_id) == MODE_TEAM2V2


## 返回 2v2 是否应对基准身份表进行蓝红互换；coin_flip 为 true 时一号/四号变为红方，二号/三号变为蓝方。
func get_team2v2_distribution(swap_colors: bool) -> Array[String]:
	# 结果身份表；始终复制基准再按需互换，避免修改常量数组。
	var result: Array[String] = []
	for identity_value: String in TEAM2V2_DISTRIBUTION_BASE:
		if swap_colors:
			result.append("red" if identity_value == "blue" else "blue")
		else:
			result.append(identity_value)
	return result


## 返回身份是否在开局时公开；标准身份局仅领袖公开，斗地主与 2v2 全部身份明置（阵营对战无需隐藏）。
func is_identity_public_at_start(identity: String, mode_id: String = MODE_IDENTITY) -> bool:
	var mode: String = normalize_mode(mode_id)
	if mode == MODE_DOUDIZHU or mode == MODE_TEAM2V2:
		return not identity.is_empty()
	return identity == "leader"


## 返回模式授予的额外体力上限；斗地主地主固定 +1，身份局领袖仅在不少于 5 人时 +1；2v2 不加体力。
func get_opening_max_hp_bonus(identity: String, player_count: int, mode_id: String = MODE_IDENTITY) -> int:
	var mode: String = normalize_mode(mode_id)
	if mode == MODE_DOUDIZHU:
		return 1 if identity == "landlord" else 0
	if mode == MODE_TEAM2V2:
		return 0
	return 1 if identity == "leader" and player_count >= 5 else 0


## 返回模式在开局额外安装的技能 ID 列表；武将固有技能之外的身份/模式技能从此处统一读取。
func get_mode_skill_ids(identity: String, mode_id: String = MODE_IDENTITY) -> Array[String]:
	# 技能结果；同一身份不会重复写入相同技能 ID。
	var result: Array[String] = []
	if normalize_mode(mode_id) != MODE_DOUDIZHU:
		return result
	if identity == "landlord":
		result.append("feiyang")
		result.append("bahu")
	elif identity == "peasant":
		result.append("gongku")
	return result


## 判断两个身份是否互为队友；队友不包括自己，调用方必须先确认两个不同角色。
## 身份局：主公与忠臣互为队友，反贼与反贼互为队友，内奸没有任何队友（含两个内奸之间）。
## 斗地主：地主与地主互为队友，农民与农民互为队友。
## 2v2：蓝方与蓝方互为队友，红方与红方互为队友。
func are_identities_teammates(from_identity: String, to_identity: String, mode_id: String = MODE_IDENTITY) -> bool:
	if from_identity.is_empty() or to_identity.is_empty():
		return false
	var mode: String = normalize_mode(mode_id)
	if mode == MODE_DOUDIZHU:
		if from_identity == "landlord" and to_identity == "landlord":
			return true
		if from_identity == "peasant" and to_identity == "peasant":
			return true
		return false
	if mode == MODE_TEAM2V2:
		if from_identity == "blue" and to_identity == "blue":
			return true
		if from_identity == "red" and to_identity == "red":
			return true
		return false
	if from_identity in ["leader", "loyalist"] and to_identity in ["leader", "loyalist"]:
		return true
	if from_identity == "rebel" and to_identity == "rebel":
		return true
	# 内奸没有队友；两个内奸之间也不互为队友。
	return false


## 判断两个角色是否为队友；队友永远不包括自己，死亡与离场不改变既定身份队友关系。
func are_teammates(from_player: PlayerState, to_player: PlayerState, mode_id: String = MODE_IDENTITY) -> bool:
	if from_player == null or to_player == null:
		return false
	if from_player.player_id == to_player.player_id:
		return false
	return are_identities_teammates(from_player.identity, to_player.identity, mode_id)


## 判断目标是否为来源的友方角色；友方包括自己，其他友方角色等于队友。
func is_friendly(from_player: PlayerState, to_player: PlayerState, mode_id: String = MODE_IDENTITY) -> bool:
	if from_player == null or to_player == null:
		return false
	if from_player.player_id == to_player.player_id:
		return true
	return are_teammates(from_player, to_player, mode_id)


## 检查当前存活身份并返回获胜方；空字符串表示对局继续。
func evaluate_winner(state: GameState) -> String:
	if state == null:
		return ""
	# 当前模式；缺省 identity 兼容旧存档与未写 mode 的状态。
	var mode: String = normalize_mode(str(state.match_mode))
	if mode == MODE_DOUDIZHU:
		return _evaluate_doudizhu_winner(state)
	if mode == MODE_TEAM2V2:
		return _evaluate_team2v2_winner(state)
	return _evaluate_identity_winner(state)


## 返回死亡奖惩类型，由控制器执行具体移动：draw_three、leader_penalty、teammate_draw 或空字符串。
## 斗地主没有身份局的击杀反贼摸三与主公误杀忠臣惩罚。
## 2v2 击杀任何人（含队友）均无击杀奖惩；队友死亡后由存活队友各摸一张，类型为 teammate_draw。
func get_death_reward(killer: PlayerState, victim: PlayerState, mode_id: String = MODE_IDENTITY) -> String:
	if victim == null:
		return ""
	var mode: String = normalize_mode(mode_id)
	if mode == MODE_DOUDIZHU:
		return ""
	if mode == MODE_TEAM2V2:
		return "teammate_draw"
	if killer == null:
		return ""
	if victim.identity == "rebel":
		return "draw_three"
	if killer.identity == "leader" and victim.identity == "loyalist":
		return "leader_penalty"
	return ""


## 标准身份局胜负：领袖死亡时仅剩内奸则内奸胜，否则反贼胜；全部反贼与内奸出局则领忠胜。
func _evaluate_identity_winner(state: GameState) -> String:
	# 领袖状态；身份局必须且只能存在一名领袖。
	var leader: PlayerState = _find_identity(state, "leader")
	if leader == null or not leader.alive:
		# 领袖死亡时仍存活的玩家；离场不是死亡，胜负统计不能复用排除离场角色的行动集合。
		var survivors: Array[PlayerState] = []
		# 当前玩家；只按死亡标记筛选，离场状态不会把存活者移出胜负集合。
		for player: PlayerState in state.players:
			if player.alive:
				survivors.append(player)
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


## 斗地主胜负：任一地主死亡则农民获胜；全部农民死亡则地主获胜。
func _evaluate_doudizhu_winner(state: GameState) -> String:
	# 存活地主数量；任一地主死亡即农民达成胜利条件。
	var landlord_alive: int = 0
	# 存活农民数量；全部出局后地主方获胜。
	var peasant_alive: int = 0
	# 是否已有地主死亡；五人双地主时只需击杀一名地主。
	var landlord_dead: bool = false
	for player: PlayerState in state.players:
		if player.identity == "landlord":
			if player.alive:
				landlord_alive += 1
			else:
				landlord_dead = true
		elif player.identity == "peasant":
			if player.alive:
				peasant_alive += 1
	if landlord_dead:
		return "peasants"
	if peasant_alive == 0 and landlord_alive > 0:
		return "landlords"
	return ""


## 2v2 胜负：任一阵营全部出局则另一阵营获胜；双方均仍有存活角色时对局继续。
func _evaluate_team2v2_winner(state: GameState) -> String:
	# 存活蓝方数量。
	var blue_alive: int = 0
	# 存活红方数量。
	var red_alive: int = 0
	for player: PlayerState in state.players:
		# 离场角色仍然存活；这里只排除已经确认死亡的角色，不能复用在场行动条件。
		if not player.alive:
			continue
		if player.identity == "blue":
			blue_alive += 1
		elif player.identity == "red":
			red_alive += 1
	if blue_alive == 0 and red_alive > 0:
		return "red_team"
	if red_alive == 0 and blue_alive > 0:
		return "blue_team"
	return ""


## 查找指定身份的首名玩家；身份不存在时返回 null。
func _find_identity(state: GameState, identity: String) -> PlayerState:
	for player: PlayerState in state.players:
		if player.identity == identity:
			return player
	return null
