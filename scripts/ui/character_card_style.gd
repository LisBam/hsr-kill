extends RefCounted

## 武将牌表面材质工厂；只细化调用方传入的样式，不读取快照、主题单例或场景节点。
## 原样保留内容边距和信息几何，调用方继续拥有身份、势力及残血颜色的语义。

## 小型信息面的阴影半径；默认3像素避免窄牌面上的多层阴影糊成黑块。
const BADGE_SHADOW_SIZE: int = 3
## 主牌框的阴影半径；默认8像素形成清晰悬浮边缘，不扩大输入区域。
const BODY_SHADOW_SIZE: int = 8
## 姓名底色的压暗比例；默认0.42形成深色珐琅，保留不同势力的色相。
const NAME_DARKENING: float = 0.42
## 普通角标的描边收敛比例；默认0.24降低信息框与目标选择边框的视觉竞争。
const BADGE_BORDER_BLEND: float = 0.24
## 小型信息面的圆角；默认5像素，身份和手牌数继续使用原有矩形范围。
const BADGE_RADIUS: int = 5
## 信息面阴影透明度；默认0.38，在原画上仍保持清晰边界。
const BADGE_SHADOW_ALPHA: float = 0.38
## 信息面阴影下移；默认2像素，减少徽记周围的均匀黑晕。
const BADGE_SHADOW_OFFSET: float = 2.0
## 主框阴影透明度；默认0.54，维持武将牌与桌面的分离。
const BODY_SHADOW_ALPHA: float = 0.54
## 主框阴影下移；默认3像素，保留统一光照方向。
const BODY_SHADOW_OFFSET: float = 3.0
## 姓名条左侧强调线宽；默认2像素强化竖向阅读轴。
const NAME_BORDER_WIDTH: int = 2
## 势力圆徽底色压暗比例；默认0.22，与姓名条保持同色不同明度。
const FACTION_DARKENING: float = 0.22
## 势力圆徽边缘提亮比例；默认0.12形成金属轮廓。
const FACTION_EDGE_LIGHTENING: float = 0.12
## 体力槽底色压暗比例；默认0.12衬托红黄绿和灰色珠体。
const HEALTH_DARKENING: float = 0.12
## 体力槽边框向底色混合比例；默认0.42避免窄栏描边过重。
const HEALTH_BORDER_BLEND: float = 0.42


## 细化一份已由宿主创建的独立StyleBoxFlat；role只表达材质用途，绝不承载游戏身份或规则。
static func refine(style: StyleBoxFlat, role: StringName) -> void:
	style.shadow_color = Color(0.0, 0.0, 0.0, BADGE_SHADOW_ALPHA)
	style.shadow_size = BADGE_SHADOW_SIZE
	style.shadow_offset = Vector2(0.0, BADGE_SHADOW_OFFSET)
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	match role:
		&"body":
			style.shadow_size = BODY_SHADOW_SIZE
			style.shadow_offset = Vector2(0.0, BODY_SHADOW_OFFSET)
			style.shadow_color.a = BODY_SHADOW_ALPHA
		&"name":
			style.bg_color = style.bg_color.darkened(NAME_DARKENING)
			style.border_color = style.border_color.lerp(style.bg_color, BADGE_BORDER_BLEND)
			style.border_width_left = NAME_BORDER_WIDTH
			style.corner_radius_bottom_left = BADGE_RADIUS
			style.corner_radius_bottom_right = BADGE_RADIUS
		&"faction":
			style.bg_color = style.bg_color.darkened(FACTION_DARKENING)
			style.border_color = style.border_color.lightened(FACTION_EDGE_LIGHTENING)
		&"health":
			style.bg_color = style.bg_color.darkened(HEALTH_DARKENING)
			style.border_color = style.border_color.lerp(style.bg_color, HEALTH_BORDER_BLEND)
		&"identity", &"hand":
			style.set_corner_radius_all(BADGE_RADIUS)
			style.border_color = style.border_color.lerp(style.bg_color, BADGE_BORDER_BLEND)
			style.bg_color.a = 1.0
			style.border_color.a = 1.0
