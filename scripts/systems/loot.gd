class_name Loot
extends RefCounted
## 掉落结算（产品文档 03.1 死亡结算 / 07.6 怪物点↔掉落表 / 10.2 dropTables schema）。
##
## 输入：掉落表 id（怪物模板的 dropTableId）；输出：物品实例数组。
## 掉落项**必在合法表内**（T07）：coin / potion / equip / rune / misc 五类，
## 品类、品质权重、itemId、等级范围均来自配置，不硬编码。
## 装备实例遵循「模板 ID 与实例 ID 分离、实例属性永久保存」（5.7 / 10.1）。
##
## misc（M2 新增）：杂项 / 任务收集物，读 miscItems 表 —— 用于灵能碎片（Q003）
## 这类「非装备、非消耗品」的产出路径。新增投放只需改 dropTables.json。

const KIND_COIN := "coin"
const KIND_POTION := "potion"
const KIND_EQUIP := "equip"
const KIND_RUNE := "rune"
const KIND_MISC := "misc"
const KIND_MOUNT := "mount"

## 装备品质、词条和档位构造均由 ItemFactory 统一处理。

## 结算一张掉落表，返回物品实例数组（不含随机数状态）。
##
## M6-0b 分组语义（创意 07 §12）：每个条目先判定 `chance` 一次，再按 `countRange`
## 抽取件数（缺省 1 件），各件独立抽品质与模板。旧「单条 = 单件」表沿用（countRange 缺省即 1）。
static func roll(drop_table_id: String, rng: RandomNumberGenerator = null, source_monster_id: String = "") -> Array:
	var r := rng if rng != null else _default_rng()
	var out: Array = []
	var table = DataLoader.get_entry("dropTables", drop_table_id)
	if table == null:
		return out
	var entries = table.get("entries", [])
	if not (entries is Array):
		return out
	for e in entries:
		if not (e is Dictionary):
			continue
		if r.randf() >= float(e.get("chance", 0.0)):
			continue
		var copies := _roll_count(e, r)
		for _i in range(copies):
			var item := _roll_entry(e, r, source_monster_id)
			if not item.is_empty():
				out.append(item)
	return out

## 按 `countRange`（[lo,hi] 整数等概率）抽取本条目生成件数；缺省 1（M6-0b / 创意 07 §12）。
static func _roll_count(e: Dictionary, r: RandomNumberGenerator) -> int:
	var cr = e.get("countRange", null)
	if not (cr is Array) or cr.size() < 2:
		return 1
	var a := int(cr[0])
	var b := int(cr[1])
	var lo := maxi(1, mini(a, b))
	var hi := maxi(1, maxi(a, b))
	return r.randi_range(lo, hi)

## 生成单个掉落项。
static func _roll_entry(e: Dictionary, r: RandomNumberGenerator, source_monster_id: String = "") -> Dictionary:
	match String(e.get("kind", "")):
		KIND_COIN:
			var gr = e.get("goldRange", [1, 1])
			var lo := int(gr[0]) if gr is Array and gr.size() >= 1 else 1
			var hi := int(gr[1]) if gr is Array and gr.size() >= 2 else lo
			return {"kind": KIND_COIN, "itemId": "coin", "gold": r.randi_range(lo, maxi(lo, hi)), "count": 1}
		KIND_POTION:
			var pid := String(e.get("itemId", ""))
			if pid.is_empty() or DataLoader.get_entry("potions", pid) == null:
				return {}
			# M6-0b：`count` 表示一个物品包的实际瓶数（Boss 大型生命药水 count=2，创意 07 §6/§12）。
			var pn := maxi(1, int(e.get("count", 1)))
			return {"kind": KIND_POTION, "itemId": pid, "count": pn}
		KIND_RUNE:
			var ids = e.get("itemIds", [])
			if e.has("itemId"):
				ids = [e.get("itemId")]
			if not (ids is Array) or ids.is_empty():
				return {}
			var rid := String(ids[r.randi_range(0, ids.size() - 1)])
			var rune = DataLoader.get_entry("runes", rid)
			if not rune is Dictionary:
				return {}
			if bool(rune.get("dropBossOnly", false)) and not source_monster_id.is_empty():
				var source = DataLoader.get_entry("monsters", source_monster_id)
				if not source is Dictionary or String(source.get("kind", "")) != "boss":
					return {}
			return {"kind": KIND_RUNE, "itemId": rid, "count": 1}
		KIND_EQUIP:
			return _roll_equip(e, r)
		KIND_MISC:
			var mid := String(e.get("itemId", ""))
			if mid.is_empty() or DataLoader.get_entry("miscItems", mid) == null:
				return {}
			return {"kind": KIND_MISC, "itemId": mid, "count": 1}
		KIND_MOUNT:
			var mount_id := String(e.get("itemId", ""))
			var mount = DataLoader.get_entry("mounts", mount_id)
			if not mount is Dictionary or source_monster_id != String(mount.get("dropBossId", "")) or GameState.owned_mounts.has(mount_id):
				return {}
			return {"kind": KIND_MOUNT, "itemId": mount_id, "count": 1}
	return {}

## 掉落只选择品质、穿戴档和型号，实例生成委托统一工厂。
static func _roll_equip(e: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var pool := String(e.get("templatePool", ""))
	var quality: String = _weighted_quality(e.get("qualityWeight", {}), r)
	var lr = e.get("levelRange", [1, 1])
	var lo := int(lr[0]) if lr is Array and lr.size() >= 1 else 1
	var hi := int(lr[1]) if lr is Array and lr.size() >= 2 else lo
	var source_level := r.randi_range(lo, maxi(lo, hi))
	var required_level := int(e.get("requiredLevel", ItemFactory.tier_for_level(source_level)))
	var tpl := _pick_equip_template(required_level, r, pool)
	if tpl.is_empty():
		return {}
	return ItemFactory.make_equip_roll(String(tpl.get("id", "")), required_level, quality, r, "drop")

## 按 qualityWeight 权重抽取品质（5.7 / 10.2）。
static func _weighted_quality(weights, r: RandomNumberGenerator) -> String:
	if not (weights is Dictionary) or weights.is_empty():
		return "common"
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return "common"
	var pick := r.randf() * total
	var acc := 0.0
	for k in weights.keys():
		acc += float(weights[k])
		if pick < acc:
			return String(k)
	return String(weights.keys()[weights.size() - 1])

## 只选真正配置了目标档位的正式型号；缺档不回退。
static func _pick_equip_template(required_level: int, r: RandomNumberGenerator, pool_id: String = "") -> Dictionary:
	var pool_def: Variant = _pool_def(pool_id)
	var matched: Array = []
	var t = DataLoader.get_table("equipments")
	if t is Array:
		for e in t:
			if not (e is Dictionary) or bool(e.get("debug", false)) or not bool(e.get("lootable", true)):
				continue
			if not _pool_accepts(pool_def, e):
				continue
			var bases: Variant = e.get("tierBases", {})
			if bases is Dictionary and bases.has(str(required_level)):
				matched.append(e)
	if matched.is_empty():
		push_error("[Loot] 装备池 %s 缺少 Lv%d 型号" % [pool_id, required_level])
		return {}
	return matched[r.randi_range(0, matched.size() - 1)]

static func _pool_def(pool_id: String) -> Variant:
	if pool_id.is_empty():
		return null
	return DataLoader.get_entry("lootPools", pool_id)

## 池仅筛型号，与品质分离；传说追加槽也能产出各部位。
static func _pool_accepts(pool_def: Variant, template: Dictionary) -> bool:
	if not (pool_def is Dictionary):
		return true
	var ids: Variant = pool_def.get("includeIds", [])
	if ids is Array and not ids.is_empty():
		return ids.has(String(template.get("id", "")))
	return true

static func _default_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r
