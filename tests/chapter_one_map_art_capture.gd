extends Node
## 第一章四图原生渲染取样；只向系统临时目录写 PNG，不读取或修改真实存档。
## 供人工核对地图色阶、道路、地标和前景遮挡，输出不是自动视觉通过证明。

const SAMPLES := {
	"camp": Vector2i(32, 18),
	"wild_trial": Vector2i(63, 35),
	"ash_land": Vector2i(125, 63),
	"corruption_source": Vector2i(113, 45),
}


## 在渲染窗口逐图载入并取一帧，等待纹理实际上传后才保存截图。
func _ready() -> void:
	for map_id in SAMPLES:
		GameState.reset_to_defaults()
		GameState.current_map = map_id
		GameState.save_pos = Iso.grid_to_world(SAMPLES[map_id])
		GameState.has_save_pos = true
		var world := preload("res://scenes/Game.tscn").instantiate()
		add_child(world)
		for _index in range(5):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var target := "/tmp/chapter_one_map_art_%s.png" % map_id
		var result := get_viewport().get_texture().get_image().save_png(target)
		assert(result == OK, "无法保存第一章原生截图：%s" % target)
		world.queue_free()
		await get_tree().process_frame
	print("[ChapterOneMapArtCapture] PASS")
	get_tree().quit()
