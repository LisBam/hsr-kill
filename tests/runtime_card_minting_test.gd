extends Node

## 运行时造牌专项回归：锁定「按已有卡牌定义造出一张自定义牌名的实体牌」的完整链路。
##
## 【为什么需要本用例】造牌把「牌名」从“由 definition_id 决定”变成“由实体决定”，
## 这条约定同时横跨数据层（实例字段与序列化）、核心层（造牌端口、牌名唯一性、洗回摸牌堆）与界面层（牌名解析）。
## 任何一环漂移都会表现为“造出的牌显示成被复制的原牌名 / 读档后自定义牌名消失 / 重名没有被拒绝 /
## 洗回摸牌堆后位次无法复现”，而这些症状分散在三层，因此在这里逐环固定下来。

## 本次测试权威控制器；使用与正式场景同类型的实例并手动装配必需子节点。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false

## 被复制的样例卡牌定义ID；使用基本牌【杀】，便于验证牌效身份仍然是被复制牌。
const SOURCE_DEFINITION_ID: String = "sha"

## 被复制的样例延时锦囊定义ID；用于验证造出的牌在类别上完全继承被复制牌。
const SOURCE_TRICK_DEFINITION_ID: String = "lebu"

## 第一次造牌使用的自定义牌名。
const FIRST_CUSTOM_NAME: String = "进程"

## 第二次造牌使用的自定义牌名。
const SECOND_CUSTOM_NAME: String = "缺陷"

## 铸造来源技能稳定ID；与银狼【以太】一致，用于验证按来源检索。
const MINTED_SKILL_ID: String = "yitai"

## 造牌使用的合法花色。
const SAMPLE_SUIT: String = "heart"

## 造牌使用的合法点数。
const SAMPLE_RANK: int = 13

## 造牌牌名长度上限；**直接取控制器常量**而不是再写一个数字：
## 两处各写一份必然漂移（上限从 12 改到 6 时本用例曾因此误报），边界断言只应跟随权威口径。
const NAME_MAX_LENGTH: int = MatchController.MINT_CARD_NAME_MAX_LENGTH


## 延迟一帧执行全部断言，确保 GameDatabase 已完成卡牌目录扫描。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 按独立状态顺序执行全部断言；任一环节失败都立即停止并报告具体原因。
func _run() -> void:
	_create_controller()
	if not _test_instance_field_round_trip():
		return
	if not _test_legacy_dict_defaults_to_empty():
		return
	if not _test_display_name_resolution_order():
		return
	if not _test_mint_success_writes_fields():
		return
	if not _test_mint_rejections_are_side_effect_free():
		return
	if not _test_name_uniqueness_across_minted_cards():
		return
	if not _test_definition_name_collision_rejected():
		return
	if not _test_minted_card_keeps_rule_identity():
		return
	if not _test_pile_lookup_by_minted_skill():
		return
	if not _test_shuffle_discard_card_into_draw_pile():
		return
	if not _test_authoritative_state_round_trip():
		return
	print("RUNTIME_CARD_MINTING_PASS fields=1 legacy=1 resolve=1 mint=1 reject=1 unique=1 collision=1 identity=1 lookup=1 shuffle=1 roundtrip=1")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关；不加载界面。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能安装与卸载都会在这里订阅与释放时机。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；保持正式实现，避免技能查询走空分支。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；公开快照广播与正式单机模式保持相同路径。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	# 表现间隔归零；规则状态不得依赖计时器，断言在零速度模式下同步完成。
	_controller.game_flow_interval_seconds = 0.0


## 创建最小权威状态；一号领袖、其余反贼形成稳定敌我关系，牌堆与弃牌堆保持为空。
func _reset_state(player_count: int) -> void:
	# 先卸载旧实例；否则上一场景的技能订阅会跨场景继续响应规则时机。
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "runtime-card-minting"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；空手牌使造牌前后的手牌张数变化可直接观察。
		var player: PlayerState = PlayerState.new(player_id, "造牌测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else "rebel"
		player.identity_revealed = true
		player.max_hp = 5
		player.hp = 5
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()


## 实例字段序列化往返：两个造牌字段必须随 to_dict / from_dict 完整往返。
func _test_instance_field_round_trip() -> bool:
	# 手工构造的造牌实体；不经过控制器，直接验证数据层契约。
	var minted_card: CardInstance = CardInstance.new(SOURCE_DEFINITION_ID, SAMPLE_SUIT, SAMPLE_RANK)
	minted_card.custom_display_name = FIRST_CUSTOM_NAME
	minted_card.minted_skill_id = MINTED_SKILL_ID
	if minted_card.get_display_name_override() != FIRST_CUSTOM_NAME:
		return _fail("override_getter=%s" % minted_card.get_display_name_override())
	# 往返后的实体；from_dict 是逐键白名单读取，漏读任一字段都会在这里暴露。
	var restored_card: CardInstance = CardInstance.from_dict(minted_card.to_dict())
	if restored_card.custom_display_name != FIRST_CUSTOM_NAME:
		return _fail("custom_name_lost restored=%s" % restored_card.custom_display_name)
	if restored_card.minted_skill_id != MINTED_SKILL_ID:
		return _fail("minted_skill_lost restored=%s" % restored_card.minted_skill_id)
	if restored_card.definition_id != SOURCE_DEFINITION_ID or restored_card.suit != SAMPLE_SUIT or restored_card.rank != SAMPLE_RANK:
		return _fail("base_fields_changed restored=%s" % [restored_card.to_dict()])
	return true


## 旧存档兼容：不含新字段的旧字典读入后必须得到空字符串，语义与造牌功能引入前完全一致。
func _test_legacy_dict_defaults_to_empty() -> bool:
	# 造牌功能引入前的实体字典形状；只有基础字段。
	var legacy_data: Dictionary = {"uid":9001, "definition_id":SOURCE_DEFINITION_ID, "suit":"spade", "rank":1, "zone":"draw_pile"}
	var legacy_card: CardInstance = CardInstance.from_dict(legacy_data)
	if not legacy_card.custom_display_name.is_empty():
		return _fail("legacy_custom_name=%s" % legacy_card.custom_display_name)
	if not legacy_card.minted_skill_id.is_empty():
		return _fail("legacy_minted_skill=%s" % legacy_card.minted_skill_id)
	# 旧字典往返后仍不含造牌语义；不能因为读入缺省而反向写出非空值。
	var legacy_round_trip: Dictionary = legacy_card.to_dict()
	if not str(legacy_round_trip.get("custom_display_name", "x")).is_empty():
		return _fail("legacy_round_trip_wrote_name=%s" % legacy_round_trip)
	return true


## 牌名解析顺序：自定义牌名优先，为空时回退到按定义解析，且武器攻击范围后缀两种路径口径一致。
func _test_display_name_resolution_order() -> bool:
	# 被复制牌定义；【杀】不是武器，因此两种解析结果都不带范围后缀。
	var source_definition: Dictionary = GameDatabase.get_card(SOURCE_DEFINITION_ID)
	if source_definition.is_empty():
		return _fail("missing_source_definition id=%s" % SOURCE_DEFINITION_ID)
	# 无自定义牌名的实体；解析结果必须与按定义解析逐字节一致，保证既有牌面不变。
	var plain_card: CardInstance = CardInstance.new(SOURCE_DEFINITION_ID, SAMPLE_SUIT, SAMPLE_RANK)
	var plain_resolved: String = GameSettings.resolve_instance_display_name(plain_card.to_dict(), source_definition)
	var definition_resolved: String = GameSettings.resolve_card_display_name(source_definition)
	if plain_resolved != definition_resolved:
		return _fail("plain_resolution_drift instance=%s definition=%s" % [plain_resolved, definition_resolved])
	# 有自定义牌名的实体；两种入口都必须给出自定义牌名。
	plain_card.custom_display_name = FIRST_CUSTOM_NAME
	if GameSettings.resolve_instance_display_name(plain_card.to_dict(), source_definition) != FIRST_CUSTOM_NAME:
		return _fail("instance_display_name_ignored=%s" % GameSettings.resolve_instance_display_name(plain_card.to_dict(), source_definition))
	if GameSettings.resolve_instance_card_name(plain_card.to_dict(), source_definition) != FIRST_CUSTOM_NAME:
		return _fail("instance_base_name_ignored=%s" % GameSettings.resolve_instance_card_name(plain_card.to_dict(), source_definition))
	return true


## 造牌成功分支：返回正 UID、字段正确、牌进入目标手牌、日志与运行时事件都已记录。
func _test_mint_success_writes_fields() -> bool:
	_reset_state(2)
	# 目标玩家手牌张数基线；造牌后必须恰好增加一张。
	var before_hand_size: int = _controller.state.get_player(0).hand.size()
	var minted_uid: int = _controller.mint_card_for_player(0, SOURCE_DEFINITION_ID, FIRST_CUSTOM_NAME, SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID)
	if minted_uid <= 0:
		return _fail("mint_rejected uid=%d" % minted_uid)
	# 造出的实体；必须落在目标玩家手牌区且字段齐全。
	var minted_card: CardInstance = _controller.state.get_player(0).find_hand_card(minted_uid)
	if minted_card == null:
		return _fail("minted_card_not_in_hand uid=%d" % minted_uid)
	if minted_card.custom_display_name != FIRST_CUSTOM_NAME or minted_card.minted_skill_id != MINTED_SKILL_ID:
		return _fail("minted_fields=%s" % [minted_card.to_dict()])
	if minted_card.definition_id != SOURCE_DEFINITION_ID or minted_card.suit != SAMPLE_SUIT or minted_card.rank != SAMPLE_RANK:
		return _fail("minted_base_fields=%s" % [minted_card.to_dict()])
	if _controller.state.get_player(0).hand.size() != before_hand_size + 1:
		return _fail("hand_size=%d expected=%d" % [_controller.state.get_player(0).hand.size(), before_hand_size + 1])
	# 移牌历史；造牌必须留下与既有摸牌/置牌同形的增量，否则表现层看不到这张牌进场。
	# 当前命中的造牌移牌记录；遍历历史取最后一条原因匹配的记录。
	var found_move: bool = false
	for move_variant: Variant in _controller.state.card_move_history:
		# 当前移牌记录；只有原因与目标区域同时匹配才算命中。
		var move_data: Dictionary = move_variant as Dictionary
		if str(move_data.get("reason", "")) == MatchController.MINT_CARD_REASON and str(move_data.get("to_zone", "")) == "hand":
			found_move = true
	if not found_move:
		return _fail("mint_move_missing history=%s" % [_controller.state.card_move_history])
	return true


## 造牌失败分支：定义缺失、重名、空名、超长、含竖线、非法花色、非法点数、玩家无效都必须返回 -1 且零副作用。
func _test_mint_rejections_are_side_effect_free() -> bool:
	_reset_state(2)
	# 先造一张成功牌，占住 FIRST_CUSTOM_NAME，供重名分支使用。
	if _controller.mint_card_for_player(0, SOURCE_DEFINITION_ID, FIRST_CUSTOM_NAME, SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID) <= 0:
		return _fail("setup_mint_rejected")
	# 失败分支清单；每项包含玩家、定义、牌名、花色、点数与人类可读标签。
	var cases: Array[Dictionary] = [
		{"label":"missing_definition", "player_id":0, "definition_id":"__no_such_card__", "name":SECOND_CUSTOM_NAME, "suit":SAMPLE_SUIT, "rank":SAMPLE_RANK},
		{"label":"duplicate_name", "player_id":0, "definition_id":SOURCE_DEFINITION_ID, "name":FIRST_CUSTOM_NAME, "suit":SAMPLE_SUIT, "rank":SAMPLE_RANK},
		{"label":"empty_name", "player_id":0, "definition_id":SOURCE_DEFINITION_ID, "name":"   ", "suit":SAMPLE_SUIT, "rank":SAMPLE_RANK},
		{"label":"too_long", "player_id":0, "definition_id":SOURCE_DEFINITION_ID, "name":"名".repeat(NAME_MAX_LENGTH + 1), "suit":SAMPLE_SUIT, "rank":SAMPLE_RANK},
		{"label":"forbidden_pipe", "player_id":0, "definition_id":SOURCE_DEFINITION_ID, "name":"进程|缺陷", "suit":SAMPLE_SUIT, "rank":SAMPLE_RANK},
		{"label":"forbidden_newline", "player_id":0, "definition_id":SOURCE_DEFINITION_ID, "name":"进程\n缺陷", "suit":SAMPLE_SUIT, "rank":SAMPLE_RANK},
		{"label":"bad_suit", "player_id":0, "definition_id":SOURCE_DEFINITION_ID, "name":SECOND_CUSTOM_NAME, "suit":"joker", "rank":SAMPLE_RANK},
		{"label":"bad_rank_low", "player_id":0, "definition_id":SOURCE_DEFINITION_ID, "name":SECOND_CUSTOM_NAME, "suit":SAMPLE_SUIT, "rank":0},
		{"label":"bad_rank_high", "player_id":0, "definition_id":SOURCE_DEFINITION_ID, "name":SECOND_CUSTOM_NAME, "suit":SAMPLE_SUIT, "rank":14},
		{"label":"bad_player", "player_id":99, "definition_id":SOURCE_DEFINITION_ID, "name":SECOND_CUSTOM_NAME, "suit":SAMPLE_SUIT, "rank":SAMPLE_RANK},
	]
	# 失败前的状态指纹；任一失败分支结束后都必须与它完全一致。
	var hand_before: int = _controller.state.get_player(0).hand.size()
	var move_count_before: int = _controller.state.card_move_history.size()
	for case_data: Dictionary in cases:
		# 当前分支的返回值；必须严格为 -1。
		var result_uid: int = _controller.mint_card_for_player(int(case_data["player_id"]), str(case_data["definition_id"]), str(case_data["name"]), str(case_data["suit"]), int(case_data["rank"]), MINTED_SKILL_ID)
		if result_uid != -1:
			return _fail("%s_returned=%d" % [str(case_data["label"]), result_uid])
		if _controller.state.get_player(0).hand.size() != hand_before or _controller.state.card_move_history.size() != move_count_before:
			return _fail("%s_had_side_effect hand=%d moves=%d" % [str(case_data["label"]), _controller.state.get_player(0).hand.size(), _controller.state.card_move_history.size()])
	return true


## 造牌牌名唯一性：与静态定义不重名时可用；同一牌名第二次造牌必须被拒绝。
func _test_name_uniqueness_across_minted_cards() -> bool:
	_reset_state(2)
	if not _controller.is_card_name_available(SECOND_CUSTOM_NAME):
		return _fail("fresh_name_rejected reason=%s" % _controller.get_card_name_rejection_reason(SECOND_CUSTOM_NAME))
	if _controller.mint_card_for_player(0, SOURCE_DEFINITION_ID, SECOND_CUSTOM_NAME, SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID) <= 0:
		return _fail("first_mint_rejected")
	# 已造出的牌名必须进入可用性判据；否则同一局可以造出两张同名牌。
	if _controller.is_card_name_available(SECOND_CUSTOM_NAME):
		return _fail("minted_name_still_available")
	# 造出的牌名必须出现在收集结果里；顺序为固定遍历顺序，因此只需成员判定。
	if not _controller.collect_minted_card_names().has(SECOND_CUSTOM_NAME):
		return _fail("collected_names=%s" % [_controller.collect_minted_card_names()])
	# 边界：恰好等于上限的牌名可用，超出一个字符即不可用。
	var max_length_name: String = "名".repeat(NAME_MAX_LENGTH)
	if not _controller.is_card_name_available(max_length_name):
		return _fail("max_length_rejected reason=%s" % _controller.get_card_name_rejection_reason(max_length_name))
	if _controller.is_card_name_available("名".repeat(NAME_MAX_LENGTH + 1)):
		return _fail("over_length_accepted")
	return true


## 与静态定义重名：原版名与项目名两个口径都必须被拒绝，否则信息框标题会被解析器改写。
func _test_definition_name_collision_rejected() -> bool:
	_reset_state(2)
	# 被复制牌的定义元数据；取其两个登记名称作为重名样本。
	var source_definition: Dictionary = GameDatabase.get_card(SOURCE_DEFINITION_ID)
	for field_name: String in ["original_name", "custom_name"]:
		# 当前登记名称；缺失时跳过，避免把空字符串当成一次有效样本。
		var registered_name: String = str(source_definition.get(field_name, "")).strip_edges()
		if registered_name.is_empty():
			continue
		if GameDatabase.is_card_display_name_taken(registered_name):
			if _controller.is_card_name_available(registered_name):
				return _fail("controller_accepted_registered_name=%s" % registered_name)
		else:
			return _fail("database_missed_registered_name=%s" % registered_name)
		if _controller.mint_card_for_player(0, SOURCE_DEFINITION_ID, registered_name, SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID) != -1:
			return _fail("mint_accepted_registered_name=%s" % registered_name)
	# 未登记的名称不应被误判为重名。
	if GameDatabase.is_card_display_name_taken("绝无此牌名甲乙丙"):
		return _fail("database_false_positive")
	return true


## 规则身份继承：造出的牌 definition_id 等于被复制牌，因此仍按被复制牌参与规则判定。
func _test_minted_card_keeps_rule_identity() -> bool:
	_reset_state(2)
	# 复制延时锦囊造牌；验证类别、目标模式与响应模式随定义自动继承，不需要逐字段搬运。
	var minted_uid: int = _controller.mint_card_for_player(0, SOURCE_TRICK_DEFINITION_ID, SECOND_CUSTOM_NAME, SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID)
	if minted_uid <= 0:
		return _fail("trick_mint_rejected uid=%d" % minted_uid)
	# 造出的实体；定义引用必须仍是被复制牌，牌名才与规则身份分离。
	var minted_card: CardInstance = _controller.state.get_player(0).find_hand_card(minted_uid)
	if minted_card == null or minted_card.definition_id != SOURCE_TRICK_DEFINITION_ID:
		return _fail("trick_definition=%s" % [minted_card.to_dict() if minted_card != null else {}])
	# 定义元数据未被子类化或覆盖：造牌不写任何 GameDatabase 容器。
	var source_definition: Dictionary = GameDatabase.get_card(SOURCE_TRICK_DEFINITION_ID)
	var minted_definition: Dictionary = GameDatabase.get_card(minted_card.definition_id)
	if str(minted_definition.get("type", "")) != str(source_definition.get("type", "")):
		return _fail("type_drift minted=%s source=%s" % [minted_definition.get("type"), source_definition.get("type")])
	# 数据库不得因为造牌而新增定义；这是“不污染图鉴与静态卡表”不变式。
	if GameDatabase.cards.has(SECOND_CUSTOM_NAME) or GameDatabase.cards.has(minted_card.definition_id + "_minted"):
		return _fail("database_polluted")
	return true


## 按铸造来源检索：摸牌堆与弃牌堆两个口径都要能找出由指定技能创造的牌，并按堆顶优先排序。
func _test_pile_lookup_by_minted_skill() -> bool:
	_reset_state(2)
	# 造三张牌，随后手动移入两个牌堆；铸造来源全部为 MINTED_SKILL_ID。
	var minted_uids: Array[int] = []
	for index: int in range(3):
		# 当前造牌牌名；三次必须互不相同。
		var current_name: String = "%s%d" % [SECOND_CUSTOM_NAME, index]
		var current_uid: int = _controller.mint_card_for_player(0, SOURCE_DEFINITION_ID, current_name, SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID)
		if current_uid <= 0:
			return _fail("lookup_setup_mint_%d uid=%d" % [index, current_uid])
		minted_uids.append(current_uid)
	# 前两张移入摸牌堆（依次追加，末张为堆顶），第三张移入弃牌堆。
	for index: int in range(2):
		# 当前实体；按 UID 定位后走统一移牌通路。
		var card: CardInstance = _controller.state.get_player(0).find_hand_card(minted_uids[index])
		if card == null:
			return _fail("lookup_setup_card_missing index=%d" % index)
		_controller.card_movement.move_card(card, "draw_pile", -1, "lookup_setup")
	# 第三张移入弃牌堆。
	var discard_card: CardInstance = _controller.state.get_player(0).find_hand_card(minted_uids[2])
	if discard_card == null:
		return _fail("lookup_setup_discard_missing")
	_controller.card_movement.move_card(discard_card, "discard_pile", -1, "lookup_setup")
	# 摸牌堆检索；从堆顶向下，因此第二张先于第一张。
	var draw_uids: Array[int] = _controller.get_draw_pile_card_uids_by_skill(MINTED_SKILL_ID)
	if draw_uids != [minted_uids[1], minted_uids[0]]:
		return _fail("draw_lookup=%s expected=%s" % [draw_uids, [minted_uids[1], minted_uids[0]]])
	# 弃牌堆检索；只有第三张。
	var discard_uids: Array[int] = _controller.get_discard_pile_card_uids_by_skill(MINTED_SKILL_ID)
	if discard_uids != [minted_uids[2]]:
		return _fail("discard_lookup=%s" % [discard_uids])
	# 未铸造来源必须查不到任何牌，且空来源不返回全部牌。
	if not _controller.get_draw_pile_card_uids_by_skill("__no_such_skill__").is_empty():
		return _fail("unknown_skill_matched")
	if not _controller.get_draw_pile_card_uids_by_skill("").is_empty():
		return _fail("empty_skill_matched")
	# 获得入口：先摸牌堆后弃牌堆，取第一张命中的牌入手。
	if not _controller.gain_top_minted_card_from_draw_or_discard(1, MINTED_SKILL_ID):
		return _fail("gain_from_draw_rejected")
	if _controller.state.get_player(1).find_hand_card(minted_uids[1]) == null:
		return _fail("gain_picked_wrong_card hand=%s" % [_controller.state.get_player(1).hand.map(func(card: CardInstance) -> int: return card.uid)])
	# 摸牌堆只剩第一张，第二次获得应取到它。
	if not _controller.gain_top_minted_card_from_draw_or_discard(1, MINTED_SKILL_ID):
		return _fail("second_gain_rejected")
	if _controller.state.get_player(1).find_hand_card(minted_uids[0]) == null:
		return _fail("second_gain_wrong_card")
	# 第三次获得回落到弃牌堆的第三张。
	if not _controller.gain_top_minted_card_from_draw_or_discard(1, MINTED_SKILL_ID):
		return _fail("third_gain_rejected")
	if _controller.state.get_player(1).find_hand_card(minted_uids[2]) == null:
		return _fail("third_gain_wrong_card")
	# 全部取完后必须返回 false 且零副作用。
	if _controller.gain_top_minted_card_from_draw_or_discard(1, MINTED_SKILL_ID):
		return _fail("gain_after_exhausted_succeeded")
	return true


## 洗回摸牌堆：位次必须写入随机历史、牌必须离开弃牌堆、非弃牌堆的牌必须被拒绝。
func _test_shuffle_discard_card_into_draw_pile() -> bool:
	_reset_state(2)
	# 造一张牌并放入弃牌堆；这是洗回端口的唯一合法输入。
	var minted_uid: int = _controller.mint_card_for_player(0, SOURCE_DEFINITION_ID, SECOND_CUSTOM_NAME, SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID)
	if minted_uid <= 0:
		return _fail("shuffle_setup_mint uid=%d" % minted_uid)
	# 造出的实体；从手牌移入弃牌堆。
	var minted_card: CardInstance = _controller.state.get_player(0).find_hand_card(minted_uid)
	if minted_card == null:
		return _fail("shuffle_setup_card_missing")
	_controller.card_movement.move_card(minted_card, "discard_pile", -1, "shuffle_setup")
	# 随机历史基线；洗回必须恰好新增一条位次记录。
	var history_before: int = _controller.state.random_history.size()
	if not _controller.shuffle_discard_card_into_draw_pile(minted_uid):
		return _fail("shuffle_rejected")
	if minted_card.zone != "draw_pile":
		return _fail("shuffle_zone=%s" % minted_card.zone)
	if _controller.state.discard_pile.has(minted_card):
		return _fail("shuffle_left_in_discard")
	if not _controller.state.draw_pile.has(minted_card):
		return _fail("shuffle_not_in_draw_pile")
	if _controller.state.random_history.size() != history_before + 1:
		return _fail("shuffle_history_delta=%d" % (_controller.state.random_history.size() - history_before))
	# 新增的位次记录；kind 与位次都必须存在，回放才能复现同一牌序。
	var history_entry: Dictionary = _controller.state.random_history[_controller.state.random_history.size() - 1]
	if str(history_entry.get("kind", "")) != MatchController.MINT_CARD_SHUFFLE_HISTORY_KIND:
		return _fail("shuffle_history_kind=%s" % history_entry)
	if int(history_entry.get("position", 0)) < 1 or int(history_entry.get("card_uid", -1)) != minted_uid:
		return _fail("shuffle_history_entry=%s" % [history_entry])
	# 洗回后必须恢复为无人知晓；否则弃牌堆的公开知识会残留到牌堆里。
	if not minted_card.known_to.is_empty() or minted_card.shown or minted_card.private_owner_id != -1:
		return _fail("shuffle_knowledge_kept card=%s" % [minted_card.to_dict()])
	# 不在弃牌堆的牌必须被拒绝且零副作用：此时它已在摸牌堆。
	var history_after_first: int = _controller.state.random_history.size()
	if _controller.shuffle_discard_card_into_draw_pile(minted_uid):
		return _fail("shuffle_accepts_non_discard_card")
	if _controller.state.random_history.size() != history_after_first:
		return _fail("rejected_shuffle_wrote_history")
	# 不存在的 UID 同样必须被拒绝。
	if _controller.shuffle_discard_card_into_draw_pile(-12345):
		return _fail("shuffle_accepts_unknown_uid")
	return true


## 权威存档往返：造牌字段必须随 GameState 一起保存与恢复。
func _test_authoritative_state_round_trip() -> bool:
	_reset_state(2)
	# 分别在摸牌堆、弃牌堆与手牌各留一张造牌，覆盖三条区域序列化路径。
	var hand_uid: int = _controller.mint_card_for_player(0, SOURCE_DEFINITION_ID, "手牌造牌", SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID)
	var draw_uid: int = _controller.mint_card_for_player(0, SOURCE_DEFINITION_ID, "牌堆造牌", SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID)
	var discard_uid: int = _controller.mint_card_for_player(0, SOURCE_DEFINITION_ID, "弃牌造牌", SAMPLE_SUIT, SAMPLE_RANK, MINTED_SKILL_ID)
	if hand_uid <= 0 or draw_uid <= 0 or discard_uid <= 0:
		return _fail("round_trip_setup uids=%s" % [[hand_uid, draw_uid, discard_uid]])
	# 两张移出：一张进摸牌堆、一张进弃牌堆。
	var draw_card: CardInstance = _controller.state.get_player(0).find_hand_card(draw_uid)
	var discard_card: CardInstance = _controller.state.get_player(0).find_hand_card(discard_uid)
	if draw_card == null or discard_card == null:
		return _fail("round_trip_setup_card_missing")
	_controller.card_movement.move_card(draw_card, "draw_pile", -1, "round_trip_setup")
	_controller.card_movement.move_card(discard_card, "discard_pile", -1, "round_trip_setup")
	# 权威存档数据；手工拼装成与正式存档相同的形状（牌堆数组 + 每名玩家的权威字典），
	# 不使用征服模式的存档构建入口：本用例只关心实体牌字段的序列化，与对局模式无关。
	var save_data: Dictionary = {
		"draw_pile": _serialize_pile(_controller.state.draw_pile),
		"discard_pile": _serialize_pile(_controller.state.discard_pile),
		"players": [],
	}
	for player: PlayerState in _controller.state.players:
		# reveal_private 置真：本用例验证的是实体牌字段的序列化，手牌必须按权威存档口径完整写出。
		(save_data["players"] as Array).append(player.to_dict(-1, true))
	# 恢复后的实体集合；按 UID 索引，便于逐张核对。
	var restored_by_uid: Dictionary = {}
	_collect_restored_cards(save_data, restored_by_uid)
	for expected_uid: int in [hand_uid, draw_uid, discard_uid]:
		# 当前恢复实体；缺失即说明该区域的序列化路径丢了造牌字段或整张牌。
		var restored_card: CardInstance = restored_by_uid.get(expected_uid) as CardInstance
		if restored_card == null:
			return _fail("restore_missing uid=%d restored=%s" % [expected_uid, restored_by_uid.keys()])
		if restored_card.custom_display_name.is_empty() or restored_card.minted_skill_id != MINTED_SKILL_ID:
			return _fail("restore_lost_fields uid=%d card=%s" % [expected_uid, restored_card.to_dict()])
		if restored_card.definition_id != SOURCE_DEFINITION_ID:
			return _fail("restore_lost_definition uid=%d card=%s" % [expected_uid, restored_card.to_dict()])
	return true


## 把牌堆序列化为与 CardInstance.to_dict() 同形的字典数组；顺序保持数组原序。
func _serialize_pile(pile: Array) -> Array:
	# 序列化结果；调用方把它当作存档里的牌堆字段使用。
	var serialized: Array = []
	for card: CardInstance in pile:
		serialized.append(card.to_dict())
	return serialized


## 从权威存档数据中按 UID 收集全部实体牌；覆盖摸牌堆、弃牌堆与每名玩家的各私有区域。
func _collect_restored_cards(save_data: Dictionary, restored_by_uid: Dictionary) -> void:
	for pile_key: String in ["draw_pile", "discard_pile"]:
		for card_variant: Variant in save_data.get(pile_key, []) as Array:
			# 当前恢复实体；使用与正式读档完全相同的 from_dict 入口。
			var card: CardInstance = CardInstance.from_dict(card_variant as Dictionary)
			restored_by_uid[card.uid] = card
	for player_variant: Variant in save_data.get("players", []) as Array:
		# 当前恢复玩家；先按正式读档入口重建，再读取与实体牌相关的四个区域。
		var restored_player: PlayerState = PlayerState.from_authoritative_dict(player_variant as Dictionary)
		if restored_player == null:
			continue
		for card: CardInstance in restored_player.hand:
			restored_by_uid[card.uid] = card
		for slot_variant: Variant in restored_player.equipment.values():
			var equipment_card: CardInstance = slot_variant as CardInstance
			if equipment_card != null:
				restored_by_uid[equipment_card.uid] = equipment_card
		for card: CardInstance in restored_player.judgment_area:
			restored_by_uid[card.uid] = card
		for card: CardInstance in restored_player.wooden_ox_storage:
			restored_by_uid[card.uid] = card


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("RUNTIME_CARD_MINTING_FAIL %s" % message)
	get_tree().quit(1)
	return false
