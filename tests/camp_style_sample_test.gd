extends Node
## 营地 A/B 局部样板验收：装配同一正式世界，检查纯地面透明边、分层与固定几何。
## 实际窗口模式额外按相同镜头保存 A/B、树冠和高倍率截图，不写玩家存档。

const SAMPLE := preload("res://tests/CampStyleSample.tscn")

## 运行样板事实源、透明层、样式切换和窗口截图检查；异常以断言中止。
func _ready() -> void:
	var sample := SAMPLE.instantiate()
	add_child(sample)
	await get_tree().physics_frame
	assert(sample.ground.get_world_bounds().size == Vector2(3200, 1800), "样板改变了营地尺寸")
	var layout: Dictionary = sample.ground._camp_whitebox
	var solids := (layout["entities"] as Array).size() + (layout["fences"] as Array).size()
	assert(solids == 22 and sample.ground.get_node("CaveWalls").get_child_count() == solids,
		"样板必须继续使用原有整体障碍")
	assert(sample.world.get_node("Npcs").get_child_count() == 5,
		"样板必须保留正式 NPC 位置与数量")
	var scanned: Dictionary = _scan_solid_supports(sample)
	print("[PERF] 样板逐格承重区复核：", scanned)
	for style in ["a", "b"]:
		var layer := sample._styles[style] as Node2D
		assert(layer.get_node("ground") != null, "样板纯地面层缺失")
		for id in ["blacksmith", "merchant", "elder_tree"]:
			assert(layer.get_node(id + "_back") != null and layer.get_node(id + "_front") != null,
				"整体实体缺少背层或前沿遮挡：%s/%s" % [style, id])
			_check_split_alpha(style, id)
		var image := Image.new()
		assert(image.load("res://assets/maps/camp_style_sample/%s/ground.png" % style) == OK,
			"样板地面图片不可读")
		assert(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(image.get_width() / 2,
			image.get_height() / 2).a > 0.98, "地面局部边缘必须真正透明")
		sample._show_style(style)
		assert((sample._styles[style] as Node2D).visible, "样式切换未生效")
	for zoom in [1.0, 1.5, 2.0]:
		sample._set_zoom(zoom)
		assert(is_equal_approx(sample.camera.zoom.x, zoom), "地图倍率不正确")
	for focus in ["blacksmith", "elder_tree", "western_rocks", "northwest_palisade"]:
		sample._focus(focus)
		assert(sample.ground.cave.is_walkable(Vector2i(Iso.world_to_grid(sample.player.global_position).round())),
			"观察点不应落在障碍内：%s" % focus)
	if DisplayServer.get_name() != "headless":
		if OS.get_environment("DEGENERATEAGE_SAMPLE_HIDPI") == "1":
			DisplayServer.window_set_size(Vector2i(2560, 1600))
			await _save_view(sample, "a", "blacksmith", 1.0, "camp_style_a_hidpi")
			await _save_view(sample, "b", "blacksmith", 1.0, "camp_style_b_hidpi")
			await _save_view(sample, "b", "blacksmith", 2.0, "camp_style_b_hidpi_200")
			print("[PERF] 高分辨率视口：", get_viewport().get_visible_rect().size,
				" / 屏幕倍率：", DisplayServer.screen_get_scale())
		else:
			await _save_view(sample, "a", "blacksmith", 1.0, "camp_style_a_blacksmith")
			await _save_view(sample, "b", "blacksmith", 1.0, "camp_style_b_blacksmith")
			await _save_view(sample, "a", "blacksmith", 1.5, "camp_style_a_blacksmith_150")
			await _save_view(sample, "b", "blacksmith", 1.5, "camp_style_b_blacksmith_150")
			await _save_view(sample, "a", "blacksmith", 2.0, "camp_style_a_blacksmith_200")
			await _save_view(sample, "b", "blacksmith", 2.0, "camp_style_b_blacksmith_200")
			await _save_view(sample, "b", "elder_tree", 1.5, "camp_style_b_tree")
			await _save_view(sample, "b", "western_rocks", 1.5, "camp_style_b_rocks")
			await _save_view(sample, "b", "northwest_palisade", 1.5, "camp_style_b_fence")
			await _save_occlusion(sample, "blacksmith", [300, 173], "camp_style_b_roof_occlusion")
			await _save_occlusion(sample, "elder_tree", [1050, 340], "camp_style_b_canopy_occlusion")
	print("[CampStyleSampleTest] PASS · A/B 同场景分层与固定障碍通过")
	get_tree().quit()

## 逐格核对样板中五个立体物体的承重区，须完全落在既有不可走掩码。
## 屋檐、树冠等非承重外伸部分允许覆盖可走格，由前沿层负责遮挡。
func _scan_solid_supports(sample: Node2D) -> Dictionary:
	var supports := {
		"blacksmith": [[240, 205], [510, 205], [520, 285], [245, 295]],
		"merchant": [[320, 447], [595, 447], [600, 465], [320, 470]],
		"elder_tree": [[1063, 388], [1084, 388], [1090, 405], [1063, 408]],
		"northwest_palisade": [[10, 104], [220, 92], [520, 106], [740, 100], [740, 104], [520, 111], [220, 99], [10, 113]],
		"western_rocks": [[6, 470], [25, 470], [75, 695], [45, 800], [6, 830]],
	}
	var totals: Dictionary = {}
	for id: String in supports:
		var polygon := PackedVector2Array()
		for point: Array in supports[id]:
			polygon.append(sample._canvas_to_world(point))
		var tested := 0
		for y in range(sample.ground.grid_size.y):
			for x in range(sample.ground.grid_size.x):
				var cell := Vector2i(x, y)
				if not Geometry2D.is_point_in_polygon(Iso.grid_to_world(cell), polygon):
					continue
				tested += 1
				assert(not sample.ground.cave.is_walkable(cell),
					"立体承重区落在可走格：%s/%s" % [id, cell])
		assert(tested > 0, "承重区未覆盖任何网格中心：%s" % id)
		totals[id] = tested
	return totals

## 检查实体背层与前沿贴图像素互斥，避免同一屋顶或树冠被重复绘制。
func _check_split_alpha(style: String, id: String) -> void:
	var back := Image.new()
	var front := Image.new()
	assert(back.load("res://assets/maps/camp_style_sample/%s/%s_back.png" % [style, id]) == OK)
	assert(front.load("res://assets/maps/camp_style_sample/%s/%s_front.png" % [style, id]) == OK)
	assert(back.get_size() == front.get_size(), "实体分层像素尺寸不同：%s/%s" % [style, id])
	for y in range(back.get_height()):
		for x in range(back.get_width()):
			assert(back.get_pixel(x, y).a * front.get_pixel(x, y).a < 0.001,
				"实体背层与前沿像素重复：%s/%s" % [style, id])

## 以相同倍率和观察点截图，供人工比较清晰度、遮挡与人物可读性。
func _save_view(sample: Node2D, style: String, focus: String, zoom: float, file_name: String) -> void:
	sample._show_style(style)
	sample._focus(focus)
	sample._set_zoom(zoom)
	sample._help.visible = false
	for _frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("/tmp/%s.png" % file_name) == OK,
		"样板窗口截图失败：%s" % file_name)

## 把真实玩家移到可走的屋檐/树冠后方，验证前沿遮挡与角色排序。
func _save_occlusion(sample: Node2D, focus: String, raw: Array, file_name: String) -> void:
	sample._show_style("b")
	sample._focus(focus)
	sample._set_zoom(1.5)
	var target: Vector2 = sample.ground.clamp_to_map(sample._canvas_to_world(raw))
	assert(target.distance_to(sample._canvas_to_world(raw)) < 50.0,
		"遮挡观察点被现有障碍推离太远：%s" % focus)
	sample.player.global_position = target
	sample.camera.reset_smoothing()
	sample._help.visible = false
	for _frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("/tmp/%s.png" % file_name) == OK,
		"遮挡截图失败：%s" % file_name)
