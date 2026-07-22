class_name ConquestModeService
extends RefCounted

## 过关斩将规则服务。该服务集中记录关卡授予的机缘、由机缘汇总入场效果并抽取技能机缘，不持有界面节点或阶段调度逻辑。

## 过关斩将的首关数值；玩家面对的第一名敌方武将始终处于第1关且不获得层数增强。
const INITIAL_LEVEL: int = 1

## 固定层数中获得随机技能机缘的关卡；每关只新增一项，已经获得的技能机缘不会再次进入候选。
const SKILL_REWARD_LEVELS: Array[int] = [5, 10, 15]

## 进入无限关卡机缘规则的首个关卡；第16关及之后每关固定获得三项机缘。
const REPEATING_BONUS_START_LEVEL: int = 16

## 敌方重新入场时的基础摸牌数；灰色初始手牌机缘会在此基础上继续叠加。
const REPLACEMENT_DRAW_COUNT: int = 4

## 第14关灰色装备机缘使用的不同装备子类别数量；卡牌目录的count与该常量保持一致，便于装备流程限制最大数量。
const LEVEL_FOURTEEN_EQUIPMENT_SUBTYPE_COUNT: int = 4

## 每个固定关卡授予的非技能机缘稳定ID；同一ID允许在不同关卡重复获得，并在右键机缘历史中按顺序显示。
const FIXED_LEVEL_OPPORTUNITY_IDS: Dictionary = {
	2:["blue_max_hp_one"],
	3:["purple_draw_phase_one"],
	4:["blue_hand_limit_two"],
	6:["blue_max_hp_one"],
	7:["purple_draw_phase_one"],
	8:["gray_initial_hand_four"],
	9:["green_slash_play_limit_one"],
	11:["purple_max_hp_two"],
	12:["purple_draw_phase_one"],
	13:["orange_damage_one"],
	14:["gray_equip_distinct_four"],
}

## 第16关及之后每层固定授予的三项机缘；灰色初始手牌、蓝色体力上限与紫色摸牌阶段加成均可无限累计。
const REPEATING_LEVEL_OPPORTUNITY_IDS: Array[String] = ["gray_initial_hand_one", "blue_max_hp_one", "purple_draw_phase_one"]

## 当前权威对局状态；关卡快照写入其 conquest_state，供 UI、网络与回放统一读取。
var _state: GameState

## 当前对局共享随机源；随机武将、随机技能和随机装备均使用同一随机序列以支持固定种子复现。
var _rng: RandomNumberGenerator


## 为一局过关斩将绑定玩家和敌方稳定 ID，并初始化第1关公开快照。
func configure(state: GameState, rng: RandomNumberGenerator, player_id: int, enemy_id: int) -> void:
	_state = state
	_rng = rng
	if _state == null:
		return
	_state.conquest_state = {
		"level": INITIAL_LEVEL,
		"player_id": player_id,
		"enemy_player_id": enemy_id,
		"enemy_opportunity_ids": [],
		"awarded_fixed_opportunity_levels": [],
		"awarded_skill_opportunity_levels": [],
	}


## 清理服务持有的跨对局引用；重新开局后旧服务不得继续访问上一局状态或随机源。
func reset() -> void:
	_state = null
	_rng = null


## 返回当前关卡数；无状态或异常值时回退第1关，保证 UI 不显示无效层数。
func get_level() -> int:
	if _state == null:
		return INITIAL_LEVEL
	return maxi(int(_state.conquest_state.get("level", INITIAL_LEVEL)), INITIAL_LEVEL)


## 返回本局玩家稳定 ID；缺失状态返回-1，调用方应拒绝建立机缘或回合恢复。
func get_player_id() -> int:
	return int(_state.conquest_state.get("player_id", -1)) if _state != null else -1


## 返回本局敌方稳定 ID；缺失状态返回-1，调用方应拒绝应用敌方层数增益。
func get_enemy_id() -> int:
	return int(_state.conquest_state.get("enemy_player_id", -1)) if _state != null else -1


## 判断指定角色是否是本模式中会无限重生并叠加关卡增强的敌方角色。
func is_enemy(player_id: int) -> bool:
	return player_id >= 0 and player_id == get_enemy_id()


## 在玩家击败敌方后提升一关；返回提升后的关卡数，供换将日志和敌方入场结算使用。
func advance_level() -> int:
	if _state == null:
		return INITIAL_LEVEL
	var next_level: int = get_level() + 1
	_state.conquest_state["level"] = next_level
	return next_level


## 为当前及此前尚未记录的关卡追加固定机缘；支持测试、回放恢复直接跳至高关卡时补全历史。
func award_fixed_opportunities_through_current_level() -> Array[String]:
	# 本次新增机缘记录；允许相同稳定ID在不同关卡重复出现，右键历史必须保留该重复次数。
	var result: Array[String] = []
	if _state == null:
		return result
	# 已处理固定奖励的关卡；字符串化快照恢复后逐项转换为整数，避免重复追加同一层机缘。
	var awarded_levels: Array[int] = _get_recorded_levels("awarded_fixed_opportunity_levels")
	# 当前累计机缘；新增记录先写入该数组，后续体力与手牌上限查询立刻从同一来源读取。
	var opportunity_ids: Array[String] = get_enemy_opportunity_ids()
	for level: int in range(INITIAL_LEVEL + 1, get_level() + 1):
		if awarded_levels.has(level):
			continue
		# 本关固定机缘；普通固定层可能没有条目，16关及以后由独立三项机缘规则提供。
		var level_opportunity_ids: Array[String] = _get_fixed_opportunity_ids_for_level(level)
		if level_opportunity_ids.is_empty():
			continue
		for opportunity_id: String in level_opportunity_ids:
			if OpportunityCatalog.get_card(opportunity_id).is_empty():
				continue
			opportunity_ids.append(opportunity_id)
			result.append(opportunity_id)
		awarded_levels.append(level)
	_state.conquest_state["enemy_opportunity_ids"] = opportunity_ids.duplicate()
	_state.conquest_state["awarded_fixed_opportunity_levels"] = awarded_levels.duplicate()
	return result


## 从已获得机缘定义汇总体力上限加值；入场时重新应用到新武将基础体力，避免旧角色数值残留。
func get_max_hp_bonus() -> int:
	return _get_opportunity_effect_total("max_hp")


## 从已获得机缘定义汇总摸牌阶段加值；真实摸牌次数由控制器从同一机缘效果读取。
func get_draw_phase_bonus() -> int:
	return _get_opportunity_effect_total("draw_phase_bonus")


## 从已获得灰色初始手牌机缘汇总入场摸牌加值；只影响敌方新武将，不进入普通三选一。
func get_initial_hand_bonus() -> int:
	return _get_opportunity_effect_total("initial_hand_bonus")


## 从已获得机缘定义汇总模式级手牌上限加值；与普通机缘永久手牌上限字段隔离，换将时可安全重算。
func get_hand_limit_bonus() -> int:
	return _get_opportunity_effect_total("hand_limit")


## 从已获得机缘定义汇总【杀】次数加值；控制器以此覆盖普通、火与雷【杀】的共同次数组。
func get_slash_limit_bonus() -> int:
	return _get_opportunity_effect_total("slash_play_limit_bonus")


## 从已获得机缘定义汇总造成伤害加值；控制器会在每次正数伤害的标准修改时机前读取。
func get_damage_bonus() -> int:
	return _get_opportunity_effect_total("damage_bonus")


## 判断已获得机缘中是否包含不同子类别装备效果；灰色机缘的数量同时决定最多装备数。
func should_equip_distinct_subtypes() -> bool:
	return _get_opportunity_effect_total("equip_distinct_subtypes") > 0


## 为当前及此前尚未处理的技能关卡随机记录一项不重复获得技能机缘；返回本次新增机缘卡ID。
func ensure_skill_opportunity_rewards(enemy: PlayerState) -> Array[String]:
	# 本次新增技能机缘；每项均是完整机缘卡而不是单独技能ID，以便直接写入右键历史。
	var result: Array[String] = []
	if _state == null or enemy == null:
		return result
	# 已处理技能奖励的关卡；用于防止同一关卡因换将或重试重复随机。
	var awarded_levels: Array[int] = _get_recorded_levels("awarded_skill_opportunity_levels")
	# 已获得技能稳定ID；随机候选不能与此前机缘或当前武将固有技能重复。
	var granted_skill_ids: Array[String] = get_enemy_skill_ids()
	# 当前累计机缘；新增技能机缘与固定数值机缘共享同一公开历史来源。
	var opportunity_ids: Array[String] = get_enemy_opportunity_ids()
	for reward_level: int in SKILL_REWARD_LEVELS:
		if reward_level > get_level() or awarded_levels.has(reward_level):
			continue
		# 本次随机到的完整机缘卡；空值表示目录中没有可用非重复技能，仍标记该关避免死循环。
		var opportunity_id: String = _pick_unique_skill_opportunity_id(enemy, granted_skill_ids)
		if not opportunity_id.is_empty():
			var opportunity_card: Dictionary = OpportunityCatalog.get_card(opportunity_id)
			var skill_id: String = str(opportunity_card.get("skill_id", ""))
			opportunity_ids.append(opportunity_id)
			result.append(opportunity_id)
			if not skill_id.is_empty():
				granted_skill_ids.append(skill_id)
		awarded_levels.append(reward_level)
	_state.conquest_state["enemy_opportunity_ids"] = opportunity_ids.duplicate()
	_state.conquest_state["awarded_skill_opportunity_levels"] = awarded_levels.duplicate()
	return result


## 返回敌方已获得的全部关卡机缘ID；顺序与实际获取顺序一致，重复数值机缘不去重。
func get_enemy_opportunity_ids() -> Array[String]:
	var result: Array[String] = []
	if _state == null:
		return result
	for opportunity_id_variant: Variant in _state.conquest_state.get("enemy_opportunity_ids", []) as Array:
		# 当前机缘稳定ID；目录不存在的历史数据跳过，避免错误定义污染实际强化计算。
		var opportunity_id: String = str(opportunity_id_variant)
		if not opportunity_id.is_empty() and not OpportunityCatalog.get_card(opportunity_id).is_empty():
			result.append(opportunity_id)
	return result


## 返回敌方通过技能机缘获得的稳定技能ID；相同技能不会重复进入结果，供新武将入场重新安装。
func get_enemy_skill_ids() -> Array[String]:
	var result: Array[String] = []
	for opportunity_id: String in get_enemy_opportunity_ids():
		# 当前机缘定义；只有获得技能效果才参与技能恢复，不把数值机缘误当作运行时技能。
		var opportunity_card: Dictionary = OpportunityCatalog.get_card(opportunity_id)
		var skill_id: String = str(opportunity_card.get("skill_id", "")) if str(opportunity_card.get("effect", "")) == "grant_skill" else ""
		if not skill_id.is_empty() and not result.has(skill_id):
			result.append(skill_id)
	return result


## 从可用武将中随机选择一名与当前武将不同的敌方新武将；武将库不足时允许保留原武将以保证对局可继续。
func choose_replacement_character(current_character_id: String, character_ids: Array[String]) -> String:
	var candidates: Array[String] = []
	for character_id: String in character_ids:
		if not character_id.is_empty() and character_id != current_character_id:
			candidates.append(character_id)
	if candidates.is_empty():
		for character_id: String in character_ids:
			if not character_id.is_empty():
				candidates.append(character_id)
	if candidates.is_empty():
		return ""
	if _rng == null:
		return candidates[0]
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## 返回指定状态数组中的已处理关卡；网络或回放恢复后的普通数组会被安全转为强类型且去重。
func _get_recorded_levels(state_key: String) -> Array[int]:
	var result: Array[int] = []
	if _state == null:
		return result
	for level_variant: Variant in _state.conquest_state.get(state_key, []) as Array:
		# 当前已处理层数；小于第2关没有关卡奖励语义，跳过异常历史值。
		var level: int = int(level_variant)
		if level > INITIAL_LEVEL and not result.has(level):
			result.append(level)
	return result


## 返回指定层数的固定机缘；16关后每层返回固定三项，其他未配置关卡返回空数组。
func _get_fixed_opportunity_ids_for_level(level: int) -> Array[String]:
	var result: Array[String] = []
	if level >= REPEATING_BONUS_START_LEVEL:
		return REPEATING_LEVEL_OPPORTUNITY_IDS.duplicate()
	for opportunity_id_variant: Variant in FIXED_LEVEL_OPPORTUNITY_IDS.get(level, []) as Array:
		# 当前固定机缘稳定ID；定义不存在时留给调用方过滤，保证本函数只负责层数映射。
		var opportunity_id: String = str(opportunity_id_variant)
		if not opportunity_id.is_empty():
			result.append(opportunity_id)
	return result


## 从全部敌方关卡机缘中累加指定效果的数值；卡牌目录是数值与效果类型的唯一来源。
func _get_opportunity_effect_total(effect_id: String) -> int:
	var result: int = 0
	if effect_id.is_empty():
		return result
	for opportunity_id: String in get_enemy_opportunity_ids():
		# 当前机缘定义；只有效果稳定ID匹配时才累加count，避免把获得技能等无数值机缘混入。
		var opportunity_card: Dictionary = OpportunityCatalog.get_card(opportunity_id)
		if str(opportunity_card.get("effect", "")) == effect_id:
			result += int(opportunity_card.get("count", 0))
	return result


## 从获得技能机缘中随机选择一项尚未取得、且不与当前敌方固有技能重复的完整机缘卡ID。
func _pick_unique_skill_opportunity_id(enemy: PlayerState, granted_skill_ids: Array[String]) -> String:
	# 当前武将固有技能；本次入场武将已经写入enemy，随机机缘不得与其重复。
	var native_skill_ids: Array = GameDatabase.get_character(enemy.character_id).get("skills", []) as Array
	# 可选机缘稳定ID；同一技能只能保留一项机缘，机缘品质仍沿用目录原始定义。
	var candidates: Array[String] = []
	for opportunity_card: Dictionary in OpportunityCatalog.get_all_cards():
		var skill_id: String = str(opportunity_card.get("skill_id", ""))
		if str(opportunity_card.get("effect", "")) != "grant_skill" or skill_id.is_empty() or granted_skill_ids.has(skill_id) or native_skill_ids.has(skill_id):
			continue
		var opportunity_id: String = str(opportunity_card.get("id", ""))
		if not opportunity_id.is_empty() and not candidates.has(opportunity_id):
			candidates.append(opportunity_id)
	if candidates.is_empty():
		return ""
	if _rng == null:
		return candidates[0]
	return candidates[_rng.randi_range(0, candidates.size() - 1)]
