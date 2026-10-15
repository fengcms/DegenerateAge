extends Node2D
## 幸存者营地 A/B 贴图局部实机样板：在同一正式 Game 场景上只替换可视层。
## 玩家、NPC、地图尺寸、导航和障碍直接复用当前营地；此场景不会写入正式地图入口。

const GAME_SCENE := preload("res://scenes/Game.tscn")
const MANIFEST_A := "res://assets/maps/camp_style_sample/a/manifest.json"
const MANIFEST_B := "res://assets/maps/camp_style_sample/b/manifest.json"
const FOCUS := {
	"blacksmith": [125, 300],
	"elder_tree": [1000, 450],
	"western_rocks": [125, 610],
	"northwest_palisade": [120, 170],
}

var world: Node2D
var ground: IsoGround
var player: PlayerCharacter
var camera: Camera2D
var active_style := "b"
var _styles: Dictionary = {}
var _help: Label

## 载入正式世界并隐藏原营地绘制；物理、寻路和角色节点仍由正式场景管理。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	GameState.settings["mapScale"] = 1.0
	world = GAME_SCENE.instantiate()
	add_child(world)
	ground = world.get_node("Ground") as IsoGround
	player = world.get_node("Entities/Player") as PlayerCharacter
	camera = player.get_node("Camera2D") as Camera2D
	ground.visible = false
	for style in ["a", "b"]:
		_styles[style] = _build_style(style)
		world.add_child(_styles[style])
	_show_style("b")
	_focus("blacksmith")
	_build_help()

## 将原画参考坐标映射到既有 3200×1800 世界矩形，不改变任何布局数据。
func _canvas_to_world(raw: Array) -> Vector2:
	return ground._camp_canvas_to_world(raw)

## 从运行清单装配纯地面、整体实体背层和可遮挡前沿；只在场景加载时创建。
func _build_style(style: String) -> Node2D:
	var path := MANIFEST_A if style == "a" else MANIFEST_B
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "营地样板清单缺失：%s" % path)
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert(String(manifest["layout_id"]) == String(ground._camp_whitebox["id"]),
		"样板与正式营地障碍源不一致")
	var layer := Node2D.new()
	layer.name = "CampStyle_%s" % style.to_upper()
	var color := Color("a59270") if style == "a" else Color("a88454")
	var base := Polygon2D.new()
	base.name = "UntreatedArea"
	base.color = color
	var bounds := ground.get_world_bounds()
	base.polygon = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	base.z_as_relative = false
	base.z_index = -4096
	layer.add_child(base)
	_add_sprite(layer, "ground", String(manifest["ground"]), manifest["patch"], -4095, style)
	for entry: Dictionary in manifest["objects"]:
		var rect: Array = entry["rect"]
		if entry.has("back"):
			_add_sprite(layer, String(entry["id"]) + "_back", String(entry["back"]), rect, -3500, style)
		if entry.has("front"):
			var foot: Array = [rect[0], entry["foot_y"]]
			var z := clampi(roundi(_canvas_to_world(foot).y), -3499, 3500)
			_add_sprite(layer, String(entry["id"]) + "_front", String(entry["front"]), rect, z, style)
	return layer

## 把一张带透明边的样板图放在原画参考矩形；B 的 2 倍像素只改变清晰度。
func _add_sprite(parent: Node2D, name: String, path: String, raw: Array, depth: int, style: String) -> void:
	var texture := load(path) as Texture2D
	assert(texture != null, "营地样板贴图缺失：%s" % path)
	var sprite := Sprite2D.new()
	sprite.name = name
	sprite.texture = texture
	sprite.centered = false
	sprite.position = _canvas_to_world([raw[0], raw[1]])
	var unit := ground.get_world_bounds().size / ground._camp_canvas_size
	sprite.scale = unit * Vector2(float(raw[2]) / texture.get_width(), float(raw[3]) / texture.get_height())
	sprite.z_as_relative = false
	sprite.z_index = depth
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if style == "a" else CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(sprite)

## 切换 A/B 的可视节点；不触碰正式世界节点、碰撞、路线或 NPC 位置。
func _show_style(style: String) -> void:
	assert(_styles.has(style), "未知营地样板风格：%s" % style)
	active_style = style
	for key: String in _styles:
		(_styles[key] as Node2D).visible = key == style
	_update_help()

## 将真实玩家移至现有可走格附近；用于同镜头比较建筑、树冠和岩石。
func _focus(id: String) -> void:
	assert(FOCUS.has(id), "未知样板观察点：%s" % id)
	player.global_position = ground.clamp_to_map(_canvas_to_world(FOCUS[id]))
	player.clear_travel_intent()
	camera.reset_smoothing()

## 按游戏已有地图倍率更新镜头和世界文字，供 100%/150%/200% 清晰度比较。
func _set_zoom(value: float) -> void:
	GameState.settings["mapScale"] = value
	SettingsRuntime.apply_map_scale_to(camera)
	SettingsRuntime.apply_world_text_scale()
	camera.reset_smoothing()
	_update_help()

## 创建样板场景的操作提示；文字不参与正式地图和导出素材。
func _build_help() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SampleControls"
	add_child(layer)
	_help = Label.new()
	_help.position = Vector2(16, 12)
	_help.add_theme_color_override("font_color", Color("f6ead2"))
	_help.add_theme_color_override("font_shadow_color", Color("211910"))
	_help.add_theme_constant_override("shadow_offset_x", 2)
	_help.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_help)
	_update_help()

## 更新当前风格和倍率说明；截图测试可隐藏此标签获得相同构图。
func _update_help() -> void:
	if _help != null:
		_help.text = "营地样板 %s · 地图 %.0f%%   F5 A / F6 B   F1 铁匠 / F2 长老树 / F3 岩石 / F4 栅栏   F7/F8/F9 倍率" % [
			active_style.to_upper(), float(GameState.settings.get("mapScale", 1.0)) * 100.0]

## 响应样板快捷键；WASD/鼠标仍交给真实玩家移动与交互。
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1: _focus("blacksmith")
		KEY_F2: _focus("elder_tree")
		KEY_F3: _focus("western_rocks")
		KEY_F4: _focus("northwest_palisade")
		KEY_F5: _show_style("a")
		KEY_F6: _show_style("b")
		KEY_F7: _set_zoom(1.0)
		KEY_F8: _set_zoom(1.5)
		KEY_F9: _set_zoom(2.0)
