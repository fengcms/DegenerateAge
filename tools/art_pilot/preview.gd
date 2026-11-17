extends Node2D
## 独立素材尺寸查看器；加载已经打包的四张图片，不访问正式游戏和存档。
## 允许拖动静态对象检查透明边缘和相互遮挡，不模拟移动或战斗动画。
var actors: Array[Sprite2D] = []
var selected: Sprite2D
var enlarged := false

## 首次进入时创建底图、按脚底排序的对象和说明；图片只加载一次。
func _ready() -> void:
	var background := _sprite("camp")
	background.centered = false
	add_child(background)
	var layer := Node2D.new()
	layer.y_sort_enabled = true
	add_child(layer)
	var names := ["hero", "wolf", "worm"]
	var points := [Vector2(460, 510), Vector2(660, 510), Vector2(790, 580)]
	for i in range(3):
		var actor := _sprite(names[i])
		actor.offset.y = -actor.texture.get_height() * 0.5
		actor.position = points[i]
		layer.add_child(actor)
		actors.append(actor)
	var info := Label.new()
	info.text = "静态素材校准 · 拖动对象比较透明边缘与前后关系 · 空格切换 1×/2×\n主角约96px高 / 怪物110px宽；非行走动画，建筑暂为背景"
	info.position = Vector2(20, 20)
	info.add_theme_color_override("font_color", Color.WHITE)
	info.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(info)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../art_source/style_pilot_20261117/layers/runtime_preview.png"))
		print("ART_PREVIEW_CAPTURE_OK")
		get_tree().quit()

## 从项目资产目录读取已裁切PNG；隔离查看器不依赖主工程导入缓存。
func _sprite(id: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	var path := ProjectSettings.globalize_path("res://../../assets/art_pilot/" + id + ".png")
	sprite.texture = ImageTexture.create_from_image(Image.load_from_file(path))
	return sprite

## 拖动仅改变查看器中静态贴图位置；空格倍率用于对比细节损失。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		enlarged = not enlarged
		for actor in actors:
			actor.scale = Vector2.ONE * (2.0 if enlarged else 1.0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		selected = null
		if event.pressed:
			for actor in actors:
				if actor.get_rect().has_point(actor.to_local(event.position)):
					if selected == null or actor.position.y > selected.position.y:
						selected = actor
	elif event is InputEventMouseMotion and selected != null:
		selected.position += event.relative
