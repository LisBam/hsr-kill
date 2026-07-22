class_name ConquestModeService
extends RefCounted

## 过关斩将规则服务。该服务集中计算关卡层数、敌方入场增益与随机技能来源，不持有界面节点或阶段调度逻辑。

## 过关斩将的首关数值；玩家面对的第一名敌方武将始终处于第1关且不获得层数增强。
const INITIAL_LEVEL: int = 1

## 固定层数中首次获得随机技能的关卡；每关只新增一项，已经获得的技能不会再次进入候选。
const SKILL_REWARD_LEVELS: Array[int] = [5, 10, 15]

## 进入无限递增规则的首个关卡；第16关及之后每关均叠加初始手牌、体力上限与摸牌阶段加成。
const REPEATING_BONUS_START_LEVEL: int = 16

## 敌方重生时的基础摸牌数；第8关与后续初始手牌增益会在此基础上继续相加。
const REPLACEMENT_DRAW_COUNT: int = 4

## 第2关获得的体力上限加值；该加值会在后续所有关卡继续生效。
const LEVEL_TWO_MAX_HP_BONUS: int = 1

## 第4关获得的手牌上限加值；该加值会在后续所有关卡继续生效。
const LEVEL_FOUR_HAND_LIMIT_BONUS: int = 2

## 第6关获得的体力上限加值；该加值会与第2关加值叠加。
const LEVEL_SIX_MAX_HP_BONUS: int = 1

## 第8关获得的初始手牌加值；敌方每次换将入场时额外获得该数量的手牌。
const LEVEL_EIGHT_INITIAL_HAND_BONUS: int = 4

## 第9关获得的【杀】出牌阶段次数加值；按同一【杀】次数分组统一生效。
const LEVEL_NINE_SLASH_LIMIT_BONUS: int = 1

## 第11关获得的体力上限加值；该加值会与此前体力上限增强叠加。
const LEVEL_ELEVEN_MAX_HP_BONUS: int = 2

## 第13关获得的造成伤害加值；敌方造成的每次正数伤害均在通常伤害修正前增加该值。
const LEVEL_THIRTEEN_DAMAGE_BONUS: int = 1

## 第14关自动装备的不同子类别数量；从牌堆或弃牌堆中每类随机选择一张并直接装备。
const LEVEL_FOURTEEN_EQUIPMENT_SUBTYPE_COUNT: int = 4

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
		"enemy_skill_ids": [],
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


## 返回当前关卡需要累计获得的随机技能数量；第5、10、15关各增加一项，之后保持三项。
func get_required_skill_reward_count() -> int:
	var result: int = 0
	for reward_level: int in SKILL_REWARD_LEVELS:
		if get_level() >= reward_level:
			result += 1
	return result


## 返回当前关卡累计增加的体力上限；第2、6、11关固定累加，第16关起每关再+1。
func get_max_hp_bonus() -> int:
	var level: int = get_level()
	var result: int = 0
	if level >= 2:
		result += LEVEL_TWO_MAX_HP_BONUS
	if level >= 6:
		result += LEVEL_SIX_MAX_HP_BONUS
	if level >= 11:
		result += LEVEL_ELEVEN_MAX_HP_BONUS
	if level >= REPEATING_BONUS_START_LEVEL:
		result += level - REPEATING_BONUS_START_LEVEL + 1
	return result


## 返回当前关卡累计增加的摸牌阶段摸牌数；第3、7、12关固定累加，第16关起每关再+1。
func get_draw_phase_bonus() -> int:
	var level: int = get_level()
	var result: int = 0
	if level >= 3:
		result += 1
	if level >= 7:
		result += 1
	if level >= 12:
		result += 1
	if level >= REPEATING_BONUS_START_LEVEL:
		result += level - REPEATING_BONUS_START_LEVEL + 1
	return result


## 返回当前关卡累计增加的初始手牌数；第8关固定+4，第16关起每关再+1。
func get_initial_hand_bonus() -> int:
	var level: int = get_level()
	var result: int = LEVEL_EIGHT_INITIAL_HAND_BONUS if level >= 8 else 0
	if level >= REPEATING_BONUS_START_LEVEL:
		result += level - REPEATING_BONUS_START_LEVEL + 1
	return result


## 返回当前关卡累计增加的手牌上限；第4关起恒为+2，后续关卡不再重复增加该项。
func get_hand_limit_bonus() -> int:
	return LEVEL_FOUR_HAND_LIMIT_BONUS if get_level() >= 4 else 0


## 返回当前关卡累计增加的【杀】使用次数上限；第9关起每个出牌阶段增加1次。
func get_slash_limit_bonus() -> int:
	return LEVEL_NINE_SLASH_LIMIT_BONUS if get_level() >= 9 else 0


## 返回当前关卡累计增加的造成伤害；第13关起敌方的每次正数伤害增加1点。
func get_damage_bonus() -> int:
	return LEVEL_THIRTEEN_DAMAGE_BONUS if get_level() >= 13 else 0


## 判断当前敌方入场是否应自动装备不同子类别的装备；第14关起每次新武将入场均继续拥有该增益。
func should_equip_distinct_subtypes() -> bool:
	return get_level() >= 14


## 从当前卡池的“获得技能”机缘中补足关卡要求的非重复技能；返回本次新加入的技能 ID，供日志和回放记录。
func ensure_skill_rewards(enemy: PlayerState) -> Array[String]:
	var result: Array[String] = []
	if _state == null or enemy == null:
		return result
	var granted_skill_ids: Array[String] = _get_enemy_skill_ids()
	while granted_skill_ids.size() < get_required_skill_reward_count():
		var skill_id: String = _pick_unique_opportunity_skill(enemy, granted_skill_ids)
		if skill_id.is_empty():
			break
		granted_skill_ids.append(skill_id)
		result.append(skill_id)
	_state.conquest_state["enemy_skill_ids"] = granted_skill_ids.duplicate()
	return result


## 返回当前关卡已经抽中的敌方机缘技能；数组副本只保存稳定技能 ID，不泄漏机缘候选对象。
func get_enemy_skill_ids() -> Array[String]:
	return _get_enemy_skill_ids()


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


## 从状态快照读取已抽中的敌方技能列表，并转换为强类型数组，兼容网络序列化后的普通数组。
func _get_enemy_skill_ids() -> Array[String]:
	var result: Array[String] = []
	if _state == null:
		return result
	for skill_id_variant: Variant in _state.conquest_state.get("enemy_skill_ids", []) as Array:
		var skill_id: String = str(skill_id_variant)
		if not skill_id.is_empty() and not result.has(skill_id):
			result.append(skill_id)
	return result


## 从包含 skill_id 的机缘定义中随机选择一项尚未取得、且不与当前敌方固有技能重复的技能。
func _pick_unique_opportunity_skill(enemy: PlayerState, granted_skill_ids: Array[String]) -> String:
	var native_skill_ids: Array = GameDatabase.get_character(enemy.character_id).get("skills", []) as Array
	var candidates: Array[String] = []
	for opportunity_card: Dictionary in OpportunityCatalog.get_all_cards():
		var skill_id: String = str(opportunity_card.get("skill_id", ""))
		if skill_id.is_empty() or granted_skill_ids.has(skill_id) or native_skill_ids.has(skill_id) or candidates.has(skill_id):
			continue
		candidates.append(skill_id)
	if candidates.is_empty():
		return ""
	if _rng == null:
		return candidates[0]
	return candidates[_rng.randi_range(0, candidates.size() - 1)]
