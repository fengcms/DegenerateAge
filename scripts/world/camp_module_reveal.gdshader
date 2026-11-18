shader_type canvas_item;
// 上部局部遮挡淡出：仅改变显示alpha，不参与碰撞；无屏幕采样与动态灯光。
uniform float reveal_amount = 0.0;
uniform sampler2D reveal_mask : filter_nearest, repeat_disable;
uniform vec2 focus_uv = vec2(0.5);
uniform vec2 radius_uv = vec2(0.2);
// 仅对允许淡出的屋顶/树冠蒙版及人物附近椭圆区域降低透明度。
void fragment() {
	vec4 pixel = COLOR;
	float upper = texture(reveal_mask, UV).r;
	float region = 1.0 - smoothstep(0.65, 1.0, length((UV - focus_uv) / radius_uv));
	pixel.a *= 1.0 - 0.82 * reveal_amount * upper * region;
	COLOR = pixel;
}
