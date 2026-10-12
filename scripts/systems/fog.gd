class_name Fog
extends RefCounted
## M3-3：探索按 4×4 格区块持久化；圈半径按工程文档 13 的已确认方案为 8 格。
## GameState 只持有集合，序列化不含节点；大小来自 MapService，边缘不足四格也合法。
const BLOCK_SIZE := 4
const REVEAL_RADIUS := 8

static func block_grid(map_id: String) -> Vector2i:
	var dims := MapService.grid_size(map_id)
	return Vector2i(ceili(float(dims.x) / BLOCK_SIZE), ceili(float(dims.y) / BLOCK_SIZE))

static func contains(map_id: String, cell: Vector2i) -> bool:
	var dims := MapService.grid_size(map_id)
	return cell.x >= 0 and cell.y >= 0 and cell.x < dims.x and cell.y < dims.y

static func block_id(map_id: String, cell: Vector2i) -> String:
	return str((cell.y / BLOCK_SIZE) * block_grid(map_id).x + cell.x / BLOCK_SIZE)

static func is_explored(map_id: String, cell: Vector2i) -> bool:
	return contains(map_id, cell) and GameState.explored_maps.get(map_id, {}).has(block_id(map_id, cell))

static func reveal(map_id: String, cell: Vector2i) -> bool:
	if not contains(map_id, cell):
		return false
	var dims := MapService.grid_size(map_id)
	var blocks: Dictionary = GameState.explored_maps.get(map_id, {})
	var changed := false
	for y in range(maxi(0, cell.y - REVEAL_RADIUS), mini(dims.y, cell.y + REVEAL_RADIUS + 1)):
		for x in range(maxi(0, cell.x - REVEAL_RADIUS), mini(dims.x, cell.x + REVEAL_RADIUS + 1)):
			if Vector2i(x, y).distance_squared_to(cell) > REVEAL_RADIUS * REVEAL_RADIUS:
				continue
			var key := block_id(map_id, Vector2i(x, y))
			if not blocks.has(key):
				blocks[key] = true
				changed = true
	GameState.explored_maps[map_id] = blocks
	if changed:
		EventBus.fog_changed.emit(map_id)
	return changed

static func encode() -> Dictionary:
	var out := {}
	for map_id in GameState.explored_maps:
		var ids: Array[int] = []
		for key in GameState.explored_maps[map_id]:
			ids.append(int(key))
		ids.sort()
		out[map_id] = ids
	return out

## 旧档无字段视为空；未知地图、重复、非整数、越界区块不会揭示地图。
static func normalize(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for map_id in raw:
		if not map_id is String or not MapService.exists(map_id) or not raw[map_id] is Array:
			continue
		var dims := block_grid(map_id)
		var limit := dims.x * dims.y
		var blocks := {}
		for id: Variant in raw[map_id]:
			if not (id is int or id is float):
				continue
			var value := float(id)
			if is_finite(value) and value == floor(value) and value >= 0 and value < limit:
				blocks[str(int(value))] = true
		out[map_id] = blocks
	return out
