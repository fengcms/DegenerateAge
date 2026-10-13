extends SceneTree
## Packs generated source sheets into fixed, foot-aligned game cells.

func _initialize() -> void:
	pack_sheet("shellback_bug", Vector2i(80, 80), Vector2i(40, 64), Vector2i(58, 34))
	pack_sheet("ash_wraith", Vector2i(64, 80), Vector2i(32, 64), Vector2i(52, 49))
	pack_strip("training_dummy", 3, Vector2i(64, 80), Vector2i(32, 64), Vector2i(48, 52), "res://assets/sprites/monsters/training_dummy/dummy_atlas.png")
	for role in ["quest", "shop", "blacksmith", "warehouse", "carter"]:
		pack_strip(role, 8, Vector2i(64, 80), Vector2i(32, 64), Vector2i(48, 50), "res://assets/sprites/npcs/%s/idle_atlas.png" % role)
	quit()

func clean(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.6:
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				image.set_pixel(x, y, color)

func row_bands(image: Image) -> Array[Vector2i]:
	var bands: Array[Vector2i] = []
	var start := -1
	for y in range(image.get_height()):
		var count := 0
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.5:
				count += 1
		if count > 16:
			if start < 0:
				start = y
		elif start >= 0:
			if y - start > 12:
				bands.append(Vector2i(start, y))
			start = -1
	if start >= 0:
		bands.append(Vector2i(start, image.get_height()))
	return bands

func source_image(id: String) -> Image:
	var path := "res://art_source/chapter_one_characters/%s_source.png" % id
	var image := Image.load_from_file(path)
	assert(image != null, path)
	clean(image)
	return image

func save(image: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	assert(image.save_png(path) == OK, path)

func pack_sheet(id: String, cell: Vector2i, pivot: Vector2i, bounds: Vector2i) -> void:
	var image := source_image(id)
	var bands := row_bands(image)
	assert(bands.size() == 8, "%s must have eight pose rows, found %d" % [id, bands.size()])
	var pieces: Array[Image] = []
	for band in bands:
		for col in range(8):
			var left := roundi(float(col) * image.get_width() / 8.0)
			var right := roundi(float(col + 1) * image.get_width() / 8.0)
			var source := image.get_region(Rect2i(left, band.x, right - left, band.y - band.x))
			var used := source.get_used_rect()
			assert(used.has_area(), "%s missing row/column" % id)
			pieces.append(source.get_region(used))
	var atlas := compose(pieces, 8, 8, cell, pivot, bounds)
	save(atlas, "res://assets/sprites/monsters/%s/actor_atlas.png" % id)

func pack_strip(id: String, columns: int, cell: Vector2i, pivot: Vector2i, bounds: Vector2i, destination: String) -> void:
	var image := source_image(id)
	var pieces: Array[Image] = []
	for col in range(columns):
		var left := roundi(float(col) * image.get_width() / columns)
		var right := roundi(float(col + 1) * image.get_width() / columns)
		var source := image.get_region(Rect2i(left, 0, right - left, image.get_height()))
		var used := source.get_used_rect()
		assert(used.has_area(), "%s missing column %d" % [id, col])
		pieces.append(source.get_region(used))
	save(compose(pieces, columns, 1, cell, pivot, bounds), destination)

func compose(pieces: Array[Image], columns: int, rows: int, cell: Vector2i, pivot: Vector2i, bounds: Vector2i) -> Image:
	var max_w := 1
	var max_h := 1
	for piece in pieces:
		max_w = maxi(max_w, piece.get_width())
		max_h = maxi(max_h, piece.get_height())
	var factor := minf(float(bounds.x) / max_w, float(bounds.y) / max_h)
	var atlas := Image.create(cell.x * columns, cell.y * rows, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for row in range(rows):
		for col in range(columns):
			var piece := pieces[row * columns + col].duplicate() as Image
			piece.resize(maxi(1, roundi(piece.get_width() * factor)), maxi(1, roundi(piece.get_height() * factor)), Image.INTERPOLATE_NEAREST)
			var pos := Vector2i(col * cell.x + pivot.x - piece.get_width() / 2, row * cell.y + pivot.y - piece.get_height())
			atlas.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), pos)
	return atlas
