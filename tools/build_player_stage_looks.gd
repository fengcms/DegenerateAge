extends SceneTree
## 将 look_02—look_06 已审定的八向关键姿态源稿装配为游戏帧格。
## 原稿放 art_source，运行时仅载入本工具输出的 64×80 图集。
## 用法：Godot --headless --path . --script tools/build_player_stage_looks.gd

const CELL := Vector2i(64, 80)
const PIVOT := Vector2i(32, 64)
const LOOK_IDS := ["02", "03", "04", "05", "06"]
const STATES := {"idle": 4, "walk": 8, "attack": 6, "hit": 2, "death": 6, "sit": 4}
const SOURCE_NAMES := {
	"idle": "idle_8dir_master.png",
	"walk": "walk_8dir_4pose_master.png",
	"attack": "attack_contact_8dir_master.png",
	"followthrough": "attack_followthrough_8dir_master.png",
	"other": "hit_sit_death_8dir_master.png",
}

func _initialize() -> void:
	for look_id in LOOK_IDS:
		_build_look(look_id)
	quit()

func _build_look(look_id: String) -> void:
	var source_dir := "res://art_source/player/look_%s/" % look_id
	var output_dir := "res://assets/sprites/player/stage_looks/look_%s/" % look_id
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) == OK)
	var idle := _load_cells(source_dir + SOURCE_NAMES.idle, 1)
	var walk := _load_cells(source_dir + SOURCE_NAMES.walk, 4)
	var attack := _load_cells(source_dir + SOURCE_NAMES.attack, 1)
	var followthrough := _load_cells(source_dir + SOURCE_NAMES.followthrough, 1)
	var other := _load_cells(source_dir + SOURCE_NAMES.other, 3)
	for state in STATES:
		var atlas := Image.create(CELL.x * 8, CELL.y * STATES[state], false, Image.FORMAT_RGBA8)
		atlas.fill(Color.TRANSPARENT)
		for frame in range(STATES[state]):
			for direction in range(8):
				var source: Image
				var height := 48
				var width := 60
				var bob := 0
				match state:
					"idle":
						source = idle[direction]
						bob = [0, -1, -2, -1][frame]
					"walk":
						# 第六档原稿第四行脚部被生图画布截断，复用第二步的完整姿势。
						var source_row := frame % 4
						if look_id == "06" and source_row == 3:
							source_row = 1
						source = walk[source_row * 8 + direction]
						bob = [0, -1, 0, -1, 0, -1, 0, -1][frame]
					"attack":
						source = attack[direction] if frame <= 1 else followthrough[direction] if frame <= 3 else idle[direction]
						bob = [0, -1, 0, 1, 0, 0][frame]
						width = 62
						height = 52
						# 命中发生于第 0 帧；后续为接触保持和收势。
					"hit":
						source = other[direction] if frame == 0 else idle[direction]
						bob = 1 if frame == 0 else 0
					"death":
						source = other[direction] if frame <= 1 else other[16 + direction]
						height = 48 if frame <= 1 else 30
						bob = 0
					"sit":
						source = other[8 + direction]
						height = 34
						bob = [0, -1, -1, 0][frame]
				_put(atlas, source, frame, direction, width, height, bob)
		var path := output_dir + "look_%s_%s_atlas.png" % [look_id, state]
		assert(atlas.save_png(path) == OK, "保存失败：%s" % path)
		print("[StageLookBuild] ", look_id, " ", state, " ", atlas.get_size())

func _load_cells(path: String, rows: int) -> Array[Image]:
	var source := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert(source != null, "源稿缺失：%s" % path)
	source.convert(Image.FORMAT_RGBA8)
	var pieces: Array[Image] = []
	for row in range(rows):
		for direction in range(8):
			var x0 := roundi(float(direction) * source.get_width() / 8.0)
			var x1 := roundi(float(direction + 1) * source.get_width() / 8.0)
			var y0 := roundi(float(row) * source.get_height() / float(rows))
			var y1 := roundi(float(row + 1) * source.get_height() / float(rows))
			var piece := source.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
			# 生成源稿含低透明边缘杂点；保留实像素并清掉半透明噪点。
			for y in range(piece.get_height()):
				for x in range(piece.get_width()):
					var color := piece.get_pixel(x, y)
					if color.a < 0.6:
						piece.set_pixel(x, y, Color.TRANSPARENT)
			var bounds := piece.get_used_rect()
			assert(bounds.size.x > 0 and bounds.size.y > 0, "动作格缺失：%s/%d/%d" % [path, row, direction])
			pieces.append(piece.get_region(bounds))
	return pieces

func _put(atlas: Image, piece: Image, row: int, direction: int, max_width: int, max_height: int, bob: int) -> void:
	var frame := piece.duplicate() as Image
	var factor := minf(float(max_width) / float(frame.get_width()), float(max_height) / float(frame.get_height()))
	frame.resize(maxi(1, roundi(frame.get_width() * factor)), maxi(1, roundi(frame.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	var x := direction * CELL.x + PIVOT.x - frame.get_width() / 2
	var y := row * CELL.y + PIVOT.y - frame.get_height() + bob
	assert(x >= direction * CELL.x and x + frame.get_width() <= (direction + 1) * CELL.x, "横向出格")
	assert(y >= row * CELL.y and y + frame.get_height() <= (row + 1) * CELL.y, "纵向出格")
	atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(x, y))
