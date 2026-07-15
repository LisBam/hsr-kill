extends Node

## 本地手牌内联选择回归。验证响应与弃牌不打开独立窗口，并正确控制候选牌、按钮和多选数量。

## 正式主场景稳定等待帧数；覆盖延迟开局失败提示与首轮界面节点初始化。
const SETTLE_FRAME_COUNT: int = 4


## 延迟执行界面回归，确保测试节点已经进入场景树。
func _ready() -> void:
	call_deferred("_run")


## 注入包含两张手牌的本地快照，依次验证单张响应、强制多选弃牌和公共展示牌窗口。
func _run() -> void:
	# 正式主场景资源；内联选择必须覆盖玩家实际运行的桌面与操作按钮。
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
	# 测试手牌快照；普通【杀】应灰显，【闪】应成为唯一可交互响应候选。
	var slash_data: Dictionary = {"uid":7001, "definition_id":"sha", "suit":"spade", "rank":7, "zone":"hand", "owner_id":0}
	# 测试【闪】快照；点击后确认按钮才允许提交。
	var dodge_data: Dictionary = {"uid":7002, "definition_id":"shan", "suit":"heart", "rank":2, "zone":"hand", "owner_id":0}
	match_controller.state_changed.emit(_make_snapshot([slash_data, dodge_data], 11))
	await get_tree().process_frame
	# 单张【闪】请求；候选全部属于本人手牌，因此必须使用底部内联选择。
	var response_request: Dictionary = {
		"request_id":11,
		"chooser_id":0,
		"title":"响应询问",
		"prompt":"是否打出【闪】响应【杀】？",
		"candidates":[_candidate(dodge_data)],
		"min_select":0,
		"max_select":1,
		"allow_cancel":true,
		"context":{"kind":"slash_response"},
	}
	main_instance.call("_on_card_choice_requested", response_request)
	await get_tree().process_frame
	# 独立选择面板；本人手牌响应期间必须保持关闭。
	var selection_panel: CardSelectionPanel = main_instance.get_node("CardSelectionPanel") as CardSelectionPanel
	# 底部确认按钮；未选择候选前必须禁用。
	var confirm_button: Button = main_instance.get_node("%UseButton") as Button
	# 底部取消按钮；可取消响应必须显示并允许点击。
	var cancel_button: Button = main_instance.get_node("%CancelButton") as Button
	# 回合结束按钮；内联请求期间只保留确定与取消，不应继续显示普通出牌操作。
	var end_play_button: Button = main_instance.get_node("%EndPlayButton") as Button
	# 当前手牌视图映射；用于验证候选交互和非候选灰显状态。
	var response_card_views: Dictionary = main_instance.get("_card_views") as Dictionary
	# 非候选【杀】视图；必须禁用输入并使用更低亮度纸张。
	var disabled_slash_view: CardView = response_card_views.get(7001) as CardView
	# 候选【闪】视图；必须保留正常亮度和交互能力。
	var enabled_dodge_view: CardView = response_card_views.get(7002) as CardView
	# 非候选【杀】纸张节点；用于读取禁用状态下的场景样式。
	var disabled_slash_body: Panel = disabled_slash_view.get_node("CardBody") as Panel
	# 候选【闪】纸张节点；用于读取正常交互状态下的场景样式。
	var enabled_dodge_body: Panel = enabled_dodge_view.get_node("CardBody") as Panel
	# 非候选【杀】最终纸张样式；用于读取深灰禁用亮度。
	var disabled_style: StyleBoxFlat = disabled_slash_body.get_theme_stylebox("panel") as StyleBoxFlat
	# 候选【闪】最终纸张样式；用于读取正常可交互亮度。
	var enabled_style: StyleBoxFlat = enabled_dodge_body.get_theme_stylebox("panel") as StyleBoxFlat
	if selection_panel.visible or disabled_slash_view.is_interactable or not enabled_dodge_view.is_interactable or enabled_style.bg_color.get_luminance() - disabled_style.bg_color.get_luminance() < 0.2 or not confirm_button.disabled or not cancel_button.visible or cancel_button.disabled or end_play_button.visible:
		_fail("response_inline_state")
		return
	main_instance.call("_on_card_pressed", 7002)
	if confirm_button.disabled or not enabled_dodge_view.is_card_selected:
		_fail("response_confirm_state")
		return
	# 强制弃牌请求；两张手牌都可选择，必须选满2张后确认才启用，取消按钮保持可见但禁用。
	var discard_request: Dictionary = {
		"request_id":12,
		"chooser_id":0,
		"title":"弃牌阶段",
		"prompt":"请选择2张手牌弃置",
		"candidates":[_candidate(slash_data), _candidate(dodge_data)],
		"min_select":2,
		"max_select":2,
		"allow_cancel":false,
		"context":{"kind":"discard_phase"},
	}
	main_instance.call("_on_card_choice_requested", discard_request)
	main_instance.call("_on_card_pressed", 7001)
	if not confirm_button.disabled or not cancel_button.visible or not cancel_button.disabled:
		_fail("discard_partial_state")
		return
	main_instance.call("_on_card_pressed", 7002)
	if confirm_button.disabled or (main_instance.get("_inline_selected_card_uids") as Array).size() != 2:
		_fail("discard_complete_state")
		return
	# 公共展示牌请求；候选不属于本人手牌，必须继续使用独立 CardSelectionPanel。
	var harvest_card_data: Dictionary = {"uid":7003, "definition_id":"tao", "suit":"heart", "rank":3, "zone":"processing", "owner_id":-1}
	# 五谷请求；用于验证展示区没有被内联分类误吞。
	var harvest_request: Dictionary = {
		"request_id":13,
		"chooser_id":0,
		"title":"五谷丰登",
		"prompt":"请选择一张展示牌获得",
		"candidates":[_candidate(harvest_card_data)],
		"min_select":1,
		"max_select":1,
		"allow_cancel":false,
		"context":{"kind":"harvest"},
	}
	main_instance.call("_on_card_choice_requested", harvest_request)
	await get_tree().process_frame
	if not selection_panel.visible or not (main_instance.get("_inline_card_choice") as Dictionary).is_empty():
		_fail("harvest_modal_state")
		return
	# 本地普通出牌快照；权威 chooseToUse 只列出【杀】，响应专用【闪】即使轮到本人也必须保持禁用灰显。
	var play_snapshot: Dictionary = _make_snapshot([slash_data, dodge_data], 14)
	play_snapshot["current_player_id"] = 0
	play_snapshot["current_phase"] = "play"
	play_snapshot["current_choice_request"] = {"request_id":14, "event_id":14, "actor_id":0, "choice_type":"use", "card_ids":[7001]}
	match_controller.state_changed.emit(play_snapshot)
	await get_tree().process_frame
	# 出牌阶段手牌视图；可用性必须逐牌读取 chooseToUse 候选，而不是把整手牌一起启用。
	var play_card_views: Dictionary = main_instance.get("_card_views") as Dictionary
	# 出牌阶段可用【杀】；存在合法动作时保留完整亮度与输入。
	var playable_slash_view: CardView = play_card_views.get(7001) as CardView
	# 出牌阶段不可用【闪】；没有任何合法动作时禁用输入并加深灰显。
	var unusable_dodge_view: CardView = play_card_views.get(7002) as CardView
	# 可用【杀】纸张节点；用于读取正常出牌亮度。
	var playable_slash_body: Panel = playable_slash_view.get_node("CardBody") as Panel
	# 不可用【闪】纸张节点；用于验证普通出牌阶段同样应用深灰禁用样式。
	var unusable_dodge_body: Panel = unusable_dodge_view.get_node("CardBody") as Panel
	# 可用【杀】最终纸张样式；作为正常亮度基准。
	var playable_slash_style: StyleBoxFlat = playable_slash_body.get_theme_stylebox("panel") as StyleBoxFlat
	# 不可用【闪】最终纸张样式；与基准亮度差至少0.2保证禁用状态不是轻微变暗。
	var unusable_dodge_style: StyleBoxFlat = unusable_dodge_body.get_theme_stylebox("panel") as StyleBoxFlat
	if not playable_slash_view.is_interactable or unusable_dodge_view.is_interactable or playable_slash_style.bg_color.get_luminance() - unusable_dodge_style.bg_color.get_luminance() < 0.2:
		_fail("play_phase_card_availability")
		return
	remove_child(main_instance)
	main_instance.free()
	await get_tree().process_frame
	print("INLINE_HAND_CHOICE_PASS")
	get_tree().quit(0)


## 把卡牌快照包装成统一选择候选；可见性与所有者字段和正式控制器输出一致。
func _candidate(card_data: Dictionary) -> Dictionary:
	return {
		"uid":int(card_data.get("uid", -1)),
		"owner_id":int(card_data.get("owner_id", -1)),
		"zone":str(card_data.get("zone", "")),
		"slot":"",
		"visible":true,
		"card_data":card_data.duplicate(true),
	}


## 构造本地观察者快照；只包含内联选择需要的手牌、阶段和运行时请求标识。
func _make_snapshot(hand_cards: Array, request_id: int) -> Dictionary:
	# 本地玩家快照；完整手牌仅对0号观察者公开。
	var local_player: Dictionary = {
		"player_id":0,
		"seat_number":1,
		"display_name":"本地玩家",
		"character_id":"trailblazer",
		"identity":"lord",
		"hp":4,
		"max_hp":4,
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
		"turn_number":1,
		"draw_pile_count":100,
		"discard_pile_count":0,
		"game_over":false,
	}


## 输出稳定失败原因并以非0状态退出，便于命令行定位具体内联交互断言。
func _fail(reason: String) -> void:
	printerr("INLINE_HAND_CHOICE_FAIL %s" % reason)
	get_tree().quit(1)
