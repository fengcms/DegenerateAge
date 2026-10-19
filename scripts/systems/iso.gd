class_name Iso
extends RefCounted
## 等距（isometric）坐标工具 —— 依据产品文档 7.1（64×32 瓦片）。
##
## 坐标约定（与文档公式一致）：
##   screenX = (col − row) × tileW / 2
##   screenY = −(col + row) × tileH / 2
## 即 row 增大向左、col+row 增大向上；地图整体位于原点上方（−Y 方向）。
## 若将来想改成「Y 向下生长」的观感，只需改本文件公式，其他代码不受影响。

const TILE_W := 64.0
const TILE_H := 32.0
const HALF_W := TILE_W * 0.5
const HALF_H := TILE_H * 0.5

const DIR_N := Vector2i(0, -1)
const DIR_E := Vector2i(1, 0)
const DIR_S := Vector2i(0, 1)
const DIR_W := Vector2i(-1, 0)

## 网格坐标（整数格中心）-> 世界像素
static func grid_to_world(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x - cell.y) * HALF_W, -float(cell.x + cell.y) * HALF_H)

## 网格坐标（可含小数，用于瓦片顶点 / 网格线）-> 世界像素
static func grid_pt(col: float, row: float) -> Vector2:
	return Vector2((col - row) * HALF_W, -(col + row) * HALF_H)

## 世界像素 -> 网格浮点坐标
static func world_to_grid(pos: Vector2) -> Vector2:
	var a := pos.x / HALF_W      # = col − row
	var b := -pos.y / HALF_H     # = col + row
	return Vector2((a + b) * 0.5, (b - a) * 0.5)

## 瓦片某个方向的顶点（N / E / S / W）
static func tile_corner(cell: Vector2i, dir: Vector2i) -> Vector2:
	return grid_to_world(cell) + Vector2(float(dir.x) * HALF_W, float(dir.y) * HALF_H)

## 瓦片菱形的四个顶点（N, E, S, W）
static func tile_points(cell: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		tile_corner(cell, DIR_N),
		tile_corner(cell, DIR_E),
		tile_corner(cell, DIR_S),
		tile_corner(cell, DIR_W),
	])

## 深度排序值（col+row 越大越靠前，用于脚底 Y 排序）
static func depth(cell: Vector2i) -> int:
	return cell.x + cell.y

# ---- 地面几何（等距平面）--------------------------------------------------
# 地面是斜 45° 俯视：地面上的 1 单位长度投影到屏幕，横向占 1、纵向只占 GROUND_SQUASH。
# 因此「地面正圆」在屏幕上必须是 **2:1 的椭圆**（长轴横向）。
# 这里提供几何唯一来源；绘制统一走 `GroundFx`，禁止在 `_draw()` 里裸画 `draw_circle`
# 表示地面圆（那会画出一张竖起来的圆片）。

## 地面纵向压缩比 = HALF_H / HALF_W = 0.5（唯一来源，禁止再写字面量 0.45 / 0.5）。
const GROUND_SQUASH := HALF_H / HALF_W

## 屏幕（世界）坐标 -> 地面坐标：纵向放大 `1 / GROUND_SQUASH`（= 2）倍，
## 使「地面正圆」在地面坐标里恢复成正圆，可直接用欧氏距离 / 角度比较。
static func to_ground(p: Vector2) -> Vector2:
	return Vector2(p.x, p.y / GROUND_SQUASH)

## 地面坐标 -> 屏幕（世界）坐标：纵向压回 `GROUND_SQUASH`。
static func from_ground(p: Vector2) -> Vector2:
	return Vector2(p.x, p.y * GROUND_SQUASH)

## 屏幕方向 -> 地面方向（单位向量）。只改变纵向分量比例，屏幕上的指向不变。
## 用于把「设计者给的屏幕朝向」翻成地面空间里的扇形中线。
static func ground_dir(dir: Vector2) -> Vector2:
	if dir.length() < 0.0001:
		return Vector2.RIGHT
	return to_ground(dir).normalized()

## 地面两点之间的地面真实距离（屏幕两点 → 地面欧氏距离）。
static func ground_distance(a: Vector2, b: Vector2) -> float:
	return to_ground(a).distance_to(to_ground(b))

## 地面正圆 -> 屏幕椭圆点集（闭合，**首点不在末尾重复**）。
## `radius` 是**地面半径**，也就是椭圆在屏幕上的横向半径；纵向自动为 `radius * 0.5`。
static func ground_ellipse(center: Vector2, radius: float, segments: int = 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(8, segments)
	for i in range(n):
		var a := TAU * float(i) / float(n)
		out.append(center + from_ground(Vector2(cos(a), sin(a)) * radius))
	return out

## 地面圆弧 -> 屏幕点集（**未闭合**，用于扇形 / 环带描边）。
## 角度按地面坐标定义（0 = +X，逆时针为正，与 Godot 屏幕角度同向）。
static func ground_arc(center: Vector2, radius: float, from_angle: float, to_angle: float,
		segments: int = 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(2, segments)
	for i in range(n + 1):
		var a := lerpf(from_angle, to_angle, float(i) / float(n))
		out.append(center + from_ground(Vector2(cos(a), sin(a)) * radius))
	return out

## 点（屏幕坐标）是否落在地面圆内。与 `ground_ellipse` 同源：横向全 `radius`、纵向半 `radius`。
static func ground_contains(center: Vector2, radius: float, p: Vector2) -> bool:
	return ground_distance(center, p) <= radius

## 点（屏幕坐标）是否落在地面环带内（`inner` 不含、`outer` 含）。
static func ground_ring_contains(center: Vector2, inner: float, outer: float, p: Vector2) -> bool:
	var d := ground_distance(center, p)
	return d >= inner and d <= outer

## 地面正方形（2:1 菱形）四顶点（屏幕坐标，顺序：北 / 东 / 南 / 西）。
## `half_width` 是方块的**地面半边长**，投影后横向半宽 = `half_width`、纵向半高 = `half_width * 0.5`。
static func ground_diamond(center: Vector2, half_width: float) -> PackedVector2Array:
	var dy := half_width * GROUND_SQUASH
	return PackedVector2Array([
		center + Vector2(0.0, -dy),
		center + Vector2(half_width, 0.0),
		center + Vector2(0.0, dy),
		center + Vector2(-half_width, 0.0),
	])
