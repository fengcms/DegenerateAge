extends SceneTree
## 按每只怪物的 directional_preview.json 烘焙八方向试玩图集。
## 命令：godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_spirit_larva

var monster_id := "c2_spirit_larva"
var side := 80
var foot_y := 64
var max_width := 70
var max_height := 58
var source_dir := ""
var output_path := ""
var directions: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="):
			monster_id = arg.trim_prefix("--id=")
	var result := _build()
	quit(0 if result else 1)

func _build() -> bool:
	if not _read_config():
		return false
	var atlas := Image.create_empty(side * 3, side * 8, false, Image.FORMAT_RGBA8)
	for row in 8:
		var pose := _load_pose(row)
		if pose == null:
			return false
		for state in 3:
			var frame := pose.duplicate()
			if state > 0:
				_tint(frame, state)
			atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(state * side, row * side))
	var status := atlas.save_png(ProjectSettings.globalize_path(output_path))
	if status != OK:
		push_error("无法保存方向试玩图集：%s" % status)
		return false
	print("%s 方向试玩图集：%s（%s×%s）" % [monster_id, output_path, atlas.get_width(), atlas.get_height()])
	return true

func _read_config() -> bool:
	if monster_id.length() < 4 or not monster_id.begins_with("c") or not monster_id[1].is_valid_int() or monster_id.contains("/") or monster_id.contains(".."):
		push_error("无效怪物 ID：%s" % monster_id)
		return false
	source_dir = "res://art_source/chapters/ch%02d/monsters/%s/" % [int(monster_id[1]), monster_id]
	output_path = "res://assets/sprites/monsters/%s/directional_preview_atlas.png" % monster_id
	var file := FileAccess.open(source_dir + "directional_preview.json", FileAccess.READ)
	if file == null:
		push_error("缺少方向清单：%s" % source_dir)
		return false
	var config: Variant = JSON.parse_string(file.get_as_text())
	if not config is Dictionary or String(config.get("id", "")) != monster_id:
		push_error("方向清单 ID 错误：%s" % monster_id)
		return false
	side = int(config.get("side", 0))
	foot_y = int(config.get("foot_y", 0))
	max_width = int(config.get("max_width", 0))
	max_height = int(config.get("max_height", 0))
	directions = config.get("directions", [])
	if not (side in [80, 112, 192]) or foot_y <= 0 or foot_y >= side or max_width <= 0 or max_width > side or max_height <= 0 or max_height > foot_y or directions.size() != 7:
		push_error("方向清单尺寸或方向数量错误：%s" % monster_id)
		return false
	for filename in directions:
		if not filename is String or not filename.ends_with(".png") or filename.contains("/") or filename.contains(".."):
			push_error("方向文件名错误：%s" % filename)
			return false
	return true

func _load_pose(row: int) -> Image:
	if row == 7:
		var old := Image.load_from_file("res://assets/sprites/monsters/%s/simplified_atlas.png" % monster_id)
		if old == null or old.get_width() < side or old.get_height() != side:
			push_error("东南向旧图缺失或尺寸错误")
			return null
		return old.get_region(Rect2i(0, 0, side, side))
	var source := Image.load_from_file(source_dir + String(directions[row]))
	if source == null or source.is_empty():
		push_error("方向候选缺失：%s" % directions[row])
		return null
	source.convert(Image.FORMAT_RGBA8)
	var bounds := _visible_bounds(source)
	if bounds.size == Vector2i.ZERO:
		push_error("方向候选为空：%s" % directions[row])
		return null
	var body := source.get_region(bounds)
	var ratio: float = minf(float(max_width) / body.get_width(), float(max_height) / body.get_height())
	body.resize(maxi(1, roundi(body.get_width() * ratio)), maxi(1, roundi(body.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	var frame := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	frame.blit_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), Vector2i((side - body.get_width()) / 2, foot_y - body.get_height()))
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
	for y in side:
		for x in side:
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
