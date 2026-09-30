shader_type canvas_item;

// 绿幕色度键控。把过场动画视频里指定钥匙色（默认纯绿）的背景像素变成完全透明，
// 让视频直接叠在牌桌画面上播放，而不需要在外部软件里预先抠像。
//
// 判定使用“色度距离”而不是 RGB 距离：先减去每个像素自身的亮度，只比较颜色信息。
// 这样绿幕上的阴影、明暗渐变仍然是同一种色度，能被同一阈值吃掉；
// 而前景中亮度相近但色相不同的部分（肤色、金属、红蓝服装）不会被误抠。
//
// 使用方式：把本材质赋给 VideoStreamPlayer（或任何显示视频帧的 CanvasItem），
// 若视频背景不是标准绿幕，只需修改 key_color 即可。

// 需要被抠掉的背景色；默认纯绿（0,1,0），绿幕视频保持默认值。
uniform vec3 key_color : source_color = vec3(0.0, 1.0, 0.0);

// 色度相似度阈值：与钥匙色的色度距离小于该值的像素视为背景并完全透明。
// 默认0.30足以吃掉视频压缩噪声与轻微溢色，又明显小于常见前景色的色度距离。
uniform float similarity : hint_range(0.0, 1.5) = 0.30;

// 边缘过渡宽度：在阈值之上的一段距离内做平滑过渡，用于保留发丝与半透明边缘。
// 默认0.12兼顾软边与不出现半透明绿边；调小会得到更锐利但更容易锯齿的轮廓。
uniform float smoothness : hint_range(0.001, 1.0) = 0.12;

// 去溢色强度：0保留角色边缘的绿色反光，1按钥匙色方向完全移除溢色。
// 绿幕打光越强，角色边缘越容易残留绿边，因此默认1。
uniform float spill_suppression : hint_range(0.0, 1.0) = 1.0;

// 亮度权重：Rec.709系数，用于把颜色拆成“亮度 + 色度”两部分。
const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

// 取颜色的色度分量：剔除亮度后只剩色相与饱和度信息，同色不同亮度得到相同结果。
vec3 extract_chroma(vec3 color) {
	return color - vec3(dot(color, LUMA_WEIGHTS));
}


void fragment() {
	// 当前视频帧颜色；Theora视频没有Alpha通道，因此只需要重新计算不透明度。
	vec4 video_color = texture(TEXTURE, UV);
	// 像素色度与钥匙色色度；两者都是三维向量，长度差即为抠像依据。
	vec3 pixel_chroma = extract_chroma(video_color.rgb);
	vec3 key_chroma = extract_chroma(key_color);
	// 抠像遮罩：0表示完全透明（背景），1表示完全保留（前景）。
	float mask = smoothstep(similarity, similarity + smoothness, distance(pixel_chroma, key_chroma));
	// 钥匙色的色度方向；钥匙色本身为灰度时没有方向，退化为零向量避免非法归一化。
	vec3 key_chroma_direction = length(key_chroma) > 0.0001 ? normalize(key_chroma) : vec3(0.0);
	// 当前像素沿钥匙色方向的多余色度；负值表示像素偏向互补色，不属于溢色，不参与削减。
	float spill_amount = max(dot(pixel_chroma, key_chroma_direction), 0.0);
	// 去溢色后的色度：只削减沿钥匙色方向的分量，肤色与红蓝等其它色相保持原样。
	vec3 despilled_chroma = pixel_chroma - key_chroma_direction * spill_amount * spill_suppression;
	// 最终颜色：保留原始亮度并换回去溢色后的色度，因此去溢色不会改变画面明暗关系。
	vec3 final_color = clamp(vec3(dot(video_color.rgb, LUMA_WEIGHTS)) + despilled_chroma, vec3(0.0), vec3(1.0));
	COLOR = vec4(final_color, video_color.a * mask);
}
