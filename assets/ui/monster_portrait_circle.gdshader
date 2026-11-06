shader_type canvas_item;
// Boss头像圆形裁切：使用控件顶点坐标，避免AtlasTexture的图集UV偏移导致头像被误裁。
uniform vec2 portrait_size = vec2(64.0);
varying vec2 portrait_uv;
// 将控件本地像素映射到0至1，不使用带图集偏移的UV。
void vertex() {
	portrait_uv = VERTEX / max(portrait_size, vec2(1.0));
}
// 仅裁去圆外像素；圆内颜色继续使用原始图集采样。
void fragment() {
	vec2 p = portrait_uv * 2.0 - 1.0;
	if (dot(p, p) > 0.94) {
		discard;
	}
}
