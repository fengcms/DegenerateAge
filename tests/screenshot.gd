extends Node
## 截图工具（开发期视觉验收用，不参与游戏运行）：
## 加载 Main 场景，等待若干帧渲染完成后截图到 /tmp，然后退出。
## 运行：GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##       "$GODOT" --path . res://tests/Screenshot.tscn

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(30):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png("/tmp/degenerateage_hud.png")
	print("[Screenshot] err=%d size=%s -> /tmp/degenerateage_hud.png" % [err, str(img.get_size())])
	get_tree().quit()
