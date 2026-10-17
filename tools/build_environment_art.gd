extends SceneTree
## Reproducibly packs the generated scene atlases into game-size PNGs.
## cave 地砖不在此处打包：它由 tools/build_cave_tiles.gd 从 cave_base 快照确定性派生并横向拉平
## （依据 docs/素材设计/41-地砖族扩充cave脚本派生小样与验收.md），避免覆盖已投产的 9 块产物。

const SOURCE := "res://art_source/environment/"

## 地砖打包表：每族列出源稿相对路径与格数（列×行）；产物按表内顺序、逐行逐列连续编号为 tile_N.png。
## wild 用单张 3×3（9 变体）；ash 用两张 2×2 合成 8 变体（3×3 排版比例不合格时的退回方案，见
## docs/素材设计/35-地砖族扩充第一批复核.md §6）。cave 不在本表内，见文件头说明。
const TILE_PLAN := {
	"wild": [{"file": "ground_tiles_v1/wild_tiles_3x3.png", "cols": 3, "rows": 3}],
	"ash": [
		{"file": "ground_tiles_v1/ash_tiles_a.png", "cols": 2, "rows": 2},
		{"file": "ground_tiles_v1/ash_tiles_b.png", "cols": 2, "rows": 2},
	],
}

func _initialize() -> void:
	for theme in ["wild", "ash"]:
		_pack_tiles(theme)
	for theme in ["wild", "ash", "cave"]:
		_pack_props(theme)
	quit()

## 按 TILE_PLAN 逐源稿切格：每格仍走「alpha 硬阈 → trim → 点采样 64×32 → 菱形掩码 + 填隙」四步，
## 结果按源稿顺序连续编号。仅行列数与源稿文件名改为查表，处理逻辑保持不变。
func _pack_tiles(theme: String) -> void:
	assert(TILE_PLAN.has(theme), "缺少地砖打包表：%s" % theme)
	var fill := Color("515a42") if theme == "wild" else Color("4b4443") if theme == "ash" else Color("d1b787")
	var index := 0
	for plan: Dictionary in TILE_PLAN[theme]:
		var image := Image.load_from_file(SOURCE + String(plan["file"]))
		assert(image != null, "地砖源稿缺失：%s" % plan["file"])
		image.convert(Image.FORMAT_RGBA8)
		var cols := int(plan["cols"])
		var rows := int(plan["rows"])
		var cell := image.get_size() / Vector2i(cols, rows)
		for row in range(rows):
			for col in range(cols):
				var piece := image.get_region(Rect2i(Vector2i(col, row) * cell, cell))
				_clear_faint(piece)
				var bounds := piece.get_used_rect()
				assert(bounds.has_area())
				piece = piece.get_region(bounds)
				piece.resize(64, 32, Image.INTERPOLATE_NEAREST)
				for y in range(32):
					for x in range(64):
						var edge := 1.0 - absf((x + 0.5 - 32.0) / 32.0) - absf((y + 0.5 - 16.0) / 16.0)
						var inside := edge >= 0.0
						if not inside:
							piece.set_pixel(x, y, Color.TRANSPARENT)
						elif piece.get_pixel(x, y).a < 0.5:
							piece.set_pixel(x, y, fill)
						elif theme == "cave" and edge < 0.22:
							var color := piece.get_pixel(x, y)
							piece.set_pixel(x, y, color.lerp(fill, 1.0 - clampf(edge / 0.22, 0.0, 1.0)))
				_save(piece, "res://assets/tiles/%s/tile_%d.png" % [theme, index])
				index += 1

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
