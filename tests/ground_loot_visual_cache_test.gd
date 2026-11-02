extends Node
## 实际窗口验证原画法与高密度缓存的像素一致性，以及缓存不接管奖励和节点。

## 等待离屏缓存完成并比较两个同样位置的原始/缓存静止物品。
func _ready() -> void:
	assert(DisplayServer.get_name() != "headless", "此用例必须实际窗口")
	for i in range(GroundLootVisualCache.THRESHOLD):
		var marker := Node.new()
		add_child(marker)
		marker.add_to_group("ground_items")
	GameState.reset_to_defaults()
	for persistent in [false,true]:
		await compare_visual(persistent)
	DataLoader.revision += 1
	EventBus.data_loaded.emit()
	assert(GroundLootVisualCache._textures.is_empty(), "数据重载释放旧版本缓存")
	print("[GroundLootVisualCacheTest] PASS")
	get_tree().quit()

## 逐像素对照普通与持久装备，保持原始透明层、光柱和未领取双环。
func compare_visual(persistent: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var item := ItemFactory.make_equip_exact("c6_equip_weapon",500,"legendary",rng)
	var original := GroundItem.new()
	original._bake_source = true
	original.item = item.duplicate(true)
	original.batch_size = 100
	original.persistent = persistent
	original._spawn_t = 9999.0
	original.position = Vector2(200,200)
	original.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(original)
	var cached := GroundItem.new()
	cached.item = item.duplicate(true)
	cached.batch_size = 100
	cached.persistent = persistent
	cached.position = Vector2(500,200)
	add_child(cached)
	cached.set_physics_process(false)
	cached._spawn_t = 9999.0
	for i in range(60):
		cached.queue_redraw()
		await get_tree().process_frame
	assert(cached._cached_drawn and not cached.is_claimed(), "缓存就绪且没有认领奖励")
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	var bad := 0
	for y in range(160):
		for x in range(128):
			var a := image.get_pixel(x+136,y+88)
			var b := image.get_pixel(x+436,y+88)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.12:
				bad += 1
	print("[PERF] cached_visual persistent=",persistent," difference_pixels=",bad)
	assert(bad < 100, "原画法与合成结果应一致：差异像素%d" % bad)
	assert(GroundLootVisualCache._textures.size() <= GroundLootVisualCache.LIMIT)
	assert(get_tree().get_nodes_in_group("ground_items").size() == GroundLootVisualCache.THRESHOLD+1, "离屏源不加入拾取组")
	assert(GameState.unclaimed_count(GameState.current_map) == (1 if persistent else 0), "离屏源不重复登记奖励")
	image.save_png("/tmp/ground_loot_visual_cache.png")
	original.free()
	cached.free()
	GameState.unclaimed_loot = {}
