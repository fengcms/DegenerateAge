extends SceneTree
## Deterministic packing of imagegen originals; no gameplay data is changed.

const OUT := "res://docs/素材设计/样板/可玩样板-v1/"

func _initialize() -> void:
	pack_actor("res://art_source/playable_sample/guardian_source_atlas.png", "res://assets/sprites/player/guardian/guardian_atlas.png", Vector2i(64, 80), Vector2i(32, 64), 48, 56)
	pack_guardian_extra()
	pack_actor("res://art_source/playable_sample/wolf_source_atlas.png", "res://assets/sprites/monsters/wolf_corrupted/wolf_atlas.png", Vector2i(80, 80), Vector2i(40, 64), 40, 64)
	pack_icon("weapon_starter", "res://assets/sprites/equip/weapon_starter.png")
	pack_icon("potion_hp_small", "res://assets/sprites/items/potion_hp_small.png")
	pack_icon("spirit_shard", "res://assets/sprites/items/spirit_shard.png")
	pack_tiles()
	pack_prop("campfire", Vector2i(64, 80), Vector2i(32, 64), Vector2i(46, 54))
	pack_prop("crate", Vector2i(64, 64), Vector2i(32, 48), Vector2i(38, 38))
	quit()

func clean(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x, y)
			if c.a < 0.6:
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				c.a = 1.0
				image.set_pixel(x, y, c)

func bands(image: Image) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
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
			if y - start > 15:
				result.append(Vector2i(start, y))
			start = -1
	if start >= 0:
		result.append(Vector2i(start, image.get_height()))
	return result

func save(image: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	assert(image.save_png(path) == OK, path)

func pack_actor(source: String, destination: String, cell: Vector2i, pivot: Vector2i, height: int, width: int) -> void:
	var image := Image.load_from_file(source)
	assert(image != null, source)
	clean(image)
	var rows := bands(image)
	print(source, " row bands: ", rows)
	assert(rows.size() == 7 or rows.size() == 8, "Unexpected actor row count")
	var pieces: Array[Image] = []
	var max_h := 1
	var max_w := 1
	for row in rows:
		for col in range(8):
			var x0 := roundi(float(col) * image.get_width() / 8.0)
			var x1 := roundi(float(col + 1) * image.get_width() / 8.0)
			var piece := image.get_region(Rect2i(x0, row.x, x1 - x0, row.y - row.x))
			var bounds := piece.get_used_rect()
			assert(bounds.size.x > 0 and bounds.size.y > 0, "Empty actor cell")
			piece = piece.get_region(bounds)
			pieces.append(piece)
			max_h = maxi(max_h, bounds.size.y)
			max_w = maxi(max_w, bounds.size.x)
	var factor := minf(float(height) / max_h, float(width) / max_w)
	var atlas := Image.create(cell.x * 8, cell.y * 8, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for row in range(8):
		# The guardian generator omitted a separate hit row. Reuse its recoil
		# key pose for hit explicitly; death comes from the final source band.
		var source_row := row if rows.size() == 8 else mini(row, 5)
		if row == 7:
			source_row = rows.size() - 1
		for col in range(8):
			var piece := pieces[source_row * 8 + col].duplicate() as Image
			piece.resize(maxi(1, roundi(piece.get_width() * factor)), maxi(1, roundi(piece.get_height() * factor)), Image.INTERPOLATE_NEAREST)
			var offset := Vector2i(col * cell.x + pivot.x - piece.get_width() / 2, row * cell.y + pivot.y - piece.get_height())
			atlas.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), offset)
	save(atlas, destination)

func pack_guardian_extra() -> void:
	var source := "res://art_source/playable_sample/guardian_hit_sit_source.png"
	var image := Image.load_from_file(source)
	assert(image != null, source)
	clean(image)
	var rows := bands(image)
	assert(rows.size() == 2, "Expected hit and sit sprite rows")
	var pieces: Array[Image] = []
	var max_h := 1
	var max_w := 1
	for row in rows:
		for col in range(8):
			var x0 := roundi(float(col) * image.get_width() / 8.0)
			var x1 := roundi(float(col + 1) * image.get_width() / 8.0)
			var piece := image.get_region(Rect2i(x0, row.x, x1 - x0, row.y - row.x))
			var bounds := piece.get_used_rect()
			assert(bounds.size.x > 0 and bounds.size.y > 0, "Empty guardian extra cell")
			piece = piece.get_region(bounds)
			pieces.append(piece)
			max_h = maxi(max_h, piece.get_height())
			max_w = maxi(max_w, piece.get_width())
	var factor := minf(48.0 / max_h, 56.0 / max_w)
	var atlas := Image.create(64 * 8, 80 * 2, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for row in range(2):
		for col in range(8):
			var piece := pieces[row * 8 + col].duplicate() as Image
			piece.resize(maxi(1, roundi(piece.get_width() * factor)), maxi(1, roundi(piece.get_height() * factor)), Image.INTERPOLATE_NEAREST)
			var offset := Vector2i(col * 64 + 32 - piece.get_width() / 2, row * 80 + 64 - piece.get_height())
			atlas.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), offset)
	save(atlas, "res://assets/sprites/player/guardian/guardian_hit_sit_atlas.png")

func pack_icon(id: String, destination: String) -> void:
	var source := Image.load_from_file("res://art_source/playable_sample/%s.png" % id)
	clean(source)
	var piece := source.get_region(source.get_used_rect())
	var factor := 38.0 / maxf(piece.get_width(), piece.get_height())
	piece.resize(maxi(1, roundi(piece.get_width() * factor)), maxi(1, roundi(piece.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	var icon := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	icon.fill(Color.TRANSPARENT)
	icon.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), (Vector2i(48, 48) - piece.get_size()) / 2)
	save(icon, destination)
	var small := piece.duplicate() as Image
	small.resize(maxi(1, roundi(piece.get_width() * 0.55)), maxi(1, roundi(piece.get_height() * 0.55)), Image.INTERPOLATE_NEAREST)
	var world := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	world.fill(Color.TRANSPARENT)
	world.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(16 - small.get_width() / 2, 24 - small.get_height()))
	save(world, "res://assets/sprites/items/%s_ground.png" % id)

func pack_tiles() -> void:
	var image := Image.load_from_file("res://art_source/playable_sample/camp_source_tiles.png")
	clean(image)
	for row in range(2):
		for col in range(2):
			var cell := Vector2i(image.get_width() / 2, image.get_height() / 2)
			var piece := image.get_region(Rect2i(Vector2i(col, row) * cell, cell))
			piece = piece.get_region(piece.get_used_rect())
			piece.resize(64, 32, Image.INTERPOLATE_NEAREST)
			# Enforce an exact shared 2:1 footprint; transparent pinholes use dirt.
			for y in range(32):
				for x in range(64):
					var inside := absf((x + 0.5 - 32.0) / 32.0) + absf((y + 0.5 - 16.0) / 16.0) <= 1.0
					if not inside:
						piece.set_pixel(x, y, Color.TRANSPARENT)
					elif piece.get_pixel(x, y).a < 0.5:
						piece.set_pixel(x, y, Color("806346"))
			save(piece, "res://assets/tiles/camp/tile_%d.png" % (row * 2 + col))

func pack_prop(id: String, cell: Vector2i, pivot: Vector2i, bounds: Vector2i) -> void:
	var image := Image.load_from_file("res://art_source/playable_sample/%s.png" % id)
	clean(image)
	var piece := image.get_region(image.get_used_rect())
	var factor := minf(float(bounds.x) / piece.get_width(), float(bounds.y) / piece.get_height())
	piece.resize(maxi(1, roundi(piece.get_width() * factor)), maxi(1, roundi(piece.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	var result := Image.create(cell.x, cell.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(pivot.x - piece.get_width() / 2, pivot.y - piece.get_height()))
	save(result, "res://assets/tiles/camp/%s.png" % id)
