extends SceneTree
## 初始角色「腐化之翼」八向待机与行走审稿图集打包器。
## 从 art_source/player/look_01/mount_sources 读取双翼人物源稿，输出 docs 内的候选图集。
## 此工具只构建美术样板，不接入正式玩家，也不改变坐骑玩法与速度。

const SOURCE_DIR := "res://art_source/player/look_01/mount_sources/"
const OUT_DIR := "res://docs/素材设计/样板/初始角色C/"
const FRAME := Vector2i(128, 128)
const PIVOT := Vector2i(64, 104)

## 离线构建入口：打包双翼待机与移动四帧样板。
func _initialize() -> void:
	_build("idle", [0, 315, 565, 815, 1122])
	_build("walk", [0, 244, 466, 690, 887])
	quit()

## 将低透明噪点去除，避免透明边缘把裁切范围扩大到相邻动作格。
func _clean(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.6:
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				pixel.a = 1.0
				image.set_pixel(x, y, pixel)

## 按八方向和四个时间行提取独立素材，并统计全状态统一缩放比例。
func _pieces(state: String, edges: Array) -> Array[Image]:
	var path := SOURCE_DIR + "corrupted_wing_%s_source.png" % state
	var source := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert(source != null and source.get_height() == edges[-1], "双翼源稿尺寸错误：%s" % path)
	_clean(source)
	var result: Array[Image] = []
	for row in range(4):
		for col in range(8):
			var x0 := roundi(float(col) * source.get_width() / 8.0)
			var x1 := roundi(float(col + 1) * source.get_width() / 8.0)
			var piece := source.get_region(Rect2i(x0, int(edges[row]), x1 - x0, int(edges[row + 1]) - int(edges[row])))
			var bounds := piece.get_used_rect()
			assert(bounds.size.x > 0 and bounds.size.y > 0, "双翼动作格为空：%s/%d/%d" % [state, row, col])
			result.append(piece.get_region(bounds))
	return result

## 只保留缩小后与角色相连的最大八邻域轮廓，剔除源稿散落的孤立羽片。
func _keep_main_shape(frame: Image) -> void:
	var width := frame.get_width()
	var height := frame.get_height()
	var count := width * height
	var seen := PackedByteArray()
	seen.resize(count)
	var largest: Array[int] = []
	for y in range(height):
		for x in range(width):
			var start := y * width + x
			if seen[start] != 0 or frame.get_pixel(x, y).a < 0.5:
				continue
			var queue: Array[int] = [start]
			seen[start] = 1
			var head := 0
			while head < queue.size():
				var point := queue[head]
				head += 1
				var px: int = point % width
				var py: int = int(point / width)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var nx: int = px + dx
						var ny: int = py + dy
						if nx < 0 or ny < 0 or nx >= width or ny >= height:
							continue
						var candidate: int = ny * width + nx
						if seen[candidate] == 0 and frame.get_pixel(nx, ny).a >= 0.5:
							seen[candidate] = 1
							queue.append(candidate)
			if queue.size() > largest.size():
				largest = queue
	var keep := PackedByteArray()
	keep.resize(count)
	for point in largest:
		keep[point] = 1
	for y in range(height):
		for x in range(width):
			if keep[y * width + x] == 0:
				frame.set_pixel(x, y, Color.TRANSPARENT)

## 将源稿缩放并靠统一脚底锚点排布为 8 列×4 行的透明图集。
func _build(state: String, edges: Array) -> void:
	var pieces := _pieces(state, edges)
	var max_w := 1
	var max_h := 1
	for piece in pieces:
		max_w = maxi(max_w, piece.get_width())
		max_h = maxi(max_h, piece.get_height())
	var factor := minf(56.0 / max_h, 90.0 / max_w)
	var atlas := Image.create(FRAME.x * 8, FRAME.y * 4, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for row in range(4):
		for col in range(8):
			var frame := pieces[row * 8 + col].duplicate() as Image
			frame.resize(maxi(1, roundi(frame.get_width() * factor)), maxi(1, roundi(frame.get_height() * factor)), Image.INTERPOLATE_NEAREST)
			_keep_main_shape(frame)
			var point := Vector2i(col * FRAME.x + PIVOT.x - frame.get_width() / 2, row * FRAME.y + PIVOT.y - frame.get_height())
			assert(point.x >= col * FRAME.x and point.y >= row * FRAME.y, "双翼动作越出帧格")
			atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), point)
	var output := OUT_DIR + "corrupted_wing_%s_candidate_atlas.png" % state
	assert(atlas.save_png(output) == OK, "双翼图集保存失败：%s" % output)
	print("[GuardianWingSample] ", state, " ", atlas.get_size(), " 缩放=", factor)
