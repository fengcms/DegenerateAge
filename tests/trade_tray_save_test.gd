extends Node
## 托盘落盘回归：使用隔离 user 目录验证定时、退出、满包和旧档兼容，不接触真实玩家存档。

## 未成交物品应同时保留在保存快照或背包中，满包读档不得丢失或复制。
func _ready() -> void:
	GameState.reset_to_defaults()
	SaveManager.autosave_in_tests = true
	SaveManager.active_slot = 1
	var item := ItemFactory.make_equip("weapon_iron")
	GameState.trade_tray[0] = item
	GameState.set_trade_staged_count(1)
	assert(SaveManager.autosave("定时"))
	var saved: Dictionary = SaveManager.read_slot(1).data
	assert(saved.tradeTray.size() == 1 and saved.tradeTray[0].instanceId == item.instanceId)
	SaveManager.apply_to_game_state(saved)
	assert(GameState.trade_tray.is_empty() and GameState.inventory[0].instanceId == item.instanceId)
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = ItemFactory.make_equip("weapon_iron")
	GameState.trade_tray[0] = item
	GameState.set_trade_staged_count(1)
	SaveManager.save_on_quit()
	saved = SaveManager.read_slot(1).data
	SaveManager.apply_to_game_state(saved)
	SaveManager.apply_to_game_state(saved)
	assert(GameState.trade_tray.size() == 1 and GameState.trade_tray[0].instanceId == item.instanceId)
	assert(Inventory.used_slots(GameState.inventory) == GameState.inventory.size())
	GameState.set_trade_staged_count(2)
	assert(not SaveManager.save_slot(1, true))
	saved.erase("tradeTray")
	SaveManager.apply_to_game_state(saved)
	assert(GameState.trade_tray.is_empty())
	GameState.trade_tray[0] = item
	GameState.set_trade_staged_count(1)
	assert(GameState.commit_trade_tray().ok)
	var balance := GameState.gold
	assert(not GameState.commit_trade_tray().ok and GameState.gold == balance)
	SaveManager.active_slot = -1
	print("[TradeTraySaveTest] PASS")
	get_tree().quit()
