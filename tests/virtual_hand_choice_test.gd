extends Node

## 虚拟手牌替换选择回归。验证「技能声明的虚拟牌临时接管手牌区」这一可复用机制的完整表现链路：
## 真实手牌向左离场 → 虚拟候选以摸牌动画进入手牌区 → 选中占位牌后按请求声明的有序组合高亮合法目标
## → 权威端不再等待时虚拟牌向右离场 → 真实手牌以摸牌动画回归。
## 同一回归还验证取消重选时复用地重新对账候选集合，使同一套节点与状态机可以连续接管多次请求。

## 正式主场景稳定等待帧数；覆盖延迟开局提示与首轮界面节点初始化。
const SETTLE_FRAME_COUNT: int = 4

## 状态机等待上限帧数；远大于0.24秒入场与离场补间所需帧数，只在出现真实卡死时耗尽。
const MAX_WAIT_FRAMES: int = 300

## 第一张真实手牌实体 UID；进入虚拟手牌模式后必须整体离场。
const FIRST_HAND_UID: int = 7001

## 第二张真实手牌实体 UID；用于验证全部真实手牌都参与离场与回归，而不是只处理首张。
const SECOND_HAND_UID: int = 7002

## 首次虚拟请求编号；必须与注入快照的 current_choice_request.request_id 一致，否则界面会立刻判定请求失效。
const FIRST_REQUEST_ID: int = 501

## 取消重选后的虚拟请求编号；两次请求处于同一快照窗口内，因此沿用同一编号即可验证复用。
const SECOND_REQUEST_ID: int = 502

## 权威端不再等待的快照编号；与本地窗口编号不同即代表本次虚拟选择已经结束。
const CLOSED_REQUEST_ID: int = 999

## 虚拟候选的花色；视为使用的牌没有花色，界面必须隐藏角标而不是沿用实体牌面。
const VIRTUAL_SUIT: String = "none"

## 虚拟候选的点数；视为使用的牌没有点数，0表示无点数而不是最小点数。
const VIRTUAL_RANK: int = 0

## 第一个虚拟候选的合法目标组合；单一目标，用于验证“下一步目标”取自组合而不回退到全部目标。
const FIRST_CANDIDATE_TARGETS: Array = [[1]]

## 第二个虚拟候选的合法目标组合；两名有序目标，用于验证借刀类顺序组合在界面侧同样被完整表达。
const SECOND_CANDIDATE_TARGETS: Array = [[2, 3]]


## 延迟执行界面回归，确保测试节点已经进入场景树。
func _ready() -> void:
	call_deferred("_run")


## 注入含两张真实手牌的本地快照，依次验证虚拟手牌模式的进入、选牌与目标映射、退出与复用。
func _run() -> void:
	# 正式主场景资源；虚拟手牌替换必须覆盖玩家实际运行的桌面与手牌区容器。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	# 正式桌面实例；测试只注入只读快照，不启动合法身份对局。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	# 正式对局控制器；非法1人配置阻止自动对局和 AI 计时器干扰界面断言。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	match_controller.default_player_count = 1
	match_controller.local_human_player_id = 0
	match_controller.randomize_local_human_seat = false
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 启动主菜单遮罩；本测试随后注入局内快照，因此显式关闭遮罩以同步恢复局内菜单和全部局内控件。
	var startup_main_menu: MainMenu = main_instance.get_node("%MainMenu") as MainMenu
	startup_main_menu.visible = false
	await get_tree().process_frame
	# 真实手牌快照；进入虚拟手牌模式前必须先有两张实体牌，才能验证整体离场与回归。
	var slash_data: Dictionary = {"uid":FIRST_HAND_UID, "definition_id":"sha", "suit":"spade", "rank":7, "zone":"hand", "owner_id":0}
	# 第二张真实手牌快照；【闪】与【杀】牌名不同，确保回归后仍是同一批实体牌而不是新建占位牌。
	var dodge_data: Dictionary = {"uid":SECOND_HAND_UID, "definition_id":"shan", "suit":"heart", "rank":2, "zone":"hand", "owner_id":0}
	match_controller.state_changed.emit(_make_snapshot([slash_data, dodge_data], FIRST_REQUEST_ID))
	await get_tree().process_frame
	# 统一手牌视图映射；真实牌与虚拟占位牌共用同一份映射，因此必须整体对账而不是并行两套容器。
	var card_views: Dictionary = main_instance.get("_card_views") as Dictionary
	# 手牌容器；虚拟牌必须进入同一容器，才能复用原布局、滚动裁剪与交互链路。
	var hand_container: Node = main_instance.get("hand_container") as Node
	if not card_views.has(FIRST_HAND_UID) or not card_views.has(SECOND_HAND_UID):
		_fail("virtual_hand_baseline_hand")
		return
	# 真实手牌基线节点；虚拟牌入场后这些节点必须被释放，而不是仅被隐藏或压暗。
	var baseline_first_view: CardView = card_views.get(FIRST_HAND_UID) as CardView
	# 第二张真实手牌基线节点；两张都要释放，否则手牌区会残留真实牌面。
	var baseline_second_view: CardView = card_views.get(SECOND_HAND_UID) as CardView

	# ── 场景一：进入虚拟手牌模式 ─────────────────────────────────────────────
	# 首个虚拟候选；【杀】在本次请求中的合法目标组合只有一个目标1。
	var slash_candidate: Dictionary = _virtual_candidate(0, "sha", FIRST_CANDIDATE_TARGETS)
	# 第二个虚拟候选；【无中生有】声明的有序组合为两名目标，用于验证组合映射完整透传到界面。
	var wuzhong_candidate: Dictionary = _virtual_candidate(1, "wuzhong", SECOND_CANDIDATE_TARGETS)
	main_instance.call("_on_card_choice_requested", _virtual_request(FIRST_REQUEST_ID, [slash_candidate, wuzhong_candidate]))
	if not await _wait_until(func() -> bool: return bool(main_instance.get("_virtual_hand_choice_active"))):
		_fail("virtual_hand_entry_not_active")
		return
	# 虚拟牌视图映射；键为占位牌号，数量必须与请求声明的候选数量一致。
	var virtual_views: Dictionary = main_instance.get("_virtual_hand_views") as Dictionary
	if virtual_views.size() != 2:
		_fail("virtual_hand_view_count")
		return
	# 首个占位牌号；界面不得为虚拟候选分配任何真实牌 UID，否则会与实体牌冲突。
	var first_placeholder_uid: int = SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE
	# 第二个占位牌号；同一请求内按声明顺序递增。
	var second_placeholder_uid: int = SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE + 1
	for placeholder_uid: int in [first_placeholder_uid, second_placeholder_uid]:
		# 当前虚拟牌节点；必须已经进入手牌容器并且可交互，玩家操作方式与真实手牌完全一致。
		var virtual_view: CardView = virtual_views.get(placeholder_uid) as CardView
		if virtual_view == null or not is_instance_valid(virtual_view) or virtual_view.get_parent() != hand_container:
			_fail("virtual_hand_view_container")
			return
		if not virtual_view.is_interactable or not bool(virtual_view.get("_hide_suit_rank")):
			_fail("virtual_hand_view_face")
			return
		# 摸牌入场证据：新节点必须带非零运行时偏移，或该 UID 的入场补间仍在运行，而不是瞬间贴到布局位置。
		var gain_tween_running: bool = (main_instance.get("_local_hand_gain_tweens") as Dictionary).has(placeholder_uid)
		if virtual_view.hand_entry_offset == Vector2.ZERO and not gain_tween_running:
			_fail("virtual_hand_entry_animation")
			return
	# 等待一帧让离场节点的 queue_free 生效，再断言真实手牌已经离场而不是被隐藏。
	await get_tree().process_frame
	if card_views.has(FIRST_HAND_UID) or card_views.has(SECOND_HAND_UID):
		_fail("virtual_hand_real_cards_not_released")
		return
	if is_instance_valid(baseline_first_view) or is_instance_valid(baseline_second_view):
		_fail("virtual_hand_real_card_node_alive")
		return

	# ── 场景二：选中占位牌并读取该牌自己的合法目标 ──────────────────────────
	main_instance.call("_on_card_pressed", first_placeholder_uid)
	# 本地内联选择集；虚拟牌与真实牌共用同一份选择集，提交时上行占位牌号。
	var selected_uids: Array = main_instance.get("_inline_selected_card_uids") as Array
	if selected_uids.size() != 1 or int(selected_uids[0]) != first_placeholder_uid:
		_fail("virtual_hand_select_placeholder_uid")
		return
	# 选中态虚拟牌节点；必须复用真实手牌的选中表现，玩家才能确认自己选中了哪张可选牌。
	var selected_view: CardView = virtual_views.get(first_placeholder_uid) as CardView
	if selected_view == null or not selected_view.is_card_selected:
		_fail("virtual_hand_select_visual")
		return
	# 合法目标集合；必须取自该占位牌号声明的组合，而不是回退到请求的全部目标。
	var first_targets: Array = main_instance.call("_get_selectable_target_ids") as Array
	if first_targets.size() != 1 or int(first_targets[0]) != 1:
		_fail("virtual_hand_target_mapping_first")
		return
	# 取消本张选择后改选第二个候选；单选请求下未选中的其他候选由统一层保持禁用，
	# 因此先点击已选牌取消，再点击另一张，验证每张虚拟候选都按自己的声明映射提供目标。
	main_instance.call("_on_card_pressed", first_placeholder_uid)
	# 取消后的选择集；必须为空，避免把“点击第二张无效”误判成替换失败。
	var cleared_uids: Array = main_instance.get("_inline_selected_card_uids") as Array
	if not cleared_uids.is_empty():
		_fail("virtual_hand_select_clear")
		return
	main_instance.call("_on_card_pressed", second_placeholder_uid)
	# 改选后的选择集；仍然是单一占位牌号。
	var replaced_uids: Array = main_instance.get("_inline_selected_card_uids") as Array
	if replaced_uids.size() != 1 or int(replaced_uids[0]) != second_placeholder_uid:
		_fail("virtual_hand_select_second")
		return
	# 第二个候选的目标集合；两名有序组合的第一个目标，验证顺序组合不被打平为全集。
	var second_targets: Array = main_instance.call("_get_selectable_target_ids") as Array
	if second_targets.size() != 1 or int(second_targets[0]) != 2:
		_fail("virtual_hand_target_mapping_second")
		return

	# ── 场景三：请求结束，虚拟牌离场且真实手牌以摸牌动画回归 ────────────────
	match_controller.state_changed.emit(_make_snapshot([slash_data, dodge_data], CLOSED_REQUEST_ID))
	if not await _wait_until(func() -> bool: return (main_instance.get("_virtual_hand_views") as Dictionary).is_empty()):
		_fail("virtual_hand_exit_not_cleared")
		return
	if bool(main_instance.get("_virtual_hand_choice_active")):
		_fail("virtual_hand_exit_flag")
		return
	# 真实手牌回归证据：两张实体牌重新建立节点，并且走的是获得牌入场通道。
	if not await _wait_until(func() -> bool: return (main_instance.get("_card_views") as Dictionary).has(FIRST_HAND_UID)):
		_fail("virtual_hand_return_missing")
		return
	# 回归后的真实手牌节点；必须是新节点，证明离场时确实释放过而不是仅隐藏。
	var returning_first_view: CardView = (main_instance.get("_card_views") as Dictionary).get(FIRST_HAND_UID) as CardView
	if returning_first_view == null or not is_instance_valid(returning_first_view) or returning_first_view.get_parent() != hand_container:
		_fail("virtual_hand_return_container")
		return
	if not (main_instance.get("_card_views") as Dictionary).has(SECOND_HAND_UID):
		_fail("virtual_hand_return_second_missing")
		return
	# 回归入场证据：节点必须带非零运行时偏移或仍有入场补间，表现为“像摸牌一样”回到手牌区。
	var returning_gain_running: bool = (main_instance.get("_local_hand_gain_tweens") as Dictionary).has(FIRST_HAND_UID)
	if returning_first_view.hand_entry_offset == Vector2.ZERO and not returning_gain_running:
		_fail("virtual_hand_return_gain_animation")
		return
	# 占位牌号不得残留；否则下次真实手牌对账会把占位 UID 当作实体牌渲染。
	for placeholder_uid: int in [first_placeholder_uid, second_placeholder_uid]:
		if (main_instance.get("_card_views") as Dictionary).has(placeholder_uid):
			_fail("virtual_hand_placeholder_leftover")
			return

	# ── 场景四：同一机制可复用，取消重选时按新请求重新对账候选 ──────────────
	match_controller.state_changed.emit(_make_snapshot([slash_data, dodge_data], SECOND_REQUEST_ID))
	await get_tree().process_frame
	main_instance.call("_on_card_choice_requested", _virtual_request(SECOND_REQUEST_ID, [slash_candidate]))
	if not await _wait_until(func() -> bool: return (main_instance.get("_virtual_hand_views") as Dictionary).size() == 1):
		_fail("virtual_hand_reuse_entry")
		return
	# 取消后技能重新枚举候选：同一请求窗口内换成两个候选，界面必须增补新牌并保留仍在场的牌。
	main_instance.call("_on_card_choice_requested", _virtual_request(SECOND_REQUEST_ID, [slash_candidate, wuzhong_candidate]))
	if not await _wait_until(func() -> bool: return (main_instance.get("_virtual_hand_views") as Dictionary).size() == 2):
		_fail("virtual_hand_reuse_reconcile")
		return
	if not bool(main_instance.get("_virtual_hand_choice_active")):
		_fail("virtual_hand_reuse_active")
		return
	# 第二次退出必须同样干净收尾，证明状态机可以连续接管多次虚拟选择。
	match_controller.state_changed.emit(_make_snapshot([slash_data, dodge_data], CLOSED_REQUEST_ID))
	if not await _wait_until(func() -> bool: return (main_instance.get("_virtual_hand_views") as Dictionary).is_empty()):
		_fail("virtual_hand_reuse_exit")
		return
	if not await _wait_until(func() -> bool: return (main_instance.get("_card_views") as Dictionary).has(FIRST_HAND_UID) and (main_instance.get("_card_views") as Dictionary).has(SECOND_HAND_UID)):
		_fail("virtual_hand_reuse_return")
		return
	print("VIRTUAL_HAND_CHOICE_PASS")
	get_tree().quit(0)


## 按帧等待一个界面状态条件成立；返回 false 表示超过上限仍未成立，用于区分卡死与断言失败。
func _wait_until(condition: Callable, max_frames: int = MAX_WAIT_FRAMES) -> bool:
	for _frame_index: int in range(max_frames):
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return false


## 构造一个虚拟候选；字段与技能请求端口写出的可序列化数据完全一致，界面只按这些事实渲染。
func _virtual_candidate(candidate_index: int, definition_id: String, target_combinations: Array) -> Dictionary:
	# 占位牌号；由技能请求端口统一分配的高基数编号，不会与任何真实实体牌 UID 冲突。
	var placeholder_uid: int = SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE + candidate_index
	# 虚拟牌面；视为使用的牌没有花色与点数，也不属于任何真实牌区。
	var card_data: Dictionary = {
		"uid":placeholder_uid,
		"definition_id":definition_id,
		"suit":VIRTUAL_SUIT,
		"rank":VIRTUAL_RANK,
		"zone":"virtual_hand",
		"owner_id":0,
		"virtual_hand":true,
		"target_combinations":target_combinations.duplicate(true),
	}
	return {
		"uid":placeholder_uid,
		"owner_id":0,
		"zone":"virtual_hand",
		"slot":"",
		"visible":true,
		"virtual_hand":true,
		"card_data":card_data,
	}


## 构造虚拟手牌选择请求；与技能请求端口输出同构，界面据 context.virtual_hand 识别本次接管。
func _virtual_request(request_id: int, candidates: Array) -> Dictionary:
	# 占位牌号到完整有序目标组合的映射；字符串键兼容网络序列化后的字典结构。
	var target_combinations_by_card_id: Dictionary = {}
	# 全部候选声明的目标并集；作为映射缺失时的回退目标集合，规则端仍会复核提交结果。
	var fallback_target_ids: Array = []
	for candidate_variant: Variant in candidates:
		# 当前候选；只取本次请求声明的占位牌号与目标组合。
		var candidate: Dictionary = candidate_variant as Dictionary
		# 当前候选占位牌号键；界面按字符串键读取，与技能端口写入格式一致。
		var candidate_uid_key: String = str(int(candidate.get("uid", -1)))
		# 当前候选声明的完整有序目标组合。
		var combinations: Array = (candidate.get("card_data", {}) as Dictionary).get("target_combinations", []) as Array
		target_combinations_by_card_id[candidate_uid_key] = combinations.duplicate(true)
		for combination_variant: Variant in combinations:
			for target_id_variant: Variant in combination_variant as Array:
				# 当前目标 ID；去重后写入回退集合。
				var target_id: int = int(target_id_variant)
				if not fallback_target_ids.has(target_id):
					fallback_target_ids.append(target_id)
	return {
		"request_id":request_id,
		"chooser_id":0,
		"title":"自摸",
		"prompt":"请选择视为使用的牌，并为其指定目标",
		"choice_type":"card_target",
		"candidates":candidates,
		"target_ids":fallback_target_ids,
		"min_select":1,
		"max_select":1,
		"min_targets":1,
		"max_targets":1,
		"allow_cancel":true,
		"context":{
			"kind":"zimo_pick_effect",
			"virtual_hand":true,
			"target_combinations_by_card_id":target_combinations_by_card_id,
		},
	}


## 构造本地观察者快照；只包含虚拟手牌替换需要的手牌、阶段与运行时请求标识。
func _make_snapshot(hand_cards: Array, request_id: int) -> Dictionary:
	# 本地玩家快照；完整手牌仅对0号观察者公开。
	var local_player: Dictionary = {
		"player_id":0,
		"seat_number":1,
		"display_name":"本地玩家",
		"character_id":"qingque",
		"identity":"leader",
		"hp":3,
		"max_hp":3,
		"alive":true,
		"chained":false,
		"hand_count":hand_cards.size(),
		"hand":hand_cards.duplicate(true),
		"equipment":{},
		"judgment_area":[],
		"wooden_ox_storage":[],
		"wooden_ox_storage_count":0,
	}
	return {
		"players":[local_player],
		"current_player_id":1,
		"current_phase":"choice",
		"current_choice_request":{"request_id":request_id, "actor_id":0},
		"local_pending_choice_request_ids":[],
		"turn_number":1,
		"draw_pile_count":100,
		"discard_pile_count":0,
		"game_over":false,
	}


## 输出稳定失败原因并以非0状态退出，便于命令行定位具体虚拟手牌断言。
func _fail(reason: String) -> void:
	printerr("VIRTUAL_HAND_CHOICE_FAIL %s" % reason)
	get_tree().quit(1)
