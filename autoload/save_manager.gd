extends Node
## SaveManager — 单机存档（单例 / Autoload）。
##
## 机制（见 docs/产品文档/10 数据配置与存档技术 10.3）：
##   - 3 个独立存档槽；写入 user://saves/slot_N.json。
##   - 原子写入：先写临时文件，成功后替换主档；保留一份最近有效备份（.bak）。
##   - 版本迁移：读取时按 schemaVersion 递增补默认值（旧档导入）。
##   - 写入失败提示不静默丢失；不持久化运行时节点对象。

const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 3
const CURRENT_SCHEMA := 1

func _ready() -> void:
	_ensure_dir()

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot

## 是否存在某槽存档。
func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

## 采集当前运行时状态为存档字典。
func _collect() -> Dictionary:
	return {
		"schemaVersion": CURRENT_SCHEMA,
		"savedAt": Time.get_datetime_string_from_system(),
		"player": GameState.player,
		"gold": GameState.gold,
		"currentMap": GameState.current_map,
		"questStates": GameState.quest_states,
		"firstClear": GameState.first_clear,
		"settings": GameState.settings,
	}

## 原子写入：tmp 写好 -> 备份旧档 -> 替换主档。
func save_slot(slot: int) -> bool:
	_ensure_dir()
	var data := _collect()
	data["slotId"] = slot

	var path := _slot_path(slot)
	var tmp := path + ".tmp"

	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 无法写入临时存档：%s" % tmp)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

	# 备份现有有效存档（最近一份），保障可回滚。
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.copy_absolute(path, bak)

	# 原子替换。
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("[SaveManager] 替换存档失败（err=%d）：%s" % [err, path])
		return false

	print("[SaveManager] 已保存到槽 %d：%s" % [slot, path])
	return true

## 读取某槽存档（含版本迁移）。返回 {} 表示无存档或损坏。
func load_slot(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[SaveManager] 无法读取存档：%s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		push_error("[SaveManager] 存档损坏，已保留备份：%s" % path)
		return {}
	return _migrate(data)

## 版本迁移：为旧档补齐新增字段的默认值。
func _migrate(data: Dictionary) -> Dictionary:
	var v: int = int(data.get("schemaVersion", 1))
	if v < 1:
		# 示例：未来 schemaVersion 提升时在此补默认值。
		data["schemaVersion"] = 1
	return data

## 应用存档到运行时状态。
func apply_to_game_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	GameState.player = data.get("player", GameState.player)
	GameState.gold = int(data.get("gold", 0))
	GameState.current_map = String(data.get("currentMap", "camp"))
	GameState.quest_states = data.get("questStates", {})
	GameState.first_clear = data.get("firstClear", {})
	GameState.settings = data.get("settings", GameState.settings)

## 删除某槽存档（含备份）。
func delete_slot(slot: int) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var p: String = _slot_path(slot) + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
