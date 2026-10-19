extends Node
## 工程 61：装备出售「暴力」预设。
##
## 这份测试守的是**三条边界**，任何一条松掉都会让「一键清包」变成事故：
##   ① 暴力只跳过「价值判断」——收藏与任务物品**仍然不卖**；
##   ② 暴力只管**背包装备**——药水 / 如意 / 卷轴 / 已穿戴 / 仓库一律不碰；
##   ③ 暴力**不落档**——它若进了 `settings`，漏登记 `CHOICE_VALUES` 会判整档损坏，
##      而且下次打开面板就是「40 格已经全勾好」的默认态。
##
## ⚠ 「一次点击即成交」这条必须用**不传 `allow_risky`** 调用来验：
##    传 `true` 等于玩家已经点过二次确认，那样测不出实现有没有跳过风险层。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[BrutalPresetTest] " + label)

func _ready() -> void:
	_test_selects_every_sellable()
	_test_hard_gates_still_hold()
	_test_sells_in_one_click()
	_test_not_persisted()
	await _test_ui_one_click()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[BrutalPresetTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[BrutalPresetTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

## ① 价值判断全跳过：更高品质、已升星、比身上更好的装备都默认勾选。
func _test_selects_every_sellable() -> void:
	_stage_bag()
	var rows := GameState.preview_equipment_sale(SellGearPolicy.BRUTAL)
	check(rows.size() == 3, "暴力清单应含全部 3 件背包装备，实际 %d" % rows.size())
	for row in rows:
		var item_name := ItemUtil.display_name(row.item_snapshot)
		check(bool(row.default_selected), "暴力应默认勾选「%s」" % item_name)
		check(bool(row.manual_selectable), "暴力应允许手动调整「%s」" % item_name)
		check((row.reasons as Array).is_empty(), "暴力不应对「%s」给出任何拦截理由" % item_name)
	# 对照：同一批数据在谨慎预设下绝不会全选 —— 否则上面的断言等于没测到「暴力」。
	var cautious := GameState.preview_equipment_sale(SellGearPolicy.CAUTIOUS)
	var cautious_selected := 0
	for row in cautious:
		if bool(row.default_selected):
			cautious_selected += 1
	check(cautious_selected < rows.size(),
		"对照失败：谨慎预设也全选了（%d/%d），暴力的差别测不出来" % [cautious_selected, rows.size()])

## ② 收藏与任务物品仍不卖；药水 / 如意 / 卷轴根本不进装备清单。
func _test_hard_gates_still_hold() -> void:
	_stage_bag()
	var favorite_id := String((GameState.inventory[0] as Dictionary).get("instanceId", ""))
	check(GameState.set_equipment_favorite(favorite_id, true), "应能把第一件设为收藏")
	var rows := GameState.preview_equipment_sale(SellGearPolicy.BRUTAL)
	var favorited := {}
	var potion_listed := false
	for row in rows:
		var item: Dictionary = row.item_snapshot
		if String(item.get("instanceId", "")) == favorite_id:
			favorited = row
		if String(item.get("kind", "")) != "equip":
			potion_listed = true
	check(not favorited.is_empty(), "收藏件仍应在清单里可见（只是不该被选中）")
	if not favorited.is_empty():
		check(not bool(favorited.default_selected), "收藏件不得被默认勾选")
		check(not bool(favorited.manual_selectable), "收藏件不得被手动勾选（与普通预设一致）")
		check((favorited.reasons as Array).has("favorite"), "收藏件应带 favorite 理由，实际 %s" % [favorited.reasons])
	check(rows.size() == 3, "清单仍应是 3 件装备（收藏件只是不被选中）")
	check(not potion_listed, "暴力清单只能含装备，药水 / 如意 / 卷轴不得混入")

## ③ 一次点击成交：不传 allow_risky 也必须成功，且金币与移除件数对得上。
func _test_sells_in_one_click() -> void:
	_stage_bag()
	var rows := GameState.preview_equipment_sale(SellGearPolicy.BRUTAL)
	var expected := 0
	for row in rows:
		expected += int(row.price)
	var equipment_before := 0
	for it in GameState.inventory:
		if it is Dictionary and String(it.get("kind", "")) == "equip":
			equipment_before += 1
	# 🔴 关键：第三个参数之外**不传** allow_risky（默认 false）—— 暴力本就不该走二次确认。
	var sold := GameState.sell_selected_equipment(rows, false, SellGearPolicy.BRUTAL)
	check(bool(sold.get("ok", false)), "暴力出售应一次成功，实际 reason=%s" % String(sold.get("reason", "")))
	check(int(sold.get("count", 0)) == rows.size(),
		"应卖出 %d 件，实际 %d" % [rows.size(), int(sold.get("count", 0))])
	check(GameState.gold == expected, "金币应入账 %d，实际 %d" % [expected, GameState.gold])
	var equipment_after := 0
	for it in GameState.inventory:
		if it is Dictionary and String(it.get("kind", "")) == "equip":
			equipment_after += 1
	check(equipment_after == equipment_before - rows.size(),
		"背包装备应从 %d 减到 %d，实际剩 %d" % [equipment_before, equipment_before - rows.size(), equipment_after])

	# 🔴 override 必须一路传到校验层：漏传会拿存档预设比对，判「清单已变化」——
	#    这条断言就是那个漏传的牙。
	_stage_bag()
	var rows2 := GameState.preview_equipment_sale(SellGearPolicy.BRUTAL)
	check(not bool(GameState.validate_equipment_sale(rows2, false).get("ok", false)),
		"同一份暴力清单在不传 override 时应判「清单已变化」（证明 override 真的在传）")
	check(bool(GameState.validate_equipment_sale(rows2, false, SellGearPolicy.BRUTAL).get("ok", false)),
		"带上暴力 override 应通过校验")

## ④ 不落档：设置入口拒绝暴力，且它永远不在存档合法值域里。
func _test_not_persisted() -> void:
	GameState.reset_to_defaults()
	var before := String(GameState.settings.get("sellGearPreset", ""))
	check(not GameState.set_sell_gear_preset(SellGearPolicy.BRUTAL), "暴力不得写入设置")
	check(String(GameState.settings.get("sellGearPreset", "")) == before,
		"被拒绝后设置应保持原值，实际「%s」" % String(GameState.settings.get("sellGearPreset", "")))
	check(not SellGearPolicy.PERSISTABLE.has(SellGearPolicy.BRUTAL), "PERSISTABLE 不应包含暴力")
	check(SellGearPolicy.valid_preset(SellGearPolicy.BRUTAL), "暴力仍必须是合法预设（否则清单无法生成）")
	# 🔴 存档白名单：暴力既然不落档，就不能出现在 CHOICE_VALUES 里。
	# 一旦有人误登记，这条会红 —— 那说明「存了 brutal 的档」会通过校验，但读档路径并没有对应的回落逻辑。
	check(not SettingsRuntime.valid_choice("sellGearPreset", SellGearPolicy.BRUTAL),
		"暴力不得进入存档枚举止（它会以「40 格全勾」的默认态回到玩家面前）")
	for preset_id in SellGearPolicy.PERSISTABLE:
		check(SettingsRuntime.valid_choice("sellGearPreset", String(preset_id)),
			"可落档预设 %s 必须在 CHOICE_VALUES 里（漏登记会判整档损坏）" % preset_id)

## ⑤ UI 层：选暴力后**点一次**确认就成交。
## 这条与 ③ 不重复 —— ③ 验的是事务层「不需要 allow_risky」，⑤ 验的是窗口有没有真的跳过
## `_risk_confirmed` 那一层。少了它，「事务层能过、界面却仍要你点第二次」会全绿。
func _test_ui_one_click() -> void:
	_stage_bag()
	var preview := EquipmentSalePreview.new()
	preview.mode = EquipmentSalePreview.DIRECT
	add_child(preview)
	for i in range(3):
		await get_tree().process_frame
	var brutal_index := SellGearPolicy.PRESETS.find(SellGearPolicy.BRUTAL)
	preview.call("_on_preset_selected", brutal_index)
	for i in range(2):
		await get_tree().process_frame
	var warning: Label = preview.get("_warning")
	check(warning.text.is_empty(), "暴力预设不应显示风险提示，实际「%s」" % warning.text)
	check(not bool(preview.get("_risk_confirmed")), "暴力预设不应进入二次确认态")
	var gold_before := GameState.gold
	preview.call("_on_confirm")
	await get_tree().process_frame
	check(not is_instance_valid(preview), "暴力确认后窗口应直接关闭（一次点击成交）")
	check(GameState.gold > gold_before, "一次点击后金币应已入账，实际 %d → %d" % [gold_before, GameState.gold])
	var left_equip := 0
	for it in GameState.inventory:
		if it is Dictionary and String(it.get("kind", "")) == "equip":
			left_equip += 1
	check(left_equip == 0, "暴力成交后背包不应剩装备，实际 %d" % left_equip)

# ---- 夹具 ----

## 三件背包装备（含一件更高品质、一件已升星）+ 药水 / 如意 / 卷轴各一，外加一件已穿戴武器。
## 每次调用都重置，避免上一个用例卖掉的残留影响下一个。
func _stage_bag() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 60
	GameState.gold = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	GameState.equipment.weapon = ItemFactory.make_equip_roll("weapon_iron", 1, "common", rng)
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null
	GameState.inventory[0] = ItemFactory.make_equip_roll("weapon_iron", 1, "legendary", rng)
	GameState.inventory[1] = ItemFactory.make_equip_roll("shoes_cloth", 1, "epic", rng)
	var starred: Dictionary = GameState.inventory[1]
	starred["star"] = 12
	GameState.inventory[1] = starred
	GameState.inventory[2] = ItemFactory.make_equip_roll("armor_cloth", 1, "uncommon", rng)
	GameState.inventory[3] = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	GameState.inventory[4] = {"kind": "rune", "itemId": "rune_iron", "count": 1}
	GameState.inventory[5] = {"kind": "misc", "itemId": "misc_town_scroll", "count": 1}
