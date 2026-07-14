class_name DecadeBattleLayout
extends Control

## 无名杀十周年式环桌座次布局组件。组件只根据人数和可视尺寸摆放角色卡，不读取规则对象或提交动作。

## 常规对手武将牌尺寸；默认118×172像素对应参考扩展 nova 布局，运行时通常无需动态修改。
@export var opponent_card_size: Vector2 = Vector2(118.0, 172.0)

## 六张以上顶部武将牌使用的紧凑尺寸；默认104×156像素避免九至十人局发生遮挡，运行时通常无需动态修改。
@export var compact_opponent_card_size: Vector2 = Vector2(104.0, 156.0)

## 顶部武将牌距牌桌上边缘的距离；默认14像素接近参考 CSS 的9像素视觉留白，运行时可在检查器中调整。
@export_range(0.0, 100.0, 1.0) var top_margin: float = 14.0

## 左右侧武将牌距牌桌边缘的距离；默认22像素对应参考布局的边缘安全区，运行时可在检查器中调整。
@export_range(0.0, 100.0, 1.0) var side_margin: float = 22.0

## 单侧只有一名角色时的纵向位置比例；默认0.20使其位于牌桌上半区，运行时通常无需动态修改。
@export_range(0.1, 0.6, 0.01) var single_side_y_ratio: float = 0.20

## 单侧有两名角色时第一名的纵向位置比例；默认0.18用于十人局上侧座位，运行时通常无需动态修改。
@export_range(0.1, 0.5, 0.01) var upper_side_y_ratio: float = 0.18

## 单侧有两名角色时第二名的纵向位置比例；默认0.47用于十人局下侧座位，运行时通常无需动态修改。
@export_range(0.25, 0.7, 0.01) var lower_side_y_ratio: float = 0.47

## 当前由桌面绑定的对手角色卡数组；数组顺序与本地玩家之后的存活座次顺序一致。
var _opponent_views: Array[Control] = []

## 当前对局总人数；支持2至10人，用于选择与无名杀相同的座次模板。
var _total_player_count: int = 0


## 启用尺寸变化监听；窗口拉伸后会基于当前可视区域重新计算全部座位。
func _ready() -> void:
	# 座次容器覆盖整个牌桌但自身不承载点击；忽略鼠标可让右上角按钮和其他同级控件直接参与命中测试，子角色牌仍保持独立交互。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_opponents)


## 绑定一组新建的角色视图并立即应用座次；组件不持有玩家快照或身份等业务数据。
func bind_opponent_views(opponent_views: Array[Control], total_player_count: int) -> void:
	_opponent_views.clear()
	for opponent_view: Control in opponent_views:
		_opponent_views.append(opponent_view)
	_total_player_count = clampi(total_player_count, 2, 10)
	_layout_opponents()


## 清理已释放的视图引用；桌面整体重建角色卡前调用可避免尺寸变化信号访问旧节点。
func clear_opponent_views() -> void:
	_opponent_views.clear()
	_total_player_count = 0


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
	# 左右侧座位数量；二至三人局全部位于顶部，四至九人局每侧一名，十人局每侧两名。
	var side_count_per_edge: int = 0 if _total_player_count <= 3 else (2 if _total_player_count >= 10 else 1)
	# 顶部座位数量；用于决定卡牌尺寸并生成均匀但符合参考比例的横坐标。
	var top_count: int = maxi(valid_views.size() - side_count_per_edge * 2, 0)
	# 当前座位使用的武将牌尺寸；顶部超过五张时切换紧凑尺寸。
	var active_card_size: Vector2 = compact_opponent_card_size if top_count >= 6 else opponent_card_size
	# 当前视图索引；按右侧、顶部从右到左、左侧的无名杀座次顺序依次消费。
	var view_index: int = 0
	if side_count_per_edge > 0:
		for right_index: int in range(side_count_per_edge):
			_place_view(valid_views[view_index], Vector2(size.x - side_margin - active_card_size.x, _side_y(right_index, side_count_per_edge)), active_card_size)
			view_index += 1
	# 顶部中心横坐标比例；数组按从右向左排列，与无名杀 data-position 递增方向一致。
	var top_ratios: PackedFloat32Array = _top_center_ratios(top_count)
	for top_index: int in range(top_count):
		# 当前顶部座位的中心横坐标；按牌桌实时宽度从比例换算。
		var center_x: float = size.x * float(top_ratios[top_index])
		_place_view(valid_views[view_index], Vector2(center_x - active_card_size.x * 0.5, top_margin), active_card_size)
		view_index += 1
	if side_count_per_edge > 0:
		for left_index: int in range(side_count_per_edge):
			_place_view(valid_views[view_index], Vector2(side_margin, _side_y(side_count_per_edge - left_index - 1, side_count_per_edge)), active_card_size)
			view_index += 1


## 返回侧边座位纵坐标；单座位使用统一上半区位置，双座位分别使用上、下两个比例。
func _side_y(side_index: int, side_count: int) -> float:
	if side_count <= 1:
		return size.y * single_side_y_ratio
	return size.y * (upper_side_y_ratio if side_index == 0 else lower_side_y_ratio)


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


## 把角色卡放入指定矩形并同步组件尺寸参数；布局只改变 Control 几何信息。
func _place_view(opponent_view: Control, target_position: Vector2, target_size: Vector2) -> void:
	if opponent_view.has_method("apply_panel_size"):
		opponent_view.call("apply_panel_size", target_size)
	else:
		opponent_view.custom_minimum_size = target_size
		opponent_view.size = target_size
	opponent_view.position = target_position
