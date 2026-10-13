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
	"lootPools": "lootPools.json",
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
const ID_UNIQUE_TABLES := ["affixes", "equipments", "skills", "monsters", "quests", "maps", "potions", "miscItems", "mounts", "runes", "shops", "dropTables", "lootPools"]

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
			var map_id := String(mp.get("id", "?"))
			var tier: Variant = mp.get("tierRange", [])
			if not (tier is Array) or tier.size() != 2 or not _is_whole_level(tier[0]) or not _is_whole_level(tier[1]) or int(tier[0]) < 1 or int(tier[1]) < int(tier[0]):
				report.append("[maps] %s 的 tierRange 应为有效的 [最低等级, 最高等级]" % map_id)
			else:
				var tier_min := int(tier[0])
				var tier_max := int(tier[1])
				var spawn_specs: Array = mp.get("spawnPoints", []).duplicate()
				if mp.get("bossSpawn", null) is Dictionary:
					spawn_specs.append(mp.bossSpawn)
				for spec in spawn_specs:
					if spec is Dictionary and spec.has("level"):
						if not _is_whole_level(spec.level):
							report.append("[maps] %s 的 %s 刷新等级应为整数" % [map_id, spec.get("monsterId", "?")])
						else:
							var spec_level := int(spec.level)
							if spec_level < 0 or (spec_level > 0 and (spec_level < tier_min or spec_level > tier_max)):
								report.append("[maps] %s 的 %s 刷新等级 %d 超出 tierRange %d～%d" % [map_id, spec.get("monsterId", "?"), spec_level, tier_min, tier_max])
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
				if not ["shop", "quest", "carter", "blacksmith", "warehouse"].has(role):
					report.append("[maps] %s 的 npc role '%s' 非法" % [mid_map, role])
				if role == "blacksmith" and (String(npc.get("npcName", "")).is_empty() or String(npc.get("greeting", "")).is_empty()):
					report.append("[maps] %s 的铁匠缺少 npcName 或 greeting" % mid_map)
				var sid := String(npc.get("shopId", ""))
				if role == "shop" and not shop_ids.has(sid):
					report.append("[maps] %s 的 shop NPC 引用未定义 npcId '%s'" % [mid_map, sid])
	report.append_array(_validate_walk_exits(maps))

	# 4) 掉落表合法性（T07：掉落项必在合法表内）
	report.append_array(_validate_drop_tables())
	# 4b) 装备池合法性（M6-0b / 创意 07 §7：池定义合法、传说池非空、模板存在、非 debug）
	report.append_array(_validate_loot_pools())
	var runes = tables.get("runes")
	if runes is Array:
		for rune in runes:
			if not rune is Dictionary:
				continue
			var rune_id := String(rune.get("id", ""))
			if not (rune.get("successBonus") is float or rune.get("successBonus") is int) or float(rune.get("successBonus", 0.0)) <= 0.0 or float(rune.get("successBonus", 0.0)) > 1.0:
				report.append("[runes] %s 的 successBonus 应在 (0,1]" % rune_id)
			if not rune.get("dropBossOnly") is bool:
				report.append("[runes] %s 的 dropBossOnly 必须为布尔值" % rune_id)
	var mounts = tables.get("mounts")
	if mounts is Array:
		for mount in mounts:
			if not mount is Dictionary:
				continue
			var mid := String(mount.get("id", ""))
			if not _is_whole_level(mount.get("levelReq", 0)) or int(mount.get("levelReq", 0)) < 1:
				report.append("[mounts] %s 的 levelReq 必须是正整数" % mid)
			if not (mount.get("speedBonus") is float or mount.get("speedBonus") is int) or float(mount.get("speedBonus", 0.0)) <= 0.0:
				report.append("[mounts] %s 的 speedBonus 必须大于 0" % mid)
	report.append_array(_validate_affixes())
	report.append_array(Warehouse.validate_config())

	return report

## Godot 的 JSON 数值可能以 float 返回；等级须仍是正整数形式。
func _is_whole_level(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and float(value) == floorf(float(value))

## T07：校验 dropTables 的品类 / 引用 / 品质权重 / 等级范围。
func _validate_drop_tables() -> Array[String]:
	var report: Array[String] = []
	var dts = tables.get("dropTables")
	if not (dts is Array):
		return report
	var potion_ids := _id_set("potions")
	var rune_ids := _id_set("runes")
	var misc_ids := _id_set("miscItems")
	var pool_ids := _id_set("lootPools")
	var quality_enum := ["common", "uncommon", "rare", "epic", "legendary"]
	var valid_kinds := ["coin", "potion", "equip", "rune", "misc", "mount"]

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
					if en.has("itemId"):
						ids = [en.get("itemId")]
					if not (ids is Array) or ids.is_empty():
						report.append("[dropTables] %s rune 条目缺少 itemId/itemIds" % did)
					else:
						for rid in ids:
							if not rune_ids.has(String(rid)):
								report.append("[dropTables] %s 引用未定义如意 '%s'" % [did, rid])
							else:
								var rune_tpl = get_entry("runes", String(rid))
								if bool(rune_tpl.get("dropBossOnly", false)):
									var monsters = get_table("monsters")
									if monsters is Array:
										for source in monsters:
											if source is Dictionary and String(source.get("dropTableId", "")) == did and String(source.get("kind", "")) != "boss":
												report.append("[dropTables] %s 的 Boss 专属如意被非 Boss 使用" % did)
				"misc":
					var mid := String(en.get("itemId", ""))
					if not misc_ids.has(mid):
						report.append("[dropTables] %s 引用未定义杂项 '%s'" % [did, mid])
				"mount":
					var mount_id := String(en.get("itemId", ""))
					var mount = get_entry("mounts", mount_id)
					if not mount is Dictionary:
						report.append("[dropTables] %s 引用未定义坐骑 '%s'" % [did, mount_id])
					else:
						var boss = get_entry("monsters", String(mount.get("dropBossId", "")))
						if not boss is Dictionary or String(boss.get("kind", "")) != "boss" or String(boss.get("dropTableId", "")) != did:
							report.append("[mounts] %s 的 dropBossId 必须是使用 %s 的 Boss" % [mount_id, did])
				"equip":
					if not (en.get("levelRange", null) is Array):
						report.append("[dropTables] %s equip 条目缺少 levelRange" % did)
					# M6-0b：countRange 分组件数（[lo,hi] 整数，≥1，lo≤hi）。
					if en.has("countRange"):
						var cr = en.get("countRange")
						if not (cr is Array) or cr.size() != 2 \
							or not _is_whole_level(cr[0]) or not _is_whole_level(cr[1]) \
							or int(cr[0]) < 1 or int(cr[1]) < int(cr[0]):
							report.append("[dropTables] %s equip 条目的 countRange 应为 [≥1 整数, ≥lo 整数]" % did)
					# M6-0b：templatePool 引用合法性。
					if en.has("templatePool"):
						var pool_id := String(en.get("templatePool", ""))
						if pool_id.is_empty() or not pool_ids.has(pool_id):
							report.append("[dropTables] %s equip 条目引用未定义装备池 '%s'" % [did, pool_id])
					var qw = en.get("qualityWeight", {})
					if not (qw is Dictionary) or qw.is_empty():
						report.append("[dropTables] %s equip 条目缺少 qualityWeight" % did)
					else:
						var qsum := 0.0
						for q in qw.keys():
							if not quality_enum.has(String(q)):
								report.append("[dropTables] %s 品质权重含未知品质 '%s'" % [did, q])
							else:
								qsum += float(qw[q])
						# 创意 07 §7：所有品质概率必须合计 100（容差）。
						if absf(qsum - 100.0) > 0.5:
							report.append("[dropTables] %s equip 条目品质概率合计应为 100（实际 %.1f）" % [did, qsum])
	return report

## M6-0b：校验装备池（创意 07 §7 —— 池定义合法、传说池非空、模板存在、非 debug）。
func _validate_loot_pools() -> Array[String]:
	var report: Array[String] = []
	var pools = tables.get("lootPools")
	if not (pools is Array) or pools.is_empty():
		report.append("[lootPools] 需要非空数组")
		return report
	var quality_enum := ["common", "uncommon", "rare", "epic", "legendary"]
	var equips = tables.get("equipments")
	for p in pools:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pid := String(p.get("id", "?"))
		var only: Array = []
		var raw_only = p.get("onlyQuality", [])
		if raw_only is Array:
			only = raw_only
		var exclude: Array = []
		var raw_exclude = p.get("excludeQuality", [])
		if raw_exclude is Array:
			exclude = raw_exclude
		for q in only:
			if not quality_enum.has(String(q)):
				report.append("[lootPools] %s 的 onlyQuality 含未知品质 '%s'" % [pid, q])
		for q in exclude:
			if not quality_enum.has(String(q)):
				report.append("[lootPools] %s 的 excludeQuality 含未知品质 '%s'" % [pid, q])
		if not only.is_empty() and not exclude.is_empty():
			report.append("[lootPools] %s 不应同时声明 onlyQuality 与 excludeQuality" % pid)
		# 池必须至少能选出一个非 debug 模板（§7：空池 ⇒ 启动明确报错，不静默少发）。
		var n := 0
		if equips is Array:
			for e in equips:
				if not (e is Dictionary) or bool(e.get("debug", false)):
					continue
				var q := String(e.get("quality", "common"))
				var ok := true
				if not only.is_empty():
					ok = only.has(q)
				elif not exclude.is_empty():
					ok = not exclude.has(q)
				if ok:
					n += 1
		if n == 0:
			report.append("[lootPools] %s 池为空（无任何非 debug 模板匹配）" % pid)
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

## M6-1：出口、入口必须有效且双向配对；错误在启动校验时暴露。
func _validate_walk_exits(maps: Variant) -> Array[String]:
	var report: Array[String] = []
	if not maps is Array:
		return report
	var by_id := {}
	for entry in maps:
		if entry is Dictionary:
			by_id[String(entry.get("id", ""))] = entry
	for entry in maps:
		if not entry is Dictionary:
			continue
		var map_id := String(entry.get("id", ""))
		var exits: Variant = entry.get("exits", null)
		var entrances: Variant = entry.get("entrances", null)
		if not exits is Array or not entrances is Dictionary:
			report.append("[maps] %s 缺少 exits 数组或 entrances 字典" % map_id)
			continue
		for entrance_id in entrances.keys():
			if String(entrance_id).is_empty() or not _valid_walk_cell(entrances[entrance_id], entry):
				report.append("[maps] %s 的入口 %s 坐标无效" % [map_id, entrance_id])
		var seen := {}
		for exit_data in exits:
			if not exit_data is Dictionary:
				report.append("[maps] %s 的出口必须是对象" % map_id)
				continue
			var exit_id := String(exit_data.get("id", ""))
			if exit_id.is_empty() or seen.has(exit_id):
				report.append("[maps] %s 的出口 id 为空或重复：%s" % [map_id, exit_id])
			seen[exit_id] = true
			if not _valid_walk_cell(exit_data.get("cell", null), entry):
				report.append("[maps] %s 的出口 %s 坐标无效" % [map_id, exit_id])
			var to_id := String(exit_data.get("toMap", ""))
			if to_id == map_id or not by_id.has(to_id):
				report.append("[maps] %s 的出口 %s 目标图无效" % [map_id, exit_id])
				continue
			var target: Dictionary = by_id[to_id]
			var target_entrances: Variant = target.get("entrances", null)
			var target_entrance := String(exit_data.get("toEntrance", ""))
			if not target_entrances is Dictionary or not target_entrances.has(target_entrance):
				report.append("[maps] %s 的出口 %s 找不到 %s 的入口 %s" % [map_id, exit_id, to_id, target_entrance])
				continue
			var reverse_found := false
			var reverse_exits: Variant = target.get("exits", [])
			if reverse_exits is Array:
				for reverse in reverse_exits:
					if reverse is Dictionary and String(reverse.get("toMap", "")) == map_id:
						var own_entrances: Dictionary = entrances
						if own_entrances.has(String(reverse.get("toEntrance", ""))):
							reverse_found = true
							break
			if not reverse_found:
				report.append("[maps] %s 的出口 %s 缺少 %s 的双向返回出口" % [map_id, exit_id, to_id])
	return report

func _valid_walk_cell(value: Variant, map_data: Dictionary) -> bool:
	if not value is Array or value.size() != 2:
		return false
	var size_data: Variant = map_data.get("size", null)
	if not size_data is Dictionary:
		return false
	for i in range(2):
		var coordinate: Variant = value[i]
		if not (coordinate is int or coordinate is float) or float(coordinate) != floor(float(coordinate)):
			return false
		var limit := int(size_data.get("w" if i == 0 else "h", 0))
		if int(coordinate) < 0 or int(coordinate) >= limit:
			return false
	return true

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
