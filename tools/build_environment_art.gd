extends SceneTree
## Reproducibly packs the generated scene atlases into game-size PNGs.

const SOURCE := "res://art_source/environment/"

func _initialize() -> void:
	for theme in ["wild", "ash"]:
		_pack_tiles(theme)
		_pack_props(theme)
	quit()

func _pack_tiles(theme: String) -> void:
	var image := Image.load_from_file(SOURCE + theme + "_tiles.png")
	assert(image != null)
	image.convert(Image.FORMAT_RGBA8)
	var cell := image.get_size() / 2
	var fill := Color("515a42") if theme == "wild" else Color("4b4443")
	for row in range(2):
		for col in range(2):
			var piece := image.get_region(Rect2i(Vector2i(col, row) * cell, cell))
			_clear_faint(piece)
			var bounds := piece.get_used_rect()
			assert(bounds.has_area())
			piece = piece.get_region(bounds)
			piece.resize(64, 32, Image.INTERPOLATE_NEAREST)
			for y in range(32):
				for x in range(64):
					var inside := absf((x + 0.5 - 32.0) / 32.0) + absf((y + 0.5 - 16.0) / 16.0) <= 1.0
					if not inside:
						piece.set_pixel(x, y, Color.TRANSPARENT)
					elif piece.get_pixel(x, y).a < 0.5:
						piece.set_pixel(x, y, fill)
			_save(piece, "res://assets/tiles/%s/tile_%d.png" % [theme, row * 2 + col])

func _pack_props(theme: String) -> void:
	var image := Image.load_from_file(SOURCE + theme + "_props.png")
	assert(image != null)
	image.convert(Image.FORMAT_RGBA8)
	var cell := image.get_size() / 2
	for row in range(2):
		for col in range(2):
			var piece := image.get_region(Rect2i(Vector2i(col, row) * cell, cell))
			_clear_faint(piece)
			var bounds := piece.get_used_rect()
			assert(bounds.has_area())
			piece = piece.get_region(bounds)
			var factor := minf(56.0 / piece.get_width(), 68.0 / piece.get_height())
			piece.resize(maxi(1, roundi(piece.get_width() * factor)), maxi(1, roundi(piece.get_height() * factor)), Image.INTERPOLATE_NEAREST)
			var packed := Image.create(80, 80, false, Image.FORMAT_RGBA8)
			packed.fill(Color.TRANSPARENT)
			packed.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(40 - piece.get_width() / 2, 72 - piece.get_height()))
			_save(packed, "res://assets/tiles/%s/prop_%d.png" % [theme, row * 2 + col])

func _clear_faint(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				image.set_pixel(x, y, color)

func _save(image: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	assert(image.save_png(path) == OK)
