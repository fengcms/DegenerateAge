extends SceneTree
## 将汲灵幼虫的七张独立方向候选与原东南向贴图烘焙成试玩图集。
## 图集：3 列（原姿、受击、死亡）× 8 行（s/sw/w/nw/n/ne/e/se），每格 80×80。

const SIDE := 80
const FOOT_Y := 64
const MAX_WIDTH := 70
const MAX_HEIGHT := 58
const SOURCE := "res://art_source/chapters/ch02/monsters/c2_spirit_larva/"
const OUTPUT := "res://assets/sprites/monsters/c2_spirit_larva/directional_preview_atlas.png"
const DIRECTIONS := [
	"south_candidate_v1.png", "sw_candidate_v1.png", "west_candidate_v1.png",
	"nw_candidate_v1.png", "rear_candidate_v3.png", "ne_candidate_v1.png",
	"east_candidate_v1.png", "",
]

func _initialize() -> void:
	var result := _build()
	quit(0 if result else 1)

func _build() -> bool:
	var atlas := Image.create_empty(SIDE * 3, SIDE * 8, false, Image.FORMAT_RGBA8)
	for row in DIRECTIONS.size():
		var pose := _load_pose(row)
		if pose == null:
			return false
		for state in 3:
			var frame := pose.duplicate()
			if state > 0:
				_tint(frame, state)
			atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(state * SIDE, row * SIDE))
	var status := atlas.save_png(ProjectSettings.globalize_path(OUTPUT))
	if status != OK:
		push_error("无法保存方向试玩图集：%s" % status)
		return false
	print("汲灵幼虫方向试玩图集：%s（%s×%s）" % [OUTPUT, atlas.get_width(), atlas.get_height()])
	return true

func _load_pose(row: int) -> Image:
	if row == 7:
		var old := Image.load_from_file("res://assets/sprites/monsters/c2_spirit_larva/simplified_atlas.png")
		if old == null or old.get_width() < SIDE or old.get_height() != SIDE:
			push_error("东南向旧图缺失或尺寸错误")
			return null
		return old.get_region(Rect2i(0, 0, SIDE, SIDE))
	var source := Image.load_from_file(SOURCE + DIRECTIONS[row])
	if source == null or source.is_empty():
		push_error("方向候选缺失：%s" % DIRECTIONS[row])
		return null
	source.convert(Image.FORMAT_RGBA8)
	var bounds := _visible_bounds(source)
	if bounds.size == Vector2i.ZERO:
		push_error("方向候选为空：%s" % DIRECTIONS[row])
		return null
	var body := source.get_region(bounds)
	var ratio: float = minf(float(MAX_WIDTH) / body.get_width(), float(MAX_HEIGHT) / body.get_height())
	body.resize(maxi(1, roundi(body.get_width() * ratio)), maxi(1, roundi(body.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	var frame := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	frame.blit_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), Vector2i((SIDE - body.get_width()) / 2, FOOT_Y - body.get_height()))
	return frame

func _visible_bounds(source: Image) -> Rect2i:
	var left := source.get_width()
	var top := source.get_height()
	var right := -1
	var bottom := -1
	for y in source.get_height():
		for x in source.get_width():
			if source.get_pixel(x, y).a <= 0.25:
				continue
			left = mini(left, x)
			top = mini(top, y)
			right = maxi(right, x)
			bottom = maxi(bottom, y)
	if right < left:
		return Rect2i()
	return Rect2i(left, top, right - left + 1, bottom - top + 1)

func _tint(frame: Image, state: int) -> void:
	for y in SIDE:
		for x in SIDE:
			var color := frame.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			if state == 1:
				var alpha := color.a
				color = color.lerp(Color.WHITE, 0.56)
				color.a = alpha
			else:
				var gray: float = (color.r * 0.299 + color.g * 0.587 + color.b * 0.114) * 0.48
				color = Color(gray, gray, gray, color.a)
			frame.set_pixel(x, y, color)
