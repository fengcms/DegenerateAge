extends Node
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("[ReviewRegression] 失败：", message)

func _ready() -> void:
	GameState.reset_to_defaults()
	_test_inventory()
	_test_equipment()
	_test_save()
	print("[ReviewRegression] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_inventory() -> void:
	var inv := Inventory.create(3)
	inv[0] = ItemFactory.make_any("potion_hp_small", 98)
	var incoming := ItemFactory.make_any("potion_hp_small", 105)
	var original := incoming.duplicate(true)
	check(Inventory.has_space_for(inv, incoming) and Inventory.add(inv, incoming), "整批入包应成功")
	check(inv[0].count == 99 and inv[1].count == 99 and inv[2].count == 5, "数量完整分配：98+105=203")
	check(incoming == original, "不修改调用方物品")
	var snapshot := inv.duplicate(true)
	var too_many := ItemFactory.make_any("potion_hp_small", 95)
	check(not Inventory.has_space_for(inv, too_many) and not Inventory.add(inv, too_many), "余量94不足95必须失败")
	check(inv == snapshot, "失败不能部分入包")
	check(Inventory.add(inv, ItemFactory.make_any("potion_hp_small", 94)) and inv[2].count == 99, "恰好装满")
	for count in [0, -1, 1.5]:
		check(not Inventory.add(Inventory.create(), {"kind":"potion", "itemId":"potion_hp_small", "count":count}), "非法数量拒绝")
	var alias := ItemFactory.make_any("potion_hp_small", 2)
	var aliased: Array = [alias, null]
	check(Inventory.add(aliased, alias) and alias.count == 2 and aliased[0].count == 4, "别名输入也不被修改")
	var multiple := Inventory.create(2)
	multiple[0] = ItemFactory.make_any("potion_hp_small", 98)
	multiple[1] = ItemFactory.make_any("potion_hp_small", 95)
	check(Inventory.add(multiple, ItemFactory.make_any("potion_hp_small", 5)) and multiple[1].count == 99, "无空格时合并多个未满堆")

func _test_equipment() -> void:
	var inv := Inventory.create()
	for i in range(inv.size()):
		inv[i] = ItemFactory.make_equip("weapon_iron")
	var slots := Equipment.create()
	slots.weapon = ItemFactory.make_equip("weapon_iron")
	var old: Dictionary = slots.weapon.duplicate(true)
	var replacement: Dictionary = inv[17].duplicate(true)
	check(Equipment.equip_from_inventory(slots, inv, "weapon", 17, 99).ok, "满背包换装应成功")
	check(slots.weapon == replacement and inv[17] == old and Inventory.used_slots(inv) == 40, "交换实例与属性完整")
	var snapshot := inv.duplicate(true)
	var worn := slots.duplicate(true)
	check(not Equipment.unequip(slots, inv, "weapon").ok and inv == snapshot and slots == worn, "满包单独卸装仍失败且原子")
	check(not Equipment.equip_from_inventory(slots, inv, "helmet", 17, 99).ok and inv == snapshot and slots == worn, "错误槽位不改变状态")

func _test_save() -> void:
	const SLOT := 3
	var prev_active: int = SaveManager.active_slot
	var snap := _snapshot_saves(SLOT)
	SaveManager.delete_slot(SLOT)
	GameState.gold = 123
	check(SaveManager.save_slot(SLOT, true), "写有效基线")
	check(SaveManager.save_slot(SLOT, true), "建立有效备份")
	var backup := FileAccess.get_file_as_string(SaveManager.backup_path(SLOT))
	var baseline := SaveManager._collect()
	var invalid: Array = [{"player":{}}, {"schemaVersion":2, "player":{}, "gold":0}]
	for key in ["gold", "inventory", "equipment", "questStates", "currentMap", "settings", "exploredMaps"]:
		var partial := baseline.duplicate(true)
		partial.erase(key)
		invalid.append(partial)
	for patch in [{"schemaVersion":SaveManager.CURRENT_SCHEMA + 1}, {"inventory":{}}, {"currentMap":"missing"}, {"gold":-1}]:
		var data := baseline.duplicate(true)
		data.merge(patch, true)
		invalid.append(data)
	for patch in [{"level":0}, {"hp":-1}, {"mp":"35"}]:
		var data := baseline.duplicate(true)
		data.player.merge(patch, true)
		invalid.append(data)
	# C-P2-1 / C-P2-2 / C-P2-3 / C-P3-1：新增校验项的坏档断言（键白名单 / 区间 / 战斗属性上界）。
	var illegal_unlock := baseline.duplicate(true)
	illegal_unlock.unlocks = {"chapter_not_exist": true}
	invalid.append(illegal_unlock)
	var illegal_boss := baseline.duplicate(true)
	illegal_boss.firstClear = {"not_a_boss": true}
	invalid.append(illegal_boss)
	var illegal_scale := baseline.duplicate(true)
	illegal_scale.settings.mapScale = 9.0
	invalid.append(illegal_scale)
	var illegal_stat := baseline.duplicate(true)
	illegal_stat.player.criticalChance = 0.99
	invalid.append(illegal_stat)
	for data in invalid:
		check(not SaveManager._is_valid_save(data), "拒绝不完整/类型错误/越界/未来版本")
		check(not SaveManager._last_invalid_reason.is_empty(), "校验失败应记录字段级原因")
		SaveManager._write_json_atomic(SaveManager.slot_path(SLOT), data)
		var result := SaveManager.read_slot(SLOT)
		check(result.ok and result.source == "backup" and result.data.gold == 123, "非法主档应恢复有效备份")
		check(FileAccess.get_file_as_string(SaveManager.backup_path(SLOT)) == backup, "恢复不破坏备份")
	check(SaveManager._last_invalid_reason.is_empty(), "校验通过时应清空失败原因")
	# 绕过读取直接保存，同样不能把不完整主档复制进备份。
	SaveManager._write_json_atomic(SaveManager.slot_path(SLOT), {"player":{}})
	GameState.gold = 456
	check(SaveManager.save_slot(SLOT, true), "无效主档下允许保存正确运行态")
	check(FileAccess.get_file_as_string(SaveManager.backup_path(SLOT)) == backup, "保存不覆盖最近有效备份")
	var before := GameState.gold
	SaveManager.apply_to_game_state({"player":{}})
	check(GameState.gold == before, "直接应用坏档不改变进度")
	SaveManager._write_json_atomic(SaveManager.slot_path(SLOT), {"player":{}})
	SaveManager._write_json_atomic(SaveManager.backup_path(SLOT), {"player":{}})
	check(not SaveManager.load_into_game(SLOT).ok and GameState.gold == before, "主备均坏明确失败且保留运行态")
	var v1 := baseline.duplicate(true)
	v1.schemaVersion = 1
	v1.erase("exploredMaps")
	check(not SaveManager._is_valid_save(v1), "装备模型升级后拒绝旧版本存档")
	check(not v1.has("exploredMaps"), "迁移不修改输入")
	v1.settings.erase("potionThreshold")
	v1.erase("unlocks")
	check(not SaveManager._is_valid_save(v1), "旧版新增设置/解锁字段不触发迁移")
	SaveManager._write_json_atomic(SaveManager.backup_path(SLOT), baseline)
	DirAccess.remove_absolute(SaveManager.slot_path(SLOT))
	check(SaveManager.read_slot(SLOT).source == "backup", "主档缺失也从备份恢复")
	check(not SaveManager._is_valid_save({"schemaVersion":0, "player":{"level":3}, "gold":5}), "v0 旧存档明确拒绝")
	# C-P2-4：测试只用 3 号槽且必须还原现场（含 last_slot），不得删除/覆盖玩家真实存档。
	_restore_saves(SLOT, snap)
	SaveManager.active_slot = prev_active
	GameState.reset_to_defaults()

# ---- 存档测试辅助：快照 / 还原 3 号槽与 last_slot（避免污染玩家真实存档）----

func _snapshot_saves(slot: int) -> Dictionary:
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

func _restore_saves(slot: int, snap: Dictionary) -> void:
	SaveManager.delete_slot(slot)
	for key in snap.keys():
		var txt := String(snap[key])
		var path: String = SaveManager.LAST_SLOT_FILE if String(key) == "__last__" \
			else SaveManager.slot_path(slot) + String(key)
		if txt.is_empty():
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			_write_raw(path, txt)

func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[ReviewRegression] 无法写入测试文件：%s" % path)
		return
	f.store_string(text)
	f.close()
