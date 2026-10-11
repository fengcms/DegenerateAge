extends Node
## 存档面板视觉验收（开发期，M5 移除）。
## 覆盖 M1-10：Esc 打开存档面板 → 3 张存档卡（活动槽 / 有档 / 空槽）→ 二次确认删除态。
## 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/SaveShot.tscn
##
## 说明：只在 3 号槽做演示（测试前后快照还原），不碰玩家 1 / 2 号槽。

const DEMO_SLOT := 3

func _ready() -> void:
	var snap := _snapshot(DEMO_SLOT)
	var prev_active := SaveManager.active_slot

	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	# 造一份演示进度并写入 3 号槽（写两次 → 产生最近有效备份）
	GameState.reset_to_defaults()
	GameState.player.level = 5
	GameState.player.xp = 40
	GameState.gold = 1280
	EventBus.player_leveled.emit(5)
	EventBus.gold_changed.emit(GameState.gold)
	GameState.add_item(_equip("weapon_starter", "shot_bag1", "common", {"atk": 5}))
	GameState.add_item(_equip("helmet_cloth", "shot_bag2", "uncommon", {"def": 2}))
	GameState.add_item({"kind": "potion", "itemId": "potion_hp_small", "count": 6})
	GameState.equipment["weapon"] = _equip("weapon_wolfking", "shot_worn", "rare", {"atk": 12},
		[{"stat": "atk", "value": 6}])
	EventBus.equipment_changed.emit()
	EventBus.inventory_changed.emit()
	await get_tree().process_frame

	SaveManager.set_active_slot(DEMO_SLOT)
	var ok1 := SaveManager.save_slot(DEMO_SLOT, true)
	var ok2 := SaveManager.save_slot(DEMO_SLOT, true)
	print("[SaveShot] 写入 3 号槽：%s / %s（第二次产生备份）" % [str(ok1), str(ok2)])

	var panel = main.get_node("UI/SavePanel")
	panel.set_open(true)
	for _i in range(12):
		await get_tree().process_frame

	var cards: Array = panel._cards
	print("[SaveShot] 存档卡数量=%d（产品文档 9.4：3 张）" % cards.size())
	for c in cards:
		var s := SaveManager.slot_summary(int(c.slot))
		print("[SaveShot] 槽 %d：%s" % [int(c.slot), c.info.text])
		_expect_card(c, s)

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_save_panel.png")

	# 二次确认态（9.4：删除需二次确认）
	panel._on_delete_pressed(DEMO_SLOT)
	for _i in range(6):
		await get_tree().process_frame
	var demonstrating := false
	for c in cards:
		if int(c.slot) == DEMO_SLOT and c.yes.visible and not c.del.visible:
			demonstrating = true
	print("[SaveShot] 删除二次确认态：%s" % str(demonstrating))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_save_confirm.png")

	# 取消 → 回到常态；关闭面板
	panel._on_delete_cancelled(DEMO_SLOT)
	panel.set_open(false)
	for _i in range(4):
		await get_tree().process_frame
	print("[SaveShot] 面板关闭，panel_open=%s" % str(GameState.panel_open))

	_restore(DEMO_SLOT, snap)
	SaveManager.active_slot = prev_active
	GameState.reset_to_defaults()
	get_tree().quit()

func _expect_card(card: Dictionary, summary: Dictionary) -> void:
	if bool(summary.get("ok", false)):
		print("[SaveShot]   └ 有档：读取可用=%s 删除可用=%s" % [
			str(not card.load.disabled), str(not card.del.disabled)])
	else:
		print("[SaveShot]   └ 无可用档：读取禁用=%s" % str(card.load.disabled))

func _equip(item_id: String, inst_id: String, quality: String, base: Dictionary,
		affixes: Array = []) -> Dictionary:
	return {
		"kind": "equip", "itemId": item_id, "instanceId": inst_id,
		"quality": quality, "level": 1,
		"baseAttrs": base, "affixes": affixes, "pctAttrs": [],
		"star": 0, "count": 1,
	}

# ---- 现场保护：不污染玩家真实存档 ----

func _snapshot(slot: int) -> Dictionary:
	var out := {"__last__": ""}
	if FileAccess.file_exists(SaveManager.LAST_SLOT_FILE):
		var lf := FileAccess.open(SaveManager.LAST_SLOT_FILE, FileAccess.READ)
		if lf != null:
			out["__last__"] = lf.get_as_text()
			lf.close()
	for suffix in ["", ".bak", ".tmp", ".corrupt"]:
		var p: String = SaveManager.slot_path(slot) + suffix
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				out[suffix] = f.get_as_text()
				f.close()
	return out

func _restore(slot: int, snap: Dictionary) -> void:
	SaveManager.delete_slot(slot)
	for key in snap.keys():
		var txt := String(snap[key])
		var path: String = SaveManager.LAST_SLOT_FILE if String(key) == "__last__" \
			else SaveManager.slot_path(slot) + String(key)
		if txt.is_empty():
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_string(txt)
				f.close()
	print("[SaveShot] 已还原 3 号槽与 last_slot 现场")
