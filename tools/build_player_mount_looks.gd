extends SceneTree
## 骑乘外观（坐骑）图集烘焙器。
##
## 职责：把带坐骑的八向母版去背，按「列＝方向、行＝姿势帧」裁列，逐格裁掉透明边、
## 统一缩放到全状态一致的比例并重新对齐脚底锚点，最后打包为游戏读取的帧格图集。
##
## 输入：art_source/player/look_XX/mount_sources/<name>_<state>_raw.jpg（生成图，纯品红背景）
## 中间源稿：同目录 <name>_<state>_source.png（去背后母版，供人工修边，随 art_source 提交）
## 输出：assets/sprites/player/stage_looks/look_XX/mounts/<name>_<state>_atlas.png
##
## 契约：帧格 128×128、脚底锚点 (64,104)，列＝方向（顺序固定 s, sw, w, nw, n, ne, e, se）、
## 行＝姿势帧，与 CharacterLook.LOOKS[*].mounts 的登记一致；缩放上限沿用 look_01 坐骑图集的校准值。
## 生活依赖本机 ImageMagick（只用于色键去背与腐蚀，其余全部在 Godot 内完成）。
##
## 用法：Godot --headless --path . --script tools/build_player_mount_looks.gd

## ImageMagick 可执行名；色键去背与 alpha 腐蚀由它完成，避免在 GDScript 里逐像素扫全幅生成图。
const MAGICK := "magick"

## 运行图集帧格与脚底锚点，与 look_01 坐骑图集、CharacterLook.mounts 登记保持一致。
const CELL := Vector2i(128, 128)
const PIVOT := Vector2i(64, 104)

## 主体（含双翼与武器）缩放上限，取自 look_01 坐骑图集已校准的取值，
## 保证不同 look 的坐骑在 128×128 帧格内占地一致。
const MAX_HEIGHT := 56.0
const MAX_WIDTH := 90.0

## 去背参数：品红底与人物最近色的安全分界（18% fuzz），腐蚀两像素抹掉最外圈被背景污染的描边。
const KEY_COLOR := "srgb(252,22,168)"
const KEY_FUZZ := "18%"
const KEY_ERODE := "Disk:2"

## 坐骑外观清单：look_id → mount_id → state → 母版参数。
## rows 为母版行数（idle 是单姿势行、walk 是四姿势行）；frames 为运行图集帧数；
## bob 为逐帧整体抬升像素，用于呼吸与步频节奏，沿用角色待机、行走的既有做法。
const MOUNTS := {
	"look_06": {
		"mount_corrupted_wing": {
			"idle": {
				"raw": "res://art_source/player/look_06/mount_sources/corrupted_wing_idle_raw.jpg",
				"source": "res://art_source/player/look_06/mount_sources/corrupted_wing_idle_source.png",
				"rows": 1, "frames": 4, "bob": [0, -1, -2, -1],
			},
			"walk": {
				"raw": "res://art_source/player/look_06/mount_sources/corrupted_wing_walk_raw.jpg",
				"source": "res://art_source/player/look_06/mount_sources/corrupted_wing_walk_source.png",
				"rows": 4, "frames": 4, "bob": [0, -1, 0, -1],
			},
		},
	},
}

## 离线构建入口：逐个 look、逐只坐骑烘焙全部状态。
func _initialize() -> void:
	for look_id in MOUNTS:
		for mount_id in MOUNTS[look_id]:
			_build_mount(look_id, mount_id, MOUNTS[look_id][mount_id])
	quit()

## 构建一只坐骑的全部状态图集。
## 逐状态各算一次缩放比例：不同状态母版的原生绘制比例并不一致
## （单行 idle 母版里人物画得大、四行 walk 母版里人物画得小），
## 沿用单一比例会让骑乘待机与行走互相切换时主体跳大小，故必须按状态归一到同一占地高度。
func _build_mount(look_id: String, mount_id: String, states: Dictionary) -> void:
	for state in states:
		var master := _master_image(states[state])
		var cells := _split_cells(master, int(states[state].rows), look_id, mount_id, state)
		var factor := _state_factor(cells)
		_pack_state(look_id, mount_id, state, cells, states[state], factor)

## 为一个状态求缩放比例：宽度取全部格最大值；高度只取「未顶到行边界」的格。
## 四行母版的行距不足时，格内容会顶到行边界并被邻行羽片渗入，这类格的高度被算大，
## 直接参与取最大会把整档比例压小（walk 因此比 idle 小一半）；优先用未被截断的格作参考。
func _state_factor(cells: Array[Dictionary]) -> float:
	var widest := 1
	var tallest := 1
	var tallest_unclipped := 0
	for cell in cells:
		var image: Image = cell.image
		widest = maxi(widest, image.get_width())
		tallest = maxi(tallest, image.get_height())
		if not bool(cell.clipped):
			tallest_unclipped = maxi(tallest_unclipped, image.get_height())
	var reference := tallest_unclipped if tallest_unclipped > 0 else tallest
	return minf(MAX_HEIGHT / float(reference), MAX_WIDTH / float(widest))

## 读取母版：先用品红背景的生成原图去背并回写透明 PNG 源稿，再一律以该源稿为准。
## 源稿随 art_source 提交，便于人工修边；图集每次都由本工具重建，不手工修改产物。
func _master_image(param: Dictionary) -> Image:
	var raw_abs := ProjectSettings.globalize_path(String(param.raw))
	var source_abs := ProjectSettings.globalize_path(String(param.source))
	if FileAccess.file_exists(raw_abs):
		DirAccess.make_dir_recursive_absolute(source_abs.get_base_dir())
		var status := OS.execute(MAGICK, PackedStringArray([
			raw_abs, "-alpha", "set", "-fuzz", KEY_FUZZ, "-transparent", KEY_COLOR,
			"-channel", "A", "-morphology", "Erode", KEY_ERODE, "+channel", "-strip", source_abs,
		]), [], true)
		assert(status == 0, "坐骑母版去背失败：%s" % raw_abs)
	var image := Image.load_from_file(source_abs)
	assert(image != null, "坐骑母版缺失：%s" % String(param.source))
	image.convert(Image.FORMAT_RGBA8)
	return image

## 按「8 列＝方向、rows 行＝姿势帧」切分母版，并逐格裁掉透明边。
## 母版宽高不能被整除时按比例取整；方向顺序固定为 s, sw, w, nw, n, ne, e, se，不得改序。
## 每格返回 {image, clipped}；clipped 表示裁切后内容顶到行边界，说明母版行距不足，
## 该格高度可能被邻行羽片渗入而偏大，只作分布参考、不参与比例基准。
func _split_cells(source: Image, rows: int, look_id: String, mount_id: String, state: String) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	var row_height := float(source.get_height()) / float(rows)
	for row in range(rows):
		for direction in range(8):
			var x0 := roundi(float(direction) * source.get_width() / 8.0)
			var x1 := roundi(float(direction + 1) * source.get_width() / 8.0)
			var y0 := roundi(float(row) * source.get_height() / float(rows))
			var y1 := roundi(float(row + 1) * source.get_height() / float(rows))
			var piece := source.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
			var bounds := piece.get_used_rect()
			assert(bounds.size.x > 0 and bounds.size.y > 0,
				"坐骑动作格为空：%s/%s/%s/行%d/列%d" % [look_id, mount_id, state, row, direction])
			var clipped := bounds.position.y <= 0 or float(bounds.end.y) >= row_height
			pieces.append({"image": piece.get_region(bounds), "clipped": clipped})
	return pieces

## 把一个状态打包成「8 列 × frames 行」的 128×128 帧格图集。
## 每格按本状态比例点采样缩放后，剔除与主体不相连的邻格渗漏碎块，再以脚底线对齐锚点，
## 避免剑尖与披风下摆把接地线拉偏。
func _pack_state(look_id: String, mount_id: String, state: String, pieces: Array[Dictionary], param: Dictionary, factor: float) -> void:
	var frames := int(param.frames)
	var bob: Array = param.bob
	var rows := int(param.rows)
	var atlas := Image.create(CELL.x * 8, CELL.y * frames, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for frame in range(frames):
		# idle 只有一行姿势，四帧复用同一姿势并靠 bob 做呼吸；walk 四帧逐行对应四个节拍。
		var source_row := 0 if rows == 1 else frame
		for direction in range(8):
			var piece: Image = pieces[source_row * 8 + direction].image
			piece = piece.duplicate() as Image
			piece.resize(maxi(1, roundi(piece.get_width() * factor)), maxi(1, roundi(piece.get_height() * factor)), Image.INTERPOLATE_NEAREST)
			_keep_main_shape(piece)
			var foot := _foot_line(piece)
			var point := Vector2i(
				direction * CELL.x + PIVOT.x - piece.get_width() / 2,
				frame * CELL.y + PIVOT.y - foot + int(bob[frame]))
			assert(point.x >= direction * CELL.x and point.x + piece.get_width() <= (direction + 1) * CELL.x,
				"坐骑动作横向出格：%s/%s/%s/列%d" % [look_id, mount_id, state, direction])
			assert(point.y >= frame * CELL.y and point.y + piece.get_height() <= (frame + 1) * CELL.y,
				"坐骑动作纵向出格：%s/%s/%s/帧%d/列%d" % [look_id, mount_id, state, frame, direction])
			atlas.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), point)
	var output_dir := "res://assets/sprites/player/stage_looks/%s/mounts/" % look_id
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) == OK)
	var path := output_dir + "%s_%s_atlas.png" % [_short_name(mount_id), state]
	assert(atlas.save_png(path) == OK, "坐骑图集保存失败：%s" % path)
	print("[PlayerMountBuild] %s %s 尺寸=" % [look_id, "_%s_%s" % [mount_id, state]], atlas.get_size(), " 缩放=", factor)

## 只保留缩放后与主体相连的最大八邻域轮廓，剔除母版因行距不足而渗进本格的邻格羽片碎块。
## 与 look_01 坐骑图集的既有做法一致：只在打包阶段清理，不改动 art_source 里的源稿。
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

## 估计脚底基线：取主体中间 50% 宽的竖带内最低实心像素行，返回其下边界。
## 竖带用于避开剑尖、披风下摆等向外下探的部件；竖带内无实心像素时退回整幅最低行。
func _foot_line(piece: Image) -> int:
	var foot := _lowest_opaque_row(piece, piece.get_width() / 4, piece.get_width() - piece.get_width() / 4)
	if foot >= 0:
		return foot + 1
	return _lowest_opaque_row(piece, 0, piece.get_width()) + 1

## 返回 [left, right) 横向区间内最低的实心像素行号；整列全透明时返回 -1。
## 阈值取 0.5 与图集硬边一致，避免半透明描边被当作接地像素。
func _lowest_opaque_row(piece: Image, left: int, right: int) -> int:
	for y in range(piece.get_height() - 1, -1, -1):
		for x in range(left, right):
			if piece.get_pixel(x, y).a >= 0.5:
				return y
	return -1

## 取图集文件名用的短名：mount_corrupted_wing → corrupted_wing。
func _short_name(mount_id: String) -> String:
	return mount_id.trim_prefix("mount_")
