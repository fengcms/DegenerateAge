class_name GroundLootIdle
extends Node
## 地图掉落根节点拥有的静止调度器；只停高密度持久装备的物理空转，不接管奖励。
## 常态每0.1未缩放秒共享玩家查询；库存版本变化下一物理步唤醒，点击/悬停立即退出静止。
const INTERVAL := 0.1
var game_clock := 0.0
var _clock_frame := -1
var _remaining := 0.0
var _revision := -1
var _sleepers: Dictionary = {}

## 在掉落父节点下按需建立一个调度器；不跨图持有物品或玩家。
static func park(item: GroundItem) -> void:
	var parent := item.get_parent()
	if parent == null:
		return
	var service := parent.get_node_or_null("GroundLootIdle") as GroundLootIdle
	if service == null:
		service = GroundLootIdle.new()
		service.name = "GroundLootIdle"
		parent.add_child(service)
	service.set_physics_process(true)
	service._sleepers[item.get_instance_id()] = item
	item._idle_service = service
	# 物品本步已累加delta；若服务排在其后，本步尚未计入共享钟，起点需抵消这一步。
	var pending_step := service.get_physics_process_delta_time() if Engine.is_in_physics_frame() and service._clock_frame != Engine.get_physics_frames() else 0.0
	item._idle_started = service.game_clock+pending_step
	item.set_physics_process(false)

## 从静止状态恢复精确累计的游戏秒；tick用于调度唤醒，输入入口仅恢复不自动抢交易。
func wake(item: GroundItem, tick: bool = false) -> void:
	_sleepers.erase(item.get_instance_id())
	if _sleepers.is_empty():
		set_physics_process(false)
	var elapsed := maxf(0.0,game_clock-item._idle_started)
	item._idle_service = null
	item._spawn_t += elapsed
	item._phase += elapsed*3.0
	item._blocked_cd = maxf(0.0,item._blocked_cd-elapsed)
	item._range_t = 0.0
	item.set_physics_process(true)
	if tick and not item.is_queued_for_deletion():
		item._physics_process(0.0)

## 节点提前释放时注销；字典只保留当前地图仍存在的物品。
func forget(item: GroundItem) -> void:
	_sleepers.erase(item.get_instance_id())
	if _sleepers.is_empty():
		set_physics_process(false)

## 共享版本/玩家查询后扫描静止装备；只恢复附近可重试、表现失效或交互中的节点。
func _physics_process(delta: float) -> void:
	game_clock += delta
	_clock_frame = Engine.get_physics_frames()
	_remaining -= delta/maxf(Engine.time_scale,0.000001)
	var revision := LootRetryState.revision()
	var changed := revision != _revision
	if not changed and _remaining > 0.0:
		return
	_revision = revision
	_remaining = INTERVAL
	var dense := _is_dense()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var can_pick: bool = player != null and player.get("is_dead") != true and GameState.auto_pickup_on
	var position: Vector2 = player.global_position if can_pick else Vector2.ZERO
	for id in _sleepers.keys():
		var item := _sleepers[id] as GroundItem
		if not is_instance_valid(item) or item.is_queued_for_deletion():
			_sleepers.erase(id)
			continue
		if not dense or not item._cached_drawn or not item._cached_visual_matches() or item._hovered:
			item._cached_drawn = false
			item.queue_redraw()
			wake(item,true)
		elif can_pick and not item.manual_only and item._failed_pickup_revision != revision \
				and position.distance_squared_to(item.global_position) <= GroundItem.PICKUP_RANGE_PX*GroundItem.PICKUP_RANGE_PX:
			wake(item,true)

## 将窗口密度判定集中一次；逻辑测试可用固定密度隔离渲染后端。
func _is_dense() -> bool:
	return GroundLootVisualCache.dense(get_tree())
