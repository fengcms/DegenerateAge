class_name GroundLootVisualCache
extends RefCounted
## 高密度静止装备的共享表现缓存：原画法离屏合成，保留节点、交互和奖励，不重排绘制顺序。
## 最多128种128×160纹理（约10MiB RGBA），仅实际窗口启用；缺图或预算满回退原画法。
const THRESHOLD := 256
const LIMIT := 128
const SIZE := Vector2i(128,160)
const ORIGIN := Vector2(64,112)
static var _textures: Dictionary = {}
static var _pending: Dictionary = {}
static var _jobs: Array[Dictionary] = []
static var _worker_pending := false
static var _frame := -1
static var _scene_id := 0
static var _dense := false
static var _connected := false

## 同帧共享一次密度查询，不让每件物品重复收集全场节点。
static func dense(tree: SceneTree) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var frame := Engine.get_process_frames()
	var scene_id := tree.current_scene.get_instance_id() if tree.current_scene != null else 0
	if frame != _frame or scene_id != _scene_id:
		_frame = frame
		_scene_id = scene_id
		_dense = tree.get_nodes_in_group("ground_items").size() >= THRESHOLD
	return _dense

## 依模板、品质、持久标记和数据版本复用原表现；只在缓存缺失时排一个离屏任务。
static func texture_for(item: Dictionary, persistent: bool, tree: SceneTree) -> Texture2D:
	if not _connected:
		_connected = true
		EventBus.data_loaded.connect(_invalidate)
	if SampleArt.ground_for(item) == null:
		return null
	var key := "%s:%s:%s:%d" % [String(item.get("itemId","")),ItemUtil.quality_of(item),str(persistent),DataLoader.revision]
	if _textures.has(key):
		return _textures[key]
	if not _pending.has(key) and _textures.size() + _pending.size() < LIMIT:
		_pending[key] = true
		_jobs.append({"key":key,"item":item.duplicate(true),"persistent":persistent,"revision":DataLoader.revision})
		if not _worker_pending:
			_worker_pending = true
			_start_worker.call_deferred(tree)
	return null

## 规则/素材重载时丢弃旧版本队列，节点会按版本变化释放自身引用并恢复原画法。
static func _invalidate() -> void:
	_textures.clear()
	_pending.clear()
	_jobs.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		# 重载是低频事件，即便世界暂停也重绘一次，释放节点持有的旧版本图像。
		for node in tree.get_nodes_in_group("ground_items"):
			if node is CanvasItem:
				node.queue_redraw()

## 延后挂载短生命周期工作节点，避免在绘制回调或场景装配期间直接修改根节点。
static func _start_worker(tree: SceneTree) -> void:
	if not is_instance_valid(tree) or tree.root == null:
		_jobs.clear()
		_pending.clear()
		_worker_pending = false
		return
	var worker := Worker.new()
	worker.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(worker)

class Worker extends Node:
	## 每次只处理一张，完成后释放离屏节点；正常游戏没有常驻缓存处理循环。
	func _ready() -> void:
		while not GroundLootVisualCache._jobs.is_empty():
			var job: Dictionary = GroundLootVisualCache._jobs.pop_front()
			var viewport := SubViewport.new()
			viewport.size = GroundLootVisualCache.SIZE
			viewport.transparent_bg = true
			viewport.world_2d = World2D.new()
			viewport.disable_3d = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			add_child(viewport)
			# 动态挂原脚本，避开类解析循环；源节点在_ready中跳过全部玩法注册。
			var source := Node2D.new()
			source.set_script(load("res://scripts/entities/ground_item.gd"))
			source.set("_bake_source",true)
			source.set("item",job.item)
			source.set("persistent",job.persistent)
			source.set("batch_size",100)
			source.set("_spawn_t",9999.0)
			source.position = GroundLootVisualCache.ORIGIN
			source.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			viewport.add_child(source)
			await RenderingServer.frame_post_draw
			if int(job.revision) != DataLoader.revision:
				viewport.queue_free()
				GroundLootVisualCache._pending.erase(job.key)
				await get_tree().process_frame
				continue
			var image := viewport.get_texture().get_image()
			if image == null or image.is_empty() or not image.get_used_rect().has_area():
				# 窗口不可绘制时不得缓存空图，保留原画法等待下一次有效绘制。
				GroundLootVisualCache._pending.erase(job.key)
				viewport.queue_free()
				await get_tree().process_frame
				continue
			var used := image.get_used_rect()
			image = image.get_region(used)
			# 透明离屏结果为预乘alpha，转回普通纹理，避免二次混合使光柱变暗。
			image.convert(Image.FORMAT_RGBA8)
			var bytes := image.get_data()
			for i in range(0,bytes.size(),4):
				var alpha := int(bytes[i+3])
				if alpha > 0 and alpha < 255:
					for channel in range(3):
						bytes[i+channel] = mini(255,roundi(float(bytes[i+channel])*255.0/alpha))
			image.set_data(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8,bytes)
			var texture := ImageTexture.create_from_image(image)
			texture.set_meta("loot_offset",Vector2(used.position)-GroundLootVisualCache.ORIGIN)
			GroundLootVisualCache._textures[job.key] = texture
			GroundLootVisualCache._pending.erase(job.key)
			viewport.queue_free()
			await get_tree().process_frame
		GroundLootVisualCache._worker_pending = false
		queue_free()
