shader_type canvas_item;
render_mode unshaded;

// 局外背景单次绘制：低对比光晕、轨道与稀疏星点，不读取屏幕、不创建粒子节点。
uniform vec4 base_color : source_color = vec4(0.045, 0.05, 0.065, 1.0);
// 强调色来自当前主题；缺省金色仅用于材质尚未初始化时。
uniform vec4 accent_color : source_color = vec4(0.83, 0.71, 0.37, 1.0);
// 动效关闭后固定时间采样；隐藏画布不产生任何片元开销。
uniform bool motion_enabled = true;
// 装饰强度，0至1；运行时由MenuAmbient.strength覆盖。
uniform float strength : hint_range(0.0, 1.0) = 0.22;
// 每秒网格位移，0至0.1；0为静止，默认0.008用于缓慢漂移。
uniform float drift_speed : hint_range(0.0, 0.1) = 0.008;
// 当前背景宽高比；缺省16:9，resize时由组件同步。
uniform float aspect_ratio = 1.777778;
// 浅色纸面采用印刷式金线，深色主题继续使用光晕；由语义注册表决定，默认开启。
uniform bool paper_theme = true;

// 确定性视觉噪声，不消费游戏规则使用的随机源。
float hash_cell(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// 动效关闭时的固定采样时间，避免视觉仍随TIME变化。
	float clock_time = motion_enabled ? TIME : 0.0;
	// 相对右上方光晕中心的等比坐标，防止窗口比例改变时圆环被压扁。
	vec2 point = (UV - vec2(0.78, 0.28)) * vec2(aspect_ratio, 1.0);
	// 径向衰减光晕，仅提供低对比度背景层次。
	float glow = exp(-dot(point, point) * 2.4);
	// 亚像素抗锯齿轨道，0.68为相对画布高度的装饰半径。
	float orbit = 1.0 - smoothstep(0.0005, 0.002, abs(length(point) - 0.68));
	// 稀疏星点网格坐标；34×19与默认横屏比例对应。
	vec2 star_uv = UV * vec2(34.0, 19.0) + vec2(clock_time * drift_speed, -clock_time * drift_speed * 0.4);
	// 当前网格索引，用于生成确定性星点位置。
	vec2 cell = floor(star_uv);
	// 每格的确定性数值，范围0至1，不接入CPU随机数。
	float seed = hash_cell(cell);
	// 单元格内相对星点中心的坐标，中心避开网格边缘。
	vec2 local = fract(star_uv) - vec2(0.2 + seed * 0.6, 0.2 + hash_cell(cell + 2.0) * 0.6);
	// 仅9%的单元格绘制小光点，限制视觉密度。
	float star = (1.0 - smoothstep(0.012, 0.065, length(local))) * step(0.91, seed);
	// 平缓明暗变化，不产生频闪或突然消失。
	float shimmer = 0.62 + 0.38 * sin(clock_time * 0.7 + seed * 26.0);
	// 最终背景颜色，光晕、轨道和星点按统一强度合成。
	vec3 background = base_color.rgb + accent_color.rgb * glow * strength * 0.25;
	background += accent_color.rgb * (orbit * 0.12 + star * shimmer * 0.65) * strength;
	if (paper_theme) {
		// 角落星盘的等比坐标，中心内容区只保留低对比纸色。
		vec2 paper_point = (UV - vec2(0.97, 0.1)) * vec2(aspect_ratio, 1.0);
		// 三条同心金线采用像素导数抗锯齿，不依赖屏幕分辨率。
		float radius = length(paper_point);
		float line_width = max(fwidth(radius), 0.0008);
		float rings = 1.0 - smoothstep(line_width, line_width * 2.0, min(abs(radius - 0.61), min(abs(radius - 0.69), abs(radius - 1.25))));
		// 对角交线形成淡淡的星图纹理，不绘制明亮闪烁星点。
		float diagonal = 1.0 - smoothstep(line_width, line_width * 2.0, abs(paper_point.x + paper_point.y * 0.7));
		background = mix(base_color.rgb, accent_color.rgb, (rings * 0.32 + diagonal * 0.16) * strength);
	}
	COLOR = vec4(background, base_color.a);
}
