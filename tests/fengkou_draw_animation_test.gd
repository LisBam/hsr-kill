extends Node

## 【风口】批量获得后立刻询问时的摸牌动画回归。
##
## 覆盖的真实时序：一次 `draw()` 摸到两张牌 → 控制器在同一段结算内派发 `cardsGainedBatchAfter` →
## 【风口】第一段把询问延后到下一个结算边界并弹出牌选择请求，而**包含这两张牌的权威快照此刻还没有发出**。
## 桌面在这一帧收到询问后会按上一份快照重新对账手牌，若把「当前快照里没有这张牌」当成「牌已经离开手牌」，
## 刚登记的门闸与待起飞批次会被整批丢弃，玩家看到的就是「摸牌跳过动画、牌直接出现在手牌区」。
## 因此本用例必须在真实牌桌 + 真实控制器 + 真实 `draw()` 上运行，注入式快照无法复现该帧的先后关系。

## 主场景稳定帧数；保证武将视图与手牌容器完成初始化。
const SETTLE_FRAME_COUNT: int = 4
## 摸牌堆张数；必须不少于本用例摸牌张数，否则权威摸牌会因牌堆为空提前结束。
const DRAW_PILE_SIZE: int = 10
## 本次摸牌张数；两张即达到【风口】第一段的最小批次张数（2），从而在同一帧建立询问。
const DRAW_COUNT: int = 2
## 摸牌与延后询问恢复之间允许等待的帧数；延后结算在下一帧被唤醒。
const CHOICE_WAIT_FRAMES: int = 8
## 快照广播后允许等待的帧数；飞行在布局完成的那一帧启动。
const FLIGHT_WAIT_FRAMES: int = 10


## 延迟运行，避免主场景自身的就绪流程与用例断言同时写入。
func _ready() -> void:
	call_deferred("_run")


## 建立真实对局状态、安装【风口】、真实摸牌两张，并断言飞行没有被询问界面取消。
func _run() -> void:
	# 正式主场景；必须使用真实牌桌与真实控制器。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	# 主场景实例；作为测试根节点子节点运行完整界面初始化流程。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	# 对局控制器；非法1人配置阻止自动身份局，用例自己建立权威状态。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	match_controller.default_player_count = 1
	match_controller.local_human_player_id = 0
	match_controller.randomize_local_human_seat = false
	# 流程间隔归零；让摸牌与延后询问在本用例的时间预算内完成。
	match_controller.game_flow_interval_seconds = 0.0
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 主菜单覆盖层；隐藏后牌桌可见，但不会触发开局流程。
	(main_instance.get_node("%MainMenu") as MainMenu).visible = false
	# 卡牌表现层；飞行牌面与门闸的最终归属组件。
	var animation_layer: CardUseAnimationLayer = main_instance.get_node("%CardUseAnimationLayer") as CardUseAnimationLayer
	if not _prepare_authoritative_state(match_controller):
		_fail("state_setup")
		return
	# 【风口】安装结果；安装失败时本用例的前提不成立。
	if not _install_fengkou(match_controller, 0):
		_fail("fengkou_install")
		return
	# 初始快照；手牌为空，使随后两张牌的落位判定不受既有手牌干扰。
	match_controller._emit_state()
	await get_tree().process_frame
	await get_tree().process_frame
	# 真实摸牌；批次获得会在同一段结算内触发【风口】第一段。
	match_controller.draw(0, DRAW_COUNT, false)
	# 摸到的实体 UID；顺序即牌堆摸取顺序。
	var drawn_uids: Array[int] = []
	for hand_card: CardInstance in match_controller.state.get_player(0).hand:
		drawn_uids.append(hand_card.uid)
	if drawn_uids.size() != DRAW_COUNT:
		_fail("draw_count=%d" % drawn_uids.size())
		return
	# 门闸登记结果；两张牌必须在同一帧各自登记门闸，且批次仍在等待快照布局。
	var gates: Dictionary = main_instance.get("_local_hand_gain_flight_gates") as Dictionary
	# 待起飞批次；本机 `draw()` 批次在快照到达后才起飞。
	var pending_batches: Dictionary = main_instance.get("_pending_local_draw_batches") as Dictionary
	if gates.size() != DRAW_COUNT or pending_batches.is_empty():
		_fail("flight_gate_missing gates=%s pending=%s" % [gates, pending_batches])
		return
	for drawn_uid: int in drawn_uids:
		if not gates.has(drawn_uid):
			_fail("flight_gate_uid_missing uid=%d gates=%s" % [drawn_uid, gates])
			return
	# 等待【风口】的延后询问出现；请求创建时会用上一份快照重新对账手牌，正是本次回归的关键帧。
	var has_choice: bool = await _await_clause1_choice(match_controller)
	if not has_choice:
		_fail("fengkou_choice_missing")
		return
	# 询问帧之后的门闸；绝不能被「旧快照里没有这张牌」清掉，否则整批摸牌飞行被丢弃。
	var gates_after_choice: Dictionary = main_instance.get("_local_hand_gain_flight_gates") as Dictionary
	if gates_after_choice.size() != DRAW_COUNT or (main_instance.get("_pending_local_draw_batches") as Dictionary).is_empty():
		_fail("flight_cancelled_by_choice gates=%s pending=%s" % [gates_after_choice, main_instance.get("_pending_local_draw_batches")])
		return
	# 权威快照广播；正式对局由结算边界的同一入口发出，本用例显式触发。
	match_controller._emit_state()
	for _frame_index: int in range(FLIGHT_WAIT_FRAMES):
		await get_tree().process_frame
	# 飞行牌面数量；两张牌都必须真正起飞，而不是直接出现在手牌槽位。
	if animation_layer._transfer_cards.size() != DRAW_COUNT:
		_fail("flight_not_started transfers=%d viewport_gates=%s" % [animation_layer._transfer_cards.size(), main_instance.get("_local_hand_gain_flight_gates")])
		return
	print("FENGKOU_DRAW_PASS draw=%d flight=%d choice=pending" % [DRAW_COUNT, animation_layer._transfer_cards.size()])
	get_tree().quit(0)


## 建立两名玩家与非空摸牌堆的权威状态；返回false表示状态未就绪。
func _prepare_authoritative_state(match_controller: MatchController) -> bool:
	match_controller.state = GameState.new()
	match_controller.state.match_id = "fengkou-draw-animation-test"
	match_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	match_controller.state.turn_number = 1
	match_controller.state.round_number = 1
	match_controller.state.current_player_id = 0
	match_controller.state.current_phase = "play"
	match_controller.state.phase_index = 3
	for player_id: int in range(2):
		# 当前测试玩家；一号位为本地玩家，二号位提供「其他角色」语义。
		var player: PlayerState = PlayerState.new(player_id, "风口测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else "rebel"
		player.identity_revealed = true
		player.max_hp = 3
		player.hp = 3
		match_controller.state.players.append(player)
	for index: int in range(DRAW_PILE_SIZE):
		match_controller.state.draw_pile.append(CardInstance.new("shan", "heart", index % 13 + 1))
	match_controller._rebuild_match_rule_services_and_root_event()
	match_controller._pending_card_choice.clear()
	match_controller._deferred_skill_settlements.clear()
	return match_controller.state.players.size() == 2 and not match_controller.state.draw_pile.is_empty()


## 按正式 bind/install 顺序为指定玩家安装【风口】；返回false表示技能创建失败。
func _install_fengkou(match_controller: MatchController, player_id: int) -> bool:
	# 技能运行时实例；数据库必须能按稳定ID创建独立对象。
	var skill: SkillDefinition = GameDatabase.create_skill("fengkou")
	if skill == null:
		return false
	skill.bind(match_controller, player_id)
	# 当前玩家技能表；与正式固有技能安装使用同一张表，使时机订阅与失效路径完全一致。
	var player_skills: Dictionary = match_controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills["fengkou"] = skill
	match_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return true


## 等待【风口】第一段的延后询问出现；返回false表示等待上限内依然没有请求。
func _await_clause1_choice(match_controller: MatchController) -> bool:
	for _attempt: int in range(CHOICE_WAIT_FRAMES):
		if match_controller.has_pending_card_choice():
			return true
		await get_tree().process_frame
	return match_controller.has_pending_card_choice()


## 以可见失败标记结束用例；避免与看门狗或成功出口重复退出。
func _fail(message: String) -> void:
	printerr("FENGKOU_DRAW_FAIL %s" % message)
	get_tree().quit(1)
