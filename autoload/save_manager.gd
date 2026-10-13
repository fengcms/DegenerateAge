extends Node
## SaveManager — 单机存档（单例 / Autoload）。
##
## 机制（见 docs/产品文档/10 数据配置与存档技术 10.3；落地方案见工程文档 06）：
##   - 3 个独立存档槽；写入 user://saves/slot_N.json（互不影响，04 §4.1）。
##   - 原子写入：先写 .tmp，成功后替换主档；主档有效时先留一份最近有效备份（.bak）。
##   - **损坏恢复（T16）**：主档不可解析 / 结构非法 → 自动回退 .bak；恢复成功把坏档另存
##     为 .corrupt（保留现场）并把备份内容写回主档；备份也不可用则明确失败，绝不静默返回空档。
##   - 保存策略：关键事件即时存（升级 / 穿戴 / 交易 / 任务 / 切图）、每 120 秒定时存、
##     退出存；写入失败有明确提示（不静默丢失）。
##   - 版本迁移：读取时按 schemaVersion 递增补默认值（旧档导入）。
##   - 不持久化运行时节点对象；**自动战斗开关不落档**（10.3：重启后默认关闭）。

const SAVE_DIR := "user://saves/"
const LAST_SLOT_FILE := SAVE_DIR + "last_slot.json"

const MAX_SLOTS := 3
## 存档 schema 版本（工程文档 06）。
## v7（M4-10 / 工程文档 14 §3.1 ④）新增：`worldTime`（世界时钟）与 `spawnRespawn`（怪物点刷新状态）。
## v8（M6-0c / 工程文档 18 §5）新增：`unclaimedLoot`（精英 / Boss 未领取战利品，创意 07 §11）。
const CURRENT_SCHEMA := 10

## 自动存间隔（10.3：常规每 120 秒）与事件存去抖（合并短时间内的多次变更，避免频繁写盘）。
const AUTOSAVE_INTERVAL := 120.0
const AUTOSAVE_DEBOUNCE := 0.6

## 当前活动槽：自动存 / 退出存写入该槽。-1 = 未开档（新游戏未手动存过，不做任何自动写盘）。
var active_slot: int = -1

## 自动存总开关。
var autosave_enabled: bool = true
## 测试场景下是否**强制**允许自动存。
## 默认 false → 运行 `res://tests/*` 的开发期工具时自动存**自动关闭**（见 _autosave_allowed）。
## 原因（实测事故，M1-10 后）：测试工具会 `GameState.reset_to_defaults()` / 大量击杀升级，
## 而启动续档后 `active_slot` 指向玩家真实槽位 → 自动存/退出存会把玩家存档**写坏**。
## 需要压测自动存路径的工具（`SoakTest`，其自行快照 / 还原整个存档目录）可显式置 true。
var autosave_in_tests: bool = false

var _since_last_save: float = 0.0
var _debounce: float = -1.0
## 应用存档过程中抑制自动存（读档回写不应触发新一轮写盘）。
var _suppress_autosave: bool = false
## 启动续档提示：autoload 就绪时 HUD 尚未创建，故延后一帧广播（10.3）。
var _resume_toast: String = ""

func _ready() -> void:
	_ensure_dir()
	_connect_events()
	# 首次升级时导入最近使用角色的显示倍率，主菜单随即按该倍率展示。
	# 此后以独立偏好文件为准，切换角色不会改掉屏幕设置。
	if SettingsRuntime.read_display_preferences().is_empty():
		var last := _read_last_slot()
		if last >= 1 and last <= MAX_SLOTS:
			var previous := read_slot(last)
			if bool(previous.get("ok", false)):
				var saved: Variant = (previous.get("data", {}) as Dictionary).get("settings", {})
				if saved is Dictionary:
					for key in SettingsRuntime.DISPLAY_PREF_KEYS:
						if (saved as Dictionary).has(key):
							GameState.settings[key] = saved[key]
					SettingsRuntime.save_display_preferences()
					SettingsRuntime.apply_all()
	# M4-7：启动先显示主菜单；玩家选择「继续」后才读取上次存档。

func _process(delta: float) -> void:
	if active_slot < 0:
		return
	_since_last_save += delta
	if _since_last_save >= AUTOSAVE_INTERVAL:
		_since_last_save = 0.0
		autosave("定时")
		return
	if _debounce > 0.0:
		_debounce -= delta
		if _debounce <= 0.0:
			_debounce = -1.0
			autosave("关键事件")

## 退出存（10.3：退出存）。窗口关闭通知先于退出发出，此处同步写盘即可完成。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_on_quit()

# ---- 路径 ----

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot

func backup_path(slot: int) -> String:
	return slot_path(slot) + ".bak"

## 是否存在某槽的主档文件（不判断内容是否有效）。
func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

## 主档的相对后缀（供删除遍历：主档 / 备份 / 临时 / 损坏现场，避免遗漏）。
func _sidecar_suffixes() -> Array[String]:
	return ["", ".bak", ".tmp", ".corrupt"] as Array[String]

# ---- 采集与写入 ----

## 采集当前运行时状态为存档字典（10.3 记录清单）。
func _collect() -> Dictionary:
	var pos := _player_world_pos()
	return {
		"schemaVersion": CURRENT_SCHEMA,
		"slotId": active_slot,
		"savedAt": Time.get_datetime_string_from_system(),
		"player": GameState.player.duplicate(true),
		"gold": GameState.gold,
		"currentMap": GameState.current_map,
		"visitedMaps": GameState.visited_maps.duplicate(),
		"playerPos": [pos.x, pos.y],
		"inventory": GameState.inventory.duplicate(true),
		"inventoryExpansions": GameState.inventory_expansions,
		"warehouse": GameState.warehouse.duplicate(true),
		"warehouseExpansions": GameState.warehouse_expansions,
		"ownedMounts": GameState.owned_mounts.duplicate(),
		"activeMount": GameState.active_mount,
		"equipment": GameState.equipment.duplicate(true),
		"questStates": GameState.quest_states.duplicate(true),
		"firstClear": GameState.first_clear.duplicate(true),
		"unlocks": GameState.unlocks.duplicate(true),
		"settings": GameState.settings.duplicate(true),
		"hotbar": GameState.hotbar.duplicate(true),
		"exploredMaps": Fog.encode(),
		# M4-10：世界时钟与怪物点刷新状态（墓碑跨图 / 跨档保持，见工程文档 14 §3.1 ④）
		"worldTime": GameState.world_time,
		"spawnRespawn": GameState.encode_spawn_respawn(),
		# M6-0c：未领取战利品（精英 / Boss 入包失败，跨图 / 跨档保留；创意 07 §11）
		"unclaimedLoot": GameState.encode_unclaimed_loot(),
		# 注意：运行态自动战斗开关**不入档**（10.3：重启后自动战斗默认关闭）。
	}

## 玩家当前世界坐标（场景中取实体；无场景时退回上次读档坐标）。
func _player_world_pos() -> Vector2:
	var p := get_tree().get_first_node_in_group("player")
	if p is Node2D:
		return (p as Node2D).global_position
	return GameState.save_pos

## 保存到某槽。silent = true 时不弹成功提示（自动存用，避免刷屏；失败始终提示）。
func save_slot(slot: int, silent: bool = false, new_game: bool = false) -> bool:
	if not MapService.pending_travel.is_empty():
		EventBus.toast_requested.emit("地图切换中，请稍后存档", "danger")
		return false
	_ensure_dir()
	var data := _collect()
	data["slotId"] = slot
	if new_game:
		# 菜单里的世界仍是旧节点；新档始终从营地中心出生。
		var camp: Dictionary = DataLoader.get_entry("maps", "camp")
		var size: Dictionary = camp.get("size", {})
		var center := Iso.grid_to_world(Vector2i(int(size.get("w", 40)) / 2, int(size.get("h", 40)) / 2))
		data["playerPos"] = [center.x, center.y]
	if slot < 1 or slot > MAX_SLOTS or not _is_valid_save(data):
		EventBus.toast_requested.emit("当前状态不符合存档格式，未覆盖已有存档", "danger")
		return false

	var path := slot_path(slot)

	# 只有主档**有效**时才留备份——否则会把损坏内容覆盖掉可用的 .bak（T16 前提）。
	if _is_valid_save(_read_file(path)):
		if not _copy_over(path, backup_path(slot)):
			EventBus.toast_requested.emit("备份写入失败，未覆盖已有存档", "danger")
			return false

	if not _write_json_atomic(path, data):
		push_error("[SaveManager] 保存失败：%s" % path)
		EventBus.toast_requested.emit("存档写入失败（槽 %d），进度未保存！" % slot, "danger")
		return false
	if new_game:
		# 主档成功落盘后才清掉旧备份，避免日后把新角色恢复成旧角色。
		for suffix in [".bak", ".corrupt"]:
			var sidecar: String = path + suffix
			if FileAccess.file_exists(sidecar):
				DirAccess.remove_absolute(sidecar)

	active_slot = slot
	_since_last_save = 0.0
	_debounce = -1.0
	_write_last_slot(slot)
	print("[SaveManager] 已保存到槽 %d：%s" % [slot, path])
	if not silent:
		EventBus.toast_requested.emit("已保存到槽 %d（自动存档将写入本槽）" % slot, "pickup")
	return true

## 自动存（定时 / 关键事件 / 退出）：静默成功，失败必提示。
func autosave(_reason: String) -> bool:
	if not _autosave_allowed():
		return false
	return save_slot(active_slot, true)

## 退出存（10.3）。此时已无法交互，失败仅报错。
func save_on_quit() -> void:
	if not _autosave_allowed():
		return
	if save_slot(active_slot, true):
		print("[SaveManager] 退出存档完成（槽 %d）" % active_slot)

## 关键事件触发的去抖存（升级 / 穿戴 / 交易 / 任务 / 切图）。
## 未开档（active_slot < 0）、正在读档、或不允许自动存时忽略——避免"新游戏 / 测试把旧档写坏"。
func request_autosave() -> void:
	if not _autosave_allowed():
		return
	_debounce = AUTOSAVE_DEBOUNCE

## 是否允许自动存 / 退出存写盘。
## 三重闸门：① 已开档；② 不在读档抑制期；③ 总开关开且（非测试场景 或 显式放开测试）。
func _autosave_allowed() -> bool:
	if active_slot < 0 or _suppress_autosave or not autosave_enabled or not MapService.pending_travel.is_empty():
		return false
	if not autosave_in_tests and _is_test_scene():
		return false
	return true

## 当前主场景是否为 `res://tests/` 下的开发期工具。
## 这类工具会重置 / 大幅改动 GameState，若允许自动存会把玩家真实存档写坏（实测事故）。
func _is_test_scene() -> bool:
	var cs := get_tree().current_scene
	return cs != null and String(cs.scene_file_path).begins_with("res://tests/")

func _connect_events() -> void:
	EventBus.boss_first_clear.connect(func(_id: String) -> void: request_autosave())
	EventBus.player_leveled.connect(func(_lv: int) -> void: request_autosave())
	EventBus.equipment_changed.connect(func() -> void: request_autosave())
	EventBus.upgrade_completed.connect(func() -> void: request_autosave())
	EventBus.inventory_organized.connect(func() -> void: request_autosave())
	EventBus.inventory_changed.connect(func() -> void: request_autosave())
	EventBus.trade_done.connect(func(_k: String, _i: String, _p: int) -> void: request_autosave())
	EventBus.map_changed.connect(func(_m: String) -> void: request_autosave())
	EventBus.fog_changed.connect(func(_m: String) -> void: request_autosave())
	EventBus.quest_accepted.connect(func(_q: String) -> void: request_autosave())
	EventBus.quest_completed.connect(func(_q: String) -> void: request_autosave())
	EventBus.quest_rewarded.connect(func(_q: String) -> void: request_autosave())
	EventBus.warehouse_changed.connect(func() -> void: request_autosave())
	EventBus.mount_changed.connect(func() -> void: request_autosave())
	EventBus.settings_changed.connect(func() -> void: request_autosave())
	EventBus.hotbar_changed.connect(func() -> void: request_autosave())

# ---- 读取与迁移 ----

## 读取某槽并存档（含备份回退与版本迁移）。
## 返回 {ok: bool, source: "main"/"backup"/"", data: Dictionary, message: String}。
func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(backup_path(slot)):
		return {"ok": false, "source": "", "data": {}, "message": "槽 %d 还没有存档" % slot}

	var main: Variant = _read_file(path)
	if _is_valid_save(main):
		return {"ok": true, "source": "main", "data": _migrate(main as Dictionary), "message": ""}

	# T16：主档损坏 → 回退备份
	push_warning("[SaveManager] 槽 %d 主档不可用，尝试从备份恢复" % slot)
	var bak: Variant = _read_file(backup_path(slot))
	if _is_valid_save(bak):
		var restored := _restore_backup(slot, bak as Dictionary)
		return {
			"ok": true, "source": "backup", "data": _migrate(bak as Dictionary),
			"message": ("槽 %d 主存档不可用，已从备份恢复（原主档另存为 .corrupt）" if restored else "槽 %d 已读取备份，但主档修复写入失败；现场与备份已保留") % slot,
		}
	return {
		"ok": false, "source": "", "data": {},
		"message": "槽 %d 存档损坏且备份不可用（现场文件已保留）" % slot,
	}

## 把备份内容写回主档（自愈），并把损坏的主档另存为 .corrupt 保留现场。
func _restore_backup(slot: int, data: Dictionary) -> bool:
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		var corrupt := path + ".corrupt"
		if FileAccess.file_exists(corrupt):
			DirAccess.remove_absolute(corrupt)
		if DirAccess.rename_absolute(path, corrupt) != OK:
			return false
	return _write_json_atomic(path, data)

## 读档并应用到运行时状态（不重载场景，重载由 UI 层负责）。
## 返回同 read_slot 的结构（额外含 applied: bool）。
func load_into_game(slot: int) -> Dictionary:
	var res := read_slot(slot)
	if not bool(res.get("ok", false)):
		EventBus.toast_requested.emit(String(res.get("message", "读档失败")), "danger")
		return res
	apply_to_game_state(res.get("data", {}))
	active_slot = slot
	_write_last_slot(slot)
	var msg := String(res.get("message", ""))
	EventBus.toast_requested.emit(
		msg if not msg.is_empty() else "已载入槽 %d 的存档" % slot,
		"danger" if res.get("source", "main") == "backup" else "pickup")
	res["applied"] = true
	return res

## 启动续档（10.3「继续」语义）：读取上次使用的槽并应用。
## 返回是否成功续档；失败不打断启动（新游戏照常）。
func resume_last() -> bool:
	var slot := _read_last_slot()
	if slot < 0:
		return false
	var res := read_slot(slot)
	if not bool(res.get("ok", false)):
		push_warning("[SaveManager] 续档失败（槽 %d）：%s" % [slot, res.get("message", "")])
		_resume_toast = "续档失败：%s" % String(res.get("message", ""))
		return false
	apply_to_game_state(res.get("data", {}))
	active_slot = slot
	_resume_toast = String(res.get("message", ""))
	if _resume_toast.is_empty():
		_resume_toast = "已继续上次存档（槽 %d）" % slot
	return true

func _emit_resume_toast() -> void:
	print("[SaveManager] 续档完成：Lv%d 金币 %d 地图 %s 背包 %d 格" % [
		int(GameState.player.level), GameState.gold, GameState.current_map,
		GameState.inventory_used()])
	if _resume_toast.is_empty():
		return
	var kind := "danger" if _resume_toast.begins_with("续档失败") else "info"
	EventBus.toast_requested.emit(_resume_toast, kind)
	_resume_toast = ""

## 版本迁移：为旧档补齐新增字段的默认值（10.3 / 04 §4.5 版本化内容 + 旧档导入）。
func _migrate(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	var v := int(data.get("schemaVersion", -1))
	# 仅明确声明的 v0 支持历史最小角色格式；不能把无版本坏档当旧档补空。
	if v == 0:
		var defaults := {"slotId": -1, "savedAt": "", "currentMap": "camp", "playerPos": null,
			"inventory": Inventory.create(), "equipment": Equipment.create(), "questStates": {},
			"firstClear": {}, "unlocks": {}, "settings": GameState.default_settings()}
		for key in defaults:
			if not data.has(key):
				data[key] = defaults[key]
		if data.get("player") is Dictionary:
			data.player = _migrate_player(data.player)
	# ⚠ M5-9c：设置键补齐对**所有版本**生效，不能只放在下面的 v < CURRENT_SCHEMA 分支里。
	# default_settings() 新增键（mapScale / displayScaleMode / displayScale…）时，当前版本的存量档
	# 同样缺这些键；若只在跨版本迁移时补，新键一上线就会把全部存量档判为损坏
	# （实测事故：9c 加键后启动续档报「槽 1 主档不可用」——校验按 default_settings() 逐键查）。
	# 语义与运行时读取一致：缺键取默认值；存档已有值优先，未知键保留（见 _migrate_settings）。
	if data.get("settings") is Dictionary:
		data.settings = _migrate_settings(data.settings)
	if v >= 0 and v < CURRENT_SCHEMA:
		if not data.has("unlocks"):
			data.unlocks = {}
		if not data.has("exploredMaps"):
			data.exploredMaps = {}
		if v < 3:
			data.warehouse = Warehouse.create()
			data.warehouseExpansions = 0
		if v < 4:
			data.ownedMounts = []
			data.activeMount = ""
		if v < 6:
			data.hotbar = HotbarConfig.defaults()
		if v < 7:
			# M4-10：旧档无世界时钟与刷新状态 → 视为「无墓碑」，从零起算（不报错）
			data.worldTime = 0.0
			data.spawnRespawn = {}
		if v < 8:
			# M6-0c：旧档无未领取战利品 → 空集合（创意 07 §11）
			data.unclaimedLoot = {}
		if v < 9:
			data.visitedMaps = ["camp"]
			var previous_map := String(data.get("currentMap", ""))
			if previous_map != "camp" and DataLoader.get_entry("maps", previous_map) is Dictionary:
				data.visitedMaps.append(previous_map)
		if v < 10:
			data.inventoryExpansions = 0
		data.schemaVersion = CURRENT_SCHEMA
	return data

## 应用前完整校验；无效数据不修改运行态。只有明确旧版本允许迁移缺省字段。
func apply_to_game_state(data: Dictionary) -> void:
	if not _is_valid_save(data):
		EventBus.toast_requested.emit("存档结构无效，未改变当前进度", "danger")
		return
	data = _migrate(data)
	_suppress_autosave = true

	if data.get("player", null) is Dictionary:
		GameState.player = _migrate_player(data["player"] as Dictionary)
	GameState.gold = clampi(int(data.get("gold", 0)), 0, GameState.GOLD_CAP)
	GameState.current_map = String(data.get("currentMap", "camp"))
	GameState.visited_maps.clear()
	for map_id in data.visitedMaps:
		if not GameState.visited_maps.has(map_id):
			GameState.visited_maps.append(map_id)
	GameState.explored_maps = Fog.normalize(data.get("exploredMaps", {}))
	# M4-10：世界时钟与怪物点刷新状态。须在读档重载场景**之前**恢复 ——
	# `Game._ready` → `spawn_from_map` 装配怪物点时会立即读取该状态（决定是否建墓碑）。
	GameState.world_time = maxf(0.0, float(data.get("worldTime", 0.0)))
	GameState.apply_spawn_respawn(data.get("spawnRespawn", {}))
	# M6-0c：未领取战利品同样须在重载场景前恢复 —— `Game._ready` 会据此重建地面物（创意 07 §11.2）。
	GameState.apply_unclaimed_loot(_deep_int(data.get("unclaimedLoot", {})))
	GameState.inventory_expansions = int(data.get("inventoryExpansions", 0))
	GameState.inventory = _migrate_inventory(data.get("inventory", []), GameState.inventory_expansions)
	GameState.warehouse_expansions = int(data.get("warehouseExpansions", 0))
	GameState.warehouse = _migrate_warehouse(data.get("warehouse", []), GameState.warehouse_expansions)
	GameState.owned_mounts.clear()
	for mount_id in data.get("ownedMounts", []):
		GameState.owned_mounts.append(String(mount_id))
	GameState.active_mount = String(data.get("activeMount", ""))
	GameState.equipment = _migrate_equipment(data.get("equipment", {}))
	GameState.hotbar = data.hotbar.duplicate(true)
	# 任务状态：经 Quest 归一化（老档 String 值 → {state, progress}，见 11 §4.1 R8）
	GameState.quest_states = Quest.normalize_states(data.get("questStates", {}))
	if data.get("firstClear", null) is Dictionary:
		GameState.first_clear = data["firstClear"] as Dictionary
	if data.get("unlocks", null) is Dictionary:
		GameState.unlocks = data["unlocks"] as Dictionary
	else:
		GameState.unlocks = {}
	if data.get("settings", null) is Dictionary:
		GameState.settings = _migrate_settings(data["settings"] as Dictionary)
		if SettingsRuntime.read_display_preferences().is_empty():
			# 未有本机偏好时，首次读取旧槽即迁入独立文件。
			SettingsRuntime.save_display_preferences()
		GameState.settings = SettingsRuntime.with_display_preferences(GameState.settings)
		SettingsRuntime.apply_all()

	# 坐标：交给 Game._ready 消费（10.3 当前地图与坐标）
	var pp = data.get("playerPos", null)
	if pp is Array and (pp as Array).size() >= 2:
		GameState.save_pos = Vector2(float((pp as Array)[0]), float((pp as Array)[1]))
		GameState.has_save_pos = true
	else:
		GameState.clear_save_pos()

	# 运行态开关不持久化：10.3 重启后自动战斗默认关闭
	GameState.auto_battle_on = false
	GameState.auto_pickup_on = false
	GameState.close_all_panels()

	# HP / MP 收敛到（可能变化的）上限：装备加成改变上限时不越界、不补满
	GameState.player.hp = mini(int(GameState.player.hp), GameState.max_hp())
	GameState.player.mp = mini(int(GameState.player.mp), GameState.max_mp())

	_suppress_autosave = false

# ---- 字段迁移 ----

## 角色字段补全：以默认模板为底，覆盖存档中的已有字段（旧档缺字段自动补默认值）。
func _migrate_player(raw: Dictionary) -> Dictionary:
	var out := GameState.default_player()
	for k in raw.keys():
		out[k] = raw[k]
	return _deep_int(out) as Dictionary

func _migrate_settings(raw: Dictionary) -> Dictionary:
	var out := GameState.default_settings()
	for k in raw.keys():
		out[k] = raw[k]
	return _deep_int(out) as Dictionary

## 背包迁移：定长 40 格（5.8）；多余丢弃、不足补空、非法项置空。
func _migrate_inventory(raw, expansions: int = 0) -> Array:
	var out := Inventory.create(Warehouse.capacity(expansions))
	if not (raw is Array):
		return out
	var arr := raw as Array
	for i in range(mini(arr.size(), out.size())):
		if arr[i] is Dictionary:
			out[i] = _deep_int((arr[i] as Dictionary).duplicate(true))
	return out

func _migrate_warehouse(raw, expansions: int) -> Array:
	var out := Warehouse.create(expansions)
	if not raw is Array:
		return out
	for i in range(mini(raw.size(), out.size())):
		if raw[i] is Dictionary:
			out[i] = _deep_int((raw[i] as Dictionary).duplicate(true))
	return out

## 装备槽迁移：以 14 槽模板为底（5.1）；未知槽位丢弃，缺失槽补空。
func _migrate_equipment(raw) -> Dictionary:
	var out := Equipment.create()
	if not (raw is Dictionary):
		return out
	for k in (raw as Dictionary).keys():
		var sid := String(k)
		if not out.has(sid):
			continue
		var it = raw[k]
		if it is Dictionary:
			out[sid] = _deep_int((it as Dictionary).duplicate(true))
	return out

## JSON 数字一律解析为 float（Godot JSON 实现）→ 整数值回落为 int，
## 保证读档后属性与存档前**逐字段相等**（实例属性不重随，10.1）。
func _deep_int(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for k in d.keys():
				d[k] = _deep_int(d[k])
			return d
		TYPE_ARRAY:
			var a: Array = v
			for i in range(a.size()):
				a[i] = _deep_int(a[i])
			return a
		TYPE_FLOAT:
			var f := float(v)
			if absf(f) < 9007199254740992.0 and is_equal_approx(f, round(f)):
				return int(f)
			return f
		_:
			return v

# ---- 摘要 / 删除 ----

## 某槽摘要（供存档卡显示，不改动运行时状态）。
## 返回 {slot, exists, ok, empty, source, message, name, level, gold, mapId, mapName, savedAt}。
func slot_summary(slot: int) -> Dictionary:
	var info := {
		"slot": slot, "exists": has_slot(slot), "ok": false, "empty": not has_slot(slot),
		"source": "", "message": "", "name": "", "level": 0, "gold": 0,
		"mapId": "", "mapName": "", "savedAt": "", "inventoryUsed": 0, "worn": 0,
	}
	var res := read_slot(slot)
	info["source"] = String(res.get("source", ""))
	info["message"] = String(res.get("message", ""))
	if not bool(res.get("ok", false)):
		return info
	var d: Dictionary = res.get("data", {})
	var p: Dictionary = {}
	if d.get("player", null) is Dictionary:
		p = d["player"]
	var map_id := String(d.get("currentMap", "camp"))
	info["ok"] = true
	info["name"] = String(p.get("name", "守护者"))
	info["level"] = int(p.get("level", 1))
	info["gold"] = int(d.get("gold", 0))
	info["mapId"] = map_id
	info["mapName"] = map_display_name(map_id)
	info["savedAt"] = _pretty_time(String(d.get("savedAt", "")))
	var inv_raw = d.get("inventory", null)
	if inv_raw is Array:
		info["inventoryUsed"] = Inventory.used_slots(inv_raw as Array)
	var eq_raw = d.get("equipment", null)
	if eq_raw is Dictionary:
		info["worn"] = Equipment.worn_count(eq_raw as Dictionary)
	return info

## 全部槽摘要（1..MAX_SLOTS）。
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(1, MAX_SLOTS + 1):
		out.append(slot_summary(i))
	return out

## 地图显示名（取 maps.json 的 name；无则回退 id）。
func map_display_name(map_id: String) -> String:
	var m = DataLoader.get_entry("maps", map_id)
	if m is Dictionary:
		return String((m as Dictionary).get("name", map_id))
	return map_id

func _pretty_time(iso: String) -> String:
	return iso.replace("T", " ") if not iso.is_empty() else ""

## 删除某槽（主档 + 备份 + 临时 + 损坏现场）；若删的是活动槽则解除活动状态。
func delete_slot(slot: int) -> void:
	for suffix in _sidecar_suffixes():
		var p := slot_path(slot) + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if active_slot == slot:
		active_slot = -1
	if _read_last_slot() == slot:
		_write_last_slot(-1)
	print("[SaveManager] 已删除槽 %d 的存档" % slot)

func set_active_slot(slot: int) -> void:
	active_slot = slot
	_write_last_slot(slot if slot >= 0 else -1)

func continue_slot() -> int:
	var slot := _read_last_slot()
	return slot if slot >= 1 and slot <= MAX_SLOTS and bool(read_slot(slot).get("ok", false)) else -1

# ---- 底层文件操作 ----

## 原子写入：tmp 写好 → 替换主档（10.3）。
func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 无法写入临时存档：%s" % tmp)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("[SaveManager] 替换存档失败（err=%d）：%s" % [err, path])
		DirAccess.remove_absolute(tmp)
		return false
	return true

## 读文件并解析为 Variant；不存在 / 打不开 / 解析失败一律返回 null（不抛错）。
func _read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)

## 所有读档/备份/应用入口使用同一校验；先识别版本，再迁移再验收，绝不修改输入。
func _is_valid_save(raw: Variant) -> bool:
	if not raw is Dictionary or not _whole(raw.get("schemaVersion"), 0, CURRENT_SCHEMA):
		return false
	if not raw.get("player") is Dictionary or not _whole(raw.player.get("level"), 1):
		return false
	if not _whole(raw.get("gold"), 0, GameState.GOLD_CAP):
		return false
	var data := _migrate(raw)
	for key in ["player", "equipment", "questStates", "firstClear", "unlocks", "settings", "exploredMaps"]:
		if not data.get(key) is Dictionary:
			return false
	if not _whole(data.get("inventoryExpansions"), 0, Warehouse.max_expansions()):
		return false
	if not data.get("inventory") is Array or data.inventory.size() != Warehouse.capacity(int(data.inventoryExpansions)):
		return false
	if not _whole(data.get("warehouseExpansions"), 0, Warehouse.max_expansions()):
		return false
	if not data.get("warehouse") is Array or data.warehouse.size() != Warehouse.capacity(int(data.warehouseExpansions)):
		return false
	if not data.get("ownedMounts") is Array or not data.get("activeMount") is String:
		return false
	if not HotbarConfig.valid_layout(data.get("hotbar")):
		return false
	var seen_mounts := {}
	for mount_id in data.ownedMounts:
		if not mount_id is String or not DataLoader.get_entry("mounts", mount_id) is Dictionary or seen_mounts.has(mount_id):
			return false
		seen_mounts[mount_id] = true
	if not data.activeMount.is_empty() and not seen_mounts.has(data.activeMount):
		return false
	if not data.get("currentMap") is String or DataLoader.get_entry("maps", data.currentMap) == null:
		return false
	if not data.get("visitedMaps") is Array:
		return false
	for map_id in data.visitedMaps:
		if not map_id is String or not DataLoader.get_entry("maps", map_id) is Dictionary:
			return false
	# M4-10：世界时钟与怪物点刷新状态（v7 起；旧档由 _migrate 补默认）
	if not _number(data.get("worldTime")) or float(data.worldTime) < 0.0:
		return false
	if not _valid_spawn_respawn(data.get("spawnRespawn")):
		return false
	# M6-0c：未领取战利品结构（v8 起；旧档由 _migrate 补空集合）
	if not _valid_unclaimed_loot(data.get("unclaimedLoot")):
		return false
	if not data.get("savedAt") is String or not _whole(data.get("slotId"), -1, MAX_SLOTS):
		return false
	var pos: Variant = data.get("playerPos")
	if not data.has("playerPos") or (pos != null and (not pos is Array or pos.size() != 2)):
		return false
	if pos is Array:
		for value in pos:
			if not _number(value):
				return false
	for key in GameState.default_player():
		var value: Variant = data.player.get(key)
		if key == "name":
			if not value is String or value.is_empty():
				return false
		elif not _number(value) or float(value) < 0:
			return false
	for key in ["level", "xp", "hp", "mp"]:
		if not _whole(data.player.get(key), 1 if key == "level" else 0):
			return false
	if float(data.player.attackInterval) <= 0 or float(data.player.movementSpeed) <= 0:
		return false
	for item in data.inventory:
		if item != null and not _valid_item(item):
			return false
	for item in data.warehouse:
		if item != null and not _valid_item(item):
			return false
	if data.equipment.size() != Equipment.SLOT_DEFS.size():
		return false
	for slot in Equipment.create():
		if not data.equipment.has(slot):
			return false
		var item: Variant = data.equipment[slot]
		if item != null and (not _valid_item(item) or item.kind != "equip" or not Equipment.slot_accepts(slot, item)):
			return false
	for key in ["firstClear", "unlocks"]:
		for value in data[key].values():
			if not value is bool:
				return false
	for value in data.questStates.values():
		if value is String:
			if not Quest._is_known_state(value):
				return false
		elif not value is Dictionary or not value.get("state") is String or not Quest._is_known_state(value.state) or not _whole(value.get("progress"), 0):
			return false
	for key in GameState.default_settings():
		var value: Variant = data.settings.get(key)
		var default_value: Variant = GameState.default_settings()[key]
		if default_value is bool:
			if not value is bool:
				return false
		elif default_value is Dictionary:
			if not value is Dictionary or not SettingsRuntime.valid_bindings(value):
				return false
		elif default_value is String:
			if not value is String or not SettingsRuntime.valid_choice(key, value):
				return false
		elif not _number(value) or float(value) < 0:
			return false
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _whole(value: Variant, minimum: float, maximum: float = 9007199254740991.0) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

func _valid_item(item: Variant) -> bool:
	if not item is Dictionary or not item.get("kind") is String or not item.get("itemId") is String:
		return false
	var kind := String(item.kind)
	if kind == "equip":
		if not DataLoader.get_entry("equipments", item.itemId) is Dictionary or not item.get("instanceId") is String or item.instanceId.is_empty():
			return false
		if not item.get("baseAttrs") is Dictionary or not item.get("affixes") is Array or not item.get("pctAttrs") is Array:
			return false
		if not _whole(item.get("level"), 1) or not _whole(item.get("star"), 0, 12) or not ItemUtil.is_valid_quality(str(item.get("quality", ""))):
			return false
		for value in item.baseAttrs.values():
			if not _number(value):
				return false
		for effect in item.affixes + item.pctAttrs:
			if not effect is Dictionary or not effect.get("stat") is String or not _number(effect.get("value")):
				return false
		return true
	var table: String = {"potion": "potions", "misc": "miscItems", "quest": "miscItems", "rune": "runes"}.get(kind, "")
	return not table.is_empty() and DataLoader.get_entry(table, item.itemId) != null and _whole(item.get("count", 1), 1, ItemUtil.stack_max(item))

## M4-10：怪物点刷新状态合法性。整体须为字典；每项须含合法 `readyAt`（有限数）
## 与可选 `pos`（长度 2 的数对）。**不认识的 key 不拒档** —— 地图数据变动不应导致读档失败
## （`GameState.apply_spawn_respawn` 亦会忽略非法项；此处只拦「结构级」坏档）。
func _valid_spawn_respawn(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var table: Dictionary = raw
	for key in table.keys():
		var record: Variant = table[key]
		if not (record is Dictionary):
			return false
		var entry: Dictionary = record
		if not _number(entry.get("readyAt")):
			return false
		var pos: Variant = entry.get("pos", null)
		if pos == null:
			continue
		if not (pos is Array) or (pos as Array).size() != 2:
			return false
		for value in (pos as Array):
			if not _number(value):
				return false
	return true

## M6-0c（创意 07 §11）：未领取战利品合法性。整体字典；每图须为数组；每条含字符串 `uid` /
## `batchId`、合法物品 `item`、长度 2 的数对 `pos`。与 `_valid_spawn_respawn` 同口径——
## **不认识的 map_id 不拒档**（地图数据变动不应导致读档失败；`apply_unclaimed_loot` 亦会忽略非法项）。
func _valid_unclaimed_loot(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	for map_id in (raw as Dictionary).keys():
		var rows: Variant = (raw as Dictionary)[map_id]
		if not (rows is Array):
			return false
		for record in (rows as Array):
			if not (record is Dictionary):
				return false
			if not (record.get("uid") is String) or not (record.get("batchId") is String):
				return false
			if not (record.get("item") is Dictionary) or not _valid_item(record.item):
				return false
			var pos: Variant = record.get("pos", null)
			if not (pos is Array) or (pos as Array).size() != 2:
				return false
			for value in (pos as Array):
				if not _number(value):
					return false
	return true

## 先复制到临时文件再替换备份，复制失败不得先删除旧备份。
func _copy_over(src: String, dst: String) -> bool:
	var temp := dst + ".tmp"
	if DirAccess.copy_absolute(src, temp) != OK:
		return false
	var error := DirAccess.rename_absolute(temp, dst)
	if error != OK:
		DirAccess.remove_absolute(temp)
	return error == OK

func _write_last_slot(slot: int) -> void:
	if slot < 0:
		if FileAccess.file_exists(LAST_SLOT_FILE):
			DirAccess.remove_absolute(LAST_SLOT_FILE)
		return
	var f := FileAccess.open(LAST_SLOT_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"slot": slot}))
	f.close()

func _read_last_slot() -> int:
	var v: Variant = _read_file(LAST_SLOT_FILE)
	if not (v is Dictionary):
		return -1
	var slot := int((v as Dictionary).get("slot", -1))
	if slot < 1 or slot > MAX_SLOTS:
		return -1
	return slot
