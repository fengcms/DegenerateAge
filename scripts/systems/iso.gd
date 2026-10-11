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
