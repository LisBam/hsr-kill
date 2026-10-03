extends Node

## 专属锦囊牌与不可知置牌机制专项回归。
## 逐条覆盖两个机制底座：卡牌专属字段与校验口径、按定义造实体牌入堆、隐藏事实的私有承载与广播边界、
## 牌堆位次置牌端口、位次询问的三选项交互协议，以及「未选牌时位次不可确认」的操作区内联可用性。
## 本用例不认识任何具体卡牌或技能，全部断言都通过通用端口与通用快照字段完成。

## 测试专用设置文件；本用例修改的持久化偏好不会写入玩家正式配置。
const TEST_SETTINGS_FILE_PATH: String = "user://exclusive_card_private_placement_test_settings.cfg"

## 测试使用的玩家数量；3 人局足以覆盖“其他观察者与 AI 快照都拿不到私有事实”的多观察者断言。
const TEST_PLAYER_COUNT: int = 3

## 用于插入牌堆的稳定卡牌定义 ID；必须是数据库中真实存在的普通牌，避免依赖尚未制作的内容。
const PROBE_DEFINITION_ID: String = "sha"

## 位次询问协议中的三个稳定选项 ID；与规则层常量逐字一致，任一处漂移都会让本用例失败。
const OPTION_TOP_ID: String = "pile_slot_1"

## 位次询问的第二个稳定选项 ID：置于牌堆顶第二张。
const OPTION_SECOND_ID: String = "pile_slot_2"

## 位次询问的取消选项 ID；它不能作为“已确认”的位次提交。
const OPTION_CANCEL_ID: String = "cancel"

## 位次询问的玩家可见标签；与来源需求原文「牌堆顶第一张 / 牌堆顶第二张 / 取消」逐字一致。
const OPTION_TOP_LABEL: String = "牌堆顶第一张"

## 位次询问的第二个玩家可见标签。
const OPTION_SECOND_LABEL: String = "牌堆顶第二张"

## 位次询问的取消按钮玩家可见标签。
const OPTION_CANCEL_LABEL: String = "取消"

## 私有置牌事实的键名；与 MatchController 常量逐字一致，用于逐字段断言落盘内容。
const PRIVATE_KEY_CARD_UID: String = "card_uid"

## 私有置牌事实的位次键名。
const PRIVATE_KEY_POSITION: String = "position"

## 私有置牌事实的回合角色键名。
const PRIVATE_KEY_TURN_PLAYER_ID: String = "turn_player_id"

## 私有置牌事实的回合号键名。
const PRIVATE_KEY_TURN_NUMBER: String = "turn_number"

## 位次询问的选择类型标识；与规则层 MatchController.CARD_POSITION_CHOICE_TYPE 逐字一致。
const INLINE_CHOICE_TYPE: String = "card_position"

## 正式桌面操作行的场景路径；内联询问的三个按钮都渲染在这一行里。
const ACTION_ROW_PATH: String = "InteractionPanel/InteractionVBox/ActionRow"

## 规则层声明的取消选项被渲染成的通用取消按钮路径；位次询问不得再生成该按钮，否则玩家会看到两个取消。
const INLINE_CANCEL_BUTTON_PATH: String = "InteractionPanel/InteractionVBox/ActionRow/InlineControlCancelButton"

## 位次询问在操作行中允许出现的可见按钮数量；两项位次加一项取消，不多不少。
const INLINE_ACTION_BUTTON_COUNT: int = 3

## 正式主场景初始化所需的稳定等待帧数；覆盖主菜单遮罩与局内控件的一次完整布局。
const UI_SETTLE_FRAME_COUNT: int = 4

## 测试前设置文件路径；结束时恢复，禁止污染玩家正式配置。
var _original_settings_file_path: String = "user://game_settings.cfg"

## 测试前“控制所有角色”设置；结束时恢复进入测试前实际读取到的值，而不是固定恢复默认值。
var _original_control_all_characters_enabled: bool = false

## 测试使用的权威控制器；按正式子组件名称装配。
var _controller: MatchController

## 本次已发出的公共日志文本；用于断言秘密放置不写对局记录。
var _captured_logs: Array[String] = []

## 本次已发出的卡牌区域表现事件；用于断言秘密放置不产生公开表现。
var _captured_transfers: Array[Dictionary] = []


## 延迟执行，确保自动加载与全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证内容口径、入堆端口、私有事实、置牌端口、选择协议与界面可用性。
func _run() -> void:
	_begin_settings_isolation()
	_log_progress("card_field")
	if not _test_exclusive_card_field_and_deck_disjointness():
		return
	_log_progress("database_validation")
	if not _test_game_database_validation_is_clean():
		return
	if not await _start_playable_match():
		return
	# 公共日志与表现事件的可观测出口；两者都只在正式规则动作中发出，用于对比秘密放置前后的差值。
	_controller.log_added.connect(_on_log_added)
	_controller.card_transfer_requested.connect(_on_card_transfer_requested)
	_log_progress("insert_pile")
	if not await _test_insert_card_into_draw_pile():
		return
	_log_progress("private_fact")
	if not await _test_private_pile_placement_fact():
		return
	_log_progress("broadcast_boundary")
	if not await _test_secret_placement_broadcast_boundary():
		return
	_log_progress("position_protocol")
	if not await _test_position_request_protocol():
		return
	_log_progress("inline_usability")
	if not await _test_inline_three_option_usability():
		return
	_restore_settings()
	print("EXCLUSIVE_CARD_PRIVATE_PLACEMENT_PASS card_field+validation+insert_pile+private_fact+broadcast_boundary+position_protocol+inline_usability")
	get_tree().quit(0)


## 输出阶段进度；失败时用于定位停滞在哪个用例，不参与任何断言，也不影响 PASS 判定。
func _log_progress(stage: String) -> void:
	print("EXCLUSIVE_CARD_STAGE %s" % stage)


## 捕获公共日志；只统计条数，不参与规则状态。
func _on_log_added(message: String) -> void:
	_captured_logs.append(message)


## 捕获公开表现事件；秘密放置必须一条都不产生。
func _on_card_transfer_requested(card_data: Dictionary, source_player_id: int, source_zone: String, target_player_id: int, target_zone: String) -> void:
	_captured_transfers.append({
		"card_data":card_data.duplicate(true),
		"source_player_id":source_player_id,
		"source_zone":source_zone,
		"target_player_id":target_player_id,
		"target_zone":target_zone,
	})


## 验证卡牌专属字段的读取口径，以及「没有任何牌堆引用专属牌」的内容不变量。
## 断言要点：
## ① 静态元数据与语义读取入口逐字一致，不存在绕过元数据的第二条口径；
## ② 非专属牌一律为 false，因此既有卡牌行为完全不变；
## ③ 专属牌必须自带合法牌面声明——它没有牌堆条目，牌面只能来自卡牌文件；
## ④ 任何牌堆条目都不得引用一张 exclusive 牌（专属牌只能由技能在运行时加入游戏）。
func _test_exclusive_card_field_and_deck_disjointness() -> bool:
	# 数据库中全部专属牌 ID；本用例不白名单具体牌名，只断言读取口径与两条不变量。
	var exclusive_definition_ids: Array[String] = []
	for card_id_variant: Variant in GameDatabase.cards.keys():
		# 当前卡牌稳定 ID；用于读取静态元数据与定义对象。
		var card_id: String = str(card_id_variant)
		# 当前卡牌定义对象；缺失时说明数据库索引与定义表不同步。
		var card_definition: CardDefinition = GameDatabase.get_card_definition(card_id)
		if card_definition == null:
			return _fail("card_definition_missing id=%s" % card_id)
		# 静态元数据；与语义读取入口必须给出同一答案。
		var definition_metadata: Dictionary = GameDatabase.get_card(card_id)
		if bool(definition_metadata.get("exclusive", false)) != card_definition.is_exclusive():
			return _fail("exclusive_reader_mismatch id=%s" % card_id)
		if not card_definition.is_exclusive():
			continue
		exclusive_definition_ids.append(card_id)
		# 专属牌自带牌面；缺少或非法时入堆端口只能退回权威随机牌面，与内容声明的牌面不符。
		if not CardInstance.is_valid_suit(str(definition_metadata.get("suit", ""))) or not CardInstance.is_valid_rank(int(definition_metadata.get("rank", 0))):
			return _fail("exclusive_card_without_declared_face id=%s suit=%s rank=%d" % [card_id, str(definition_metadata.get("suit", "")), int(definition_metadata.get("rank", 0))])
	# 至少存在一张专属牌；否则下面的“牌堆反向不变量”会退化成空断言而失去意义。
	if exclusive_definition_ids.is_empty():
		return _fail("no_exclusive_card_registered")
	# 探针定义；直接构造目标基类，验证 exclusive 为真时的读取结果与 false 严格对称。
	var probe_definition: CardDefinition = CardDefinition.new({
		"id":"probe_exclusive_definition",
		"original_name":"探针",
		"custom_name":"探针",
		"type":"trick",
		"subtype":"delayed",
		"effect_id":"probe_exclusive_effect",
		"target_mode":"self",
		"description":"探针定义，仅用于验证专属字段读取口径。",
		"exclusive":true,
	})
	if not probe_definition.is_exclusive():
		return _fail("probe_definition_not_exclusive")
	# 缺省探针；完全没有 exclusive 键时必须回退 false。
	var default_probe: CardDefinition = CardDefinition.new({"id":"probe_default_definition"})
	if default_probe.is_exclusive():
		return _fail("default_probe_should_not_be_exclusive")
	# 牌堆反向不变量；任何牌堆都不得引用 exclusive 牌，否则专属牌会被常规洗牌带入游戏。
	for deck_id_variant: Variant in GameDatabase.decks.keys():
		# 当前牌堆稳定 ID；用于定位违规条目。
		var deck_id: String = str(deck_id_variant)
		for card_row_variant: Variant in GameDatabase.get_deck_cards(deck_id):
			# 当前紧凑牌堆条目；标准格式为 [花色, 点数, 卡牌ID]。
			var card_row: Array = card_row_variant as Array
			if card_row.size() < 3:
				continue
			# 当前条目引用的卡牌定义 ID。
			var deck_definition_id: String = str(card_row[2])
			# 当前定义对象；查不到时不属于本断言范围（由数据库自身的引用校验负责）。
			var deck_definition: CardDefinition = GameDatabase.get_card_definition(deck_definition_id)
			if deck_definition != null and deck_definition.is_exclusive():
				return _fail("exclusive_card_referenced_by_deck deck=%s card=%s" % [deck_id, deck_definition_id])
	return true


## 验证数据库静态校验结果为干净；同时确认“卡牌定义存在但不被任何牌堆引用”不是错误。
func _test_game_database_validation_is_clean() -> bool:
	if not GameDatabase.validation_errors.is_empty():
		return _fail("validation_errors=%s" % str(GameDatabase.validation_errors))
	# 未被任何牌堆引用的卡牌集合；生产先例证明这类牌存在且合法，因此本机制无需放宽任何现有校验。
	# 该断言的作用是：一旦未来有提交为“专属牌必须入堆”新增反向校验，本用例会立刻失败并暴露口径冲突。
	var referenced_definition_ids: Dictionary = {}
	for deck_id_variant: Variant in GameDatabase.decks.keys():
		for card_row_variant: Variant in GameDatabase.get_deck_cards(str(deck_id_variant)):
			var card_row: Array = card_row_variant as Array
			if card_row.size() >= 3:
				referenced_definition_ids[str(card_row[2])] = true
	# 未被引用的定义数量；为 0 时说明反向口径未被验证，但不算失败（内容可能恰好全部入堆）。
	var unreferenced_count: int = 0
	for card_id_variant: Variant in GameDatabase.cards.keys():
		if not referenced_definition_ids.has(str(card_id_variant)):
			unreferenced_count += 1
	if unreferenced_count > 0 and not GameDatabase.validation_errors.is_empty():
		return _fail("unreferenced_card_reported_as_error count=%d" % unreferenced_count)
	return true


## 验证「按卡牌定义创建实体牌并按位次加入摸牌堆」端口的全部前置校验、位次语义与增量口径。
func _test_insert_card_into_draw_pile() -> bool:
	# 基线；入堆前牌堆与移牌历史长度，用于断言“恰好一条”增量。
	var baseline_pile_size: int = _controller.state.draw_pile.size()
	var baseline_history_size: int = _controller.state.card_move_history.size()
	var baseline_random_count: int = _controller.state.random_history.size()
	# 非法输入必须零副作用；逐条核对数量与返回值。
	if _controller.create_and_insert_card_into_draw_pile("", "spade", 1, 1) != -1:
		return _fail("empty_definition_should_fail")
	if _controller.create_and_insert_card_into_draw_pile("probe_definition_not_in_database", "spade", 1, 1) != -1:
		return _fail("unknown_definition_should_fail")
	if _controller.create_and_insert_card_into_draw_pile(PROBE_DEFINITION_ID, "spade", 1, -1) != -1:
		return _fail("position_negative_should_fail")
	if _controller.create_and_insert_card_into_draw_pile(PROBE_DEFINITION_ID, "spade", 1, 3) != -1:
		return _fail("position_three_should_fail")
	if _controller.state.draw_pile.size() != baseline_pile_size or _controller.state.card_move_history.size() != baseline_history_size:
		return _fail("failed_insert_produced_side_effect")
	if _controller.state.random_history.size() != baseline_random_count:
		return _fail("failed_insert_wrote_random_history")
	# 显式牌面入堆；位置 2 应插在距数组末尾 1 个元素处（数组末尾为顶）。
	var second_uid: int = _controller.create_and_insert_card_into_draw_pile(PROBE_DEFINITION_ID, "heart", 7, 2)
	if second_uid < 0:
		return _fail("explicit_insert_position_two_rejected")
	if _controller.state.draw_pile.size() != baseline_pile_size + 1:
		return _fail("insert_did_not_grow_pile")
	if _controller.state.draw_pile[_controller.state.draw_pile.size() - 2].uid != second_uid:
		return _fail("position_two_index_mismatch")
	# 显式牌面不得写随机历史；只有缺省牌面才动用权威随机源。
	if _controller.state.random_history.size() != baseline_random_count:
		return _fail("explicit_insert_wrote_random_history")
	# 实体可被数据库解析；牌面即调用方给出的花色点数。
	var inserted_instance: CardInstance = _controller.state.draw_pile[_controller.state.draw_pile.size() - 2]
	if inserted_instance.definition_id != PROBE_DEFINITION_ID or inserted_instance.suit != "heart" or inserted_instance.rank != 7:
		return _fail("inserted_card_face_mismatch id=%s suit=%s rank=%d" % [inserted_instance.definition_id, inserted_instance.suit, inserted_instance.rank])
	if GameDatabase.get_card(inserted_instance.definition_id).is_empty():
		return _fail("inserted_card_definition_unresolvable")
	# 位置 1 应成为牌堆最新顶（数组末尾）；位次语义是“放置那一刻从顶往下数”，
	# 因此原本的顶牌被整体下压一位，而不是每张牌各自记住固定位次。
	var previous_top_uid: int = _controller.state.draw_pile.back().uid
	var top_uid: int = _controller.create_and_insert_card_into_draw_pile(PROBE_DEFINITION_ID, "club", 9, 1)
	if top_uid < 0:
		return _fail("explicit_insert_position_one_rejected")
	if _controller.state.draw_pile.back().uid != top_uid:
		return _fail("position_one_is_not_pile_top")
	if _controller.state.draw_pile[_controller.state.draw_pile.size() - 2].uid != previous_top_uid:
		return _fail("previous_top_not_pushed_down")
	if _controller.state.draw_pile[_controller.state.draw_pile.size() - 3].uid != second_uid:
		return _fail("position_two_shifted_by_top_insert")
	# 缺省牌面；必须使用权威随机源并写入随机历史，使存档与回放可以复现同一组牌面。
	var random_uid: int = _controller.create_and_insert_card_into_draw_pile(PROBE_DEFINITION_ID)
	if random_uid < 0:
		return _fail("random_face_insert_rejected")
	# 随机结果实体；用于核对花色点数取值域与记账条数。
	var random_instance: CardInstance = null
	for draw_card: CardInstance in _controller.state.draw_pile:
		if draw_card.uid == random_uid:
			random_instance = draw_card
			break
	if random_instance == null:
		return _fail("random_inserted_card_missing")
	if not CardInstance.is_valid_suit(random_instance.suit) or not CardInstance.is_valid_rank(random_instance.rank):
		return _fail("random_face_out_of_range suit=%s rank=%d" % [random_instance.suit, random_instance.rank])
	if _controller.state.random_history.size() != baseline_random_count + 1:
		return _fail("random_insert_missing_history")
	if str((_controller.state.random_history.back() as Dictionary).get("kind", "")) != "exclusive_card_insert":
		return _fail("random_history_kind_mismatch")
	# 增量口径；两次成功入堆必须各产生恰好一条移牌历史，且目标区域都是摸牌堆。
	if _controller.state.card_move_history.size() != baseline_history_size + 3:
		return _fail("move_history_count=%d" % (_controller.state.card_move_history.size() - baseline_history_size))
	for history_index: int in range(baseline_history_size, _controller.state.card_move_history.size()):
		# 当前移牌摘要；入堆的来源区域必须是空字符串（新牌此前不属于任何区域）。
		var move_data: Dictionary = _controller.state.card_move_history[history_index]
		if str(move_data.get("to_zone", "")) != "draw_pile" or str(move_data.get("from_zone", "")) != "":
			return _fail("move_history_zone_mismatch to=%s from=%s" % [str(move_data.get("to_zone", "")), str(move_data.get("from_zone", ""))])
	# 位次方向必须与真实摸牌顺序一致；连续摸两张，断言先摸到“位置 1”、再摸到“位置 2”。
	# 为了让顺序可观测，先把牌堆顶两位替换为本次专门插入的两张：位置 1 后插，位置 2 先插。
	var draw_probe_top_uid: int = _controller.create_and_insert_card_into_draw_pile(PROBE_DEFINITION_ID, "spade", 13, 1)
	var draw_probe_second_uid: int = _controller.create_and_insert_card_into_draw_pile(PROBE_DEFINITION_ID, "diamond", 12, 2)
	if draw_probe_top_uid < 0 or draw_probe_second_uid < 0:
		return _fail("draw_probe_insert_rejected")
	if _controller.state.draw_pile.back().uid != draw_probe_top_uid or _controller.state.draw_pile[_controller.state.draw_pile.size() - 2].uid != draw_probe_second_uid:
		return _fail("draw_probe_layout_mismatch")
	# 真实摸牌；摸牌服务固定取数组末尾，因此顺序必须与位次语义一致。
	var draw_baseline_history: int = _controller.state.card_move_history.size()
	_controller.draw(0, 2, false)
	await get_tree().process_frame
	# 本次摸牌产生的进入手牌顺序；按移牌历史读取，不依赖界面快照。
	var drawn_uids: Array[int] = []
	for history_index: int in range(draw_baseline_history, _controller.state.card_move_history.size()):
		var move_data: Dictionary = _controller.state.card_move_history[history_index]
		if str(move_data.get("to_zone", "")) == "hand":
			for card_uid_variant: Variant in move_data.get("card_ids", []) as Array:
				drawn_uids.append(int(card_uid_variant))
	if drawn_uids.size() < 2 or drawn_uids[0] != draw_probe_top_uid or drawn_uids[1] != draw_probe_second_uid:
		return _fail("draw_order_mismatch drawn=%s expect=[%d,%d]" % [str(drawn_uids), draw_probe_top_uid, draw_probe_second_uid])
	# 结算本次摸牌可能产生的选择窗口，避免影响后续用例的提交。
	if not await _settle_pending_choices():
		return false
	# 卡牌自带牌面；专属牌没有牌堆条目，调用方省略牌面时必须落到卡牌文件声明的花色点数，而不是随机值。
	if not await _test_definition_declared_face_default():
		return false
	# 洗入位次；position=0 表示由权威随机源在整副牌堆中均匀选位，必须记账且必须落在合法下标区间内。
	if not await _test_random_position_insert():
		return false
	return true


## 验证「调用方省略牌面 → 卡牌定义自带牌面」这一优先级，不依赖任何具体专属牌是否已制作。
func _test_definition_declared_face_default() -> bool:
	# 探针定义；花色点数写进静态元数据，模拟专属牌“牌面来自卡牌文件”的唯一来源。
	var probe_card_id: String = "probe_declared_face_card"
	GameDatabase.cards[probe_card_id] = {
		"id":probe_card_id,
		"original_name":"探针",
		"custom_name":"探针",
		"type":"trick",
		"subtype":"delayed",
		"effect_id":"probe_declared_face_effect",
		"target_mode":"self",
		"description":"探针定义，仅用于验证自带牌面优先级。",
		"exclusive":true,
		"suit":"diamond",
		"rank":11,
	}
	GameDatabase.card_definitions[probe_card_id] = CardDefinition.new(GameDatabase.cards[probe_card_id])
	# 随机历史基线；自带牌面不消耗权威随机源，因此本次入堆不得新增随机记账。
	var baseline_random_count: int = _controller.state.random_history.size()
	var declared_uid: int = _controller.create_and_insert_card_into_draw_pile(probe_card_id, "", 0, 1)
	if declared_uid < 0:
		return _fail("declared_face_insert_rejected")
	# 实际实体；必须复现定义声明的花色点数。
	var declared_instance: CardInstance = null
	for draw_card: CardInstance in _controller.state.draw_pile:
		if draw_card.uid == declared_uid:
			declared_instance = draw_card
			break
	if declared_instance == null:
		return _fail("declared_face_card_missing")
	if declared_instance.suit != "diamond" or declared_instance.rank != 11:
		return _fail("declared_face_not_used suit=%s rank=%d" % [declared_instance.suit, declared_instance.rank])
	if _controller.state.random_history.size() != baseline_random_count:
		return _fail("declared_face_wrote_random_history")
	# 显式牌面优先级最高；调用方给出合法牌面时必须覆盖定义声明。
	var explicit_uid: int = _controller.create_and_insert_card_into_draw_pile(probe_card_id, "spade", 2, 1)
	if explicit_uid < 0:
		return _fail("explicit_face_over_declared_rejected")
	# 显式牌面实体；用于核对覆盖结果。
	var explicit_instance: CardInstance = null
	for draw_card: CardInstance in _controller.state.draw_pile:
		if draw_card.uid == explicit_uid:
			explicit_instance = draw_card
			break
	if explicit_instance == null or explicit_instance.suit != "spade" or explicit_instance.rank != 2:
		return _fail("explicit_face_priority_broken")
	# 探针清理；数据库是全局单例，残留条目会污染后续用例与验证结论。
	GameDatabase.cards.erase(probe_card_id)
	GameDatabase.card_definitions.erase(probe_card_id)
	return true


## 验证洗入位次：位次由权威随机源在 [1, 牌堆张数+1] 内选取，写入随机历史，且落点与记录的位次一致。
func _test_random_position_insert() -> bool:
	# 牌堆张数；洗入上界是本值 +1，因此抽到的位次必须落在 1..size+1。
	var pile_size: int = _controller.state.draw_pile.size()
	var baseline_random_count: int = _controller.state.random_history.size()
	var baseline_history_size: int = _controller.state.card_move_history.size()
	var shuffled_uid: int = _controller.create_and_insert_card_into_draw_pile(PROBE_DEFINITION_ID, "heart", 5, 0)
	if shuffled_uid < 0:
		return _fail("random_position_insert_rejected")
	if _controller.state.draw_pile.size() != pile_size + 1:
		return _fail("random_position_did_not_grow_pile")
	# 随机记账；洗入位次取决于当时的牌堆张数，因此必须与牌面随机一样写入历史才能复现。
	if _controller.state.random_history.size() != baseline_random_count + 1:
		return _fail("random_position_missing_history")
	var history_entry: Dictionary = _controller.state.random_history.back() as Dictionary
	if str(history_entry.get("kind", "")) != "exclusive_card_insert":
		return _fail("random_position_history_kind=%s" % str(history_entry.get("kind", "")))
	# 记账位次；既是可复现凭据，也用于反推实际落点。
	var recorded_position: int = int(history_entry.get("position", -1))
	if recorded_position < 1 or recorded_position > pile_size + 1:
		return _fail("random_position_out_of_range position=%d pile=%d" % [recorded_position, pile_size])
	# 实际下标；位次 N 对应「距数组末尾 N-1 个元素」，与置牌端口共用同一换算口径。
	var expected_index: int = _controller.state.draw_pile.size() - recorded_position
	if _controller.state.draw_pile[expected_index].uid != shuffled_uid:
		return _fail("random_position_index_mismatch position=%d index=%d" % [recorded_position, expected_index])
	if _controller.state.card_move_history.size() != baseline_history_size + 1:
		return _fail("random_position_move_history_count")
	return true


## 验证私有置牌事实的可见性裁剪、存档往返、非法写入与清除口径。
func _test_private_pile_placement_fact() -> bool:
	# 持有者与两名旁观者；至少需要一名旁观者用于验证“其他角色不可知”。
	var owner_id: int = 0
	var other_id: int = _find_other_alive_player(owner_id)
	if other_id < 0:
		return _fail("no_other_player_for_privacy")
	# 先清除残留，保证后续断言只观察本次写入。
	_controller.clear_private_pile_placement(owner_id)
	# 非法写入必须零副作用。
	if _controller.set_private_pile_placement(-1, 100, 1, 0, 1):
		return _fail("negative_player_should_fail")
	if _controller.set_private_pile_placement(9999, 100, 1, 0, 1):
		return _fail("unknown_player_should_fail")
	if _controller.set_private_pile_placement(owner_id, -1, 1, 0, 1):
		return _fail("negative_card_uid_should_fail")
	if _controller.set_private_pile_placement(owner_id, 100, 3, 0, 1):
		return _fail("invalid_position_should_fail")
	if not _controller.get_private_pile_placement(owner_id).is_empty():
		return _fail("failed_write_left_fact")
	# 合法写入；四个键齐全且取值与入参一致。
	var turn_number: int = _controller.state.turn_number
	if not _controller.set_private_pile_placement(owner_id, 4242, 2, owner_id, turn_number):
		return _fail("legal_private_fact_rejected")
	var fact: Dictionary = _controller.get_private_pile_placement(owner_id)
	if int(fact.get(PRIVATE_KEY_CARD_UID, -1)) != 4242 or int(fact.get(PRIVATE_KEY_POSITION, 0)) != 2:
		return _fail("private_fact_payload_mismatch %s" % str(fact))
	if int(fact.get(PRIVATE_KEY_TURN_PLAYER_ID, -1)) != owner_id or int(fact.get(PRIVATE_KEY_TURN_NUMBER, -1)) != turn_number:
		return _fail("private_fact_turn_payload_mismatch %s" % str(fact))
	# 可见性裁剪：只有持有者的「权威全量序列化」能读到该键；其余三条通道都读不到。
	# 本地广播快照是 to_dict(本机真人, false)，它会整体进入回放录制，因此必须不含该键。
	var owner_public_snapshot: Dictionary = _controller.state.get_player(owner_id).to_dict(owner_id, false)
	if owner_public_snapshot.has("private_pile_placement"):
		return _fail("owner_broadcast_snapshot_leaked_private_fact")
	var other_public_snapshot: Dictionary = _controller.state.get_player(other_id).to_dict(other_id, false)
	if other_public_snapshot.has("private_pile_placement"):
		return _fail("other_public_snapshot_leaked_private_fact")
	if _controller.state.get_player(owner_id).to_dict(other_id, false).has("private_pile_placement"):
		return _fail("other_viewer_snapshot_leaked_private_fact")
	# AI 快照口径：它使用 reveal_private=true，但对非持有者仍不得包含该事实。
	# 这是本机制最容易泄露的一条通道：所有AI快照都是 to_dict(该AI的player_id, true)，
	# 若序列化条件采用 reveal_private，则每个AI都会读到别人的置牌事实。
	if _controller.state.get_player(owner_id).to_dict(other_id, true).has("private_pile_placement"):
		return _fail("ai_snapshot_for_other_player_leaked_private_fact")
	if not _controller.state.get_player(owner_id).to_dict(owner_id, true).has("private_pile_placement"):
		return _fail("owner_private_snapshot_missing_fact")
	# 权威公开观察快照（viewer_id = -1）同样不含该事实；权威端读取事实只能走 get_private_pile_placement()。
	if _controller.state.get_player(owner_id).to_dict(-1, true).has("private_pile_placement"):
		return _fail("authority_public_snapshot_leaked_private_fact")
	# 权威存档往返；存档流程固定使用 to_dict(本人的player_id, true)，因此恢复后事实必须逐字段一致。
	var authoritative_data: Dictionary = _controller.state.get_player(owner_id).to_dict(owner_id, true)
	var restored_player: PlayerState = PlayerState.from_authoritative_dict(authoritative_data)
	if int(restored_player.private_pile_placement.get(PRIVATE_KEY_CARD_UID, -1)) != 4242 or int(restored_player.private_pile_placement.get(PRIVATE_KEY_POSITION, 0)) != 2:
		return _fail("authoritative_round_trip_lost_fact %s" % str(restored_player.private_pile_placement))
	# 旧存档兼容；缺少该键时按空字典恢复，不得抛错或残留字段。
	var legacy_data: Dictionary = authoritative_data.duplicate(true)
	legacy_data.erase("private_pile_placement")
	var legacy_player: PlayerState = PlayerState.from_authoritative_dict(legacy_data)
	if not legacy_player.private_pile_placement.is_empty():
		return _fail("legacy_save_should_restore_empty_fact")
	# 清除口径；第一次返回 true，第二次因已无事实而返回 false。
	if not _controller.clear_private_pile_placement(owner_id):
		return _fail("clear_private_fact_rejected")
	if _controller.clear_private_pile_placement(owner_id):
		return _fail("second_clear_should_return_false")
	if not _controller.get_private_pile_placement(owner_id).is_empty():
		return _fail("private_fact_survived_clear")
	return true


## 验证秘密置牌的四条公开通道（日志 / 表现事件 / 快照 / 移牌历史）边界与位次落地结果。
func _test_secret_placement_broadcast_boundary() -> bool:
	# 持牌者；必须拥有至少一张手牌才能执行秘密放置。
	var owner_id: int = _find_player_with_hand_cards(1)
	if owner_id < 0:
		return _fail("no_player_with_hand_cards")
	# 被放置的实体；取该玩家手牌中的第一张，只使用稳定 UID。
	var placed_card: CardInstance = _controller.state.get_player(owner_id).hand[0]
	var placed_uid: int = placed_card.uid
	var baseline_hand_size: int = _controller.state.get_player(owner_id).hand.size()
	var baseline_pile_size: int = _controller.state.draw_pile.size()
	var baseline_history_size: int = _controller.state.card_move_history.size()
	var baseline_log_count: int = _captured_logs.size()
	var baseline_transfer_count: int = _captured_transfers.size()
	# 非法输入必须零副作用。
	if _controller.place_hand_card_on_draw_pile_top(owner_id, placed_uid, 0):
		return _fail("placement_position_zero_should_fail")
	if _controller.place_hand_card_on_draw_pile_top(owner_id, placed_uid, 3):
		return _fail("placement_position_three_should_fail")
	if _controller.place_hand_card_on_draw_pile_top(9999, placed_uid, 1):
		return _fail("placement_unknown_player_should_fail")
	if _controller.place_hand_card_on_draw_pile_top(owner_id, 987654321, 1):
		return _fail("placement_unknown_card_should_fail")
	if _controller.state.get_player(owner_id).hand.size() != baseline_hand_size or _controller.state.draw_pile.size() != baseline_pile_size:
		return _fail("failed_placement_produced_side_effect")
	# 合法放置到位次 2；手牌 -1、牌堆 +1，且实体确实位于“牌堆顶第二张”。
	if not _controller.place_hand_card_on_draw_pile_top(owner_id, placed_uid, 2):
		return _fail("legal_placement_rejected")
	if _controller.state.get_player(owner_id).hand.size() != baseline_hand_size - 1:
		return _fail("placement_did_not_remove_hand_card")
	if _controller.state.draw_pile.size() != baseline_pile_size + 1:
		return _fail("placement_did_not_grow_pile")
	if _controller.state.draw_pile[_controller.state.draw_pile.size() - 2].uid != placed_uid:
		return _fail("placement_position_two_index_mismatch")
	# 移牌历史恰好一条，且原因与来源区域可核对。
	if _controller.state.card_move_history.size() != baseline_history_size + 1:
		return _fail("placement_move_history_count=%d" % (_controller.state.card_move_history.size() - baseline_history_size))
	var placement_move: Dictionary = _controller.state.card_move_history.back()
	if str(placement_move.get("to_zone", "")) != "draw_pile" or str(placement_move.get("from_zone", "")) != "hand":
		return _fail("placement_move_zone_mismatch %s" % str(placement_move))
	if str(placement_move.get("reason", "")) != "secret_pile_placement":
		return _fail("placement_reason_mismatch %s" % str(placement_move.get("reason", "")))
	# 广播边界①：不写公共日志（对局记录）。
	if _captured_logs.size() != baseline_log_count:
		return _fail("placement_wrote_public_log %s" % str(_captured_logs.slice(baseline_log_count)))
	# 广播边界②：不产生公开表现事件（目标区域不是手牌或弃牌堆）。
	if _captured_transfers.size() != baseline_transfer_count:
		return _fail("placement_emitted_public_transfer")
	# 广播边界③：牌面知识被彻底清除，其他角色无法从 known_to 推断这张牌去了哪里。
	# 通过移牌历史取回实体；牌仍在牌堆，因此直接扫描牌堆定位。
	var relocated_card: CardInstance = null
	for draw_card: CardInstance in _controller.state.draw_pile:
		if draw_card.uid == placed_uid:
			relocated_card = draw_card
			break
	if relocated_card == null:
		return _fail("placed_card_not_in_draw_pile")
	if not relocated_card.known_to.is_empty() or relocated_card.shown:
		return _fail("placed_card_knowledge_not_cleared known_to=%s shown=%s" % [str(relocated_card.known_to), str(relocated_card.shown)])
	# 广播边界④：任何观察者的快照都不含该牌 UID；牌堆牌面在所有快照中都不可见。
	# 判据只取“承载实体身份的 uid 字段”，避免用裸数值匹配时被血量、手牌数等同值整数误报。
	for player: PlayerState in _controller.state.players:
		# 当前观察者的普通快照；序列化后收集其中出现的全部实体 UID。
		var viewer_snapshot: Dictionary = _controller.state.to_dict(player.player_id, false)
		var visible_card_uids: Dictionary = {}
		_collect_snapshot_card_uids(viewer_snapshot, visible_card_uids)
		if visible_card_uids.has(placed_uid):
			return _fail("placed_card_uid_leaked_in_snapshot viewer=%d" % player.player_id)
	# 位次落地结果用真实牌堆顺序验证；同时把位次 1 也覆盖一次。
	# 位次是“放置那一刻从顶往下数”的相对位次，因此新的顶牌会把此前所有牌整体下压一位。
	var previous_top_uid: int = _controller.state.draw_pile.back().uid
	var second_probe: CardInstance = _controller.state.get_player(owner_id).hand[0]
	if not _controller.place_hand_card_on_draw_pile_top(owner_id, second_probe.uid, 1):
		return _fail("second_placement_rejected")
	if _controller.state.draw_pile.back().uid != second_probe.uid:
		return _fail("second_placement_is_not_pile_top")
	if _controller.state.draw_pile[_controller.state.draw_pile.size() - 2].uid != previous_top_uid:
		return _fail("placement_previous_top_not_pushed_down")
	if _controller.state.draw_pile[_controller.state.draw_pile.size() - 3].uid != placed_uid:
		return _fail("first_placement_not_pushed_to_third")
	# 秘密放置同样不写日志；两次放置的日志差值为 0。
	if _captured_logs.size() != baseline_log_count:
		return _fail("second_placement_wrote_public_log")
	return true


## 验证位次询问的三个稳定选项、候选范围，以及伪造提交被整条拒绝、合法提交被接受。
func _test_position_request_protocol() -> bool:
	# 询问对象；必须拥有至少两张手牌，便于构造“多选一张”的非法提交。
	var chooser_id: int = _find_player_with_hand_cards(2)
	if chooser_id < 0:
		return _fail("no_chooser_with_two_hand_cards")
	# 询问前的待办状态；用于核对询问结束后窗口被正确清空。
	# 先清空累计窗口：对手 AI 在前序步骤中可能已经用出锦囊并打开反制链。
	if not await _settle_pending_choices():
		return false
	if not _controller._pending_card_choice.is_empty():
		return _fail("pending_choice_before_request")
	# 正式端口调用；本用例的询问对象是本机真人，因此请求进入异步等待，返回值必须是“未确认”。
	var immediate_result: Dictionary = _controller.request_hand_card_pile_position(chooser_id, "游丝", "你可以将一张手牌置于牌堆顶的第一张或第二张。")
	if bool(immediate_result.get("confirmed", true)) or int(immediate_result.get("card_uid", 0)) != -1 or int(immediate_result.get("position", -1)) != 0:
		return _fail("deferred_request_should_not_confirm %s" % str(immediate_result))
	if _controller._pending_card_choice.is_empty():
		# 诊断字段；请求被拒绝的原因只可能来自控制器入口的前置校验或时机取消，因此逐项打印当前归属状态。
		return _fail("position_request_not_published negation=%s game_over=%s chooser_alive=%s hand=%d local_human=%d" % [
			str(_controller._pending_negation_choices),
			str(_controller.state.game_over),
			str(_controller.state.get_player(chooser_id).alive if _controller.state.get_player(chooser_id) != null else false),
			_controller.state.get_player(chooser_id).hand.size() if _controller.state.get_player(chooser_id) != null else -1,
			_controller.local_human_player_id,
		])
	# 请求快照；后续面板渲染与非法提交都基于同一份权威请求。
	var pending_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(pending_choice.get("choice_type", "")) != "card_position":
		return _fail("choice_type=%s" % str(pending_choice.get("choice_type", "")))
	if int(pending_choice.get("min_card_select", 0)) != 1 or int(pending_choice.get("max_card_select", 0)) != 1:
		return _fail("card_select_range_mismatch min=%d max=%d" % [int(pending_choice.get("min_card_select", 0)), int(pending_choice.get("max_card_select", 0))])
	# 选项数量、ID 与标签必须与来源需求原文逐字一致，且顺序固定。
	var control_options: Array = pending_choice.get("control_options", []) as Array
	if control_options.size() != 3:
		return _fail("control_option_count=%d" % control_options.size())
	if str((control_options[0] as Dictionary).get("id", "")) != OPTION_TOP_ID or str((control_options[0] as Dictionary).get("label", "")) != OPTION_TOP_LABEL:
		return _fail("option_zero_mismatch %s" % str(control_options[0]))
	if str((control_options[1] as Dictionary).get("id", "")) != OPTION_SECOND_ID or str((control_options[1] as Dictionary).get("label", "")) != OPTION_SECOND_LABEL:
		return _fail("option_one_mismatch %s" % str(control_options[1]))
	if str((control_options[2] as Dictionary).get("id", "")) != OPTION_CANCEL_ID or str((control_options[2] as Dictionary).get("label", "")) != OPTION_CANCEL_LABEL:
		return _fail("option_two_mismatch %s" % str(control_options[2]))
	# 候选只包含询问者自己的手牌；其他角色的手牌绝不会进入候选。
	var candidates: Array = pending_choice.get("candidates", []) as Array
	if candidates.size() != _controller.state.get_player(chooser_id).hand.size():
		return _fail("candidate_count=%d hand=%d" % [candidates.size(), _controller.state.get_player(chooser_id).hand.size()])
	for candidate_variant: Variant in candidates:
		# 当前候选快照；区域与持有者必须同时属于询问者本人。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("owner_id", -1)) != chooser_id or str(candidate.get("zone", "")) != "hand":
			return _fail("candidate_outside_own_hand %s" % str(candidate))
	# 规则层必须为 AI 与网络提供可提交动作；否则请求会在创建时被拒绝或让 AI 永久挂住。
	var legal_actions: Array[Dictionary] = _controller.get_pending_choice_legal_actions()
	var expected_action_count: int = candidates.size() * 2 + 1
	if legal_actions.size() != expected_action_count:
		return _fail("legal_action_count=%d expect=%d" % [legal_actions.size(), expected_action_count])
	# 伪造提交①：不属于本次候选的牌 + 合法位次。
	if _submit_position_choice(pending_choice, [991199], OPTION_SECOND_ID, true):
		return _fail("forged_card_should_be_rejected")
	# 伪造提交②：合法牌 + cancel 作为已确认位次。
	if _submit_position_choice(pending_choice, [int((candidates[0] as Dictionary).get("uid", -1))], OPTION_CANCEL_ID, true):
		return _fail("cancel_as_confirmed_position_should_be_rejected")
	# 伪造提交③：合法牌 + 空位次。
	if _submit_position_choice(pending_choice, [int((candidates[0] as Dictionary).get("uid", -1))], "", true):
		return _fail("missing_position_should_be_rejected")
	# 伪造提交④：两张手牌 + 合法位次（描述要求恰好一张）。
	var two_card_uids: Array[int] = []
	for candidate_index: int in range(2):
		two_card_uids.append(int((candidates[candidate_index] as Dictionary).get("uid", -1)))
	if _submit_position_choice(pending_choice, two_card_uids, OPTION_SECOND_ID, true):
		return _fail("two_cards_should_be_rejected")
	# 非法提交不得吞掉窗口；仍必须保持同一请求可继续提交。
	if _controller._pending_card_choice.is_empty():
		return _fail("rejected_submission_dropped_request")
	# 合法提交；选中一张手牌 + 牌堆顶第二张。
	var chosen_uid: int = int((candidates[0] as Dictionary).get("uid", -1))
	if not _submit_position_choice(pending_choice, [chosen_uid], OPTION_SECOND_ID, true):
		return _fail("legal_position_submission_rejected")
	if _controller._resolved_control_choice_id != OPTION_SECOND_ID:
		return _fail("resolved_control_id=%s" % _controller._resolved_control_choice_id)
	if _controller._resolved_card_choice_uids.size() != 1 or _controller._resolved_card_choice_uids[0] != chosen_uid:
		return _fail("resolved_card_uids=%s" % str(_controller._resolved_card_choice_uids))
	if not _controller._pending_card_choice.is_empty():
		return _fail("accepted_submission_left_pending_request")
	if not await _settle_pending_choices():
		return false
	return true


## 验证位次询问在正式桌面上以「手牌区选牌 + 操作区询问按钮」的方式呈现，不再打开任何独立窗口。
## 可见按钮恰好三个，顺序为「牌堆顶第一张 / 牌堆顶第二张 / 取消」；
## 未选中恰好一张手牌时前两项不可点击、取消始终可点击；选中一张后前两项转为可点击。
## 最后分别点击一次取消与一次第二张位次，核对权威结果槽收到的是放弃与“恰好一张牌 + 第二位次”。
func _test_inline_three_option_usability() -> bool:
	# 询问对象；正式桌面只把属于本机真人座位的请求渲染成内联询问，因此固定使用本地人类座位。
	var chooser_id: int = int(_controller.local_human_player_id)
	# 询问者状态；为null说明本用例尚未建立可交互对局。
	var chooser: PlayerState = _controller.state.get_player(chooser_id) if _controller.state != null and chooser_id >= 0 else null
	if chooser == null or not chooser.alive:
		return _fail("inline_chooser_missing id=%d" % chooser_id)
	# 询问者手牌数量；至少两张才能既验证“未选牌不可确认”又验证“选中一张后可确认”。
	if chooser.hand.size() < 2:
		return _fail("inline_chooser_hand=%d" % chooser.hand.size())
	# 询问前清空累计窗口：权威入口会拒绝“已有待办请求”时新建的位次请求。
	if not await _settle_pending_choices():
		return false
	# 私有置牌事实与牌堆张数基线；界面整段交互只提交意图，两者都不允许发生变化。
	_controller.clear_private_pile_placement(chooser_id)
	var baseline_pile_size: int = _controller.state.draw_pile.size()
	# 正式主场景；内联询问必须覆盖玩家实际运行的桌面、手牌区与操作按钮。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("main_scene_missing")
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	# 主场景自带控制器；非法1人配置阻止自动开局与AI计时器，本用例随后把界面整体改接真实权威控制器。
	var ui_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	ui_controller.default_player_count = 1
	ui_controller.local_human_player_id = chooser_id
	ui_controller.randomize_local_human_seat = false
	for _frame_index: int in range(UI_SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 启动主菜单遮罩；本用例注入局内询问，因此显式关闭遮罩以恢复局内控件。
	(main_instance.get_node("%MainMenu") as MainMenu).visible = false
	await get_tree().process_frame
	# 界面接线：请求发布、状态广播与动作提交三条链路全部指向已经建立的权威控制器。
	# 这样断言覆盖的是完整回路（真实请求 → 内联渲染 → 真实按钮 → 权威结果槽），而不是只测一次渲染。
	main_instance.set("match_controller", _controller)
	_controller.state_changed.connect(Callable(main_instance, "_on_state_changed"))
	_controller.card_choice_requested.connect(Callable(main_instance, "_on_card_choice_requested"))
	_controller.call("_emit_state")
	await get_tree().process_frame
	# 正式桌面接线与等待帧期间，真实对局可能已经为本地玩家打开了响应窗口；正式端口会拒绝“已有待办请求”时新建的位次请求。
	# 因此这里在创建询问前再清空一次累计窗口，且清空后不再等待任何帧，确保询问创建不会被新窗口抢先拦截。
	if not await _settle_pending_choices():
		return false
	# 首次询问；询问对象是本机真人，因此请求必然异步等待界面操作而不是当场结算。
	var request_result: Dictionary = _controller.request_hand_card_pile_position(chooser_id, "游丝", "请选择一张手牌与一个牌堆位次。")
	if bool(request_result.get("confirmed", true)) or _controller._pending_card_choice.is_empty() or str(_controller._pending_card_choice.get("choice_type", "")) != INLINE_CHOICE_TYPE:
		return _fail("inline_request_not_published result=%s pending=%s" % [str(request_result), str(_controller._pending_card_choice.get("choice_type", ""))])
	await get_tree().process_frame
	# 正式桌面节点；独立选牌窗口、操作面板与两个复用按钮。
	var card_selection_panel: CardSelectionPanel = main_instance.get_node("CardSelectionPanel") as CardSelectionPanel
	var interaction_panel: PanelContainer = main_instance.get_node("InteractionPanel") as PanelContainer
	var use_button: Button = main_instance.get_node("%UseButton") as Button
	var cancel_button: Button = main_instance.get_node("%CancelButton") as Button
	# 独立窗口必须保持关闭；位次询问完全复用桌面内联交互。
	if card_selection_panel.visible or not interaction_panel.visible:
		return _fail("inline_window_state panel=%s interaction=%s" % [str(card_selection_panel.visible), str(interaction_panel.visible)])
	# 操作行可见按钮；询问期间只允许出现三个，避免通用取消按钮与声明的取消选项重复。
	var visible_action_buttons: Array[Button] = _get_visible_action_row_buttons(main_instance)
	if visible_action_buttons.size() != INLINE_ACTION_BUTTON_COUNT:
		return _fail("inline_button_count=%d names=%s" % [visible_action_buttons.size(), str(_get_button_texts(visible_action_buttons))])
	if use_button.text != OPTION_TOP_LABEL or cancel_button.text != OPTION_SECOND_LABEL:
		return _fail("inline_option_labels=%s/%s" % [use_button.text, cancel_button.text])
	# 第三项由声明的取消选项渲染；同一操作行不允许再出现通用取消按钮。
	var declared_cancel_button: Button = _get_inline_extra_option_button(main_instance, 0)
	if main_instance.get_node_or_null(INLINE_CANCEL_BUTTON_PATH) != null:
		return _fail("inline_duplicated_cancel_button")
	if declared_cancel_button == null or declared_cancel_button.text != OPTION_CANCEL_LABEL:
		return _fail("inline_third_option=%s" % str(declared_cancel_button))
	# 未选中手牌：两个位次按钮必须不可点击，取消选项必须可点击。
	if not use_button.disabled or not cancel_button.disabled or declared_cancel_button.disabled:
		return _fail("inline_initial_disabled top=%s second=%s cancel=%s" % [str(use_button.disabled), str(cancel_button.disabled), str(declared_cancel_button.disabled)])
	# 候选手牌；取自权威请求，界面不自行推导可选项。
	var candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if candidates.size() < 2:
		return _fail("inline_candidate_count=%d" % candidates.size())
	var chosen_uid: int = int((candidates[0] as Dictionary).get("uid", -1))
	if chosen_uid < 0:
		return _fail("inline_candidate_uid_missing")
	# 在手牌区选中一张手牌；两个位次按钮必须立即解除禁用，取消选项保持可点击。
	main_instance.call("_on_card_pressed", chosen_uid)
	await get_tree().process_frame
	declared_cancel_button = _get_inline_extra_option_button(main_instance, 0)
	if use_button.disabled or cancel_button.disabled or declared_cancel_button == null or declared_cancel_button.disabled:
		return _fail("inline_selected_disabled top=%s second=%s cancel=%s" % [str(use_button.disabled), str(cancel_button.disabled), str(declared_cancel_button == null or declared_cancel_button.disabled)])
	# 点击取消选项；必须提交 confirmed=false 的空选择，既不放置手牌也不产生私有事实。
	declared_cancel_button.pressed.emit()
	# 提交在点击瞬间同步完成：此刻结果槽必须正好是本次放弃的形态，且询问窗口已经关闭。
	# 后续帧里真实对局可能立刻打开新的响应窗口，因此“窗口已关闭”的断言必须放在这里而不是等待一帧之后。
	if not _controller._pending_card_choice.is_empty():
		return _fail("inline_cancel_left_pending_request")
	# 取消提交的是声明的取消选项本身，并保持 confirmed=false、不携带任何手牌；权威端据此把本次放置视为未发生。
	if _controller._resolved_control_choice_id != OPTION_CANCEL_ID or not _controller._resolved_card_choice_uids.is_empty():
		return _fail("inline_cancel_resolved_choice control=%s uids=%s" % [_controller._resolved_control_choice_id, str(_controller._resolved_card_choice_uids)])
	await get_tree().process_frame
	# 界面只提交意图：放弃不放置手牌，也不产生私有事实或改变牌堆张数。
	if not _controller.get_private_pile_placement(chooser_id).is_empty() or _controller.state.draw_pile.size() != baseline_pile_size:
		return _fail("inline_cancel_touched_pile")
	# 第二次询问；这次确认「牌堆顶第二张」，用于验证手牌维度确实随确认一起送达权威端。
	# 同样先清空窗口再立即创建请求，避免真实对局在等待帧里先打开响应窗口。
	if not await _settle_pending_choices():
		return false
	var confirm_result: Dictionary = _controller.request_hand_card_pile_position(chooser_id, "游丝", "请选择一张手牌与一个牌堆位次。")
	if bool(confirm_result.get("confirmed", true)) or _controller._pending_card_choice.is_empty() or str(_controller._pending_card_choice.get("choice_type", "")) != INLINE_CHOICE_TYPE:
		return _fail("inline_second_request_not_published result=%s pending=%s" % [str(confirm_result), str(_controller._pending_card_choice.get("choice_type", ""))])
	await get_tree().process_frame
	var second_candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	var second_uid: int = int((second_candidates[0] as Dictionary).get("uid", -1))
	if second_uid < 0:
		return _fail("inline_second_candidate_missing")
	main_instance.call("_on_card_pressed", second_uid)
	await get_tree().process_frame
	# 原取消位置上的按钮此时承担「牌堆顶第二张」；点击它即确认第二位次。
	cancel_button.pressed.emit()
	# 与取消同理：确认结果槽必须在点击瞬间读取，避免后续帧里新请求覆盖结果。
	if not _controller._pending_card_choice.is_empty():
		return _fail("inline_confirm_left_pending_request")
	if _controller._resolved_control_choice_id != OPTION_SECOND_ID:
		return _fail("inline_confirm_control=%s" % _controller._resolved_control_choice_id)
	if _controller._resolved_card_choice_uids.size() != 1 or int(_controller._resolved_card_choice_uids[0]) != second_uid:
		return _fail("inline_confirm_uids=%s expected=%d" % [str(_controller._resolved_card_choice_uids), second_uid])
	await get_tree().process_frame
	# 界面只提交意图：确认动作同样不得自行移动手牌或写入私有事实。
	if not _controller.get_private_pile_placement(chooser_id).is_empty() or _controller.state.draw_pile.size() != baseline_pile_size:
		return _fail("inline_ui_moved_cards_without_authority")
	# 清理；先断开界面与权威控制器的信号接线，再释放主场景，避免退出阶段继续渲染。
	_controller.state_changed.disconnect(Callable(main_instance, "_on_state_changed"))
	_controller.card_choice_requested.disconnect(Callable(main_instance, "_on_card_choice_requested"))
	remove_child(main_instance)
	main_instance.free()
	await get_tree().process_frame
	return true


## 返回正式桌面操作行中当前可见的按钮；内联询问期间的可见数量即玩家看到的询问按钮数量。
func _get_visible_action_row_buttons(main_instance: Control) -> Array[Button]:
	# 可见按钮结果；按场景中的实际顺序收集，顺序与玩家从左到右看到的一致。
	var result: Array[Button] = []
	var action_row: HBoxContainer = main_instance.get_node(ACTION_ROW_PATH) as HBoxContainer
	for child: Node in action_row.get_children():
		if child is Button and (child as Button).visible:
			result.append(child as Button)
	return result


## 返回内联询问追加的第 index 个文字选项按钮；请求刷新会重建这些按钮，因此每次断言都必须重新查找。
func _get_inline_extra_option_button(main_instance: Control, option_index: int) -> Button:
	return main_instance.get_node_or_null("%s/InlineControlOptionButton_%d" % [ACTION_ROW_PATH, option_index]) as Button


## 汇总按钮文本；仅用于失败诊断，帮助区分“按钮缺失”和“标签漂移”两类原因。
func _get_button_texts(buttons: Array[Button]) -> Array[String]:
	# 文本结果；顺序与传入按钮一致。
	var result: Array[String] = []
	for button: Button in buttons:
		result.append(button.text)
	return result


## 构造并提交一次位次询问动作；返回是否被权威入口接受。
func _submit_position_choice(pending_choice: Dictionary, selected_card_uids: Array[int], control_id: String, confirmed: bool) -> bool:
	# 请求序号与回答者；两者都必须与当前窗口一致，否则会被前置校验拒绝而无法验证目标规则。
	var request_id: int = int(pending_choice.get("request_id", -1))
	var chooser_id: int = int(pending_choice.get("chooser_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {
		"request_id":request_id,
		"selected_card_uids":selected_card_uids.duplicate(),
		"selected_target_ids":[],
		"selected_control_id":control_id,
		"confirmed":confirmed,
	}
	return _controller.submit_action(action)


## 递归收集快照中所有承载实体牌身份的 UID 字段值，写入 out_uids 集合。
## 只接受键名以 uid 结尾（或恰好等于 uid）的整数值：这样既覆盖手牌、装备、判定区等全部牌区，
## 也不会把血量、手牌数、回合号等同值整数误判成“某张牌出现在快照里”。
func _collect_snapshot_card_uids(value: Variant, out_uids: Dictionary) -> void:
	if value is Dictionary:
		for key_variant: Variant in (value as Dictionary).keys():
			# 当前键名；只按名字判定是否为实体身份字段。
			var key_name: String = str(key_variant).to_lower()
			# 当前值；只可能是标量或容器，两种情况都要继续下钻。
			var child_value: Variant = (value as Dictionary)[key_variant]
			if key_name == "uid" or key_name.ends_with("_uid") or key_name.ends_with("_uids"):
				if child_value is Array:
					for uid_variant: Variant in child_value as Array:
						if uid_variant is int or uid_variant is float:
							out_uids[int(uid_variant)] = true
				elif child_value is int or child_value is float:
					out_uids[int(child_value)] = true
			_collect_snapshot_card_uids(child_value, out_uids)
		return
	if value is Array:
		for item_variant: Variant in value as Array:
			_collect_snapshot_card_uids(item_variant, out_uids)


## 返回一名手牌数不少于指定值且仍然存活的玩家 ID；找不到时返回 -1。
func _find_player_with_hand_cards(minimum_hand_size: int) -> int:
	if _controller == null or _controller.state == null:
		return -1
	for player: PlayerState in _controller.state.players:
		if player.alive and not player.out_of_game and player.hand.size() >= minimum_hand_size:
			return player.player_id
	return -1


## 返回除指定角色外的一名存活玩家 ID；找不到时返回 -1。
func _find_other_alive_player(excluded_player_id: int) -> int:
	if _controller == null or _controller.state == null:
		return -1
	for player: PlayerState in _controller.state.players:
		if player.alive and not player.out_of_game and player.player_id != excluded_player_id:
			return player.player_id
	return -1


## 取消当前待处理选择；必须绑定创建时的请求编号与回答者，否则会被权威入口拒绝。
func _cancel_pending_choice() -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return true
	# 请求序号与回答者；两者都取自权威窗口本身。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
	return _controller.submit_action(action)


## 确认当前待处理选择；候选一律取自规则层自己生成的合法动作，因此不会读到隐藏信息，
## 也不会因窗口类型（选牌、选目标、组合选择、文字选项）不同而构造出无法通过校验的负载。
func _confirm_pending_choice() -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return true
	if bool(_controller.submit_first_legal_pending_choice()):
		return true
	# 规则层没有给出任何可确认动作时，按请求字段做保守回退（仅用于诊断，不作为常规路径）。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	var selected_target_ids: Array[int] = []
	var candidate_target_ids: Array = _controller._pending_card_choice.get("target_ids", []) as Array
	if not candidate_target_ids.is_empty():
		selected_target_ids.append(int(candidate_target_ids[0]))
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":selected_target_ids, "confirmed":true}
	return _controller.submit_action(action)


## 结算当前全部待办选择；用于把上一步骤可能产生的窗口清空，避免后续用例被拦截。
## 同时覆盖【无懈可击】并行响应窗口：本用例不验证锦囊反制链，但对手 AI 在推进过程中随时可能使用锦囊，
## 残留的反制窗口会让 controller.request_card_choice 直接拒绝后续全部权威请求，因此必须一并按“不使用无懈”清空。
func _settle_pending_choices() -> bool:
	var safety: int = 0
	while _controller != null and (not _controller._pending_card_choice.is_empty() or not _controller._pending_negation_choices.is_empty()) and safety < 48:
		safety += 1
		if not _controller._pending_negation_choices.is_empty():
			_cancel_pending_negation_requests()
			await get_tree().process_frame
			continue
		if not _cancel_pending_choice() and not _confirm_pending_choice():
			return _fail("settle_pending_choices_stuck")
		await get_tree().process_frame
	if _controller != null and (not _controller._pending_card_choice.is_empty() or not _controller._pending_negation_choices.is_empty()):
		return _fail("settle_pending_choices_exhausted")
	return true


## 逐个取消当前全部待办的【无懈可击】请求；空选牌列表即“不使用无懈”，由控制器按既有响应协议继续该轮。
## 不在此处 await：调用方负责在下一帧重新读取待办表，因为取消一个响应者后可能立刻出现下一名响应者。
func _cancel_pending_negation_requests() -> void:
	if _controller == null:
		return
	for request_id_variant: Variant in _controller._pending_negation_choices.keys().duplicate():
		# 当前反制请求；chooser_id 是唯一有权提交该请求的角色。
		var request_data: Dictionary = _controller._pending_negation_choices.get(request_id_variant, {}) as Dictionary
		var chooser_id: int = int(request_data.get("chooser_id", -1))
		if chooser_id < 0:
			continue
		# 放弃动作；载荷携带请求ID与空选牌列表，表示该响应者不使用【无懈可击】。
		var cancel_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		cancel_action.payload = {"request_id":int(request_id_variant), "selected_card_uids":[]}
		_controller.submit_action(cancel_action)


## 启动一局可操作的对局，并把开局选将与开局技能选择全部结算干净。
## 固定种子选将会随武将池变化而换人，因此不假设任何具体武将或开局是否产生技能选择。
func _start_playable_match() -> bool:
	_create_controller()
	GameSettings.set_control_all_characters_enabled(false)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	if not _controller.start_match(TEST_PLAYER_COUNT, 20261002, IdentityRules.MODE_IDENTITY):
		return _fail("start_match")
	# 选将阶段：本地真人按候选顺序提交，其余座位由内置AI推进。
	var selection_safety: int = 0
	while _controller.state.current_phase == "character_selection" and selection_safety < 24:
		selection_safety += 1
		if _controller.character_selection.get_pending_player_ids().has(0):
			var candidates: Array[String] = _controller.character_selection.get_candidates(0)
			if candidates.is_empty() or not _controller.select_character(0, candidates[0]):
				return _fail("selection_submit")
		await get_tree().process_frame
	if _controller.state.current_phase == "character_selection":
		return _fail("selection_stuck")
	# 开局技能选择：优先取消；不可取消的强制窗口按规则层下发的首个合法候选确认，避免开局清理永久卡住。
	var opening_safety: int = 0
	while not _controller._pending_card_choice.is_empty() and opening_safety < 24:
		opening_safety += 1
		if not _cancel_pending_choice() and not _confirm_pending_choice():
			return _fail("opening_choice_settle kind=%s chooser=%d" % [str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")), int(_controller._pending_card_choice.get("chooser_id", -1))])
		await get_tree().process_frame
	# 推进到首个出牌阶段；回合开始时机可能再次创建选择，同样按统一出口结算。
	var turn_safety: int = 0
	while _controller.state.current_phase != "play" and turn_safety < 160:
		turn_safety += 1
		if not _controller._pending_card_choice.is_empty():
			if not _cancel_pending_choice() and not _confirm_pending_choice():
				return _fail("turn_choice_settle phase=%s" % str(_controller.state.current_phase))
		_controller.call("_emit_state")
		_controller.call("_ensure_ai_progress_after_resolution")
		await get_tree().process_frame
	if _controller.state.current_phase != "play":
		return _fail("play_phase_not_reached phase=%s turn=%d" % [str(_controller.state.current_phase), _controller.state.turn_number])
	# 相位期间的响应窗口同样需要结算，否则随后的提交会被待办窗口拦截。
	if not await _settle_pending_choices():
		return false
	return true


## 创建指定网络模式的最小正式控制器组件树。
func _create_controller() -> void:
	if _controller != null and is_instance_valid(_controller):
		remove_child(_controller)
		_controller.free()
	_controller = MatchController.new()
	_controller.name = "MatchController"
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	network_gateway.mode = NetworkGateway.Mode.OFFLINE
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0


## 把本用例全部设置写入切换后的独立临时文件，并保存需要恢复的正式状态。
func _begin_settings_isolation() -> void:
	_original_settings_file_path = GameSettings.get_settings_file_path()
	_original_control_all_characters_enabled = GameSettings.control_all_characters_enabled
	GameSettings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)


## 恢复设置、清空临时写盘并删除测试文件。
func _restore_settings() -> void:
	GameSettings.set_control_all_characters_enabled(_original_control_all_characters_enabled)
	GameSettings.flush_pending_settings()
	GameSettings.set("_settings_file_path", _original_settings_file_path)
	if FileAccess.file_exists(TEST_SETTINGS_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_FILE_PATH))


## 失败出口；恢复设置后输出稳定错误标记并退出非零状态。
func _fail(reason: String) -> bool:
	_restore_settings()
	printerr("EXCLUSIVE_CARD_FAIL %s" % reason)
	get_tree().quit(1)
	return false
