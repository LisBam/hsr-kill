class_name CharacterSelectionService
extends RefCounted

## 选将规则服务。该服务只管理阶段、随机候选和隐藏选择，不依赖界面、AI节点、网络节点或卡牌规则。

## 主公单独选将阶段；只有主公可以确认候选，确认后立即公开所选武将。
const PHASE_LORD: String = "lord_selecting"

## 其他玩家同时选将阶段；所有非主公玩家可独立确认，但选择内容在全员完成前保持隐藏。
const PHASE_OTHERS: String = "others_selecting"

## 选将完成阶段；所有选择已可由控制器统一应用并亮出。
const PHASE_COMPLETE: String = "complete"

## 当前选将阶段；默认空字符串表示尚未创建选将流程。
var phase: String = ""

## 本局主公玩家 ID；默认 -1，开始流程时从身份状态中解析。
var lord_player_id: int = -1

## 每名玩家的候选武将数量；默认5，实际数量不会超过已登记武将总数。
var candidate_count: int = 5

## 本局参与选将的玩家 ID 数组；按座次保存，阶段校验和完成判断均使用该稳定顺序。
var _player_ids: Array[int] = []

## 全部可用武将 ID；开始流程时复制，候选生成不会修改全局数据索引。
var _character_ids: Array[String] = []

## 玩家 ID 到候选武将 ID 数组的映射；只有对应观察者可从公开快照取得具体内容。
var _candidates_by_player: Dictionary = {}

## 玩家 ID 到已选武将 ID 的映射；非主公选择在流程完成前不会向其他观察者公开。
var _selections_by_player: Dictionary = {}

## 选将使用的随机数生成器；由对局控制器注入，与本局种子保持一致且不创建第二套随机源。
var _rng: RandomNumberGenerator


## 创建一局选将流程并为主公生成首批候选；返回空字符串表示初始化成功。
func begin(players: Array[PlayerState], character_ids: Array[String], requested_candidate_count: int, rng: RandomNumberGenerator) -> String:
	_player_ids.clear()
	_character_ids = character_ids.duplicate()
	_candidates_by_player.clear()
	_selections_by_player.clear()
	lord_player_id = -1
	_rng = rng
	candidate_count = clampi(requested_candidate_count, 1, maxi(_character_ids.size(), 1))
	if _character_ids.is_empty():
		return "没有可用于选将的武将配置。"
	for player: PlayerState in players:
		_player_ids.append(player.player_id)
		if player.identity == "lord":
			lord_player_id = player.player_id
	if lord_player_id < 0:
		return "身份配置缺少主公，无法开始选将。"
	phase = PHASE_LORD
	_candidates_by_player[lord_player_id] = _make_candidates("")
	return ""


## 提交一名玩家的选将结果；返回空字符串表示合法，阶段推进由服务统一完成。
func select_character(player_id: int, character_id: String) -> String:
	if phase == PHASE_COMPLETE or phase.is_empty():
		return "当前没有可提交的选将操作。"
	if not _player_ids.has(player_id):
		return "选将玩家不存在。"
	if phase == PHASE_LORD and player_id != lord_player_id:
		return "主公尚未完成选将。"
	if phase == PHASE_OTHERS and player_id == lord_player_id:
		return "主公已经完成选将。"
	if _selections_by_player.has(player_id):
		return "该玩家已经确认武将。"
	# 当前玩家候选数组；具体选择必须来自服务生成的五张候选牌。
	var candidates: Array[String] = get_candidates(player_id)
	if not candidates.has(character_id):
		return "所选武将不在当前候选列表中。"
	_selections_by_player[player_id] = character_id
	if phase == PHASE_LORD:
		phase = PHASE_OTHERS
		for other_player_id: int in _player_ids:
			if other_player_id != lord_player_id:
				_candidates_by_player[other_player_id] = _make_candidates(character_id)
	if _selections_by_player.size() == _player_ids.size():
		phase = PHASE_COMPLETE
	return ""


## 返回指定玩家的候选武将 ID 副本；不存在候选时返回空数组。
func get_candidates(player_id: int) -> Array[String]:
	# 原始候选数组；逐项复制为强类型字符串，避免字典 Variant 泄漏可修改引用。
	var raw_candidates: Array = _candidates_by_player.get(player_id, []) as Array
	# 强类型候选副本；调用方可以安全排序或渲染。
	var result: Array[String] = []
	for candidate_variant: Variant in raw_candidates:
		result.append(str(candidate_variant))
	return result


## 返回指定玩家已确认的武将 ID；尚未确认时返回空字符串。
func get_selection(player_id: int) -> String:
	return str(_selections_by_player.get(player_id, ""))


## 返回当前仍需确认的玩家 ID 数组；主公阶段只返回主公，其他阶段返回所有未确认非主公。
func get_pending_player_ids() -> Array[int]:
	# 尚未完成的玩家数组；顺序与桌面座次一致，便于 AI 和网络层稳定调度。
	var result: Array[int] = []
	for player_id: int in _player_ids:
		if phase == PHASE_LORD and player_id != lord_player_id:
			continue
		if not _selections_by_player.has(player_id):
			result.append(player_id)
	return result


## 返回面向指定观察者的选将快照；候选与非主公选择内容严格按可见性裁剪。
func to_dict(viewer_id: int) -> Dictionary:
	# 玩家确认状态数组；公开“是否确认”便于同时选将阶段展示进度，但不泄漏具体选择。
	var readiness: Array[Dictionary] = []
	for player_id: int in _player_ids:
		readiness.append({
			"player_id":player_id,
			"ready":_selections_by_player.has(player_id),
		})
	# 本地候选数组；只有轮到观察者且尚未确认时才包含实际武将 ID。
	var local_candidates: Array[String] = []
	if can_player_select(viewer_id):
		local_candidates = get_candidates(viewer_id)
	return {
		"phase":phase,
		"lord_player_id":lord_player_id,
		"lord_character_id":get_selection(lord_player_id),
		"candidate_count":candidate_count,
		"local_player_id":viewer_id,
		"local_candidates":local_candidates,
		"local_selected_character_id":get_selection(viewer_id),
		"can_select":can_player_select(viewer_id),
		"readiness":readiness,
	}


## 返回指定玩家当前是否可以确认候选；该判断只检查选将状态，不涉及界面可用性。
func can_player_select(player_id: int) -> bool:
	if _selections_by_player.has(player_id):
		return false
	if phase == PHASE_LORD:
		return player_id == lord_player_id
	if phase == PHASE_OTHERS:
		return _player_ids.has(player_id) and player_id != lord_player_id
	return false


## 为一名玩家生成不重复的随机候选；其他玩家候选优先排除已经公开的主公武将。
func _make_candidates(excluded_character_id: String) -> Array[String]:
	# 候选池副本；排除主公武将后若数量不足，会回退完整武将池保证配置数量可满足。
	var pool: Array[String] = _character_ids.duplicate()
	if not excluded_character_id.is_empty() and pool.size() > candidate_count:
		pool.erase(excluded_character_id)
	_shuffle(pool)
	# 本次候选；数量最多为检查器配置的 candidate_count，且单名玩家列表内不会重复。
	var result: Array[String] = []
	for candidate_index: int in range(mini(candidate_count, pool.size())):
		result.append(pool[candidate_index])
	return result


## 使用本局随机数生成器原地洗牌；保持相同 seed 下身份、牌堆和选将候选均可复现。
func _shuffle(values: Array[String]) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		# 与当前位置交换的随机索引；范围包含0与当前索引。
		var swap_index: int = _rng.randi_range(0, index)
		# 当前位置的临时武将 ID；交换后继续处理前一个位置。
		var temporary: String = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
