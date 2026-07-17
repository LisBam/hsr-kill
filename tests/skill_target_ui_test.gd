extends Node

## 技能目标选择界面回归。验证纯目标请求与牌目标组合请求复用牌桌临时选择，不打开独立卡牌窗口。

## 正式主场景初始化等待帧数；保证武将视图和中央按钮已经完成绑定。
const SETTLE_FRAME_COUNT: int = 4


## 延迟运行界面断言，避免主场景就绪流程与测试快照同时写入。
func _ready() -> void:
	call_deferred("_run")


## 注入两名玩家与一张本地手牌，依次验证选目标和牌目标组合的高亮、选择与确认状态。
func _run() -> void:
	# 正式牌桌；技能目标必须复用真实玩家视图与操作按钮。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	# 正式桌面实例；测试只注入裁剪后的只读快照。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	# 对局控制器；非法1人配置阻止自动身份局干扰测试快照。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	match_controller.default_player_count = 1
	match_controller.local_human_player_id = 0
	match_controller.randomize_local_human_seat = false
	# 主场景稳定帧；逐帧等待动态玩家视图和操作组件完成初始化。
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 本地组合选择材料牌；只用于界面候选和选中状态。
	var material_card: Dictionary = {"uid":801, "definition_id":"shan", "suit":"heart", "rank":2, "zone":"hand", "owner_id":0}
	match_controller.state_changed.emit(_make_snapshot(material_card, 21))
	await get_tree().process_frame
	# 纯目标请求；没有卡牌候选时仍应使用内联目标交互。
	var target_request: Dictionary = {
		"request_id":21,
		"chooser_id":0,
		"choice_type":"target",
		"title":"选择目标",
		"prompt":"请选择一名目标",
		"candidates":[],
		"target_ids":[1],
		"min_select":1,
		"max_select":1,
		"min_card_select":0,
		"max_card_select":0,
		"min_target_select":1,
		"max_target_select":1,
		"allow_cancel":true,
		"context":{"kind":"ui_target_test"},
	}
	main_instance.call("_on_card_choice_requested", target_request)
	await get_tree().process_frame
	# 独立卡牌选择面板；纯目标请求期间必须保持关闭。
	var selection_panel: CardSelectionPanel = main_instance.get_node("CardSelectionPanel") as CardSelectionPanel
	# 中央确认按钮；选择目标前禁用，选择完成后启用。
	var confirm_button: Button = main_instance.get_node("%UseButton") as Button
	# 当前全部玩家视图；按稳定玩家 ID 定位目标组件。
	var player_views: Dictionary = main_instance.get("_player_views") as Dictionary
	# 1号目标玩家视图；用于验证合法目标和已选目标描边状态。
	var target_view: PlayerTargetView = player_views.get(1) as PlayerTargetView
	if selection_panel.visible or confirm_button.disabled == false or target_view == null or not target_view.is_legal_target or target_view.is_target_selected:
		_fail("target_initial")
		return
	main_instance.call("_on_target_pressed", 1)
	if confirm_button.disabled or not target_view.is_target_selected:
		_fail("target_selected")
		return
	# 牌目标组合请求；选择材料后目标仍由同一武将牌交互，并满足两个维度后才允许确认。
	# 本地材料候选；保持与正式 card_choice_requested 快照结构一致。
	var candidate: Dictionary = {"uid":801, "owner_id":0, "zone":"hand", "slot":"", "visible":true, "card_data":material_card.duplicate(true)}
	# 组合请求快照；分别要求1张牌和1名目标，并声明牌801只能选择目标1。
	var combined_request: Dictionary = {
		"request_id":22,
		"chooser_id":0,
		"choice_type":"card_target",
		"title":"选择牌和目标",
		"prompt":"请选择一张牌和一名目标",
		"candidates":[candidate],
		"target_ids":[1],
		"min_select":1,
		"max_select":1,
		"min_card_select":1,
		"max_card_select":1,
		"min_target_select":1,
		"max_target_select":1,
		"allow_cancel":true,
		"context":{"kind":"ui_card_target_test", "target_ids_by_card_id":{"801":[1]}},
	}
	main_instance.call("_on_card_choice_requested", combined_request)
	main_instance.call("_on_card_pressed", 801)
	if not confirm_button.disabled or not target_view.is_legal_target:
		_fail("combined_card_only")
		return
	main_instance.call("_on_target_pressed", 1)
	if confirm_button.disabled or not target_view.is_target_selected:
		_fail("combined_complete")
		return
	print("SKILL_TARGET_UI_PASS")
	get_tree().quit(0)


## 构造本地观察者快照；只包含技能目标选择需要的公开玩家与本地手牌。
func _make_snapshot(material_card: Dictionary, request_id: int) -> Dictionary:
	# 本地玩家；手牌完整可见。
	var local_player: Dictionary = {"player_id":0, "seat_number":1, "display_name":"本地玩家", "character_id":"trailblazer", "identity":"lord", "hp":4, "max_hp":4, "alive":true, "chained":false, "hand_count":1, "hand":[material_card.duplicate(true)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "wooden_ox_storage_count":0}
	# 目标玩家；只需要公开武将状态。
	var target_player: Dictionary = {"player_id":1, "seat_number":2, "display_name":"目标玩家", "character_id":"march7th", "identity":"rebel", "hp":4, "max_hp":4, "alive":true, "chained":false, "hand_count":0, "hand":[], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "wooden_ox_storage_count":0}
	return {"players":[local_player, target_player], "current_player_id":0, "current_phase":"choice", "current_choice_request":{"request_id":request_id, "actor_id":0}, "turn_number":1, "draw_pile_count":100, "discard_pile_count":0, "game_over":false}


## 输出失败原因并以非0状态结束。
func _fail(reason: String) -> void:
	printerr("SKILL_TARGET_UI_FAIL %s" % reason)
	get_tree().quit(1)
