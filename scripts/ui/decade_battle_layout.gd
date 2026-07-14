class_name DecadeBattleLayout
extends Control

## 无名杀十周年式环桌座次布局组件。组件只根据人数和可视尺寸摆放角色卡，不读取规则对象或提交动作。

## 武将牌原始设计尺寸；只用于追溯统一1.15倍放大比例，运行时布局使用放大后的固定尺寸。
const BASE_PLAYER_CARD_SIZE: Vector2 = Vector2(118.0, 172.0)

## 全部武将牌相对原始设计的统一放大倍数；该数值只扩大牌框与插画空间，不缩放信息控件。
const PLAYER_CARD_SCALE: float = 1.15

## 全部武将牌统一使用的固定尺寸；135.7×197.8与可编辑 player_target_view.tscn 的根节点尺寸完全一致。
const UNIFIED_PLAYER_CARD_SIZE: Vector2 = BASE_PLAYER_CARD_SIZE * PLAYER_CARD_SCALE

## 游戏内座次标签的固定高度；26像素是18像素字体进入场景树后的真实控件高度，保持放大前的实际UI尺寸。
const PLAYER_SEAT_LABEL_HEIGHT: float = 26.0

## 游戏内完整座位容器尺寸；宽度等于武将牌，223.8像素高度由197.8像素武将牌与26像素座次标签组成。
const PLAYER_SEAT_SLOT_SIZE: Vector2 = Vector2(UNIFIED_PLAYER_CARD_SIZE.x, UNIFIED_PLAYER_CARD_SIZE.y + PLAYER_SEAT_LABEL_HEIGHT)

## 顶部武将牌距牌桌上边缘的距离；默认2像素为紧凑窗口中的十人局错列座位保留纵向安全间隔。
## 该参数只改变顶部座位位置，运行时通常无需动态修改，不影响牌面尺寸、座次顺序或规则数值。
@export_range(0.0, 100.0, 1.0) var top_margin: float = 2.0

## 左右侧武将牌距牌桌边缘的距离；默认22像素对应参考布局的边缘安全区，运行时可在检查器中调整。
@export_range(0.0, 100.0, 1.0) var side_margin: float = 22.0

## 单侧只有一名角色时的纵向位置比例；默认0.20使其位于牌桌上半区，运行时通常无需动态修改。
@export_range(0.1, 0.6, 0.01) var single_side_y_ratio: float = 0.20

## 单侧有两名角色时第一名的纵向位置比例；默认0.18用于十人局上侧座位，运行时通常无需动态修改。
@export_range(0.1, 0.5, 0.01) var upper_side_y_ratio: float = 0.18

## 单侧有两名角色时第二名的纵向位置比例；默认0.35为放大后的下侧座位预留底部界面安全区，运行时通常无需动态修改。
@export_range(0.25, 0.7, 0.01) var lower_side_y_ratio: float = 0.35

## 单侧双座位的横向错列间隔；默认14像素让下侧座位向牌桌内侧移动一张牌宽，避开底部本地界面。
## 该参数只在十人局生效，运行时通常无需动态修改，不改变座次顺序或目标规则。
@export_range(0.0, 80.0, 1.0) var stacked_side_horizontal_gap: float = 14.0

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
	# 顶部座位数量；用于生成均匀但符合参考比例的横坐标。
	var top_count: int = maxi(valid_views.size() - side_count_per_edge * 2, 0)
	# 当前座位容器尺寸；武将牌保持135.7×197.8，独立座次标签始终位于容器底部。
	var active_card_size: Vector2 = PLAYER_SEAT_SLOT_SIZE
	# 当前视图索引；按右侧、顶部从右到左、左侧的无名杀座次顺序依次消费。
	var view_index: int = 0
	if side_count_per_edge > 0:
		for right_index: int in range(side_count_per_edge):
			# 右侧座位横坐标；十人局下侧牌向内错列，避免与右下本地武将牌占用同一列。
			var right_x: float = size.x - side_margin - active_card_size.x - float(right_index) * (active_card_size.x + stacked_side_horizontal_gap)
			_place_view(valid_views[view_index], Vector2(right_x, _side_y(right_index, side_count_per_edge)), active_card_size)
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
			# 左侧座位纵向索引；座次消费顺序与视觉上下方向相反，因此先换算为实际的上、下位置。
			var left_side_index: int = side_count_per_edge - left_index - 1
			# 左侧座位横坐标；十人局下侧牌向内错列，避免与左下装备区占用同一列。
			var left_x: float = side_margin + float(left_side_index) * (active_card_size.x + stacked_side_horizontal_gap)
			_place_view(valid_views[view_index], Vector2(left_x, _side_y(left_side_index, side_count_per_edge)), active_card_size)
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


## 把角色座位容器放入指定矩形并同步组件尺寸参数；布局只改变容器几何信息。
func _place_view(opponent_view: Control, target_position: Vector2, target_size: Vector2) -> void:
	if opponent_view.has_method("apply_panel_size"):
		opponent_view.call("apply_panel_size", target_size)
	else:
		opponent_view.custom_minimum_size = target_size
		opponent_view.size = target_size
	opponent_view.position = target_position
