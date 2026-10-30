extends Node
## DataLoader — 数据加载与校验（单例 / Autoload）。
##
## 职责：
##   1. 读取 res://data/ 下由 TABLES 登记的 JSON 配置表；地图与怪物分别按目录索引
##      聚合配置，保持对外表接口不变（见 docs/产品文档/10 数据配置与存档技术）。
##      文案表 `localization.json` 由 `Localization` 独立加载，**不在此列**（B-P3-2：避免双份内存与漂移）。
##   2. 在启动时执行校验（ID 唯一 / 引用合法 / 等级范围），非法时明确报错而非静默。
## 数据全部文本可编辑——新增怪物须写入所属章节并登记章节索引。

const DATA_DIR := "res://data/"

## 逻辑表名 -> 文件名；地图与怪物由各自的目录清单加载。
const TABLES := {
	"classes": "classes.json",
	"equipments": "equipments.json",
	"equipmentRules": "equipmentRules.json",
	"skills": "skills.json",
	"skillProgression": "skillProgression.json",
	"affixes": "affixes.json",
	"dropTables": "dropTables.json",
	"lootPools": "lootPools.json",
	"quests": "quests.json",
	"shops": "shops.json",
	"upgrade": "upgrade.json",
	"mounts": "mounts.json",
	"runes": "runes.json",
	"warehouse": "warehouse.json",
	"exchange": "exchange.json",
	"miscItems": "miscItems.json",
	"potions": "potions.json",
	"endgame": "endgame.json",
	"durability": "durability.json",
}

const MAP_INDEX := "res://data/maps/index.json"
const MONSTER_INDEX := "res://data/monsters/index.json"
const APPEARANCE_INDEX := "res://data/monster_appearances/index.json"

## 需要做「ID 唯一」校验的表（数组型）。
const ID_UNIQUE_TABLES := ["classes", "affixes", "equipments", "skills", "skillProgression", "monsters", "monsterAppearances", "quests", "maps", "potions", "miscItems", "mounts", "runes", "shops", "dropTables", "lootPools"]

## 各表用作「唯一键」的字段名（缺省为 id）。shops 以 npcId 为键（见 docs 第 10 章 schema）。
const KEY_FIELDS := {
	"shops": "npcId",
	"skillProgression": "skillId",
}

## M10-4：任务等级门槛 `requiresLevel` 的上界。
## ⚠ 须与 `GameState.PLAYER_LEVEL_CAP` 保持一致（此处写字面量是刻意的：
## `data_loader` 目前完全不引用 `GameState`，加引用会引入 autoload 初始化顺序耦合）。
const MAX_QUEST_REQUIRES_LEVEL := 9999

## 工程 107：破甲幅度（`debuff.defenseScale` = 目标防御的**保留比例**）的合法下界。
## 1.0 必然非法（等于没破甲）；0.55 ⇒ 最多破 45% 防御。再深会和 `defensePierce`
## 叠成接近无视防御 —— 那是阶跃式的数值塌陷（工程 88 教训），校验直接拦在数据层。
## ⚠ 别和 `Monster.ARMOR_BREAK_SCALE = 0.7` 混为一谈：那个是「数据没写时」的兜底值。
const ARMOR_BREAK_SCALE_FLOOR := 0.55

## M10-6：随身商队使用**合成店铺 id**（`Shop.PORTABLE_SHOP_ID`），它不写进 `shops.json`。
## 这里写字面量而非引用 `Shop`，同样是为了不给 data_loader 引入反向依赖；
## 真实店铺一旦占用这个 id，货单会被聚合力覆盖 → 启动期直接报错，不留给运行时猜。
const RESERVED_SHOP_IDS := ["portable_shop"]

## 历史遗留图（第一、二章）：入口落点与反向出口存在既有错位，未按第三至六章的
## 「同格」口径对齐（属审阅明确范围外的遗留）。仅用于豁免 `_validate_walk_exits`
## 的**同格断言**，待后续统一口径时逐图归正并移出白名单。
const LEGACY_MAPS := [
	"camp", "wild_trial", "ash_land", "corruption_source",
	"c2_well_town", "c2_pipe_slope", "c2_old_well", "c2_lower_works",
	"c2_ember_furnace", "c2_well_core",
]

var tables: Dictionary = {}
var errors: Array[String] = []
## 配置重载修订号；技能阶数解析缓存以此识别热重载并失效。
var revision := 0

## 表名 -> { 唯一键 -> 条目 }。启动时构建一次，使 get_entry 由线性扫描降为 O(1)。
var _index: Dictionary = {}

## 启动时一次性加载各表、地图、怪物与表现档案，随后供实体按 ID 查询。
func _ready() -> void:
	load_all()

## 重新加载全部配置表并重建索引；编辑器或测试主动重载时会发出 data_loaded。
func load_all() -> void:
	tables.clear()
	errors.clear()
	for key in TABLES.keys():
		tables[key] = _load_json(DATA_DIR + TABLES[key])
	tables["maps"] = _load_maps()
	tables["monsters"] = _load_monsters()
	tables["monsterAppearances"] = _load_monster_appearances()
	_build_index()
	revision += 1
	EventBus.data_loaded.emit()

## 按各表唯一键构建查表索引（仅数组表）。字典表本身即为键值表，无需另建。
func _build_index() -> void:
	_index.clear()
	for key in tables.keys():
		var t = tables.get(key)
		if not (t is Array):
			continue
		var key_field: String = KEY_FIELDS.get(key, "id")
		var map := {}
		for e in t:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var k := String(e.get(key_field, ""))
			if not k.is_empty():
				map[k] = e
		_index[key] = map

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

## 按地图清单读取各目录的 map.json，聚合为旧版 maps 数组接口。
## 缺失、非法路径及目录 ID 不符时记录配置错误，避免静默丢地图。
func _load_maps() -> Array:
	var entries = _load_json(MAP_INDEX)
	var result: Array = []
	if not (entries is Array):
		errors.append("地图索引必须是路径数组：%s" % MAP_INDEX)
		return result
	var seen := {}
	for relative in entries:
		if not (relative is String) or not relative.ends_with("/map.json") or relative.begins_with("/") or relative.contains(".."):
			errors.append("非法地图索引路径：%s" % str(relative))
			continue
		var path: String = "res://data/maps/" + relative
		var map_data = _load_json(path)
		if not (map_data is Dictionary):
			errors.append("地图配置必须是对象：%s" % path)
			continue
		var directory_id: String = relative.get_base_dir().get_file()
		var map_id: String = String(map_data.get("id", ""))
		if map_id != directory_id or seen.has(map_id):
			errors.append("地图 ID 与目录不符或重复：%s" % path)
			continue
		seen[map_id] = true
		result.append(map_data)
	return result

## 按章节索引聚合怪物数组，保留旧 monsters 表与 ID 查询接口。
## 路径只能位于 data/monsters 下；缺失、重复章节或非法条目记录配置错误。
func _load_monsters() -> Array:
	var entries: Variant = _load_json(MONSTER_INDEX)
	var result: Array = []
	if not (entries is Array):
		errors.append("怪物索引必须是路径数组：%s" % MONSTER_INDEX)
		return result
	var seen_paths := {}
	for relative in entries:
		if not (relative is String) or not relative.ends_with("/monsters.json") or relative.begins_with("/") or relative.contains(".."):
			errors.append("非法怪物索引路径：%s" % str(relative))
			continue
		if seen_paths.has(relative):
			errors.append("重复怪物索引路径：%s" % relative)
			continue
		seen_paths[relative] = true
		var path: String = "res://data/monsters/" + relative
		var chapter_data: Variant = _load_json(path)
		if not (chapter_data is Array):
			errors.append("章节怪物配置必须是数组：%s" % path)
			continue
		for row in chapter_data:
			if not (row is Dictionary):
				errors.append("怪物条目必须是对象：%s" % path)
				continue
			result.append(row)
	return result

## 读取一档案一文件的怪物表现清单，按稳定外观 ID 聚合一次供实例复用。
## 文件名必须与档案 ID 一致；非法路径或缺失内容报告为启动配置错误。
func _load_monster_appearances() -> Array:
	var entries: Variant = _load_json(APPEARANCE_INDEX)
	var result: Array = []
	if not (entries is Array):
		errors.append("怪物表现索引必须是路径数组：%s" % APPEARANCE_INDEX)
		return result
	var seen_paths := {}
	for relative in entries:
		if not (relative is String) or not relative.ends_with(".json") or relative.contains("/") or relative.contains(".."):
			errors.append("非法怪物表现索引路径：%s" % str(relative))
			continue
		if seen_paths.has(relative):
			errors.append("重复怪物表现索引路径：%s" % relative)
			continue
		seen_paths[relative] = true
		var path: String = "res://data/monster_appearances/" + relative
		var appearance: Variant = _load_json(path)
		if not (appearance is Dictionary) or String(appearance.get("id", "")) != relative.get_basename():
			errors.append("怪物表现 ID 与文件名不符：%s" % path)
			continue
		result.append(appearance)
	return result

## 启动时验证表现档案的渲染类型、关键元数据与资源引用。
## 本函数不加载纹理或创建节点，缺资源在此报错，运行端仍可回退占位图。
func _validate_monster_appearance(spec: Dictionary) -> Array[String]:
	var report: Array[String] = []
	var id := String(spec.get("id", "?"))
	var renderer := String(spec.get("renderer", ""))
	if not renderer in ["procedural", "sample_atlas", "static_atlas", "animation_pack", "directional_preview", "chapter2_manifest"]:
		report.append("[monsterAppearances] %s 的 renderer 无效：%s" % [id, renderer])
		return report
	if spec.has("headHpY") and not (spec.headHpY is float or spec.headHpY is int):
		report.append("[monsterAppearances] %s 的 headHpY 必须是数值" % id)
	if spec.has("displayScale") and (not (spec.displayScale is float or spec.displayScale is int) or float(spec.displayScale) <= 0.0):
		report.append("[monsterAppearances] %s 的 displayScale 必须大于 0" % id)
	if renderer in ["sample_atlas", "static_atlas", "directional_preview"]:
		var fields := ["main"] if renderer == "sample_atlas" else ["texture"]
		if renderer == "sample_atlas":
			fields.append_array(["walk", "extra"])
		for field in fields:
			var path := String(spec.get(field, ""))
			if field in ["walk", "extra"] and path.is_empty():
				continue
			if not path.begins_with("res://assets/sprites/monsters/") or not ResourceLoader.exists(path):
				report.append("[monsterAppearances] %s 的 %s 素材缺失：%s" % [id, field, path])
		var coords: Variant = spec.get("pivot", []) if renderer == "sample_atlas" else spec.get("offset", [])
		if not (coords is Array) or coords.size() != 2 or not (coords[0] is int or coords[0] is float) or not (coords[1] is int or coords[1] is float):
			report.append("[monsterAppearances] %s 的脚底锚点/偏移无效" % id)
		if renderer == "static_atlas" and int(spec.get("hframes", 0)) <= 0:
			report.append("[monsterAppearances] %s 的 hframes 无效" % id)
	if renderer == "animation_pack" and not MonsterAnimationLibrary.PACKS.has(String(spec.get("assetKey", ""))):
		report.append("[monsterAppearances] %s 的 animation_pack 未在生成库登记" % id)
	if renderer == "chapter2_manifest" and String(spec.get("assetKey", "")).is_empty():
		report.append("[monsterAppearances] %s 缺少第二章清单 assetKey" % id)
	return report

## A4（工程文档 56 §2.4）：`bossSkill.knockback / knockdown` 是可选字段（缺省走代码常量）。
## 一旦写了就必须形状合法 —— 否则会出现「配了字段却不生效」的静默失效。
func _validate_skill_knockback(id: String, skill: Variant) -> Array[String]:
	var report: Array[String] = []
	if not skill is Dictionary:
		return report
	var kb: Variant = (skill as Dictionary).get("knockback", null)
	if kb != null and (not kb is Dictionary
			or not _is_nonnegative_number((kb as Dictionary).get("distance"))
			or not _is_nonnegative_number((kb as Dictionary).get("duration"))):
		report.append("[monsters] %s 的 bossSkill.knockback 需含非负 distance / duration" % id)
	var kd: Variant = (skill as Dictionary).get("knockdown", null)
	if kd != null and (not kd is Dictionary or not _is_nonnegative_number((kd as Dictionary).get("duration"))):
		report.append("[monsters] %s 的 bossSkill.knockdown 需含非负 duration" % id)
	return report

## 取整表。
func get_table(table_name: String) -> Variant:
	return tables.get(table_name)

## 按 id 取条目（数组表或字典表均可）。数组表走启动时构建的索引，命中为 O(1)。
func get_entry(table_name: String, id: String) -> Variant:
	var t = tables.get(table_name)
	if t == null:
		return null
	if t is Array:
		# 索引已建（load_all 后）时直接查；未建时回退线性扫描，保持旧行为。
		if _index.has(table_name):
			var hit: Variant = (_index[table_name] as Dictionary).get(id)
			if hit != null:
				return hit
			# 未命中：表可能在运行时被追加/替换（如测试注入新条目），
			# 回退线性扫描并把结果补进索引，兼顾正确性与查询成本。
			var found: Variant = _linear_get(t, table_name, id)
			if found != null:
				(_index[table_name] as Dictionary)[id] = found
			return found
		return _linear_get(t, table_name, id)
	elif t is Dictionary:
		return t.get(id)
	return null

## 数组表的线性扫描（回退路径 / 运行时新增条目的兜底）。
func _linear_get(t: Array, table_name: String, id: String) -> Variant:
	var key_field: String = KEY_FIELDS.get(table_name, "id")
	for e in t:
		if typeof(e) == TYPE_DICTIONARY and String(e.get(key_field, "")) == id:
			return e
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
			var appearance_id := String(m.get("appearanceId", ""))
			if appearance_id.is_empty() or get_entry("monsterAppearances", appearance_id) == null:
				report.append("[monsters] %s 引用未登记的 appearanceId '%s'" % [m.get("id", "?"), appearance_id])
			report.append_array(_validate_skill_knockback(String(m.get("id", "?")), m.get("bossSkill")))
	var appearances = tables.get("monsterAppearances")
	if appearances is Array:
		for appearance in appearances:
			if appearance is Dictionary:
				report.append_array(_validate_monster_appearance(appearance))

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
			# M10-3（工程文档 43 §3.1）：`levelFromPlayer.enabled` 的图（循环图）等级按玩家现算，
			# **必须缺席 tierRange**；存量图仍必填。两个方向都报错 —— 写成「都可选」会让
			# 既写 tierRange 又写 levelFromPlayer 的坏表静默走夹紧分支（症状就是「100 级进图
			# 还是 60 级 Boss」）。
			var from_player: Variant = mp.get("levelFromPlayer", null)
			var dynamic_level := from_player is Dictionary and bool((from_player as Dictionary).get("enabled", false))
			var level_min := 0
			if from_player != null and not dynamic_level:
				report.append("[maps] %s 的 levelFromPlayer 必须是含 enabled:true 的字典" % map_id)
			if dynamic_level:
				var raw_min: Variant = (from_player as Dictionary).get("minLevel", 1)
				if not _is_whole_level(raw_min) or int(raw_min) < 1:
					report.append("[maps] %s 的 levelFromPlayer.minLevel 应为正整数" % map_id)
				else:
					level_min = int(raw_min)
				if mp.has("tierRange"):
					report.append("[maps] %s 配了 levelFromPlayer，不能再写 tierRange（等级由玩家等级现算）" % map_id)
			var tier_min := 0
			var tier_max := 0
			var tier_ok := dynamic_level
			if not dynamic_level:
				var tier: Variant = mp.get("tierRange", [])
				if not (tier is Array) or tier.size() != 2 or not _is_whole_level(tier[0]) or not _is_whole_level(tier[1]) or int(tier[0]) < 1 or int(tier[1]) < int(tier[0]):
					report.append("[maps] %s 的 tierRange 应为有效的 [最低等级, 最高等级]" % map_id)
				else:
					tier_ok = true
					tier_min = int(tier[0])
					tier_max = int(tier[1])
			if tier_ok:
				var spawn_specs: Array = mp.get("spawnPoints", []).duplicate()
				if mp.get("bossSpawn", null) is Dictionary:
					spawn_specs.append(mp.bossSpawn)
				if mp.get("bossSpawns", null) is Array:
					spawn_specs.append_array(mp.bossSpawns)
				for spec in spawn_specs:
					if spec is Dictionary and spec.has("level"):
						if not _is_whole_level(spec.level):
							report.append("[maps] %s 的 %s 刷新等级应为整数" % [map_id, spec.get("monsterId", "?")])
						else:
							var spec_level := int(spec.level)
							if dynamic_level:
								if spec_level > 0 and spec_level < level_min:
									report.append("[maps] %s 的 %s 刷新等级 %d 低于 levelFromPlayer.minLevel %d" % [map_id, spec.get("monsterId", "?"), spec_level, level_min])
							elif spec_level < 0 or (spec_level > 0 and (spec_level < tier_min or spec_level > tier_max)):
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
			# M10-3：多 Boss 点（循环图）。缺省 null 合法；一旦出现就必须逐条完整，
			# 否则「点没生成」与「点生成了但没掉落」都会沉到运行期才暴露。
			var multi: Variant = mp.get("bossSpawns", null)
			if multi != null:
				if not multi is Array:
					report.append("[maps] %s 的 bossSpawns 必须是数组" % map_id)
				else:
					for spec in (multi as Array):
						if not spec is Dictionary:
							report.append("[maps] %s 的 bossSpawns 条目必须是字典" % map_id)
							continue
						var mmid: String = String(spec.get("monsterId", ""))
						if mmid.is_empty() or not monster_ids.has(mmid):
							report.append("[maps] %s 的 bossSpawns 引用未定义怪物 '%s'" % [map_id, mmid])
						else:
							var m_tpl: Variant = get_entry("monsters", mmid)
							if m_tpl is Dictionary and String((m_tpl as Dictionary).get("kind", "")) != "boss":
								report.append("[maps] %s 的 bossSpawns 怪物 '%s' 的 kind 不是 boss" % [map_id, mmid])
						if not _valid_walk_cell(spec.get("cell", null), mp):
							report.append("[maps] %s 的 bossSpawns 怪物 '%s' 缺少合法的 cell" % [map_id, mmid])
						var mdt: String = String(spec.get("dropTableId", ""))
						if mdt.is_empty() or not dt_ids.has(mdt):
							report.append("[maps] %s 的 bossSpawns 怪物 '%s' 的 dropTableId '%s' 未在 dropTables 中定义" % [map_id, mmid, mdt])
			# M10-5：Boss 与普通点的 monsterId 不得重叠。
			# 墓碑与追猎令牌共用 `spawn_key(map, monster_id, ordinal)`，而 ordinal 由 Spawner
			# 跨 `spawnPoints` → boss 两次装配**连续累加**。一旦重叠，令牌按「boss 列表内序号」
			# 算出的 ordinal 会错位 ⇒ 面板显示「存活」而实际在冷却（或反之）。
			# 现在全库零重叠，这条校验把它从「巧合」变成「契约」。
			var spawn_ids := {}
			for sp in mp.get("spawnPoints", []):
				if sp is Dictionary:
					var sp_mid := String((sp as Dictionary).get("monsterId", ""))
					if not sp_mid.is_empty() and int((sp as Dictionary).get("count", 1)) > 0:
						spawn_ids[sp_mid] = true
			var boss_specs_for_overlap: Array = []
			if mp.get("bossSpawn", null) is Dictionary:
				boss_specs_for_overlap.append(mp.bossSpawn)
			if mp.get("bossSpawns", null) is Array:
				boss_specs_for_overlap.append_array(mp.bossSpawns)
			for spec in boss_specs_for_overlap:
				if not spec is Dictionary:
					continue
				var omid := String((spec as Dictionary).get("monsterId", ""))
				if spawn_ids.has(omid):
					report.append("[maps] %s 的 Boss '%s' 同时出现在 spawnPoints，会让刷新状态序号错位" % [map_id, omid])

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
				var shop_npc_id := String(s.get("npcId", ""))
				if RESERVED_SHOP_IDS.has(shop_npc_id):
					report.append("[shops] npcId '%s' 是随身商队的保留 id，真实店铺不得占用" % shop_npc_id)
				shop_ids[shop_npc_id] = true
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
	report.append_array(_validate_entry_gates(maps))
	report.append_array(_validate_gate_flags(maps))
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
	# 5) 五表结构化校验（B 共性-5）：类型 / 数值范围 / 跨表引用存在性。
	report.append_array(_validate_classes())
	report.append_array(_validate_skills())
	report.append_array(_validate_skill_progression())
	report.append_array(_validate_quests())
	report.append_array(_validate_potions())
	report.append_array(_validate_misc_items())
	report.append_array(_validate_sellable_prices())
	report.append_array(_validate_exchange())
	report.append_array(_validate_upgrade())
	report.append_array(_validate_endgame())
	report.append_array(_validate_durability())

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
	var slot_order: Variant = cfg.get("slotOrder", [])
	if not tiers is Array or tiers.is_empty() or not qualities is Dictionary or not fixed is Dictionary or not percent is Dictionary:
		report.append("[equipmentRules] 档位、品质与词条池非法")
		return report
	var expected_slots: Array[String] = Equipment.slot_kinds()   # B-P3-6：部位清单唯一来源在 Equipment
	if not slot_order is Array or slot_order.size() != 10:
		report.append("[equipmentRules] slotOrder 必须包含十种部位")
		return report
	for slot in expected_slots:
		if slot_order.count(slot) != 1:
			report.append("[equipmentRules] slotOrder 的 %s 必须恰好出现一次" % slot)
	if int(cfg.get("ruleVersion", 0)) != 4:
		report.append("[equipmentRules] ruleVersion 应为 4")
	var slot_coverage := {}
	var previous_tier := 0
	for tier in tiers:
		if not _is_whole_level(tier) or int(tier) < 1:
			report.append("[equipmentRules] 套起点必须是正整数")
			continue
		# 套起点为「1 起、每十级一档」的升序前缀（1、11、21、31、41、51…），
		# 允许只登记已投入的档位，后续章节再逐档补齐。
		if int(tier) <= previous_tier:
			report.append("[equipmentRules] 套起点必须严格升序")
		elif int(tier) != 1 and (int(tier) - 1) % 10 != 0:
			report.append("[equipmentRules] 套起点需为 1 起的每十级一档（1、11、21…）")
		previous_tier = int(tier)
		slot_coverage[str(int(tier))] = {}
	for factor_key in ["affixTierScale", "tierValueMultiplier"]:
		var factors: Variant = cfg.get(factor_key, {})
		for tier in tiers:
			if not factors is Dictionary or not (factors.get(str(int(tier))) is int or factors.get(str(int(tier))) is float) \
					or float(factors.get(str(int(tier)), 0.0)) <= 0.0:
				report.append("[equipmentRules] %s 缺少套起点 %d 的正数倍率" % [factor_key, int(tier)])
	if not _is_whole_level(cfg.get("maxStar")) or int(cfg.maxStar) != 12 \
			or not (cfg.get("starMult") is int or cfg.get("starMult") is float) or float(cfg.starMult) < 0.0:
		report.append("[equipmentRules] 星级参数非法")
	for quality in ItemUtil.QUALITIES:   # B-P3-6：品质枚举唯一来源在 ItemUtil
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
		# 15 号方案：阶段形象字段只允许写在武器模板上，取值为 look_ + 整数。
		# 只校验格式与落点，不要求素材已登记——素材未到时由 CharacterLook 回退默认形象。
		if e.has("look"):
			var look_id := String(e.get("look", ""))
			if slot != "weapon" or not look_id.begins_with("look_") or not look_id.trim_prefix("look_").is_valid_int():
				report.append("[equipments] %s 的 look 字段非法：%s" % [item_id, look_id])
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
		var actual_level: int = int(tier_key) + slot_order.find(slot)
		if not _is_whole_level(e.get("requiredLevel")) or int(e.get("requiredLevel", 0)) != actual_level:
			report.append("[equipments] %s 穿戴等级应为 Lv%d" % [item_id, actual_level])
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
		# 尚未登记任何型号的档位（如后续章节才投入的 31/41/51）不要求十部位齐全；
		# 一旦该档开始登记型号，就必须十部位各有一件可掉落型号。
		if slot_coverage[tier_key].is_empty():
			continue
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
	var quality_enum: Array = ItemUtil.QUALITIES   # B-P3-6：品质枚举唯一来源在 ItemUtil
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
					# M10-2：两套互斥口径——静态档靠 levelRange + tierStart，
					# 动态档（levelFromBoss）靠击杀目标的实际等级，所属套由 ItemFactory 锚定 51。
					# ⚠ 必须两个方向都报错：写成「两个都可选」会让带齐两者的坏表静默走错分支。
					var dynamic_flag: Variant = en.get("levelFromBoss", false)
					if not (dynamic_flag is bool):
						report.append("[dropTables] %s 的 levelFromBoss 必须为布尔值" % did)
						dynamic_flag = false
					var dynamic := bool(dynamic_flag)
					if en.has("requiredLevel"):
						report.append("[dropTables] %s equip 不能用 requiredLevel" % did)
					if dynamic:
						if en.has("tierStart"):
							report.append("[dropTables] %s equip 的 levelFromBoss 与 tierStart 互斥" % did)
						if en.has("levelRange"):
							report.append("[dropTables] %s equip 的 levelFromBoss 条目不应带 levelRange" % did)
						# 工程 91：`levelOffset` = 掉落等级在击杀目标等级上的偏移（孤王绝域 +10）。
						# 上界 9990 与 `ItemFactory.dynamic_tier_start` 的末档夹取对齐。
						if en.has("levelOffset"):
							var offset: Variant = en.get("levelOffset")
							if not _is_whole_level(offset) or int(offset) < 0 or int(offset) > 9990:
								report.append("[dropTables] %s 的 levelOffset 必须是 0—9990 的整数" % did)
					else:
						# 🔴 静态条配 levelOffset 会让实例等级与 requiredLevel 脱钩 ⇒ 必须报错，不能静默忽略。
						if en.has("levelOffset"):
							report.append("[dropTables] %s 的 levelOffset 只能配在 levelFromBoss 条目上" % did)
						var level_range: Variant = en.get("levelRange", null)
						if not level_range is Array or level_range.size() != 2 \
								or not _is_whole_level(level_range[0]) or not _is_whole_level(level_range[1]) \
								or int(level_range[0]) < 1 or int(level_range[1]) < int(level_range[0]):
							report.append("[dropTables] %s equip 条目缺少 levelRange" % did)
						if not en.has("tierStart"):
							report.append("[dropTables] %s equip 必须使用 tierStart，不能用 requiredLevel" % did)
						if en.has("tierStart"):
							var required: Variant = en.get("tierStart")
							var cfg: Variant = tables.get("equipmentRules")
							var legal := false
							if cfg is Dictionary and _is_whole_level(required):
								for configured in cfg.get("tiers", []):
									if int(configured) == int(required):
										legal = true
							if not legal:
								report.append("[dropTables] %s 的 tierStart 未在装备套起点表中" % did)
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

## 校验动态入场门槛的类型和引用，防止配置失误让地图从快捷旅行绕过。
func _validate_entry_gates(maps: Variant) -> Array[String]:
	var report: Array[String] = []
	if not maps is Array:
		return report
	var ids := {}
	for entry in maps:
		if entry is Dictionary:
			ids[String(entry.get("id", ""))] = true
	for entry in maps:
		if not entry is Dictionary or not entry.has("entryGate"):
			continue
		var map_id := String(entry.get("id", ""))
		var gate: Variant = entry.entryGate
		if not gate is Dictionary:
			report.append("[maps] %s 的 entryGate 必须是字典" % map_id)
			continue
		var origin := String((gate as Dictionary).get("walkOnlyFrom", ""))
		if origin.is_empty() or not ids.has(origin):
			report.append("[maps] %s 的 entryGate.walkOnlyFrom 必须引用已有地图" % map_id)
		var level: Variant = (gate as Dictionary).get("minLevel", null)
		if not _is_whole_level(level) or int(level) < 1:
			report.append("[maps] %s 的 entryGate.minLevel 必须是正整数" % map_id)
		var quality := String((gate as Dictionary).get("allEquipmentQuality", ""))
		if not quality.is_empty() and quality != "legendary":
			report.append("[maps] %s 的 entryGate.allEquipmentQuality 目前只支持 legendary" % map_id)
	return report

## 校验步行出口的双向拓扑与同格落点，避免进图后被困。
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
			var reverse_edge: Dictionary = {}
			var reverse_exits: Variant = target.get("exits", [])
			if reverse_exits is Array:
				for reverse in reverse_exits:
					if reverse is Dictionary and String(reverse.get("toMap", "")) == map_id:
						var own_entrances: Dictionary = entrances
						if own_entrances.has(String(reverse.get("toEntrance", ""))):
							reverse_edge = reverse
							break
			if reverse_edge.is_empty():
				report.append("[maps] %s 的出口 %s 缺少 %s 的双向返回出口" % [map_id, exit_id, to_id])
			elif not LEGACY_MAPS.has(to_id):
				## 同格契约（工程文档 19 §5.1 现行口径）：目标图入口落点须与其反向出口**同格**，
				## 否则玩家往返同一门户会落到不同位置。防「直接弹回」由 MapService 的到达锁承担。
				var landing: Array = target_entrances[target_entrance]
				var back_cell: Variant = reverse_edge.get("cell", null)
				if landing.size() == 2 and back_cell is Array and back_cell.size() == 2 \
						and (landing[0] != back_cell[0] or landing[1] != back_cell[1]):
					report.append("[maps] %s 的出口 %s → %s/%s 落点 %s 与反向出口 %s 落点 %s 不同格" % [
						map_id, exit_id, to_id, target_entrance, str(landing),
						String(reverse_edge.get("id", "")), str(back_cell)])
	return report

## E1（工程文档 30 §4）：门禁/交通——每个 `requiresUnlock` 都必须由某个任务奖励产出，
## 否则该条道路或刷新区会永久锁死（「免费步行永远能完成主线」的底线）。
## 字段形态同时校验：不锁就省略，写了就必须是非空字符串。
func _validate_gate_flags(maps: Variant) -> Array[String]:
	var report: Array[String] = []
	if not maps is Array:
		return report
	var produced := {}
	var quests = tables.get("quests")
	if quests is Array:
		for entry in quests:
			if not entry is Dictionary:
				continue
			var reward: Variant = entry.get("reward", null)
			if not reward is Dictionary:
				continue
			var single := String((reward as Dictionary).get("unlock", ""))
			if not single.is_empty():
				produced[single] = true
			var unlocks: Variant = (reward as Dictionary).get("unlocks", [])
			if unlocks is Array:
				for flag in unlocks:
					if not String(flag).is_empty():
						produced[String(flag)] = true
	for entry in maps:
		if not entry is Dictionary:
			continue
		var map_id := String(entry.get("id", "?"))
		report.append_array(_check_gate_flag("[maps] %s 的 requiresUnlock" % map_id, entry.get("requiresUnlock", null), produced))
		var raw_exits: Variant = entry.get("exits", null)
		if raw_exits is Array:
			for exit_data in (raw_exits as Array):
				if exit_data is Dictionary:
					report.append_array(_check_gate_flag("[maps] %s 的出口 %s requiresUnlock" % [map_id, exit_data.get("id", "?")],
						exit_data.get("requiresUnlock", null), produced))
		var spawn_specs: Array = []
		var raw_spawns: Variant = entry.get("spawnPoints", null)
		if raw_spawns is Array:
			spawn_specs.assign(raw_spawns)
		if entry.get("bossSpawn", null) is Dictionary:
			spawn_specs.append(entry.bossSpawn)
		# M10-3：多 Boss 点的门禁键同样必须有人产出，否则玩家永远进不去而不报错。
		if entry.get("bossSpawns", null) is Array:
			spawn_specs.append_array(entry.bossSpawns)
		for spec in spawn_specs:
			if spec is Dictionary:
				report.append_array(_check_gate_flag("[maps] %s 的刷新区 %s requiresUnlock" % [map_id, spec.get("monsterId", "?")],
					spec.get("requiresUnlock", null), produced))
	return report

## 已有数据以空串表示「不锁」，因此空串合法；一旦写了键名就必须有人产出该键。
func _check_gate_flag(label: String, raw: Variant, produced: Dictionary) -> Array[String]:
	if raw == null:
		return []
	if not raw is String:
		return ["%s 必须是字符串（不锁写空串）" % label] as Array[String]
	var flag: String = raw
	if flag.is_empty():
		return []
	if not produced.has(flag):
		return ["%s 引用无人产出的解锁键 '%s'（需由某任务 reward.unlock/unlocks 产出）" % [label, flag]] as Array[String]
	return []

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

## 数值须为有限且非负（int / float 皆可）。
func _is_nonnegative_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0

## 数值须为有限且严格为正。
func _is_positive_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0

## 由 maps.npcs 汇总的全部 npcId（任务 giver / turnIn / talk 目标的合法集合）。
func _npc_id_set() -> Dictionary:
	var out := {}
	var maps = tables.get("maps")
	if not (maps is Array):
		return out
	for entry in maps:
		if not entry is Dictionary:
			continue
		for spec in entry.get("npcs", []):
			if spec is Dictionary:
				var nid := String(spec.get("npcId", ""))
				if not nid.is_empty():
					out[nid] = true
	return out

## 工程 98 职业表：系数 / 射程 / 技能归属必须自洽。
## 最有价值的一条是「`skills` 与 skills.json 的 `class` 双向对齐」—— 只写一边会让
## 技能面板（按 skills 过滤）与快捷栏（按 classes 过滤）各说各话，玩家看到技能却拖不上去。
func _validate_classes() -> Array[String]:
	var report: Array[String] = []
	var rows: Variant = tables.get("classes")
	if not rows is Array or (rows as Array).is_empty():
		return ["[classes] 需要非空数组"] as Array[String]
	var seen := {}
	for raw in (rows as Array):
		if not raw is Dictionary:
			report.append("[classes] 条目必须是字典")
			continue
		var cid := String((raw as Dictionary).get("id", ""))
		if cid.is_empty() or seen.has(cid):
			report.append("[classes] id 为空或重复：%s" % cid)
			continue
		seen[cid] = true
		if String((raw as Dictionary).get("name", "")).is_empty():
			report.append("[classes] %s 缺少 name" % cid)
		for key in ["hpMult", "mpMult", "atkMult", "defMult"]:
			if not _is_positive_number((raw as Dictionary).get(key, null)):
				report.append("[classes] %s 的 %s 应为正数" % [cid, key])
		var reach: Variant = (raw as Dictionary).get("attackRange", null)
		if not _is_positive_number(reach) or float(reach) < 1.0:
			report.append("[classes] %s 的 attackRange 应不小于 1 格" % cid)
		var basic := String((raw as Dictionary).get("basicSkill", ""))
		var skills: Variant = (raw as Dictionary).get("skills", [])
		if not skills is Array or (skills as Array).is_empty():
			report.append("[classes] %s 的 skills 需要非空数组" % cid)
			continue
		if not (skills as Array).has(basic):
			report.append("[classes] %s 的 skills 必须包含普攻 %s" % [cid, basic])
		for sid in (skills as Array):
			var template: Variant = get_entry("skills", String(sid))
			if not template is Dictionary:
				report.append("[classes] %s 引用未定义技能 '%s'" % [cid, sid])
			elif String((template as Dictionary).get("class", "")) != cid:
				report.append("[classes] %s 的技能 '%s' 在 skills 表里归属 %s" % [
					cid, sid, String((template as Dictionary).get("class", ""))])
	if not seen.has("warrior"):
		report.append("[classes] 必须存在默认职业 warrior（旧档迁移的落点）")
	return report

## skills.json：类型 / 范围 / 形状 / 目标（B 共性-5）。
func _validate_skills() -> Array[String]:
	var report: Array[String] = []
	var skills = tables.get("skills")
	if not (skills is Array):
		report.append("[skills] 需要数组")
		return report
	for entry in skills:
		if not entry is Dictionary:
			continue
		var sid := String(entry.get("id", "?"))
		if String(entry.get("name", "")).is_empty():
			report.append("[skills] %s 缺少 name" % sid)
		# 工程 98：每条技能必须归属且只归属一个职业。缺省视为 warrior 会让
		# 「新加一条法师技能忘了写 class」变成静默出现在武士面板里。
		var owner := String(entry.get("class", ""))
		if owner.is_empty():
			report.append("[skills] %s 缺少 class 归属" % sid)
		elif get_entry("classes", owner) == null:
			report.append("[skills] %s 的 class '%s' 未在 classes 表登记" % [sid, owner])
		if entry.has("manaCostPct") \
				and (not _is_positive_number(entry.get("manaCostPct")) or float(entry.get("manaCostPct")) >= 1.0):
				report.append("[skills] %s 的 manaCostPct 应在 (0,1) 内（技能耗蓝系数）" % sid)
		if entry.has("basic") and not entry.get("basic") is bool:
			report.append("[skills] %s 的 basic 必须为布尔值" % sid)
		if not _is_whole_level(entry.get("unlockLevel")) or int(entry.get("unlockLevel", 0)) < 1:
			report.append("[skills] %s 的 unlockLevel 应为正整数" % sid)
		var kind := String(entry.get("kind", ""))
		if not ["attack", "buff"].has(kind):
			report.append("[skills] %s 的 kind '%s' 非法" % [sid, kind])
		if not _is_nonnegative_number(entry.get("coefficient", null)):
			report.append("[skills] %s 的 coefficient 应为非负数" % sid)
		if not _is_nonnegative_number(entry.get("cooldown", null)):
			report.append("[skills] %s 的 cooldown 应为非负数" % sid)
		if not _is_whole_level(entry.get("manaCost")) or int(entry.get("manaCost", -1)) < 0:
			report.append("[skills] %s 的 manaCost 应为非负整数" % sid)
		var shape := String(entry.get("shape", ""))
		if not ["single", "cone", "circle", "self"].has(shape):
			report.append("[skills] %s 的 shape '%s' 非法" % [sid, shape])
		if not _is_nonnegative_number(entry.get("range", null)):
			if shape != "self":
				report.append("[skills] %s 的 range 应为非负数" % sid)
		var target_type := String(entry.get("targetType", ""))
		if not ["enemy", "self"].has(target_type):
			report.append("[skills] %s 的 targetType '%s' 非法" % [sid, target_type])
		if kind == "buff":
			if not _is_positive_number(entry.get("duration", null)):
				report.append("[skills] %s 的 buff 需正数 duration" % sid)
			var effects: Variant = entry.get("effects")
			if not (effects is Dictionary) or (effects as Dictionary).is_empty():
				report.append("[skills] %s 的 buff 需非空 effects" % sid)
			else:
				for key in (effects as Dictionary):
					if not _is_positive_number((effects as Dictionary)[key]):
						report.append("[skills] %s 的 effects.%s 应为正数" % [sid, key])
		if String(entry.get("icon", "")).is_empty():
			report.append("[skills] %s 缺少 icon" % sid)
		# 工程 107：减益的结构校验。`defenseScale` 是**防御保留比例**，语义方向与
		# 「破甲幅度」相反 —— 写反了（填 1.42 表示破 42%）会静默变成「给怪加防」。
		var debuff: Variant = entry.get("debuff")
		if entry.has("debuff"):
			if not debuff is Dictionary:
				report.append("[skills] %s 的 debuff 应为字典" % sid)
			else:
				var dtype := String((debuff as Dictionary).get("type", ""))
				if not ["armorBreak", "slow"].has(dtype):
					report.append("[skills] %s 的 debuff.type '%s' 非法" % [sid, dtype])
				if not _is_positive_number((debuff as Dictionary).get("duration", null)):
					report.append("[skills] %s 的 debuff 需正数 duration" % sid)
				if (debuff as Dictionary).has("defenseScale"):
					var keep: Variant = (debuff as Dictionary).get("defenseScale")
					if not _is_positive_number(keep) \
							or float(keep) < ARMOR_BREAK_SCALE_FLOOR or float(keep) >= 1.0:
						report.append("[skills] %s 的 debuff.defenseScale 应在 [%.2f, 1) 内（防御保留比例，非破甲幅度）" % [sid, ARMOR_BREAK_SCALE_FLOOR])
	return report

## 玩家技能升级表：只允许五个非普攻技能，阶数连续且等级/金币/效果合法。
## 启动时校验一次；运行时解析器只读这份已经通过校验的配置。
func _validate_skill_progression() -> Array[String]:
	var report: Array[String] = []
	var config: Variant = tables.get("skillProgression")
	if not config is Array:
		report.append("[skillProgression] 需要数组")
		return report
	var expected: Dictionary = {}
	var skills: Variant = tables.get("skills")
	if skills is Array:
		for raw_skill in skills:
			# 工程 98：普攻由数据标记 `basic` 判定，不再写死 `basic_slash`（法师火球术同属普攻）。
			if raw_skill is Dictionary and not bool(raw_skill.get("basic", false)):
				expected[String(raw_skill.id)] = raw_skill
	var seen: Dictionary = {}
	for raw_entry in config:
		if not raw_entry is Dictionary:
			report.append("[skillProgression] 条目应为字典")
			continue
		var sid := String(raw_entry.get("skillId", ""))
		if not expected.has(sid) or seen.has(sid):
			report.append("[skillProgression] 技能 ID 未知或重复：%s" % sid)
			continue
		seen[sid] = true
		var ranks: Variant = raw_entry.get("ranks")
		if not ranks is Array or ranks.size() != 4:
			report.append("[skillProgression] %s 必须配置 2—5 阶" % sid)
			continue
		var base: Dictionary = expected[sid]
		var previous_cost := 0
		var previous_coefficient := 1.0
		# 工程 98：增益类技能的上一阶快照按**基础表的键**初始化 —— 战意觉醒是
		# attackPct / attackSpeedPct，魔法盾是 damageToManaPct。写死两个键会让魔法盾
		# 永远判定越界，或者（更糟）把它的升阶值当噪声放过。
		var previous_effects: Dictionary = {}
		var base_effects: Dictionary = base.get("effects", {})
		for key in base_effects.keys():
			previous_effects[String(key)] = float(base_effects[key])
		# 工程 107：破甲幅度的上一阶快照。基础表没写 defenseScale ⇒ 以 0.7 起算。
		var base_debuff: Dictionary = base.get("debuff", {})
		var previous_break_scale := float(base_debuff.get("defenseScale", 0.7))
		for i in range(4):
			var entry: Variant = ranks[i]
			if not entry is Dictionary:
				report.append("[skillProgression] %s 第 %d 阶应为字典" % [sid, i + 2])
				continue
			var rank := i + 2
			if not _is_whole_level(entry.get("rank")) or int(entry.rank) != rank:
				report.append("[skillProgression] %s 阶数应连续为 %d" % [sid, rank])
			if not _is_whole_level(entry.get("unlockLevel")) or int(entry.unlockLevel) != int(base.unlockLevel) + 10 * (rank - 1):
				report.append("[skillProgression] %s 第 %d 阶等级门槛非法" % [sid, rank])
			if not _is_whole_level(entry.get("goldCost")) or int(entry.goldCost) <= previous_cost or int(entry.goldCost) > 999999999:
				report.append("[skillProgression] %s 第 %d 阶金币价格应递增且不越上限" % [sid, rank])
			else:
				previous_cost = int(entry.goldCost)
			if String(base.get("kind", "")) == "buff":
				var effects: Variant = entry.get("effects")
				var next_effects: Dictionary = previous_effects.duplicate()
				var bad := not effects is Dictionary or (effects as Dictionary).size() != base_effects.size()
				if not bad:
					for key in base_effects.keys():
						var value: Variant = (effects as Dictionary).get(String(key), null)
						var cap := _progression_effect_cap(String(key))
						if not _is_nonnegative_number(value) \
								or float(value) <= float(next_effects.get(String(key), 0.0)) \
								or float(value) > cap:
							bad = true
							break
						next_effects[String(key)] = float(value)
				if bad:
					report.append("[skillProgression] %s 第 %d 阶增益越界" % [sid, rank])
				else:
					previous_effects = next_effects
			elif not _is_nonnegative_number(entry.get("coefficientMultiplier")) or float(entry.coefficientMultiplier) <= previous_coefficient or float(entry.coefficientMultiplier) > 1.12:
				report.append("[skillProgression] %s 第 %d 阶系数倍率越界" % [sid, rank])
			else:
				previous_coefficient = float(entry.coefficientMultiplier)
			# 工程 107：破甲幅度逐阶成长。三条判据（方向与「破甲幅度」相反，是保留比例）：
			# ① 落在 [0.55, 1) 内；② 逐阶只能**变小**（变不变大就是升阶变弱）；③ 类型必须与基础表一致。
			# 基础表没写 defenseScale 时以 0.7（工程 52 旧值）为起点，否则第一阶会被判成「越界变大」。
			var step_debuff: Variant = entry.get("debuff")
			if step_debuff is Dictionary:
				if String((step_debuff as Dictionary).get("type", "")) != String(base_debuff.get("type", "")):
					report.append("[skillProgression] %s 第 %d 阶 debuff.type 必须与基础表一致" % [sid, rank])
				elif (step_debuff as Dictionary).has("defenseScale"):
					var keep: Variant = (step_debuff as Dictionary).get("defenseScale")
					if not _is_positive_number(keep) \
							or float(keep) < ARMOR_BREAK_SCALE_FLOOR or float(keep) >= 1.0:
						report.append("[skillProgression] %s 第 %d 阶 debuff.defenseScale 应在 [%.2f, 1) 内" % [sid, rank, ARMOR_BREAK_SCALE_FLOOR])
					elif float(keep) >= previous_break_scale:
						report.append("[skillProgression] %s 第 %d 阶 debuff.defenseScale 必须小于上一阶（%.2f）" % [sid, rank, previous_break_scale])
					else:
						previous_break_scale = float(keep)
			elif entry.has("debuff"):
				report.append("[skillProgression] %s 第 %d 阶 debuff 应为字典" % [sid, rank])
	for sid in expected:
		if not seen.has(sid):
			report.append("[skillProgression] 缺少技能：%s" % sid)
	return report

## 增益键的满阶上限。未登记的键按 1.0 处理（仍要求逐阶递增，只是不限顶）——
## 新增效果键时必须在这里补一行，否则上限形同虚设。
func _progression_effect_cap(key: String) -> float:
	match key:
		"attackPct":
			return 0.26
		"attackSpeedPct":
			return 0.19
		"damageToManaPct":
			return 0.50
		# 工程 107：战意觉醒改用减伤（不再给攻击）。上限 = 5 阶 0.28。
		# ⚠ 减伤与魔法盾的转嫁是**乘算**关系，上限抬到 0.5 以上会让武士变成准无敌。
		"damageReducePct":
			return 0.28
	return 1.0

## quests.json：类型 / 结构 / 跨表引用（B 共性-5）。
func _validate_quests() -> Array[String]:
	var report: Array[String] = []
	var quests = tables.get("quests")
	if not (quests is Array):
		report.append("[quests] 需要数组")
		return report
	var monster_ids := _id_set("monsters")
	var misc_ids := _id_set("miscItems")
	var equip_ids := _id_set("equipments")
	var potion_ids := _id_set("potions")
	var map_ids := _id_set("maps")
	var quest_ids := _id_set("quests")
	var npc_ids := _npc_id_set()
	for entry in quests:
		if not entry is Dictionary:
			continue
		var qid := String(entry.get("id", "?"))
		if String(entry.get("name", "")).is_empty():
			report.append("[quests] %s 缺少 name" % qid)
		var qtype := String(entry.get("type", ""))
		if not ["main", "side"].has(qtype):
			report.append("[quests] %s 的 type '%s' 非法" % [qid, qtype])
		var giver := String(entry.get("giver", ""))
		if giver.is_empty() or not npc_ids.has(giver):
			report.append("[quests] %s 的 giver '%s' 未定义" % [qid, giver])
		if entry.has("turnIn"):
			var turn_in := String(entry.get("turnIn", ""))
			if turn_in.is_empty() or not npc_ids.has(turn_in):
				report.append("[quests] %s 的 turnIn '%s' 未定义" % [qid, turn_in])
		var prev := String(entry.get("prev", ""))
		if not prev.is_empty() and not quest_ids.has(prev):
			report.append("[quests] %s 的 prev '%s' 未定义" % [qid, prev])
		if not entry.get("abandonable", false) is bool:
			report.append("[quests] %s 的 abandonable 必须为布尔" % qid)
		# M10-4：等级门槛（可选字段）。0/缺失 = 无门槛；写在数据里就必须是合法等级。
		if entry.has("requiresLevel"):
			var need_level: Variant = entry.get("requiresLevel")
			if not _is_whole_level(need_level) or int(need_level) < 1 \
					or int(need_level) > MAX_QUEST_REQUIRES_LEVEL:
				report.append("[quests] %s 的 requiresLevel 应为 1–%d 的整数" % [qid, MAX_QUEST_REQUIRES_LEVEL])
		var scope: Variant = entry.get("mapScope", [])
		if not (scope is Array):
			report.append("[quests] %s 的 mapScope 应为数组" % qid)
		else:
			for map_id in (scope as Array):
				if not map_ids.has(String(map_id)):
					report.append("[quests] %s 的 mapScope 引用未定义地图 '%s'" % [qid, map_id])
		var obj: Variant = entry.get("objective")
		if not (obj is Dictionary):
			report.append("[quests] %s 缺少 objective" % qid)
		else:
			var objd: Dictionary = obj
			var okind := String(objd.get("kind", ""))
			if not ["kill", "collect", "talk"].has(okind):
				report.append("[quests] %s 的 objective.kind '%s' 非法" % [qid, okind])
			if not _is_whole_level(objd.get("count")) or int(objd.get("count", 0)) < 1:
				report.append("[quests] %s 的 objective.count 应为正整数" % qid)
			var target := String(objd.get("targetId", ""))
			if target.is_empty():
				report.append("[quests] %s 的 objective.targetId 为空" % qid)
			elif okind == "kill" and not monster_ids.has(target):
				report.append("[quests] %s 的击杀目标 '%s' 未定义" % [qid, target])
			elif okind == "collect" and not misc_ids.has(target):
				report.append("[quests] %s 的收集目标 '%s' 未定义" % [qid, target])
			elif okind == "talk" and not npc_ids.has(target):
				report.append("[quests] %s 的交谈目标 '%s' 未定义" % [qid, target])
			if objd.has("sourceMonster") and not monster_ids.has(String(objd.get("sourceMonster", ""))):
				report.append("[quests] %s 的 sourceMonster '%s' 未定义" % [qid, objd.get("sourceMonster", "")])
		if entry.has("reward"):
			report.append_array(_validate_quest_reward(qid, entry.get("reward"), equip_ids, misc_ids, potion_ids))
	return report

## quests.json 的 reward 结构 / 引用校验。
func _validate_quest_reward(qid: String, reward: Variant, equip_ids: Dictionary, misc_ids: Dictionary, potion_ids: Dictionary) -> Array[String]:
	var report: Array[String] = []
	if not (reward is Dictionary):
		report.append("[quests] %s 的 reward 应为对象" % qid)
		return report
	var rd: Dictionary = reward
	if not _nonnegative_whole(rd.get("gold", null)):
		report.append("[quests] %s 的 reward.gold 应为非负整数" % qid)
	if not _nonnegative_whole(rd.get("xp", null)):
		report.append("[quests] %s 的 reward.xp 应为非负整数" % qid)
	if rd.has("item"):
		var item_id := String(rd.get("item", ""))
		if not (equip_ids.has(item_id) or misc_ids.has(item_id)):
			report.append("[quests] %s 的 reward.item '%s' 未定义" % [qid, item_id])
	if rd.has("tierStart"):
		var legal := false
		var cfg: Variant = tables.get("equipmentRules")
		if cfg is Dictionary and _is_whole_level(rd.get("tierStart")):
			for configured in (cfg as Dictionary).get("tiers", []):
				if int(configured) == int(rd.get("tierStart")):
					legal = true
		if not legal:
			report.append("[quests] %s 的 reward.tierStart 未在装备套起点表中" % qid)
	if rd.has("items"):
		var items: Variant = rd.get("items")
		if not (items is Array):
			report.append("[quests] %s 的 reward.items 应为数组" % qid)
		else:
			for spec in (items as Array):
				if not (spec is Dictionary):
					report.append("[quests] %s 的 reward.items 含非法条目" % qid)
					continue
				var iid := String((spec as Dictionary).get("itemId", ""))
				if not (equip_ids.has(iid) or misc_ids.has(iid) or potion_ids.has(iid)):
					report.append("[quests] %s 的 reward.items 引用未定义物品 '%s'" % [qid, iid])
				if not _is_whole_level((spec as Dictionary).get("count", 0)) or int((spec as Dictionary).get("count", 0)) < 1:
					report.append("[quests] %s 的 reward.items count 应为正整数" % qid)
	return report

## potions.json：类型 / 范围（B 共性-5）。
func _validate_potions() -> Array[String]:
	var report: Array[String] = []
	var rows = tables.get("potions")
	if not (rows is Array):
		report.append("[potions] 需要数组")
		return report
	for entry in rows:
		if not entry is Dictionary:
			continue
		var pid := String(entry.get("id", "?"))
		if String(entry.get("name", "")).is_empty():
			report.append("[potions] %s 缺少 name" % pid)
		var pkind := String(entry.get("kind", ""))
		if not ["red", "blue"].has(pkind):
			report.append("[potions] %s 的 kind '%s' 非法" % [pid, pkind])
		if not _is_whole_level(entry.get("tier")) or int(entry.get("tier", 0)) < 1:
			report.append("[potions] %s 的 tier 应为正整数" % pid)
		if not _is_whole_level(entry.get("restoreAmount")) or int(entry.get("restoreAmount", 0)) < 1:
			report.append("[potions] %s 的 restoreAmount 应为正整数" % pid)
		# M10-10：`restorePercent` 缺省允许（退回固定值，向后兼容）；
		# 存在时必须落在 (0, 1) —— `pct >= 1` 等于「一瓶回满」，属设计外；`pct <= 0` 是无意义脏数据。
		# ⚠ 新增档位必须同步写 `restorePercent`：缺省不报错，该档在 61 级以上会静默退回固定量
		# （`potions.json` 是纯 JSON 数组、写不了注释，故约定落在本处与 08 §11.5）。
		var pct_value: Variant = entry.get("restorePercent", null)
		if pct_value != null and (not _is_positive_number(pct_value) or float(pct_value) >= 1.0):
			report.append("[potions] %s 的 restorePercent 应在 (0, 1) 内" % pid)
		if not _is_nonnegative_number(entry.get("cooldown", null)):
			report.append("[potions] %s 的 cooldown 应为非负数" % pid)
		if not _is_whole_level(entry.get("price")) or int(entry.get("price", -1)) < 0:
			report.append("[potions] %s 的 price 应为非负整数" % pid)
		if not _is_whole_level(entry.get("stackMax")) or int(entry.get("stackMax", 0)) < 1:
			report.append("[potions] %s 的 stackMax 应为正整数" % pid)
	return report

## miscItems.json：类型（B 共性-5）。
func _validate_misc_items() -> Array[String]:
	var report: Array[String] = []
	var rows = tables.get("miscItems")
	if not (rows is Array):
		report.append("[miscItems] 需要数组")
		return report
	for entry in rows:
		if not entry is Dictionary:
			continue
		var mid := String(entry.get("id", "?"))
		if String(entry.get("name", "")).is_empty():
			report.append("[miscItems] %s 缺少 name" % mid)
		var use_type := String(entry.get("useType", ""))
		if not ["playAnimation", "randomTeleport", "townPortal", "revive", "quest", "panel"].has(use_type):
			report.append("[miscItems] %s 的 useType '%s' 非法" % [mid, use_type])
		# M10-4（P-6）：`panelId` 只在 useType=panel 时允许 —— 两个方向都报错。
		# 只校验「非空」会让脏 id 活到运行时，双击才炸；只校验 panel 分支会让
		# 非 panel 道具挂个无效 panelId 而无人发现（同 levelFromBoss / levelFromPlayer 的坑）。
		var panel_id := String(entry.get("panelId", ""))
		if use_type == "panel":
			if panel_id.is_empty():
				report.append("[miscItems] %s 的 useType=panel 必须带 panelId" % mid)
			elif not PanelRouter.has(panel_id):
				report.append("[miscItems] %s 的 panelId '%s' 未登记" % [mid, panel_id])
		elif not panel_id.is_empty():
			report.append("[miscItems] %s 的 useType '%s' 不应带 panelId" % [mid, use_type])
		if not entry.get("animation", "") is String:
			report.append("[miscItems] %s 的 animation 应为字符串" % mid)
		# 工程 109：`bound` 是「绑定」标记（不可丢 / 不可售），金条金砖用它把
		# 「能换成金币」和「能卖成金币」两条通道分开。类型写错会静默失效（bool(null)=false），
		# 所以这里按字段存在即校验，而不是只在 true 时校验。
		if entry.has("bound") and not entry.get("bound") is bool:
			report.append("[miscItems] %s 的 bound 必须为布尔值" % mid)
	return report

## 可售品类必须配正价格（工程 39 D-7 / G3）：否则 `Shop.base_value()` 返回 0，
## 放行后玩家卖出去**静默拿 0 金币**。任务物品（`questItem: true`）不收，不参与本检查。
func _validate_sellable_prices() -> Array[String]:
	var report: Array[String] = []
	for table_name in ["potions", "miscItems", "runes"]:
		var rows = tables.get(table_name)
		if not (rows is Array):
			report.append("[%s] 需要数组" % table_name)
			continue
		for entry in rows:
			if not entry is Dictionary:
				continue
			if bool((entry as Dictionary).get("questItem", false)):
				continue
			var eid := String((entry as Dictionary).get("id", "?"))
			# 工程 109：绑定物（金条 / 金砖）刻意不可售 —— 价值只能走仓库兑换台，
			# 否则玩家能在货郎处把金条再卖一次，同一个资产两条换钱通道。
			# 绑定物必须 price 0（写了正价说明作者意图混乱，一并报出来）。
			if bool((entry as Dictionary).get("bound", false)):
				if int((entry as Dictionary).get("price", 0)) != 0:
					report.append("[%s] %s 是绑定物，price 必须为 0" % [table_name, eid])
				continue
			if not _is_whole_level((entry as Dictionary).get("price", null)) \
					or int((entry as Dictionary).get("price", 0)) <= 0:
				report.append("[%s] %s 缺少可售价格 price（可售品类必须为正整数）" % [table_name, eid])
	return report

## exchange.json：仓库兑换对（工程 109）。
## 🔴 这四条汇率就是玩家资产的交换比例，写错一位（100 万写成 10 万）**运行时不会报错**，
## 只会变成「白送金条」。启动期一次性把关，比事后对账便宜得多。
func _validate_exchange() -> Array[String]:
	var report: Array[String] = []
	var cfg: Variant = tables.get("exchange")
	if cfg == null:
		return report
	if not cfg is Dictionary:
		report.append("[exchange] 需要对象")
		return report
	var rows: Variant = (cfg as Dictionary).get("pairs", null)
	if not rows is Array or (rows as Array).is_empty():
		report.append("[exchange] pairs 需要非空数组")
		return report
	var seen := {}
	for row in (rows as Array):
		if not row is Dictionary:
			report.append("[exchange] pairs 成员必须为对象")
			continue
		var rid := String((row as Dictionary).get("id", ""))
		if rid.is_empty():
			report.append("[exchange] 存在缺少 id 的兑换对")
			continue
		if seen.has(rid):
			report.append("[exchange] 兑换对 id 重复：%s" % rid)
		seen[rid] = true
		var from_id := String((row as Dictionary).get("from", ""))
		var to_id := String((row as Dictionary).get("to", ""))
		for pair in [["from", from_id], ["to", to_id]]:
			var key := String(pair[0])
			var target := String(pair[1])
			if target.is_empty():
				report.append("[exchange] %s 缺少 %s" % [rid, key])
			elif target != "gold" and not (get_entry("miscItems", target) is Dictionary):
				report.append("[exchange] %s 的 %s '%s' 既不是 gold 也不在 miscItems" % [rid, key, target])
		if not from_id.is_empty() and from_id == to_id:
			report.append("[exchange] %s 的 from 与 to 不能相同" % rid)
		for key in ["fromCount", "toCount"]:
			if not _is_whole_level((row as Dictionary).get(key, null)) \
					or int((row as Dictionary).get(key, 0)) <= 0:
				report.append("[exchange] %s 的 %s 应为正整数" % [rid, key])
	return report

## upgrade.json：成功表长度 / 取值 / 费用参数（B 共性-5、E-P3-3）。
## M10-3（工程文档 43 §5.5）：循环 Boss 的归一化基底（`data/endgame.json`）。
## 十条登记必须指向真实 Boss 模板，且 `norm` 三键均为正整数 —— 写错会得到「1 血的纸 Boss」，
## 而且只在实际进图时才暴露（启动期是最便宜的一次拦截机会）。
func _validate_endgame() -> Array[String]:
	var report: Array[String] = []
	var cfg: Variant = tables.get("endgame")
	if cfg == null:
		return report
	if not cfg is Dictionary:
		return ["[endgame] 应为字典（含 arenaBosses 数组）"] as Array[String]
	var rows: Variant = (cfg as Dictionary).get("arenaBosses", [])
	if not rows is Array:
		return ["[endgame] arenaBosses 必须是数组"] as Array[String]
	var seen := {}
	for entry in (rows as Array):
		if not entry is Dictionary:
			report.append("[endgame] arenaBosses 条目必须是字典")
			continue
		var mid := String((entry as Dictionary).get("monsterId", ""))
		if mid.is_empty():
			report.append("[endgame] arenaBosses 存在缺少 monsterId 的条目")
			continue
		if seen.has(mid):
			report.append("[endgame] arenaBosses 重复 monsterId：%s" % mid)
		seen[mid] = true
		if not get_entry("monsters", mid) is Dictionary:
			report.append("[endgame] arenaBosses 引用未定义怪物 '%s'" % mid)
		var norm: Variant = (entry as Dictionary).get("norm", null)
		if not norm is Dictionary:
			report.append("[endgame] %s 缺少 norm 字典" % mid)
			continue
		for key in ["hp", "atk", "def"]:
			var value: Variant = (norm as Dictionary).get(key, null)
			if not _is_whole_level(value) or int(value) < 1:
				report.append("[endgame] %s 的 norm.%s 应为正整数" % [mid, key])
	var normals: Variant = (cfg as Dictionary).get("goldFieldNormals", [])
	if not normals is Array:
		report.append("[endgame] goldFieldNormals 必须是数组")
	else:
		for entry in (normals as Array):
			if not entry is Dictionary:
				report.append("[endgame] goldFieldNormals 条目必须是字典")
				continue
			var mid := String((entry as Dictionary).get("monsterId", ""))
			var template: Variant = get_entry("monsters", mid)
			if not template is Dictionary or String((template as Dictionary).get("kind", "")) != "normal":
				report.append("[endgame] goldFieldNormals 引用的 %s 不是普通怪" % mid)
			var norm: Variant = (entry as Dictionary).get("norm", {})
			for key in ["hp", "atk", "def"]:
				if not norm is Dictionary or not _is_whole_level((norm as Dictionary).get(key, null)) or int((norm as Dictionary).get(key, 0)) < 1:
					report.append("[endgame] %s 的 norm.%s 应为正整数" % [mid, key])
	return report

## 工程 77 耐久配置：上限为正整数、损耗分档非负整数、修理费参数为正数。
## 损耗分档必须登记 normal / elite / boss 三档（`Monster._kind()` 的全部取值），
## 少一档会让该类怪物击杀不磨损 —— 修理出口静默消失，比报错更难发现。
func _validate_durability() -> Array[String]:
	var report: Array[String] = []
	var cfg: Variant = tables.get("durability")
	if cfg == null:
		return ["[durability] 缺少配置文件"] as Array[String]
	if not cfg is Dictionary:
		return ["[durability] 应为字典"] as Array[String]
	var maximum: Variant = (cfg as Dictionary).get("maxDurability", null)
	if not _is_whole_level(maximum) or int(maximum) < 1:
		report.append("[durability] maxDurability 应为正整数")
	var wear: Variant = (cfg as Dictionary).get("wearPerKill", null)
	if not wear is Dictionary:
		report.append("[durability] wearPerKill 应为字典")
	else:
		for kind in ["normal", "elite", "boss"]:
			var points: Variant = (wear as Dictionary).get(kind, null)
			if not _is_whole_level(points) or int(points) < 0:
				report.append("[durability] wearPerKill.%s 应为非负整数" % kind)
	var repair: Variant = (cfg as Dictionary).get("repairCost", null)
	if not repair is Dictionary:
		report.append("[durability] repairCost 应为字典")
	else:
		for key in ["earlyPerLevel", "reforgeShare"]:
			var value: Variant = (repair as Dictionary).get(key, null)
			if not (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) or float(value) <= 0.0:
				report.append("[durability] repairCost.%s 应为正数" % key)
		var early_max: Variant = (repair as Dictionary).get("earlyMaxLevel", null)
		if not _is_whole_level(early_max) or int(early_max) < 1:
			report.append("[durability] repairCost.earlyMaxLevel 应为正整数")
	return report

func _validate_upgrade() -> Array[String]:
	var report: Array[String] = []
	var cfg = tables.get("upgrade")
	if not (cfg is Dictionary):
		report.append("[upgrade] 需要对象")
		return report
	var max_star := int((cfg as Dictionary).get("maxStar", -1))
	if not _is_whole_level((cfg as Dictionary).get("maxStar")) or max_star < 1:
		report.append("[upgrade] maxStar 应为正整数")
	var rates: Variant = (cfg as Dictionary).get("successRate")
	if not (rates is Array):
		report.append("[upgrade] successRate 应为数组")
	else:
		var arr: Array = rates
		if max_star >= 0 and arr.size() != max_star + 1:
			report.append("[upgrade] successRate 长度应为 maxStar+1（%d）" % (max_star + 1))
		for i in range(arr.size()):
			var value: Variant = arr[i]
			if not _is_whole_level(value) or int(value) < 0 or int(value) > 100:
				report.append("[upgrade] successRate[%d] 应为 0～100 的整数" % i)
			elif i < arr.size() - 1 and int(value) < int(arr[i + 1]):
				report.append("[upgrade] successRate[%d] 不应小于后一项" % i)
	var params: Variant = (cfg as Dictionary).get("costParams")
	if not (params is Dictionary):
		report.append("[upgrade] 缺少 costParams")
	else:
		if not _is_positive_number((params as Dictionary).get("UP_BASE", null)):
			report.append("[upgrade] costParams.UP_BASE 应为正数")
		if not _is_positive_number((params as Dictionary).get("UP_R", null)):
			report.append("[upgrade] costParams.UP_R 应为正数")
	return report
