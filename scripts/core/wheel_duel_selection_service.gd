class_name WheelDuelSelectionService
extends RefCounted

## 1v1车轮战专属选将服务。该服务只管理候选池、抓将顺序与私有出场阵容，不接触牌堆、体力或界面节点。

## 抓将阶段稳定名称；后手先按122221顺序从公共候选池取得双方各五名武将。
const PHASE_DRAFT: String = "draft"

## 阵容阶段稳定名称；双方各自从五名已取得武将中按顺序确认三名出场武将。
const PHASE_LINEUP: String = "lineup"

## 完成阶段稳定名称；双方阵容均确认后由控制器亮出首发武将并进入对战。
const PHASE_COMPLETE: String = "complete"

## 双方抓将批次数量；后手先抓1名，随后双方依次抓2、2、2、2名，最后先手抓1名，共10名。
const DRAFT_BATCH_COUNTS: Array[int] = [1, 2, 2, 2, 2, 1]

## 每名玩家抓取的武将总数；固定5名，运行时不应修改。
const DRAFTED_CHARACTER_COUNT_PER_PLAYER: int = 5

## 每名玩家实际出场的武将数量；固定3名，顺序确认后整局不可更改。
const LINEUP_CHARACTER_COUNT_PER_PLAYER: int = 3

## 候选明置与暗置数量允许的最小值；主菜单设置均限制为3至20。
const MIN_CANDIDATE_COUNT: int = 3

## 候选明置与暗置数量允许的最大值；主菜单设置均限制为3至20。
const MAX_CANDIDATE_COUNT: int = 20

## 当前阶段；空字符串表示服务尚未初始化。
var phase: String = ""

## 先手玩家稳定ID；身份固定为red，并在对战开始后获得第一回合。
var first_player_id: int = -1

## 后手玩家稳定ID；身份固定为blue，并取得抓将阶段的第一次选择权。
var second_player_id: int = -1

## 本局明置候选数量；范围3至20，默认由设置锁定为6。
var face_up_candidate_count: int = 6

## 本局暗置候选数量；范围3至20，默认由设置锁定为4。
var face_down_candidate_count: int = 4

## 当前抓将批次索引；范围0至5，进入阵容阶段后保持末值。
var draft_batch_index: int = 0

## 当前抓将批次已经选择的数量；达到该批次数量后自动推进到下一批。
var picks_in_current_batch: int = 0

## 公共候选槽数组；每项保存稳定slot_id、真实character_id、是否明置与选择者ID，已选槽继续保留原位置。
var _pool_slots: Array[Dictionary] = []

## 玩家已取得的五名武将；键为稳定玩家ID，值按取得顺序保存武将ID。
var _drafted_by_player: Dictionary = {}

## 玩家最终三名出场武将；键为稳定玩家ID，值按不可变出场顺序保存武将ID。
var _lineup_by_player: Dictionary = {}

## 本局随机源；由控制器注入并与身份、牌堆共用同一种子以支持回放复现。
var _rng: RandomNumberGenerator


## 初始化候选池与抓将流程；成功返回空字符串，配置非法时返回可直接显示给玩家的中文错误。
func begin(players: Array[PlayerState], character_ids: Array[String], requested_face_up_count: int, requested_face_down_count: int, rng: RandomNumberGenerator) -> String:
	phase = ""
	_pool_slots.clear()
	_drafted_by_player.clear()
	_lineup_by_player.clear()
	draft_batch_index = 0
	picks_in_current_batch = 0
	if players.size() != 2:
		return "1v1车轮战仅支持2名玩家。"
	face_up_candidate_count = clampi(requested_face_up_count, MIN_CANDIDATE_COUNT, MAX_CANDIDATE_COUNT)
	face_down_candidate_count = clampi(requested_face_down_count, MIN_CANDIDATE_COUNT, MAX_CANDIDATE_COUNT)
	var total_candidate_count: int = face_up_candidate_count + face_down_candidate_count
	if total_candidate_count < DRAFTED_CHARACTER_COUNT_PER_PLAYER * 2:
		return "候选明置武将与候选暗置武将合计至少需要10名。"
	if character_ids.size() < total_candidate_count:
		return "当前武将数量不足，无法生成%d名不重复的车轮战候选武将。" % total_candidate_count
	_rng = rng
	first_player_id = players[0].player_id
	second_player_id = players[1].player_id
	_drafted_by_player[first_player_id] = []
	_drafted_by_player[second_player_id] = []
	_lineup_by_player[first_player_id] = []
	_lineup_by_player[second_player_id] = []
	var shuffled_character_ids: Array[String] = character_ids.duplicate()
	_shuffle_strings(shuffled_character_ids)
	for slot_index: int in range(total_candidate_count):
		_pool_slots.append({"slot_id":slot_index, "character_id":shuffled_character_ids[slot_index], "face_up":slot_index < face_up_candidate_count, "picked_by_player_id":-1})
	phase = PHASE_DRAFT
	return ""


## 返回当前应抓将的玩家ID；阵容阶段或完成阶段返回-1。
func get_current_drafter_id() -> int:
	if phase != PHASE_DRAFT or draft_batch_index < 0 or draft_batch_index >= DRAFT_BATCH_COUNTS.size():
		return -1
	return second_player_id if draft_batch_index % 2 == 0 else first_player_id


## 返回当前批次仍需抓取的数量；非抓将阶段返回0。
func get_remaining_picks_in_batch() -> int:
	if phase != PHASE_DRAFT or draft_batch_index < 0 or draft_batch_index >= DRAFT_BATCH_COUNTS.size():
		return 0
	return maxi(DRAFT_BATCH_COUNTS[draft_batch_index] - picks_in_current_batch, 0)


## 从指定公共槽抓取一名武将；暗置武将在成功取得后只进入取得者的私有武将列表。
func pick_candidate(player_id: int, slot_id: int) -> String:
	if phase != PHASE_DRAFT:
		return "当前不在车轮战抓将阶段。"
	if player_id != get_current_drafter_id():
		return "当前尚未轮到该玩家抓将。"
	var slot_index: int = _find_pool_slot_index(slot_id)
	if slot_index < 0:
		return "该候选武将已被选择或不存在。"
	var drafted: Array = _drafted_by_player.get(player_id, []) as Array
	if drafted.size() >= DRAFTED_CHARACTER_COUNT_PER_PLAYER:
		return "该玩家已经取得5名武将。"
	var selected_slot: Dictionary = _pool_slots[slot_index]
	if int(selected_slot.get("picked_by_player_id", -1)) >= 0:
		return "该候选武将已被选择或不存在。"
	selected_slot["picked_by_player_id"] = player_id
	_pool_slots[slot_index] = selected_slot
	drafted.append(str(selected_slot.get("character_id", "")))
	_drafted_by_player[player_id] = drafted
	picks_in_current_batch += 1
	if picks_in_current_batch >= DRAFT_BATCH_COUNTS[draft_batch_index]:
		draft_batch_index += 1
		picks_in_current_batch = 0
	if draft_batch_index >= DRAFT_BATCH_COUNTS.size():
		phase = PHASE_LINEUP
	return ""


## 提交三名武将的固定出场顺序；必须来自本人取得的五名武将且不得重复。
func submit_lineup(player_id: int, ordered_character_ids: Array[String]) -> String:
	if phase != PHASE_LINEUP:
		return "当前不在车轮战阵容确认阶段。"
	if player_id != first_player_id and player_id != second_player_id:
		return "提交阵容的玩家不存在。"
	if not (_lineup_by_player.get(player_id, []) as Array).is_empty():
		return "该玩家已经确认出场武将顺序。"
	if ordered_character_ids.size() != LINEUP_CHARACTER_COUNT_PER_PLAYER:
		return "请选择3名武将并按出场顺序提交。"
	var drafted: Array = _drafted_by_player.get(player_id, []) as Array
	var unique_ids: Dictionary = {}
	for character_id: String in ordered_character_ids:
		if character_id.is_empty() or not drafted.has(character_id):
			return "出场武将必须来自本人取得的5名武将。"
		if unique_ids.has(character_id):
			return "同一名武将不能在出场阵容中重复。"
		unique_ids[character_id] = true
	_lineup_by_player[player_id] = ordered_character_ids.duplicate()
	if has_submitted_lineup(first_player_id) and has_submitted_lineup(second_player_id):
		phase = PHASE_COMPLETE
	return ""


## 返回指定玩家取得的五名武将副本；仅供权威控制器、本人私有快照与AI读取。
func get_drafted_characters(player_id: int) -> Array[String]:
	var result: Array[String] = []
	for character_id_variant: Variant in _drafted_by_player.get(player_id, []) as Array:
		result.append(str(character_id_variant))
	return result


## 返回指定玩家最终三名出场武将副本；阵容未确认时返回空数组。
func get_lineup(player_id: int) -> Array[String]:
	var result: Array[String] = []
	for character_id_variant: Variant in _lineup_by_player.get(player_id, []) as Array:
		result.append(str(character_id_variant))
	return result


## 返回指定玩家是否已经确认三名出场武将及顺序。
func has_submitted_lineup(player_id: int) -> bool:
	return (_lineup_by_player.get(player_id, []) as Array).size() == LINEUP_CHARACTER_COUNT_PER_PLAYER


## 生成面向单一观察者的私有快照；已选槽统一暗置并公开我方/对方归属，不发送被选武将真实ID。
func to_dict(viewer_id: int) -> Dictionary:
	if phase.is_empty():
		return {}
	var pool_snapshot: Array[Dictionary] = []
	for slot: Dictionary in _pool_slots:
		# 当前槽位选择者；负数表示仍可选择，已选槽必须保持牌背且只显示观察者相对归属。
		var picked_by_player_id: int = int(slot.get("picked_by_player_id", -1))
		# 当前槽位是否仍公开正面；被选择后无论原本明暗均强制暗置。
		var is_face_up: bool = bool(slot.get("face_up", false)) and picked_by_player_id < 0
		# 当前观察者看到的选择归属；旁观者统一视为对方选择，避免公开稳定玩家ID产生额外界面依赖。
		var selection_owner: String = ""
		if picked_by_player_id >= 0:
			selection_owner = "self" if picked_by_player_id == viewer_id else "opponent"
		pool_snapshot.append({"slot_id":int(slot.get("slot_id", -1)), "face_up":is_face_up, "character_id":str(slot.get("character_id", "")) if is_face_up else "", "selection_owner":selection_owner})
	var opponent_id: int = second_player_id if viewer_id == first_player_id else first_player_id
	var viewer_is_player: bool = viewer_id == first_player_id or viewer_id == second_player_id
	var can_select: bool = phase == PHASE_DRAFT and viewer_id == get_current_drafter_id()
	can_select = can_select or phase == PHASE_LINEUP and viewer_is_player and not has_submitted_lineup(viewer_id)
	return {
		"selection_kind":"wheel_duel",
		"phase":phase,
		"can_select":can_select,
		"first_player_id":first_player_id,
		"second_player_id":second_player_id,
		"local_identity":"red" if viewer_id == first_player_id else "blue",
		"pool_slots":pool_snapshot,
		"local_drafted_characters":get_drafted_characters(viewer_id),
		"local_lineup":get_lineup(viewer_id),
		"local_lineup_submitted":has_submitted_lineup(viewer_id),
		"opponent_drafted_count":get_drafted_characters(opponent_id).size(),
		"opponent_lineup_submitted":has_submitted_lineup(opponent_id),
		"current_drafter_id":get_current_drafter_id(),
		"remaining_picks_in_batch":get_remaining_picks_in_batch(),
		"draft_batch_index":draft_batch_index,
		"face_up_candidate_count":face_up_candidate_count,
		"face_down_candidate_count":face_down_candidate_count,
	}


## 按稳定槽ID查找当前公共候选数组索引；候选被取得后槽ID不会复用。
func _find_pool_slot_index(slot_id: int) -> int:
	for slot_index: int in range(_pool_slots.size()):
		if int(_pool_slots[slot_index].get("slot_id", -1)) == slot_id and int(_pool_slots[slot_index].get("picked_by_player_id", -1)) < 0:
			return slot_index
	return -1


## 使用本局随机源原地洗牌字符串数组；服务无随机源时保持输入顺序供独立测试使用。
func _shuffle_strings(values: Array[String]) -> void:
	if _rng == null:
		return
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index: int = _rng.randi_range(0, index)
		var temporary_value: String = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary_value
