extends SceneTree
## 初始角色 look_01 的八向动画打包器。
## 读取 art_source 中已审查的 AI 源稿和现有守护者关键帧，按列＝方向、行＝时间帧导出六张 64×80 帧格图集。
## 仅负责离线图像排布；不改变战斗时序、角色状态、碰撞或运行时资源加载。
## 用法：Godot --headless --path . --script tools/build_guardian_animations.gd

const SOURCE_DIR := "res://art_source/player/look_01/animation_sources/"
const OUTPUT_DIR := "res://assets/sprites/player/guardian/animations/"
const CELL := Vector2i(64, 80)
const PIVOT := Vector2i(32, 64)

## Godot 入口：顺序制作六张图集，完成后关闭离线进程。
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_build("idle", [0, 256, 476, 695, 887], 4, 48, 56)
	_build("walk", [0, 244, 466, 690, 887], 8, 48, 56)
	_build("attack", [0, 220, 400, 585, 765, 1086], 6, 48, 56)
	_build("hit", [0, 390, 725], 2, 48, 56)
	_build("death", [0, 260, 480, 690, 880, 1086], 6, 46, 56)
	_build("sit", [0, 280, 480, 680, 887], 4, 34, 56)
	quit()

## 读取源稿、清除低透明杂点，并按固定八列与审定行界限拆出每个独立姿态。
func _source_pieces(state: String, y_edges: Array) -> Array[Image]:
	var filename := "walk_inbetween_source.png" if state == "walk" else "%s_source.png" % state
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_DIR + filename))
	assert(source != null, "源稿不存在：%s" % filename)
	assert(y_edges[0] == 0 and y_edges[-1] == source.get_height(), "源稿高度或行界限变化：%s" % filename)
	_clean(source)
	var pieces: Array[Image] = []
	for row in range(y_edges.size() - 1):
		for col in range(8):
			var x0 := roundi(float(col) * source.get_width() / 8.0)
			var x1 := roundi(float(col + 1) * source.get_width() / 8.0)
			var region := Rect2i(x0, int(y_edges[row]), x1 - x0, int(y_edges[row + 1]) - int(y_edges[row]))
			var piece := source.get_region(region)
			var bounds := piece.get_used_rect()
			assert(bounds.size.x > 0 and bounds.size.y > 0, "缺失动作格：%s/%d/%d" % [state, row, col])
			pieces.append(piece.get_region(bounds))
	return pieces

## 将低于 60% 不透明度的像素清零，避免生成源稿的低透明噪点扩大裁切范围。
func _clean(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.6:
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				image.set_pixel(x, y, color)

## 把裁好的原稿缩到世界角色尺度，并将所有方向与时间帧对齐到同一脚底锚点。
func _put_generated(atlas: Image, piece: Image, row: int, col: int, factor: float) -> void:
	var frame := piece.duplicate() as Image
	frame.resize(maxi(1, roundi(frame.get_width() * factor)), maxi(1, roundi(frame.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	var point := Vector2i(col * CELL.x + PIVOT.x - frame.get_width() / 2, row * CELL.y + PIVOT.y - frame.get_height())
	assert(point.x >= col * CELL.x and point.y >= row * CELL.y, "动作越出帧格")
	assert(point.x + frame.get_width() <= (col + 1) * CELL.x and point.y + frame.get_height() <= (row + 1) * CELL.y, "动作越出帧格")
	atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), point)

## 复制原有 64×80 关键帧，供四张既有行走图与攻击/死亡末帧使用。
func _put_existing(atlas: Image, source: Image, source_row: int, row: int, col: int) -> void:
	var region := Rect2i(col * CELL.x, source_row * CELL.y, CELL.x, CELL.y)
	atlas.blit_rect(source, region, Vector2i(col * CELL.x, row * CELL.y))

## 根据各状态源稿行数输出目标图集；行走交错补帧，攻击与死亡保留原有末态关键帧。
func _build(state: String, y_edges: Array, frames: int, target_height: int, target_width: int) -> void:
	var pieces := _source_pieces(state, y_edges)
	var source_rows := y_edges.size() - 1
	assert(pieces.size() == source_rows * 8, "源稿格子数错误：%s" % state)
	var max_width := 1
	var max_height := 1
	for piece in pieces:
		max_width = maxi(max_width, piece.get_width())
		max_height = maxi(max_height, piece.get_height())
	var factor := minf(float(target_height) / float(max_height), float(target_width) / float(max_width))
	var atlas := Image.create(CELL.x * 8, CELL.y * frames, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var old_main := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sprites/player/guardian/guardian_atlas.png"))
	var old_walk := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sprites/player/guardian/guardian_walk_atlas.png"))
	assert(old_main != null and old_walk != null, "守护者旧图集缺失")
	for row in range(frames):
		for col in range(8):
			if state == "walk" and row % 2 == 0:
				_put_existing(atlas, old_walk, row / 2, row, col)
			elif state == "attack" and row == frames - 1:
				_put_existing(atlas, old_main, 0, row, col)
			elif state == "death" and row == frames - 1:
				_put_existing(atlas, old_main, 7, row, col)
			else:
				var source_row := row / 2 if state == "walk" else row
				assert(source_row < source_rows, "源稿行数不足：%s/%d" % [state, row])
				_put_generated(atlas, pieces[source_row * 8 + col], row, col, factor)
	var output := OUTPUT_DIR + "guardian_%s_atlas.png" % state
	assert(atlas.save_png(output) == OK, "保存失败：%s" % output)
	print("[GuardianAnimationBuild] ", state, " ", atlas.get_size(), " 源行数=", source_rows, " 缩放=", factor)
