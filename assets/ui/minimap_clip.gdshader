shader_type canvas_item;
// 小地图局部视野的圆形裁剪：圆外的地形、标记、路线一律丢弃，
// 避免放大后的内容糊到 HUD 框体之外（小地图是全仓首个非矩形裁剪需求）。
// clip_center / clip_radius 用被裁剪节点自身的局部坐标（与 GDScript 侧同步更新），
// 因此不依赖 UV 语义，底图网格与标记层共用同一份材质。
uniform vec2 clip_center = vec2(82.0, 82.0);
uniform float clip_radius = 79.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	if (distance(local_pos, clip_center) > clip_radius) {
		discard;
	}
}
