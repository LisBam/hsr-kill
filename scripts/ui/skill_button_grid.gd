class_name SkillButtonGrid
extends Container

## 本地武将技能按钮网格。组件只负责从右到左、从下到上的固定排版，不读取技能规则或玩家状态。

## 每行最多容纳的技能按钮数量；默认2对应牌桌底部的双列布局，运行时通常无需动态修改。
@export_range(1, 4, 1) var maximum_columns: int = 2

## 相邻技能按钮的水平间距；默认6像素用于区分同层的两个技能，运行时可按主题调整。
@export_range(0.0, 24.0, 1.0) var horizontal_gap: float = 6.0

## 相邻技能按钮层的垂直间距；默认6像素保证第二层不会与第一层按钮边框重叠，运行时可按主题调整。
@export_range(0.0, 24.0, 1.0) var vertical_gap: float = 6.0


## 子节点数量或最小尺寸变化时重新排列；只处理 Control 类型技能按钮。
func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout_skill_buttons()


## 返回当前技能数量所需的紧凑尺寸；一项只占一列，两项及以上最多占两列并向上增加层数。
func _get_minimum_size() -> Vector2:
	# 当前参与布局的技能按钮；隐藏节点不占用列数或层数。
	var buttons: Array[Control] = _get_visible_buttons()
	if buttons.is_empty():
		return Vector2.ZERO
	# 当前按钮统一尺寸；技能按钮组件使用固定最小尺寸，取全部最大值可兼容未来主题扩展。
	var button_size: Vector2 = Vector2.ZERO
	for button: Control in buttons:
		button_size = button_size.max(button.get_combined_minimum_size())
	# 当前实际列数；只有一个技能时不保留第二列空位。
	var column_count: int = mini(buttons.size(), maxi(maximum_columns, 1))
	# 当前实际层数；超过单层上限后继续向上增加新层。
	var row_count: int = ceili(float(buttons.size()) / float(maxi(maximum_columns, 1)))
	return Vector2(
		button_size.x * float(column_count) + horizontal_gap * float(maxi(column_count - 1, 0)),
		button_size.y * float(row_count) + vertical_gap * float(maxi(row_count - 1, 0))
	)


## 按技能定义顺序把第一项放在右下角，第二项放在其左侧，第三项从右侧第二层继续排列。
func _layout_skill_buttons() -> void:
	# 当前参与布局的技能按钮；顺序与武将定义中的 skills 数组完全一致。
	var buttons: Array[Control] = _get_visible_buttons()
	if buttons.is_empty():
		return
	# 当前按钮统一尺寸；使用最大最小尺寸保证同行按钮边界整齐。
	var button_size: Vector2 = Vector2.ZERO
	for button: Control in buttons:
		button_size = button_size.max(button.get_combined_minimum_size())
	# 当前每行列数；固定不超过 maximum_columns，索引0始终位于最右列。
	var column_limit: int = maxi(maximum_columns, 1)
	for button_index: int in range(buttons.size()):
		# 当前技能所在列；0表示右侧第一列，1表示其左侧第二列。
		var column_index: int = button_index % column_limit
		# 当前技能所在层；0表示最下层，后续数值依次向上。
		var row_index: int = floori(float(button_index) / float(column_limit))
		# 当前按钮右下向左上的目标矩形；容器右边和底边始终贴齐最先配置的技能按钮。
		var target_position: Vector2 = Vector2(
			size.x - button_size.x - float(column_index) * (button_size.x + horizontal_gap),
			size.y - button_size.y - float(row_index) * (button_size.y + vertical_gap)
		)
		fit_child_in_rect(buttons[button_index], Rect2(target_position, button_size))


## 收集当前可见的 Control 子节点；非控件辅助节点和隐藏节点不会参与技能顺序。
func _get_visible_buttons() -> Array[Control]:
	# 可见技能按钮数组；保持场景树顺序以对应武将技能定义顺序。
	var result: Array[Control] = []
	for child: Node in get_children():
		if child is Control and (child as Control).visible:
			result.append(child as Control)
	return result
