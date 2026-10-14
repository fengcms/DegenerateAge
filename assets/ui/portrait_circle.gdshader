shader_type canvas_item;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	if (dot(p, p) > 0.94) {
		discard;
	}
}
