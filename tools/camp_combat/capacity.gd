extends "res://tools/camp_combat/main.gd"
## 满背包真实掉落验收：以隔离填充物占满40格，正式击杀后验证不吞奖励，腾格后自动恢复。

## 完成真实战斗、满包保留与事件触发重拾；不直接调用拾取或替怪物伪造奖励。
func _run_verification() -> void:
	GameState.settings.autoSellEquipOnPickup = false
	for index in range(GameState.inventory.size()):
		GameState.inventory[index] = ItemFactory.make_any("potion_hp_small",999)
	EventBus.inventory_changed.emit()
	assert(Inventory.is_full(GameState.inventory))
	GameState.set_auto_battle(true)
	var deadline := Time.get_ticks_msec()+90000
	while kills<2 and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		assert(not hero.is_dead)
	assert(kills==2)
	await get_tree().create_timer(4.0).timeout
	assert(GameState.gold>0,"满包不应阻止金币入账")
	assert(pickups==0 and Inventory.used_slots(GameState.inventory)==40,"满包时非金币物品被错误入账")
	var expected: Dictionary = {}
	var claim_ids: Array[String] = []
	var preserved_count := 0
	for node in get_tree().get_nodes_in_group("ground_items"):
		var drop := node as GroundItem
		if drop==null or drop.is_claimed():
			continue
		assert(not drop.item.is_empty(),"满包奖励为空")
		if drop.persistent:
			assert(not drop.claim_uid.is_empty(),"持久掉落未登记记录")
			claim_ids.append(drop.claim_uid)
		_add_count(expected,drop.item)
		preserved_count += 1
	assert(not expected.is_empty(),"未产生非金币掉落，不能证明满包保留")
	var remaining := GameState.unclaimed_count(GameState.current_map)
	await get_tree().create_timer(5.0).timeout
	assert(GameState.unclaimed_count(GameState.current_map)==remaining,"满包等待期间持久奖励记录丢失")
	var observed: Dictionary = {}
	for node in get_tree().get_nodes_in_group("ground_items"):
		if node is GroundItem and not node.is_claimed():
			_add_count(observed,node.item)
	assert(observed==expected,"满包等待期间普通掉落丢失")
	# 只移走测试预填充物，真实掉落仍由原实体与原拾取入口处理。
	GameState.inventory = Inventory.create(GameState.INVENTORY_SIZE)
	EventBus.inventory_changed.emit()
	deadline = Time.get_ticks_msec()+30000
	while get_tree().get_nodes_in_group("ground_items").size()>0 and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
	assert(get_tree().get_nodes_in_group("ground_items").is_empty(),"腾格后正式自动拾取未恢复")
	var actual: Dictionary = {}
	for item in GameState.inventory:
		if item is Dictionary:
			_add_count(actual,item)
	assert(actual==expected,"掉落与入包的实例/数量不守恒")
	assert(GameState.unclaimed_count(GameState.current_map)==0,"拾取后持久记录未注销")
	print("CAMP_CAPACITY_OK: preserved=",preserved_count," persistent=",claim_ids.size()," picked=",pickups," gold=",GameState.gold)
	get_tree().quit()

## 装备按实例身份、堆叠物按模板聚合数量，避免堆叠改变格数误判丢失或重复奖励。
func _add_count(counts: Dictionary, item: Dictionary) -> void:
	var key := String(item.get("instanceId",item.get("itemId","")))
	assert(not key.is_empty())
	counts[key] = int(counts.get(key,0))+int(item.get("count",1))

## 正式金币也发item_picked("coin")；满包断言只统计需要背包空间的物品，不误判金币入账。
func _on_pickup(id: String) -> void:
	if id!="coin":
		super._on_pickup(id)
