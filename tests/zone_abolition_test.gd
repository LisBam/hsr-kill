extends Node

## 装备栏、整个装备区与判定区废除专项回归。覆盖时机取消、单栏限制、整区兼容、移牌防线、序列化与废除占位效果。

## 本测试共用的权威对局控制器；所有区域变化均通过正式公开端口执行。
var _controller: MatchController

## 已捕获的废除与恢复时机顺序；每项用例显式清空，不与移牌时机混合。
var _captured_timings: Array[String] = []


## 延迟一帧开始测试，确保卡牌数据库与全局类名已完成扫描。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行权威规则与客户端占位效果断言；任一失败立即非零退出。
func _run() -> void:
	_create_controller()
	if not _test_equipment_slot_and_area_abolition():
		return
	if not _test_judgment_area_abolition():
		return
	if not await _test_abolition_views():
		return
	print("ZONE_ABOLITION_PASS")
	get_tree().quit(0)


## 创建与正式对局相同的控制器、时机总线、AI协调器和离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则时机总线；用于捕获可取消Before与生效After事件。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；对局控制器的完整初始化依赖，本测试不使用其策略。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；快照发送沿用正式单机路径。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.game_flow_interval_seconds = 0.0
	_reset_state()


## 创建两名存活角色的最小身份局状态，并重建全部规则服务。
func _reset_state() -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "zone-abolition"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.turn_number = 1
	for player_id: int in range(2):
		# 当前测试角色；0号领袖与1号反贼使用固定公开身份。
		var player: PlayerState = PlayerState.new(player_id, "区域测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else "rebel"
		player.identity_revealed = true
		player.character_id = "wandi"
		player.character_generation = 1
		player.max_hp = 5
		player.hp = 5
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()


## 校验Before取消、单栏废除、整区废除、分栏恢复与旧存档兼容。
func _test_equipment_slot_and_area_abolition() -> bool:
	# 区域所属角色；预置武器、防具与进攻坐骑以验证部分废除不会清空其他栏位。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.hp = 4
	# 武器栏诸葛连弩；第一次废除会被Before取消并保留。
	var weapon: CardInstance = _equipment_card("zhuge", "spade", 1, 0)
	# 防具栏白银狮子；与武器一起废除时进入弃牌堆并按标准离区效果回复1点体力。
	var armor: CardInstance = _equipment_card("baiyin", "club", 2, 0)
	# 进攻坐骑大宛；部分废除后继续留在装备区，整区废除时才离区。
	var offensive_mount: CardInstance = _equipment_card("dawan", "spade", 3, 0)
	owner.equipment = {"weapon":weapon, "armor":armor, "offensive_mount":offensive_mount}
	_controller.event_bus.subscribe("disableEquipBefore", self, _cancel_and_capture_timing)
	if _controller.set_player_equipment_slots_abolished(0, ["weapon"], true, "cancel_probe", 1) or not owner.equipment.has("weapon") or owner.is_equipment_slot_abolished("weapon") or _captured_timings != ["disableEquipBefore"]:
		return _fail("disable_equip_cancel=%s/%s/%s" % [owner.equipment.keys(), owner.get_abolished_equipment_slot_ids(), _captured_timings])
	_controller.event_bus.unsubscribe_owner(self)
	_captured_timings.clear()
	_subscribe_zone_timings()
	if not _controller.set_player_equipment_slots_abolished(0, ["armor", "weapon", "weapon", "unknown"], true, "partial", 1):
		return _fail("partial_disable_rejected")
	if owner.equipment.has("weapon") or owner.equipment.has("armor") or not owner.equipment.has("offensive_mount") or owner.equipment_area_abolished or owner.get_abolished_equipment_slot_ids() != ["weapon", "armor"] or not _controller.is_player_equipment_slot_abolished(0, "weapon") or _controller.get_player_abolished_equipment_slot_ids(0) != ["weapon", "armor"] or not _controller.state.discard_pile.has(weapon) or not _controller.state.discard_pile.has(armor) or owner.hp != owner.max_hp:
		return _fail("partial_disable_state=%s/%s/%s/hp=%d" % [owner.equipment.keys(), owner.get_abolished_equipment_slot_ids(), owner.equipment_area_abolished, owner.hp])
	# 装备牌的固定目标数组；显式使用强类型数组以匹配卡牌规则服务的公开接口。
	var owner_target_ids: Array[int] = [0]
	# 废除武器栏与可用进攻坐骑的规则校验结果；部分废除不得误禁止其他类型。
	var weapon_error: String = _controller.card_rules.validate_virtual_use(0, "zhuge", owner_target_ids)
	# 进攻坐骑当前合法性；空字符串表示仍可正常替换该栏装备。
	var mount_error: String = _controller.card_rules.validate_virtual_use(0, "dawan", owner_target_ids)
	if weapon_error.is_empty() or not mount_error.is_empty():
		return _fail("partial_rule=%s/%s" % [weapon_error, mount_error])
	# 伪造位于处理区的武器；统一移牌边界必须在最终阶段再次拒绝废除栏位。
	var blocked_processing_weapon: CardInstance = CardInstance.new("qinggang", "club", 4)
	blocked_processing_weapon.zone = "processing"
	_controller.state.processing_area.append(blocked_processing_weapon)
	if _controller._move_card_with_timings(blocked_processing_weapon, "equipment", 0, "abolished_boundary", _controller.state.current_event_id, "weapon") != null or not _controller.state.processing_area.has(blocked_processing_weapon):
		return _fail("equipment_move_boundary")
	if not _controller.set_player_equipment_slots_abolished(0, ["weapon"], false, "partial_restore", 1) or owner.is_equipment_slot_abolished("weapon") or not owner.is_equipment_slot_abolished("armor") or owner.equipment.has("weapon"):
		return _fail("partial_restore=%s" % owner.get_abolished_equipment_slot_ids())
	# 未知装备栏位不属于五个基础栏；即使对应武器栏已经恢复，最终移动边界也不能创建异常字典键。
	if _controller._move_card_with_timings(blocked_processing_weapon, "equipment", 0, "invalid_slot_boundary", _controller.state.current_event_id, "unknown") != null or not _controller.state.processing_area.has(blocked_processing_weapon):
		return _fail("equipment_invalid_slot_boundary")
	if not _controller.set_player_zones_abolished(0, true, false, "full_disable", 1) or not owner.equipment_area_abolished or owner.get_abolished_equipment_slot_ids() != PlayerState.EQUIPMENT_SLOT_ORDER or owner.equipment.has("offensive_mount") or not _controller.state.discard_pile.has(offensive_mount):
		return _fail("full_disable=%s/%s" % [owner.equipment_area_abolished, owner.get_abolished_equipment_slot_ids()])
	# 省略目标栏位的处理区宝物；底层兼容规则会解析为宝物栏，也必须受整区废除约束。
	var blocked_default_slot_treasure: CardInstance = CardInstance.new("muniu", "diamond", 5)
	blocked_default_slot_treasure.zone = "processing"
	_controller.state.processing_area.append(blocked_default_slot_treasure)
	if _controller._move_card_with_timings(blocked_default_slot_treasure, "equipment", 0, "abolished_default_slot", _controller.state.current_event_id) != null or not _controller.state.processing_area.has(blocked_default_slot_treasure):
		return _fail("equipment_default_slot_boundary")
	# 整区废除公开快照；新字典和旧布尔值必须一致且能从权威数据恢复。
	var public_snapshot: Dictionary = owner.to_dict(1, false)
	# 从权威快照重建的角色；用于验证单栏字典持久化。
	var restored_owner: PlayerState = PlayerState.from_authoritative_dict(owner.to_dict(0, true))
	if (public_snapshot.get("abolished_equipment_slots", {}) as Dictionary).size() != 5 or not restored_owner.equipment_area_abolished or restored_owner.get_abolished_equipment_slot_ids() != PlayerState.EQUIPMENT_SLOT_ORDER:
		return _fail("equipment_serialization=%s/%s" % [public_snapshot.get("abolished_equipment_slots", {}), restored_owner.get_abolished_equipment_slot_ids()])
	# 仅含旧式equipment_area_abolished的存档数据；迁移后应自动补齐五个废除栏位。
	var legacy_snapshot: Dictionary = owner.to_dict(0, true)
	legacy_snapshot.erase("abolished_equipment_slots")
	# 旧存档重建角色；用于保证新机制不会将整区废除误恢复为普通空栏。
	var legacy_restored_owner: PlayerState = PlayerState.from_authoritative_dict(legacy_snapshot)
	if legacy_restored_owner.get_abolished_equipment_slot_ids() != PlayerState.EQUIPMENT_SLOT_ORDER:
		return _fail("legacy_equipment_migration=%s" % legacy_restored_owner.get_abolished_equipment_slot_ids())
	# 运行期旧式角色状态；直接保留整区布尔值时，公开快照也必须规范化补齐五栏供旧局面继续显示。
	var legacy_runtime_owner: PlayerState = PlayerState.new(9, "旧式区域状态")
	legacy_runtime_owner.equipment_area_abolished = true
	# 旧式运行期状态生成的公开快照；用于校验客户端不依赖缺失的栏位字典自行猜测。
	var legacy_runtime_snapshot: Dictionary = legacy_runtime_owner.to_dict(0, false)
	if not bool(legacy_runtime_snapshot.get("equipment_area_abolished", false)) or (legacy_runtime_snapshot.get("abolished_equipment_slots", {}) as Dictionary).size() != 5:
		return _fail("legacy_runtime_snapshot=%s" % legacy_runtime_snapshot.get("abolished_equipment_slots", {}))
	if not _controller.set_player_zones_abolished(0, false, false, "full_restore", 1) or owner.equipment_area_abolished or not owner.get_abolished_equipment_slot_ids().is_empty() or not owner.equipment.is_empty():
		return _fail("full_restore=%s/%s" % [owner.equipment_area_abolished, owner.get_abolished_equipment_slot_ids()])
	return true


## 校验判定区废除会弃置既有延时锦囊、拒绝新牌进入并发布完整时机。
func _test_judgment_area_abolition() -> bool:
	# 判定区所属角色；废除前预置一张【乐不思蜀】。
	var owner: PlayerState = _controller.state.get_player(0)
	# 待离区的延时锦囊；废除后应经标准弃牌移动进入弃牌堆。
	var delayed_card: CardInstance = CardInstance.new("lebu", "heart", 6)
	delayed_card.zone = "judgment"
	delayed_card.owner_id = 0
	owner.judgment_area.append(delayed_card)
	if not _controller.set_player_judgment_area_abolished(0, true, "judge_disable", 1) or not owner.judgment_area_abolished or not owner.judgment_area.is_empty() or not _controller.state.discard_pile.has(delayed_card):
		return _fail("judgment_disable")
	_controller.state.current_player_id = 1
	# 向已废除判定区使用【乐不思蜀】的规则错误；非空表示预览已正确拒绝。
	# 延时锦囊的固定目标数组；强类型数据可直接复用规则服务的目标合法性入口。
	var judgment_target_ids: Array[int] = [0]
	# 废除判定区后的延时锦囊规则错误；非空表示规则预览已正确拒绝。
	var delayed_error: String = _controller.card_rules.validate_virtual_use(1, "lebu", judgment_target_ids)
	if delayed_error.is_empty():
		return _fail("judgment_rule_allowed")
	# 位于处理区的延时锦囊；统一移牌边界必须在规则预览之后仍拒绝进入。
	var blocked_delayed_card: CardInstance = CardInstance.new("bingliang", "spade", 7)
	blocked_delayed_card.zone = "processing"
	_controller.state.processing_area.append(blocked_delayed_card)
	if _controller._move_card_with_timings(blocked_delayed_card, "judgment", 0, "abolished_boundary", _controller.state.current_event_id) != null or not _controller.state.processing_area.has(blocked_delayed_card):
		return _fail("judgment_move_boundary")
	if not _controller.set_player_judgment_area_abolished(0, false, "judge_restore", 1) or owner.judgment_area_abolished or not owner.judgment_area.is_empty():
		return _fail("judgment_restore")
	# 全部区域专属时机顺序；弃牌移动的通用时机不在本捕获列表中。
	var expected_timings: Array[String] = [
		"disableEquipBefore", "disableEquipAfter",
		"enableEquipAfter",
		"disableEquipBefore", "disableEquipAfter",
		"enableEquipAfter",
		"disableJudgeBefore", "disableJudgeAfter",
		"enableJudgeAfter",
	]
	if _captured_timings != expected_timings:
		return _fail("zone_timing_order=%s" % [_captured_timings])
	return true


## 校验本地装备栏与判定区组件使用独立废除占位，不把占位伪造为实体卡牌。
func _test_abolition_views() -> bool:
	# 本地装备栏组件；固定150×148尺寸与正式桌面布局一致。
	var equipment_view: EquipmentStackView = EquipmentStackView.new()
	equipment_view.size = Vector2(150.0, 148.0)
	add_child(equipment_view)
	# 无装备候选数组；废除占位不参与实体装备选择。
	var empty_candidate_uids: Array[int] = []
	# 无已选装备数组；用于确保占位效果不伪造选择状态。
	var empty_selected_uids: Array[int] = []
	equipment_view.configure({}, 0, empty_candidate_uids, empty_selected_uids, {"weapon":true, "treasure":true})
	await get_tree().process_frame
	# 废除武器栏横条；应保留固定栏位并显示“已废除”文本。
	var abolished_weapon_row: Button = equipment_view.get_row("weapon")
	# 废除宝物栏横条；空宝物栏也不得因没有实体装备而隐藏废除效果。
	var abolished_treasure_row: Button = equipment_view.get_row("treasure")
	if abolished_weapon_row == null or abolished_treasure_row == null or not equipment_view.is_slot_abolished("weapon") or equipment_view.is_slot_equipped("weapon") or not _row_contains_text(abolished_weapon_row, "已废除"):
		return _fail("equipment_abolition_view")
	# 判定区标记组件；空判定区废除时仍要显示独立“废”菱形。
	var judgment_view: JudgmentZoneView = JudgmentZoneView.new()
	judgment_view.size = Vector2(160.0, 24.0)
	add_child(judgment_view)
	# 空判定牌名数组；废除标记由独立状态绘制，不写入伪造的牌名。
	var empty_judgment_names: Array[String] = []
	judgment_view.configure(empty_judgment_names, true)
	await get_tree().process_frame
	if not judgment_view.visible or not judgment_view.is_abolished() or judgment_view.get_abolished_marker_rect().size != Vector2.ONE * judgment_view.marker_size or not _node_tree_contains_label(judgment_view, "废"):
		return _fail("judgment_abolition_view")
	equipment_view.queue_free()
	judgment_view.queue_free()
	return true


## 创建一张已位于指定角色装备区的测试实体牌。
func _equipment_card(definition_id: String, suit: String, rank: int, owner_id: int) -> CardInstance:
	# 新装备实体；区域与所属者显式设置，使移牌历史可正确记录来源。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "equipment"
	card.owner_id = owner_id
	return card


## 注册本专项需要的六个废除/恢复时机；不捕获通用移牌时机。
func _subscribe_zone_timings() -> void:
	for event_name: String in ["disableEquipBefore", "disableEquipAfter", "enableEquipAfter", "disableJudgeBefore", "disableJudgeAfter", "enableJudgeAfter"]:
		_controller.event_bus.subscribe(event_name, self, _capture_timing)


## 捕获并取消首次装备栏废除前时机；用于验证取消时不改状态也不弃牌。
func _cancel_and_capture_timing(event: RuleEvent) -> void:
	_captured_timings.append(event.name)
	event.cancel()


## 捕获一条已生效的区域废除或恢复时机名。
func _capture_timing(event: RuleEvent) -> void:
	_captured_timings.append(event.name)


## 检查装备横条的子富文本是否包含指定文字；不依赖动态节点名。
func _row_contains_text(row: Button, expected_text: String) -> bool:
	if row == null:
		return false
	for child: Node in row.get_children():
		if child is RichTextLabel and expected_text in (child as RichTextLabel).text:
			return true
	return false


## 递归检查组件节点树中是否存在指定Label文本；判定菱形的文字与背景为兄弟节点。
func _node_tree_contains_label(root: Node, expected_text: String) -> bool:
	for child: Node in root.get_children():
		if child is Label and (child as Label).text == expected_text:
			return true
		if _node_tree_contains_label(child, expected_text):
			return true
	return false


## 输出稳定失败标签并以非零状态退出；返回false便于调用方立即中止。
func _fail(message: String) -> bool:
	printerr("ZONE_ABOLITION_FAIL %s" % message)
	get_tree().quit(1)
	return false
