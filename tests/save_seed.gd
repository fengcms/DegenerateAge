extends Node
## 端到端存档验证 · 第 1 步：造档（开发期，M5 移除）。
## 作用：把一份可辨认的进度写入 3 号槽，并让 last_slot 指向它；
##       随后由**另一个进程**启动真实主场景，验证「存 → 退 → 进」后状态一致。
##
## 运行：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   "$GODOT" --headless --path . res://tests/SaveSeed.tscn        # 造档
##   "$GODOT" --headless --path . --quit                            # 真实启动（应打印续档日志）
##
## ⚠ 会改写 3 号槽与 last_slot.json：运行前后请自行备份这两个文件（见工程文档 06 §8）。

const DEMO_SLOT := 3

func _ready() -> void:
	print("[SaveSeed] 存档目录：%s" % ProjectSettings.globalize_path(SaveManager.SAVE_DIR))
	GameState.reset_to_defaults()
	GameState.player.level = 7
	GameState.player.xp = 33
	GameState.player.attack = 24
	GameState.player.defense = 11
	GameState.player.hp = 90
	GameState.gold = 1234
	GameState.quest_states = {"Q001": "done"}
	GameState.add_item(_equip("weapon_starter", "seed_bag1", {"atk": 5}))
	GameState.equipment["weapon"] = _equip("weapon_wolfking", "seed_worn", {"atk": 12},
		[{"stat": "atk", "value": 6}])
	GameState.save_pos = Vector2(400.0, -400.0)
	GameState.has_save_pos = true

	SaveManager.set_active_slot(DEMO_SLOT)
	SaveManager.save_slot(DEMO_SLOT, true)
	SaveManager.save_slot(DEMO_SLOT, true)
	var s := SaveManager.slot_summary(DEMO_SLOT)
	print("[SaveSeed] 已写入槽 %d：Lv%d 金币 %d 背包 %d 件 已穿戴 %d 件 坐标 %s" % [
		DEMO_SLOT, int(s.get("level", 0)), int(s.get("gold", 0)),
		int(s.get("inventoryUsed", 0)), int(s.get("worn", 0)), str(GameState.save_pos)])
	print("[SaveSeed] 请另开进程启动主场景验证续档；完成后还原槽 3 与 last_slot.json")
	get_tree().quit()

func _equip(item_id: String, inst_id: String, base: Dictionary, affixes: Array = []) -> Dictionary:
	return {
		"kind": "equip", "itemId": item_id, "instanceId": inst_id,
		"quality": "common", "level": 1,
		"baseAttrs": base, "affixes": affixes, "pctAttrs": [],
		"star": 0, "count": 1,
	}
