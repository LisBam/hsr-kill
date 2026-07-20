class_name CharacterSelectionService
extends RefCounted

## 选将规则服务。该服务只管理阶段、随机候选和隐藏选择，不依赖界面、AI节点、网络节点或卡牌规则。

## 领袖单独选将阶段；只有领袖可以确认候选，确认后立即公开所选武将。
const PHASE_LEADER: String = "leader_selecting"

## 其他玩家同时选将阶段；所有非领袖玩家可独立确认，但选择内容在全员完成前保持隐藏。
const PHASE_OTHERS: String = "others_selecting"

## 选将完成阶段；所有选择已可由控制器统一应用并亮出。
const PHASE_COMPLETE: String = "complete"

## 自选武将、座次与身份阶段；全部真人先确认，剩余 AI 再从未占用座次和身份名额中完成选择。
const PHASE_CUSTOM: String = "custom_selecting"

## 身份按钮与 AI 自动分配使用的稳定顺序；顺序只影响界面排列和剩余名额选择，不改变身份规则。
const IDENTITY_ORDER: Array[String] = ["leader", "loyalist", "rebel", "renegade"]

## 当前选将阶段；默认空字符串表示尚未创建选将流程。
var phase: String = ""

## 本局领袖玩家 ID；默认 -1，开始流程时从身份状态中解析。
var leader_player_id: int = -1

## 每名玩家的候选武将数量；默认5，实际数量不会超过已登记武将总数。
var candidate_count: int = 5

## 本局是否启用全武将、座次与身份自选；开始后固定，界面设置变化不会中途改变候选协议。
var custom_assignment_enabled: bool = false

## 本局参与选将的玩家 ID 数组；按座次保存，阶段校验和完成判断均使用该稳定顺序。
var _player_ids: Array[int] = []

## 全部可用武将 ID；开始流程时复制，候选生成不会修改全局数据索引。
var _character_ids: Array[String] = []

## 玩家 ID 到候选武将 ID 数组的映射；只有对应观察者可从公开快照取得具体内容。
var _candidates_by_player: Dictionary = {}

## 玩家 ID 到已选武将 ID 的映射；非领袖选择在流程完成前不会向其他观察者公开。
var _selections_by_player: Dictionary = {}

## 玩家 ID 到本局真实身份 ID 的映射；只在面向该玩家自身的选将快照中返回其本人身份，不向其他观察者公开。
var _identities_by_player: Dictionary = {}

## 自选模式下每种身份允许的总数量；来源为开局已经生成的标准身份分布。
var _identity_limits: Dictionary = {}

## 自选模式下玩家 ID 到已确认座次号的映射；座次从1开始且全局唯一。
var _selected_seats_by_player: Dictionary = {}

## 自选模式下玩家 ID 到已确认身份 ID 的映射；每种身份数量不得超过标准分布。
var _selected_identities_by_player: Dictionary = {}

## 选将使用的随机数生成器；由对局控制器注入，与本局种子保持一致且不创建第二套随机源。
var _rng: RandomNumberGenerator


## 创建一局选将流程并为领袖生成首批候选；返回空字符串表示初始化成功。
func begin(players: Array[PlayerState], character_ids: Array[String], requested_candidate_count: int, rng: RandomNumberGenerator, allow_custom_assignment: bool = false) -> String:
	_player_ids.clear()
	_character_ids = character_ids.duplicate()
	_candidates_by_player.clear()
	_selections_by_player.clear()
	_identities_by_player.clear()
	_identity_limits.clear()
	_selected_seats_by_player.clear()
	_selected_identities_by_player.clear()
	leader_player_id = -1
	_rng = rng
	custom_assignment_enabled = allow_custom_assignment
	candidate_count = clampi(requested_candidate_count, 1, maxi(_character_ids.size(), 1))
	if _character_ids.is_empty():
		return "没有可用于选将的武将配置。"
	for player: PlayerState in players:
		_player_ids.append(player.player_id)
		_identities_by_player[player.player_id] = player.identity
		_identity_limits[player.identity] = int(_identity_limits.get(player.identity, 0)) + 1
		if player.identity == "leader":
			leader_player_id = player.player_id
	if leader_player_id < 0:
		return "身份配置缺少领袖，无法开始选将。"
	if custom_assignment_enabled:
		phase = PHASE_CUSTOM
		leader_player_id = -1
		for player_id: int in _player_ids:
			_candidates_by_player[player_id] = _make_candidates("")
	else:
		phase = PHASE_LEADER
		_candidates_by_player[leader_player_id] = _make_candidates("")
	return ""


## 提交一名玩家的选将结果；返回空字符串表示合法，阶段推进由服务统一完成。
func select_character(player_id: int, character_id: String, requested_seat_number: int = -1, requested_identity: String = "") -> String:
	if phase == PHASE_COMPLETE or phase.is_empty():
		return "当前没有可提交的选将操作。"
	if not _player_ids.has(player_id):
		return "选将玩家不存在。"
	if phase == PHASE_LEADER and player_id != leader_player_id:
		return "领袖尚未完成选将。"
	if phase == PHASE_OTHERS and player_id == leader_player_id:
		return "领袖已经完成选将。"
	if _selections_by_player.has(player_id):
		return "该玩家已经确认武将。"
	# 自选模式允许通过“所有武将”提交任意已登记武将，普通模式仍严格使用本次随机候选。
	# 当前玩家候选数组；具体选择必须来自服务生成的五张候选牌。
	var candidates: Array[String] = get_candidates(player_id)
	if not candidates.has(character_id) and not (custom_assignment_enabled and _character_ids.has(character_id)):
		return "所选武将不在当前候选列表中。"
	if phase == PHASE_CUSTOM:
		# 规范化后的座次与身份；选择一号位或领袖会强制形成同一配对。
		var seat_number: int = requested_seat_number
		var identity: String = requested_identity
		if seat_number == 1 or identity == "leader":
			seat_number = 1
			identity = "leader"
		if seat_number < 1 or seat_number > _player_ids.size():
			return "请选择有效座次。"
		if not _identity_limits.has(identity):
			return "请选择有效身份。"
		if seat_number == 1 and identity != "leader":
			return "一号位必须选择领袖身份。"
		if identity == "leader" and seat_number != 1:
			return "领袖身份必须选择一号位。"
		for selected_player_id_variant: Variant in _selected_seats_by_player.keys():
			# 已确认玩家 ID；同一座次不能由两名玩家占用。
			var selected_player_id: int = int(selected_player_id_variant)
			if selected_player_id != player_id and int(_selected_seats_by_player.get(selected_player_id, -1)) == seat_number:
				return "该座次已经被其他玩家选择。"
		# 当前身份已用名额；达到标准身份分布上限时拒绝新的确认。
		var used_identity_count: int = 0
		for selected_identity_variant: Variant in _selected_identities_by_player.values():
			if str(selected_identity_variant) == identity:
				used_identity_count += 1
		if used_identity_count >= int(_identity_limits.get(identity, 0)):
			return "该身份的可选名额已经用完。"
		_selected_seats_by_player[player_id] = seat_number
		_selected_identities_by_player[player_id] = identity
	_selections_by_player[player_id] = character_id
	if phase == PHASE_LEADER:
		phase = PHASE_OTHERS
		for other_player_id: int in _player_ids:
			if other_player_id != leader_player_id:
				_candidates_by_player[other_player_id] = _make_candidates(character_id)
	if _selections_by_player.size() == _player_ids.size():
		phase = PHASE_COMPLETE
		if custom_assignment_enabled:
			for selected_player_id_variant: Variant in _player_ids:
				# 当前已确认玩家；领袖身份唯一且已与一号位绑定。
				var selected_player_id: int = int(selected_player_id_variant)
				if str(_selected_identities_by_player.get(selected_player_id, "")) == "leader":
					leader_player_id = selected_player_id
					break
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


## 返回自选模式下玩家确认的座次号；尚未确认或普通模式返回-1。
func get_selected_seat_number(player_id: int) -> int:
	return int(_selected_seats_by_player.get(player_id, -1))


## 返回自选模式下玩家确认的身份；尚未确认或普通模式返回空字符串。
func get_selected_identity(player_id: int) -> String:
	return str(_selected_identities_by_player.get(player_id, ""))


## 返回指定玩家当前仍可选择的座次；已经被其他确认玩家占用的座次会被移除。
func get_available_seat_numbers(player_id: int) -> Array[int]:
	# 已占用座次集合；当前玩家尚未确认时通常为空自身记录，接口仍兼容未来重新编辑。
	var occupied_seats: Array[int] = []
	for selected_player_id_variant: Variant in _selected_seats_by_player.keys():
		# 当前已确认玩家 ID；查询者自己的旧值不阻止其重新选择。
		var selected_player_id: int = int(selected_player_id_variant)
		if selected_player_id != player_id:
			occupied_seats.append(int(_selected_seats_by_player.get(selected_player_id, -1)))
	# 可用座次结果；从一号位到末号位稳定排列。
	var result: Array[int] = []
	for seat_number: int in range(1, _player_ids.size() + 1):
		if not occupied_seats.has(seat_number):
			result.append(seat_number)
	return result


## 返回指定玩家当前仍有名额的身份；领袖与一号位联动仍由提交校验最终保证。
func get_available_identities(player_id: int) -> Array[String]:
	# 当前各身份已用数量；查询者自己的旧选择不计入，兼容未来允许重新编辑。
	var used_counts: Dictionary = {}
	for selected_player_id_variant: Variant in _selected_identities_by_player.keys():
		# 当前已确认玩家 ID；忽略查询者自己的记录。
		var selected_player_id: int = int(selected_player_id_variant)
		if selected_player_id == player_id:
			continue
		# 当前身份 ID；按标准名额累计。
		var selected_identity: String = str(_selected_identities_by_player.get(selected_player_id, ""))
		used_counts[selected_identity] = int(used_counts.get(selected_identity, 0)) + 1
	# 可用身份结果；固定按领袖、忠臣、反贼、内奸排列。
	var result: Array[String] = []
	for identity: String in IDENTITY_ORDER:
		if int(used_counts.get(identity, 0)) < int(_identity_limits.get(identity, 0)):
			result.append(identity)
	return result


## 返回当前仍需确认的玩家 ID 数组；领袖阶段只返回领袖，其他阶段返回所有未确认非领袖。
func get_pending_player_ids() -> Array[int]:
	# 尚未完成的玩家数组；顺序与桌面座次一致，便于 AI 和网络层稳定调度。
	var result: Array[int] = []
	for player_id: int in _player_ids:
		if phase == PHASE_LEADER and player_id != leader_player_id:
			continue
		if not _selections_by_player.has(player_id):
			result.append(player_id)
	return result


## 返回面向指定观察者的选将快照；候选与非领袖选择内容严格按可见性裁剪。
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
		"selection_kind":"initial",
		"leader_player_id":leader_player_id,
		"leader_character_id":get_selection(leader_player_id),
		"candidate_count":candidate_count,
		"player_count":_player_ids.size(),
		"local_player_id":viewer_id,
		"local_identity":get_selected_identity(viewer_id) if custom_assignment_enabled else str(_identities_by_player.get(viewer_id, "hidden")),
		"local_candidates":local_candidates,
		"all_character_ids":_character_ids.duplicate() if custom_assignment_enabled and can_player_select(viewer_id) else [],
		"allow_all_characters":custom_assignment_enabled,
		"allow_custom_assignment":custom_assignment_enabled,
		"seat_options":get_available_seat_numbers(viewer_id) if custom_assignment_enabled and can_player_select(viewer_id) else [],
		"identity_options":get_available_identities(viewer_id) if custom_assignment_enabled and can_player_select(viewer_id) else [],
		"local_selected_character_id":get_selection(viewer_id),
		"can_select":can_player_select(viewer_id),
		"readiness":readiness,
	}


## 返回指定玩家当前是否可以确认候选；该判断只检查选将状态，不涉及界面可用性。
func can_player_select(player_id: int) -> bool:
	if _selections_by_player.has(player_id):
		return false
	if phase == PHASE_LEADER:
		return player_id == leader_player_id
	if phase == PHASE_OTHERS:
		return _player_ids.has(player_id) and player_id != leader_player_id
	if phase == PHASE_CUSTOM:
		return _player_ids.has(player_id)
	return false


## 为一名玩家生成不重复的随机候选；其他玩家候选优先排除已经公开的领袖武将。
func _make_candidates(excluded_character_id: String) -> Array[String]:
	# 候选池副本；排除领袖武将后若数量不足，会回退完整武将池保证配置数量可满足。
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
