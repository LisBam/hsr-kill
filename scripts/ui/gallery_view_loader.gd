class_name GalleryViewLoader
extends Node

## 图鉴的通用加载调度组件。页面只提供条目与创建回调；本组件管理视口优先级、后台插画与 CPU 时间预算。
## 列表内容或几何变化时扫描一次目录，范围准备完成后停止逐帧处理；不持有规则对象或玩家设置。

## 运行时预算的安全下限（毫秒）；与页面检查器的0.5毫秒最小值一致，防止错误配置让队列永远没有工作机会。
const MIN_CREATION_BUDGET_MS: float = 0.5

## 每帧牌面创建时间预算（毫秒）；默认3毫秒，至少允许一张，单张创建无法被中途抢占。
var creation_budget_ms: float = 3.0

## 每帧最大创建数量；默认4张，与时间预算同时生效，页面在刷新时传入检查器配置。
var visible_views_per_frame: int = 4

## 视口上下的预取屏数；默认2屏，页面刷新时传入，0表示只准备当前可视区域。
var prefetch_viewport_count: float = 2.0

## 当前完整条目；字典包含slot、definition与view，页面和调度器共享同一展示数据。
var _entries: Array[Dictionary] = []

## 需要优先完成的可见牌面；范围变化时重新生成，不保留过时滚动任务。
var _viewport_entries: Array[Dictionary] = []

## 当前屏之外的预取牌面；只在当前屏准备完整后调度。
var _buffer_entries: Array[Dictionary] = []

## 当前页面的滚动容器；滚动值和尺寸变化唤醒加载，无需每帧遍历完整目录。
var _scroll: ScrollContainer

## 页面列表遮罩；只在加载状态或几何改变时更新，避免稳定浏览时反复覆盖主题属性。
var _cover: GalleryLoadingCover

## 所属内容页；通过有效可见性判断祖先首页隐藏的情况。
var _page: Control

## 页面专有的牌面创建回调；必须同步创建节点并写回条目的view字段。
var _create_view: Callable

## 是否需要重算加载范围；滚动、布局和可见性事件只标记一次，下个处理帧合并执行。
var _range_dirty: bool = true


## 装配一次滚动与可见性信号；调用者应先把本组件挂到对应内容页，再执行绑定。
func bind(scroll: ScrollContainer, cover: GalleryLoadingCover, create_view: Callable) -> void:
	_scroll = scroll
	_cover = cover
	_page = get_parent() as Control
	_create_view = create_view
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	_scroll.resized.connect(invalidate)
	_page.visibility_changed.connect(invalidate)
	set_process(false)


## 提交已完成布局的条目；保持原有节点缓存，只重算需要准备的范围。
func refresh(entries: Array[Dictionary]) -> void:
	_entries = entries
	invalidate()


## 等待页面完成筛选与布局时暂停旧任务，防止按旧分类或旧坐标创建无用牌面。
func suspend() -> void:
	set_process(false)
	_viewport_entries.clear()
	_buffer_entries.clear()
	if is_instance_valid(_page) and _page.is_visible_in_tree():
		_cover.set_loading(true, _scroll)


## 合并滚动、尺寸和显示变化；隐藏页面停止创建，重新打开时根据当前滚动位置恢复。
func invalidate() -> void:
	_range_dirty = true
	set_process(is_instance_valid(_page) and _page.is_visible_in_tree())


## 滚动值只用于唤醒；实际位置在下帧统一读取，快速连续拖动不会堆积过时任务。
func _on_scroll_changed(_value: float) -> void:
	invalidate()


## 根据当前范围非阻塞准备插画并创建正式牌面；数量和时间预算共同限制单帧工作量。
func _process(_delta: float) -> void:
	if not _page.is_visible_in_tree():
		set_process(false)
		return
	# 范围变化时需要重新同步遮罩坐标；稳定加载帧不重复覆盖颜色和布局属性。
	var range_changed: bool = _range_dirty
	if _range_dirty:
		_rebuild_range()
	# 本帧起点；同时限制插画任务轮询和牌面装配工作。
	var started: int = Time.get_ticks_usec()
	# 本帧剩余创建数量；至少为1，避免异常配置让遮罩永远不消失。
	var remaining: int = maxi(visible_views_per_frame, 1)
	# 当前屏队列先于邻屏队列；当前屏未齐时不挤占后台并发名额。
	for pending: Array[Dictionary] in [_viewport_entries, _buffer_entries]:
		# 当前队列游标；未完成插画跳过，已创建条目立即移除。
		var index: int = 0
		while index < pending.size() and remaining > 0:
			if Time.get_ticks_usec() - started >= maxf(creation_budget_ms, MIN_CREATION_BUDGET_MS) * 1000.0:
				break
			# 当前条目；预先准备纹理后，组件原有同步加载入口只访问引擎缓存。
			var entry: Dictionary = pending[index]
			if not ArtworkLoader.prepare_from_definition(entry.get("definition", {})):
				index += 1
				continue
			_create_view.call(entry)
			pending.remove_at(index)
			remaining -= 1
		if not _viewport_entries.is_empty():
			break
	if range_changed or _cover.visible != (not _viewport_entries.is_empty()):
		_cover.set_loading(not _viewport_entries.is_empty(), _scroll)
	if _viewport_entries.is_empty() and _buffer_entries.is_empty():
		set_process(false)


## 每次范围变化扫描一次完整目录；当前屏优先，邻屏按距视口的距离预取，避免固定先加载上方。
func _rebuild_range() -> void:
	_range_dirty = false
	_viewport_entries.clear()
	_buffer_entries.clear()
	# 当前视口上、下边界及预取范围；均使用滚动内容坐标。
	var top: float = _scroll.scroll_vertical
	# 视口底边；滚动条本身的裁切尺寸由ScrollContainer处理。
	var bottom: float = top + _scroll.size.y
	# 上下预取距离；隐藏或搜索过滤的条目不参与准备。
	var margin: float = _scroll.size.y * prefetch_viewport_count
	# 完整目录条目；只有范围失效时访问一次，不在空闲帧重复扫描。
	for entry: Dictionary in _entries:
		# 当前固定尺寸槽；目录失效后refresh会替换整组条目。
		var slot: Control = entry.get("slot") as Control
		if not is_instance_valid(slot) or not slot.visible or is_instance_valid(entry.get("view")):
			continue
		if slot.position.y + slot.size.y > top and slot.position.y < bottom:
			_viewport_entries.append(entry)
		elif slot.position.y + slot.size.y > top - margin and slot.position.y < bottom + margin:
			_buffer_entries.append(entry)
	_buffer_entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return absf((left["slot"] as Control).position.y - top) < absf((right["slot"] as Control).position.y - top)
	)
