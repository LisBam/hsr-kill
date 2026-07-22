class_name PlayerMarkersView
extends Control

## 角色公开标记排列组件。其他角色使用纵排，第一视角使用横排，二者复用完全相同的单标记图标与悬停协议。

## 任一子标记请求显示详细信息时向外转发；牌桌或武将牌组件负责绑定唯一信息框。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 任一子标记离开时向外转发关闭请求。
signal information_dismissed

## 相邻标记间距；默认4像素让多个32像素圆形图标保持清晰分隔，运行时通常无需动态修改。
## 当前默认间距调整为2像素，配合24像素圆形图标紧凑贴近武将牌。
@export_range(0.0, 12.0, 1.0) var marker_gap: float = 2.0

## 是否横向排列；false用于其他角色武将牌左侧纵排，true用于第一视角手牌栏上方横排。
var horizontal: bool = false

## 当前公开标记字典副本；键为稳定标记ID，值为图标、数量和详细说明。
var _marks: Dictionary = {}

## 当前已经创建的单标记组件；每次标记集合变化时重建，数量通常很小且不保留旧规则引用。
var _badges: Array[PlayerMarkerBadge] = []

## 当前渲染签名；标记内容和排列方向均未变化时跳过节点重建。
var _configuration_signature: int = -1


## 默认忽略空白区域鼠标，只有实际圆形子标记接收悬停。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_badges()


## 写入公开标记并选择排列方向；标记按order和稳定ID排序，所有客户端得到一致顺序。
func configure(marks: Dictionary, horizontal_layout: bool = false) -> void:
	# 下一份配置签名；深层字典内容参与哈希，数量或说明变化都会刷新悬停信息。
	var next_signature: int = hash([marks, horizontal_layout, marker_gap])
	if _configuration_signature == next_signature:
		return
	_configuration_signature = next_signature
	_marks = marks.duplicate(true)
	horizontal = horizontal_layout
	_refresh_badges()


## 返回当前全部标记实际占用尺寸；第一视角据此为右侧判定区预留不重叠空间。
func get_required_size() -> Vector2:
	if _badges.is_empty():
		return Vector2.ZERO
	# 单标记尺寸；所有子组件使用相同直径，读取首项即可。
	var badge_size: Vector2 = _badges[0].get_badge_size()
	# 排列主轴长度；N个图标拥有N-1段间距。
	var primary_length: float = (badge_size.x if horizontal else badge_size.y) * float(_badges.size()) + marker_gap * float(maxi(_badges.size() - 1, 0))
	return Vector2(primary_length, badge_size.y) if horizontal else Vector2(badge_size.x, primary_length)


## 按当前UI风格刷新所有子图标；标记顺序、数量与信息保持不变。
func refresh_ui_style() -> void:
	for badge: PlayerMarkerBadge in _badges:
		badge.refresh_ui_style()


## 清理旧图标并按稳定顺序创建当前标记；空集合时组件尺寸归零且不拦截输入。
func _refresh_badges() -> void:
	if not is_node_ready():
		return
	for badge: PlayerMarkerBadge in _badges:
		badge.queue_free()
	_badges.clear()
	# 有效标记数组；数量非正数的数据不进入表现层。
	var ordered_marks: Array[Dictionary] = []
	for mark_id_variant: Variant in _marks.keys():
		# 当前标记副本；补齐稳定ID供排序和悬停回退使用。
		var mark_id: String = str(mark_id_variant)
		var mark_data: Dictionary = (_marks.get(mark_id_variant, {}) as Dictionary).duplicate(true)
		if int(mark_data.get("count", 0)) <= 0:
			continue
		mark_data["id"] = mark_id
		ordered_marks.append(mark_data)
	ordered_marks.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get("order", 0)) != int(right.get("order", 0)):
			return int(left.get("order", 0)) < int(right.get("order", 0))
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	for mark_index: int in range(ordered_marks.size()):
		# 当前单标记组件；只持有本项公开数据副本并转发悬停信息。
		var badge: PlayerMarkerBadge = PlayerMarkerBadge.new()
		badge.name = "Marker_%s" % str(ordered_marks[mark_index].get("id", mark_index))
		badge.z_index = 1
		add_child(badge)
		badge.configure(ordered_marks[mark_index])
		badge.information_requested.connect(_on_badge_information_requested)
		badge.information_dismissed.connect(_on_badge_information_dismissed)
		# 当前主轴偏移；横排改变x，纵排改变y。
		var primary_offset: float = float(mark_index) * (badge.badge_diameter + marker_gap)
		badge.position = Vector2(primary_offset, 0.0) if horizontal else Vector2(0.0, primary_offset)
		_badges.append(badge)
	size = get_required_size()
	custom_minimum_size = size
	visible = not _badges.is_empty()


## 转发子标记信息请求；来源仍由最外层绑定的PlayerMarkersView实例统一标识。
func _on_badge_information_requested(information: Dictionary, anchor_rect: Rect2) -> void:
	information_requested.emit(information, anchor_rect)


## 转发子标记信息关闭请求。
func _on_badge_information_dismissed() -> void:
	information_dismissed.emit()
