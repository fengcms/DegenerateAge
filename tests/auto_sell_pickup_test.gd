extends Node
## 工程 63：拾取装备「自动出售」。
##
## 这份测试守的是**四条边界**，松掉任何一条都会变成「玩家的装备被静默销毁」：
##   ① 只对**拾取**生效 —— `add_item()` 的调用方（商店买货 / 任务奖励）必须留在背包里；
##   ② 价值判断复用出售面板那一套 —— 比身上更好的、收藏的、品质超预设的**不卖**；
##   ③ 两个自动出售专属否决 —— **金币已满不卖**（卖了等于白扔）、**空槽位不卖**
##      （`_judge()` 的 V1 规则刻意不保护空槽，手动清单里玩家能取消勾选，自动出售没有这一步）；
##   ④ 60 级门槛**运行时**生效 —— 只拦界面等于没拦（改档 / 导入档 / 将来降级都可能带 true）。
##
## ⚠ 「积极 ≠ 全卖」也在断言里（史诗 / 传说会被品质理由拦下），
##    因为玩家对「最多选积极」的预期很容易被理解成「积极就全清」。

var failures: Array[String] = []
## 信号计数用成员变量而不是 lambda 局部变量 —— GDScript 的 lambda 按值捕获，
## 在闭包里 `picked += 1` 只改副本，外面永远读到 0（首版就栽在这里，误判成「信号没发」）。
var _picked := 0
var _traded := 0

func _on_picked(_id: String) -> void:
	_picked += 1

func _on_traded(_kind: String, _id: String, _gold: int) -> void:
	_traded += 1

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[AutoSellPickupTest] " + label)

func _ready() -> void:
	_test_sells_when_enabled()
	_test_level_gate()
	_test_disabled_by_default()
	_test_favorite_kept()
	_test_non_equip_untouched()
	_test_better_item_kept()
	_test_empty_slot_kept()
	_test_gold_capped_kept()
	_test_preset_limits()
	_test_add_item_not_affected()
	_test_save_roundtrip()
	_test_summary_text()
	await _test_ui_gate()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[AutoSellPickupTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[AutoSellPickupTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- ① 正常成交 ----

func _test_sells_when_enabled() -> void:
	_stage(60)
	var item := _roll("weapon_iron", "common")
	var expected := Shop.sell_price(item)
	var bag_before := _bag_count()
	_picked = 0
	_traded = 0
	EventBus.item_picked.connect(_on_picked)
	EventBus.trade_done.connect(_on_traded)
	var res := GameState.pickup_loot(item)
	EventBus.item_picked.disconnect(_on_picked)
	EventBus.trade_done.disconnect(_on_traded)
	check(GameState.auto_sell_enabled(), "60 级 + 开关开 ⇒ 自动出售应生效")
	check(bool(res.get("ok", false)) and bool(res.get("auto_sold", false)),
		"可卖装备应被自动出售，实际 %s" % [res])
	check(int(res.get("gold", 0)) == expected, "入账应为 %d，实际 %d" % [expected, int(res.get("gold", 0))])
	check(GameState.gold == expected, "金币应为 %d，实际 %d" % [expected, GameState.gold])
	check(_bag_count() == bag_before, "自动出售不应占用背包格：%d → %d" % [bag_before, _bag_count()])
	# item_picked 不能因为「没进背包」就被吞掉：拾取音效与收集类任务都挂在这个信号上。
	check(_picked == 1, "自动出售仍应广播 item_picked（实际 %d 次）" % _picked)
	check(_traded == 1, "自动出售应广播 trade_done(sell)（实际 %d 次）" % _traded)

# ---- ④ 60 级门槛（运行时，不只是界面） ----

func _test_level_gate() -> void:
	_stage(59)
	var item := _roll("weapon_iron", "common")
	var res := GameState.pickup_loot(item)
	check(not GameState.auto_sell_enabled(), "59 级即使开关为真也不得生效")
	check(not bool(res.get("auto_sold", false)), "59 级不应自动出售")
	check(GameState.gold == 0, "59 级金币不应变动，实际 %d" % GameState.gold)
	check(_bag_count() == 1, "59 级装备应进背包，实际背包 %d 件" % _bag_count())

func _test_disabled_by_default() -> void:
	GameState.reset_to_defaults()
	check(not bool(GameState.settings.get("autoSellEquipOnPickup", true)), "新键默认必须是 false")
	GameState.player.level = 60
	var item := _roll("weapon_iron", "common")
	var res := GameState.pickup_loot(item)
	check(not bool(res.get("auto_sold", false)), "开关关闭时不得自动出售")
	check(_bag_count() == 1, "开关关闭时装备应进背包")

# ---- ② 价值判断仍然有效 ----

func _test_favorite_kept() -> void:
	_stage(60)
	var item := _roll("weapon_iron", "common")
	item["favorite"] = true
	var res := GameState.pickup_loot(item)
	check(not bool(res.get("auto_sold", false)), "收藏装备不得自动出售")
	check(String(res.get("reason", "")) == "favorite",
		"拒卖理由应为 favorite，实际「%s」" % String(res.get("reason", "")))
	check(_bag_count() == 1, "收藏装备应进背包")

func _test_non_equip_untouched() -> void:
	_stage(60)
	var potion := {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	var scroll := {"kind": "misc", "itemId": "misc_town_scroll", "count": 1}
	var rune := {"kind": "rune", "itemId": "rune_iron", "count": 1}
	for it in [potion, scroll, rune]:
		var res := GameState.pickup_loot(it)
		check(not bool(res.get("auto_sold", false)),
			"非装备不得进入自动出售：%s" % String((it as Dictionary).get("kind", "")))
	check(_bag_count() == 3, "药水 / 卷轴 / 如意都应进背包，实际 %d 件" % _bag_count())
	check(GameState.gold == 0, "非装备不应产生金币")

func _test_better_item_kept() -> void:
	_stage(60)
	# 身上是传说武器，掉一件史诗同槽 ⇒ 品质更高但比身上差，仍要被品质理由拦下。
	var epic := _roll("weapon_iron", "epic")
	check(not bool(GameState.pickup_loot(epic).get("auto_sold", false)), "品质高于预设上限的装备不得自动出售")
	check(_bag_count() == 1, "被品质拦下的装备应进背包，实际 %d 件" % _bag_count())
	# 比身上更好的：先穿普通武器，再丢传说 ⇒ 评分更高，必须留下让玩家穿。
	_stage(60)
	GameState.equipment["weapon"] = ItemFactory.make_equip_roll("weapon_iron", 1, "common", _rng())
	var strong := _roll("weapon_iron", "legendary")
	var res := GameState.pickup_loot(strong)
	check(not bool(res.get("auto_sold", false)), "比身上更好的装备不得自动出售")
	# 传说同时命中 upgrade（评分更高）与 quality（高于积极档上限），理由顺序由 `_judge()` 决定，
	# 这里只要求「命中其中之一」—— 断死具体某一条会让「调整理由顺序」这种无关改动变红。
	check(["upgrade", "quality"].has(String(res.get("reason", ""))),
		"应因「更好」或「品质超标」被拦下，实际「%s」" % String(res.get("reason", "")))
	check(_bag_count() == 1, "比身上更好的装备应进背包，实际 %d 件" % _bag_count())
	# 评分更高但品质不超标的对照：穿普通，丢稀有 ⇒ 稀有 ≤ 上限，靠 upgrade 理由拦下。
	_stage(60)
	GameState.equipment["weapon"] = ItemFactory.make_equip_roll("weapon_iron", 1, "common", _rng())
	var better := _roll("weapon_iron", "rare")
	var kept := GameState.pickup_loot(better)
	check(not bool(kept.get("auto_sold", false)), "评分更高的同槽装备不得自动出售")
	check(String(kept.get("reason", "")) == "upgrade",
		"应因 upgrade 被拦下，实际「%s」" % String(kept.get("reason", "")))

# ---- ③ 自动出售专属否决 ----

func _test_empty_slot_kept() -> void:
	_stage(60)
	check(GameState.equipment.get("helmet") == null, "夹具前提：头盔槽应为空")
	var helmet := _roll("helmet_cloth", "common")
	var res := GameState.pickup_loot(helmet)
	check(not bool(res.get("auto_sold", false)),
		"空槽位的第一件装备不得自动出售（否则该部位永远穿不上）")
	check(String(res.get("reason", "")) == "empty_slot",
		"拒卖理由应为 empty_slot，实际「%s」" % String(res.get("reason", "")))
	check(_bag_count() == 1, "空槽装备应进背包")

func _test_gold_capped_kept() -> void:
	_stage(60)
	GameState.gold = GameState.GOLD_CAP
	var item := _roll("weapon_iron", "common")
	var res := GameState.pickup_loot(item)
	check(not bool(res.get("auto_sold", false)), "金币已满时不得自动出售（卖了等于白扔）")
	check(String(res.get("reason", "")) == "gold_capped",
		"拒卖理由应为 gold_capped，实际「%s」" % String(res.get("reason", "")))
	check(GameState.gold == GameState.GOLD_CAP, "金币应保持上限值")
	check(_bag_count() == 1, "金币满时装备应进背包")

# ---- 「积极」的边界 ----

func _test_preset_limits() -> void:
	# 积极：稀有可卖
	_stage(60, SellGearPolicy.AGGRESSIVE)
	var rare := _roll("weapon_iron", "rare")
	check(bool(GameState.pickup_loot(rare).get("auto_sold", false)), "积极档应卖掉稀有装备")
	# 积极：史诗不卖（品质上限 rare）
	_stage(60, SellGearPolicy.AGGRESSIVE)
	var epic := _roll("weapon_iron", "epic")
	var res := GameState.pickup_loot(epic)
	check(not bool(res.get("auto_sold", false)), "积极档不得卖掉史诗（max_quality = rare）")
	check(String(res.get("reason", "")) == "quality",
		"史诗应因品质被拦下，实际「%s」" % String(res.get("reason", "")))
	# 谨慎：优秀就不卖
	_stage(60, SellGearPolicy.CAUTIOUS)
	var uncommon := _roll("weapon_iron", "uncommon")
	check(not bool(GameState.pickup_loot(uncommon).get("auto_sold", false)), "谨慎档不得卖掉优秀装备")

# ---- ① 商店 / 任务奖励的入包不受影响 ----

func _test_add_item_not_affected() -> void:
	_stage(60)
	var item := _roll("weapon_iron", "common")
	check(GameState.add_item(item), "add_item 应成功入包")
	check(GameState.gold == 0, "add_item 不得触发自动出售（否则商店买的装备会当场被卖）")
	check(_bag_count() == 1, "经 add_item 的装备应留在背包")

# ---- 落档 ----

func _test_save_roundtrip() -> void:
	GameState.reset_to_defaults()
	check(not bool(GameState.settings.get("autoSellEquipOnPickup", true)), "新键默认必须是 false")
	GameState.settings["autoSellEquipOnPickup"] = true
	var data := SaveManager._collect()
	check(SaveManager._is_valid_save(data), "开启自动出售后应可存档")
	var schema_before := int(data.schemaVersion)
	var missing := SaveManager._collect()
	missing.settings.erase("autoSellEquipOnPickup")
	check(SaveManager._is_valid_save(missing), "当前版本档缺新键仍应有效（加 bool 键不得 bump schema）")
	var migrated := SaveManager._migrate(missing)
	check(not bool(migrated.settings.get("autoSellEquipOnPickup", true)), "缺键迁移应补 false")
	check(int(migrated.schemaVersion) == schema_before, "加键不得改变 schemaVersion（%d → %d）"
		% [schema_before, int(migrated.schemaVersion)])

# ---- 批次摘要 ----

func _test_summary_text() -> void:
	var rolled := [{"kind": "equip", "quality": "common", "itemId": "weapon_iron"}]
	var plain := LootNotify.summary_text("腐化巨兽", rolled, 0)
	check(not plain.contains("自动出售"), "无自动出售时摘要不得出现该段，实际「%s」" % plain)
	var sold := LootNotify.summary_text("腐化巨兽", rolled, 0, false, 3, 900)
	check(sold.contains("自动出售 3 件 +900 金币"), "自动出售应追加件数与金币，实际「%s」" % sold)

# ---- 界面门槛 ----

func _test_ui_gate() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 59
	var panel: Control = (load("res://scenes/ui/SettingsPanel.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.set_open(true)
	await get_tree().process_frame
	var check_box: CheckBox = panel.get("_auto_sell_check")
	var picker: OptionButton = panel.get("_auto_sell_preset")
	check(check_box != null, "设置面板「游戏」页应有自动出售勾选框")
	check(picker != null, "设置面板应有预设下拉")
	if check_box != null:
		check(check_box.disabled, "59 级时勾选框必须灰显")
		check(check_box.text.contains(str(SellGearPolicy.AUTO_SELL_MIN_LEVEL)),
			"灰显时应写明等级门槛，实际「%s」" % check_box.text)
		GameState.player.level = 60
		panel.call("_refresh_auto_sell_gate")
		check(not check_box.disabled, "60 级时勾选框必须可用")
	if picker != null:
		check(picker.item_count == SellGearPolicy.PERSISTABLE.size(),
			"预设下拉必须只有可落档的三档，实际 %d 档" % picker.item_count)
		for i in range(picker.item_count):
			var preset_id := String(picker.get_item_metadata(i))
			check(preset_id != SellGearPolicy.BRUTAL, "预设下拉绝不能出现「暴力」（第 %d 项）" % i)
	panel.set_open(false)
	panel.queue_free()
	await get_tree().process_frame

# ---- 夹具 ----

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 63
	return r

func _roll(item_id: String, quality: String) -> Dictionary:
	return ItemFactory.make_equip_roll(item_id, 1, quality, _rng())

## 60 级判定的标准局面：满级可勾、身上穿一件传说武器（让「同槽更差」可判为可卖）、背包清空。
func _stage(level: int, preset: String = SellGearPolicy.AGGRESSIVE) -> void:
	GameState.reset_to_defaults()
	GameState.player.level = level
	GameState.gold = 0
	GameState.settings["autoSellEquipOnPickup"] = true
	GameState.set_sell_gear_preset(preset)
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null
	GameState.equipment["weapon"] = ItemFactory.make_equip_roll("weapon_iron", 1, "legendary", _rng())

func _bag_count() -> int:
	var n := 0
	for it in GameState.inventory:
		if it is Dictionary:
			n += 1
	return n
