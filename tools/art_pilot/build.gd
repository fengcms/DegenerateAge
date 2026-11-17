extends SceneTree
## 将局部样板源图裁去透明留白并缩至展示尺寸；不执行抠图或改变造型。
## 此脚本仅生成隔离美术查看器素材，不修改正式资源。

## 按固定目标高度/宽度打包，并输出透明与尺寸检查信息。
func _initialize() -> void:
	for id in ["camp", "hero", "wolf", "worm"]:
		var image := Image.load_from_file("res://art_source/style_pilot_20261117/layers/" + id + ".png")
		print(id, " source=", image.get_size(), " alpha=", image.detect_alpha(), " used=", image.get_used_rect())
		if id != "camp":
			image = image.get_region(image.get_used_rect())
			var factor := 96.0 / image.get_height() if id == "hero" else 110.0 / image.get_width()
			image.resize(roundi(image.get_width() * factor), roundi(image.get_height() * factor), Image.INTERPOLATE_LANCZOS)
		else:
			image.resize(1200, 800, Image.INTERPOLATE_LANCZOS)
		image.save_png("res://assets/art_pilot/" + id + ".png")
	quit()
