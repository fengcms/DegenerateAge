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
## v10（工程文档 22）新增：`inventoryExpansions`，存档校验按扩容次数检查背包长度。
## v11（三轴装备模型）：装备实例结构破坏性升级；schema 0—10 不再读取，旧文件保留。
## v14（E1 / 工程文档 30 §4）新增：`questRewardPlans`（持久任务发奖计划，失败重试复用同一实例与词条）。
## v15（技能升阶）新增：`skillRanks`（只存已购买的 2—5 阶；旧档默认空，解锁技能按等级拥有 1 阶）。
## v16：满星紫装重铸解锁第五词条；缺失标记保持原装备快照。
const CURRENT_SCHEMA := 16
## 可读取的最低 schema 版本（0—10 明确拒读，产品 10.3）。`_is_valid_save` 与导入的前置检查共用同一下限，
## 避免两处写死 11 后出现「读档能读、导入不能导」的分裂。
const MIN_READABLE_SCHEMA := 11
## 角色名长度上限（与存档面板输入框 `max_length` 一致）；导入时超长名字按此截断。
const MAX_PLAYER_NAME_LENGTH := 16
## 文件名禁用字符（角色名可能被玩家改成含路径分隔符 / 通配符的内容，仅用于导出文件名安全化）。
const ILLEGAL_FILENAME_CHARS := ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
## 营地开放外围只增加可走区域；旧白盒档位保留坐标、迷雾和地面战利品。
const CURRENT_CAMP_LAYOUT_VERSION := "2026-10-16-camp-open-perimeter-v2"
const PREVIOUS_CAMP_LAYOUT_VERSION := "2026-10-15-camp-whitebox-v1"
## 工程 82：聚金地脉从 160×90 收成 64×48（单战场 6 营）。坐标需按比例重映射一次。
## 🔴 **独立的一次性门** —— 不能复用 `mapLayoutVersion`（存量档早已有该键，迁移永远不会触发），
##    也不能无门（每次读档都按同一比例再缩一次 ⇒ 玩家坐标持续漂移）。
const CURRENT_C7_GOLD_LAYOUT_VERSION := "2026-10-21-gold-field-v2"
const LEGACY_C7_GOLD_SIZE := Vector2(160, 90)
## 旧目录只用于 v11 读档迁移；正式装备表始终只有二十个型号。
const EQUIPMENT_LEGACY_IDS := {
	"weapon_starter": "weapon_iron", "armor_starter": "armor_cloth",
	"weapon_wolfking": "weapon_iron", "weapon_legendary_vein_guard": "weapon_iron",
	"c2_inspector_armor": "c2_road_armor", "c2_backup_blade": "c2_road_blade",
	"c2_apprentice_bracer": "c2_road_bracer", "c2_slag_shield": "c2_copper_shield",
	"c2_road_blade_modified": "c2_road_blade", "c2_copper_shield_modified": "c2_copper_shield",
	"c2_road_armor_modified": "c2_road_armor", "c2_road_helmet_modified": "c2_road_helmet",
	"c2_road_shoes_modified": "c2_road_shoes", "c2_road_bracer_modified": "c2_road_bracer",
	"c2_road_knee_modified": "c2_road_knee", "c2_copper_bracelet_modified": "c2_copper_bracelet",
	"c2_road_ring_modified": "c2_road_ring", "c2_warm_necklace_modified": "c2_warm_necklace",
	"c2_foreman_gauntlet": "c2_road_blade", "c2_devourer_heart": "c2_warm_necklace",
	"c2_extractor_eye": "c2_road_ring",
}

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

## 工程 79：最近一次读档的「随身工具补领」提示（`ToolReclaim`）。
## 与 `_resume_toast` 同源——补领发生在 `apply_to_game_state` 内，此时 HUD 尚未就绪，
## 必须延后到 `load_into_game` / `_emit_resume_toast` 再广播，否则 toast 丢在空中。
var _last_reclaim_notice: String = ""
var _last_reclaim_danger: bool = false
## 续档提示是否为 danger 级（续档失败 / 工程 79 补领失败）。
var _resume_toast_danger: bool = false

## 最近一次 `_is_valid_save` 失败的原因（字段级，G-P2-1）；通过时清空。
var _last_invalid_reason: String = ""

## C-P3-7：最近一次 `_migrate` 中因无法识别而**逐件丢弃**的装备实例数（供读档提示）。
var _last_pruned_equipment: int = 0

## C-P2-2：合法解锁键 / 合法 Boss 键白名单（来自数据表，惰性构建一次）。
## 数据表重新加载（`data_loaded`）时失效重建。
var _known_unlock_ids: Dictionary = {}
var _known_boss_ids: Dictionary = {}
var _legal_keys_ready: bool = false

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
		"mapLayoutVersion": CURRENT_CAMP_LAYOUT_VERSION,
		# 工程 82：聚金地脉缩图版本（迁移的一次性门）。新档从出生就带，老档读一次即补。
		"c7GoldLayoutVersion": CURRENT_C7_GOLD_LAYOUT_VERSION,
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
		"questItems": GameState.quest_items.duplicate(true),
		# E1：持久任务发奖计划（尚未领取的随机奖励实例，失败重试不重抽；工程文档 30 §4）
		"questRewardPlans": GameState.quest_reward_plans.duplicate(true),
		"firstClear": GameState.first_clear.duplicate(true),
		"unlocks": GameState.unlocks.duplicate(true),
		"settings": GameState.settings.duplicate(true),
		"hotbar": GameState.hotbar.duplicate(true),
		"skillRanks": GameState.skill_ranks.duplicate(true),
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
		EventBus.toast_requested.emit(Localization.tr_key("msg.save_manager.p001"), "danger")
		return false
	var live_player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if live_player != null and live_player.is_dead and not new_game:
		EventBus.toast_requested.emit(Localization.tr_key("msg.save_manager.p002"), "danger")
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
		# G-P2-1：自校验失败必须留下字段级原因，否则新版本引入非法运行态时无从定位违例字段。
		var reason := "槽号越界" if slot < 1 or slot > MAX_SLOTS else _last_invalid_reason
		push_error("[SaveManager] 保存失败：槽 %d，原因「%s」，地图 %s" % [slot, reason, GameState.current_map])
		EventBus.toast_requested.emit(Localization.tr_key("msg.save_manager.p003"), "danger")
		return false

	var path := slot_path(slot)

	# 只有主档**有效**时才留备份——否则会把损坏内容覆盖掉可用的 .bak（T16 前提）。
	if _is_valid_save(_read_file(path)):
		if not _copy_over(path, backup_path(slot)):
			push_error("[SaveManager] 备份失败：槽 %d，路径 %s" % [slot, backup_path(slot)])
			EventBus.toast_requested.emit(Localization.tr_key("msg.save_manager.p004"), "danger")
			return false

	if not _write_json_atomic(path, data):
		push_error("[SaveManager] 存档落盘失败：槽 %d，地图 %s，路径 %s" % [slot, GameState.current_map, path])
		EventBus.toast_requested.emit(Localization.tr_key("msg.save_manager.p006") % slot, "danger")
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
		EventBus.toast_requested.emit(Localization.tr_key("msg.save_manager.p007") % slot, "pickup")
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
## E-P3-4（与计划原文的偏差）：货郎托盘内有暂存装备时挂起——托盘物品已出背包、尚未结算，
## 此刻写盘会把它们整批漏掉；待托盘清空（确认出售 / 退回）后由下一次触发恢复。比「暂存时补存一次」
## 更能防丢失：补存之后仍会有升级 / 整理等事件再次触发自动存，托盘物品照样丢失。
func request_autosave() -> void:
	if GameState.trade_staged_count > 0:
		return
	if not _autosave_allowed():
		return
	_debounce = AUTOSAVE_DEBOUNCE

## 是否允许自动存 / 退出存写盘。
## 三重闸门：① 已开档；② 不在读档抑制期；③ 总开关开且（非测试场景 或 显式放开测试）。
func _autosave_allowed() -> bool:
	var live_player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if live_player != null and live_player.is_dead:
		return false
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
	EventBus.skill_rank_changed.connect(func(_id: String, _rank: int) -> void: request_autosave())
	EventBus.equipment_changed.connect(func() -> void: request_autosave())
	EventBus.equipment_favorite_changed.connect(func() -> void: request_autosave())
	EventBus.upgrade_completed.connect(func() -> void: request_autosave())
	EventBus.inventory_organized.connect(func() -> void: request_autosave())
	EventBus.inventory_expanded.connect(func() -> void: request_autosave())
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
	# C-P2-2：数据表重载后重建解锁 / Boss 键白名单（惰性，见 _ensure_legal_keys）。
	EventBus.data_loaded.connect(func() -> void: _invalidate_legal_keys())

# ---- 读取与迁移 ----

## 读取某槽并存档（含备份回退与版本迁移）。
## 返回 {ok: bool, source: "main"/"backup"/"", data: Dictionary, message: String}。
func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(backup_path(slot)):
		return {"ok": false, "source": "", "data": {}, "message": Localization.tr_key("msg.save_manager.p008") % slot}

	var main: Variant = _read_file(path)
	if _is_valid_save(main):
		var migrated_main := _migrate(main as Dictionary)
		return {"ok": true, "source": "main", "data": migrated_main, "message": _pruned_notice("")}

	# T16：主档损坏 → 回退备份
	push_warning("[SaveManager] 槽 %d 主档不可用（原因「%s」，地图 %s），尝试从备份恢复"
		% [slot, _last_invalid_reason, GameState.current_map])
	var bak: Variant = _read_file(backup_path(slot))
	if _is_valid_save(bak):
		var restored := _restore_backup(slot, bak as Dictionary)
		var migrated_bak := _migrate(bak as Dictionary)
		var base := (Localization.tr_key("msg.save_manager.p010") if restored else Localization.tr_key("msg.save_manager.p011")) % slot
		return {"ok": true, "source": "backup", "data": migrated_bak, "message": _pruned_notice(base)}
	if (main is Dictionary and int(main.get("schemaVersion", -1)) < CURRENT_SCHEMA) \
			or (bak is Dictionary and int(bak.get("schemaVersion", -1)) < CURRENT_SCHEMA):
		return {"ok": false, "source": "", "data": {},
			"message": Localization.tr_key("msg.save_manager.equipment_schema_incompatible") % slot}
	return {
		"ok": false, "source": "", "data": {},
		"message": Localization.tr_key("msg.save_manager.p012") % slot,
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

## C-P3-7：读档提示——本次迁移若丢弃了无法识别的旧装备，在基础提示后附加数量说明。
func _pruned_notice(base: String) -> String:
	if _last_pruned_equipment <= 0:
		return base
	var notice := Localization.tr_key("msg.save_manager.pruned_equipment") % _last_pruned_equipment
	return notice if base.is_empty() else base + "；" + notice

## 读档并应用到运行时状态（不重载场景，重载由 UI 层负责）。
## 返回同 read_slot 的结构（额外含 applied: bool）。
func load_into_game(slot: int) -> Dictionary:
	var res := read_slot(slot)
	if not bool(res.get("ok", false)):
		EventBus.toast_requested.emit(String(res.get("message", Localization.tr_key("msg.save_manager.p013"))), "danger")
		return res
	apply_to_game_state(res.get("data", {}))
	active_slot = slot
	_write_last_slot(slot)
	# 工程 79：补领提示并到读档提示后；补领失败（背包与仓库都满）按 danger 呈现。
	var reclaim_danger := _take_reclaim_danger()
	var msg := _with_reclaim_notice(String(res.get("message", "")))
	EventBus.toast_requested.emit(
		msg if not msg.is_empty() else Localization.tr_key("msg.save_manager.p014") % slot,
		"danger" if res.get("source", "main") == "backup" or reclaim_danger else "pickup")
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
		_resume_toast = Localization.tr_key("msg.save_manager.p016") % String(res.get("message", ""))
		return false
	apply_to_game_state(res.get("data", {}))
	active_slot = slot
	# 工程 79：补领提示并入续档提示（延后到 `_emit_resume_toast` 广播，此刻 HUD 尚未就绪）。
	_resume_toast_danger = _take_reclaim_danger()
	_resume_toast = _with_reclaim_notice(String(res.get("message", "")))
	if _resume_toast.is_empty():
		_resume_toast = Localization.tr_key("msg.save_manager.p017") % slot
	return true

func _emit_resume_toast() -> void:
	# G-P3-1：日志不输出可变进度数值（等级 / 金币 / 背包占用），仅留槽位与地图便于定位；
	# 正式构建下 stdout 可能留在玩家机器上，进度摘要属敏感存档内容。
	print("[SaveManager] 续档完成（槽 %d，地图 %s）" % [active_slot, GameState.current_map])
	if _resume_toast.is_empty():
		return
	var kind := "info"
	if _resume_toast.begins_with(Localization.tr_key("msg.save_manager.p018")) or _resume_toast_danger:
		kind = "danger"
	EventBus.toast_requested.emit(_resume_toast, kind)
	_resume_toast = ""
	_resume_toast_danger = false

## 版本迁移：为旧档补齐新增字段的默认值（10.3 / 04 §4.5 版本化内容 + 旧档导入）。
func _migrate(source: Dictionary) -> Dictionary:
	# C-P3-2：本函数中的 v0 与 v<11 分支在真实读档路径**不可达** ——
	# `_is_valid_save` 只接受 schema 11—15（产品 10.3：0—10 明确拒读），
	# 故这些分支仅为历史兼容保留（`_migrate` 单测仍会直接调用），勿据此认为旧档可导入。
	var data := source.duplicate(true)
	var v := int(data.get("schemaVersion", -1))
	# schema 11—12 的第一章存档若尚无布局版本，仍需完成独立的地图坐标转换。
	if not data.has("mapLayoutVersion") and v >= 11:
		_migrate_landscape_positions(data)
		data.mapLayoutVersion = "2026-10-14-landscape-v2"
	var layout_version := String(data.get("mapLayoutVersion", ""))
	if layout_version == PREVIOUS_CAMP_LAYOUT_VERSION:
		# 旧白盒坐标仍有效；外围障碍撤除及马车碰撞缩小只扩大可走区。
		data.mapLayoutVersion = CURRENT_CAMP_LAYOUT_VERSION
	elif layout_version != CURRENT_CAMP_LAYOUT_VERSION:
		_migrate_camp_whitebox(data)
	# 工程 82：聚金地脉缩图（160×90 → 64×48）的一次性坐标迁移。
	# 🔴 与上面的 `mapLayoutVersion` **完全解耦**：存量档早已有该键，复用它永远不触发；
	#    独立门保证「每个存档一生只缩一次」，否则每次读档都按同一比例再缩、坐标持续漂移。
	if String(data.get("c7GoldLayoutVersion", "")) != CURRENT_C7_GOLD_LAYOUT_VERSION:
		_migrate_c7_gold_positions(data)
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
	# ⚠ 工程 98：**与下面 M5-9c 完全同一个坑** —— `_is_valid_save` 会按 `default_player()`
	# 逐键校验 `player`，所以 `default_player()` 新增键（`classId`）时若只在 `v == 0` 分支补，
	# 存量档会在下一版上线**立刻全部判为损坏**（实测：续档直接报「player.classId 非法」，
	# 然后走备份恢复）。这里对所有版本统一补齐，缺键取默认值、已有值优先。
	if data.get("player") is Dictionary:
		data.player = _migrate_player(data.player)
	# ⚠ M5-9c：设置键补齐对**所有版本**生效，不能只放在下面的 v < CURRENT_SCHEMA 分支里。
	# default_settings() 新增键（mapScale / displayScaleMode / displayScale…）时，当前版本的存量档
	# 同样缺这些键；若只在跨版本迁移时补，新键一上线就会把全部存量档判为损坏
	# （实测事故：9c 加键后启动续档报「槽 1 主档不可用」——校验按 default_settings() 逐键查）。
	# 语义与运行时读取一致：缺键取默认值；存档已有值优先，未知键保留（见 _migrate_settings）。
	if data.get("settings") is Dictionary:
		data.settings = _migrate_settings(data.settings)
	if not data.get("questItems") is Dictionary:
		data.questItems = {}
	# E1：持久任务发奖计划对**所有版本**生效（旧档无此键 → 空字典，不因缺键判坏档）。
	data.questRewardPlans = _migrate_quest_reward_plans(data.get("questRewardPlans"))
	# C-P3-7：装备实例升级按**实例自身版本**收敛，不再按整档 schema 判断启停。
	# 无论档位版本，`equipmentRuleVersion < 4` 的实例都走同一条链（旧 ID 归并 → 等级同步），
	# 避免「合法旧实例因档位版本被跳过迁移」而被整档拒绝。
	_migrate_equipment_catalog(data)
	_migrate_equipment_requirements(data)
	# 迁移后仍无法识别的装备实例逐件丢弃（不整档拒绝）。
	_prune_unrecognized_equipment(data)
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
		if v < 15:
			data.skillRanks = {}
		data.schemaVersion = CURRENT_SCHEMA
	return data

## E1：持久任务发奖计划读档归一化 —— 只保留任务 ID 可解析、且每个待发实例都过 `_valid_item` 的记录。
## 单条非法**逐条丢弃**（不整档拒绝），与装备实例「按实例版本收敛」同一取向：坏数据只损失待发奖励，
## 不允许单个任务把整份存档判为损坏。空计划（无 item 也无 bonus）一并丢弃。
func _migrate_quest_reward_plans(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		return out
	for quest_id in (raw as Dictionary).keys():
		var entry: Variant = (raw as Dictionary)[quest_id]
		if not entry is Dictionary or not DataLoader.get_entry("quests", String(quest_id)) is Dictionary:
			continue
		var item: Variant = (entry as Dictionary).get("item", {})
		if not item is Dictionary or (not (item as Dictionary).is_empty() and not _valid_item(item)):
			continue
		var bonus_raw: Variant = (entry as Dictionary).get("bonus", [])
		if not bonus_raw is Array:
			continue
		var bonus: Array = []
		var legal := true
		for made in (bonus_raw as Array):
			if not made is Dictionary or (made as Dictionary).is_empty() or not _valid_item(made):
				legal = false
				break
			bonus.append((made as Dictionary).duplicate(true))
		if not legal:
			continue
		if (item as Dictionary).is_empty() and bonus.is_empty():
			continue
		out[String(quest_id)] = {"item": (item as Dictionary).duplicate(true), "bonus": bonus}
	return out

## 将旧营地坐标和遗留地面物迁到白盒出生区，并重置无可逆映射的营地迷雾。
## 只在布局版本旧于白盒时执行；重复读档不会重复变更物品或其他地图状态。
func _migrate_camp_whitebox(data: Dictionary) -> void:
	var spawn := Iso.grid_to_world(Vector2i(53, 53))
	if String(data.get("currentMap", "")) == "camp":
		data.playerPos = [spawn.x, spawn.y]
	var respawn: Variant = data.get("spawnRespawn", {})
	if respawn is Dictionary:
		for key in respawn:
			if String(key).begins_with("camp#") and respawn[key] is Dictionary:
				respawn[key].pos = [spawn.x, spawn.y]
	var loot: Variant = data.get("unclaimedLoot", {})
	if loot is Dictionary and loot.get("camp") is Array:
		for row in loot["camp"]:
			if row is Dictionary:
				row.pos = [spawn.x, spawn.y]
	var explored: Variant = data.get("exploredMaps", {})
	if explored is Dictionary:
		explored.erase("camp")
	data.mapLayoutVersion = CURRENT_CAMP_LAYOUT_VERSION

## v11 装备目录归并为每档每部位唯一型号；保留实例 ID、品质、星级和词条。
## 已穿但不足 Lv11 的旧第二档装备转入背包、仓库或玩家所在位置的未领取战利品，绝不丢件。
func _migrate_equipment_catalog(data: Dictionary) -> void:
	for key in ["inventory", "warehouse"]:
		var items: Variant = data.get(key)
		if items is Array:
			for item in items:
				_migrate_equipment_item(item)
	var worn: Variant = data.get("equipment")
	if worn is Dictionary:
		for slot in worn:
			var item: Variant = worn[slot]
			_migrate_equipment_item(item)
			if item is Dictionary and String(item.get("kind", "")) == "equip" \
					and int(item.get("requiredLevel", 1)) > int(data.get("player", {}).get("level", 1)):
				worn[slot] = null
				_store_migrated_unequipped(data, item)
	var by_map: Variant = data.get("unclaimedLoot")
	if by_map is Dictionary:
		for map_id in by_map:
			var rows: Variant = by_map[map_id]
			if rows is Array:
				for row in rows:
					if row is Dictionary:
						_migrate_equipment_item(row.get("item"))

## 将旧装备实例改为新目录的型号与基底（末版本由 `_migrate_equipment_requirement_item` 补到 4）。
## C-P3-7：按实例自身版本判定（`< 3` 即需归并），不再依赖整档 schema；
## 仍无法识别（模板不存在 / 基底缺失）的实例改由 `_prune_unrecognized_equipment` 逐件丢弃。
func _migrate_equipment_item(value: Variant) -> void:
	if not value is Dictionary or String(value.get("kind", "")) != "equip":
		return
	var old_id := String(value.get("itemId", ""))
	var new_id := String(EQUIPMENT_LEGACY_IDS.get(old_id, old_id))
	var tpl: Variant = DataLoader.get_entry("equipments", new_id)
	if not tpl is Dictionary or not _whole(value.get("equipmentRuleVersion"), 0, 2):
		return
	var bases: Dictionary = tpl.get("tierBases", {})
	if bases.size() != 1:
		return
	var tier := int(bases.keys()[0])
	value["itemId"] = new_id
	value["requiredLevel"] = tier
	value["level"] = tier
	value["rawBaseAttrs"] = (bases[str(tier)] as Dictionary).duplicate(true)
	value["equipmentRuleVersion"] = 3

## v12→v13：只改装备型号的穿戴等级，不重抽属性；越级已穿装备安全返还。
func _migrate_equipment_requirements(data: Dictionary) -> void:
	for key in ["inventory", "warehouse"]:
		var items: Variant = data.get(key)
		if items is Array:
			for item in items:
				_migrate_equipment_requirement_item(item)
	var worn: Variant = data.get("equipment")
	if worn is Dictionary:
		for slot in worn:
			var item: Variant = worn[slot]
			_migrate_equipment_requirement_item(item)
			if item is Dictionary and String(item.get("kind", "")) == "equip" \
					and int(item.get("requiredLevel", 1)) > int(data.get("player", {}).get("level", 1)):
				worn[slot] = null
				_store_migrated_unequipped(data, item)
	var by_map: Variant = data.get("unclaimedLoot")
	if by_map is Dictionary:
		for map_id in by_map:
			var rows: Variant = by_map[map_id]
			if rows is Array:
				for row in rows:
					if row is Dictionary:
						_migrate_equipment_requirement_item(row.get("item"))

## 旧实例的基底与词条是快照；仅同步等级标记及规则版本。
func _migrate_equipment_requirement_item(value: Variant) -> void:
	if not value is Dictionary or String(value.get("kind", "")) != "equip" or int(value.get("equipmentRuleVersion", 0)) != 3:
		return
	var tpl: Variant = DataLoader.get_entry("equipments", String(value.get("itemId", "")))
	if not tpl is Dictionary:
		return
	value["requiredLevel"] = int(tpl.get("requiredLevel", 0))
	value["level"] = int(tpl.get("requiredLevel", 0))
	value["equipmentRuleVersion"] = 4

## 将迁移后等级不足的旧穿戴装备放入空格；两个容器都满时落在当前位置并持久化。
func _store_migrated_unequipped(data: Dictionary, item: Dictionary) -> void:
	for key in ["inventory", "warehouse"]:
		var slots: Variant = data.get(key)
		if slots is Array:
			for index in range(slots.size()):
				if slots[index] == null:
					slots[index] = item
					return
	var map_id := String(data.get("currentMap", "camp"))
	var by_map: Variant = data.get("unclaimedLoot")
	if not by_map is Dictionary:
		by_map = {}
		data["unclaimedLoot"] = by_map
	if not by_map.get(map_id) is Array:
		by_map[map_id] = []
	var pos: Variant = data.get("playerPos", [0.0, 0.0])
	if not pos is Array or pos.size() != 2:
		pos = [0.0, 0.0]
	by_map[map_id].append({"uid": "migration_" + String(item.get("instanceId", "")),
		"batchId": "equipment_catalog_migration", "item": item, "pos": pos.duplicate()})

## C-P3-7：迁移后仍无法识别的装备实例**逐件丢弃**并计数，避免单件坏实例导致整档拒读。
## 只处理装备实例（`kind == "equip"`）；其他物品（药水 / 任务品等）的非法仍由
## `_is_valid_save` 整体拒绝——它们通常意味着数据表或结构级损坏，不宜静默吞掉。
func _prune_unrecognized_equipment(data: Dictionary) -> void:
	_last_pruned_equipment = 0
	for key in ["inventory", "warehouse"]:
		var slots: Variant = data.get(key)
		if not slots is Array:
			continue
		var rows: Array = slots
		for index in range(rows.size()):
			if _is_unrecognized_equipment(rows[index]):
				rows[index] = null
				_last_pruned_equipment += 1
	var worn: Variant = data.get("equipment")
	if worn is Dictionary:
		var slots: Dictionary = worn
		for slot in slots.keys():
			if _is_unrecognized_equipment(slots[slot]):
				slots[slot] = null
				_last_pruned_equipment += 1
	var by_map: Variant = data.get("unclaimedLoot")
	if by_map is Dictionary:
		var loot: Dictionary = by_map
		for map_id in loot.keys():
			var rows: Variant = loot[map_id]
			if not rows is Array:
				continue
			var kept: Array = []
			for row in (rows as Array):
				var item: Variant = (row as Dictionary).get("item") if row is Dictionary else null
				if _is_unrecognized_equipment(item):
					_last_pruned_equipment += 1
					continue
				kept.append(row)
			loot[map_id] = kept

## 是否为「无法识别的装备实例」：结构上像装备实例，但迁移后仍过不了 `_valid_item`。
func _is_unrecognized_equipment(item: Variant) -> bool:
	return item is Dictionary and String(item.get("kind", "")) == "equip" and not _valid_item(item)

func _migrate_landscape_positions(data: Dictionary) -> void:
	var old_sizes := {
		"camp": Vector2(40, 40), "wild_trial": Vector2(60, 60),
		"ash_land": Vector2(60, 60), "corruption_source": Vector2(50, 50),
	}
	var map_id := String(data.get("currentMap", ""))
	if old_sizes.has(map_id) and data.get("playerPos") is Array:
		data.playerPos = _remap_landscape_position(data.playerPos, old_sizes[map_id], map_id)
	# 旧迷雾区块坐标无可逆映射，重置探索遮罩；到访记录与剧情状态保留。
	data.exploredMaps = {}
	var respawn: Variant = data.get("spawnRespawn", {})
	if respawn is Dictionary:
		for key in respawn:
			var source_map := String(key).get_slice("#", 0)
			if old_sizes.has(source_map) and respawn[key] is Dictionary:
				var record: Dictionary = respawn[key]
				if record.get("pos") is Array:
					record.pos = _remap_landscape_position(record.pos, old_sizes[source_map], source_map)
	var loot: Variant = data.get("unclaimedLoot", {})
	if loot is Dictionary:
		for source_map in loot:
			if not old_sizes.has(String(source_map)) or not loot[source_map] is Array:
				continue
			for record in loot[source_map]:
				if record is Dictionary and record.get("pos") is Array:
					record.pos = _remap_landscape_position(record.pos, old_sizes[String(source_map)], String(source_map))

## 工程 82：聚金地脉缩图（160×90 → 64×48）的一次性坐标重映射。
## 覆盖三处会落坐标的地方：玩家位置 / 墓碑刷新点 / 未认领的地面掉落。
## 映射按格坐标等比缩放（`_remap_landscape_position`），旧图靠边的坐标不会被推到图外。
func _migrate_c7_gold_positions(data: Dictionary) -> void:
	var map_id := "c7_gold_field"
	if String(data.get("currentMap", "")) == map_id and data.get("playerPos") is Array:
		data.playerPos = _remap_landscape_position(data.playerPos, LEGACY_C7_GOLD_SIZE, map_id)
	var respawn: Variant = data.get("spawnRespawn", {})
	if respawn is Dictionary:
		for key in respawn:
			if String(key).get_slice("#", 0) == map_id and respawn[key] is Dictionary:
				var record: Dictionary = respawn[key]
				if record.get("pos") is Array:
					record.pos = _remap_landscape_position(record.pos, LEGACY_C7_GOLD_SIZE, map_id)
	var loot: Variant = data.get("unclaimedLoot", {})
	if loot is Dictionary and loot.get(map_id) is Array:
		for record in loot[map_id]:
			if record is Dictionary and record.get("pos") is Array:
				record.pos = _remap_landscape_position(record.pos, LEGACY_C7_GOLD_SIZE, map_id)
	data.c7GoldLayoutVersion = CURRENT_C7_GOLD_LAYOUT_VERSION

func _remap_landscape_position(raw: Array, old_size: Vector2, map_id: String) -> Array:
	if raw.size() != 2:
		return raw
	var new_size := MapService.grid_size(map_id)
	if new_size.x <= 0 or new_size.y <= 0:
		return raw
	var cell := Iso.world_to_grid(Vector2(float(raw[0]), float(raw[1])))
	var mapped := Vector2i(
		clampi(roundi(cell.x * float(new_size.x - 1) / (old_size.x - 1.0)), 0, new_size.x - 1),
		clampi(roundi(cell.y * float(new_size.y - 1) / (old_size.y - 1.0)), 0, new_size.y - 1))
	var world := Iso.grid_to_world(mapped)
	return [world.x, world.y]

## 应用前完整校验；无效数据不修改运行态。只有明确旧版本允许迁移缺省字段。
func apply_to_game_state(data: Dictionary) -> void:
	if not _is_valid_save(data):
		# G-P2-1：读档校验失败同样要留字段级原因（运行态保持不变，仅提示玩家）。
		push_error("[SaveManager] 读档数据校验失败：槽 %d，字段原因「%s」"
			% [int(data.get("slotId", -1)), _last_invalid_reason])
		EventBus.toast_requested.emit(Localization.tr_key("msg.save_manager.p019"), "danger")
		return
	data = _migrate(data)
	GameState.cancel_gold_batch()
	_suppress_autosave = true
	GameState.reset_equipment_prompt_session()
	GameState.skill_cooldowns = {}
	GameState.clear_buffs()
	# 5.11：药水冷却同为运行态、不落档，读档后须与技能冷却一并清零。
	Consumable.reset()

	if data.get("player", null) is Dictionary:
		GameState.player = _migrate_player(data["player"] as Dictionary)
	GameState.gold = clampi(int(data.get("gold", 0)), 0, GameState.GOLD_CAP)
	GameState.skill_ranks = data.skillRanks.duplicate(true)
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
	GameState.preferred_mount = GameState.active_mount
	GameState.equipment = _migrate_equipment(data.get("equipment", {}))
	GameState.hotbar = data.hotbar.duplicate(true)
	# 工程 98 R5：快捷栏里不属于**本档职业**的技能格必须清空。
	# 放着不管的后果不是报错，而是「点技能格没反应 + 技能面板里找不到它」——玩家无法自救。
	GameState.prune_hotbar_for_class()
	# 任务状态：经 Quest 归一化（老档 String 值 → {state, progress}，见 11 §4.1 R8）
	GameState.quest_states = Quest.normalize_states(data.get("questStates", {}))
	GameState.quest_items = _deep_int(data.get("questItems", {}))
	# E1：待发奖励计划须在场景重载前恢复 —— 交付时 `Quest._reward_plan` 会直接复用该实例。
	GameState.quest_reward_plans = _migrate_quest_reward_plans(data.get("questRewardPlans"))
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
	# M10-0：旧档的基础攻防是线性成长的（每级 +2/+1），这里按曲线基线幂等抬一次。
	# 必须放在 `GameState.equipment` 恢复**之后**（max_hp 依赖装备加成），且不落档、不写标记。
	# 工程 103：旧法师档先按旧蓝池还原百分比，再由新上限接收该百分比。
	# 标记随 player 正常落档，读同一份新版存档不会反复补蓝；武士旧值不变。
	if int(GameState.player.get("manaFormulaVersion", 0)) < GameState.MANA_FORMULA_VERSION:
		var old_mp_ratio := clampf(float(GameState.player.mp) / float(maxi(1, GameState.legacy_max_mp())), 0.0, 1.0)
		GameState.player.mp = int(round(float(GameState.max_mp()) * old_mp_ratio))
		GameState.player.manaFormulaVersion = GameState.MANA_FORMULA_VERSION
	GameState.align_baseline_stats()

	# C-P3-4：菜单流程态同属会话运行态（不落档）。成功读到存档即代表进入世界，
	# 与 reset_to_defaults 的 "menu" 成对，避免残留上一会话的菜单态。
	GameState.menu_mode = "world"
	GameState.close_all_panels()

	# HP / MP 收敛到（可能变化的）上限：装备加成改变上限时不越界、不补满
	GameState.player.hp = mini(int(GameState.player.hp), GameState.max_hp())
	GameState.player.mp = mini(int(GameState.player.mp), GameState.max_mp())

	# 工程 79：永久工具补领（读档自愈）。必须在 `_suppress_autosave = false` **之前** ——
	# 补发会广播 inventory_changed，留在抑制期内可避免「读档过程中额外落一次盘」。
	# 补发结果本身随下一次自然保存（退出存 / 拾取等）固化；即便没固化，下次读档仍会补（幂等）。
	_set_reclaim_notice(ToolReclaim.reclaim_into_game())

	_suppress_autosave = false

# ---- 工程 79：随身工具补领提示 ----

## 把补领结果翻成一条读档提示（空串 = 没补，不打扰玩家）。
## 提示不在这里广播：`apply_to_game_state` 运行时 HUD 尚未就绪，toast 会丢在空中。
func _set_reclaim_notice(result: Dictionary) -> void:
	_last_reclaim_notice = ""
	_last_reclaim_danger = false
	var given := result.get("given", []) as Array
	var to_warehouse := result.get("to_warehouse", []) as Array
	var failed := result.get("failed", []) as Array
	if given.is_empty() and failed.is_empty():
		return
	var parts: Array[String] = []
	if not given.is_empty():
		var line := Localization.tr_key("msg.save_manager.reclaim_tools") % given.size()
		if not to_warehouse.is_empty():
			line += Localization.tr_key("msg.save_manager.reclaim_warehouse") % to_warehouse.size()
		parts.append(line)
	if not failed.is_empty():
		# 补不进去是实打实的阻断（面板仍打不开），用 danger 让玩家看见。
		parts.append(Localization.tr_key("msg.save_manager.reclaim_failed"))
		_last_reclaim_danger = true
	_last_reclaim_notice = "；".join(PackedStringArray(parts))

## 取走「补领失败」标记（danger 级），取用即清空。须在 `_with_reclaim_notice` 之前调用
## —— 后者在提示为空时会提前返回，不会捎带清这个标记。
func _take_reclaim_danger() -> bool:
	var value := _last_reclaim_danger
	_last_reclaim_danger = false
	return value

## 把补领提示并到读档提示后（前置提示为空时直接采用）。取用即清空，避免跨次读档串台。
func _with_reclaim_notice(base: String) -> String:
	if _last_reclaim_notice.is_empty():
		return base
	var notice := _last_reclaim_notice
	_last_reclaim_notice = ""
	return notice if base.is_empty() else base + "；" + notice

# ---- 字段迁移 ----

## 角色字段补全：以默认模板为底，覆盖存档中的已有字段（旧档缺字段自动补默认值）。
func _migrate_player(raw: Dictionary) -> Dictionary:
	var out := GameState.default_player()
	for k in raw.keys():
		out[k] = raw[k]
	# 工程 98：职业字段与 `autoRepairEquip` 同口径 —— 默认表打底 + 旧字段覆盖，
	# **旧档因此自动补成 warrior，不 bump schema**。非法值（被改档）回退默认，不拒档。
	out["classId"] = PlayerClass.normalize(String(out.get("classId", "")))
	# 缺字段即旧法力公式；不能直接套 default_player 的新版标记，否则旧蓝量只剩小比例。
	if not raw.has("manaFormulaVersion"):
		out["manaFormulaVersion"] = 0
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

# ---- 导出与导入（角色存档搬运；见工程文档《人物存档导出与导入设计方案》）----
#
# 与读档 / 存档共用同一套校验与迁移（`_is_valid_save` / `_migrate`），不同点有三：
#   1. 导出**只读**：不走 `read_slot`，避免损坏自愈把本机存档改掉；主档坏了就导备份内容。
#   2. 导入**不采集运行态**：不复用 `save_slot`（它会 `_collect()` 当前进度并改写 `active_slot`）。
#   3. 导入**不改变 active_slot、不自动读取**：否则导入内容会在 120 秒内被自动存覆盖。

## 导出某槽为可移植的明文 JSON 文件（与槽档同一 schema、同一序列化格式）。
## 返回 { ok: bool, message: String, path: String }；失败不产生半截文件。
func export_slot(slot: int, path: String) -> Dictionary:
	var res := _read_for_export(slot)
	if not bool(res.get("ok", false)):
		var reason := String(res.get("message", ""))
		push_error("[SaveManager] 导出失败：槽 %d，原因「%s」" % [slot, reason])
		var rejected := Localization.tr_key("msg.save_manager.export_fail") % reason
		EventBus.toast_requested.emit(rejected, "danger")
		return {"ok": false, "message": rejected, "path": ""}
	if not _write_text_atomic_to(path, JSON.stringify(res.get("data", {}), "\t")):
		push_error("[SaveManager] 导出落盘失败：槽 %d，路径 %s" % [slot, path])
		var failed := Localization.tr_key("msg.save_manager.export_fail") % path
		EventBus.toast_requested.emit(failed, "danger")
		return {"ok": false, "message": failed, "path": ""}
	var clauses: Array[String] = []
	clauses.append(Localization.tr_key("msg.save_manager.export_ok") % [slot, path])
	if String(res.get("source", "main")) == "backup":
		clauses.append(Localization.tr_key("msg.save_manager.export_from_backup"))
	var message := "；".join(clauses)
	EventBus.toast_requested.emit(message, "pickup")
	return {"ok": true, "message": message, "path": path}

## 只读获取待导出内容：主档有效用主档，否则用有效备份。
## **不**触发 `_restore_backup` 的自愈写回 —— 导出是「搬走一份」，不该改动本机存档。
## 返回 { ok: bool, source: "main"/"backup"/"", data: Dictionary, message: String }。
func _read_for_export(slot: int) -> Dictionary:
	if slot < 1 or slot > MAX_SLOTS:
		return {"ok": false, "source": "", "data": {},
			"message": Localization.tr_key("msg.save_manager.bad_slot") % slot}
	var main_exists := FileAccess.file_exists(slot_path(slot))
	var main: Variant = _read_file(slot_path(slot))
	if _is_valid_save(main):
		return {"ok": true, "source": "main", "data": _migrate(main as Dictionary), "message": _pruned_notice("")}
	# 主档不存在时的 `_last_invalid_reason` 是「schemaVersion 非法：<null>」这类噪音，
	# 只在主档真存在时才留作下方的字段级原因。
	var main_reason := _last_invalid_reason if main_exists else ""
	if not FileAccess.file_exists(backup_path(slot)):
		return {"ok": false, "source": "", "data": {},
			"message": Localization.tr_key("msg.save_manager.p008") % slot}
	var bak: Variant = _read_file(backup_path(slot))
	if _is_valid_save(bak):
		return {"ok": true, "source": "backup", "data": _migrate(bak as Dictionary), "message": _pruned_notice("")}
	# 主档与备份都不可用：优先回主档的字段级原因（更贴近玩家手改坏的那一处）。
	return {"ok": false, "source": "", "data": {},
		"message": main_reason if not main_reason.is_empty() else _last_invalid_reason}

## 从外部文件导入到指定槽。校验通过才写入；**不改变 active_slot**。
## 返回 { ok: bool, message: String, pruned: int }。
func import_from_file(slot: int, path: String) -> Dictionary:
	if slot < 1 or slot > MAX_SLOTS:
		return _reject_import(slot, path, Localization.tr_key("msg.save_manager.bad_slot") % slot)
	var raw: Variant = _read_file(path)
	if not raw is Dictionary:
		return _reject_import(slot, path,
			Localization.tr_key("msg.save_manager.import_invalid") % Localization.tr_key("msg.save_manager.import_bad_json"))
	var data := raw as Dictionary
	# 版本前置检查只为把「版本不符」从「结构非法」里拆出来给玩家看：`_is_valid_save` 目前对两者
	# 都只回一句「schemaVersion 非法」。schemaVersion 缺失 / 非数值仍交由 `_is_valid_save` 报字段级原因。
	var version := int(data.get("schemaVersion", -1))
	if version > CURRENT_SCHEMA:
		return _reject_import(slot, path,
			Localization.tr_key("msg.save_manager.import_newer") % [version, CURRENT_SCHEMA])
	if _whole(data.get("schemaVersion"), 0, MIN_READABLE_SCHEMA - 1):
		return _reject_import(slot, path, Localization.tr_key("msg.save_manager.import_legacy") % version)
	if not _is_valid_save(data):
		return _reject_import(slot, path, Localization.tr_key("msg.save_manager.import_invalid") % _last_invalid_reason)
	return import_to_slot(slot, data)

## 把已校验的存档数据写入某槽（供 `import_from_file` 与自动化测试直接调用）。
## 只复用 `save_slot` 的「校验 → 备份 → 原子写入」步骤顺序，不采集运行态、不碰 `active_slot`。
## 与 `new_game` 的差异：导入**不清**旧 `.corrupt`，保留玩家此前改坏的现场。
func import_to_slot(slot: int, data: Dictionary) -> Dictionary:
	if slot < 1 or slot > MAX_SLOTS:
		return _reject_import(slot, "内嵌数据", Localization.tr_key("msg.save_manager.bad_slot") % slot)
	if not _is_valid_save(data):
		return _reject_import(slot, "内嵌数据",
			Localization.tr_key("msg.save_manager.import_invalid") % _last_invalid_reason)
	var normalized := _migrate(data)
	var pruned := _last_pruned_equipment
	# 归一化 1：槽档固有字段，必须与落点一致（`save_slot` 亦有同款改写）。
	normalized["slotId"] = slot
	# 归一化 2：角色名截断（见 `_normalize_import_name`）。
	var renamed := _normalize_import_name(normalized)
	# 归一化改动了**将要写入的字节**，故必须对最终内容再验一次（校验对象是落盘内容）。
	if not _is_valid_save(normalized):
		return _reject_import(slot, "内嵌数据",
			Localization.tr_key("msg.save_manager.import_invalid") % _last_invalid_reason)
	_ensure_dir()
	var path := slot_path(slot)
	# 与 `save_slot` 同款前提：只有主档**有效**时才留备份，否则会把可用的 .bak 覆盖成坏档（T16 前提）。
	if _is_valid_save(_read_file(path)) and not _copy_over(path, backup_path(slot)):
		push_error("[SaveManager] 导入备份失败：槽 %d，路径 %s" % [slot, backup_path(slot)])
		var backup_failed := Localization.tr_key("msg.save_manager.p004")
		EventBus.toast_requested.emit(backup_failed, "danger")
		return {"ok": false, "message": backup_failed, "pruned": pruned}
	if not _write_json_atomic(path, normalized):
		push_error("[SaveManager] 导入写入失败：槽 %d，路径 %s" % [slot, path])
		var write_failed := Localization.tr_key("msg.save_manager.import_write_fail") % slot
		EventBus.toast_requested.emit(write_failed, "danger")
		return {"ok": false, "message": write_failed, "pruned": pruned}
	var clauses: Array[String] = []
	clauses.append(Localization.tr_key("msg.save_manager.import_ok") % slot)
	if renamed:
		clauses.append(Localization.tr_key("msg.save_manager.import_name_clamped"))
	if pruned > 0:
		clauses.append(Localization.tr_key("msg.save_manager.pruned_equipment") % pruned)
	var message := "；".join(clauses)
	EventBus.toast_requested.emit(message, "pickup")
	print("[SaveManager] 已导入槽 %d（文件校验通过）" % slot)
	return {"ok": true, "message": message, "pruned": pruned}

## 导入失败：留在日志与 toast，返回失败结构；**不做任何写入**（目标槽字节不变）。
func _reject_import(slot: int, source: String, message: String) -> Dictionary:
	push_error("[SaveManager] 导入被拒（槽 %d，来源 %s）：%s" % [slot, source, message])
	EventBus.toast_requested.emit(message, "danger")
	return {"ok": false, "message": message, "pruned": 0}

## 导入归一化：角色名去首尾空白并按 `MAX_PLAYER_NAME_LENGTH` 截断。
## 校验只要求「非空字符串」而 UI 输入框限 16 字，手改超长名会撑坏卡面与角色面板。
## 返回是否发生改写；**全空白名保持原值不动**（不静默改名，若真非法由 `_is_valid_save` 拒绝）。
func _normalize_import_name(data: Dictionary) -> bool:
	var player: Variant = data.get("player")
	if not player is Dictionary:
		return false
	var current := String((player as Dictionary).get("name", ""))
	var cleaned := current.strip_edges()
	if cleaned.is_empty():
		return false
	var clamped := cleaned.substr(0, MAX_PLAYER_NAME_LENGTH)
	(player as Dictionary)["name"] = clamped
	return clamped != current

## 把文本原子写到任意路径（导出用）：tmp 写好 → 读回校验 → 改名替换。
## 任一步失败删除临时文件并返回 false，**不产生半截目标文件**。
## 与 `_write_json_atomic` 同款保证，但不限定在 `SAVE_DIR` 内（导出目标是玩家选的任意目录）。
func _write_text_atomic_to(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 无法写入临时导出文件：%s" % tmp)
		return false
	f.store_string(text)
	f.close()
	if not _verify_written(tmp, text):
		push_error("[SaveManager] 导出写入校验失败（内容不完整），已删除临时文件：%s" % tmp)
		DirAccess.remove_absolute(tmp)
		return false
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("[SaveManager] 导出改名失败（err=%d）：%s" % [err, path])
		DirAccess.remove_absolute(tmp)
		return false
	return true

## 导出文件名：清洗角色名中的路径分隔符 / 通配符 / 控制字符并截断为 16 字，空名回退 `character`；
## 附时间戳避免同名覆盖。仅用于文件名，不改动存档内的角色名。
func export_file_name(character_name: String, level: int) -> String:
	var safe := character_name.strip_edges().substr(0, MAX_PLAYER_NAME_LENGTH)
	for ch in ILLEGAL_FILENAME_CHARS:
		safe = safe.replace(ch, "_")
	var cleaned := ""
	for i in safe.length():
		cleaned += "_" if safe.unicode_at(i) < 32 else safe[i]
	if cleaned.is_empty():
		cleaned = "character"
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	return "save_%s_Lv%d_%s.json" % [cleaned, level, stamp]

# ---- 底层文件操作 ----

## 原子写入：tmp 写好 → 校验回读 → 替换主档（10.3）。
func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var text := JSON.stringify(data, "\t")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 无法写入临时存档：%s" % tmp)
		return false
	f.store_string(text)
	f.close()
	# C-P3-6：写后读回校验。磁盘写满 / 写入中断会把内容截断；若不校验就 rename 成主档，
	# 截断档要等下次读档解析失败才回退 .bak —— 本次会话最新进度已在回退中丢失且当时无提示。
	# 失败时**不 rename**，保留 tmp 供排查。
	if not _verify_written(tmp, text):
		push_error("[SaveManager] 写入校验失败（内容不完整），已保留现场：%s" % tmp)
		return false
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("[SaveManager] 替换存档失败（err=%d）：%s" % [err, path])
		DirAccess.remove_absolute(tmp)
		return false
	return true

## 写后读回校验：文件可打开、完整读回且与写入内容逐字一致。
func _verify_written(path: String, expected: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	return text == expected

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
	_last_invalid_reason = ""
	if not raw is Dictionary or not _whole(raw.get("schemaVersion"), MIN_READABLE_SCHEMA, CURRENT_SCHEMA):
		return _reject("schemaVersion 非法：%s" % str(raw.get("schemaVersion", "缺失") if raw is Dictionary else raw))
	if not raw.get("player") is Dictionary or not _whole(raw.player.get("level"), 1):
		return _reject("player.level 非法")
	if not _whole(raw.get("gold"), 0, GameState.GOLD_CAP):
		return _reject("gold 非法")
	var data := _migrate(raw)
	for key in ["player", "equipment", "questStates", "firstClear", "unlocks", "settings", "exploredMaps", "questRewardPlans", "skillRanks"]:
		if not data.get(key) is Dictionary:
			return _reject("%s 应为字典" % key)
	if not _whole(data.get("inventoryExpansions"), 0, Warehouse.max_expansions()):
		return _reject("inventoryExpansions 非法")
	if not data.get("inventory") is Array or data.inventory.size() != Warehouse.capacity(int(data.inventoryExpansions)):
		return _reject("inventory 长度与扩容不符")
	if not _whole(data.get("warehouseExpansions"), 0, Warehouse.max_expansions()):
		return _reject("warehouseExpansions 非法")
	for skill_id in data.skillRanks.keys():
		var sid := String(skill_id)
		var value: Variant = data.skillRanks[skill_id]
		var step := SkillProgression.step(sid, int(value) if _whole(value, 2, 5) else 0)
		if not skill_id is String or not _whole(value, 2, 5) or step.is_empty() \
				or int(data.player.level) < int(step.get("unlockLevel", 99999)):
			return _reject("skillRanks.%s 阶数或角色等级非法" % sid)
	if not data.get("warehouse") is Array or data.warehouse.size() != Warehouse.capacity(int(data.warehouseExpansions)):
		return _reject("warehouse 长度与扩容不符")
	if not data.get("ownedMounts") is Array or not data.get("activeMount") is String:
		return _reject("ownedMounts / activeMount 类型非法")
	if not HotbarConfig.valid_layout(data.get("hotbar")):
		return _reject("hotbar 布局非法")
	var seen_mounts := {}
	for mount_id in data.ownedMounts:
		if not mount_id is String or not DataLoader.get_entry("mounts", mount_id) is Dictionary or seen_mounts.has(mount_id):
			return _reject("ownedMounts 含未知或重复坐骑：%s" % str(mount_id))
		seen_mounts[mount_id] = true
	if not data.activeMount.is_empty() and not seen_mounts.has(data.activeMount):
		return _reject("activeMount 未在收藏中：%s" % data.activeMount)
	if not data.get("currentMap") is String or DataLoader.get_entry("maps", data.currentMap) == null:
		return _reject("currentMap 未知：%s" % str(data.get("currentMap")))
	if not data.get("visitedMaps") is Array:
		return _reject("visitedMaps 应为数组")
	for map_id in data.visitedMaps:
		if not map_id is String or not DataLoader.get_entry("maps", map_id) is Dictionary:
			return _reject("visitedMaps 含未知地图：%s" % str(map_id))
	# M4-10：世界时钟与怪物点刷新状态（v7 起；旧档由 _migrate 补默认）
	if not _number(data.get("worldTime")) or float(data.worldTime) < 0.0:
		return _reject("worldTime 非法")
	if not _valid_spawn_respawn(data.get("spawnRespawn")):
		return _reject("spawnRespawn 结构非法")
	# M6-0c：未领取战利品结构（v8 起；旧档由 _migrate 补空集合）
	if not _valid_unclaimed_loot(data.get("unclaimedLoot")):
		return _reject("unclaimedLoot 结构非法")
	# E1：待发奖励计划已由 `_migrate_quest_reward_plans` 逐条收敛，这里只拦「任务 ID 不可解析」级别。
	for plan_id in data.questRewardPlans:
		if not plan_id is String or not DataLoader.get_entry("quests", String(plan_id)) is Dictionary:
			return _reject("questRewardPlans 含未知任务：%s" % str(plan_id))
	if not data.get("savedAt") is String or not _whole(data.get("slotId"), -1, MAX_SLOTS):
		return _reject("savedAt / slotId 非法")
	var pos: Variant = data.get("playerPos")
	if not data.has("playerPos") or (pos != null and (not pos is Array or pos.size() != 2)):
		return _reject("playerPos 结构非法")
	if pos is Array:
		for value in pos:
			if not _number(value):
				return _reject("playerPos 含非数值")
	for key in GameState.default_player():
		var value: Variant = data.player.get(key)
		if key == "name":
			if not value is String or value.is_empty():
				return _reject("player.name 非法")
		elif key == "classId":
			# 工程 98：职业 id 是**字符串枚举**，不是数值。这段循环会把 `default_player()`
			# 里除 `name` 外的每个键都当非负数校验 —— 加了 `classId` 却忘了这里，
			# 结果就是**所有存档全部读不进来**（报错文案还是「player.classId 应为非负数」）。
			# 🔴 非法 id 不拒档：交给 `_migrate_player` 归一成默认职业，避免被改档的人彻底进不去。
			if not value is String or String(value).is_empty():
				return _reject("player.classId 非法")
		elif not _number(value) or float(value) < 0:
			return _reject("player.%s 应为非负数" % key)
	for key in ["level", "xp", "hp", "mp"]:
		var maximum: float = GameState.PLAYER_LEVEL_CAP if key == "level" else 9007199254740991.0
		if not _whole(data.player.get(key), 1.0 if key == "level" else 0.0, maximum):
			return _reject("player.%s 非法或越界" % key)
	if not _whole(data.player.get("manaFormulaVersion"), 0, GameState.MANA_FORMULA_VERSION):
		return _reject("player.manaFormulaVersion 非法")
	# C-P3-1：与战斗侧一致的上界（产品 03 §3.8 / Combat 常量），拦明显异常或被篡改的值。
	for key in ["attack", "defense", "dodge", "block"]:
		if not _number(data.player.get(key)) or float(data.player[key]) > GameState.PLAYER_STAT_CAP:
			return _reject("player.%s 超上界" % key)
	if not _number(data.player.get("criticalChance")) or float(data.player.criticalChance) > Combat.MAX_CRIT_CHANCE:
		return _reject("player.criticalChance 超上界")
	if not _number(data.player.get("criticalMultiplier")) \
			or float(data.player.criticalMultiplier) < 1.0 or float(data.player.criticalMultiplier) > Combat.MAX_CRIT_MULT:
		return _reject("player.criticalMultiplier 越界")
	if not _number(data.player.get("cdr")) or float(data.player.cdr) > GameState.PLAYER_CDR_CAP:
		return _reject("player.cdr 超上界")
	if not _number(data.player.get("attackInterval")) or float(data.player.attackInterval) < Combat.MIN_ATTACK_INTERVAL:
		return _reject("player.attackInterval 低于下限")
	if not _number(data.player.get("movementSpeed")) or float(data.player.movementSpeed) > GameState.PLAYER_MOVE_SPEED_CAP:
		return _reject("player.movementSpeed 超上界")
	for item in data.inventory:
		if item != null and not _valid_item(item):
			return _reject("inventory 含非法物品")
	for item in data.warehouse:
		if item != null and not _valid_item(item):
			return _reject("warehouse 含非法物品")
	if data.equipment.size() != Equipment.SLOT_DEFS.size():
		return _reject("equipment 槽数量不符")
	for slot in Equipment.create():
		if not data.equipment.has(slot):
			return _reject("equipment 缺槽：%s" % slot)
		var item: Variant = data.equipment[slot]
		if item != null and (not _valid_item(item) or item.kind != "equip" or not Equipment.slot_accepts(slot, item)):
			return _reject("equipment.%s 非法" % slot)
	# C-P2-2：解锁 / 首杀键必须来自数据表（合法解锁 id / Boss id），值必须是 bool。
	_ensure_legal_keys()
	for key in ["firstClear", "unlocks"]:
		var legal: Dictionary = _known_unlock_ids if key == "unlocks" else _known_boss_ids
		# 数据表不可用（缺失 / 解析失败）时跳过白名单，避免把全部存档误判损坏。
		var strict := not legal.is_empty()
		for entry_key in data[key].keys():
			if not data[key][entry_key] is bool:
				return _reject("%s 值应为 bool" % key)
			if strict and not legal.has(String(entry_key)):
				return _reject("%s 含未登记键：%s" % [key, str(entry_key)])
	for value in data.questStates.values():
		if value is String:
			if not Quest._is_known_state(value):
				return _reject("questStates 含未知状态：%s" % value)
		elif not value is Dictionary or not value.get("state") is String or not Quest._is_known_state(value.state) or not _whole(value.get("progress"), 0):
			return _reject("questStates 条目结构非法")
	for key in GameState.default_settings():
		var value: Variant = data.settings.get(key)
		var default_value: Variant = GameState.default_settings()[key]
		if default_value is bool:
			if not value is bool:
				return _reject("settings.%s 应为 bool" % key)
		elif default_value is Dictionary:
			if not value is Dictionary or not SettingsRuntime.valid_bindings(value):
				return _reject("settings.%s 键位非法" % key)
		elif default_value is String:
			if not value is String:
				return _reject("settings.%s 应为 String" % key)
			# C-P2-1：只对**已登记枚举止**的 String 键校验值域；未登记键不做值域校验，
			# 避免「新增 String 设置键漏注册」把全量存量档判为损坏（M5-9c 实测事故）。
			# 漏注册由 `tests/smoke_test.gd` 的逐键断言在冒烟阶段拦下。
			if SettingsRuntime.is_choice_key(key) and not SettingsRuntime.valid_choice(key, value):
				return _reject("settings.%s 值非法：%s" % [key, value])
		# C-P2-3：数值键按 `SettingsRuntime.NUMERIC_RANGES` 单一来源校验区间。
		elif not _number(value) or not SettingsRuntime.valid_setting_number(key, float(value)):
			return _reject("settings.%s 数值越界" % key)
	return true

## 校验失败：记录字段级原因并返回 false（供 `_is_valid_save` 内部使用）。
func _reject(reason: String) -> bool:
	if _last_invalid_reason.is_empty():
		_last_invalid_reason = reason
	return false

## C-P2-2：惰性构建合法解锁键 / Boss 键白名单（数据表重新加载时失效重建）。
func _ensure_legal_keys() -> void:
	if _legal_keys_ready:
		return
	_legal_keys_ready = true
	_known_unlock_ids = {}
	_known_boss_ids = {}
	var quests: Variant = DataLoader.get_table("quests")
	if quests is Array:
		for quest in (quests as Array):
			if not quest is Dictionary:
				continue
			var reward: Variant = (quest as Dictionary).get("reward", {})
			if not reward is Dictionary:
				continue
			var unlocks: Variant = (reward as Dictionary).get("unlocks", [])
			if not unlocks is Array:
				continue
			for unlock in (unlocks as Array):
				_known_unlock_ids[String(unlock)] = true
	var monsters: Variant = DataLoader.get_table("monsters")
	if monsters is Array:
		for monster in (monsters as Array):
			if not monster is Dictionary:
				continue
			var entry := monster as Dictionary
			if String(entry.get("kind", "")) != "boss":
				continue
			_known_boss_ids[String(entry.get("id", ""))] = true
			var first_clear: Variant = entry.get("firstClearReward", {})
			if first_clear is Dictionary:
				var unlock := String((first_clear as Dictionary).get("unlock", ""))
				if not unlock.is_empty():
					_known_unlock_ids[unlock] = true

## 数据表重载后使白名单缓存失效（下次校验时重建）。
func _invalidate_legal_keys() -> void:
	_legal_keys_ready = false

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
		if item.has("favorite") and not item.favorite is bool:
			return false
		# 工程 77：`durability` 是**可选字段**（`favorite` 先例）——缺失 = 满耐久，旧档零迁移。
		# 字段存在时宽松上界 10000（**不写死 800**，上限在 durability.json 可调），
		# 写死会让调高上限后旧档逐件判毁档（D-21 静默毁档教训）。
		if item.has("durability") and not _whole(item.get("durability"), 0, 10000):
			return false
		# M10-1：上限放进 5（v5 = 61+ 动态实例）；下限仍是 4，v3 及更早不走这条路。
		if not _whole(item.get("equipmentRuleVersion"), 4, 5) or not item.get("rawBaseAttrs") is Dictionary or not item.get("affixes") is Array or not item.get("pctAttrs") is Array:
			return false
		if item.rawBaseAttrs.is_empty() or not _whole(item.get("count", 1), 1, 1) \
				or not ReforgeAffixes.valid_state(item) or item.pctAttrs.size() > 1:
			return false
		if not _whole(item.get("requiredLevel"), 1) or not _whole(item.get("level"), 1) or int(item.level) != int(item.requiredLevel) \
				or not _whole(item.get("star"), 0, 12) or not ItemUtil.is_valid_quality(str(item.get("quality", ""))):
			return false
		var template: Dictionary = DataLoader.get_entry("equipments", String(item.itemId))
		var bases: Dictionary = template.get("tierBases", {})
		var tier_key := str(ItemFactory.tier_start_for_template(String(item.itemId)))
		# 实例基底是生成时的数值快照；后续数值平衡不应让合法存档失效。
		# M10-1：v4 保持「严格等于模板等级」（改档抬等级这条路继续堵着）；
		# v5 是动态实例，等级由生成时决定，只校验「> 60 且 ≤ 上限」+ 必须挂循环套。
		var level_ok := false
		if int(item.equipmentRuleVersion) == ItemFactory.RULE_VERSION_DYNAMIC:
			level_ok = bases.size() == 1 and bases.has(tier_key) \
					and tier_key == str(ItemFactory.DYNAMIC_BASE_TIER) \
					and int(item.requiredLevel) > Balance.SOFTCAP_LEVEL \
					and int(item.requiredLevel) <= GameState.PLAYER_LEVEL_CAP
		else:
			level_ok = bases.size() == 1 and bases.has(tier_key) \
					and int(item.requiredLevel) == int(template.get("requiredLevel", 0))
		if not level_ok:
			return false
		if not _number(item.get("qualityMultiplierSnapshot")) or float(item.qualityMultiplierSnapshot) <= 0.0 \
				or float(item.qualityMultiplierSnapshot) > 100.0 or not _number(item.get("starMultiplierSnapshot")) \
				or float(item.starMultiplierSnapshot) < 0.0 or float(item.starMultiplierSnapshot) > 1.0:
			return false
		for stat in item.rawBaseAttrs:
			var value: Variant = item.rawBaseAttrs[stat]
			if not ["atk", "def", "hp", "mp"].has(String(stat)) or not _number(value) or float(value) < 0.0:
				return false
		var seen_stats := {}
		for effect in item.affixes + item.pctAttrs:
			if not effect is Dictionary or not effect.get("stat") is String or not _number(effect.get("value")):
				return false
			var stat := String(effect.stat)
			# 词条白名单与 equipmentRules 的 fixedAffixes/percentAffixes 键保持一致（战斗词条仅 cdr 已开放）。
			if not ["atk", "def", "hp", "mp", "hpPercent", "mpPercent", "cdr"].has(stat) \
					or seen_stats.has(stat) or float(effect.value) < 0.0:
				return false
			seen_stats[stat] = true
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
			var item: Variant = record.get("item")
			if not (item is Dictionary) or (not _valid_item(item) and not _valid_ground_coin(item)
					and not _valid_ground_mount(item)):
				return false
			var pos: Variant = record.get("pos", null)
			if not (pos is Array) or (pos as Array).size() != 2:
				return false
			for value in (pos as Array):
				if not _number(value):
					return false
	return true

## 精英 / Boss 的金币也可以保留在地面；金币不是背包物品，故只在未领取记录中放行。
func _valid_ground_coin(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "coin" and String(item.get("itemId", "")) == "coin" \
		and _whole(item.get("gold"), 1, GameState.GOLD_CAP) and _whole(item.get("count", 1), 1)

## 坐骑拾取后进入收藏而非背包，同样仅在未领取地面物中允许。
func _valid_ground_mount(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "mount" and DataLoader.get_entry("mounts", String(item.get("itemId", ""))) is Dictionary \
		and _whole(item.get("count", 1), 1, 1)

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
		# C-P3-5：写失败不静默 —— last_slot 未更新会让主菜单「继续」落空且无法解释。
		push_warning("[SaveManager] 无法写入最近槽位记录：%s" % LAST_SLOT_FILE)
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
