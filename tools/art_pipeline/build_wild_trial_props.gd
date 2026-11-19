extends SceneTree
## 打包试炼荒野的透明岩脊与残车源稿。只裁透明边和缩放，保留旧运行画幅及脚锚。
## 在独立 Godot 项目运行，用户参数为仓库绝对路径。

const SOURCE_DIR := "/art_source/environment/wild_trial_props_v1/"
const OUTPUT_DIR := "/assets/tiles/chapter1_v2/wild_trial/"
const SIZES := {"moss_ridge": Vector2i(188, 182), "broken_cart": Vector2i(180, 177)}

## 按旧物件画幅输出独立运行贴图；缺图、非透明或空图会以非零状态退出。
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("需要仓库绝对路径")
		quit(1)
		return
	for asset: String in SIZES:
		var image := Image.load_from_file(args[0] + SOURCE_DIR + asset + ".png")
		if image == null or image.detect_alpha() == Image.ALPHA_NONE:
			push_error("缺少透明源稿：" + asset)
			quit(1)
			return
		var bounds := _subject_bounds(image)
		if not bounds.has_area():
			push_error("透明源稿没有主体：" + asset)
			quit(1)
			return
		var piece := image.get_region(bounds)
		var size: Vector2i = SIZES[asset]
		piece.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		if piece.save_png(args[0] + OUTPUT_DIR + asset + "_modular.png") != OK:
			push_error("无法保存运行贴图：" + asset)
			quit(1)
			return
	print("WILD_TRIAL_PROPS_BUILD_OK")
	quit()

## 找出主体边界，忽略周围近透明噪点并保留框内原始 alpha。
func _subject_bounds(image: Image) -> Rect2i:
	var start := image.get_size()
	var end := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.1:
				var point := Vector2i(x, y)
				start = start.min(point)
				end = end.max(point)
	return Rect2i(start, end - start + Vector2i.ONE) if end.x >= 0 else Rect2i()
