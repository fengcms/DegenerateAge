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
	"equipmentRules": "equipmentRules.json",
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
	report.append_array(_validate_carter_clusters(maps))
	report.append_array(_validate_walk_exits(maps))
	report.append_array(_validate_safe_areas(maps))

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
	report.append_array(_validate_equipment_model())
	report.append_array(Warehouse.validate_config())

	return report

## Godot 的 JSON 数值可能以 float 返回；等级须仍是正整数形式。
func _is_whole_level(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and float(value) == floorf(float(value))

## 装备型号、穿戴档与品质配置须同时完整，不能在掉落时回退到低档。
func _validate_equipment_model() -> Array[String]:
	var report: Array[String] = []
	var cfg: Variant = tables.get("equipmentRules")
	var equips: Variant = tables.get("equipments")
	if not cfg is Dictionary or not equips is Array:
		report.append("[equipmentRules] 需要规则字典与装备型号数组")
		return report
	var tiers: Variant = cfg.get("tiers", [])
	var qualities: Variant = cfg.get("qualities", {})
	var fixed: Variant = cfg.get("fixedAffixes", {})
	var percent: Variant = cfg.get("percentAffixes", {})
	if not tiers is Array or tiers.is_empty() or not qualities is Dictionary or not fixed is Dictionary or not percent is Dictionary:
		report.append("[equipmentRules] 档位、品质与词条池非法")
		return report
	var expected_slots := ["weapon", "shield", "helmet", "armor", "shoes", "necklace", "bracer", "knee", "bracelet", "ring"]
	var slot_coverage := {}
	var previous_tier := 0
	for tier in tiers:
		if not _is_whole_level(tier) or int(tier) < 1:
			report.append("[equipmentRules] 穿戴档必须是正整数")
			continue
		var expected_tier := 1 if previous_tier == 0 else 11
		if int(tier) != expected_tier:
			report.append("[equipmentRules] 当前穿戴档仅允许 Lv1、Lv11 且升序")
		previous_tier = int(tier)
		slot_coverage[str(int(tier))] = {}
	if not _is_whole_level(cfg.get("maxStar")) or int(cfg.maxStar) != 12 \
			or not (cfg.get("starMult") is int or cfg.get("starMult") is float) or float(cfg.starMult) < 0.0:
		report.append("[equipmentRules] 星级参数非法")
	for quality in ["common", "uncommon", "rare", "epic", "legendary"]:
		var q: Variant = qualities.get(quality)
		if not q is Dictionary or not _is_whole_level(q.get("affixCount")) or int(q.affixCount) < 0 \
				or int(q.affixCount) > 4 or not (q.get("percentChance") is int or q.get("percentChance") is float) \
				or float(q.percentChance) < 0.0 or float(q.percentChance) > 1.0 \
				or not (q.get("baseMultiplier") is float or q.get("baseMultiplier") is int) \
				or float(q.baseMultiplier) <= 0.0:
			report.append("[equipmentRules] 品质 %s 参数非法" % quality)
	for e in equips:
		if not e is Dictionary:
			continue
		var item_id := String(e.get("id", "?"))
		var slot := String(e.get("slot", ""))
		var bases: Variant = e.get("tierBases", {})
		var pool: Variant = e.get("affixPool", [])
		if not expected_slots.has(slot) or not bases is Dictionary or not pool is Array:
			report.append("[equipments] %s 的槽型/档位/词条池非法" % item_id)
			continue
		if bases.size() != 1 or not slot_coverage.has(String(bases.keys()[0])):
			report.append("[equipments] %s 必须且只能属于一个合法穿戴档" % item_id)
			continue
		if not qualities.has(String(e.get("defaultQuality", "common"))):
			report.append("[equipments] %s 默认品质非法" % item_id)
		var fixed_count := 0
		var seen := {}
		for stat in pool:
			if seen.has(String(stat)) or (not fixed.has(String(stat)) and not percent.has(String(stat))):
				report.append("[equipments] %s 的词条池含重复或未知属性 %s" % [item_id, stat])
			seen[String(stat)] = true
			if fixed.has(String(stat)):
				fixed_count += 1
		if fixed_count < 4:
			report.append("[equipments] %s 至少需要四种合法固定词条" % item_id)
		var tier_key := String(bases.keys()[0])
		var base: Variant = bases[tier_key]
		if not base is Dictionary or base.is_empty():
			report.append("[equipments] %s 缺少 Lv%s 基底" % [item_id, tier_key])
			continue
		for stat in base:
			if not fixed.has(String(stat)) or not (base[stat] is float or base[stat] is int) or float(base[stat]) <= 0.0:
				report.append("[equipments] %s 的 Lv%s 基底属性 %s 非法" % [item_id, tier_key, stat])
		if bool(e.get("lootable", true)) and not bool(e.get("debug", false)):
			if slot_coverage[tier_key].has(slot):
				report.append("[equipments] Lv%s 的 %s 出现多个正式型号" % [tier_key, slot])
			slot_coverage[tier_key][slot] = true
	for tier_key in slot_coverage:
		for slot in expected_slots:
			if not slot_coverage[tier_key].has(slot):
				report.append("[equipments] Lv%s 缺少可掉落 %s 型号" % [tier_key, slot])
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
					var level_range: Variant = en.get("levelRange", null)
					if not level_range is Array or level_range.size() != 2 \
							or not _is_whole_level(level_range[0]) or not _is_whole_level(level_range[1]) \
							or int(level_range[0]) < 1 or int(level_range[1]) < int(level_range[0]):
						report.append("[dropTables] %s equip 条目缺少 levelRange" % did)
					if en.has("requiredLevel"):
						var required: Variant = en.get("requiredLevel")
						var cfg: Variant = tables.get("equipmentRules")
						var legal := false
						if cfg is Dictionary and _is_whole_level(required):
							for configured in cfg.get("tiers", []):
								if int(configured) == int(required):
									legal = true
						if not legal:
							report.append("[dropTables] %s 的 requiredLevel 未在装备档位表中" % did)
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

## 型号池只筛装备型号，与品质权重分离。
func _validate_loot_pools() -> Array[String]:
	var report: Array[String] = []
	var pools = tables.get("lootPools")
	if not (pools is Array) or pools.is_empty():
		report.append("[lootPools] 需要非空数组")
		return report
	var equips = tables.get("equipments")
	for p in pools:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pid := String(p.get("id", "?"))
		var include_ids: Variant = p.get("includeIds", [])
		if not include_ids is Array:
			report.append("[lootPools] %s 的 includeIds 应为数组" % pid)
			continue
		for item_id in include_ids:
			if not get_entry("equipments", String(item_id)) is Dictionary:
				report.append("[lootPools] %s 引用未知装备型号 %s" % [pid, item_id])
		# 池必须至少能选出一个非 debug、可掉落的型号。
		var n := 0
		if equips is Array:
			for e in equips:
				if not (e is Dictionary) or bool(e.get("debug", false)) or not bool(e.get("lootable", true)):
					continue
				if include_ids.is_empty() or include_ids.has(String(e.get("id", ""))):
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
func _validate_carter_clusters(maps: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not maps is Array:
		return ["[maps] 地图表不是数组"] as Array[String]
	var by_id := {}
	for entry in maps:
		if entry is Dictionary:
			by_id[String(entry.get("id", ""))] = entry
	for entry in maps:
		if not entry is Dictionary:
			continue
		var id := String(entry.get("id", ""))
		var kind := String(entry.get("kind", ""))
		var hub_id := String(entry.get("hubId", ""))
		if not ["hub", "spoke"].has(kind):
			errors.append("[maps] %s 的 kind 必须为 hub 或 spoke" % id)
		var hub: Variant = by_id.get(hub_id, null)
		if not hub is Dictionary or String(hub.get("kind", "")) != "hub":
			errors.append("[maps] %s 的 hubId 未指向有效 hub" % id)
		if kind == "hub" and hub_id != id:
			errors.append("[maps] 枢纽 %s 必须指向自身" % id)
		var hub_links: Variant = entry.get("hubLinks", null)
		if kind == "hub":
			if not hub_links is Array:
				errors.append("[maps] %s 缺少 hubLinks 数组" % id)
			else:
				var seen := {}
				for linked in hub_links:
					var peer: Variant = by_id.get(String(linked), null)
					if seen.has(linked) or linked == id or not peer is Dictionary or String(peer.get("kind", "")) != "hub":
						errors.append("[maps] %s 的 hubLinks 含无效枢纽 %s" % [id, linked])
					elif not peer.get("hubLinks", []) is Array or not peer.get("hubLinks", []).has(id):
						errors.append("[maps] %s 与 %s 的 hubLinks 不双向" % [id, linked])
					seen[linked] = true
			var spoke_count := 0
			for candidate in maps:
				if candidate is Dictionary and String(candidate.get("kind", "")) == "spoke" and String(candidate.get("hubId", "")) == id:
					spoke_count += 1
			if spoke_count == 0:
				errors.append("[maps] 枢纽 %s 缺少附属地图" % id)
			var defaults: Variant = entry.get("carterFare", null)
			if not defaults is Dictionary:
				errors.append("[maps] 枢纽 %s 缺少 carterFare" % id)
			else:
				for target_kind in ["hub", "spoke"]:
					if not _nonnegative_whole(defaults.get(target_kind, null)):
						errors.append("[maps] 枢纽 %s 的 carterFare.%s 无效" % [id, target_kind])
		elif entry.has("hubLinks") or entry.has("carterFare"):
			errors.append("[maps] 附属地图 %s 不得配置枢纽字段" % id)
		var fares: Variant = entry.get("carterFares", {})
		if not fares is Dictionary:
			errors.append("[maps] %s 的 carterFares 必须为字典" % id)
		else:
			for target_id in fares:
				var target: Variant = by_id.get(String(target_id), null)
				var reachable: bool = target is Dictionary and (String(target.get("hubId", "")) == hub_id or (hub is Dictionary and hub.get("hubLinks", []).has(target_id)))
				if target_id == id or not reachable or not _nonnegative_whole(fares[target_id]):
					errors.append("[maps] %s 的 carterFares 目标或费用无效：%s" % [id, target_id])
	return errors

func _nonnegative_whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) == floor(float(value))

func _validate_safe_areas(maps: Variant) -> Array[String]:
	var report: Array[String] = []
	if not maps is Array:
		return report
	for entry in maps:
		if not entry is Dictionary:
			continue
		var id := String(entry.get("id", ""))
		var area: Variant = entry.get("safeArea", null)
		if not bool(entry.get("safeZone", false)):
			if area != null:
				report.append("[maps] %s 非城镇地图不得配置 safeArea" % id)
			continue
		if not area is Dictionary or not _valid_walk_cell(area.get("min", null), entry) \
				or not _valid_walk_cell(area.get("max", null), entry):
			report.append("[maps] %s 的安全区矩形坐标无效" % id)
			continue
		var lo: Array = area.min
		var hi: Array = area.max
		if int(lo[0]) >= int(hi[0]) or int(lo[1]) >= int(hi[1]):
			report.append("[maps] %s 的安全区矩形必须有正面积" % id)
			continue
		for npc in entry.get("npcs", []):
			if not npc is Dictionary or not _valid_walk_cell(npc.get("cell", null), entry):
				continue
			var cell: Array = npc.cell
			if int(cell[0]) < int(lo[0]) or int(cell[0]) > int(hi[0]) \
					or int(cell[1]) < int(lo[1]) or int(cell[1]) > int(hi[1]):
				report.append("[maps] %s 的 NPC 位于安全区外" % id)
	return report

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
		if not _valid_walk_cell(entry.get("carterArrival", null), entry):
			report.append("[maps] %s 的车夫抵达坐标无效" % map_id)
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
