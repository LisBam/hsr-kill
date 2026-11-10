extends ColorRect

## 轻量局外氛围层：单个ShaderMaterial完成背景光晕和缓慢星点，无_process、不占用规则随机数。
## 必须放在交互面板后方；mouse_filter固定IGNORE，隐藏主菜单后自动停止绘制。

## 背景着色器；资源只加载一次，每个氛围层创建独立材质以隔离参数。
const AMBIENT_SHADER: Shader = preload("res://assets/ui/menu_ambient.gdshader")
## 装饰强度；默认0.32，0至1，可运行时修改后调用refresh_style，避免干扰正文阅读。
@export_range(0.0, 1.0, 0.01) var strength: float = 0.32
## 星点漂移速度；默认0.008个网格单位/秒，可运行时修改后刷新，0表示静止。
@export_range(0.0, 0.1, 0.001) var drift_speed: float = 0.008
## 是否播放背景动效；默认true，可运行时修改后刷新，关闭后保留静态光晕。
@export var motion_enabled: bool = true


## 创建局部材质并订阅主题/尺寸；没有逐帧CPU工作。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	# 独立着色器材质；大厅和首页的宽高比可以分别更新。
	var ambient_material: ShaderMaterial = ShaderMaterial.new()
	ambient_material.shader = AMBIENT_SHADER
	material = ambient_material
	resized.connect(refresh_style)
	GameSettings.ui_style_changed.connect(_on_style_changed)
	refresh_style()


## 切换主题后延迟读取活动语义色，等待原有主题协调器完成同步。
func _on_style_changed(_style_id: String) -> void:
	call_deferred("refresh_style")


## 更新单个材质的参数；不修改UIStyleRegistry，也不重建纹理。
func refresh_style() -> void:
	if material == null:
		return
	# 当前材质；只在初始化后使用。
	var ambient_material: ShaderMaterial = material as ShaderMaterial
	ambient_material.set_shader_parameter("base_color", BattleUIStyle.get_color("outer_background"))
	ambient_material.set_shader_parameter("accent_color", BattleUIStyle.get_color("accent"))
	ambient_material.set_shader_parameter("strength", strength)
	ambient_material.set_shader_parameter("drift_speed", drift_speed)
	ambient_material.set_shader_parameter("motion_enabled", motion_enabled)
	ambient_material.set_shader_parameter("aspect_ratio", size.x / maxf(size.y, 1.0))
