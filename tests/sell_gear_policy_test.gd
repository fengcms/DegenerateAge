extends Node
## 装备出售预设与收藏保护回归，使用隔离存档环境中的真实装备实例。

var failures: Array[String] = []

## 覆盖预设边界、评分保护、收藏流转与旧实例兼容。
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 109
	var old_common := ItemFactory.make_equip_roll("shoes_cloth", 1, "common", rng)
	var old_uncommon := ItemFactory.make_equip_roll("shoes_cloth", 1, "uncommon", rng)
	var new_shoes := ItemFactory.make_equip_roll("c2_road_shoes", 11, "common", rng)
	var old_rare := ItemFactory.make_equip_roll("shoes_cloth", 1, "rare", rng)
	GameState.equipment = Equipment.create()
	GameState.equipment.shoes = new_shoes
	GameState.player.level = 15
	var cautious := SellGearPolicy.entry(old_common, 0, 15, GameState.equipment, SellGearPolicy.CAUTIOUS)
	check(bool(cautious.get("default_selected", false)), "谨慎预设选择低十级的普通零星鞋")
	check(not bool(SellGearPolicy.entry(old_uncommon, 1, 15, GameState.equipment, SellGearPolicy.CAUTIOUS).get("default_selected", false)),
		"谨慎预设不默认选择优秀")
	check(bool(SellGearPolicy.entry(old_uncommon, 1, 15, GameState.equipment, SellGearPolicy.STANDARD).get("default_selected", false)),
		"标准预设选择优秀旧装备")
	check(not bool(SellGearPolicy.entry(old_common, 0, 6, GameState.equipment, SellGearPolicy.CAUTIOUS).get("default_selected", false)),
		"谨慎预设仍要求穿戴等级低至少十级")
	GameState.equipment = Equipment.create()
	check(bool(SellGearPolicy.entry(old_rare, 2, 15, GameState.equipment, SellGearPolicy.STANDARD).get("default_selected", false))
		and bool(SellGearPolicy.entry(old_rare, 2, 15, GameState.equipment, SellGearPolicy.AGGRESSIVE).get("default_selected", false)),
		"标准与积极预设均默认选择旧套稀有零星装备")
	GameState.equipment.shoes = new_shoes
	var same_suit := SellGearPolicy.entry(new_shoes, 0, 11, GameState.equipment, SellGearPolicy.STANDARD)
	check(not bool(same_suit.get("default_selected", false))
		and (same_suit.get("reasons") as Array).has("suit")
		and bool(SellGearPolicy.entry(new_shoes, 0, 11, GameState.equipment, SellGearPolicy.AGGRESSIVE).get("default_selected", false)),
		"同套装备：标准按旧套判据排除，积极不限等级默认勾选")
	var starred := old_common.duplicate(true)
	starred.star = 1
	check(not bool(SellGearPolicy.entry(starred, 0, 15, GameState.equipment, SellGearPolicy.CAUTIOUS).get("default_selected", false)),
		"已升星装备不被默认勾选")
	GameState.equipment = Equipment.create()
	var empty_slot := SellGearPolicy.entry(new_shoes, 0, 30, GameState.equipment, SellGearPolicy.AGGRESSIVE)
	check(bool(empty_slot.get("default_selected", false)) and not bool(empty_slot.get("protected_upgrade", false)),
		"空槽不再计入评分保护，积极预设可默认勾选该类装备")
	GameState.inventory[0] = old_common
	check(GameState.set_equipment_favorite(String(old_common.instanceId), true), "背包装备可收藏")
	var locked := SellGearPolicy.entry(GameState.inventory[0], 0, 15, GameState.equipment, SellGearPolicy.CAUTIOUS)
	check(not bool(locked.get("manual_selectable", true)) and not Shop.can_sell(GameState.inventory[0]),
		"收藏装备既不能批选也不能手售")
	check(SaveManager._valid_item(GameState.inventory[0]), "收藏装备可通过存档校验")
	var legacy := old_common.duplicate(true)
	legacy.erase("favorite")
	check(SaveManager._valid_item(legacy) and not bool(legacy.get("favorite", false)), "旧装备无收藏字段仍合法")
	legacy.favorite = "yes"
	check(not SaveManager._valid_item(legacy), "非法收藏字段拒读")
	# ---- 工程 99：破损件（耐久 0）必须能走快速出售 ----
	# 对照组：同一件白装，唯一差异是耐久。修复前破损那份 `default_selected` 恒为 false，
	# 于是「一键按预设出售」对破损件整体失效 —— 这正是用户报的 bug。
	GameState.equipment = Equipment.create()
	GameState.equipment.shoes = new_shoes
	var intact_probe := old_common.duplicate(true)
	intact_probe["instanceId"] = "probe_intact_common"
	intact_probe["durability"] = Durability.max_durability()
	# `old_common` 在上一组收藏用例里已被标记收藏 —— 必须清掉，否则 favorite 会同时污染
	# 两条断言的判据（收藏件本来就既不能勾选也不能手售）。
	intact_probe.erase("favorite")
	var broken_probe := old_common.duplicate(true)
	broken_probe["instanceId"] = "probe_broken_common"
	broken_probe["durability"] = 0
	broken_probe.erase("favorite")
	var intact_row := SellGearPolicy.entry(intact_probe, 0, 15, GameState.equipment, SellGearPolicy.CAUTIOUS)
	var broken_row := SellGearPolicy.entry(broken_probe, 1, 15, GameState.equipment, SellGearPolicy.CAUTIOUS)
	check(bool(intact_row.get("default_selected", false)) and bool(broken_row.get("default_selected", false)),
		"破损白装与完好白装在谨慎预设下同样被默认勾选（工程 99 核心判据）")
	check(bool(intact_row.get("manual_selectable", false)) and bool(broken_row.get("manual_selectable", false)),
		"破损件仍可手选")
	# 原因集里必须留着 damaged —— 界面靠它标「已损坏」，删掉这条标注就看不见了。
	check((broken_row.get("reasons") as Array).has("damaged")
		and not (intact_row.get("reasons") as Array).has("damaged"),
		"只有破损件带 damaged 标注")
	var raw_reasons: Array[String] = ["damaged", "starred"]
	var blocked := SellGearPolicy.blocking_reasons(raw_reasons)
	check(blocked.size() == 1 and blocked[0] == "starred",
		"blocking_reasons 滤掉仅提示项、保留真正否决项")
	# 保护不能被误删：破损 + 已升星 / 破损 + 评分可提升 仍需拦。
	var broken_starred := old_common.duplicate(true)
	broken_starred["instanceId"] = "probe_broken_starred"
	broken_starred["durability"] = 0
	broken_starred.erase("favorite")
	broken_starred.star = 1
	var starred_row := SellGearPolicy.entry(broken_starred, 2, 15, GameState.equipment, SellGearPolicy.AGGRESSIVE)
	check(not bool(starred_row.get("default_selected", true))
		and (starred_row.get("reasons") as Array).has("starred"),
		"破损且已升星的装备仍不被预设勾选")
	GameState.equipment = Equipment.create()
	GameState.equipment.shoes = old_common
	var broken_upgrade := new_shoes.duplicate(true)
	broken_upgrade["instanceId"] = "probe_broken_upgrade"
	broken_upgrade["durability"] = 0
	var upgrade_row := SellGearPolicy.entry(broken_upgrade, 3, 15, GameState.equipment, SellGearPolicy.AGGRESSIVE)
	check((upgrade_row.get("reasons") as Array).has("upgrade")
		and not bool(upgrade_row.get("default_selected", true)),
		"破损件若评分可提升仍不被勾选（工程 77 R2 的核心保护仍在）")
	# 拾取自动出售与手动清单**刻意**不同口径：自动出售没有「取消勾选」，破损件照旧拦。
	GameState.equipment = Equipment.create()
	var auto_broken := SellGearPolicy.auto_sell(broken_probe, SellGearPolicy.AUTO_SELL_MIN_LEVEL,
		GameState.equipment, SellGearPolicy.STANDARD, false)
	check(not bool(auto_broken.get("sell", true)) and String(auto_broken.get("reason", "")) == "damaged",
		"拾取自动出售仍拒绝破损件（与手动清单的刻意差异）")
	check(Localization.tr_key("ui.sale_preview.reason_damaged") != "ui.sale_preview.reason_damaged",
		"damaged 原因有本地化文案（此前是裸 key）")
	check(GameState.set_sell_gear_preset(SellGearPolicy.STANDARD) and not GameState.set_sell_gear_preset("unknown"),
		"预设只接受登记值")
	if failures.is_empty():
		print("[SellGearPolicyTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 收集失败断言后一次性返回，便于同时定位多个边界问题。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
