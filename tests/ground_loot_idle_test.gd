extends Node
## 静止调度契约：库存唤醒、走近、输入冷却与回收；用固定密度隔离渲染后端。
class Service extends GroundLootIdle:
	var dense := true
	## 测试密集状态变化，不依赖headless支持图像缓存。
	func _is_dense() -> bool:
		return dense
class Player extends Node2D:
	var is_dead := false
class Item extends GroundItem:
	var attempts := 0
	var success := false
	var attempts_by_frame: Dictionary = {}
	## 测试源不注册持久记录，真实奖励数量另由窗口压力基准检查。
	func _ready() -> void:
		set_physics_process(false)
	## 固定测试表现，避免真实绘制在无头环境把模拟缓存标记清空。
	func _draw() -> void:
		pass
	## 隔离绘制，只验证调度和原自动拾取入口。
	func _tick_redraw(_delta: float) -> void:
		pass
	## 将模板变化作为缓存失效，方便验证恢复原物理路径。
	func _cached_visual_matches() -> bool:
		return String(item.get("itemId","")) == "fixed"
	## 统计唯一交易入口调用，成功由测试显式控制。
	func _try_pickup(_announce: bool = true, _quiet: bool = false) -> bool:
		attempts += 1
		var frame := Engine.get_process_frames()
		attempts_by_frame[frame] = int(attempts_by_frame.get(frame, 0)) + 1
		return success

class Boundary extends Node:
	signal finished
	var service: Service
	var target: Item
	## 在真实物理回调中模拟物品先执行、服务后执行，验证恢复时间不重复累加本步。
	func _physics_process(delta: float) -> void:
		set_physics_process(false)
		service.game_clock = 5.0
		service._clock_frame = -1
		var before := target._spawn_t
		GroundLootIdle.park(target)
		service._physics_process(delta)
		service.wake(target)
		assert(is_equal_approx(target._spawn_t,before), "静止首步不能重复累计游戏秒")
		finished.emit()

## 共享服务每步检查库存版本，走近仅等0.1未缩放秒；输入不等待定时扫描。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.inventory = Inventory.create(1)
	GameState.inventory[0] = ItemFactory.make_any("potion_hp_small",999)
	GameState.set_auto_pickup(true)
	var player := Player.new()
	player.add_to_group("player")
	add_child(player)
	var root := Node2D.new()
	add_child(root)
	var service := Service.new()
	service.name = "GroundLootIdle"
	root.add_child(service)
	service._revision = LootRetryState.revision()
	var items: Array[Item] = []
	for i in range(24):
		var item := Item.new()
		item.item = {"kind":"equip","itemId":"fixed"}
		item.persistent = true
		item._cached_drawn = true
		item._spawn_t = 100.0
		item.position = Vector2(1000,0) if i > 0 else Vector2.ZERO
		root.add_child(item)
		item._failed_pickup_revision = LootRetryState.revision()
		GroundLootIdle.park(item)
		items.append(item)
	var old_scale := Engine.time_scale
	Engine.time_scale = 16.0
	for i in range(60):
		service._physics_process(16.0/60.0)
	assert(service._sleepers.size() == 24 and items[0].attempts == 0)
	assert(not items[0].is_physics_processing(), "静止物品没有逐帧回调")
	items[0].success = true
	GameState.inventory[0] = null # 兼容旧调用直接腾格，下一物理步也要恢复。
	service.set_physics_process(false)
	await get_tree().physics_frame
	service._physics_process(16.0/60.0)
	assert(items[0].is_claimed() and items[0].attempts == 1)
	assert(service._sleepers.size() == 23, "只唤醒附近可重试物品，实际%d" % service._sleepers.size())
	player.position = items[1].position
	service._remaining = 0.0
	items[1].success = true
	service._physics_process(16.0/60.0)
	assert(items[1].is_claimed(), "走近恢复附近拾取")
	var manual := items[2]
	manual._blocked_cd = 4.0
	service.game_clock += 5.0
	manual._on_hover(true)
	assert(manual._idle_service == null and manual.is_physics_processing())
	assert(manual._blocked_cd == 0.0, "恢复累计游戏秒冷却")
	items[3].item.itemId = "changed"
	service._remaining = 0.0
	service._physics_process(0.0)
	assert(items[3]._idle_service == null, "模板失效恢复物理表现")
	var removed_id := items[4].get_instance_id()
	items[4].free()
	assert(not service._sleepers.has(removed_id), "释放立即注销调度引用")
	service.dense = false
	service._remaining = 0.0
	service._physics_process(0.0)
	assert(service._sleepers.is_empty(), "密度降低恢复全部节点")
	var boundary_item := Item.new()
	boundary_item.item = {"kind":"equip","itemId":"fixed"}
	boundary_item._cached_drawn = true
	boundary_item._spawn_t = 100.0
	boundary_item.position = Vector2(100000,0)
	root.add_child(boundary_item)
	service.dense = true
	var boundary := Boundary.new()
	boundary.service = service
	boundary.target = boundary_item
	root.add_child(boundary)
	await boundary.finished
	await _check_pickup_budget(player)
	Engine.time_scale = old_scale
	print("[GroundLootIdleTest] PASS")
	get_tree().quit()


## 物理补步共享预算，下一显示帧继续处理上次未尝试的装备。
func _check_pickup_budget(player: Player) -> void:
	var root := Node2D.new()
	add_child(root)
	var service := Service.new()
	service.name = "GroundLootIdle"
	root.add_child(service)
	var attempts_by_frame: Dictionary = {}
	for i in range(5):
		var item := Item.new()
		item.item = {"kind": "equip", "itemId": "fixed"}
		item.position = player.position
		item.persistent = true
		item._cached_drawn = true
		item._spawn_t = 100.0
		item.success = true
		item.attempts_by_frame = attempts_by_frame
		root.add_child(item)
		GroundLootIdle.park(item)
	service.set_physics_process(false)
	for i in range(8):
		service._physics_process(16.0 / 60.0)
	assert(service._sleepers.size() == 3, "同一显示帧的物理补步最多尝试两件")
	service.set_physics_process(true)
	for i in range(30):
		if service._sleepers.is_empty():
			break
		await get_tree().process_frame
	assert(service._sleepers.is_empty(), "预算用完后继续领取，直至候选处理完")
	var attempts := 0
	for count in attempts_by_frame.values():
		assert(int(count) <= 2, "跨物理补步的单帧预算")
		attempts += int(count)
	assert(attempts == 5, "每件候选恰好领取一次")
	root.queue_free()
