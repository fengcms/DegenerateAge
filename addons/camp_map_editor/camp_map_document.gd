@tool
extends RefCounted
## 幸存者营地可视化编辑数据模型。编辑地面笔刷排布、整体实体位置、
## 碰撞多边形和道路控制点；草稿与正式地图分离，应用前由 Python 校验。

const SOURCE_PATH := "res://data/map_art/camp_whitebox_v2.json"
const DRAFT_PATH := "res://data/map_art/camp_editor_draft.json"
const MANIFEST_PATH := "res://assets/maps/camp_style_full_b_v2/manifest.json"
const PALETTE_PATH := "res://data/map_art/camp_ground_palette.json"

var layout: Dictionary = {}
var manifest: Dictionary = {}
var palette: Dictionary = {}
var base_hash := ""
var dirty := false
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var _pending_snapshot: Dictionary = {}

## 读取正式营地或与当前正式源匹配的草稿；返回可展示的中文错误，空串表示成功。
func open() -> String:
	dirty = false
	var source := FileAccess.get_file_as_string(SOURCE_PATH)
	if source.is_empty():
		return "找不到正式营地布局。"
	base_hash = source.sha256_text()
	var parsed: Variant = JSON.parse_string(source)
	if not parsed is Dictionary:
		return "正式营地布局不是有效 JSON。"
	layout = parsed
	var draft_file := FileAccess.open(DRAFT_PATH, FileAccess.READ)
	if draft_file != null:
		var draft: Variant = JSON.parse_string(draft_file.get_as_text())
		if draft is Dictionary and String(draft.get("base_hash", "")) == base_hash \
				and draft.get("layout") is Dictionary:
			layout = draft["layout"]
			dirty = true
	var art_file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if art_file == null:
		return "找不到营地美术清单。"
	var art: Variant = JSON.parse_string(art_file.get_as_text())
	if not art is Dictionary:
		return "营地美术清单不是有效 JSON。"
	manifest = art
	var palette_file := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if palette_file == null:
		return "找不到营地地面笔刷清单。"
	var palette_data: Variant = JSON.parse_string(palette_file.get_as_text())
	if not palette_data is Dictionary:
		return "营地地面笔刷清单不是有效 JSON。"
	palette = palette_data
	_ensure_fence_art_metadata()
	_sync_manifest_positions()
	undo_stack.clear()
	redo_stack.clear()
	return validate()

## 返回布局尺寸、ID、矩形和实体引用是否完整；不会修改任何文件。
func validate() -> String:
	var canvas: Array = layout.get("reference_canvas", [])
	if layout.get("id") != "camp_whitebox_v2" or canvas.size() != 2 \
			or int(canvas[0]) != 1672 or int(canvas[1]) != 941:
		return "画布或布局版本与当前营地不一致。"
	var ids: Dictionary = {}
	for item: Dictionary in layout.get("entities", []):
		var id := String(item.get("id", ""))
		if ids.has(id) or not item.get("art_rect") is Array or not item.get("footprint") is Array:
			return "实体数据不完整或 ID 重复：%s" % id
		ids[id] = true
		var rect: Array = item["art_rect"]
		if rect.size() != 4 or rect[0] < 0 or rect[1] < 0 \
				or rect[0] + rect[2] > 1672 or rect[1] + rect[3] > 941:
			return "实体超出画布：%s" % id
		if not _valid_polygon(item["footprint"]):
			return "实体碰撞轮廓无效、交叉或超出画布：%s" % id
	for fence: Dictionary in layout.get("fences", []):
		var id := String(fence.get("id", ""))
		if ids.has(id) or not fence.get("polygon") is Array:
			return "围栏数据不完整或 ID 重复：%s" % id
		ids[id] = true
		if not _valid_polygon(fence["polygon"]):
			return "围栏碰撞轮廓无效、交叉或超出画布：%s" % id
		var fence_rect := art_rect(id)
		if fence_rect.position.x < 0 or fence_rect.position.y < 0 \
				or fence_rect.end.x > 1672 or fence_rect.end.y > 941:
			return "围栏美术超出画布：%s" % id
	if ids.size() != 11:
		return "本版编辑器应有 7 个整体实体和 4 段围栏。"
	var paths: Array = [layout["main_road"]] + layout["branches"]
	for points: Array in paths:
		for index in range(points.size()):
			var point: Array = points[index]
			if point.size() != 2 or point[0] < 0 or point[0] > 1672 \
					or point[1] < 0 or point[1] > 941:
				return "道路控制点超出画布。"
			if index > 0 and point == points[index - 1]:
				return "道路出现零长线段。"
	var known_tiles: Dictionary = {}
	for tile: Dictionary in palette.get("tiles", []):
		known_tiles[String(tile.get("id", ""))] = true
	var used_cells: Dictionary = {}
	for patch: Dictionary in layout.get("ground_patches", []):
		var cell: Array = patch.get("cell", [])
		var tile_id := String(patch.get("tile", ""))
		if cell.size() != 2 or not known_tiles.has(tile_id) \
				or int(cell[0]) != cell[0] or int(cell[1]) != cell[1] \
				or cell[0] < 0 or cell[0] >= 14 or cell[1] < 0 or cell[1] >= 8:
			return "地面笔刷格或类型无效。"
		var key := "%s,%s" % [cell[0], cell[1]]
		if used_cells.has(key):
			return "地面笔刷格重复：%s" % key
		used_cells[key] = true
	return ""

## 检查画布像素多边形是否可供碰撞和通行共用：至少三点、无自交且可三角化。
func _valid_polygon(raw: Array) -> bool:
	if raw.size() < 3 or raw.size() > 32:
		return false
	var points := PackedVector2Array()
	var double_area := 0.0
	for index in range(raw.size()):
		var point: Array = raw[index]
		if point.size() != 2 or point[0] < 0 or point[0] > 1672 or point[1] < 0 or point[1] > 941:
			return false
		var next_point: Array = raw[(index + 1) % raw.size()]
		double_area += float(point[0]) * float(next_point[1]) - float(next_point[0]) * float(point[1])
		points.append(Vector2(point[0], point[1]))
	return absf(double_area) >= 16.0 and not Geometry2D.triangulate_polygon(points).is_empty()

## 取得指定实体或围栏在画布中的运行美术矩形，供命中测试和标注。
func art_rect(object_id: String) -> Rect2:
	for item: Dictionary in manifest.get("objects", []):
		if String(item.get("id", "")) == object_id:
			var rect: Array = item["rect"]
			return Rect2(rect[0], rect[1], rect[2], rect[3])
	return Rect2()

## 返回画布中的实体脚底多边形；围栏沿用单个整体 polygon。
func footprint(object_id: String) -> PackedVector2Array:
	for group in ["entities", "fences"]:
		for item: Dictionary in layout.get(group, []):
			if String(item.get("id", "")) != object_id:
				continue
			var result := PackedVector2Array()
			for point: Array in item["footprint" if group == "entities" else "polygon"]:
				result.append(Vector2(point[0], point[1]))
			return result
	return PackedVector2Array()

## 返回指定对象的可变碰撞数组；实体用 footprint，围栏用 polygon。
func _collision_points(object_id: String) -> Array:
	for group in ["entities", "fences"]:
		for item: Dictionary in layout.get(group, []):
			if String(item.get("id", "")) == object_id:
				return item["footprint" if group == "entities" else "polygon"]
	return []

## 将一个碰撞顶点移到参考画布内的整数像素；不移动任何美术图层。
func move_collision_vertex(object_id: String, vertex_index: int, position: Vector2i) -> void:
	var points := _collision_points(object_id)
	if vertex_index < 0 or vertex_index >= points.size():
		return
	points[vertex_index] = [clampi(position.x, 0, 1672), clampi(position.y, 0, 941)]

## 在指定边后插入碰撞顶点；新增点与原多边形仍作为单个整体碰撞。
func insert_collision_vertex(object_id: String, edge_index: int, position: Vector2i) -> int:
	var points := _collision_points(object_id)
	if edge_index < 0 or edge_index >= points.size() or points.size() >= 32:
		return -1
	points.insert(edge_index + 1, [clampi(position.x, 0, 1672), clampi(position.y, 0, 941)])
	return edge_index + 1

## 删除指定碰撞顶点，最低保留三点；返回是否确实删除。
func remove_collision_vertex(object_id: String, vertex_index: int) -> bool:
	var points := _collision_points(object_id)
	if points.size() <= 3 or vertex_index < 0 or vertex_index >= points.size():
		return false
	points.remove_at(vertex_index)
	return true

## 查找画布上一个 128×128 地面格当前的笔刷 ID；空串表示原始地面。
func ground_patch_at(cell: Vector2i) -> String:
	for patch: Dictionary in layout.get("ground_patches", []):
		if patch.get("cell", []) == [cell.x, cell.y]:
			return String(patch.get("tile", ""))
	return ""

## 在地面格放置一个笔刷；空 ID 会擦除覆盖层并露出原始地纹。
func set_ground_patch(cell: Vector2i, tile_id: String) -> void:
	if cell.x < 0 or cell.x >= 14 or cell.y < 0 or cell.y >= 8:
		return
	var patches: Array = layout.get("ground_patches", [])
	for index in range(patches.size()):
		if patches[index].get("cell", []) == [cell.x, cell.y]:
			if tile_id.is_empty():
				patches.remove_at(index)
			else:
				patches[index]["tile"] = tile_id
			layout["ground_patches"] = patches
			return
	if not tile_id.is_empty():
		patches.append({"cell": [cell.x, cell.y], "tile": tile_id})
	layout["ground_patches"] = patches

## 鼠标拖动开始时记录完整快照；同一次拖动只占一个撤销步骤。
func begin_change() -> void:
	_pending_snapshot = layout.duplicate(true)

## 提交一次已发生的拖动，清空重做历史；无位移时不增加步骤。
func finish_change() -> void:
	if not _pending_snapshot.is_empty() and _pending_snapshot != layout:
		undo_stack.append(_pending_snapshot)
		redo_stack.clear()
		dirty = true
	_pending_snapshot = {}

## 按画布像素平移一个既有整体对象，同时平移美术、视觉轮廓和单体碰撞。
func move_object(object_id: String, delta: Vector2i) -> void:
	if delta == Vector2i.ZERO:
		return
	for group in ["entities", "fences"]:
		for item: Dictionary in layout.get(group, []):
			if String(item.get("id", "")) != object_id:
				continue
			for key in ["footprint", "visual", "polygon"]:
				if item.has(key):
					for point: Array in item[key]:
						point[0] += delta.x
						point[1] += delta.y
			if item.has("art_rect"):
				item["art_rect"][0] += delta.x
				item["art_rect"][1] += delta.y
			if item.has("art_foot_y"):
				item["art_foot_y"] += delta.y
			if item.has("visual_foot_y"):
				item["visual_foot_y"] += delta.y
			_sync_manifest_positions()
			return

## 移动主路或支路的一个控制点，单位为参考画布像素；道路预览随之重绘。
func move_road_point(branch_index: int, point_index: int, position: Vector2i) -> void:
	var points: Array = layout["main_road"] if branch_index < 0 else layout["branches"][branch_index]
	points[point_index] = [clampi(position.x, 0, 1672), clampi(position.y, 0, 941)]

## 撤销上一次拖动并同步美术预览；没有历史时返回 false。
func undo() -> bool:
	if undo_stack.is_empty():
		return false
	redo_stack.append(layout.duplicate(true))
	layout = undo_stack.pop_back()
	_sync_manifest_positions()
	dirty = true
	return true

## 重做上一次已撤销的拖动并同步美术预览；没有历史时返回 false。
func redo() -> bool:
	if redo_stack.is_empty():
		return false
	undo_stack.append(layout.duplicate(true))
	layout = redo_stack.pop_back()
	_sync_manifest_positions()
	dirty = true
	return true

## 将草稿写入独立 JSON，保留正式源哈希；游戏在点击应用前不会读取草稿。
func save_draft() -> String:
	var issue := validate()
	if not issue.is_empty():
		return issue
	var file := FileAccess.open(DRAFT_PATH, FileAccess.WRITE)
	if file == null:
		return "草稿文件无法写入。"
	file.store_string(JSON.stringify({"base_hash": base_hash, "layout": layout}, "  ") + "\n")
	dirty = false
	return ""

## 旧围栏源只记录碰撞轮廓：用当前运行美术补齐独立矩形和脚底深度。
## 补齐后可单独编辑碰撞顶点，而不会意外拉伸或换位围栏贴图。
func _ensure_fence_art_metadata() -> void:
	for fence: Dictionary in layout.get("fences", []):
		if fence.has("art_rect") and fence.has("art_foot_y"):
			continue
		for art: Dictionary in manifest.get("objects", []):
			if String(art.get("id", "")) == String(fence.get("id", "")):
				fence["art_rect"] = art["rect"].duplicate()
				fence["art_foot_y"] = art["foot_y"]
				break

## 从唯一布局重算预览矩形；围栏美术坐标独立于可编辑的碰撞轮廓。
func _sync_manifest_positions() -> void:
	for art: Dictionary in manifest.get("objects", []):
		var id := String(art.get("id", ""))
		for item: Dictionary in layout.get("entities", []):
			if String(item.get("id", "")) == id:
				art["rect"] = item["art_rect"].duplicate()
				art["foot_y"] = item["art_foot_y"]
				break
		for fence: Dictionary in layout.get("fences", []):
			if String(fence.get("id", "")) != id:
				continue
			if fence.has("art_rect") and fence.has("art_foot_y"):
				art["rect"] = fence["art_rect"].duplicate()
				art["foot_y"] = fence["art_foot_y"]
				break
			var polygon: Array = fence["polygon"]
			var min_x := 1672
			var min_y := 941
			var max_x := 0
			var max_y := 0
			for point: Array in polygon:
				min_x = mini(min_x, int(point[0]))
				min_y = mini(min_y, int(point[1]))
				max_x = maxi(max_x, int(point[0]))
				max_y = maxi(max_y, int(point[1]))
			if max_y - min_y > max_x - min_x:
				art["rect"] = [min_x - 11, min_y - 20, max_x - min_x + 22, max_y - min_y + 27]
			else:
				art["rect"] = [min_x, min_y - 25, max_x - min_x, max_y - min_y + 36]
			art["foot_y"] = max_y
			break
