extends Node
## 破损件出售链路探针 —— 排查「背包中耐久为 0 的装备无法快速出售」。
##
## 只读语义：**不写任何存档**（不改 `GameState.inventory` 的持久化状态，不调 SaveManager）。
## 做法是把构造好的装备临时塞进 `GameState.inventory`，跑完立即还原。
##
## 覆盖四段，任一段与预期不符即为根因所在：
##   ① `SellGearPolicy.entry()`  → 预设是否勾选（default_selected）/ 能否手选（manual_selectable）
##   ② `GameState.preview_equipment_sale()` → 清单里到底有没有这件
##   ③ `GameState.validate_equipment_sale()` → 手选后能否过事务层（含 allow_risky）
##   ④ 本地化键 `ui.sale_preview.reason_damaged` 是否存在
##
## 运行：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/sell_broken_probe.tscn`

const ITEM_ID := "weapon_iron"
const TIER := 1
const PLAYER_LEVEL := 40

func _ready() -> void:
	var saved_inventory := GameState.inventory
	var saved_level: int = int(GameState.player.get("level", 1))
	GameState.inventory = []
	GameState.player.level = PLAYER_LEVEL
	_probe()
	GameState.inventory = saved_inventory
	GameState.player.level = saved_level
	get_tree().quit()

func _make(quality: String, durability: int, tag: String) -> Dictionary:
	var item := ItemFactory.make_equip_roll(ITEM_ID, TIER, quality, null, "probe_" + tag)
	if item.is_empty():
		print("[FATAL] 造装备失败：%s / %s" % [ITEM_ID, quality])
		return {}
	item["durability"] = durability
	return item

func _probe() -> void:
	var intact := _make("common", Durability.max_durability(), "intact")
	var broken := _make("common", 0, "broken")
	var broken_rare := _make("rare", 0, "broken_rare")
	var intact_rare := _make("rare", Durability.max_durability(), "intact_rare")
	var samples := {
		"满耐久 白": intact, "耐久0 白": broken,
		"满耐久 蓝": intact_rare, "耐久0 蓝": broken_rare,
	}
	for key in samples:
		GameState.inventory.append(samples[key])

	print("== ① SellGearPolicy.entry()（玩家 Lv%d）==" % PLAYER_LEVEL)
	for preset in SellGearPolicy.PRESETS:
		print("-- preset=%s" % preset)
		for key in samples:
			var row := SellGearPolicy.entry(samples[key], 0, PLAYER_LEVEL, {}, preset)
			print("   %-10s default_selected=%-5s manual_selectable=%-5s price=%-6d reasons=%s" % [
				key, str(row.get("default_selected")), str(row.get("manual_selectable")),
				int(row.get("price", 0)), str(row.get("reasons"))])

	print("== ② GameState.preview_equipment_sale() 清单条数 ==")
	for preset in SellGearPolicy.PRESETS:
		var rows := GameState.preview_equipment_sale(preset)
		var picked := 0
		for row in rows:
			if bool(row.get("default_selected", false)):
				picked += 1
		print("   preset=%-11s 清单 %d 条 / 默认勾选 %d 条" % [preset, rows.size(), picked])

	print("== ③ 手选破损件过事务层（standard）==")
	var target := GameState.preview_equipment_sale(SellGearPolicy.STANDARD)
	var chosen: Array[Dictionary] = []
	for row in target:
		if String(row.get("instance_id", "")) == String(broken.get("instanceId", "")):
			chosen.append(row)
	if chosen.is_empty():
		print("   [异常] 破损件根本不出现在清单里")
	else:
		var strict := GameState.validate_equipment_sale(chosen, false, SellGearPolicy.STANDARD)
		var risky := GameState.validate_equipment_sale(chosen, true, SellGearPolicy.STANDARD)
		print("   allow_risky=false → ok=%s reason=%s" % [str(strict.get("ok")), str(strict.get("reason"))])
		print("   allow_risky=true  → ok=%s reason=%s" % [str(risky.get("ok")), str(risky.get("reason"))])

	print("== ④ 本地化键 ==")
	for reason in ["favorite", "unsellable", "quality", "level", "suit", "upgrade", "starred", "damaged"]:
		var key: String = "ui.sale_preview.reason_" + String(reason)
		var text := Localization.tr_key(key)
		print("   %-32s → %s%s" % [key, text, "   [缺键]" if text == key else ""])
