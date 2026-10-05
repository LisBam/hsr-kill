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
const IDENTITY_ORDER: Array[String] = ["leader", "loyalist", "rebel", "renegade", "landlord", "peasant", "blue", "red"]

## 当前选将阶段；默认空字符串表示尚未创建选将流程。
var phase: String = ""

## 本局领袖玩家 ID；默认 -1，开始流程时从身份状态中解析。
var leader_player_id: int = -1

## 当前选将所属对局模式；identity 保留领袖优先选将，斗地主与2v2全员同时选将，过关斩将固定由玩家先选、敌方后选。
var match_mode: String = "identity"

## 每名玩家的候选武将数量；默认5，实际数量不会超过已登记武将总数。
var candidate_count: int = 5

## 每名玩家本局初始拥有的换将卡数量；只接受控制器锁定后的非负值，0表示关闭换将入口。
var replacement_card_count: int = 0

## 本局是否启用全武将、座次与身份自选；开始后固定，界面设置变化不会中途改变候选协议。
var custom_assignment_enabled: bool = false

## 本局是否开放“所有武将”入口；可独立于座次身份自选启用，供固定阵营与座次的模式复用。
var all_characters_enabled: bool = false

## 本局参与选将的玩家 ID 数组；按座次保存，阶段校验和完成判断均使用该稳定顺序。
var _player_ids: Array[int] = []

## 全部可用武将 ID；开始流程时复制，候选生成不会修改全局数据索引。
var _character_ids: Array[String] = []

## 全部拥有至少一个领袖技的武将 ID；领袖候选会把这些武将固定放在普通随机候选之前。
var _leader_skill_character_ids: Array[String] = []

## 玩家 ID 到候选武将 ID 数组的映射；只有对应观察者可从公开快照取得具体内容。
var _candidates_by_player: Dictionary = {}

## 玩家 ID 到不可使用换将卡替换的候选武将 ID 数组；仅保存首任领袖阶段的领袖技固定候选。
var _locked_candidates_by_player: Dictionary = {}

## 玩家 ID 到剩余换将卡数量的映射；只有本人能从裁剪快照读取自己的剩余张数。
var _replacement_cards_remaining_by_player: Dictionary = {}

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

## 首次身份分配产生的领袖武将 ID；自选座次身份期间继续公开，最终确认后由新领袖选择刷新。
var _initial_leader_character_id: String = ""

## 首次身份分配产生的领袖玩家 ID；进入最终自选后保持不变，用于区分首任领袖保留武将与最终领袖身份。
var _initial_leader_player_id: int = -1

## 首次身份分配旋转后的玩家座次；首任领袖固定为一号位，用作自选阶段生效的默认值与未确认玩家的预览回退，不占最终座次名额。
var _initial_seats_by_player: Dictionary = {}

## 首次随机分配的玩家身份；自选阶段用作本地默认选中值和未确认玩家的预览回退，不占最终身份名额。
var _initial_identities_by_player: Dictionary = {}

## 玩家正在编辑的座次预览；只用于开局前即时展示，确认武将后才写入最终座次映射。
var _preview_seats_by_player: Dictionary = {}

## 玩家正在编辑的身份预览；只用于开局前即时展示，确认武将后才写入最终身份映射。
var _preview_identities_by_player: Dictionary = {}

## 2v2 开局座次→颜色绑定表；键为座次号 1–4，值为 blue/red。
## 由首次身份分配写入：一/四号位同色、二/三号位同色，整表蓝红可互换，自选期间不可拆散成队关系。
var _team2v2_identity_by_seat: Dictionary = {}

## 选将使用的随机数生成器；由对局控制器注入，与本局种子保持一致且不创建第二套随机源。
var _rng: RandomNumberGenerator


## 返回一号位绑定的首任身份 ID；斗地主为 landlord，标准身份局为 leader。
## 2v2 不绑定首任身份（蓝/红各两张且可互换座次色），返回空字符串。
func get_first_seat_identity() -> String:
	if is_team2v2_mode() or is_conquest_mode():
		return ""
	if is_doudizhu_mode():
		return "landlord"
	if _identity_limits.has("landlord"):
		return "landlord"
	return "leader"


## 判断当前选将是否为斗地主模式；用于跳过领袖阶段与过滤身份选项。
func is_doudizhu_mode() -> bool:
	return match_mode == "doudizhu" or _identity_limits.has("landlord")


## 返回是否为 2v2 模式；身份表含蓝方/红方时同样判定为真。
func is_team2v2_mode() -> bool:
	return match_mode == "team2v2" or (match_mode != "conquest" and (_identity_limits.has("blue") or _identity_limits.has("red")))


## 判断当前是否为过关斩将模式；该模式固定全部玩家方先确认武将，再为敌方生成随机候选，不复用2v2的成队座次约束。
func is_conquest_mode() -> bool:
	return match_mode == "conquest"


## 返回过关斩将中按座次排列的红方玩家稳定ID；以创建时的首次身份为准，联机多人局包含全部偶数座位玩家。
func get_conquest_front_player_ids() -> Array[int]:
	# 玩家方结果数组；非过关斩将返回空数组，调用方不应据此推断其他模式的阵营。
	var result: Array[int] = []
	if not is_conquest_mode():
		return result
	for player_id: int in _player_ids:
		if str(_initial_identities_by_player.get(player_id, "")) == "red":
			result.append(player_id)
	return result


## 判断指定角色是否是过关斩将中的蓝方敌人；敌方必须等待全部玩家方确认武将后才能选将。
func _is_conquest_enemy(player_id: int) -> bool:
	return is_conquest_mode() and str(_initial_identities_by_player.get(player_id, "")) == "blue"


## 判断过关斩将全部红方玩家是否已经确认武将；该边界同时控制敌方候选生成与敌方选将权限。
func _all_conquest_front_players_selected() -> bool:
	for front_player_id: int in get_conquest_front_player_ids():
		if not _selections_by_player.has(front_player_id):
			return false
	return true


## 返回是否全员同时选将（不公开武将）；斗地主与 2v2 均为 true，过关斩将使用独立的玩家先选流程。
func uses_simultaneous_selection() -> bool:
	return is_doudizhu_mode() or is_team2v2_mode()


## 返回当前阶段是否为「多名玩家同时选将」；这是**阶段**判据，与上面的**模式**判据正交，互不影响。
## 该阶段的定义本身就是选择内容在全员完成前不公开，因此期间任何 AI 都不得抢先确认武将，
## 否则真人稍后提交同一武将时会被「该武将已经被其他玩家选择」拒绝。
## 只读实现：不修改任何状态，可在门禁、快照与测试中任意调用。
func is_simultaneous_selection_phase() -> bool:
	return phase == PHASE_OTHERS


## 返回是否启用领袖优先选将与公开领袖武将；斗地主、2v2与过关斩将均为 false。
func uses_leader_priority_selection() -> bool:
	return not uses_simultaneous_selection() and not is_conquest_mode()


## 返回一号位身份是否全局唯一；唯一时身份与一号位双向绑定（身份局领袖、三人斗地主地主）。
## 2v2 不绑定一号位身份，恒为 false。
func has_unique_first_seat_identity() -> bool:
	var first_seat_identity: String = get_first_seat_identity()
	if first_seat_identity.is_empty():
		return false
	return int(_identity_limits.get(first_seat_identity, 0)) <= 1


## 返回本局固定地主座次号列表；按标准斗地身份表生成（3人为[1]，5人为[1,3]），非斗地返回空数组。
## 调用方可安全修改返回数组；该列表用于自选座次/身份联动与校验，不改变最终洗牌后的玩家对象。
func get_landlord_seat_numbers() -> Array[int]:
	var result: Array[int] = []
	if not is_doudizhu_mode():
		return result
	# 按 DOUDIZHU_DISTRIBUTIONS 的固定座次：地主占一号位，五人局另占三号位。
	var player_count: int = _player_ids.size()
	var landlord_limit: int = int(_identity_limits.get("landlord", 0))
	if player_count >= 1 and landlord_limit >= 1:
		result.append(1)
	if player_count >= 3 and landlord_limit >= 2:
		result.append(3)
	return result


## 从候选座次中挑选一个地主位；优先保留 requested，其次随机/首个可用地主位。
func _pick_landlord_seat(available_seats: Array[int], preferred_seat_number: int) -> int:
	var landlord_seats: Array[int] = get_landlord_seat_numbers()
	if landlord_seats.has(preferred_seat_number) and available_seats.has(preferred_seat_number):
		return preferred_seat_number
	# 可用地主位；顺序保持 1、3 稳定，随机仅决定多地主时落到哪一席。
	var candidates: Array[int] = []
	for seat_number: int in landlord_seats:
		if available_seats.has(seat_number):
			candidates.append(seat_number)
	if candidates.is_empty():
		return preferred_seat_number if landlord_seats.has(preferred_seat_number) else (landlord_seats[0] if not landlord_seats.is_empty() else preferred_seat_number)
	if candidates.size() == 1 or _rng == null:
		return candidates[0]
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## 从候选座次中挑选一个农民位；优先保留 requested，其次随机/首个非地主可用座次。
func _pick_peasant_seat(available_seats: Array[int], preferred_seat_number: int) -> int:
	var landlord_seats: Array[int] = get_landlord_seat_numbers()
	if preferred_seat_number >= 1 and not landlord_seats.has(preferred_seat_number) and available_seats.has(preferred_seat_number):
		return preferred_seat_number
	var candidates: Array[int] = []
	for seat_number: int in available_seats:
		if not landlord_seats.has(seat_number):
			candidates.append(seat_number)
	if candidates.is_empty():
		return preferred_seat_number
	if candidates.size() == 1 or _rng == null:
		return candidates[0]
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## 返回 2v2 某座次开局绑定的蓝/红身份；非 2v2 或未知座次返回空字符串。
func get_team2v2_identity_for_seat(seat_number: int) -> String:
	if not is_team2v2_mode():
		return ""
	return str(_team2v2_identity_by_seat.get(seat_number, ""))


## 返回 2v2 某颜色在本局绑定的座次号列表（稳定升序）；非 2v2 返回空数组。
func get_team2v2_seats_for_identity(identity: String) -> Array[int]:
	var result: Array[int] = []
	if not is_team2v2_mode() or identity.is_empty():
		return result
	for seat_number: int in range(1, _player_ids.size() + 1):
		if str(_team2v2_identity_by_seat.get(seat_number, "")) == identity:
			result.append(seat_number)
	return result


## 从可用座次中挑选与指定蓝/红身份绑定的座次；优先保留 preferred，其次随机/首个绑定座。
func _pick_team2v2_seat(available_seats: Array[int], preferred_seat_number: int, identity: String) -> int:
	var team_seats: Array[int] = get_team2v2_seats_for_identity(identity)
	if team_seats.has(preferred_seat_number) and available_seats.has(preferred_seat_number):
		return preferred_seat_number
	var candidates: Array[int] = []
	for seat_number: int in team_seats:
		if available_seats.has(seat_number):
			candidates.append(seat_number)
	if candidates.is_empty():
		# 无可用绑定座时，若 preferred 本身合法绑定则返回 preferred，便于调用方报错文案。
		return preferred_seat_number if team_seats.has(preferred_seat_number) else (team_seats[0] if not team_seats.is_empty() else preferred_seat_number)
	if candidates.size() == 1 or _rng == null:
		return candidates[0]
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## 规范化自选座次与身份的联动结果；返回 seat_number、identity 与 error。
## player_id 用于解析“除本人外已被占用”的可用座次，使选地主/农民时自动落到空闲地主位/农民位。
func _normalize_custom_seat_identity(requested_seat_number: int, requested_identity: String, player_id: int = -1) -> Dictionary:
	var seat_number: int = requested_seat_number
	var identity: String = requested_identity
	var first_seat_identity: String = get_first_seat_identity()
	# 当前可选座次；未传 player_id 时退回全部座次，仅做规则层联动与校验。
	var available_seats: Array[int] = []
	if player_id >= 0:
		available_seats = get_available_seat_numbers(player_id)
	if available_seats.is_empty():
		for seat_index: int in range(1, _player_ids.size() + 1):
			available_seats.append(seat_index)
	# 若本人当前座次不在 available（因 get_available 会排除他人占用），把本人 requested 也视作可选，便于保持原座。
	if seat_number >= 1 and not available_seats.has(seat_number):
		available_seats.append(seat_number)

	# 斗地主：地主固定占 get_landlord_seat_numbers()；座次与身份双向强制一致。
	# UI 选座/选身份后总会提交一致对；服务端再强制：地主仅 1/3，农民仅非地主座。
	var landlord_seats: Array[int] = get_landlord_seat_numbers()
	if is_doudizhu_mode() and not landlord_seats.is_empty():
		var seat_is_valid: bool = seat_number >= 1 and seat_number <= _player_ids.size()
		if identity == "landlord":
			# 选地主 → 座次落到可用 1/3（已在地主位则保持）。
			seat_number = _pick_landlord_seat(available_seats, seat_number)
			identity = "landlord"
		elif identity == "peasant":
			# 选农民 → 座次落到非 1/3（已在农民位则保持）。
			seat_number = _pick_peasant_seat(available_seats, seat_number)
			identity = "peasant"
		elif seat_is_valid and landlord_seats.has(seat_number):
			# 仅提交座次时：1/3 → 地主。
			identity = "landlord"
		elif seat_is_valid:
			# 仅提交座次时：其他位置 → 农民。
			identity = "peasant"
		else:
			return {"error": "请选择有效座次。"}
		if seat_number < 1 or seat_number > _player_ids.size():
			return {"error": "请选择有效座次。"}
		if identity.is_empty() or not _identity_limits.has(identity):
			return {"error": "请选择有效身份。"}
		if landlord_seats.has(seat_number) and identity != "landlord":
			return {"error": "%d号位必须选择地主身份。" % seat_number}
		if not landlord_seats.has(seat_number) and identity == "landlord":
			if landlord_seats.size() > 1:
				return {"error": "地主身份必须选择一号位或三号位。"}
			return {"error": "地主身份必须选择一号位。"}
		return {"seat_number": seat_number, "identity": identity, "error": ""}

	# 2v2：按开局座次成队表绑定蓝/红（1/4 同色、2/3 同色，整表可互换）。
	# 选座→同步该座绑定色；选色→落到仍可用的同色座（优先保持当前座）。
	if is_team2v2_mode():
		var seat_is_valid: bool = seat_number >= 1 and seat_number <= _player_ids.size()
		if identity == "blue" or identity == "red":
			seat_number = _pick_team2v2_seat(available_seats, seat_number, identity)
		elif seat_is_valid:
			identity = get_team2v2_identity_for_seat(seat_number)
		else:
			return {"error": "请选择有效座次。"}
		if seat_number < 1 or seat_number > _player_ids.size():
			return {"error": "请选择有效座次。"}
		if identity.is_empty() or not _identity_limits.has(identity):
			return {"error": "请选择有效身份。"}
		var bound_identity: String = get_team2v2_identity_for_seat(seat_number)
		if bound_identity.is_empty():
			return {"error": "请选择有效座次。"}
		if identity != bound_identity:
			return {"error": "%d号位必须选择%s身份。" % [seat_number, "蓝方" if bound_identity == "blue" else "红方"]}
		return {"seat_number": seat_number, "identity": identity, "error": ""}

	# 无首任身份绑定的兜底模式：仅校验座次范围与身份名额。
	if first_seat_identity.is_empty():
		if seat_number < 1 or seat_number > _player_ids.size():
			return {"error": "请选择有效座次。"}
		if identity.is_empty() or not _identity_limits.has(identity):
			return {"error": "请选择有效身份。"}
		return {"seat_number": seat_number, "identity": identity, "error": ""}

	# 身份局：一号位始终绑定首任身份；唯一首任身份选择时同步绑回一号位。
	if seat_number == 1:
		identity = first_seat_identity
	elif has_unique_first_seat_identity() and identity == first_seat_identity:
		seat_number = 1
		identity = first_seat_identity
	if seat_number < 1 or seat_number > _player_ids.size():
		return {"error": "请选择有效座次。"}
	if identity.is_empty() or not _identity_limits.has(identity):
		return {"error": "请选择有效身份。"}
	if seat_number == 1 and identity != first_seat_identity:
		return {"error": "一号位必须选择%s身份。" % ("地主" if first_seat_identity == "landlord" else "领袖")}
	if has_unique_first_seat_identity() and identity == first_seat_identity and seat_number != 1:
		return {"error": "%s身份必须选择一号位。" % ("地主" if first_seat_identity == "landlord" else "领袖")}
	return {"seat_number": seat_number, "identity": identity, "error": ""}


## 创建一局选将流程并为领袖生成首批候选；返回空字符串表示初始化成功。
func begin(players: Array[PlayerState], character_ids: Array[String], requested_candidate_count: int, rng: RandomNumberGenerator, allow_custom_assignment: bool = false, requested_replacement_card_count: int = 0, leader_skill_character_ids: Array[String] = [], requested_match_mode: String = "", allow_all_characters: bool = false) -> String:
	_player_ids.clear()
	_character_ids = character_ids.duplicate()
	_leader_skill_character_ids.clear()
	_candidates_by_player.clear()
	_locked_candidates_by_player.clear()
	_replacement_cards_remaining_by_player.clear()
	_selections_by_player.clear()
	_identities_by_player.clear()
	_identity_limits.clear()
	_selected_seats_by_player.clear()
	_selected_identities_by_player.clear()
	_initial_leader_character_id = ""
	_initial_leader_player_id = -1
	_initial_seats_by_player.clear()
	_initial_identities_by_player.clear()
	_preview_seats_by_player.clear()
	_preview_identities_by_player.clear()
	_team2v2_identity_by_seat.clear()
	leader_player_id = -1
	_rng = rng
	custom_assignment_enabled = allow_custom_assignment
	all_characters_enabled = allow_custom_assignment or allow_all_characters
	# 普通随机候选数量；设置允许1至20，武将库不足时由实际候选生成自然限制，不改变已锁定设置值。
	candidate_count = clampi(requested_candidate_count, 1, 20)
	# 本局换将卡数量；设置层已经限制为离散档位，服务仍防御性拒绝负数。
	replacement_card_count = maxi(requested_replacement_card_count, 0)
	if _character_ids.is_empty():
		return "没有可用于选将的武将配置。"
	# 模式：显式参数优先；否则根据身份表推断（地主/农民→斗地主，蓝/红→2v2）。
	var inferred_mode: String = "identity"
	for probe_player: PlayerState in players:
		if probe_player == null:
			continue
		if probe_player.identity == "landlord" or probe_player.identity == "peasant":
			inferred_mode = "doudizhu"
			break
		if probe_player.identity == "blue" or probe_player.identity == "red":
			inferred_mode = "team2v2"
	if requested_match_mode == "doudizhu" or (requested_match_mode.is_empty() and inferred_mode == "doudizhu"):
		match_mode = "doudizhu"
	elif requested_match_mode == "team2v2" or (requested_match_mode.is_empty() and inferred_mode == "team2v2"):
		match_mode = "team2v2"
	elif requested_match_mode == "conquest":
		match_mode = "conquest"
	else:
		match_mode = "identity"
	# 领袖技武将仅身份局领袖阶段使用；斗地主不注入领袖技固定候选。
	if uses_leader_priority_selection():
		for character_id: String in leader_skill_character_ids:
			if _character_ids.has(character_id) and not _leader_skill_character_ids.has(character_id):
				_leader_skill_character_ids.append(character_id)
	for player_index: int in range(players.size()):
		# 当前参与选将的玩家；初始数组顺序就是随机身份分配阶段生成的物理座次顺序。
		var player: PlayerState = players[player_index]
		_player_ids.append(player.player_id)
		_identities_by_player[player.player_id] = player.identity
		_initial_identities_by_player[player.player_id] = player.identity
		_identity_limits[player.identity] = int(_identity_limits.get(player.identity, 0)) + 1
		_replacement_cards_remaining_by_player[player.player_id] = replacement_card_count
		# 身份局记录唯一领袖；斗地主仅缓存首名地主供兼容字段，不作为优先选将者。
		if player.identity == "leader":
			leader_player_id = player.player_id
		elif player.identity == "landlord" and leader_player_id < 0:
			leader_player_id = player.player_id
		elif (is_team2v2_mode() or is_conquest_mode()) and leader_player_id < 0 and player_index == 0:
			# 2v2 兼容字段：记录一号位玩家 ID，不表示领袖优先选将。
			leader_player_id = player.player_id
	if uses_leader_priority_selection():
		if leader_player_id < 0:
			return "身份配置缺少领袖，无法开始选将。"
		_initial_leader_player_id = leader_player_id
		# 首次生效座次；身份随机完成后立即按领袖旋转，保证默认一号位与领袖身份一致。
		var initial_leader_index: int = _player_ids.find(leader_player_id)
		for player_index: int in range(_player_ids.size()):
			var initial_seat_number: int = (player_index - initial_leader_index + _player_ids.size()) % _player_ids.size() + 1
			_initial_seats_by_player[_player_ids[player_index]] = initial_seat_number
		phase = PHASE_LEADER
		_candidates_by_player[leader_player_id] = _make_candidates(leader_player_id, "", true)
		return ""
	# 斗地主、2v2与过关斩将：座次与身份已在创建玩家时固定，不再旋转。
	# 补充：身份局等领袖优先模式同样已在创建玩家后按首任身份旋转过数组，因此此处数组顺序即最终座次顺序。
	_initial_leader_player_id = -1
	for player_index: int in range(_player_ids.size()):
		_initial_seats_by_player[_player_ids[player_index]] = player_index + 1
	# 2v2：把开局座次颜色表固化为自选联动依据（1/4 同色、2/3 同色）。
	if is_team2v2_mode():
		for mapped_player_id: int in _player_ids:
			var mapped_seat_number: int = int(_initial_seats_by_player.get(mapped_player_id, -1))
			var mapped_identity: String = str(_initial_identities_by_player.get(mapped_player_id, ""))
			if mapped_seat_number >= 1 and not mapped_identity.is_empty():
				_team2v2_identity_by_seat[mapped_seat_number] = mapped_identity
	phase = PHASE_OTHERS
	# 过关斩将固定由全部红方玩家先选；敌方候选必须等全体玩家确认后才生成，避免提前随机或被AI抢先提交。
	if is_conquest_mode():
		# 全部红方玩家稳定 ID；单人局只有一号位一名玩家，联机局包含全部偶数座位玩家。
		var conquest_front_player_ids: Array[int] = get_conquest_front_player_ids()
		if conquest_front_player_ids.is_empty():
			return "过关斩将缺少玩家，无法开始选将。"
		for conquest_front_player_id: int in conquest_front_player_ids:
			_candidates_by_player[conquest_front_player_id] = _make_candidates(conquest_front_player_id, "", false)
		return ""
	for player_id: int in _player_ids:
		_candidates_by_player[player_id] = _make_candidates(player_id, "", false)
	return ""


## 提交一名玩家的选将结果；返回空字符串表示合法，阶段推进由服务统一完成。
func select_character(player_id: int, character_id: String, requested_seat_number: int = -1, requested_identity: String = "") -> String:
	if phase == PHASE_COMPLETE or phase.is_empty():
		return "当前没有可提交的选将操作。"
	if not _player_ids.has(player_id):
		return "选将玩家不存在。"
	# 过关斩将顺序校验；即使调用者绕过界面直接提交动作，敌方也不能在全部玩家确认前抢先使用全武将入口选将。
	if is_conquest_mode() and phase == PHASE_OTHERS and _is_conquest_enemy(player_id) and not _all_conquest_front_players_selected():
		return "过关斩将请等待全部玩家先选将。"
	if uses_leader_priority_selection():
		if phase == PHASE_LEADER and player_id != leader_player_id:
			return "领袖尚未完成选将。"
		if phase == PHASE_OTHERS and player_id == leader_player_id:
			return "领袖已经完成选将。"
	# 首任领袖已公开武将后只剩最终座次身份待确认；该特殊提交必须复用同一武将，不能重新进入候选选择。
	# 该保留分支只会由先亮将、后等待真人释放名额的AI首任领袖进入；真人首任领袖第一次提交已经同时确认三项。
	var is_initial_leader_assignment: bool = is_retaining_initial_leader_character(player_id)
	if _selections_by_player.has(player_id) and not is_initial_leader_assignment:
		return "该玩家已经确认武将。"
	# 自选模式允许通过“所有武将”提交任意已登记武将，普通模式仍严格使用本次随机候选。
	# 当前玩家候选数组；具体选择必须来自服务生成的五张候选牌。
	# “五张”仅表示历史默认值；实际普通随机数量由本局1至20张设置决定，自选阶段仍允许全武将入口。
	var candidates: Array[String] = get_candidates(player_id)
	if is_initial_leader_assignment and character_id != get_selection(player_id):
		return "首任领袖必须保留已经公开的武将。"
	# 全武将入口：开启自选后，身份局首任领袖公开选将、最终自选与斗地主同时选将均可提交任意已登记武将。
	# is_initial_leader_assignment 只对应 AI 首任领袖补交座次身份，真人首任领袖在 PHASE_LEADER 仍可使用全武将。
	var allows_all_characters_now: bool = all_characters_enabled and (
		phase == PHASE_LEADER
		or phase == PHASE_CUSTOM
		or uses_simultaneous_selection() and phase == PHASE_OTHERS
		or is_conquest_mode() and phase == PHASE_OTHERS
	)
	if not is_initial_leader_assignment and not candidates.has(character_id) and not (allows_all_characters_now and _character_ids.has(character_id)):
		return "所选武将不在当前候选列表中。"
	if _is_character_selected_by_other_player(player_id, character_id):
		return "该武将已经被其他玩家选择。"
	# 首任领袖是否随武将一起提交了座次身份；真人界面始终提供完整值，AI首任领袖可先亮将并把最终名额留到真人确认之后。
	var has_initial_custom_assignment: bool = (phase == PHASE_LEADER or uses_simultaneous_selection() and phase == PHASE_OTHERS) and requested_seat_number >= 1 and not requested_identity.is_empty()
	# 一次性自选确认；身份局最终自选与斗地主同时选将必须提交完整分配，首任领袖仅在请求实际携带座次身份时同步落定。
	var confirms_custom_assignment: bool = custom_assignment_enabled and (
		phase == PHASE_CUSTOM
		or has_initial_custom_assignment
		or uses_simultaneous_selection() and phase == PHASE_OTHERS
	)
	if confirms_custom_assignment:
		# 规范化后的座次与身份；斗地强制地主占固定座（1/3），2v2 按开局成队表绑定蓝/红，身份局一号位与领袖双向绑定。
		var normalized_assignment: Dictionary = _normalize_custom_seat_identity(requested_seat_number, requested_identity, player_id)
		if not str(normalized_assignment.get("error", "")).is_empty():
			return str(normalized_assignment.get("error", "请选择有效座次。"))
		var seat_number: int = int(normalized_assignment.get("seat_number", -1))
		var identity: String = str(normalized_assignment.get("identity", ""))
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
		_preview_seats_by_player.erase(player_id)
		_preview_identities_by_player.erase(player_id)
	if not is_initial_leader_assignment:
		_selections_by_player[player_id] = character_id
	# 过关斩将仅在全部红方玩家确认后才随机生成敌方候选；生成时会自动排除全部已经确认的玩家武将。
	if is_conquest_mode() and phase == PHASE_OTHERS and not _is_conquest_enemy(player_id) and _all_conquest_front_players_selected():
		for conquest_enemy_player_id: int in _player_ids:
			if _is_conquest_enemy(conquest_enemy_player_id) and not _candidates_by_player.has(conquest_enemy_player_id):
				# 当前敌方稳定玩家 ID；全部玩家确认后才按同一随机源生成候选，_make_candidates 会排除全部已选武将。
				_candidates_by_player[conquest_enemy_player_id] = _make_candidates(conquest_enemy_player_id, "", false)
	if phase == PHASE_LEADER:
		_initial_leader_character_id = character_id
		if custom_assignment_enabled:
			# 首任领袖武将同时作为最终武将保留；其后只确认座次与身份，不能再次随机发牌或弹出候选框。
			# 真人已在本次动作确认座次身份，因此会直接退出待选集合；只有未携带分配字段的AI继续走保留确认分支。
			phase = PHASE_CUSTOM
			for custom_player_id: int in _player_ids:
				if custom_player_id == leader_player_id:
					_candidates_by_player.erase(custom_player_id)
					_locked_candidates_by_player.erase(custom_player_id)
					continue
				# 最终自选严格只发放房主设置数量的随机候选；领袖技固定前缀只属于首任领袖阶段。
				_candidates_by_player[custom_player_id] = _make_candidates(custom_player_id, character_id)
		else:
			phase = PHASE_OTHERS
			for other_player_id: int in _player_ids:
				if other_player_id != leader_player_id:
					_candidates_by_player[other_player_id] = _make_candidates(other_player_id, character_id)
	# 普通模式只等待武将确认；最终自选还必须等待每名角色确认座次与身份，首任领袖已选武将不能提前结束阶段。
	# 真人首任领袖已经同时写入两份最终映射；AI首任领袖则必须等后续补齐映射后才允许完成。
	var all_players_selected: bool = _selections_by_player.size() == _player_ids.size()
	if custom_assignment_enabled and (phase == PHASE_CUSTOM or uses_simultaneous_selection() and phase == PHASE_OTHERS):
		all_players_selected = all_players_selected and _selected_seats_by_player.size() == _player_ids.size() and _selected_identities_by_player.size() == _player_ids.size()
	if all_players_selected:
		phase = PHASE_COMPLETE
		if custom_assignment_enabled:
			for selected_player_id_variant: Variant in _player_ids:
				# 当前已确认玩家；领袖身份唯一且已与一号位绑定。
				var selected_player_id: int = int(selected_player_id_variant)
				if str(_selected_identities_by_player.get(selected_player_id, "")) == get_first_seat_identity():
					leader_player_id = selected_player_id
					break
	return ""


## 使用一张换将卡替换指定玩家候选列表中的单张普通武将；返回空字符串表示替换成功。
func replace_candidate(player_id: int, character_id: String) -> String:
	if not can_player_select(player_id):
		return "当前玩家不能使用换将卡。"
	# 当前候选数组；替换必须精确命中本人私有列表中的一个稳定武将 ID。
	var candidates: Array[String] = get_candidates(player_id)
	# 被替换候选索引；负值表示请求中的武将已不属于当前私有列表。
	var candidate_index: int = candidates.find(character_id)
	if candidate_index < 0:
		return "所选武将不在当前候选列表中。"
	if get_locked_candidate_ids(player_id).has(character_id):
		return "领袖技武将不能使用换将卡替换。"
	# 当前剩余换将卡；0表示该玩家已经关闭或用尽全部次数。
	var remaining_count: int = get_replacement_cards_remaining(player_id)
	if remaining_count <= 0:
		return "换将卡已经用完。"
	# 可替换武将池；排除本人当前全部候选，保证换将结果既不同于原牌也不会在同一选将框重复。
	var pool: Array[String] = _character_ids.duplicate()
	for current_candidate_id: String in candidates:
		pool.erase(current_candidate_id)
	for selected_character_id_variant: Variant in _selections_by_player.values():
		# 已确认武将；换将结果不能把已落定的武将再次发给当前玩家。
		var selected_character_id: String = str(selected_character_id_variant)
		pool.erase(selected_character_id)
	if _is_player_previewing_leader(player_id):
		# 当前领袖身份；领袖技武将属于该身份的固定候选，不作为本次换将结果。
		for leader_skill_character_id: String in _leader_skill_character_ids:
			pool.erase(leader_skill_character_id)
	# 首任领袖已经公开后，后续随机候选继续排除该武将；全武将入口仍可由玩家主动选择它。
	if not _initial_leader_character_id.is_empty():
		pool.erase(_initial_leader_character_id)
	if pool.is_empty():
		return "没有可用于换将的其他武将。"
	_shuffle(pool)
	# 新武将 ID；共享随机源保证固定种子下换将历史可以复现。
	var replacement_character_id: String = pool[0]
	candidates[candidate_index] = replacement_character_id
	_candidates_by_player[player_id] = candidates
	_replacement_cards_remaining_by_player[player_id] = remaining_count - 1
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


## 返回指定玩家是否正在最终自选阶段保留首任领袖公开武将；该状态只要求补交座次身份，不允许再次选择或应用武将。
func is_retaining_initial_leader_character(player_id: int) -> bool:
	return phase == PHASE_CUSTOM and player_id == _initial_leader_player_id and _selections_by_player.has(player_id) and not _selected_seats_by_player.has(player_id)


## 返回指定玩家不可换将的候选 ID 副本；领袖技武将只在当前预览或首任领袖身份下锁定。
func get_locked_candidate_ids(player_id: int) -> Array[String]:
	# 原始锁定候选；逐项复制为强类型字符串，避免字典中的数组引用被外部修改。
	var raw_locked_candidates: Array = _locked_candidates_by_player.get(player_id, []) as Array
	# 强类型锁定候选副本；当前通常只包含领袖技武将。
	var result: Array[String] = []
	for character_id_variant: Variant in raw_locked_candidates:
		result.append(str(character_id_variant))
	if _is_player_previewing_leader(player_id):
		# 当前领袖候选；随机池意外包含领袖技武将时也必须与首任领袖固定候选遵守相同换将限制。
		for candidate_id: String in get_candidates(player_id):
			if _leader_skill_character_ids.has(candidate_id) and not result.has(candidate_id):
				result.append(candidate_id)
	return result


## 返回指定玩家剩余换将卡数量；不存在的玩家按0处理，不公开其他玩家的私有消耗状态。
func get_replacement_cards_remaining(player_id: int) -> int:
	return int(_replacement_cards_remaining_by_player.get(player_id, 0))


## 返回指定玩家当前可使用换将卡的候选 ID；没有剩余随机池时返回空数组，界面不会显示必然失败的按钮。
func get_replaceable_candidate_ids(player_id: int) -> Array[String]:
	if get_replacement_cards_remaining(player_id) <= 0 or not can_player_select(player_id):
		return []
	# 当前候选；全部从潜在结果池排除，保证换将后同一选将框不产生重复武将。
	var candidates: Array[String] = get_candidates(player_id)
	# 当前锁定候选；只有当前领袖身份中的领袖技武将不能作为换将目标。
	var locked_candidates: Array[String] = get_locked_candidate_ids(player_id)
	# 潜在换将池；存在至少一个不同且非领袖技武将时，普通候选才显示换将入口。
	var replacement_pool: Array[String] = _character_ids.duplicate()
	for candidate_id: String in candidates:
		replacement_pool.erase(candidate_id)
	for selected_character_id_variant: Variant in _selections_by_player.values():
		# 已确认武将；存在候选时也不能向界面错误声明该武将可作为换将结果。
		var selected_character_id: String = str(selected_character_id_variant)
		replacement_pool.erase(selected_character_id)
	if _is_player_previewing_leader(player_id):
		# 当前领袖身份；换将结果不补入额外领袖技武将，保持固定候选语义。
		for leader_skill_character_id: String in _leader_skill_character_ids:
			replacement_pool.erase(leader_skill_character_id)
	if not _initial_leader_character_id.is_empty():
		replacement_pool.erase(_initial_leader_character_id)
	if replacement_pool.is_empty():
		return []
	# 可换候选结果；保持原候选顺序，便于界面和回放稳定定位牌位。
	var result: Array[String] = []
	for candidate_id: String in candidates:
		if not locked_candidates.has(candidate_id):
			result.append(candidate_id)
	return result


## 为仍在等待的 AI 重建一组未被最终确认占用的候选；只用于自动选将防冲突，不消耗玩家换将卡。
func reroll_unclaimed_candidates(player_id: int) -> void:
	if not can_player_select(player_id):
		return
	# 已公开的首任领袖武将；后续候选继续排除，避免 AI 直接重复初始公开结果。
	var excluded_character_id: String = _initial_leader_character_id
	# 当前是否应附加领袖技固定候选；固定前缀只属于首任领袖，最终自选必须严格遵守随机候选张数。
	var include_leader_skill_characters: bool = phase == PHASE_LEADER
	_candidates_by_player[player_id] = _make_candidates(player_id, excluded_character_id, include_leader_skill_characters)


## 返回自选模式下玩家确认的座次号；尚未确认或普通模式返回-1。
func get_selected_seat_number(player_id: int) -> int:
	return int(_selected_seats_by_player.get(player_id, -1))


## 返回自选模式下玩家确认的身份；尚未确认或普通模式返回空字符串。
func get_selected_identity(player_id: int) -> String:
	return str(_selected_identities_by_player.get(player_id, ""))


## 返回首次随机分配给指定玩家的座次；自选阶段尚未确认时用于自动选中对应按钮。
func get_initial_seat_number(player_id: int) -> int:
	return int(_initial_seats_by_player.get(player_id, -1))


## 返回首次随机分配给指定玩家的身份；自选阶段尚未确认时用于自动选中对应按钮。
func get_initial_identity(player_id: int) -> String:
	return str(_initial_identities_by_player.get(player_id, _identities_by_player.get(player_id, "")))


## 返回指定玩家当前应在界面上显示的座次；最终确认优先于编辑预览，最后回退首次随机座次。
func get_preview_seat_number(player_id: int) -> int:
	if _selected_seats_by_player.has(player_id):
		return int(_selected_seats_by_player.get(player_id, -1))
	return int(_preview_seats_by_player.get(player_id, get_initial_seat_number(player_id)))


## 返回指定玩家当前应在界面上显示的身份；最终确认优先于编辑预览，最后回退首次随机身份。
func get_preview_identity(player_id: int) -> String:
	if _selected_identities_by_player.has(player_id):
		return str(_selected_identities_by_player.get(player_id, ""))
	return str(_preview_identities_by_player.get(player_id, get_initial_identity(player_id)))


## 返回指定玩家是否已经提交过未确认的座次身份预览；控制器据此区分默认随机分配与玩家主动改动。
func has_custom_assignment_preview(player_id: int) -> bool:
	return _preview_seats_by_player.has(player_id) and _preview_identities_by_player.has(player_id)


## 更新玩家尚未确认武将时的座次与身份预览；该操作不占最终名额，方便控制器即时重排未确认 AI。
func preview_custom_assignment(player_id: int, requested_seat_number: int, requested_identity: String) -> String:
	# 可预览阶段；首任领袖在第一次选将框中即可调整座次身份，其他玩家继续在最终自选阶段使用相同入口。
	var can_preview_current_phase: bool = custom_assignment_enabled and (phase == PHASE_LEADER or phase == PHASE_CUSTOM or uses_simultaneous_selection() and phase == PHASE_OTHERS)
	if not can_preview_current_phase or not can_player_select(player_id):
		return "当前玩家不能预览座次与身份。"
	# 规范化后的预览座次与身份；一号位与唯一首任身份双向绑定。
	var normalized_assignment: Dictionary = _normalize_custom_seat_identity(requested_seat_number, requested_identity, player_id)
	if not str(normalized_assignment.get("error", "")).is_empty():
		return str(normalized_assignment.get("error", "请选择有效座次与身份。"))
	var seat_number: int = int(normalized_assignment.get("seat_number", -1))
	var identity: String = str(normalized_assignment.get("identity", ""))
	# 已确认结果才占用最终名额；其他未确认玩家仍可在各自界面预览原始分配，控制器会即时重排剩余位置。
	for selected_player_id_variant: Variant in _selected_seats_by_player.keys():
		# 已确认玩家 ID；预览者自身尚未确认，不会出现在该映射中。
		var confirmed_seat_player_id: int = int(selected_player_id_variant)
		if confirmed_seat_player_id != player_id and int(_selected_seats_by_player.get(confirmed_seat_player_id, -1)) == seat_number:
			return "该座次已经被其他玩家确认。"
	for preview_player_id_variant: Variant in _preview_seats_by_player.keys():
		# 其他玩家主动预览的座次；默认随机分配不占用，但已经点击改动的预览需要即时互斥。
		var preview_seat_player_id: int = int(preview_player_id_variant)
		if preview_seat_player_id != player_id and int(_preview_seats_by_player.get(preview_seat_player_id, -1)) == seat_number:
			return "该座次正在被其他玩家预览。"
	var used_identity_count: int = 0
	for selected_player_id_variant: Variant in _selected_identities_by_player.keys():
		# 已确认身份玩家 ID；只有最终提交才消耗身份名额。
		var confirmed_identity_player_id: int = int(selected_player_id_variant)
		if confirmed_identity_player_id != player_id and str(_selected_identities_by_player.get(confirmed_identity_player_id, "")) == identity:
			used_identity_count += 1
	for preview_player_id_variant: Variant in _preview_identities_by_player.keys():
		# 其他玩家主动预览的身份；默认随机身份不占用，已修改的预览与最终名额保持同一互斥语义。
		var preview_identity_player_id: int = int(preview_player_id_variant)
		if preview_identity_player_id != player_id and str(_preview_identities_by_player.get(preview_identity_player_id, "")) == identity:
			used_identity_count += 1
	if used_identity_count >= int(_identity_limits.get(identity, 0)):
		return "该身份的可选名额已经用完。"
	_preview_seats_by_player[player_id] = seat_number
	_preview_identities_by_player[player_id] = identity
	return ""


## 返回指定玩家当前仍可选择的座次；其他玩家已确认或正在预览的座次会被移除。
func get_available_seat_numbers(player_id: int) -> Array[int]:
	# 已占用座次集合；当前玩家自己的确认或预览不阻止重新编辑，其他玩家的实时预览必须同步禁用。
	var occupied_seats: Array[int] = []
	for selected_player_id_variant: Variant in _selected_seats_by_player.keys():
		# 当前已确认玩家 ID；查询者自己的旧值不阻止其重新选择。
		var selected_player_id: int = int(selected_player_id_variant)
		if selected_player_id != player_id:
			occupied_seats.append(int(_selected_seats_by_player.get(selected_player_id, -1)))
	for preview_player_id_variant: Variant in _preview_seats_by_player.keys():
		# 当前预览玩家 ID；主动预览和最终确认在界面可选项上都占用同一座次，防止本地自动补全选中冲突按钮。
		var preview_player_id: int = int(preview_player_id_variant)
		if preview_player_id != player_id:
			occupied_seats.append(int(_preview_seats_by_player.get(preview_player_id, -1)))
	# 可用座次结果；从一号位到末号位稳定排列。
	var result: Array[int] = []
	for seat_number: int in range(1, _player_ids.size() + 1):
		if not occupied_seats.has(seat_number):
			result.append(seat_number)
	return result


## 返回指定玩家当前仍有名额的身份；其他玩家的实时预览同样占用可选名额，领袖与一号位联动仍由提交校验最终保证。
func get_available_identities(player_id: int) -> Array[String]:
	# 当前各身份已用数量；查询者自己的旧选择或预览不计入，兼容未来允许重新编辑。
	var used_counts: Dictionary = {}
	for selected_player_id_variant: Variant in _selected_identities_by_player.keys():
		# 当前已确认玩家 ID；忽略查询者自己的记录。
		var selected_player_id: int = int(selected_player_id_variant)
		if selected_player_id == player_id:
			continue
		# 当前身份 ID；按标准名额累计。
		var selected_identity: String = str(_selected_identities_by_player.get(selected_player_id, ""))
		used_counts[selected_identity] = int(used_counts.get(selected_identity, 0)) + 1
	for preview_player_id_variant: Variant in _preview_identities_by_player.keys():
		# 当前预览玩家 ID；其他玩家的预览身份在实时按钮列表中同样视为已占用名额。
		var preview_player_id: int = int(preview_player_id_variant)
		if preview_player_id == player_id:
			continue
		# 当前预览身份；与确认身份使用同一计数规则，避免随机补全到已被远端预览的名额。
		var preview_identity: String = str(_preview_identities_by_player.get(preview_player_id, ""))
		used_counts[preview_identity] = int(used_counts.get(preview_identity, 0)) + 1
	# 可用身份结果；固定按领袖、忠臣、反贼、内奸排列。
	var result: Array[String] = []
	for identity: String in IDENTITY_ORDER:
		if int(used_counts.get(identity, 0)) < int(_identity_limits.get(identity, 0)):
			result.append(identity)
	return result


## 返回当前仍需确认的玩家 ID 数组；领袖阶段只返回领袖，过关斩将的玩家确认前只返回一号位玩家，其他阶段返回全部未确认角色。
func get_pending_player_ids() -> Array[int]:
	# 尚未完成的玩家数组；顺序与桌面座次一致，便于 AI 和网络层稳定调度。
	var result: Array[int] = []
	for player_id: int in _player_ids:
		if phase == PHASE_LEADER:
			if player_id == leader_player_id and not _selections_by_player.has(player_id):
				result.append(player_id)
			continue
		if phase == PHASE_OTHERS:
			# 过关斩将：敌方候选尚未生成时只允许尚未确认的红方玩家处于待确认集合，AI驱动因此不会抢先为敌方选将。
			if is_conquest_mode() and not _all_conquest_front_players_selected():
				if not _is_conquest_enemy(player_id) and not _selections_by_player.has(player_id):
					result.append(player_id)
				continue
			var excluded_as_leader: bool = uses_leader_priority_selection() and player_id == leader_player_id
			if not excluded_as_leader and not _selections_by_player.has(player_id):
				result.append(player_id)
			continue
		if phase == PHASE_CUSTOM:
			if not _selected_seats_by_player.has(player_id):
				result.append(player_id)
			elif not _selections_by_player.has(player_id):
				result.append(player_id)
	return result


## 返回面向指定观察者的选将快照；候选与非领袖选择内容严格按可见性裁剪。
func to_dict(viewer_id: int) -> Dictionary:
	# 玩家确认状态数组；公开“是否确认”便于同时选将阶段展示进度，但不泄漏具体选择。
	var readiness: Array[Dictionary] = []
	for player_id: int in _player_ids:
		readiness.append({
			"player_id":player_id,
			"ready":_selected_seats_by_player.has(player_id) if phase == PHASE_CUSTOM else _selections_by_player.has(player_id),
		})
	# 本地候选数组；只有轮到观察者且尚未确认时才包含实际武将 ID。
	var local_candidates: Array[String] = []
	if can_player_select(viewer_id):
		local_candidates = get_candidates(viewer_id)
	# 当前可提交座次身份的阶段；身份局领袖/自选与斗地主全员同时选将均可携带座次身份。
	var allows_custom_assignment_now: bool = custom_assignment_enabled and (phase == PHASE_LEADER or phase == PHASE_CUSTOM or uses_simultaneous_selection() and phase == PHASE_OTHERS)
	# 当前可打开“所有武将”的阶段；开启自选后，首任领袖公开选将、后续最终自选、斗地主同时选将与过关斩将玩家先选阶段均应显示全武将入口。
	var allows_all_characters_now: bool = all_characters_enabled and (
		phase == PHASE_LEADER
		or phase == PHASE_CUSTOM
		or uses_simultaneous_selection() and phase == PHASE_OTHERS
		or is_conquest_mode() and phase == PHASE_OTHERS
	)
	# 首任领袖保留的最终武将；该状态只对应 AI 补交座次身份，真人首任领袖在 PHASE_LEADER 仍可使用全武将。
	var is_initial_leader_assignment: bool = is_retaining_initial_leader_character(viewer_id)
	# 公开领袖武将 ID；斗地主不公开展示任何角色武将。
	var public_leader_character_id: String = ""
	if uses_leader_priority_selection():
		public_leader_character_id = _initial_leader_character_id if phase == PHASE_CUSTOM else get_selection(leader_player_id)
	return {
		"phase":phase,
		"selection_kind":"initial",
		"match_mode":match_mode,
		"first_seat_identity":get_first_seat_identity(),
		"unique_first_seat_identity":has_unique_first_seat_identity(),
		"landlord_seat_numbers":get_landlord_seat_numbers(),
		"team2v2_identity_by_seat":_team2v2_identity_by_seat.duplicate() if is_team2v2_mode() else {},
		"team2v2_blue_seat_numbers":get_team2v2_seats_for_identity("blue") if is_team2v2_mode() else [],
		"team2v2_red_seat_numbers":get_team2v2_seats_for_identity("red") if is_team2v2_mode() else [],
		"leader_player_id":leader_player_id if uses_leader_priority_selection() else -1,
		"leader_character_id":public_leader_character_id,
		"candidate_count":candidate_count,
		"player_count":_player_ids.size(),
		"local_player_id":viewer_id,
		"local_identity":str(_identities_by_player.get(viewer_id, "hidden")),
		# 本地当前应展示的座次；所有模式均下发，供选将标题“你的座次为x号位”使用。
		"local_seat_number":get_preview_seat_number(viewer_id),
		"local_candidates":local_candidates,
		"locked_candidate_ids":get_locked_candidate_ids(viewer_id) if can_player_select(viewer_id) else [],
		"replaceable_candidate_ids":get_replaceable_candidate_ids(viewer_id) if can_player_select(viewer_id) else [],
		"replacement_cards_remaining":get_replacement_cards_remaining(viewer_id) if can_player_select(viewer_id) else 0,
		"all_character_ids":_character_ids.duplicate() if allows_all_characters_now and not is_initial_leader_assignment and can_player_select(viewer_id) else [],
		"allow_all_characters":allows_all_characters_now and not is_initial_leader_assignment and can_player_select(viewer_id),
		"allow_custom_assignment":allows_custom_assignment_now and can_player_select(viewer_id),
		"seat_options":get_available_seat_numbers(viewer_id) if allows_custom_assignment_now and can_player_select(viewer_id) else [],
		"identity_options":get_available_identities(viewer_id) if allows_custom_assignment_now and can_player_select(viewer_id) else [],
		# 首次分配座次/身份始终下发；关闭自选时仍用于标题展示，不表示可改座。
		"initial_seat_number":get_initial_seat_number(viewer_id),
		"initial_identity":get_initial_identity(viewer_id),
		"preview_seat_number":get_preview_seat_number(viewer_id) if custom_assignment_enabled else get_initial_seat_number(viewer_id),
		"preview_identity":get_preview_identity(viewer_id) if custom_assignment_enabled else get_initial_identity(viewer_id),
		"local_selected_character_id":get_selection(viewer_id),
		"retains_selected_character":is_initial_leader_assignment,
		"can_select":can_player_select(viewer_id),
		"readiness":readiness,
	}


## 返回指定玩家当前是否可以确认候选；该判断只检查选将状态，不涉及界面可用性。
func can_player_select(player_id: int) -> bool:
	if phase == PHASE_CUSTOM:
		return _player_ids.has(player_id) and not _selected_seats_by_player.has(player_id)
	if _selections_by_player.has(player_id):
		return false
	if phase == PHASE_LEADER:
		return player_id == leader_player_id
	if phase == PHASE_OTHERS:
		# 过关斩将敌方必须等待全部红方玩家确认后才可选将；候选生成与权限开放保持同一边界。
		if is_conquest_mode() and _is_conquest_enemy(player_id):
			return _player_ids.has(player_id) and _all_conquest_front_players_selected()
		if uses_leader_priority_selection():
			return _player_ids.has(player_id) and player_id != leader_player_id
		return _player_ids.has(player_id)
	return false


## 为一名玩家生成不重复的随机候选；其他玩家候选优先排除已经公开的领袖武将。
func _make_candidates(player_id: int, excluded_character_id: String, include_leader_skill_characters: bool = false) -> Array[String]:
	# 候选池副本；排除领袖武将后若数量不足，会回退完整武将池保证配置数量可满足。
	# 当前实现始终排除已经公开的首任领袖，武将库不足时只减少实际候选数，不再回填重复或公开武将。
	var pool: Array[String] = _character_ids.duplicate()
	if not excluded_character_id.is_empty():
		pool.erase(excluded_character_id)
	# 已确认武将；候选可以在未确认玩家之间重叠，但已落定结果不能再次进入 AI 补发候选或换将池。
	for selected_character_id_variant: Variant in _selections_by_player.values():
		var selected_character_id: String = str(selected_character_id_variant)
		pool.erase(selected_character_id)
	# 固定领袖技武将；先从随机池移除，再按数据库稳定顺序放在结果开头，因此不会占用普通候选数量。
	var fixed_candidates: Array[String] = []
	if include_leader_skill_characters:
		for leader_character_id: String in _leader_skill_character_ids:
			if leader_character_id == excluded_character_id or _is_character_selected_by_other_player(player_id, leader_character_id):
				continue
			pool.erase(leader_character_id)
			fixed_candidates.append(leader_character_id)
	_shuffle(pool)
	# 本次候选；数量最多为检查器配置的 candidate_count，且单名玩家列表内不会重复。
	var result: Array[String] = fixed_candidates.duplicate()
	for candidate_index: int in range(mini(candidate_count, pool.size())):
		result.append(pool[candidate_index])
	# 当前锁定候选；只有额外固定在首任领袖候选前缀中的领袖技武将不能换将。
	var locked_candidates: Array[String] = fixed_candidates.duplicate()
	_locked_candidates_by_player[player_id] = locked_candidates
	return result


## 判断玩家当前是否处于领袖身份；首任领袖始终为领袖，最终自选则读取已经规范化的预览或确认身份。
func _is_player_previewing_leader(player_id: int) -> bool:
	if not uses_leader_priority_selection():
		return false
	if phase == PHASE_LEADER:
		return player_id == leader_player_id
	# 自选阶段：一号位领袖预览者可使用领袖技候选规则。
	return phase == PHASE_CUSTOM and get_preview_identity(player_id) == get_first_seat_identity()


## 判断武将是否已由另一名玩家最终确认；随机候选可以重叠，但最终身份局不允许两名玩家使用同一武将。
func _is_character_selected_by_other_player(player_id: int, character_id: String) -> bool:
	for selected_player_id_variant: Variant in _selections_by_player.keys():
		# 已确认玩家 ID；当前提交者自身的旧值不应被视为冲突。
		var selected_player_id: int = int(selected_player_id_variant)
		if selected_player_id != player_id and str(_selections_by_player.get(selected_player_id, "")) == character_id:
			return true
	return false


## 使用本局随机数生成器原地洗牌；保持相同 seed 下身份、牌堆和选将候选均可复现。
func _shuffle(values: Array[String]) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		# 与当前位置交换的随机索引；范围包含0与当前索引。
		var swap_index: int = _rng.randi_range(0, index)
		# 当前位置的临时武将 ID；交换后继续处理前一个位置。
		var temporary: String = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
