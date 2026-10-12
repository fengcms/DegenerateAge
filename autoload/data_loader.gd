extends Node
## DataLoader — 数据加载与校验（单例 / Autoload）。
##
## 职责：
##   1. 读取 res://data/ 下的 15 个 JSON 配置（见 docs/产品文档/10 数据配置与存档技术）。
##   2. 在启动时执行校验（ID 唯一 / 引用合法 / 等级范围），非法时明确报错而非静默。
## 数据全部文本可编辑——新增物品 / 怪物只需加 JSON 条目，无需改代码。

const DATA_DIR := "res://data/"

## 逻辑表名 -> 文件名。新增配置表在此登记。
const TABLES := {
	"equipments": "equipments.json",
	"skills": "skills.json",
	"monsters": "monsters.json",
	"affixes": "affixes.json",
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
const ID_UNIQUE_TABLES := ["affixes", "equipments", "skills", "monsters", "quests", "maps", "potions", "miscItems", "mounts", "runes", "shops", "dropTables"]

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

	# 3b) 引用合法性：车夫拓扑与 NPC（M3-1 / M3-2 —— 车夫费用与 NPC 数据化后新增）
	var map_ids := {}
	if maps is Array:
		for mp in maps:
			if typeof(mp) == TYPE_DICTIONARY:
				map_ids[mp.get("id", "")] = true
	var shop_ids := {}
	var shops = tables.get("shops")
	if shops is Array:
		for s in shops:
			if typeof(s) == TYPE_DICTIONARY:
				shop_ids[s.get("npcId", "")] = true
	if maps is Array:
		for mp in maps:
			if typeof(mp) != TYPE_DICTIONARY:
				continue
			var mid_map := String(mp.get("id", "?"))
			var links := []
			var raw_links = mp.get("carterLinks", [])
			if raw_links is Array:
				links.assign(raw_links)
			for lid in links:
				if not map_ids.has(String(lid)):
					report.append("[maps] %s 的 carterLinks 指向未定义地图 '%s'" % [mid_map, lid])
			var fees = mp.get("carterFees", {})
			if fees is Dictionary:
				for fid in (fees as Dictionary).keys():
					if not links.has(fid):
						report.append("[maps] %s 的 carterFees 含未连通目的地 '%s'（不在 carterLinks 内）" % [mid_map, fid])
					if not map_ids.has(String(fid)):
						report.append("[maps] %s 的 carterFees 指向未定义地图 '%s'" % [mid_map, fid])
			var npcs := []
			var raw_npcs = mp.get("npcs", [])
			if raw_npcs is Array:
				npcs.assign(raw_npcs)
			for npc in npcs:
				if typeof(npc) != TYPE_DICTIONARY:
					continue
				var role := String(npc.get("role", ""))
				if role != "shop" and role != "quest" and role != "carter":
					report.append("[maps] %s 的 npc role '%s' 非法（应为 shop / quest / carter）" % [mid_map, role])
				var sid := String(npc.get("shopId", ""))
				if role == "shop" and not shop_ids.has(sid):
					report.append("[maps] %s 的 shop NPC 引用未定义 npcId '%s'" % [mid_map, sid])

	# 4) 掉落表合法性（T07：掉落项必在合法表内）
	report.append_array(_validate_drop_tables())
	report.append_array(_validate_affixes())

	return report

## T07：校验 dropTables 的品类 / 引用 / 品质权重 / 等级范围。
func _validate_drop_tables() -> Array[String]:
	var report: Array[String] = []
	var dts = tables.get("dropTables")
	if not (dts is Array):
		return report
	var potion_ids := _id_set("potions")
	var rune_ids := _id_set("runes")
	var misc_ids := _id_set("miscItems")
	var quality_enum := ["common", "uncommon", "rare", "epic", "legendary"]
	var valid_kinds := ["coin", "potion", "equip", "rune", "misc"]

	for d in dts:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var did := String(d.get("id", "?"))
		var entries = d.get("entries", [])
		if not (entries is Array):
			report.append("[dropTables] %s 的 entries 非法" % did)
			continue
		for en in entries:
			if typeof(en) != TYPE_DICTIONARY:
				continue
			var kind := String(en.get("kind", ""))
			if not valid_kinds.has(kind):
				report.append("[dropTables] %s 含非法品类 '%s'" % [did, kind])
				continue
			match kind:
				"coin":
					if not (en.get("goldRange", null) is Array):
						report.append("[dropTables] %s coin 条目缺少 goldRange" % did)
				"potion":
					var pid := String(en.get("itemId", ""))
					if not potion_ids.has(pid):
						report.append("[dropTables] %s 引用未定义药水 '%s'" % [did, pid])
				"rune":
					var ids = en.get("itemIds", [])
					if not (ids is Array):
						report.append("[dropTables] %s rune 条目缺少 itemIds" % did)
					else:
						for rid in ids:
							if not rune_ids.has(String(rid)):
								report.append("[dropTables] %s 引用未定义如意 '%s'" % [did, rid])
				"misc":
					var mid := String(en.get("itemId", ""))
					if not misc_ids.has(mid):
						report.append("[dropTables] %s 引用未定义杂项 '%s'" % [did, mid])
				"equip":
					if not (en.get("levelRange", null) is Array):
						report.append("[dropTables] %s equip 条目缺少 levelRange" % did)
					var qw = en.get("qualityWeight", {})
					if not (qw is Dictionary) or qw.is_empty():
						report.append("[dropTables] %s equip 条目缺少 qualityWeight" % did)
					else:
						for q in qw.keys():
							if not quality_enum.has(String(q)):
								report.append("[dropTables] %s 品质权重含未知品质 '%s'" % [did, q])
	return report

## 取某表的 id 集合（数组型）。
func _id_set(table_name: String) -> Dictionary:
	var out := {}
	var t = tables.get(table_name)
	if t is Array:
		for e in t:
			if typeof(e) == TYPE_DICTIONARY:
				out[e.get("id", "")] = true
	return out

## 词缀配置错误应在启动时暴露，避免运行中随机抽中才报错。
func _validate_affixes() -> Array[String]:
	var report: Array[String] = []
	var affixes: Variant = get_table("affixes")
	if not affixes is Array or affixes.is_empty():
		report.append("[affixes] 需要非空数组")
		return report
	for entry in affixes:
		if not entry is Dictionary or String(entry.get("name", "")).is_empty():
			report.append("[affixes] 条目缺少名称")
			continue
		for field in ["attackPct", "attackSpeedPct", "defensePct", "moveSpeedPct", "slowPct", "slowDuration", "lifeStealPct"]:
			if not entry.has(field):
				continue
			var value: Variant = entry[field]
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) <= 0:
				report.append("[affixes] %s 的 %s 必须为正数" % [entry.get("id", "?"), field])
		if entry.has("slowPct") and (float(entry.slowPct) >= 1 or not entry.has("slowDuration")):
			report.append("[affixes] 减速需要小于 1 的比例及持续时间")
		if entry.has("summonId") or entry.has("summonCount"):
			var target: Variant = get_entry("monsters", String(entry.get("summonId", "")))
			var count: Variant = entry.get("summonCount", 0)
			if not target is Dictionary or target.get("kind", "") != "normal":
				report.append("[affixes] 召唤目标必须为普通怪，禁止递归精英召唤")
			if not (count is float or count is int) or float(count) != floor(float(count)) or float(count) < 1:
				report.append("[affixes] summonCount 必须为正整数")
	for monster in get_table("monsters"):
		if not monster is Dictionary or monster.get("kind", "") != "elite":
			continue
		var pool: Variant = monster.get("affixPool", [])
		var counts: Variant = monster.get("affixCount", [])
		if not pool is Array or pool.is_empty():
			report.append("[monsters] 精英需要非空 affixPool")
			continue
		var seen := {}
		for id in pool:
			if not id is String or get_entry("affixes", str(id)) == null or seen.has(str(id)):
				report.append("[monsters] affixPool 含未知或重复词缀")
			seen[str(id)] = true
		if not counts is Array or counts.size() != 2:
			report.append("[monsters] affixCount 需要 [最少, 最多]")
			continue
		var valid := true
		for count in counts:
			if not (count is float or count is int) or float(count) != floor(float(count)) or float(count) < 1 or float(count) > pool.size():
				valid = false
		if not valid or float(counts[0]) > float(counts[1]):
			report.append("[monsters] affixCount 超出池范围或顺序错误")
	return report
