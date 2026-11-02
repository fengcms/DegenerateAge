class_name BossSkillVisual
extends RefCounted
## 只负责表现。几何为锁定的地面空间，所有进度由宿主原计时提供。
const EDGE := Color("ffad66")
const IMPACT_LIFE := 0.56
const MAX_DETAILS := 24
const MAX_WARNING_DETAILS := 8
static var detail_count := 0
# 仅缓存不可变半径网格，与地图和配色无关；进程级最多32项，超限整批释放。
static var _rings: Dictionary = {}
static var _warning_frame := -1
static var _warning_details := 0
var impacts: Array[Dictionary] = []

## 读取Boss主题副本；只在宿主初始化或数据重载时调用。
static func profile(id: String) -> Dictionary:
	var cfg: Variant = DataLoader.get_table("bossVisuals")
	if cfg is Dictionary:
		var key := String(cfg.get("bosses", {}).get(id, "corruption"))
		return cfg.get("styles", {}).get(key, {}).duplicate()
	return {"color": "b76cba", "motif": "crack"}

## 记录结算瞬间的锁定几何；单宿主最多三段残留，装饰共享并发预算。
func impact(geo: Dictionary, detailed: bool = true) -> void:
	if geo.is_empty():
		return
	if impacts.size() >= 3:
		_release(impacts.pop_front())
	var details := detailed and detail_count < MAX_DETAILS
	if details:
		detail_count += 1
	impacts.append({"geo": geo.duplicate(true), "age": 0.0, "details": details})

## 由玩法物理时间推进消散，返回本轮是否需要重绘。
func tick(delta: float) -> bool:
	var active := not impacts.is_empty()
	for i in range(impacts.size() - 1, -1, -1):
		impacts[i].age = float(impacts[i].age) + delta
		if float(impacts[i].age) >= IMPACT_LIFE:
			_release(impacts.pop_at(i))
	return active

## 取消、死亡或退出时释放宿主持有的全部装饰预算。
func clear() -> void:
	for entry in impacts:
		_release(entry)
	impacts.clear()
## 归还一段命中特效占用的全局装饰额度。
func _release(entry: Dictionary) -> void:
	if entry.get("details", false):
		detail_count = maxi(0, detail_count - 1)

## 在地面层绘制短促命中与残纹，不触发伤害。
func draw_impacts(canvas: Node2D, skin: Dictionary) -> void:
	for entry in impacts:
		var t := float(entry.age) / IMPACT_LIFE
		var geo: Dictionary = entry.geo
		var color := Color(String(skin.get("color", "c78a65")))
		if geo.kind == "claw":
			if entry.details and visible_geometry(canvas, geo):
				var center := _local(canvas, geo.center) + Vector2(0, -16)
				var direction := Iso.from_ground(geo.dir).normalized()
				for i in range(-1, 2):
					var base := center + direction.orthogonal() * i * 6.0
					var claw := PackedVector2Array([base - direction * 19.0 + Vector2(0, -8), base, base + direction * 16.0 + Vector2(0, 9)])
					canvas.draw_polyline(claw, Color(color, (1.0 - t) * 0.18), 5.0, true)
					canvas.draw_polyline(claw, Color(color.lerp(Color.WHITE, 0.55), (1.0 - t) * 0.9), 1.5, true)
			continue
		# 命中亮芯短促，之后降为非危险暗纹，绝不延长伤害窗口。
		var flash := maxf(0.0, 1.0 - t * 5.0)
		_shape(canvas, geo, Color(color, 0.10 * (1.0 - t) + flash * 0.22), Color(color.lerp(Color.WHITE, flash), (1.0 - t) * 0.85), 2.0 + flash * 3.0)
		if entry.details and visible_geometry(canvas, geo):
			_motif(canvas, geo, skin, color, 1.0 - t, t, true)

## 按原计时进度绘制完整危险边界和主题纹样。
static func warning(canvas: Node2D, geo: Dictionary, progress: float, skin: Dictionary, detailed: bool = true) -> void:
	if geo.is_empty():
		return
	var p := clampf(progress, 0.0, 1.0)
	_shape(canvas, geo, Color(0.75, 0.10, 0.045, 0.09 + p * 0.10), EDGE, 2.0)
	if detailed and visible_geometry(canvas, geo) and _admit_warning():
		var color := Color(String(skin.get("color", "c78a65")))
		_motif(canvas, geo, skin, color, 0.45 + 0.5 * p, p, false)

## 将锁定的地面坐标转换为绘制节点局部屏幕坐标。
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

## 复用GroundFx投影绘制与判定一致的圈、环、扇和胶囊。
static func _shape(canvas: Node2D, geo: Dictionary, fill: Color, edge: Color, width: float) -> void:
	match String(geo.get("kind", "")):
		"line":
			var points := line_points(geo)
			for i in range(points.size()):
				points[i] = _local(canvas, points[i])
			if fill.a > 0.0:
				canvas.draw_colored_polygon(points, fill)
			points.append(points[0])
			canvas.draw_polyline(points, edge, width, true)
		"circle":
			var center := _local(canvas, geo.center)
			if fill.a > 0.0:
				GroundFx.fill(canvas, center, float(geo.radius), fill)
			GroundFx.outline(canvas, center, float(geo.radius), edge, width, 48)
		"fan":
			var center := _local(canvas, geo.center)
			var dir := Iso.from_ground(geo.dir)
			if fill.a > 0.0:
				GroundFx.sector(canvas, center, dir, float(geo.radius), float(geo.arc), fill, 24)
			GroundFx.sector_outline(canvas, center, dir, float(geo.radius), float(geo.arc), edge, width, 24)
		"ring":
			var center := _local(canvas, geo.center)
			if fill.a > 0.0:
				var mesh := ring_mesh(float(geo.inner), float(geo.radius))
				GroundFx._hold_mesh(canvas,mesh)
				canvas.draw_mesh(mesh, null, Transform2D(0.0, center), fill)
			GroundFx.outline(canvas, center, float(geo.radius), edge, width, 48)
			GroundFx.outline(canvas, center, float(geo.inner), edge, width, 40)

## 绘制有界主题纹样；环形装饰限制在危险环带内。
static func _motif(canvas: Node2D, geo: Dictionary, skin: Dictionary, tint: Color, alpha: float, progress: float, impact_mode: bool) -> void:
	var color := Color(tint, alpha)
	var motif := String(skin.get("motif", "crack"))
	if geo.kind == "line":
		var a: Vector2 = geo["from"]
		var b: Vector2 = geo["to"]
		var dir := (b - a).normalized()
		var side := dir.orthogonal()
		var marks := clampi(int(skin.get("marks", 8)) / 2 + 3, 5, 9)
		for i in range(marks):
			var point := a.lerp(b, (i + 0.5) / float(marks))
			var width := float(geo.half) * (0.4 if motif == "metal" else 0.65)
			var tail := point - dir * minf(20.0, a.distance_to(b) / 20.0)
			if motif in ["wave", "wind", "sand"]:
				var flow := PackedVector2Array()
				for k in range(7):
					flow.append(_local(canvas, point + dir * (k - 3) * 5.0 + side * sin(k * 0.8 + progress * 2.0) * width * 0.7))
				canvas.draw_polyline(flow, color, 1.6, true)
			elif motif == "root":
				canvas.draw_polyline(PackedVector2Array([_local(canvas, tail - side * width), _local(canvas, point + side * width * 0.3), _local(canvas, tail + side * width)]), color, 2.0, true)
			elif motif == "spore":
				GroundFx.outline(canvas, _local(canvas, point), minf(13.0, width * 0.45), color, 2.0, 12)
			else:
				canvas.draw_polyline(PackedVector2Array([_local(canvas, tail - side * width), _local(canvas, point), _local(canvas, tail + side * width)]), color, 1.6, true)
		var front := a.lerp(b, clampf(progress, 0.0, 1.0))
		canvas.draw_line(_local(canvas, front - side * float(geo.half) * 0.85), _local(canvas, front + side * float(geo.half) * 0.85), Color(tint, alpha * 0.65), 3.0, true)
		return
	var center: Vector2 = geo.center
	var radius := float(geo.radius)
	var inner := float(geo.get("inner", 0.0))
	var start := (geo.dir as Vector2).angle() - float(geo.arc) / 2.0 if geo.kind == "fan" else 0.0
	var arc := float(geo.arc) if geo.kind == "fan" else TAU
	var n := 5 if geo.kind == "fan" else clampi(int(skin.get("marks", 8)), 4, 12)
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
			if motif == "root":
				canvas.draw_line(_local(canvas, mid), _local(canvas, mid + dir.orthogonal() * (hi - lo) * 0.20), color, 1.3, true)
			elif motif == "bone":
				GroundFx.outline(canvas, _local(canvas, b), 5.0, color, 1.2, 12)
		elif motif == "eye":
			var eye := PackedVector2Array()
			var mid := a.lerp(b, 0.5)
			for k in range(17):
				var t := TAU * k / 16.0
				eye.append(_local(canvas, mid + dir * cos(t) * (hi - lo) * 0.42 + dir.orthogonal() * sin(t) * minf(14.0, (hi - lo) * 0.18)))
			canvas.draw_polyline(eye, color, 1.4, true)
			canvas.draw_line(_local(canvas, a), _local(canvas, b), Color(tint, alpha * 0.4), 1.0, true)
		elif motif in ["metal", "seal"]:
			var mid := a.lerp(b, 0.7)
			var side := dir.orthogonal() * minf(12.0, (hi - lo) * 0.12)
			var glyph := [a, mid - side, b, mid + side, a] if motif == "metal" else [a - side, b - side, b + side, mid + side, mid]
			var glyph_points := PackedVector2Array()
			for point in glyph:
				glyph_points.append(_local(canvas, point))
			canvas.draw_polyline(glyph_points, color, 1.3, true)
		else:
			var pts := PackedVector2Array()
			for k in range(7):
				var d := dir.rotated(0.10 * sin(k * 0.9 + progress * 2.0))
				pts.append(_local(canvas, center + d * lerpf(lo, hi, k / 6.0)))
			canvas.draw_polyline(pts, color, 1.4, true)
			if motif == "spore":
				GroundFx.outline(canvas, _local(canvas, a.lerp(b, 0.75)), 7.0, color, 1.8, 12)
		if impact_mode:
			var height := 22.0 if motif in ["metal", "seal", "eye"] else 34.0
			if inner > 0.0:
				height = minf(height, (radius - inner) * Iso.GROUND_SQUASH * 0.45)
			var lift := sin(progress * PI) * height
			var base := _local(canvas, b)
			canvas.draw_line(base, base + Vector2(sin(angle * 3.0) * progress * 12.0, -lift), Color(tint.lerp(Color.WHITE, 0.25), alpha * 0.8), 2.0, true)
	# 进度光环始终位于危险区域内，不涂抹环击的中心安全区。
	var ring_r := lerpf(maxf(inner + (radius - inner) * 0.15, radius * 0.35), inner + (radius - inner) * 0.92, progress)
	if geo.kind == "fan":
		GroundFx.sector_outline(canvas, _local(canvas, center), Iso.from_ground(geo.dir), ring_r, arc, Color(tint, alpha * 0.6), 1.0, 24)
	else:
		GroundFx.outline(canvas, _local(canvas, center), ring_r, Color(tint, alpha * 0.65), 1.4, 40)

## 加载期校验主题参数及Boss引用，错误交由统一数据校验报告。
static func validate_config(config: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not config is Dictionary or not config.get("styles") is Dictionary or not config.get("bosses") is Dictionary:
		return ["[bossVisuals] 需要styles和bosses对象"]
	if not config.styles.has("corruption"):
		errors.append("[bossVisuals] 缺少默认corruption样式")
	for key in config.styles:
		var style: Variant = config.styles[key]
		if not style is Dictionary or not style.get("color") is String or not Color.html_is_valid(style.color) or not ["crack", "metal", "root", "bone", "seal", "eye", "wave", "sand", "spore", "wind"].has(style.get("motif")):
			errors.append("[bossVisuals] 非法样式：" + String(key))
			continue
		var marks: Variant = style.get("marks", 8)
		if not (marks is int or marks is float) or float(marks) != floor(float(marks)) or float(marks) < 4.0 or float(marks) > 12.0:
			errors.append("[bossVisuals] marks应为4—12整数")
	for id in config.bosses:
		var tpl: Variant = DataLoader.get_entry("monsters", String(id))
		if not tpl is Dictionary or tpl.get("kind") != "boss" or not config.styles.has(config.bosses[id]):
			errors.append("[bossVisuals] Boss或样式引用非法：" + String(id))
	return errors

## 同帧最多8份预警纹样；完整危险边界与渐强填色不受限额影响。
static func _admit_warning() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _warning_frame:
		_warning_frame = frame
		_warning_details = 0
	if _warning_details >= MAX_WARNING_DETAILS:
		return false
	_warning_details += 1
	return true

## 复用现有四边形合批器；48片环带一次绘制，不填充安全中心。
static func ring_mesh(inner: float, outer: float) -> ArrayMesh:
	var key := Vector2(inner, outer)
	if _rings.has(key):
		return _rings[key]
	if _rings.size() >= 32:
		_rings.clear()
	var batch := FlatTileMesh.new(48)
	for i in range(48):
		var a := Vector2.from_angle(TAU * i / 48.0)
		var b := Vector2.from_angle(TAU * (i + 1) / 48.0)
		batch.add_quad(PackedVector2Array([Iso.from_ground(a * inner), Iso.from_ground(b * inner), Iso.from_ground(b * outer), Iso.from_ground(a * outer)]))
	var mesh := batch.build()
	_rings[key] = mesh
	return mesh

## 保守剔除屏外装饰；只检查视口包围盒，不参与命中或隐藏主轮廓。
static func visible_geometry(canvas: Node2D, geo: Dictionary) -> bool:
	var center: Vector2 = geo.get("center", Vector2.ZERO)
	var radius := float(geo.get("radius", 40.0))
	if geo.kind == "line":
		center = (geo["from"] + geo["to"]) * 0.5
		radius = (geo["from"] as Vector2).distance_to(geo["to"]) * 0.5 + float(geo.half)
	var transform := canvas.get_viewport_transform()
	var point := transform * Iso.from_ground(center)
	var scale := maxf(transform.x.length(), transform.y.length())
	var extent := Vector2(radius, radius * Iso.GROUND_SQUASH) * scale + Vector2(48, 48)
	return Rect2(point - extent, extent * 2.0).intersects(canvas.get_viewport_rect())
