class_name OpportunityChoicePanel
extends Control

## 全体机缘选择弹窗。组件只渲染观察者自己的三张私有候选或等待状态，并提交稳定机缘卡ID。

## 本地玩家点击机缘卡时发出稳定ID；牌桌负责转换为统一PlayerAction并交由权威端校验。
signal opportunity_selected(card_id: String)

## 当前机缘牌包含获得技能时转发统一悬停资料；牌桌唯一InformationBoxLayer负责实际显示。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 当前机缘牌离开或禁用时转发说明撤销请求。
signal information_dismissed

## 正式机缘卡场景；三张候选均复用同一无插画牌面组件。
const OPPORTUNITY_CARD_SCENE: PackedScene = preload("res://scenes/components/opportunity_card.tscn")

## 机缘弹窗绘制层级；高于通用选牌层150，低于主菜单400与局内菜单500。
const MODAL_Z_INDEX: int = 180

## 全屏遮罩；阻止选择期间误触牌桌其他交互。
@onready var _shade: ColorRect = %Shade

## 弹窗主框；使用固定最大宽度承载三张武将牌比例机缘卡。
@onready var _frame: PanelContainer = %Frame

## 当前状态提示；本地未轮到时显示等待角色，轮到时提示从三张中选择一张。
@onready var _status_label: Label = %StatusLabel

## 机缘卡横排容器；每次轮到新的本地选择请求时整体重建。
@onready var _cards_row: HBoxContainer = %CardsRow

## 最近一次渲染签名；重复状态快照不重建牌面，避免按钮按下期间节点被释放。
var _render_signature: String = ""


## 初始化暂停可用的模态层；规则核心暂停SceneTree时仍允许玩家点击机缘卡。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = MODAL_Z_INDEX
	visible = false
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	# 弹窗样式；暖黑底与金属边框延续武将牌和现有选择框视觉语言。
	var frame_style: StyleBoxFlat = StyleBoxFlat.new()
	frame_style.bg_color = Color("171310f2")
	frame_style.border_color = Color("c9a65d")
	frame_style.set_border_width_all(3)
	frame_style.set_corner_radius_all(10)
	frame_style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	frame_style.shadow_size = 14
	frame_style.shadow_offset = Vector2(0.0, 6.0)
	_frame.add_theme_stylebox_override("panel", frame_style)


## 根据观察者裁剪快照刷新弹窗；非选择阶段立即关闭并清理旧牌面。
func show_opportunity(opportunity_snapshot: Dictionary, local_player_id: int, player_names: Dictionary) -> void:
	if opportunity_snapshot.is_empty() or not bool(opportunity_snapshot.get("active", false)) or str(opportunity_snapshot.get("stage", "")) != "choosing":
		close()
		return
	visible = true
	move_to_front()
	# 当前权威选择者；只有该ID等于本地玩家时才显示可点击候选。
	var current_chooser_id: int = int(opportunity_snapshot.get("current_chooser_id", -1))
	# 本地私有候选映射；GameState已经移除其他角色的候选正文。
	var options_by_player: Dictionary = opportunity_snapshot.get("options_by_player", {}) as Dictionary
	# 本地候选数组；字符串键兼容局域网序列化后的字典。
	var local_options: Array = options_by_player.get(str(local_player_id), options_by_player.get(local_player_id, [])) as Array
	# 已完成选择角色；用于让本地玩家确认自己的选择已经提交并进入等待。
	var chosen_player_ids: Array = opportunity_snapshot.get("chosen_player_ids", []) as Array
	# 渲染签名；请求角色、完成进度与本地候选ID共同决定是否需要重建。
	var option_ids: Array[String] = []
	for option_variant: Variant in local_options:
		option_ids.append(str((option_variant as Dictionary).get("id", "")))
	var signature: String = "%d|%s|%s" % [current_chooser_id, str(chosen_player_ids), ",".join(option_ids)]
	if signature == _render_signature:
		return
	_render_signature = signature
	_clear_cards()
	if current_chooser_id == local_player_id and not local_options.is_empty() and not chosen_player_ids.has(local_player_id):
		_status_label.text = "选择机缘时间：请选择一张机缘卡"
		for option_variant: Variant in local_options:
			# 当前机缘卡视图；只接收本地私有定义并发出稳定ID。
			var card_view: OpportunityCardView = OPPORTUNITY_CARD_SCENE.instantiate() as OpportunityCardView
			_cards_row.add_child(card_view)
			card_view.configure(option_variant as Dictionary, true)
			card_view.card_selected.connect(_on_card_selected)
			card_view.information_requested.connect(_on_card_information_requested)
			card_view.information_dismissed.connect(_on_card_information_dismissed)
		return
	# 当前等待角色名；缺失时回退“其他角色”，不暴露身份或私有候选。
	var chooser_name: String = str(player_names.get(current_chooser_id, "其他角色"))
	_status_label.text = "等待%s选择机缘……" % chooser_name


## 关闭弹窗并释放动态牌面；下一次机缘使用新签名完整重建。
func close() -> void:
	visible = false
	_render_signature = ""
	_clear_cards()


## 清空当前三张动态机缘卡；节点先移出容器再排队释放，避免参与后续布局。
func _clear_cards() -> void:
	for child: Node in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()


## 转发玩家选择并立即禁用全部牌面；权威快照返回前防止快速连点重复提交。
func _on_card_selected(card_id: String) -> void:
	for child: Node in _cards_row.get_children():
		# 当前机缘牌面；直接禁用内部透明按钮，确保权威快照返回前不能快速重复提交。
		var card_view: OpportunityCardView = child as OpportunityCardView
		if card_view != null:
			card_view.set_interactive(false)
	opportunity_selected.emit(card_id)


## 转发单张机缘卡的技能资料请求；弹窗不保存信息内容或创建第二套悬停组件。
func _on_card_information_requested(information: Dictionary, anchor_rect: Rect2) -> void:
	information_requested.emit(information, anchor_rect)


## 转发单张机缘卡的资料撤销；牌桌用弹窗实例ID维护统一来源所有权。
func _on_card_information_dismissed() -> void:
	information_dismissed.emit()
