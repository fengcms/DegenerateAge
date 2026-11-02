extends Node
## 自动失败重试契约：状态不变只尝试一次，事件后恢复，手动入口不受缓存阻挡。
class Probe extends GroundItem:
	var attempts := 0
	var succeeds := false
	var player_queries := 0
	var probe_player: Node2D
	## 记录自动物理入口是否仍查找玩家，避免仅测交易缓存却漏掉前置空转。
	func _get_player() -> Node2D:
		player_queries += 1
		return probe_player
	## 只统计交易入口调用，避免测试本身依赖掉落动画和随机装备。
	func _try_pickup(_announce: bool = true, _quiet: bool = false) -> bool:
		attempts += 1
		return succeeds

## 验证事件失效与手动例外，不读写真实存档。
func _ready() -> void:
	var item := Probe.new()
	item.item = {"kind":"equip"}
	for i in range(1000):
		assert(not item._try_auto_pickup())
	assert(item.attempts == 1)
	item._try_pickup()
	assert(item.attempts == 2, "手动点击仍立即进入原交易")
	EventBus.inventory_changed.emit()
	item.succeeds = true
	assert(item._try_auto_pickup() and item.attempts == 3, "腾格后立即恢复")
	item.succeeds = false
	for event in [EventBus.equipment_changed,EventBus.settings_changed,EventBus.data_loaded]:
		event.emit()
		var before := item.attempts
		item._try_auto_pickup()
		assert(item.attempts == before + 1)
	var before_gold := item.attempts
	EventBus.gold_changed.emit(1)
	item._try_auto_pickup()
	assert(item.attempts == before_gold, "普通金币入账不唤醒全部满包失败物")
	GameState.gold = GameState.GOLD_CAP
	EventBus.gold_changed.emit(GameState.gold)
	item._try_auto_pickup()
	assert(item.attempts == before_gold + 1, "金币封顶改变出售条件时重试")
	item.item = {"kind":"coin"}
	var before := item.attempts
	item._try_auto_pickup()
	item._try_auto_pickup()
	assert(item.attempts == before + 2, "金币不被背包失败结论阻挡")
	GameState.set_auto_pickup(true)
	item.item = {"kind":"equip"}
	item._try_auto_pickup()
	item._range_t = 1000.0
	item._spawn_t = 10.0
	item.probe_player = Node2D.new()
	add_child(item.probe_player)
	add_child(item)
	item.set_physics_process(false)
	item._range_t = 1000.0
	var queries_before := item.player_queries
	for i in range(1000):
		item._physics_process(0.016)
	assert(item.player_queries == queries_before, "同状态失败掉落不再逐帧查询玩家")
	EventBus.inventory_changed.emit()
	item.succeeds = true
	item._physics_process(0.016)
	assert(item.player_queries == queries_before+1 and item.is_claimed(), "腾格后下一物理步恢复附近认领")
	item.probe_player.free()
	item.free()
	GameState.reset_to_defaults()
	GameState.inventory = Inventory.create(1)
	GameState.inventory[0] = ItemFactory.make_any("potion_hp_small",998)
	var potion := GroundItem.new()
	potion.item = ItemFactory.make_any("potion_hp_small",1)
	assert(potion._try_auto_pickup(false,true), "满格仍可叠加到999")
	assert(GameState.inventory[0].count == 999)
	potion.free()
	var visual := GroundItem.new()
	visual._spawn_t = 10.0
	visual._near_anim = true
	visual._redraw_t = 0.2
	visual._range_t = 0.3
	var old_scale := Engine.time_scale
	Engine.time_scale = 8.0
	visual._tick_redraw(0.4)
	Engine.time_scale = old_scale
	assert(is_equal_approx(visual._redraw_t,0.15), "8倍速的0.4游戏秒仅消耗0.05现实秒表现预算")
	visual.free()
	print("[LootRetryTest] 全部通过 ✅")
	get_tree().quit()
