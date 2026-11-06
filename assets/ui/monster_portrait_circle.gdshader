shader_type canvas_item;
// Boss头像圆形裁切：使用控件顶点坐标，避免AtlasTexture的图集UV偏移导致头像被误裁。
uniform vec2 portrait_size = vec2(64.0);
varying vec2 portrait_uv;
void vertex() {
	portrait_uv = VERTEX / max(portrait_size, vec2(1.0));
}
void fragment() {
	vec2 p = portrait_uv * 2.0 - 1.0;
	if (dot(p, p) > 0.94) {
		discard;
	}
}
