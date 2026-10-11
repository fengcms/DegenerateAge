extends Node
## DataLoader — 数据加载与校验（单例 / Autoload）。
##
## 职责：
##   1. 读取 res://data/ 下的 14 个 JSON 配置（见 docs/产品文档/10 数据配置与存档技术）。
##   2. 在启动时执行校验（ID 唯一 / 引用合法 / 等级范围），非法时明确报错而非静默。
## 数据全部文本可编辑——新增物品 / 怪物只需加 JSON 条目，无需改代码。

const DATA_DIR := "res://data/"

## 逻辑表名 -> 文件名。新增配置表在此登记。
const TABLES := {
	"equipments": "equipments.json",
	"skills": "skills.json",
	"monsters": "monsters.json",
	"dropTables": "dropTables.json",
	"quests": "quests.json",
	"shops": "shops.json",
	"upgrade": "upgrade.json",
	"mounts": "mounts.json",
	"runes": "runes.json",
	"warehouse": "warehouse.json",
	"miscItems": "miscItems.json",
	"potions": "potions.json",
	"maps": "maps.json",
	"localization": "localization.json",
}

## 需要做「ID 唯一」校验的表（数组型）。
const ID_UNIQUE_TABLES := ["equipments", "skills", "monsters", "quests", "maps", "potions", "miscItems", "mounts", "runes", "shops", "dropTables"]

## 各表用作「唯一键」的字段名（缺省为 id）。shops 以 npcId 为键（见 docs 第 10 章 schema）。
const KEY_FIELDS := {
	"shops": "npcId",
}

var tables: Dictionary = {}
var errors: Array[String] = []

func _ready() -> void:
	load_all()

## 加载全部配置表。
func load_all() -> void:
	tables.clear()
	errors.clear()
	for key in TABLES.keys():
		tables[key] = _load_json(DATA_DIR + TABLES[key])
	EventBus.data_loaded.emit()

func _load_json(path: String):
	if not FileAccess.file_exists(path):
		errors.append("缺失配置文件：%s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("无法打开文件：%s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		errors.append("JSON 解析失败（语法错误）：%s" % path)
		return null
	return parsed

## 取整表。
func get_table(table_name: String) -> Variant:
	return tables.get(table_name)

## 按 id 取条目（数组表或字典表均可）。
func get_entry(table_name: String, id: String) -> Variant:
	var t = tables.get(table_name)
	if t == null:
		return null
	if t is Array:
		var key_field: String = KEY_FIELDS.get(table_name, "id")
		for e in t:
			if typeof(e) == TYPE_DICTIONARY and String(e.get(key_field, "")) == id:
				return e
	elif t is Dictionary:
		return t.get(id)
	return null

## 加载摘要（用于启动日志 / 调试）。
func get_summary() -> String:
	var parts: Array[String] = []
	for key in tables.keys():
		var t = tables[key]
		var n := 0
		if t is Array:
			n = t.size()
		elif t is Dictionary:
			n = t.size()
		parts.append("%s=%d" % [key, n])
	return ", ".join(PackedStringArray(parts))

## 启动校验，返回问题列表（空 = 全部通过）。
func validate_all() -> Array[String]:
	var report: Array[String] = []
	report.append_array(errors)

	# 1) ID 唯一性
	for table_name in ID_UNIQUE_TABLES:
		var t = tables.get(table_name)
		if not (t is Array):
			continue
		var key_field: String = KEY_FIELDS.get(table_name, "id")
		var seen := {}
		for e in t:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var key = e.get(key_field, null)
			if key == null or String(key).is_empty():
				report.append("[%s] 存在缺少 %s 的条目" % [table_name, key_field])
			elif seen.has(key):
				report.append("[%s] 重复 %s：%s" % [table_name, key_field, key])
			else:
				seen[key] = true

	# 2) 引用合法性：怪物 dropTableId 必须存在于 dropTables
	var dt_ids := {}
	var dts = tables.get("dropTables")
	if dts is Array:
		for d in dts:
			if typeof(d) == TYPE_DICTIONARY:
				dt_ids[d.get("id", "")] = true
	var monsters = tables.get("monsters")
	if monsters is Array:
		for m in monsters:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var dtid: String = String(m.get("dropTableId", ""))
			if not dtid.is_empty() and not dt_ids.has(dtid):
				report.append("[monsters] %s 的 dropTableId '%s' 未在 dropTables 中定义" % [m.get("id", "?"), dtid])

	# 3) 引用合法性：地图 spawnPoints / bossSpawn 的 monsterId 必须存在于 monsters
	var monster_ids := {}
	if monsters is Array:
		for m in monsters:
			if typeof(m) == TYPE_DICTIONARY:
				monster_ids[m.get("id", "")] = true
	var maps = tables.get("maps")
	if maps is Array:
		for mp in maps:
			if typeof(mp) != TYPE_DICTIONARY:
				continue
			for sp in mp.get("spawnPoints", []):
				var mid: String = String(sp.get("monsterId", ""))
				if not mid.is_empty() and not monster_ids.has(mid):
					report.append("[maps] %s 的怪物点引用未定义怪物 '%s'" % [mp.get("id", "?"), mid])
			var bs = mp.get("bossSpawn", null)
			if bs is Dictionary:
				var bmid: String = String(bs.get("monsterId", ""))
				if not bmid.is_empty() and not monster_ids.has(bmid):
					report.append("[maps] %s 的 bossSpawn 引用未定义怪物 '%s'" % [mp.get("id", "?"), bmid])

	return report
