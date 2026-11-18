class_name SampleRoadRules
extends RefCounted
## 模块化样板的八邻接道路规则；仅构建新样板，不影响旧地图选砖。
const NEIGHBORS := [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1), Vector2i(-1,-1)]

## 仅当相邻两正交方向存在时保留对角连接，将256种输入规范化为47种。
static func normalize(bits: int) -> int:
	for corner in range(4):
		var edges := (1 << corner) | (1 << ((corner + 1) % 4))
		if bits & edges != edges:
			bits &= ~(1 << (corner + 4))
	return bits

## 按网格邻接读取道路掩码，边界外视为非道路。
static func at(rows: Array, cell: Vector2i) -> int:
	var bits := 0
	for i in range(8):
		var p: Vector2i = cell + NEIGHBORS[i]
		if p.x >= 0 and p.y >= 0 and p.y < rows.size() and p.x < rows[p.y].length() and rows[p.y][p.x] == "1":
			bits |= 1 << i
	return normalize(bits)

## 返回全部规范化形状，按数字排序保证图集索引稳定。
static func shapes() -> Array:
	var result: Array = []
	for bits in range(256):
		var value := normalize(bits)
		if not result.has(value):
			result.append(value)
	result.sort()
	return result

## 在局部方格坐标内构建连接覆盖；道路使用窄边，草土使用较宽渐变，内角半径同步保持共边一致。
static func coverage(bits: int, u: float, v: float, edge_inner: float = 0.25, edge_outer: float = 0.38) -> float:
	var limits := [-v, u, v, -u]
	var alpha := 1.0
	for i in range(4):
		if bits & (1 << i) == 0:
			alpha = minf(alpha, 1.0 - smoothstep(edge_inner, edge_outer, limits[i]))
	var corners := [Vector2(1,-1), Vector2(1,1), Vector2(-1,1), Vector2(-1,-1)]
	for i in range(4):
		var edges := (1 << i) | (1 << ((i + 1) % 4))
		if bits & edges == edges and bits & (1 << (i+4)) == 0:
			var distance := Vector2(u,v).distance_to(corners[i] * 0.5)
			alpha = minf(alpha, smoothstep(0.5-edge_outer, 0.5-edge_inner, distance))
	return alpha
