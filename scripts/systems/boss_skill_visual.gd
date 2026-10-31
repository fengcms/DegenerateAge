class_name BossSkillVisual
extends RefCounted
## 只负责表现。几何为锁定的地面空间，所有进度由宿主原计时提供。
const EDGE := Color("ffad66")
const IMPACT_LIFE := 0.56
const MAX_DETAILS := 24
static var detail_count := 0
var impacts: Array[Dictionary] = []

static func profile(id: String) -> Dictionary:
	var cfg: Variant = DataLoader.get_table("bossVisuals")
	if cfg is Dictionary:
		var key := String(cfg.get("bosses", {}).get(id, "corruption"))
		return cfg.get("styles", {}).get(key, {}).duplicate()
	return {"color": "b76cba", "motif": "crack"}

func impact(geo: Dictionary, detailed: bool = true) -> void:
	if geo.is_empty():
		return
	if impacts.size() >= 3:
		_release(impacts.pop_front())
	var details := detailed and detail_count < MAX_DETAILS
	if details:
		detail_count += 1
	impacts.append({"geo": geo.duplicate(true), "age": 0.0, "details": details})

func tick(delta: float) -> bool:
	var active := not impacts.is_empty()
	for i in range(impacts.size() - 1, -1, -1):
		impacts[i].age = float(impacts[i].age) + delta
		if float(impacts[i].age) >= IMPACT_LIFE:
			_release(impacts.pop_at(i))
	return active

func clear() -> void:
	for entry in impacts:
		_release(entry)
	impacts.clear()
func _release(entry: Dictionary) -> void:
	if entry.get("details", false):
		detail_count = maxi(0, detail_count - 1)

func draw_impacts(canvas: Node2D, skin: Dictionary) -> void:
	for entry in impacts:
		var t := float(entry.age) / IMPACT_LIFE
		var geo: Dictionary = entry.geo
		var color := Color(String(skin.get("color", "c78a65")))
		# 命中亮芯短促，之后降为非危险暗纹，绝不延长伤害窗口。
		var flash := maxf(0.0, 1.0 - t * 5.0)
		_shape(canvas, geo, Color(color, 0.10 * (1.0 - t) + flash * 0.22), Color(color.lerp(Color.WHITE, flash), (1.0 - t) * 0.85), 2.0 + flash * 3.0)
		if entry.details:
			_motif(canvas, geo, skin, color, 1.0 - t, t, true)

static func warning(canvas: Node2D, geo: Dictionary, progress: float, skin: Dictionary, detailed: bool = true) -> void:
	if geo.is_empty():
		return
	var p := clampf(progress, 0.0, 1.0)
	_shape(canvas, geo, Color(0.75, 0.10, 0.045, 0.09 + p * 0.10), Color(EDGE, 0.16), 7.0)
	_shape(canvas, geo, Color(0, 0, 0, 0), EDGE, 1.8)
	if detailed:
		var color := Color(String(skin.get("color", "c78a65")))
		_motif(canvas, geo, skin, color, 0.45 + 0.5 * p, p, false)

static func _local(canvas: Node2D, ground: Vector2) -> Vector2:
	return canvas.to_local(Iso.from_ground(ground))

## 线段判定是胶囊：矩形加圆头，轮廓也完整覆盖圆头，不用屏幕粗线代替。
static func line_points(geo: Dictionary) -> PackedVector2Array:
	var a: Vector2 = geo["from"]
	var b: Vector2 = geo["to"]
	var dir := (b - a).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	var points := PackedVector2Array()
	for i in range(13):
		points.append(b + dir.rotated(-PI / 2.0 + PI * i / 12.0) * float(geo.half))
	for i in range(13):
		points.append(a + dir.rotated(PI / 2.0 + PI * i / 12.0) * float(geo.half))
	return points

static func _shape(canvas: Node2D, geo: Dictionary, fill: Color, edge: Color, width: float) -> void:
	match String(geo.get("kind", "")):
		"line":
			var points := line_points(geo)
			for i in range(points.size()):
				points[i] = _local(canvas, points[i])
			canvas.draw_colored_polygon(points, fill)
			points.append(points[0])
			canvas.draw_polyline(points, edge, width, true)
		"circle":
			var center := _local(canvas, geo.center)
			GroundFx.fill(canvas, center, float(geo.radius), fill)
			GroundFx.outline(canvas, center, float(geo.radius), edge, width, 48)
		"fan":
			var center := _local(canvas, geo.center)
			var dir := Iso.from_ground(geo.dir)
			GroundFx.sector(canvas, center, dir, float(geo.radius), float(geo.arc), fill, 24)
			GroundFx.sector_outline(canvas, center, dir, float(geo.radius), float(geo.arc), edge, width, 24)
		"ring":
			var center := _local(canvas, geo.center)
			GroundFx.band(canvas, center, float(geo.inner), float(geo.radius), fill, 48)
			GroundFx.outline(canvas, center, float(geo.radius), edge, width, 48)
			GroundFx.outline(canvas, center, float(geo.inner), edge, width, 40)

static func _motif(canvas: Node2D, geo: Dictionary, skin: Dictionary, tint: Color, alpha: float, progress: float, impact_mode: bool) -> void:
	var color := Color(tint, alpha)
	var motif := String(skin.get("motif", "crack"))
	if geo.kind == "line":
		var a: Vector2 = geo["from"]
		var b: Vector2 = geo["to"]
		var dir := (b - a).normalized()
		var side := dir.orthogonal()
		for i in range(7):
			var point := a.lerp(b, (i + 0.5) / 7.0)
			var width := float(geo.half) * (0.4 if motif == "metal" else 0.65)
			var tail := point - dir * minf(20.0, a.distance_to(b) / 20.0)
			canvas.draw_polyline(PackedVector2Array([_local(canvas, tail - side * width), _local(canvas, point), _local(canvas, tail + side * width)]), color, 1.6, true)
		var front := a.lerp(b, clampf(progress, 0.0, 1.0))
		canvas.draw_line(_local(canvas, front - side * float(geo.half) * 0.85), _local(canvas, front + side * float(geo.half) * 0.85), Color(tint, alpha * 0.65), 3.0, true)
		return
	var center: Vector2 = geo.center
	var radius := float(geo.radius)
	var inner := float(geo.get("inner", 0.0))
	var start := (geo.dir as Vector2).angle() - float(geo.arc) / 2.0 if geo.kind == "fan" else 0.0
	var arc := float(geo.arc) if geo.kind == "fan" else TAU
	var n := 5 if geo.kind == "fan" else 10
	for i in range(n):
		var angle := start + arc * (i + 0.5) / n
		var dir := Vector2.from_angle(angle)
		var lo := lerpf(inner, radius, 0.2) if inner > 0.0 else radius * 0.32
		var hi := lerpf(inner, radius, 0.87)
		var a := center + dir * lo
		var b := center + dir * hi
		if motif in ["crack", "root", "bone"]:
			var mid := a.lerp(b, 0.5) + dir.orthogonal() * (hi - lo) * 0.12
			canvas.draw_polyline(PackedVector2Array([_local(canvas, a), _local(canvas, mid), _local(canvas, b)]), color, 1.7 if impact_mode else 1.2, true)
		elif motif in ["metal", "seal", "eye"]:
			var mid := a.lerp(b, 0.7)
			var side := dir.orthogonal() * minf(12.0, (hi - lo) * 0.12)
			canvas.draw_polyline(PackedVector2Array([_local(canvas, a), _local(canvas, mid - side), _local(canvas, b), _local(canvas, mid + side), _local(canvas, a)]), color, 1.3, true)
		else:
			var pts := PackedVector2Array()
			for k in range(7):
				var d := dir.rotated(0.10 * sin(k * 0.9 + progress * 2.0))
				pts.append(_local(canvas, center + d * lerpf(lo, hi, k / 6.0)))
			canvas.draw_polyline(pts, color, 1.4, true)
		if impact_mode:
			var lift := sin(progress * PI) * (22.0 if motif in ["metal", "seal", "eye"] else 34.0)
			var base := _local(canvas, b)
			canvas.draw_line(base, base + Vector2(sin(angle * 3.0) * progress * 12.0, -lift), Color(tint.lerp(Color.WHITE, 0.25), alpha * 0.8), 2.0, true)
	# 进度光环始终位于危险区域内，不涂抹环击的中心安全区。
	var ring_r := lerpf(maxf(inner + (radius - inner) * 0.15, radius * 0.35), inner + (radius - inner) * 0.92, progress)
	if geo.kind == "fan":
		GroundFx.sector_outline(canvas, _local(canvas, center), Iso.from_ground(geo.dir), ring_r, arc, Color(tint, alpha * 0.6), 1.0, 24)
	else:
		GroundFx.outline(canvas, _local(canvas, center), ring_r, Color(tint, alpha * 0.65), 1.4, 40)
