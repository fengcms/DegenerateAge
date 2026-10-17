extends Node
## 角色存档导出与导入（工程文档《人物存档导出与导入设计方案》§7.1 T1–T9）。
##
## 隔离性：只用槽 1 / 2，进入时快照、退出时还原；导出文件写在 user:// 下并在结束时删除。
## 断言覆盖：导出可解析且键集合一致（T1）、改档后导入逐字段一致（T2）、坏文件不写盘（T3/T4/T5）、
## 覆盖前留备份（T6）、不改变活动槽（T7）、角色名截断提示（T8）、空槽导出失败（T9）。

const SOURCE_SLOT := 1
const TARGET_SLOT := 2
const EXPORT_PATH := "user://save_transfer_test_export.json"
const SOURCE_NAME := "导出测试者"
const SOURCE_GOLD := 4321

var _failures: Array[String] = []

func _ready() -> void:
	var prev_active: int = SaveManager.active_slot
	var snaps := {SOURCE_SLOT: _snapshot_saves(SOURCE_SLOT), TARGET_SLOT: _snapshot_saves(TARGET_SLOT)}
	GameState.reset_to_defaults()
	SaveManager.delete_slot(SOURCE_SLOT)
	SaveManager.delete_slot(TARGET_SLOT)

	_test_export_round_trip()
	_test_import_modified()
	_test_import_broken_file()
	_test_import_future_version()
	_test_import_legacy()
	_test_import_backup_preserved()
	_test_active_slot_untouched()
	_test_name_clamped()
	_test_export_empty_slot()

	SaveManager.active_slot = prev_active
	_remove_export_file()
	for slot in snaps:
		_restore_saves(int(slot), snaps[slot])
	_finish()

## T1：有效档导出 → 文件存在、无残留 .tmp、JSON 可解析、顶层键集合与 `_collect` 一致。
func _test_export_round_trip() -> void:
	_prepare_source()
	var result := SaveManager.export_slot(SOURCE_SLOT, EXPORT_PATH)
	_check(bool(result.get("ok", false)), "有效档应能导出")
	_check(FileAccess.file_exists(EXPORT_PATH), "导出文件应生成")
	_check(not FileAccess.file_exists(EXPORT_PATH + ".tmp"), "导出后不应残留临时文件")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPORT_PATH))
	_check(parsed is Dictionary, "导出文件应是可解析的 JSON 对象")
	if not parsed is Dictionary:
		return
	var doc: Dictionary = parsed
	var expected: Array = SaveManager._collect().keys()
	var actual: Array = doc.keys()
	expected.sort()
	actual.sort()
	_check(actual == expected, "导出顶层键集合应与存档采集一致：实际 %s" % str(actual))
	_check(int(doc.get("slotId", -1)) == SOURCE_SLOT, "导出保留源槽号")
	var player: Dictionary = doc.get("player", {})
	_check(String(player.get("name", "")) == SOURCE_NAME, "导出保留源角色名")

## T2：导出 → 改角色名 / 等级 / 金币 → 导入另一槽 → 改动的字段生效，其余字段逐字段一致。
func _test_import_modified() -> void:
	_prepare_source()
	var exported := SaveManager.export_slot(SOURCE_SLOT, EXPORT_PATH)
	_check(bool(exported.get("ok", false)), "导出源档用于改档")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPORT_PATH))
	_check(parsed is Dictionary, "改档前导出文件应可解析")
	if not parsed is Dictionary:
		return
	var doc: Dictionary = parsed
	var player: Dictionary = doc.get("player", {})
	player["name"] = "改档者"
	player["level"] = 42
	doc["gold"] = 999999
	_write_raw(EXPORT_PATH, JSON.stringify(doc, "\t"))
	var result := SaveManager.import_from_file(TARGET_SLOT, EXPORT_PATH)
	_check(bool(result.get("ok", false)), "合法改档应能导入")
	var target := SaveManager.read_slot(TARGET_SLOT)
	_check(bool(target.get("ok", false)), "导入后目标槽应可读")
	var data: Dictionary = target.get("data", {})
	var stored_player: Dictionary = data.get("player", {})
	_check(String(stored_player.get("name", "")) == "改档者" and int(stored_player.get("level", 0)) == 42
		and int(data.get("gold", 0)) == 999999, "改动的角色名 / 等级 / 金币应生效")
	var expected := SaveManager._migrate(doc)
	expected["slotId"] = TARGET_SLOT
	_check(_same_value(data, expected), "除槽号外其余字段应逐字段一致：差异 %s" % _diff_fields(expected, data))

## T3：截断 JSON / 缺 schemaVersion / 结构非法 → 明确拒绝，目标槽全部落盘文件字节不变。
func _test_import_broken_file() -> void:
	_prepare_target()
	var before := _digest(TARGET_SLOT)
	_write_raw(EXPORT_PATH, "{\"schemaVersion\": 14, \"player\":")
	var truncated := SaveManager.import_from_file(TARGET_SLOT, EXPORT_PATH)
	_check(not bool(truncated.get("ok", false)), "截断文件应被拒绝")
	_check(_digest(TARGET_SLOT) == before, "截断文件被拒后目标槽字节不变")
	var missing := SaveManager._collect()
	missing.erase("schemaVersion")
	_write_raw(EXPORT_PATH, JSON.stringify(missing, "\t"))
	var absent := SaveManager.import_from_file(TARGET_SLOT, EXPORT_PATH)
	_check(not bool(absent.get("ok", false)), "缺 schemaVersion 的文件应被拒绝")
	_check(_digest(TARGET_SLOT) == before, "缺版本文件被拒后目标槽字节不变")
	var broken := SaveManager._collect()
	var inventory: Array = broken.get("inventory", [])
	broken["inventory"] = inventory.slice(0, 1)
	_write_raw(EXPORT_PATH, JSON.stringify(broken, "\t"))
	var illegal := SaveManager.import_from_file(TARGET_SLOT, EXPORT_PATH)
	_check(not bool(illegal.get("ok", false)), "背包长度与扩容不符的文件应被拒绝")
	_check(not String(illegal.get("message", "")).is_empty(), "拒绝时必须给出字段级原因")
	_check(_digest(TARGET_SLOT) == before, "结构非法文件被拒后目标槽字节不变")

## T4：schemaVersion = 当前版本 + 1 → 提示「来自更新版本」，目标槽不变。
func _test_import_future_version() -> void:
	_prepare_target()
	var before := _digest(TARGET_SLOT)
	var future := SaveManager._collect()
	future["schemaVersion"] = SaveManager.CURRENT_SCHEMA + 1
	_write_raw(EXPORT_PATH, JSON.stringify(future, "\t"))
	var result := SaveManager.import_from_file(TARGET_SLOT, EXPORT_PATH)
	_check(not bool(result.get("ok", false)), "未来版本存档应被拒绝")
	_check(String(result.get("message", "")) == Localization.tr_key("msg.save_manager.import_newer")
		% [SaveManager.CURRENT_SCHEMA + 1, SaveManager.CURRENT_SCHEMA], "应提示来自更新版本并给出双方版本号")
	_check(_digest(TARGET_SLOT) == before, "未来版本被拒后目标槽字节不变")

## T5：schemaVersion = 10（低于可读下限）→ 提示「版本过旧」，目标槽不变。
func _test_import_legacy() -> void:
	_prepare_target()
	var before := _digest(TARGET_SLOT)
	var legacy := SaveManager._collect()
	legacy["schemaVersion"] = SaveManager.MIN_READABLE_SCHEMA - 1
	_write_raw(EXPORT_PATH, JSON.stringify(legacy, "\t"))
	var result := SaveManager.import_from_file(TARGET_SLOT, EXPORT_PATH)
	_check(not bool(result.get("ok", false)), "过旧版本存档应被拒绝")
	_check(String(result.get("message", "")) == Localization.tr_key("msg.save_manager.import_legacy")
		% (SaveManager.MIN_READABLE_SCHEMA - 1), "应提示版本过旧并给出版本号")
	_check(_digest(TARGET_SLOT) == before, "过旧版本被拒后目标槽字节不变")

## T6：目标槽已有有效档 → 导入后 .bak 存在，且内容等于导入前的主档。
func _test_import_backup_preserved() -> void:
	_prepare_source()
	GameState.reset_to_defaults()
	GameState.gold = 111
	_check(SaveManager.save_slot(TARGET_SLOT, true), "目标槽先建立有效档")
	var before_main := FileAccess.get_file_as_string(SaveManager.slot_path(TARGET_SLOT))
	var exported := SaveManager.export_slot(SOURCE_SLOT, EXPORT_PATH)
	_check(bool(exported.get("ok", false)), "导出源档")
	var result := SaveManager.import_from_file(TARGET_SLOT, EXPORT_PATH)
	_check(bool(result.get("ok", false)), "覆盖已有有效档应成功")
	_check(FileAccess.file_exists(SaveManager.backup_path(TARGET_SLOT)), "覆盖后应留下备份")
	_check(FileAccess.get_file_as_string(SaveManager.backup_path(TARGET_SLOT)) == before_main,
		"备份内容应等于导入前的主档")
	_check(_slot_gold(TARGET_SLOT) == SOURCE_GOLD, "导入内容已落盘")

## T7：`import_to_slot` 前后 `active_slot` 与最近槽记录都不变（导入不改变当前游戏中的槽）。
func _test_active_slot_untouched() -> void:
	_prepare_source()
	SaveManager.active_slot = 3
	var last_before := SaveManager._read_last_slot()
	var source := SaveManager.read_slot(SOURCE_SLOT)
	var result := SaveManager.import_to_slot(TARGET_SLOT, source.get("data", {}))
	_check(bool(result.get("ok", false)), "直接导入到槽应成功")
	_check(SaveManager.active_slot == 3, "导入不应改变 active_slot")
	_check(SaveManager._read_last_slot() == last_before, "导入不应改写最近槽记录")
	_check(_slot_gold(TARGET_SLOT) == SOURCE_GOLD, "目标槽写入导入内容")

## T8：角色名 200 字 → 导入后截断为 16 字，并给出截断提示。
func _test_name_clamped() -> void:
	_prepare_source()
	var source := SaveManager.read_slot(SOURCE_SLOT)
	var data: Dictionary = source.get("data", {})
	var player: Dictionary = data.get("player", {})
	player["name"] = "甲".repeat(200)
	var result := SaveManager.import_to_slot(TARGET_SLOT, data)
	_check(bool(result.get("ok", false)), "超长角色名应可导入（截断后）")
	var stored := _slot_name(TARGET_SLOT)
	_check(stored.length() == SaveManager.MAX_PLAYER_NAME_LENGTH, "角色名应截断为 16 字：实际 %d" % stored.length())
	_check(String(result.get("message", "")).contains(Localization.tr_key("msg.save_manager.import_name_clamped")),
		"截断必须给出提示（不静默改写）")

## T9：空槽（主档与备份都不存在）→ 导出返回失败且不生成文件。
func _test_export_empty_slot() -> void:
	SaveManager.delete_slot(SOURCE_SLOT)
	_remove_export_file()
	var result := SaveManager.export_slot(SOURCE_SLOT, EXPORT_PATH)
	_check(not bool(result.get("ok", false)), "空槽导出应失败")
	_check(not FileAccess.file_exists(EXPORT_PATH), "导出失败不应生成文件")
	_check(not FileAccess.file_exists(EXPORT_PATH + ".tmp"), "导出失败不应残留临时文件")

# ---- 夹具 ----

## 造一份有效源档（槽 1）：带可核对的角色名 / 等级 / 金币，且写入前清掉同槽旧档。
func _prepare_source() -> void:
	SaveManager.delete_slot(SOURCE_SLOT)
	GameState.reset_to_defaults()
	GameState.player.name = SOURCE_NAME
	GameState.player.level = 7
	GameState.gold = SOURCE_GOLD
	if not SaveManager.save_slot(SOURCE_SLOT, true):
		_failures.append("夹具失败：无法写入源槽有效档")

## 造一份有效目标档（槽 2），用于「被拒绝时目标槽字节不变」的断言。
func _prepare_target() -> void:
	SaveManager.delete_slot(TARGET_SLOT)
	GameState.reset_to_defaults()
	GameState.gold = 222
	if not SaveManager.save_slot(TARGET_SLOT, true):
		_failures.append("夹具失败：无法写入目标槽有效档")

## 某槽已落盘档案的金币值（读不到时返回 -1）。
func _slot_gold(slot: int) -> int:
	var result := SaveManager.read_slot(slot)
	if not bool(result.get("ok", false)):
		return -1
	var data: Dictionary = result.get("data", {})
	return int(data.get("gold", -1))

## 某槽已落盘档案的角色名（读不到时返回空串）。
func _slot_name(slot: int) -> String:
	var result := SaveManager.read_slot(slot)
	if not bool(result.get("ok", false)):
		return ""
	var data: Dictionary = result.get("data", {})
	var player: Dictionary = data.get("player", {})
	return String(player.get("name", ""))

## 语义值比较：数字不区分 int / float（JSON 往返会改变数字类型），数组 / 字典按元素递归。
func _same_value(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		var a: Dictionary = left
		var b: Dictionary = right
		if a.size() != b.size():
			return false
		for key in a.keys():
			if not b.has(key) or not _same_value(a[key], b[key]):
				return false
		return true
	if left is Array and right is Array:
		var a: Array = left
		var b: Array = right
		if a.size() != b.size():
			return false
		for index in a.size():
			if not _same_value(a[index], b[index]):
				return false
		return true
	if (left is int or left is float) and (right is int or right is float):
		return float(left) == float(right)
	if left is Dictionary or right is Dictionary or left is Array or right is Array:
		return false
	return left == right

## 列出两个字典的差异（递归进嵌套字典 / 数组），供「逐字段一致」断言失败时定位。
func _diff_fields(left: Variant, right: Variant, prefix: String = "") -> String:
	var differing: Array[String] = []
	if not (left is Dictionary) or not (right is Dictionary):
		return "类型不同：%s / %s" % [_type_name(left), _type_name(right)]
	var a: Dictionary = left
	var b: Dictionary = right
	for key in a.keys():
		var path := "%s%s" % [prefix, key]
		if not b.has(key):
			differing.append(path + "(仅左)")
		elif not _same_value(a[key], b[key]):
			differing.append("%s：%s / %s" % [path, str(a[key]), str(b[key])])
	for key in b.keys():
		if not a.has(key):
			differing.append("%s%s(仅右)" % [prefix, key])
	return "，".join(differing)

func _type_name(value: Variant) -> String:
	return type_string(typeof(value))

## 某槽全部落盘文件（主档 / 备份 / 临时 / 损坏现场）的内容摘要；缺文件记为 "<missing>"。
func _digest(slot: int) -> Dictionary:
	var out: Dictionary = {}
	for suffix in SaveManager._sidecar_suffixes():
		var path: String = SaveManager.slot_path(slot) + suffix
		out[suffix] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"
	return out

func _snapshot_saves(slot: int) -> Dictionary:
	var out := {"__last__": ""}
	if FileAccess.file_exists(SaveManager.LAST_SLOT_FILE):
		out["__last__"] = FileAccess.get_file_as_string(SaveManager.LAST_SLOT_FILE)
	for suffix in SaveManager._sidecar_suffixes():
		var path: String = SaveManager.slot_path(slot) + suffix
		if FileAccess.file_exists(path):
			out[suffix] = FileAccess.get_file_as_string(path)
	return out

func _restore_saves(slot: int, snap: Dictionary) -> void:
	SaveManager.delete_slot(slot)
	for key in snap.keys():
		var text := String(snap[key])
		var path: String = SaveManager.LAST_SLOT_FILE if String(key) == "__last__" \
			else SaveManager.slot_path(slot) + String(key)
		if text.is_empty():
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			_write_raw(path, text)

func _remove_export_file() -> void:
	for path in [EXPORT_PATH, EXPORT_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

## 测试直接落盘任意文本（模拟玩家手改后的坏档 / 改档），绕过存档写入路径。
func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveTransferTest] 无法写入测试文件：%s" % path)
		return
	file.store_string(text)
	file.close()

func _finish() -> void:
	if _failures.is_empty():
		print("[SaveTransferTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("[SaveTransferTest] 失败：" + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
