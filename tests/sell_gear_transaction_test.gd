extends Node
## 装备本次勾选交易回归：验证预览失效、金币上限与货郎托盘整批处理。
## 在隔离项目运行，所有 GameState 修改仅存在测试实例内。

var failures: Array[String] = []

## 使用真实装备和同一策略预览，确认交易失败无副作用、成功只处理已勾选实例。
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 115
	GameState.reset_to_defaults()
	GameState.player.level = 15
	GameState.equipment.shoes = ItemFactory.make_equip_roll("c2_road_shoes", 11, "common", rng)
	GameState.inventory[0] = ItemFactory.make_equip_roll("shoes_cloth", 1, "common", rng)
	GameState.inventory[1] = ItemFactory.make_equip_roll("shoes_cloth", 1, "uncommon", rng)
	var rows := GameState.preview_equipment_sale()
	check(rows.size() == 2 and bool(rows[0].default_selected) and not bool(rows[1].default_selected),
		"谨慎预设只默认选择普通旧装备")
	var chosen: Array[Dictionary] = [rows[0]]
	var price := int(rows[0].price)
	GameState.inventory[5] = GameState.inventory[0]
	GameState.inventory[0] = null
	check(bool(GameState.validate_equipment_sale(chosen).get("ok", false)), "整理后按实例 ID 重定位")
	var sold := GameState.sell_selected_equipment(chosen)
	check(bool(sold.get("ok", false)) and GameState.inventory[5] == null and GameState.inventory[1] is Dictionary
		and GameState.gold == price, "直卖只扣选中实例并按统一售价入账")
	GameState.inventory[0] = ItemFactory.make_equip_roll("shoes_cloth", 1, "common", rng)
	chosen = [GameState.preview_equipment_sale()[0]]
	var before_gold := GameState.gold
	var changed: Dictionary = GameState.inventory[0]
	changed.star = 1
	GameState.inventory[0] = changed
	check(not bool(GameState.sell_selected_equipment(chosen).get("ok", false))
		and GameState.inventory[0] == changed and GameState.gold == before_gold, "强化使清单失效且不扣物")
	changed.star = 0
	GameState.inventory[0] = changed
	chosen = [GameState.preview_equipment_sale()[0]]
	check(GameState.set_equipment_favorite(String(changed.instanceId), true), "可收藏待售实例")
	check(not bool(GameState.sell_selected_equipment(chosen, true).get("ok", false))
		and GameState.inventory[0] is Dictionary, "收藏状态变化使清单失效且不能强卖")
	check(GameState.set_equipment_favorite(String(changed.instanceId), false), "可取消收藏")
	chosen = [GameState.preview_equipment_sale()[0]]
	GameState.gold = GameState.GOLD_CAP - int(chosen[0].price) + 1
	check(not bool(GameState.sell_selected_equipment(chosen).get("ok", false))
		and GameState.inventory[0] is Dictionary and GameState.gold == GameState.GOLD_CAP - int(chosen[0].price) + 1,
		"金币上限导致整批拒绝，不截断收入")
	GameState.gold = 0
	var risky: Array[Dictionary] = [GameState.preview_equipment_sale()[1]]
	check(not bool(GameState.sell_selected_equipment(risky).get("ok", false))
		and GameState.inventory[1] is Dictionary, "预设外装备需要显式风险确认")
	check(bool(GameState.sell_selected_equipment(risky, true).get("ok", false)) and GameState.inventory[1] == null,
		"玩家确认后可手选预设外装备")
	var selected: Array[Dictionary] = [GameState.preview_equipment_sale()[0]]
	var gold_before_stage := GameState.gold
	check(not bool(GameState.take_equipment_for_sale(selected, 0).get("ok", false)) and GameState.inventory[0] is Dictionary,
		"托盘无空格时整批不移动")
	var staged := GameState.take_equipment_for_sale(selected, 1)
	check(bool(staged.get("ok", false)) and GameState.inventory[0] == null and GameState.gold == gold_before_stage
		and (staged.get("items", []) as Array).size() == 1, "暂存只取物，不结算金币")
	GameState.gold = GameState.GOLD_CAP
	check(not bool(GameState.shop_sell_staged(staged.items).get("ok", false)), "货郎金币满时拒绝结算")
	GameState.gold = 0
	check(bool(GameState.shop_sell_staged(staged.items).get("ok", false)), "金币容量足够后可结算")
	GameState.set_trade_staged_count(0)
	if failures.is_empty():
		print("[SellGearTransactionTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 聚合断言失败以便一次运行覆盖全部交易分支。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
