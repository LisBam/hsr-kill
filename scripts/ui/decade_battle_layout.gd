class_name DecadeBattleLayout
extends Control

## 无名杀十周年式环桌座次布局组件。组件只根据人数和可视尺寸摆放角色卡，不读取规则对象或提交动作。

## 顶部武将牌距牌桌上边缘的距离；默认2像素为紧凑窗口中的十人局错列座位保留纵向安全间隔。
## 该参数只改变顶部座位位置，运行时通常无需动态修改，不影响牌面尺寸、座次顺序或规则数值。
@export_range(0.0, 100.0, 1.0) var top_margin: float = 2.0

## 十人局其他玩家座位的统一缩放比例；默认0.90提升十人局角色信息的可读性，同时保持左右双座位紧凑排布。
## 该参数只在10人局生效，运行时通常无需动态修改，不改变武将牌资源、点击区域或规则座次。
@export_range(0.75, 1.0, 0.01) var ten_player_card_scale: float = 0.9

## 左右侧武将牌距牌桌边缘的距离；默认22像素对应参考布局的边缘安全区，运行时可在检查器中调整。
@export_range(0.0, 100.0, 1.0) var side_margin: float = 22.0

## 单侧只有一名角色时的纵向位置比例；默认0.35使增宽后的武将牌避开顶部牌列和底部功能区，运行时通常无需动态修改。
## 3:4武将牌增宽后使用0.35，使四至九人局侧边座位避开顶部牌列并保留底部界面安全区。
@export_range(0.1, 0.6, 0.01) var single_side_y_ratio: float = 0.35

## 十人局下侧完整座位距客户区底边的安全距离；默认201像素令座次号与“记录”按钮保持2像素间距，运行时通常无需动态修改。
## 该参数包含下侧武将牌和座次标签的完整高度，不改变座次顺序、角色牌资源或任何规则数值。
@export_range(120.0, 360.0, 1.0) var ten_player_lower_side_bottom_margin: float = 201.0

## 十人局同侧上下完整座位的纵向间隔；默认6像素使牌面和座次标签紧凑相邻且不重叠，运行时通常无需动态修改。
## 该参数只作用于十人局双座位，不改变四至九人局的单侧座位位置或规则座次。
@export_range(0.0, 80.0, 1.0) var ten_player_stacked_vertical_gap: float = 6.0

## 当前由桌面绑定的对手角色卡数组；数组顺序与本地玩家之后的存活座次顺序一致。
var _opponent_views: Array[Control] = []

## 当前对局总人数；支持2至10人，用于选择与无名杀相同的座次模板。
var _total_player_count: int = 0

## 已实际执行的有效座位布局次数；从0开始，仅供性能诊断与回归测试确认重复绑定是否被跳过，运行时不得手动修改。
var _layout_revision: int = 0


## 启用尺寸变化监听；窗口拉伸后会基于当前可视区域重新计算全部座位。
func _ready() -> void:
	# 座次容器覆盖整个牌桌但自身不承载点击；忽略鼠标可让右上角按钮和其他同级控件直接参与命中测试，子角色牌仍保持独立交互。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_opponents)


## 绑定一组新建的角色视图并立即应用座次；组件不持有玩家快照或身份等业务数据。
func bind_opponent_views(opponent_views: Array[Control], total_player_count: int) -> void:
	# 规范化后的对局总人数；先裁剪再比较，确保异常输入与已绑定值使用同一语义。
	var normalized_player_count: int = clampi(total_player_count, 2, 10)
	# 当前绑定是否与已有节点身份、顺序和人数完全一致；相同快照无需重复写入位置与缩放。
	var binding_unchanged: bool = _total_player_count == normalized_player_count and _opponent_views.size() == opponent_views.size()
	if binding_unchanged:
		# 当前对手视图比较索引；依次核对节点身份与顺序，任一位置不同都会使本次绑定失效并触发重排。
		for view_index: int in range(opponent_views.size()):
			if _opponent_views[view_index] != opponent_views[view_index]:
				binding_unchanged = false
				break
	if binding_unchanged:
		return
	_opponent_views.clear()
	for opponent_view: Control in opponent_views:
		_opponent_views.append(opponent_view)
	_total_player_count = normalized_player_count
	_layout_opponents()


## 清理已释放的视图引用；桌面整体重建角色卡前调用可避免尺寸变化信号访问旧节点。
func clear_opponent_views() -> void:
	_opponent_views.clear()
	_total_player_count = 0


## 返回有效座位布局执行序号；只读诊断值可比较两次操作之间是否发生了真实重排。
func get_layout_revision() -> int:
	return _layout_revision


## 按人数把角色分配到右侧、顶部和左侧，并使用参考扩展的百分比位置。
func _layout_opponents() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or _opponent_views.is_empty():
		return
	# 有效对手视图；快照重建与 queue_free 之间可能短暂存在已释放引用，布局时统一过滤。
	var valid_views: Array[Control] = []
	for opponent_view: Control in _opponent_views:
		if opponent_view != null and is_instance_valid(opponent_view):
			valid_views.append(opponent_view)
	if valid_views.is_empty():
		return
	_layout_revision += 1
	# 左右侧座位数量；二至三人局全部位于顶部，四至九人局每侧一名，十人局每侧两名。
	var side_count_per_edge: int = 0 if _total_player_count <= 3 else (2 if _total_player_count >= 10 else 1)
	# 顶部座位数量；用于生成均匀但符合参考比例的横坐标。
	var top_count: int = maxi(valid_views.size() - side_count_per_edge * 2, 0)
	# 当前座位容器尺寸；十人局统一缩放以同时保留左右两层座位、顶部五牌和中央结算空白。
	var active_card_size: Vector2 = valid_views[0].size * (ten_player_card_scale if _total_player_count >= 10 else 1.0)
	# 十人局统一缩放值；只作用于当前布局器持有的座位容器，其他人数恢复场景原始比例。
	var active_card_scale: float = ten_player_card_scale if _total_player_count >= 10 else 1.0
	for valid_view: Control in valid_views:
		valid_view.scale = Vector2.ONE * active_card_scale
	# 当前视图索引；按右侧、顶部从右到左、左侧的无名杀座次顺序依次消费。
	var view_index: int = 0
	if side_count_per_edge > 0:
		for right_index: int in range(side_count_per_edge):
			# 右侧座位纵向索引；环形顺序先消费下家六号位，再消费七号位，双座位时分别放到下、上位置。
			var right_side_index: int = side_count_per_edge - right_index - 1
			# 右侧座位横坐标；同侧上下座位必须保持同一列，避免视觉上出现左右错位。
			var right_x: float = size.x - side_margin - active_card_size.x
			_place_view(valid_views[view_index], Vector2(right_x, _side_y(right_side_index, side_count_per_edge, active_card_size.y)))
			view_index += 1
	# 顶部中心横坐标比例；数组按从右向左排列，与无名杀 data-position 递增方向一致。
	var top_ratios: PackedFloat32Array = _top_center_ratios(top_count)
	for top_index: int in range(top_count):
		# 当前顶部座位的中心横坐标；按牌桌实时宽度从比例换算。
		var center_x: float = size.x * float(top_ratios[top_index])
		_place_view(valid_views[view_index], Vector2(center_x - active_card_size.x * 0.5, top_margin))
		view_index += 1
	if side_count_per_edge > 0:
		for left_index: int in range(side_count_per_edge):
			# 左侧座位纵向索引；环形顺序已从本地上家向外消费，双座位时三号位在上、四号位在下。
			var left_side_index: int = left_index
			# 左侧座位横坐标；同侧上下座位必须保持同一列，避免视觉上出现左右错位。
			var left_x: float = side_margin
			_place_view(valid_views[view_index], Vector2(left_x, _side_y(left_side_index, side_count_per_edge, active_card_size.y)))
			view_index += 1


## 返回侧边座位纵坐标；单座位使用统一上半区位置，十人局双座位从底部安全距离反推，保证座次号贴近记录入口。
func _side_y(side_index: int, side_count: int, stacked_seat_height: float) -> float:
	if side_count <= 1:
		return size.y * single_side_y_ratio
	# 下侧完整座位的顶部坐标；以客户区底边为基准，窗口高度变化后仍保留与“记录”按钮一致的安全距离。
	var lower_side_y: float = size.y - stacked_seat_height - ten_player_lower_side_bottom_margin
	if side_index == 0:
		# 上侧完整座位的顶部坐标；上侧座位放在下侧座位上方，并只保留配置的紧凑间隔。
		var upper_side_y: float = lower_side_y - stacked_seat_height - ten_player_stacked_vertical_gap
		return upper_side_y
	return lower_side_y


## 返回顶部座位中心比例；二至八人局使用参考 CSS 数值，更多人数使用相同边界内的均匀扩展。
func _top_center_ratios(top_count: int) -> PackedFloat32Array:
	match top_count:
		1:
			return PackedFloat32Array([0.5])
		2:
			return PackedFloat32Array([0.675, 0.325])
		3:
			return PackedFloat32Array([0.72, 0.5, 0.28])
		4:
			return PackedFloat32Array([0.752, 0.584, 0.416, 0.248])
		5:
			return PackedFloat32Array([0.78, 0.64, 0.5, 0.36, 0.22])
	# 六个顶部座位用于九人局；在18%至82%之间均匀排列，延续参考布局的对称中心线。
	var ratios: PackedFloat32Array = PackedFloat32Array()
	for ratio_index: int in range(top_count):
		ratios.append(0.82 - 0.64 * float(ratio_index) / float(maxi(top_count - 1, 1)))
	return ratios


## 把角色座位容器移动到指定位置；尺寸完全由组合场景自身定义。
func _place_view(opponent_view: Control, target_position: Vector2) -> void:
	opponent_view.position = target_position
