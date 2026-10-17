extends SceneTree
## 正式怪物分层源稿离线烘焙器：以八向透明部件与逐帧姿势表生成状态图集。
## 用法：godot --headless --path . --script tools/bake_monster_layered_animation.gd -- <rig.json>。
## 只读取 art_source 中的源层，输出到同目录的 animations_v1；不修改游戏数据或外观档案。

const DIRECTIONS := ["s", "sw", "w", "nw", "n", "ne", "e", "se"]
const REQUIRED := ["idle", "attack", "hit", "death"]

## 读取命令行参数并执行一次离线烘焙；任何坏源层都以非零退出码阻止登记。
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("用法：-- <rig.json>")
		quit(2)
		return
	var error := _bake(String(args[0]))
	quit(0 if error.is_empty() else 1)
	if not error.is_empty():
		printerr(error)

## 验证源稿契约，逐状态和方向合成固定帧画布；成功才写图集和元数据。
func _bake(rig_path: String) -> String:
	var file := FileAccess.open(rig_path, FileAccess.READ)
	if file == null:
		return "找不到分层源稿：" + rig_path
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return "源稿不是 JSON 对象：" + rig_path
	var rig: Dictionary = parsed
	var id := String(rig.get("id", ""))
	if not id.is_valid_identifier() or id.contains("/"):
		return "无效怪物 ID：" + id
	var size_data: Variant = rig.get("frame_size", [])
	var pivot_data: Variant = rig.get("pivot", [])
	if not size_data is Array or size_data.size() != 2 or not pivot_data is Array or pivot_data.size() != 2:
		return "帧尺寸或脚底锚点必须是两个整数"
	for value: Variant in size_data + pivot_data:
		if not _is_integer_number(value):
			return "帧尺寸与脚底锚点必须是整数像素"
	var frame_size := Vector2i(int(size_data[0]), int(size_data[1]))
	var pivot := Vector2i(int(pivot_data[0]), int(pivot_data[1]))
	if frame_size.x <= 0 or frame_size.y <= 0 or pivot.x < 0 or pivot.y < 0 or pivot.x >= frame_size.x or pivot.y >= frame_size.y:
		return "帧尺寸或脚底锚点超出画布"
	if rig.get("directions", []) != DIRECTIONS:
		return "方向顺序必须是 s/sw/w/nw/n/ne/e/se"
	var layer_order: Variant = rig.get("layer_order", [])
	var states: Variant = rig.get("states", {})
	if not layer_order is Array or layer_order.is_empty() or not states is Dictionary:
		return "缺少部件层序或状态表"
	var unique_layers := {}
	for raw_layer: Variant in layer_order:
		var layer_name := String(raw_layer)
		if not layer_name.is_valid_identifier() or unique_layers.has(layer_name):
			return "部件名称无效或重复：" + layer_name
		unique_layers[layer_name] = true
	for required: String in REQUIRED:
		if not states.has(required):
			return "缺少基础状态：" + required
	var source_dir := rig_path.get_base_dir()
	var output_dir := source_dir.path_join("animations_v1")
	var metadata := {"id": id, "frame_size": size_data, "pivot": pivot_data, "directions": DIRECTIONS, "states": {}}
	var layers: Dictionary = {}
	var generated_atlases: Dictionary = {}
	for state: String in states:
		if not state.is_valid_identifier():
			return "状态名称无效：" + state
		var spec: Variant = states[state]
		if not spec is Dictionary:
			return "状态不是对象：" + state
		var frames: Variant = spec.get("frames", [])
		var fps := float(spec.get("fps", 0.0))
		var contact := int(spec.get("visual_contact_frame", 0))
		if not frames is Array or frames.is_empty() or fps <= 0.0 or not spec.get("loop", null) is bool or contact < 0 or contact >= frames.size():
			return "状态帧数、FPS、循环或接触帧错误：" + state
		var atlas := Image.create_empty(frame_size.x * frames.size(), frame_size.y * 8, false, Image.FORMAT_RGBA8)
		atlas.fill(Color.TRANSPARENT)
		for direction_index in range(8):
			var direction: String = DIRECTIONS[direction_index]
			for frame_index in range(frames.size()):
				var pose: Variant = frames[frame_index]
				if not pose is Dictionary:
					return "%s 第 %d 帧不是姿势对象" % [state, frame_index]
				var frame := Image.create_empty(frame_size.x, frame_size.y, false, Image.FORMAT_RGBA8)
				frame.fill(Color.TRANSPARENT)
				var parts: Variant = (pose as Dictionary).get("parts", {})
				if not parts is Dictionary:
					return "%s 第 %d 帧部件表错误" % [state, frame_index]
				for part_name: Variant in (parts as Dictionary):
					if not unique_layers.has(String(part_name)):
						return "姿势引用了未登记部件：" + String(part_name)
				for layer_name: Variant in layer_order:
					var layer := String(layer_name)
					var transform: Variant = (parts as Dictionary).get(layer, {})
					if not transform is Dictionary:
						return "部件姿势错误：" + layer
					if not bool((transform as Dictionary).get("visible", true)):
						continue
					var variant := String((transform as Dictionary).get("variant", "base"))
					if not variant.is_valid_identifier():
						return "部件变体名无效：" + variant
					var offset: Variant = (transform as Dictionary).get("offset", [0, 0])
					if not offset is Array or offset.size() != 2 or not _is_integer_number(offset[0]) or not _is_integer_number(offset[1]):
						return "部件偏移必须是像素坐标：" + layer
					var layer_path := source_dir.path_join("directions").path_join(direction).path_join(layer + "__" + variant + ".png")
					if not layers.has(layer_path):
						if not FileAccess.file_exists(layer_path):
							return "部件 PNG 缺失：" + layer_path
						var loaded := Image.load_from_file(layer_path)
						if loaded == null or loaded.is_empty() or loaded.get_size() != frame_size:
							return "部件 PNG 缺失或尺寸错误：" + layer_path
						loaded.convert(Image.FORMAT_RGBA8)
						if not _has_clear_border(loaded):
							return "部件 PNG 外沿不透明：" + layer_path
						layers[layer_path] = loaded
					var source: Image = layers[layer_path]
					frame.blend_rect(source, Rect2i(Vector2i.ZERO, frame_size), Vector2i(int(offset[0]), int(offset[1])))
				atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, frame_size), Vector2i(frame_index * frame_size.x, direction_index * frame_size.y))
		var output := output_dir.path_join(state + "_atlas.png")
		generated_atlases[output] = atlas
		metadata.states[state] = {"frames_per_direction": frames.size(), "fps": fps, "loop": spec.loop, "visual_contact_frame": contact}
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		return "不能创建输出目录：" + output_dir
	for output: String in generated_atlases:
		var atlas: Image = generated_atlases[output]
		if atlas.save_png(output) != OK:
			return "不能保存状态图集：" + output
	var output_meta := FileAccess.open(output_dir.path_join("animation.json"), FileAccess.WRITE)
	if output_meta == null:
		return "不能保存动画元数据"
	output_meta.store_string(JSON.stringify(metadata, "  ") + "\n")
	print("[MonsterLayerBaker] 完成：%s，%d 状态，%d 个源层变体" % [id, states.size(), layers.size()])
	return ""

## 拦截带色块背景的候选图；允许 1/20 的边缘透明误差，防止轻微采样噪声误报。
func _has_clear_border(image: Image) -> bool:
	var width := image.get_width()
	var height := image.get_height()
	for x in range(width):
		if image.get_pixel(x, 0).a > 0.05 or image.get_pixel(x, height - 1).a > 0.05:
			return false
	for y in range(height):
		if image.get_pixel(0, y).a > 0.05 or image.get_pixel(width - 1, y).a > 0.05:
			return false
	return true

## Godot 的 JSON 数字会读成浮点；只接受数学上的整数像素，不截断小数坐标。
func _is_integer_number(value: Variant) -> bool:
	if not value is int and not value is float:
		return false
	return float(value) == float(int(value))
