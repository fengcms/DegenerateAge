extends SceneTree
## 把第三方（Hormelz，CC0）八向骑士源表重排为项目运行图集，供 look_02 使用。
##
## 输入：`art_source/vendor/hormelz-knight-8dir/<包名>/<动画>/Knight_<动画>_dir<方向>.png`
##   厂商约定：每个「动画 × 方向」一张 PNG，画布 1280×1024，格 256×256，
##   帧号按行优先编号（帧号 → 列 = 帧号 % 5、行 = 帧号 / 5）。
##   厂商方向号：dir1=左下、dir2=左、dir3=左上、dir4=上、dir5=右上、dir6=右、dir7=右下、dir8=下。
## 输出：`assets/sprites/player/knight/knight_atlas.png`（8 方向 × 8 姿势行）
##      `assets/sprites/player/knight/knight_walk_atlas.png`（8 方向 × 4 姿势行）
##   两者帧格均为 64×80、脚底锚点 (32,64)，与 look_01（guardian）保持一致。
## 覆盖范围：只产出 look_02 需要的主图集与行走图集，不处理厂商其余动画；
##   厂商其余动画留在 art_source 作为来源存档，需要时在下方姿势表补一行即可。
## 使用方法：`godot --headless --path . --script tools/build_look_atlas.gd`，
##   随后跑一次 `godot --headless --editor --quit --path .` 让引擎生成 .import。
##
## 与既有 guardian 打包脚本的差异：源表是高分辨率预渲染三维素材，
## 256 → 48 若沿用最近邻缩放会丢掉大量像素、轮廓断裂；这里改用 Lanczos 缩放后
## 再按项目约定做透明阈值整理，帧格、锚点与坐标约定不变。

const SOURCE := "res://art_source/vendor/hormelz-knight-8dir"
const OUT_DIR := "res://assets/sprites/player/knight"
const CELL := Vector2i(64, 80)
const PIVOT := Vector2i(32, 64)
const CELL_SOURCE := 256
const ALPHA_CUTOFF := 0.6
## 身体在格内的最大占位，用于从待机帧推算统一缩放，避免挥砍帧把整体压小。
const BODY_SIZE := Vector2(48, 56)
## 厂商包名（与 art_source 下的目录同名）。
const PACKS := {"basic": "KnightBasic", "combat": "KnightAdvCombat"}
## 主图集行序与 SampleActorArt 的取行约定对齐：0/1 待机、2/3 备用步态、4/5 攻击、6 受击、7 死亡。
const MAIN_ROWS := [
	{"pack": "basic", "anim": "Idle", "frame": 0},
	{"pack": "basic", "anim": "Idle", "frame": 8},
	{"pack": "basic", "anim": "Run", "frame": 0},
	{"pack": "basic", "anim": "Run", "frame": 4},
	{"pack": "basic", "anim": "Attack", "frame": 13},
	{"pack": "basic", "anim": "Attack", "frame": 6},
	{"pack": "combat", "anim": "Knock", "frame": 7},
	{"pack": "basic", "anim": "Die", "frame": 26},
]
## 行走图集的 4 行取自行走循环上均匀分布的 4 个关键姿势，对应 WALK_ROWS 的 0..3。
const WALK_ROWS := [
	{"pack": "basic", "anim": "Walk", "frame": 0},
	{"pack": "basic", "anim": "Walk", "frame": 3},
	{"pack": "basic", "anim": "Walk", "frame": 6},
	{"pack": "basic", "anim": "Walk", "frame": 9},
]

func _initialize() -> void:
	# 项目朝向 f（0=下、1=左下、2=左 … 4=上 … 7=右下）对应的厂商方向号。
	var dirs: Array[int] = []
	for facing in range(8):
		dirs.append(8 if facing == 0 else facing)
	var factor := _body_factor(dirs)
	print("统一缩放系数：", factor)
	_save(_compose(dirs, MAIN_ROWS, factor), "%s/knight_atlas.png" % OUT_DIR)
	_save(_compose(dirs, WALK_ROWS, factor), "%s/knight_walk_atlas.png" % OUT_DIR)
	quit()

## 从待机帧（主图集第 0、1 行）推算统一缩放：所有帧共用同一系数，
## 身体大小才不会随武器挥动的包围盒变化而抖动。
func _body_factor(dirs: Array[int]) -> float:
	var max_h := 1
	var max_w := 1
	for entry: Dictionary in [MAIN_ROWS[0], MAIN_ROWS[1]]:
		for dir in dirs:
			var piece := _piece(entry, dir)
			max_h = maxi(max_h, piece.get_height())
			max_w = maxi(max_w, piece.get_width())
	return minf(BODY_SIZE.x / max_h, BODY_SIZE.y / max_w)

## 把姿势表逐行逐方向拼成图集：列＝方向、行＝姿势帧，脚底对齐到 (32,64)。
func _compose(dirs: Array[int], plan: Array, factor: float) -> Image:
	var atlas := Image.create(CELL.x * 8, CELL.y * plan.size(), false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for row in range(plan.size()):
		for facing in range(8):
			var piece := _fit(_scaled(_piece(plan[row], dirs[facing]), factor))
			var offset := Vector2i(facing * CELL.x + PIVOT.x - piece.get_width() / 2, row * CELL.y + PIVOT.y - piece.get_height())
			atlas.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), offset)
	return atlas

## 取出源表里的单帧并裁掉四周透明边。厂商表按行优先编号，列数由画布宽度推出。
func _piece(entry: Dictionary, dir: int) -> Image:
	var path := "%s/%s/%s/Knight_%s_dir%d.png" % [SOURCE, PACKS[entry.pack], entry.anim, entry.anim, dir]
	var sheet := Image.load_from_file(path)
	assert(sheet != null, path)
	var cols := sheet.get_width() / CELL_SOURCE
	var origin := Vector2i((entry.frame % cols) * CELL_SOURCE, (entry.frame / cols) * CELL_SOURCE)
	var cell := sheet.get_region(Rect2i(origin, Vector2i(CELL_SOURCE, CELL_SOURCE)))
	_clean(cell)
	return cell.get_region(cell.get_used_rect())

func _scaled(piece: Image, factor: float) -> Image:
	var scaled := piece.duplicate() as Image
	scaled.resize(maxi(1, roundi(piece.get_width() * factor)), maxi(1, roundi(piece.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	# Lanczos 会重新引入半透明边缘，按项目约定再次阈值化，保证最近邻显示时边缘干净。
	_clean(scaled)
	return scaled

## 个别挥砍/倒地帧可能超出格位，等比收缩到可容纳范围，避免被图集边缘裁断。
func _fit(piece: Image) -> Image:
	var limit := Vector2(CELL.x, PIVOT.y + 16)
	if piece.get_width() <= limit.x and piece.get_height() <= limit.y:
		return piece
	var ratio := minf(limit.x / piece.get_width(), limit.y / piece.get_height())
	var fitted := piece.duplicate() as Image
	fitted.resize(maxi(1, roundi(piece.get_width() * ratio)), maxi(1, roundi(piece.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	_clean(fitted)
	return fitted

## 透明阈值整理：低于阈值的像素直接清空，其余像素拉满不透明，避免半透明叠加。
func _clean(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < ALPHA_CUTOFF:
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				image.set_pixel(x, y, color)

func _save(image: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	assert(image.save_png(path) == OK, path)
	print("已输出：", path, " ", image.get_size())
