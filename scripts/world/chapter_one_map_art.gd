class_name ChapterOneMapArt
extends Node2D
## 第一章四图的静态多格美术实体；读取已编译的摆放记录并复用同一纹理。
## 只负责视觉与向 IsoGround 提供整体碰撞，不更改任务、刷新或寻路掩码。

var map_id := ""
var layout: Dictionary = {}
var _textures: Dictionary = {}
const WILD_PROP_DIR := "res://assets/tiles/chapter1_v2/wild_trial/"
const WILD_MODULAR_PROPS := ["moss_ridge", "broken_cart"]


## 在节点加入场景树前设定地图与摆放数据；调用方保证版本已与运行布局核对。
func configure(selected_map: String, art_layout: Dictionary) -> void:
	map_id = selected_map
	layout = art_layout


## 地图载入时一次性建立静态精灵；移动和镜头更新不重新加载图片。
func _ready() -> void:
	name = "ChapterOneMapArt"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for raw in layout.get("entities", []):
		var entity: Dictionary = raw
		var positions: Array = entity.get("visual_cells", [])
		var visual_assets: Array = entity.get("visual_assets", [])
		for index in range(positions.size()):
			var visual_entity := entity
			if index < visual_assets.size():
				visual_entity = entity.duplicate()
				visual_entity["asset_id"] = String(visual_assets[index])
			var texture := _texture_for(visual_entity)
			if texture == null:
				continue
			var values: Array = positions[index]
			var cell := Vector2i(int(values[0]), int(values[1]))
			var modular_tree := map_id=="wild_trial" and String(visual_entity.get("asset_id",""))=="dead_tree"
			var sprite: Sprite2D = CampModuleOccluder.new() if modular_tree else Sprite2D.new()
			if modular_tree:
				sprite.mask_texture = load("res://assets/environment/camp_modular_v1/tree_reveal_mask.png") as Texture2D
			sprite.name = "%s_%02d" % [String(entity.get("instance_id", "entity")), index]
			sprite.texture = texture
			sprite.centered = false
			# 导出时裁掉了透明边，脚底锚点固定在图片底部中心。
			sprite.offset = Vector2(-texture.get_width() * 0.5, -texture.get_height() + 4.0)
			var visual_scale := float(entity.get("visual_scale", 1.0))
			if modular_tree:
				visual_scale *= 189.0/230.0 # 保持旧树高度与脚底，新增较宽树冠使用局部淡出。
			sprite.scale = Vector2.ONE * visual_scale
			sprite.position = Iso.grid_to_world(cell)
			sprite.z_as_relative = false
			sprite.z_index = clampi(roundi(sprite.position.y), -3500, 3500)
			add_child(sprite)


## 对同一大型实体只建立一个 CollisionPolygon2D；顶点是格边界的等距投影。
## 使用运行掩码编译出的轮廓，不能用图片透明边或粗矩形替代碰撞。
func add_collisions_to(body: StaticBody2D) -> void:
	for raw in layout.get("entities", []):
		var entity: Dictionary = raw
		if not bool(entity.get("blocking", false)):
			continue
		var points := PackedVector2Array()
		for value in entity.get("collision_polygon", []):
			var grid_point: Array = value
			points.append(Iso.grid_pt(float(grid_point[0]), float(grid_point[1])))
		assert(points.size() >= 3, "大型障碍缺少合并碰撞：%s" % entity.get("instance_id", ""))
		var collision := CollisionPolygon2D.new()
		collision.name = String(entity.get("instance_id", "block"))
		collision.polygon = points
		body.add_child(collision)


## 按路径缓存纹理。荒野新版岩脊和残车沿用旧画幅，缺图时读取原贴图。
func _texture_for(entity: Dictionary) -> Texture2D:
	var asset_id := String(entity.get("asset_id", ""))
	var path := String(entity.get("asset_path", ""))
	if map_id=="wild_trial" and asset_id=="dead_tree":
		path = "res://assets/environment/camp_modular_v1/tree.png"
	elif map_id == "wild_trial" and path.is_empty() and asset_id in WILD_MODULAR_PROPS:
		var replacement := WILD_PROP_DIR + asset_id + "_modular.png"
		if ResourceLoader.exists(replacement, "Texture2D"):
			path = replacement
	if path.is_empty():
		path = "res://assets/tiles/chapter1_v2/%s/%s.png" % [map_id, asset_id]
	if _textures.has(path):
		return _textures[path] as Texture2D
	var texture := load(path) as Texture2D
	assert(texture != null, "第一章素材不存在：%s" % path)
	_textures[path] = texture
	return texture
