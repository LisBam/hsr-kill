class_name StartingHandMulliganService
extends RefCounted

## 开局手气卡服务。该组件只管理张数、完成状态与 AI 起手评估，不移动实体牌、不推进阶段。

## 无限手气卡模式下 AI 的单局安全评估上限；避免极端随机序列阻塞开局，玩家本人仍不受该上限影响。
const MAX_AI_UNLIMITED_ATTEMPTS: int = 20

## 一号位 AI 的最低防御需求分；1张【闪】即可满足前置位基础自保要求。
const FRONT_POSITION_DEFENSE_REQUIREMENT: float = 1.0

## 末号位相对一号位增加的防御需求分；线性插值后末位总需求为2.5分。
const LATE_POSITION_DEFENSE_BONUS: float = 1.5

## 【闪】在起手评估中的防御分；完整抵消一次普通【杀】，因此记1分。
const DODGE_DEFENSE_SCORE: float = 1.0

## 【桃】在起手评估中的防御分；兼具自救与救援能力，因此略高于单张【闪】。
const PEACH_DEFENSE_SCORE: float = 1.25

## 【酒】在起手评估中的防御分；只能濒死自救且兼具进攻用途，因此低于【闪】。
const WINE_DEFENSE_SCORE: float = 0.75

## 防具在起手评估中的防御分；未装备时仍视为可立即建立的一层防御资源。
const ARMOR_DEFENSE_SCORE: float = 1.0

## 防御坐骑在起手评估中的防御分；距离保护低于直接响应和防具，因此记0.5分。
const DEFENSIVE_MOUNT_DEFENSE_SCORE: float = 0.5

## AI 每张起始手牌的最低平均保留价值；低于3.5分时即使防御达标也会刷新。
const MINIMUM_AVERAGE_HAND_VALUE: float = 3.5

## 当前手气卡阶段是否仍在进行；全部玩家确认结束后改为false。
var active: bool = false

## 每名玩家配置的手气卡张数；0关闭、1至5与10为有限张数、-1无限张。
var configured_limit: int = 0

## 是否允许 AI 自动评估并使用手气卡；关闭时 AI 会立即确认保留起始手牌。
var ai_enabled: bool = false

## 本局参与手气卡确认的玩家 ID；按最终座次保存。
var _player_ids: Array[int] = []

## 玩家 ID 到剩余手气卡张数的映射；无限张玩家保存-1。
var _remaining_by_player: Dictionary = {}

## 已经确认不再刷新的玩家集合；键为玩家 ID，值固定true。
var _finished_by_player: Dictionary = {}

## AI 在无限模式下已经尝试的次数；有限模式不需要额外安全计数。
var _ai_attempts_by_player: Dictionary = {}


## 创建一次手气卡阶段；数量关闭或没有玩家时保持inactive。
func begin(player_ids: Array[int], limit: int, allow_ai: bool) -> void:
	_player_ids = player_ids.duplicate()
	# 标准化后的手气卡张数；服务与设置层共用公开档位，直接构造服务时也不能绕过房主规则。
	configured_limit = limit if [0, 1, 2, 3, 4, 5, 10, -1].has(limit) else 0
	ai_enabled = allow_ai
	_remaining_by_player.clear()
	_finished_by_player.clear()
	_ai_attempts_by_player.clear()
	for player_id: int in _player_ids:
		_remaining_by_player[player_id] = configured_limit
		_ai_attempts_by_player[player_id] = 0
	active = configured_limit != 0 and not _player_ids.is_empty()


## 返回指定玩家是否仍可提交刷新或结束；已完成玩家不能重新进入手气卡阶段。
func can_choose(player_id: int) -> bool:
	return active and _player_ids.has(player_id) and not _finished_by_player.has(player_id)


## 返回指定玩家当前是否还有手气卡张数；无限张始终返回true。
func can_refresh(player_id: int) -> bool:
	if not can_choose(player_id):
		return false
	return int(_remaining_by_player.get(player_id, 0)) == -1 or int(_remaining_by_player.get(player_id, 0)) > 0


## 消耗一张手气卡资格；控制器只有在实体手牌成功重新发放后才能调用。
func consume_refresh(player_id: int, is_ai: bool = false) -> bool:
	if not can_refresh(player_id):
		return false
	# 当前剩余张数；无限模式不递减，有限模式每次成功刷新减1张。
	var remaining: int = int(_remaining_by_player.get(player_id, 0))
	if remaining > 0:
		_remaining_by_player[player_id] = remaining - 1
	if is_ai:
		_ai_attempts_by_player[player_id] = int(_ai_attempts_by_player.get(player_id, 0)) + 1
	return true


## 标记一名玩家确认保留当前手牌；全部完成后自动结束服务。
func finish_player(player_id: int) -> bool:
	if not can_choose(player_id):
		return false
	_finished_by_player[player_id] = true
	if _finished_by_player.size() >= _player_ids.size():
		active = false
	return true


## 返回指定玩家的私有手气卡快照；其他玩家只能从公共阶段得知仍在等待，不获得其剩余张数。
func to_dict(viewer_id: int) -> Dictionary:
	# 当前观察者是否仍需操作；只有本人可以读取剩余张数和提交按钮状态。
	var viewer_can_choose: bool = can_choose(viewer_id)
	return {
		"active":active,
		"can_choose":viewer_can_choose,
		"can_refresh":can_refresh(viewer_id),
		"remaining":int(_remaining_by_player.get(viewer_id, 0)) if viewer_can_choose else 0,
		"finished_count":_finished_by_player.size(),
		"player_count":_player_ids.size(),
	}


## 根据起始手牌牌面与最终座次判断 AI 是否应刷新；后置位拥有更高的防御牌需求。
func should_ai_refresh(player: PlayerState, seat_number: int, total_players: int) -> bool:
	if player == null or not ai_enabled or not can_refresh(player.player_id):
		return false
	if configured_limit == -1 and int(_ai_attempts_by_player.get(player.player_id, 0)) >= MAX_AI_UNLIMITED_ATTEMPTS:
		return false
	# 后置比例；一号位为0，最后一号位接近1，用于连续提高防御需求而不硬编码具体人数。
	var late_position_ratio: float = float(maxi(seat_number - 1, 0)) / float(maxi(total_players - 1, 1))
	# 防御需求；前置位至少1分，后置位线性提高到2.5分。
	var required_defense_score: float = FRONT_POSITION_DEFENSE_REQUIREMENT + late_position_ratio * LATE_POSITION_DEFENSE_BONUS
	# 当前防御牌得分；【闪】、救援牌、防具和防御坐骑按公开牌面元数据累计。
	var defense_score: float = 0.0
	# 当前起手总保留价值；极低质量手牌即使防御达标也允许刷新。
	var total_hand_value: float = 0.0
	# 同名牌已经评估的数量；数组型 value 按第1、第2、后续同名牌依次取值，避免重复牌全部套用最高价值。
	var evaluated_definition_counts: Dictionary = {}
	for card: CardInstance in player.hand:
		# 当前卡牌定义；起手评估只读取静态元数据，不执行牌效或修改实体。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		# 当前 AI 配置；value支持单值或随同名数量递减数组，起手阶段取首项作为基础牌质。
		var ai_profile: Dictionary = definition.get("ai", {}) as Dictionary
		# 当前牌值配置；单值直接使用，数组按同名牌出现次序读取边际价值。
		var value_variant: Variant = ai_profile.get("value", 0.0)
		# 当前卡牌稳定定义ID；用于把同名实体归入同一个边际价值计数。
		var definition_id: String = card.definition_id
		# 当前同名牌序号；从0开始并限制到数组最后一项，使未显式配置更多副本时沿用最低边际价值。
		var definition_copy_index: int = int(evaluated_definition_counts.get(definition_id, 0))
		evaluated_definition_counts[definition_id] = definition_copy_index + 1
		if value_variant is Array and not (value_variant as Array).is_empty():
			# 数组型牌值；同名牌越多时按配置提供的边际价值递减。
			var value_options: Array = value_variant as Array
			total_hand_value += float(value_options[mini(definition_copy_index, value_options.size() - 1)])
		else:
			total_hand_value += float(value_variant)
		# 当前响应模式；【闪】提供完整防御分，能救援的【桃】【酒】按生存覆盖程度计分。
		var provided_response_pattern: String = str(definition.get("provided_response_pattern", ""))
		if provided_response_pattern == "shan":
			defense_score += DODGE_DEFENSE_SCORE
		elif provided_response_pattern == "tao":
			defense_score += PEACH_DEFENSE_SCORE
		elif provided_response_pattern == "jiu":
			defense_score += WINE_DEFENSE_SCORE
		# 当前装备子类型；防具提供1分，防御坐骑提供0.5分，尚未装备也按起手可用资源评估。
		var subtype: String = str(definition.get("subtype", ""))
		if subtype == "armor":
			defense_score += ARMOR_DEFENSE_SCORE
		elif subtype == "defensive_mount":
			defense_score += DEFENSIVE_MOUNT_DEFENSE_SCORE
	# 起手价值下限；每张牌平均低于3.5分视为整体牌质过低。
	var minimum_hand_value: float = float(player.hand.size()) * MINIMUM_AVERAGE_HAND_VALUE
	return defense_score < required_defense_score or total_hand_value < minimum_hand_value
