extends Node

## 本地手牌内联选择回归。验证响应与弃牌不打开独立窗口，并正确控制候选牌、按钮和多选数量。
## 同一回归同时验证本地装备候选不打开独立窗口、候选横条右移、五个空槽常驻和宝物牌面原位覆盖。

## 正式主场景稳定等待帧数；覆盖延迟开局失败提示与首轮界面节点初始化。
const SETTLE_FRAME_COUNT: int = 4

## 开启“不响应该锦囊”后按钮背景允许的最大亮度；0.20确保其明显暗于普通朱红按钮。
const END_PLAY_BUTTON_TEST_LUMINANCE: float = 0.20


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
	# 通用选择摘要；内联询问不再显示“响应询问｜已选择｜需要”这类重复状态文本。
	var selection_label: Label = main_instance.get_node("%SelectionLabel") as Label
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
	# 禁用确定按钮样式；不可提交时必须使用固定深灰背景，而不是沿用可交互悬停外观。
	var disabled_confirm_style: StyleBoxFlat = confirm_button.get_theme_stylebox("disabled") as StyleBoxFlat
	# 可用确定按钮样式；作为禁用按钮亮度差的基准，不改变当前 disabled 状态。
	var normal_confirm_style: StyleBoxFlat = confirm_button.get_theme_stylebox("normal") as StyleBoxFlat
	if selection_panel.visible or disabled_slash_view.is_interactable or not enabled_dodge_view.is_interactable or enabled_style.bg_color.get_luminance() - disabled_style.bg_color.get_luminance() < 0.2 or not confirm_button.disabled or normal_confirm_style.bg_color.get_luminance() - disabled_confirm_style.bg_color.get_luminance() < 0.1 or not cancel_button.visible or cancel_button.disabled or end_play_button.visible or selection_label.visible or not selection_label.text.is_empty():
		_fail("response_inline_state")
		return
	main_instance.call("_on_card_pressed", 7002)
	if confirm_button.disabled or not enabled_dodge_view.is_card_selected:
		_fail("response_confirm_state")
		return
	# 群体锦囊无懈询问；右侧按钮应替换为本次锦囊的不响应开关。
	var group_trick_request: Dictionary = {
		"request_id":111,
		"chooser_id":0,
		"title":"响应询问",
		"prompt":"是否使用【无懈可击】？",
		"candidates":[_candidate(dodge_data)],
		"min_select":0,
		"max_select":1,
		"allow_cancel":true,
		"context":{"kind":"trick_negation", "trick_id":"wugu", "parent_card_uid":9900},
	}
	main_instance.call("_on_card_choice_requested", group_trick_request)
	await get_tree().process_frame
	if not end_play_button.visible or end_play_button.text != "不响应该锦囊" or int(main_instance.get("_suppressed_group_trick_uid")) >= 0:
		_fail("group_trick_toggle_available")
		return
	main_instance.call("_on_end_play_pressed")
	# 开启状态样式；背景必须比普通朱红按钮更暗，且同一父锦囊的后续请求会被识别为自动跳过。
	var suppressed_button_style: StyleBoxFlat = end_play_button.get_theme_stylebox("normal") as StyleBoxFlat
	if int(main_instance.get("_suppressed_group_trick_uid")) != 9900 or suppressed_button_style.bg_color.get_luminance() >= END_PLAY_BUTTON_TEST_LUMINANCE or not bool(main_instance.call("_is_suppressed_group_trick_choice", group_trick_request)):
		_fail("group_trick_toggle_enabled")
		return
	main_instance.call("_on_end_play_pressed")
	if int(main_instance.get("_suppressed_group_trick_uid")) >= 0:
		_fail("group_trick_toggle_cancelled")
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
	# 同名字数选择测试【决斗】；其二字牌名与一字的【杀】【闪】不兼容。
	var duel_data: Dictionary = {"uid":7003, "definition_id":"juedou", "suit":"spade", "rank":1, "zone":"hand", "owner_id":0}
	match_controller.state_changed.emit(_make_snapshot([slash_data, dodge_data, duel_data], 120))
	await get_tree().process_frame
	# 录事式固定合法组合请求；选中【杀】后只能继续选择同为一字牌名的【闪】。
	var matching_name_request: Dictionary = {
		"request_id":120,
		"chooser_id":0,
		"title":"选择同名字数牌",
		"prompt":"请选择两张牌名字数相同的牌",
		"candidates":[_candidate(slash_data), _candidate(dodge_data), _candidate(duel_data)],
		"min_select":2,
		"max_select":2,
		"allow_cancel":true,
		"context":{"kind":"lushi_cards", "valid_card_combinations":[[7001, 7002]]},
	}
	main_instance.call("_on_card_choice_requested", matching_name_request)
	main_instance.call("_on_card_pressed", 7001)
	await get_tree().process_frame
	# 动态更新后的手牌视图；兼容牌保持可选，不可能完成合法组合的牌必须立即暗置。
	var matching_card_views: Dictionary = main_instance.get("_card_views") as Dictionary
	# 已选【杀】视图；已选候选必须继续保留交互，允许玩家撤销选择。
	var selected_slash_view: CardView = matching_card_views.get(7001) as CardView
	# 兼容【闪】视图；与已选【杀】构成唯一合法组合，应保持明亮可选。
	var compatible_dodge_view: CardView = matching_card_views.get(7002) as CardView
	# 不兼容【决斗】视图；当前选择下无法构成合法组合，应动态暗置且禁止点击。
	var incompatible_duel_view: CardView = matching_card_views.get(7003) as CardView
	if selected_slash_view == null or compatible_dodge_view == null or incompatible_duel_view == null or not selected_slash_view.is_interactable or not compatible_dodge_view.is_interactable or incompatible_duel_view.is_interactable:
		_fail("dynamic_valid_card_combination")
		return
	# 测试武器装备；与手牌候选共用统一实体 UID 选择协议。
	var weapon_data: Dictionary = {"uid":7004, "definition_id":"qinggang", "suit":"spade", "rank":6, "zone":"equipment", "owner_id":0}
	# 测试防御坐骑；不属于当前候选，用于确认非候选装备保持原位且防具与进攻坐骑空槽不会被压缩。
	var defensive_mount_data: Dictionary = {"uid":7005, "definition_id":"jueying", "suit":"spade", "rank":5, "zone":"equipment", "owner_id":0}
	# 不含宝物的本地装备字典；布局仍应常态显示五个固定槽位。
	var equipment_without_treasure: Dictionary = {"weapon":weapon_data, "defensive_mount":defensive_mount_data}
	match_controller.state_changed.emit(_make_snapshot([slash_data, dodge_data], 13, equipment_without_treasure))
	await get_tree().process_frame
	# 本地装备单选请求；候选完全位于选择者自己的装备区，因此必须直接复用牌桌操作区。
	var equipment_request: Dictionary = {
		"request_id":13,
		"chooser_id":0,
		"title":"选择装备",
		"prompt":"请选择一张装备牌",
		"candidates":[_candidate(weapon_data)],
		"min_select":1,
		"max_select":1,
		"allow_cancel":false,
		"context":{"kind":"equipment_cost"},
	}
	main_instance.call("_on_card_choice_requested", equipment_request)
	await get_tree().process_frame
	# 本地装备堆叠组件；装备选择必须直接发生在该组件中，不能创建第二份卡牌窗口。
	var equipment_stack: EquipmentStackView = main_instance.get_node("%EquipmentStack") as EquipmentStackView
	# 可选武器横条；应向右移动配置距离并允许点击。
	var weapon_row: Button = equipment_stack.get_row("weapon")
	# 可用状态动画中的横坐标；首帧应仍处于0至目标值之间，证明横条没有瞬移。
	var animated_candidate_shift: float = weapon_row.position.x
	# 空防具横条；参考图要求空槽保留深色背景和类型图标，而不是完全留白或显示“无”。
	var empty_armor_row: Button = equipment_stack.get_row("armor")
	# 空进攻坐骑横条；与防具空槽使用相同固定高度和3像素间距。
	var empty_offensive_mount_row: Button = equipment_stack.get_row("offensive_mount")
	# 非候选防御坐骑横条；应保持基础横坐标并位于第四个固定槽位。
	var defensive_mount_row: Button = equipment_stack.get_row("defensive_mount")
	# 装备与空槽样式；已装备牌面必须明显亮于深色空槽背景。
	var weapon_style: StyleBoxFlat = weapon_row.get_theme_stylebox("disabled") as StyleBoxFlat
	# 空防具槽样式；用于和浅色装备牌面比较背景亮度。
	var empty_armor_style: StyleBoxFlat = empty_armor_row.get_theme_stylebox("disabled") as StyleBoxFlat
	# 常驻五槽自适应高度；148像素牌面高度按五槽均分，每槽29.6像素且不保留间距。
	var adaptive_equipment_row_height: float = equipment_stack.size.y / 5.0
	# 当前五槽节距；无覆盖且无间距时严格等于自适应槽高。
	var equipment_row_pitch: float = adaptive_equipment_row_height - equipment_stack.equipment_row_overlap + equipment_stack.equipment_row_gap
	# 常驻空宝物槽；未装备时也必须显示深色占位且禁用输入。
	var empty_treasure_row: Button = equipment_stack.get_row("treasure")
	if not is_equal_approx(equipment_stack.shift_animation_seconds, 0.25) or animated_candidate_shift < 0.0 or animated_candidate_shift >= equipment_stack.selectable_shift_distance:
		_fail("equipment_candidate_animation_start:%s" % animated_candidate_shift)
		return
	await _wait_for_equipment_animation(equipment_stack)
	if selection_panel.visible or weapon_row == null or empty_armor_row == null or empty_offensive_mount_row == null or defensive_mount_row == null or empty_treasure_row == null or not is_equal_approx(equipment_stack.size.x, 150.0) or not is_equal_approx(equipment_stack.size.y, 148.0) or not is_equal_approx(weapon_row.size.y, adaptive_equipment_row_height) or not is_equal_approx(weapon_row.position.x, equipment_stack.selectable_shift_distance) or not is_zero_approx(defensive_mount_row.position.x) or not is_equal_approx(empty_armor_row.position.y - weapon_row.position.y, equipment_row_pitch) or not is_equal_approx(empty_offensive_mount_row.position.y - empty_armor_row.position.y, equipment_row_pitch) or not is_equal_approx(defensive_mount_row.position.y - weapon_row.position.y, equipment_row_pitch * 3.0) or not is_equal_approx(empty_treasure_row.position.y - weapon_row.position.y, equipment_row_pitch * 4.0) or equipment_stack.is_slot_equipped("armor") or equipment_stack.is_slot_equipped("treasure") or not equipment_stack.is_slot_equipped("weapon") or weapon_style.bg_color.get_luminance() - empty_armor_style.bg_color.get_luminance() < 0.35 or not empty_armor_row.disabled or empty_armor_row.mouse_filter != Control.MOUSE_FILTER_IGNORE or not empty_treasure_row.disabled or int(equipment_stack.get("_visible_slot_count")) != 5:
		_fail("equipment_inline_layout")
		return
	main_instance.call("_on_equipment_pressed", 7004)
	if confirm_button.disabled or not (main_instance.get("_inline_selected_card_uids") as Array).has(7004):
		_fail("equipment_inline_selection")
		return
	# 已选武器横条；选中状态在可用位置基础上继续向右移动第二段距离。
	var selected_weapon_row: Button = equipment_stack.get_row("weapon")
	await _wait_for_equipment_animation(equipment_stack)
	if not is_equal_approx(selected_weapon_row.position.x, equipment_stack.selectable_shift_distance + equipment_stack.selected_shift_distance):
		_fail("equipment_selected_shift:%s" % selected_weapon_row.position.x)
		return
	# 空候选请求；用于验证已选装备会以相同0.25秒动画复原到基础位置。
	var clear_equipment_request: Dictionary = {"request_id":130, "chooser_id":0, "title":"清理选择", "prompt":"无候选", "candidates":[], "min_select":0, "max_select":0, "allow_cancel":true, "context":{"kind":"test_clear"}}
	main_instance.call("_on_card_choice_requested", clear_equipment_request)
	await _wait_for_equipment_animation(equipment_stack)
	if not is_zero_approx((equipment_stack.get_row("weapon") as Button).position.x):
		_fail("equipment_restore_shift")
		return
	# 装备触发请求；上下文绑定公开装备 UID 后应自动选中，玩家只需确定发动或取消放弃。
	var equipment_trigger_request: Dictionary = {"request_id":131, "chooser_id":0, "title":"青釭剑", "prompt":"是否发动装备？", "candidates":[_candidate(weapon_data)], "min_select":0, "max_select":1, "allow_cancel":true, "context":{"kind":"equipment_trigger", "equipment_uid":7004}}
	main_instance.call("_on_card_choice_requested", equipment_trigger_request)
	if not (main_instance.get("_inline_selected_card_uids") as Array).has(7004) or confirm_button.disabled:
		_fail("equipment_trigger_auto_select")
		return
	await _wait_for_equipment_animation(equipment_stack)
	if not is_equal_approx((equipment_stack.get_row("weapon") as Button).position.x, equipment_stack.selectable_shift_distance + equipment_stack.selected_shift_distance):
		_fail("equipment_trigger_selected_shift")
		return
	# 测试宝物装备；宝物出现后应在常驻第五槽原位覆盖牌面，不改变其他槽位纵向间距。
	var treasure_data: Dictionary = {"uid":7006, "definition_id":"muniu", "suit":"diamond", "rank":5, "zone":"equipment", "owner_id":0}
	# 含宝物的本地装备字典；保留已有武器和防御坐骑，用于比较五槽布局位置变化。
	var equipment_with_treasure: Dictionary = equipment_without_treasure.duplicate(true)
	equipment_with_treasure["treasure"] = treasure_data
	# 加入宝物前当前有效的防御坐骑横条；装备组件会在状态切换时重建节点，因此不能复用更早的旧引用。
	var defensive_mount_row_before_treasure: Button = equipment_stack.get_row("defensive_mount")
	# 常驻五槽布局中的防御坐骑纵坐标；宝物出现后该坐标必须保持不变。
	var defensive_mount_y_without_treasure: float = defensive_mount_row_before_treasure.position.y
	match_controller.state_changed.emit(_make_snapshot([slash_data, dodge_data], 14, equipment_with_treasure))
	await get_tree().process_frame
	# 五槽布局中的宝物横条；实际装备后由深色空槽变为浅色牌面。
	var treasure_row: Button = equipment_stack.get_row("treasure")
	# 五槽布局中的防御坐骑横条；宝物牌面变化不能影响固定第四槽位置。
	var defensive_mount_row_with_treasure: Button = equipment_stack.get_row("defensive_mount")
	if treasure_row == null or int(equipment_stack.get("_visible_slot_count")) != 5 or not is_equal_approx(defensive_mount_row_with_treasure.position.y, defensive_mount_y_without_treasure) or treasure_row.position.y <= defensive_mount_row_with_treasure.position.y or not equipment_stack.is_slot_equipped("treasure"):
		_fail("equipment_treasure_layout")
		return
	# 公共展示牌请求；候选不属于本人手牌，必须继续使用独立 CardSelectionPanel。
	var harvest_card_data: Dictionary = {"uid":7003, "definition_id":"tao", "suit":"heart", "rank":3, "zone":"processing", "owner_id":-1}
	# 已被本地武将领取的原展示牌；公共窗口必须把该牌保留为虚影并在底部显示“杰帕德”。
	var taken_harvest_card_data: Dictionary = {"uid":7010, "definition_id":"shan", "suit":"diamond", "rank":8, "zone":"processing", "owner_id":-1}
	# 五谷公共展示；在具体选择请求到达前就应让所有观察者看到固定牌位。
	var harvest_public_display: Dictionary = {
		"kind":"harvest",
		"title":"五谷丰登",
		"prompt":"每名角色依次选择一张展示牌",
		"active_player_id":0,
		"slots":[
			{"uid":7003, "card_data":harvest_card_data, "taken_by_player_id":-1},
			{"uid":7010, "card_data":taken_harvest_card_data, "taken_by_player_id":0},
		],
	}
	main_instance.call("_on_public_card_choice_display_changed", harvest_public_display)
	await get_tree().process_frame
	# 紧凑选择框与浅背景滤镜；场景覆盖值必须小于组件通用默认规格。
	var selection_frame: PanelContainer = selection_panel.get("_frame") as PanelContainer
	# 全屏选择遮罩；透明度必须使用当前 UI 风格注册的统一 shade 颜色。
	var selection_shade: ColorRect = selection_panel.get("_shade") as ColorRect
	# 当前风格遮罩透明度；测试不再硬编码已经废弃的0.42旧主题值。
	var expected_selection_shade_alpha: float = BattleUIStyle.get_color("shade").a
	# 公共窗口底部操作行；旁观快照尚无本地请求时必须隐藏。
	var public_action_row: HBoxContainer = selection_panel.get("_action_row") as HBoxContainer
	# 公共牌位视图映射；领取牌仍以原 UID 留在固定位置。
	var public_card_views: Dictionary = selection_panel.get("_card_views") as Dictionary
	# 已领取展示牌视图；输入应禁用且整体透明度低于未领取牌。
	var taken_card_view: CardView = public_card_views.get(7010) as CardView
	# 领取者标签；固定作为牌位包装器中正式牌面之后的第二个子节点。
	var taken_owner_label: Label = taken_card_view.get_parent().get_child(1) as Label
	# 公共牌阵；固定使用4列网格且不创建“展示区”标题标签。
	var public_card_grid: GridContainer = (selection_panel.get("_zone_container") as VBoxContainer).get_child(0) as GridContainer
	# 公共窗口实际中心；动态尺寸必须围绕主场景中心展开，不能使用左上角局部坐标跑出屏幕。
	var expected_public_frame_position: Vector2 = (main_instance.size - selection_frame.size) * 0.5
	if not selection_panel.visible or not selection_frame.size.is_equal_approx(Vector2(360.0, 290.0)) or not selection_frame.position.is_equal_approx(expected_public_frame_position) or not is_equal_approx(selection_shade.color.a, expected_selection_shade_alpha) or public_action_row.visible or public_card_views.size() != 2 or taken_card_view.is_interactable or taken_owner_label.text != "杰帕德" or taken_card_view.modulate.a >= 0.5 or public_card_grid == null or public_card_grid.columns != 4:
		_fail("harvest_public_display visible=%s frame=%s shade=%s actions=%s cards=%d interact=%s owner=%s alpha=%s" % [selection_panel.visible, selection_frame.size, selection_shade.color.a, public_action_row.visible, public_card_views.size(), taken_card_view.is_interactable, taken_owner_label.text, taken_card_view.modulate.a])
		return
	# 五谷展示期间的无懈请求；公共数据继续保留，但本地窗口必须暂时关闭以让出手牌与确认按钮输入。
	var harvest_negation_request: Dictionary = {
		"request_id":14,
		"chooser_id":0,
		"title":"响应询问",
		"prompt":"是否使用【无懈可击】？",
		"candidates":[_candidate(dodge_data)],
		"min_select":0,
		"max_select":1,
		"allow_cancel":true,
		"context":{"kind":"trick_negation", "trick_id":"wugu", "parent_card_uid":9901},
	}
	main_instance.call("_on_card_choice_requested", harvest_negation_request)
	await get_tree().process_frame
	if selection_panel.visible or int((main_instance.get("_inline_card_choice") as Dictionary).get("request_id", -1)) != 14 or (main_instance.get("_public_card_choice_display") as Dictionary).is_empty():
		_fail("harvest_negation_interaction_conflict")
		return
	# 五谷请求；用于验证展示区没有被内联分类误吞。
	var harvest_request: Dictionary = {
		"request_id":15,
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
	# 当前本地可选展示牌；固定牌位刷新后只有未领取的7003开放输入，虚影7010继续保留。
	var interactive_public_card_views: Dictionary = selection_panel.get("_card_views") as Dictionary
	if not selection_panel.visible or not (main_instance.get("_inline_card_choice") as Dictionary).is_empty() or not public_action_row.visible or not (interactive_public_card_views.get(7003) as CardView).is_interactable or (interactive_public_card_views.get(7010) as CardView).is_interactable:
		_fail("harvest_modal_state")
		return
	# 本地普通出牌快照；权威 chooseToUse 只列出【杀】，响应专用【闪】即使轮到本人也必须保持禁用灰显。
	var play_snapshot: Dictionary = _make_snapshot([slash_data, dodge_data], 16)
	play_snapshot["current_player_id"] = 0
	play_snapshot["current_phase"] = "play"
	play_snapshot["current_choice_request"] = {"request_id":16, "event_id":16, "actor_id":0, "choice_type":"use", "card_ids":[7001]}
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
	# 丈八蛇矛装备快照；响应【杀】时装备本身作为点击入口，两张普通手牌随后成为材料候选。
	var zhangba_data: Dictionary = {"uid":7007, "definition_id":"zhangba", "suit":"spade", "rank":12, "zone":"equipment", "owner_id":0}
	# 丈八装备字典；只保留测试武器，避免其他装备候选干扰右移断言。
	var zhangba_equipment: Dictionary = {"weapon":zhangba_data}
	match_controller.state_changed.emit(_make_snapshot([slash_data, dodge_data], 17, zhangba_equipment))
	await get_tree().process_frame
	# 【杀】响应请求；丈八是唯一请求候选，但确认前必须先点击装备并再选择两张手牌材料。
	var zhangba_request: Dictionary = {
		"request_id":17,
		"chooser_id":0,
		"title":"响应询问",
		"prompt":"请打出一张【杀】",
		"candidates":[_candidate(zhangba_data)],
		"min_select":0,
		"max_select":1,
		"allow_cancel":true,
		"context":{"kind":"aoe_response", "response_patterns":["sha"]},
	}
	main_instance.call("_on_card_choice_requested", zhangba_request)
	await _wait_for_equipment_animation(equipment_stack)
	# 丈八武器横条；进入响应时先右移提示可点击，点击后保持选中并把普通手牌切换为材料候选。
	var zhangba_row: Button = equipment_stack.get_row("weapon")
	if zhangba_row == null or not is_equal_approx(zhangba_row.position.x, equipment_stack.selectable_shift_distance) or not confirm_button.disabled:
		_fail("zhangba_response_entry")
		return
	main_instance.call("_on_equipment_pressed", 7007)
	# 丈八材料视图；普通【杀】和【闪】都应可选，牌名不会限制两张手牌材料。
	var zhangba_card_views: Dictionary = main_instance.get("_card_views") as Dictionary
	if str(main_instance.get("_active_equipment_action")) != "equipment_response" or not (zhangba_card_views.get(7001) as CardView).is_interactable or not (zhangba_card_views.get(7002) as CardView).is_interactable:
		_fail("zhangba_material_mode")
		return
	main_instance.call("_on_card_pressed", 7001)
	if not confirm_button.disabled:
		_fail("zhangba_one_material_confirm")
		return
	main_instance.call("_on_card_pressed", 7002)
	if confirm_button.disabled or (main_instance.get("_equipment_action_material_uids") as Array) != [7001, 7002]:
		_fail("zhangba_two_material_confirm")
		return
	# 木牛流马出牌快照；chooseToUse 直接把宝物实体列为候选，不再显示“存木牛”专用按钮。
	var wooden_ox_play_snapshot: Dictionary = _make_snapshot([slash_data, dodge_data], 18, {"treasure":treasure_data})
	wooden_ox_play_snapshot["current_player_id"] = 0
	wooden_ox_play_snapshot["current_phase"] = "play"
	wooden_ox_play_snapshot["current_choice_request"] = {"request_id":18, "event_id":18, "actor_id":0, "choice_type":"use", "card_ids":[7006]}
	match_controller.state_changed.emit(wooden_ox_play_snapshot)
	await _wait_for_equipment_animation(equipment_stack)
	# 木牛宝物横条；候选应右移并允许点击，界面不再创建任何具体装备专用按钮。
	var wooden_ox_row: Button = equipment_stack.get_row("treasure")
	if wooden_ox_row == null or not is_equal_approx(wooden_ox_row.position.x, equipment_stack.selectable_shift_distance):
		_fail("wooden_ox_equipment_entry")
		return
	main_instance.call("_on_equipment_pressed", 7006)
	main_instance.call("_on_card_pressed", 7001)
	if str(main_instance.get("_active_equipment_action")) != "store_attachment" or (main_instance.get("_equipment_action_material_uids") as Array) != [7001] or confirm_button.disabled:
		_fail("wooden_ox_material_mode")
		return
	# 铁索连环普通手牌；未选择目标时中央确定按钮应直接表示重铸，旧重铸按钮保持隐藏。
	var chain_data: Dictionary = {"uid":7008, "definition_id":"tiesuo", "suit":"club", "rank":12, "zone":"hand", "owner_id":0}
	# 木牛流马粮牌；即使晚于普通手牌写入快照，也必须固定显示在手牌容器最左侧。
	var stored_card_data: Dictionary = {"uid":7009, "definition_id":"shan", "suit":"diamond", "rank":8, "zone":"wooden_ox", "owner_id":0}
	var chain_play_snapshot: Dictionary = _make_snapshot([chain_data], 19, {}, [stored_card_data])
	chain_play_snapshot["current_player_id"] = 0
	chain_play_snapshot["current_phase"] = "play"
	chain_play_snapshot["current_choice_request"] = {"request_id":19, "event_id":19, "actor_id":0, "choice_type":"use", "card_ids":[7008]}
	match_controller.state_changed.emit(chain_play_snapshot)
	await get_tree().process_frame
	# 手最左侧正式牌面；容器子节点顺序就是最终横向布局顺序。
	var leftmost_card_view: CardView = main_instance.get_node("%HandContainer").get_child(0) as CardView
	# 玩家快照中的普通手牌数；木牛粮虽然共同显示，但公开手牌计数仍只包含普通手牌。
	var rendered_local_player: Dictionary = ((main_instance.get("_snapshot") as Dictionary).get("players", []) as Array)[0] as Dictionary
	if leftmost_card_view == null or leftmost_card_view.card_uid != 7009 or int(rendered_local_player.get("hand_count", -1)) != 1:
		_fail("wooden_ox_leftmost_order")
		return
	main_instance.call("_on_card_pressed", 7008)
	var recast_button: Button = main_instance.get_node("%RecastButton") as Button
	var interaction_guide: Label = main_instance.get_node("%InteractionGuideLabel") as Label
	if confirm_button.disabled or recast_button.visible or not interaction_guide.text.contains("重铸"):
		_fail("chain_confirm_recast")
		return
	# 选将组件快照；领袖已亮将后左侧必须显示正式武将牌，进度长文本保持隐藏。
	var character_selection_panel: CharacterSelectionPanel = main_instance.get_node("%CharacterSelectionPanel") as CharacterSelectionPanel
	character_selection_panel.bind_snapshot({
		"phase":CharacterSelectionService.PHASE_OTHERS,
		"leader_player_id":1,
		"leader_character_id":"bronya",
		"local_player_id":0,
		"local_candidates":["gepard", "dan_heng", "march_7th", "himeko", "natasha"],
		"can_select":true,
		"readiness":[],
	})
	await get_tree().process_frame
	# 选将框左侧领袖牌承载区；已亮将快照必须创建恰好一张正式武将牌。
	var leader_character_area: Control = main_instance.get_node("%LeaderCharacterArea") as Control
	# 已废弃进度文本标签；节点保留兼容但必须隐藏并清空文本。
	var character_status_label: Label = main_instance.get_node("%CharacterSelectionStatus") as Label
	# 右侧候选承载区；横坐标应为给左侧领袖牌预留后的214像素。
	var character_candidate_area: Control = main_instance.get_node("%CharacterCandidateArea") as Control
	if not character_selection_panel.visible or not leader_character_area.visible or leader_character_area.get_child_count() != 1 or character_status_label.visible or not character_status_label.text.is_empty() or not is_equal_approx(character_candidate_area.position.x, 214.0):
		_fail("character_selection_leader_card")
		return
	remove_child(main_instance)
	main_instance.free()
	await get_tree().process_frame
	print("INLINE_HAND_CHOICE_PASS")
	get_tree().quit(0)


## 把卡牌快照包装成统一选择候选；可见性与所有者字段和正式控制器输出一致。
func _candidate(card_data: Dictionary) -> Dictionary:
	# 当前候选槽位；装备牌从静态定义读取槽位，其他区域保持空字符串。
	var slot: String = str(GameDatabase.get_card(str(card_data.get("definition_id", ""))).get("slot", "")) if str(card_data.get("zone", "")) == "equipment" else ""
	return {
		"uid":int(card_data.get("uid", -1)),
		"owner_id":int(card_data.get("owner_id", -1)),
		"zone":str(card_data.get("zone", "")),
		"slot":slot,
		"visible":true,
		"card_data":card_data.duplicate(true),
	}


## 构造本地观察者快照；只包含内联选择需要的手牌、阶段和运行时请求标识。
func _make_snapshot(hand_cards: Array, request_id: int, equipment: Dictionary = {}, wooden_ox_cards: Array = []) -> Dictionary:
	# 本地玩家快照；完整手牌仅对0号观察者公开。
	var local_player: Dictionary = {
		"player_id":0,
		"seat_number":1,
		"display_name":"本地玩家",
		"character_id":"gepard",
		"identity":"leader",
		"hp":4,
		"max_hp":4,
		"alive":true,
		"chained":false,
		"hand_count":hand_cards.size(),
		"hand":hand_cards.duplicate(true),
		"equipment":equipment.duplicate(true),
		"judgment_area":[],
		"wooden_ox_storage":wooden_ox_cards.duplicate(true),
		"wooden_ox_storage_count":wooden_ox_cards.size(),
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


## 等待装备横条完成检查器配置的横向补间，并增加0.05秒调度余量保证无头测试稳定。
func _wait_for_equipment_animation(equipment_stack: EquipmentStackView) -> void:
	await get_tree().create_timer(equipment_stack.shift_animation_seconds + 0.05).timeout


## 输出稳定失败原因并以非0状态退出，便于命令行定位具体内联交互断言。
func _fail(reason: String) -> void:
	printerr("INLINE_HAND_CHOICE_FAIL %s" % reason)
	get_tree().quit(1)
