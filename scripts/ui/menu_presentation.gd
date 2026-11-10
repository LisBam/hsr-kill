extends Node

## 首页表现装配器。只在父级MainMenu子树注册按钮、页面和模态；不承担导航、联网、文件操作或游戏规则。
## 新增页面可以在检查器补充路径；动态列表按钮通过node_added自动接入，不需要逐个手写动画。

## 表现服务脚本；由子节点持有Tween与统一时长。
const MOTION_SCRIPT: Script = preload("res://scripts/ui/menu_motion.gd")
## 原生按钮反馈脚本；每个按钮挂载一个无逐帧处理的Control组件。
const BUTTON_MOTION_SCRIPT: Script = preload("res://scripts/ui/menu_button_motion.gd")
## 单次绘制背景组件；首页与大厅分别安装，不接触战斗背景。
const AMBIENT_SCRIPT: Script = preload("res://scripts/ui/menu_ambient.gd")
## 品牌罗盘矢量；用主题强调色调制，48像素资源可按视口无损缩放。
const BRAND_EMBLEM: Texture2D = preload("res://assets/ui/menu_emblem.svg")
## 导航光标内缩；默认18逻辑像素，避免强调线贴住相邻标签。
const CURSOR_INSET: float = 18.0
## 导航光标高度；默认3逻辑像素，保持清晰而不制造第二条厚边。
const CURSOR_HEIGHT: float = 3.0
## 四个对等客户区；路径相对MainMenu，按导航顺序定义，运行前可在检查器扩展。
@export var page_paths: Array[NodePath] = [^"MainMenuFrame", ^"OnlineSettingsPanel", ^"AllCardsPanel", ^"MatchReplayPanel"]
## 顶部导航按钮的唯一名；顺序与page_paths一致，供滑动光标定位。
@export var navigation_paths: Array[NodePath] = [^"%TopIdentityModeButton", ^"%MainMenuOnlineSettingsButton", ^"%MainMenuAllCardsButton", ^"%MainMenuMatchReplayButton"]
## 局外动效开关；默认开启，运行时修改后由setter同步按钮和背景，关闭时不改业务状态。
@export var animations_enabled: bool = true:
	set(value):
		animations_enabled = value
		if is_node_ready():
			_apply_motion_preference()
## 导航光标时长；默认0.24秒，可运行时调整，快速切换从当前位置继续移动。
@export_range(0.05, 0.5, 0.01) var navigation_duration: float = 0.24
## 父级局外范围；初始为空，安装后不再向上越界注册控件。
var _scope: Control
## 子节点动画服务；实例生命周期与首页一致。
var _motion: MOTION_SCRIPT
## 当前顶部页索引；默认0，只记录视觉方向，不作为业务导航状态。
var _page_index: int = 0
## 导航高光；纯绘制Control，不参与键盘和鼠标事件。
var _navigation_cursor: Panel
## 当前光标Tween；连续切页前取消，避免光标轨道叠加。
var _navigation_tween: Tween
## 顶部按钮引用；只包含四个固定导航入口。
var _navigation_buttons: Array[Button] = []
## 上一次显示的模式标题；只用于去重同模式重复点击的视觉更新。
var _last_mode_title: String = ""
## 氛围层引用；仅首页与大厅两层，主题与动效开关同步更新。
var _ambient_layers: Array[ColorRect] = []
## 模式预览的静态渐变压暗层；只增强标题和底部操作栏可读性，不消费逐帧CPU。
var _hero_vignette: TextureRect
## 品牌区矢量图标；独立于标题文字，不改变可见功能名称。
var _brand_emblem: TextureRect
## 已挂载按钮反馈的弱引用；节点退出后自动移除，避免图鉴/大厅重建时增长。
var _feedback: Dictionary = {}


## 父组件先完成动态详情与回放界面构建，再执行装配。
func _ready() -> void:
	call_deferred("_install")


## 注册所有局外入口；明确的表面路径保证不会给每个设置行或牌面内部重复播放入场。
func _install() -> void:
	_scope = get_parent() as Control
	if _scope == null:
		return
	_motion = get_node("Motion") as MOTION_SCRIPT
	_scope.set_meta(MOTION_SCRIPT.SERVICE_META, weakref(_motion))
	for path: NodePath in page_paths:
		# 当前页；旧场景缺少回放时可安全跳过。
		var page: Control = _scope.get_node_or_null(path) as Control
		if page != null:
			_motion.watch(page, page)
			page.visibility_changed.connect(_queue_navigation_sync)
	_watch_named_surface("MainMenuSettingsPanel", "MainMenuSettingsPanel", "modal")
	_watch_named_surface("MainMenuModeDetailsPanel", "MainMenuModeDetailsPanel", "modal")
	_watch_named_surface("LanLobbyPanel", "LanLobbyFrame", "modal")
	_watch_named_surface("OnlineLobbyPanel", "OnlineLobbySurface", "page")
	_watch_named_surface("OnlineLobbySettingsPanel", "OnlineLobbySettingsPanel", "modal")
	_watch_named_surface("AllCardsInfoBackdrop", "AllCardsInfoPanel", "modal")
	_watch_named_surface("ReplayPathModalPanel", "ReplayPathModalPanel", "modal")
	_install_navigation()
	_install_brand_emblem()
	_install_hero_vignette()
	_install_background(_scope, 2)
	# 大厅单独全屏背景；其自身的背景会遮住主菜单氛围层，因此需要局部副本。
	var lobby: Control = _scope.find_child("OnlineLobbyPanel", true, false) as Control
	if lobby != null:
		_install_background(lobby, 1)
	_bind_existing(_scope)
	get_tree().node_added.connect(_on_node_added)
	_scope.visibility_changed.connect(_on_scope_visibility)
	GameSettings.ui_style_changed.connect(_on_style_changed)
	_apply_motion_preference()
	_refresh_decoration()


## 在范围内查找开关节点和视觉表面；找不到时不猜路径、不影响业务界面。
func _watch_named_surface(trigger_name: String, visual_name: String, kind: String) -> void:
	# 负责显隐的原节点；不改变其业务脚本。
	var trigger: Control = _scope.find_child(trigger_name, true, false) as Control
	# 实际进入的内容面；模态遮罩保持原位置以保护输入。
	var visual: Control = _scope.find_child(visual_name, true, false) as Control
	if trigger != null:
		_motion.watch(trigger, visual if visual != null else trigger, kind)


## 装配顶部滑动指示线；保留原有每页选中线，额外光标只在四个槽位之间过渡。
func _install_navigation() -> void:
	# 顶部导航容器；光标作为普通Panel绘制，避免容器重新分配按钮宽度。
	var navigation: Control = _scope.get_node_or_null("%MainMenuTopNavigation") as Control
	if navigation == null:
		return
	_navigation_cursor = Panel.new()
	_navigation_cursor.name = "MenuNavigationCursor"
	_navigation_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_navigation_cursor.z_index = 1
	# 光标挂在自由布局根上，避免PanelContainer把它强行铺满整个导航栏。
	_scope.add_child(_navigation_cursor)
	for index: int in range(navigation_paths.size()):
		# 当前顶部按钮；业务连接已完成，因此本连接只在业务更新之后播放。
		var button: Button = _scope.get_node_or_null(navigation_paths[index]) as Button
		if button != null:
			_navigation_buttons.append(button)
			button.pressed.connect(_on_page_requested.bind(index))
			button.resized.connect(_snap_navigation)
	_scope.resized.connect(_snap_navigation)
	call_deferred("_snap_navigation")


## 新页切换同时移动导航线；实际页的visible仍由MainMenu决定，异步内容载入不会被抢先打开。
func _on_page_requested(index: int) -> void:
	# 页面方向；跨多页只保留左右方向，不放大动画距离。
	var direction: float = 1.0 if index >= _page_index else -1.0
	_page_index = index
	_move_navigation(false)
	if index < page_paths.size():
		# 已准备好的页面；内容尚未加载时让visibility观察器随后接手。
		var page: Control = _scope.get_node_or_null(page_paths[index]) as Control
		if page != null and page.is_visible_in_tree():
			_motion.reveal(page, "page", direction)


## 布局变更后直接贴合当前按钮，避免窗口缩放与导航动画互相拉扯。
func _snap_navigation() -> void:
	if not is_instance_valid(_scope):
		return
	for index: int in range(_navigation_buttons.size()):
		if _navigation_buttons[index].button_pressed:
			_page_index = index
	_move_navigation(true)


## 业务代码可能通过Esc或网络返回切页；延迟一轮读取最终选中态，覆盖非点击导航路径。
func _queue_navigation_sync() -> void:
	call_deferred("_sync_navigation")


## 与原有顶部互斥状态对齐；只在目标改变时移动，不打断用户刚触发的光标Tween。
func _sync_navigation() -> void:
	for index: int in range(_navigation_buttons.size()):
		if _navigation_buttons[index].button_pressed and index != _page_index:
			_page_index = index
			_move_navigation(false)
			return


## 只动画光标的局部坐标，不修改按钮位置；三像素强调线与文字形成清晰导航层次。
func _move_navigation(immediate: bool) -> void:
	if _navigation_cursor == null or _page_index >= _navigation_buttons.size():
		return
	if _navigation_tween != null and _navigation_tween.is_valid():
		_navigation_tween.kill()
	# 目标按钮；坐标换算使用布局位置，与按钮自身视觉上浮无关。
	var button: Button = _navigation_buttons[_page_index]
	# 光标所在顶部容器；只参与视觉坐标换算。
	var navigation: Control = _navigation_cursor.get_parent() as Control
	# 目标光标矩形；左右内缩18像素，避免连成厚重的整圈金框。
	var target_position: Vector2 = button.global_position - navigation.global_position + Vector2(CURSOR_INSET, button.size.y - CURSOR_HEIGHT)
	# 目标线长；宽度变化与位移使用同一个轨道。
	var target_size: Vector2 = Vector2(maxf(1.0, button.size.x - CURSOR_INSET * 2.0), CURSOR_HEIGHT)
	if immediate or not animations_enabled:
		_navigation_cursor.position = target_position
		_navigation_cursor.size = target_size
		return
	_navigation_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_navigation_tween.tween_property(_navigation_cursor, "position", target_position, navigation_duration)
	_navigation_tween.tween_property(_navigation_cursor, "size", target_size, navigation_duration)


## 安装无输入的全屏氛围层；索引由调用方指定，确保始终位于交互内容之后。
func _install_background(parent: Control, child_index: int) -> void:
	# 单个背景节点；没有额外图片、粒子系统或屏幕复制。
	var background: ColorRect = AMBIENT_SCRIPT.new() as ColorRect
	background.name = "MenuAmbient"
	parent.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.move_child(background, child_index)
	_ambient_layers.append(background)


## 给指定原画添加静态暗角；保留原TextureRect的覆盖裁剪与原图比例。
func _install_hero_vignette() -> void:
	# 预览原画；动态场景缺少原画时不构建占位替代内容。
	var artwork: TextureRect = _scope.find_child("MainMenuModeBackground", true, false) as TextureRect
	if artwork == null:
		return
	_hero_vignette = TextureRect.new()
	_hero_vignette.name = "MenuHeroVignette"
	_hero_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.get_parent().add_child(_hero_vignette)
	_hero_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.get_parent().move_child(_hero_vignette, artwork.get_index() + 2)


## 将品牌文本包入横向组合；原标题节点与唯一名保留，外层宽度和顶部高度保持不变。
func _install_brand_emblem() -> void:
	# 现有品牌容器；只装配一次，不改变导航按钮的业务与顺序。
	var brand: Control = _scope.find_child("MainMenuBrand", true, false) as Control
	if brand == null:
		return
	# 横向品牌组合；继承原品牌容器的最小宽度。
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "MenuBrandRow"
	row.custom_minimum_size = brand.custom_minimum_size
	row.add_theme_constant_override("separation", 12)
	brand.get_parent().add_child(row)
	brand.get_parent().move_child(row, brand.get_index())
	_brand_emblem = TextureRect.new()
	_brand_emblem.name = "MenuBrandEmblem"
	_brand_emblem.texture = BRAND_EMBLEM
	_brand_emblem.custom_minimum_size = Vector2(42.0, 42.0)
	_brand_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_brand_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_brand_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_brand_emblem)
	brand.reparent(row)
	brand.custom_minimum_size.x = 0.0
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## 扫描已有原生按钮；不深入Node2D正式牌面，避免改变卡牌内部输入组件。
func _bind_existing(node: Node) -> void:
	if node is Node2D:
		return
	if node is BaseButton:
		_bind_button(node as BaseButton)
	for child: Node in node.get_children():
		_bind_existing(child)


## 动态回放条目、空位与踢出按钮入树后自动获得相同反馈；其他子树一律忽略。
func _on_node_added(node: Node) -> void:
	if node is BaseButton and is_instance_valid(_scope) and _scope.is_ancestor_of(node):
		call_deferred("_bind_dynamic_button", weakref(node))


## 动态节点可能在同一帧重建后释放；延迟注册使用弱引用，避免把已释放对象传入强类型参数。
func _bind_dynamic_button(reference: WeakRef) -> void:
	# 仍存活的按钮；退出场景树的临时节点不再装配反馈。
	var button: BaseButton = reference.get_ref() as BaseButton
	if button != null and button.is_inside_tree():
		_bind_button(button)


## 每个按钮只安装一次；Node2D牌面内部的按钮保持原有卡牌表现。
func _bind_button(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.is_queued_for_deletion() or button.has_node("MenuButtonMotion"):
		return
	# 祖先游标；正式牌面自己的动效与输入不在此服务职责内。
	var ancestor: Node = button.get_parent()
	while ancestor != null and ancestor != _scope:
		if ancestor is Node2D:
			return
		ancestor = ancestor.get_parent()
	# 反馈组件；独立持有Tween，按钮释放时随树回收。
	var feedback: BUTTON_MOTION_SCRIPT = BUTTON_MOTION_SCRIPT.new()
	feedback.name = "MenuButtonMotion"
	feedback.motion_enabled = animations_enabled
	button.add_child(feedback)
	_feedback[button.get_instance_id()] = weakref(feedback)
	button.tree_exiting.connect(_forget_button.bind(button.get_instance_id()), CONNECT_ONE_SHOT)
	# 模式卡的现有业务先更新标题；这里只对右侧摘要与画面播放切换表现。
	if button.get_parent().name == "ModeCardsVBox":
		button.pressed.connect(_on_mode_changed)
	# 图鉴子分类；内容仍由原组件缓存和按需创建，视觉层不重建网格。
	if str(button.name) in ["AllCharactersTabButton", "AllGameCardsTabButton", "AllOpportunitiesTabButton"]:
		button.pressed.connect(_on_gallery_category_changed)


## 清理动态按钮的弱引用，长时间切换大厅/列表也不留下历史节点键。
func _forget_button(key: int) -> void:
	_feedback.erase(key)


## 模式变化时仅淡入原画和摘要；操作栏不位移，玩家可直接连续切换或开局。
func _on_mode_changed() -> void:
	# 模式标题来自现有业务；重复点击已选模式不重复播放大幅动画。
	var title: Label = _scope.get_node_or_null("%MainMenuModeTitle") as Label
	if title == null or title.text == _last_mode_title:
		return
	_last_mode_title = title.text
	_motion.reveal(_scope.get_node("%MainMenuModeSummaryPanel") as Control, "modal")
	# 同一张指定原画继续使用，仅做短淡入，不加载额外大图。
	var artwork: Control = _scope.find_child("MainMenuModeBackground", true, false) as Control
	if artwork != null:
		_motion.reveal(artwork, "fade")


## 图鉴子分页变化时让内容区轻滑进入；缓存复用和每帧牌面创建配额保持不变。
func _on_gallery_category_changed() -> void:
	# 内容滚动区；不改动scroll_vertical，动画不会破坏滚动条范围。
	var grid: Control = _scope.find_child("AllCardsGridScroll", true, false) as Control
	if grid != null:
		_motion.reveal(grid, "page")


## 主题变更后只重绘装饰；原有页面先自行完成主题刷新。
func _on_style_changed(_style_id: String) -> void:
	call_deferred("_refresh_decoration")


## 更新顶部指示线和品牌次级文字；保留全部玩家可见功能名称。
func _refresh_decoration() -> void:
	# 局外正文滚动区也使用同主题滑条；正式牌面的Node2D内部不在导航装配范围。
	for scroll_node: Node in _scope.find_children("*", "ScrollContainer", true, false):
		# 当前原生滚动容器；只更新外观，保留滚动值与条目布局。
		var scroll: ScrollContainer = scroll_node as ScrollContainer
		# 既有滑条宽度优先，保留模式列表与图鉴在检查器中指定的尺寸。
		var scroll_bar: VScrollBar = scroll.get_v_scroll_bar()
		BattleUIStyle.apply_main_menu_scroll_bar_style(scroll_bar, scroll_bar.custom_minimum_size.x if scroll_bar.custom_minimum_size.x > 0.0 else BattleUIStyle.MAIN_MENU_SCROLL_BAR_WIDTH)
	if _brand_emblem != null:
		_brand_emblem.modulate = BattleUIStyle.get_color("accent")
	if _hero_vignette != null:
		# 原画顶部和底部压暗、中间保留原色；颜色跟随活动主题。
		var gradient: Gradient = Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.64, 1.0])
		gradient.colors = PackedColorArray([Color(BattleUIStyle.get_color("outer_background"), 0.38), Color.TRANSPARENT, Color.TRANSPARENT, Color(BattleUIStyle.get_color("outer_background"), 0.76)])
		# 细长渐变纹理；8×256像素足以线性插值，避免生成屏幕大小的纹理。
		var texture: GradientTexture2D = GradientTexture2D.new()
		texture.width = 8
		texture.height = 256
		texture.fill_from = Vector2.ZERO
		texture.fill_to = Vector2(0.0, 1.0)
		texture.gradient = gradient
		_hero_vignette.texture = texture
	if _navigation_cursor != null:
		# 导航强调线样式；无阴影，不影响容器最小尺寸。
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = BattleUIStyle.get_color("accent")
		style.set_corner_radius_all(2)
		_navigation_cursor.add_theme_stylebox_override("panel", style)
	# 既有下划线继续表达选中状态，但淡化后由滑动光标承担主要强调。
	for indicator_name: String in ["TopIdentityModeIndicator", "TopOnlineSettingsIndicator", "TopAllCardsIndicator", "TopMatchReplayIndicator"]:
		# 原生指示线；不改变visible契约，避免影响导航判断。
		var indicator: CanvasItem = _scope.find_child(indicator_name, true, false) as CanvasItem
		if indicator != null:
			indicator.self_modulate.a = 0.16
	_snap_navigation()


## 动效开关只作用于本表现树；不改变游戏速度、声音或网络设置。
func _apply_motion_preference() -> void:
	if _motion != null:
		_motion.animations_enabled = animations_enabled
	for reference: WeakRef in _feedback.values():
		# 仍存活的反馈组件；已释放条目会被退出信号移除。
		var feedback: Control = reference.get_ref() as Control
		if feedback != null:
			feedback.set("motion_enabled", animations_enabled)
	for background: ColorRect in _ambient_layers:
		background.set("motion_enabled", animations_enabled)
		background.call("refresh_style")
	if not animations_enabled:
		_snap_navigation()


## 页面重新显示时纠正光标；进入游戏后父级隐藏会自然停止全部背景绘制。
func _on_scope_visibility() -> void:
	if _scope.is_visible_in_tree():
		call_deferred("_snap_navigation")
	else:
		_motion.cancel_all()
		if _navigation_tween != null and _navigation_tween.is_valid():
			_navigation_tween.kill()
