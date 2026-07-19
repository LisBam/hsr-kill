shader_type canvas_item;

// 联机大厅形象插画的圆角 Alpha 裁切。纹理尺寸不是正方形，因此用宽高比把 UV 转成等比例坐标后再计算圆角距离。
// 圆角半径：按插画短边归一化，0.0303与大厅边框的6像素圆角保持一致。
uniform float corner_radius = 0.0303;
// 插画宽高比：148.35除以197.8，令非正方形 UV 也使用等比例圆角。
uniform float artwork_aspect_ratio = 0.75;


void fragment() {
	// 原始插画颜色：保留 TextureRect 已有颜色调制，只在最后乘圆角透明度。
	vec4 artwork_color = texture(TEXTURE, UV) * COLOR;
	// 归一化插画半尺寸：横轴先乘宽高比，避免圆角在竖图中被拉伸成椭圆。
	vec2 half_size = vec2(artwork_aspect_ratio * 0.5, 0.5);
	// 当前片元相对中心的等比例坐标：坐标原点位于插画正中心。
	vec2 point = (UV - vec2(0.5)) * vec2(artwork_aspect_ratio, 1.0);
	// 圆角矩形的局部距离输入：正值区域仅存在于四个需要裁切的角落。
	vec2 rounded_point = abs(point) - half_size + corner_radius;
	// 带符号距离：小于等于0在圆角矩形内，大于0在矩形外。
	float signed_distance = min(max(rounded_point.x, rounded_point.y), 0.0) + length(max(rounded_point, 0.0)) - corner_radius;
	// 最终 Alpha 蒙版：0.002的平滑带消除像素边缘锯齿，不影响边框尺寸。
	float mask_alpha = 1.0 - smoothstep(0.0, 0.002, signed_distance);
	artwork_color.a *= mask_alpha;
	COLOR = artwork_color;
}
