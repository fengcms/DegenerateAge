class_name GroundFx
extends RefCounted
## 地面（等距平面）绘制门面 —— **唯一**允许在 `_draw()` 里画地面圆 / 扇 / 环的入口。
##
## 为什么需要这一层：`draw_circle` / `draw_arc` 用的是屏幕（画布）坐标系，直接调用等于
## 画一张**正对镜头的圆片**；而本作地面是 64×32 的等距投影，地面正圆在屏幕上必须是
## **2:1 的椭圆**（长轴横向）。过去各文件各写各的，出现了 0.45 / 0.5 / 裸画三种口径。
##
## 约定：
##   - 所有 `radius` / `inner` / `outer` / `half_width` 参数都是**地面半径**，
##     也就是椭圆在屏幕上的**横向**半径；纵向由 `Iso.GROUND_SQUASH` 自动压到一半。
##   - 所有 `center` / `dir` 参数都是**屏幕（世界）坐标**，与宿主 `_draw()` 本地空间同构
##     （宿主无旋转 / 非等比缩放时可直接传本地坐标）。
##   - 填充用 `draw_set_transform` 压扁（一次调用，代价最低）；
##     描边用折线（`draw_arc` 的 width 会被压成横向 2px、纵向 1px，大圈肉眼可辨）。

## 小圈 / 大圈的折线段数：1px 描边下均无可见折角。
const SEG_SMALL := 32
const SEG_LARGE := 48
const SEG_THRESHOLD := 120.0

## 按半径挑折线段数。
static func segments_for(radius: float) -> int:
	return SEG_LARGE if radius > SEG_THRESHOLD else SEG_SMALL

## 地面圆填充。
static func fill(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	canvas.draw_set_transform(center, 0.0, Vector2(1.0, Iso.GROUND_SQUASH))
	canvas.draw_circle(Vector2.ZERO, radius, color)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 地面圆描边（线宽各向同性）。
static func outline(canvas: CanvasItem, center: Vector2, radius: float, color: Color,
		width: float = 2.0, segments: int = 0) -> void:
	if radius <= 0.0:
		return
	var n := segments if segments > 0 else segments_for(radius)
	var pts := Iso.ground_ellipse(center, radius, n)
	pts.append(pts[0])
	canvas.draw_polyline(pts, color, width, true)

## 地面环带填充：拆成 `segments` 个凸四边形逐片填充。
## **不要**写成「外圈正向 + 内圈逆向」的单个多边形 —— 那是自交多边形，
## Godot 的三角化结果不保证正确，容易出破洞。
static func band(canvas: CanvasItem, center: Vector2, inner: float, outer: float,
		color: Color, segments: int = 0) -> void:
	var lo := maxf(0.0, minf(inner, outer))
	var hi := maxf(inner, outer)
	if hi <= lo:
		return
	var n := segments if segments > 0 else segments_for(hi)
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		canvas.draw_colored_polygon(PackedVector2Array([
			center + Iso.from_ground(d0 * lo),
			center + Iso.from_ground(d1 * lo),
			center + Iso.from_ground(d1 * hi),
			center + Iso.from_ground(d0 * hi),
		]), color)

## 地面扇形填充（`dir` 为屏幕朝向，按地面空间展开 `arc_rad` 张角）。
static func sector(canvas: CanvasItem, center: Vector2, dir: Vector2, radius: float,
		arc_rad: float, color: Color, segments: int = 20) -> void:
	var pts := _sector_points(center, dir, radius, arc_rad, segments)
	if pts.is_empty():
		return
	canvas.draw_colored_polygon(pts, color)

## 地面扇形描边（两条半径边 + 外弧）。
static func sector_outline(canvas: CanvasItem, center: Vector2, dir: Vector2, radius: float,
		arc_rad: float, color: Color, width: float = 2.0, segments: int = 20) -> void:
	var pts := _sector_points(center, dir, radius, arc_rad, segments)
	if pts.is_empty():
		return
	pts.append(pts[0])
	canvas.draw_polyline(pts, color, width, true)

## 地面矩形带填充（`from` / `to` 为屏幕坐标，`half_width` 为地面半宽）。
## 用于 `line` 预警：四点在地面空间构造再投影，屏幕上得到平行四边形（不是矩形）。
static func band_quad(canvas: CanvasItem, from: Vector2, to: Vector2, half_width: float,
		color: Color) -> void:
	if half_width <= 0.0:
		return
	var f := Iso.to_ground(from)
	var t := Iso.to_ground(to)
	var delta := t - f
	if delta.length() < 0.0001:
		return
	var side := delta.normalized().orthogonal() * half_width
	canvas.draw_colored_polygon(PackedVector2Array([
		Iso.from_ground(f + side), Iso.from_ground(t + side),
		Iso.from_ground(t - side), Iso.from_ground(f - side),
	]), color)

## 扇形点集：`[圆心, 弧点 0 … 弧点 n]`（屏幕坐标）。半径或张角非法时返回空。
static func _sector_points(center: Vector2, dir: Vector2, radius: float, arc_rad: float,
		segments: int) -> PackedVector2Array:
	if radius <= 0.0 or arc_rad <= 0.0:
		return PackedVector2Array()
	var c := Iso.to_ground(center)
	var d := Iso.ground_dir(dir)
	var half := arc_rad * 0.5
	var n := maxi(2, segments)
	var pts := PackedVector2Array([center])
	for i in range(n + 1):
		var a := -half + arc_rad * float(i) / float(n)
		pts.append(Iso.from_ground(c + d.rotated(a) * radius))
	return pts
