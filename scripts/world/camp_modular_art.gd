class_name CampModularArt
extends Node2D
## 正式营地与试炼野外模块地面：三层地形和一层低密度路肩贴花在地图加载时一次构建。
## 通行、碰撞、服务点仍归IsoGround的正式布局管理；本模块只负责视觉，不写布局或存档。
const TERRAIN := "res://assets/environment/camp_modular_v1/terrain_atlas.png"
const GRASS := "res://assets/environment/camp_modular_v1/grass_atlas.png"
const DECALS := "res://assets/environment/camp_modular_v1/decals_atlas.png"
const DECAL_SECTORS := Vector2i(8, 6)
const DECAL_SIZE := Vector2(96, 48)
const RULES := preload("res://scripts/world/modular_road_rules.gd")
var tile_counts: Array[int] = []

## 从离线道路掩码生成三张合批网格；裁掉矩形地图外的四边形并同步裁UV，避免边缘漏光。
func setup(definition: Dictionary, bounds: Rect2) -> void:
	# 只在进入使用模块的地图时加载，避免其他地图仅引用IsoGround就驻留这两张纹理。
	var terrain := load(TERRAIN) as Texture2D
	var grass_texture := load(GRASS) as Texture2D
	assert(terrain != null and grass_texture != null)
	var rows: Array = definition.roads
	var grass: Array = definition.grass
	var shapes := RULES.shapes()
	for layer in range(3):
		var builder := FlatTileMesh.new(rows.size()*String(rows[0]).length(),true)
		var count := 0
		for y in range(rows.size()):
			for x in range(String(rows[y]).length()):
				var active: Array = grass if layer==1 else rows
				if layer>0 and String(active[y])[x]!="1":
					continue
				var cell := Vector2i(x,y)
				var full := Rect2(Iso.grid_to_world(cell)-Vector2(32,16),Vector2(64,32))
				if not full.intersects(bounds):
					continue
				var rect := full.intersection(bounds)
				var slot := shapes.find(RULES.at(active,cell))+1 if layer>0 else 0
				var variant := posmod(x,4)+posmod(y,4)*4
				var uv_min := Vector2(float(variant)/16.0,float(slot)/48.0)
				var uv_size := Vector2(1.0/16.0,1.0/48.0)
				var a := uv_min+(rect.position-full.position)/full.size*uv_size
				var b := uv_min+(rect.end-full.position)/full.size*uv_size
				builder.add_quad(PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]),PackedVector2Array([a,Vector2(b.x,a.y),b,Vector2(a.x,b.y)]))
				count += 1
		var mesh := MeshInstance2D.new()
		mesh.name = ["Soil","Grass","Road"][layer]
		mesh.mesh = builder.build()
		mesh.texture = grass_texture if layer==1 else terrain
		mesh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mesh.z_as_relative = false
		mesh.z_index = -4000+layer
		add_child(mesh)
		tile_counts.append(count)
	_add_roadside_decals(rows, bounds)

## 沿原道路找相邻的非道路格。按世界矩形分区，每区最多取一个稳定散列样本。
## 贴花只读道路掩码，无碰撞及逐帧更新，切图随地面网格一同释放。
func _add_roadside_decals(rows: Array, bounds: Rect2) -> void:
	var selected: Dictionary = {}
	var scores: Dictionary = {}
	var anchors := bounds.grow_individual(-DECAL_SIZE.x * 0.5, -DECAL_SIZE.y * 0.5,
		-DECAL_SIZE.x * 0.5, -DECAL_SIZE.y * 0.5)
	for y in range(1, rows.size() - 1):
		var row: String = rows[y]
		var above: String = rows[y - 1]
		var below: String = rows[y + 1]
		for x in range(1, row.length() - 1):
			if row[x] == "1":
				continue
			if row[x - 1] != "1" and row[x + 1] != "1" and above[x] != "1" and below[x] != "1":
				continue
			var cell := Vector2i(x, y)
			var center := Iso.grid_to_world(cell)
			if not anchors.has_point(center):
				continue
			var sector := Vector2i((center - bounds.position) / bounds.size * Vector2(DECAL_SECTORS))
			var score := hash(cell)
			if not scores.has(sector) or score < scores[sector]:
				scores[sector] = score
				selected[sector] = cell
	if selected.is_empty():
		return
	var texture := load(DECALS) as Texture2D
	if texture == null:
		return
	var builder := FlatTileMesh.new(selected.size(), true)
	for cell: Vector2i in selected.values():
		var origin := Iso.grid_to_world(cell) - DECAL_SIZE * 0.5
		var left := float(hash(cell) % 2) * 0.5
		builder.add_quad(
			PackedVector2Array([origin, origin + Vector2(DECAL_SIZE.x, 0),
				origin + DECAL_SIZE, origin + Vector2(0, DECAL_SIZE.y)]),
			PackedVector2Array([Vector2(left, 0), Vector2(left + 0.5, 0),
				Vector2(left + 0.5, 1), Vector2(left, 1)]))
	var mesh := MeshInstance2D.new()
	mesh.name = "GroundDecals"
	mesh.mesh = builder.build()
	mesh.texture = texture
	mesh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mesh.modulate = Color(0.82, 0.8, 0.76, 0.65)
	mesh.z_as_relative = false
	mesh.z_index = -3997
	add_child(mesh)
