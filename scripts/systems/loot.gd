class_name Loot
extends RefCounted
## 掉落结算（产品文档 03.1 死亡结算 / 07.6 怪物点↔掉落表 / 10.2 dropTables schema）。
##
## 输入：掉落表 id（怪物模板的 dropTableId）；输出：物品实例数组。
## 掉落项**必在合法表内**（T07）：coin / potion / equip / rune 四类，
## 品类、品质权重、itemId、等级范围均来自配置，不硬编码。
## 装备实例遵循「模板 ID 与实例 ID 分离、实例属性永久保存」（5.7 / 10.1）。

const KIND_COIN := "coin"
const KIND_POTION := "potion"
const KIND_EQUIP := "equip"
const KIND_RUNE := "rune"

## 5.10 随机词条数：普 0 / 优 1 / 稀 1–2 / 史 2–3 / 传 = 独特被动（不随机词条）。
const AFFIX_COUNT := {
	"common": [0, 0],
	"uncommon": [1, 1],
	"rare": [1, 2],
	"epic": [2, 3],
	"legendary": [0, 0],
}

## 5.10 词条池（固定值）：属性 → {min,max}。百分比词条（2%~8%）仅稀/史小概率出现。
const AFFIX_POOL := [
	{"stat": "atk", "min": 2, "max": 5},
	{"stat": "def", "min": 2, "max": 5},
	{"stat": "hp", "min": 8, "max": 20},
	{"stat": "mp", "min": 5, "max": 12},
]
const PCT_AFFIX_POOL := [
	{"stat": "hpPercent", "min": 0.02, "max": 0.08},
	{"stat": "mpPercent", "min": 0.02, "max": 0.08},
]
const PCT_AFFIX_CHANCE := 0.5      # 稀/史中，出现 1 条百分比词条的概率

## 装备实例属性随等级的缩放（5.2 每 10 级一套；M1 仅 tier-1 模板，按等级线性微调）。
const EQUIP_LV_SCALE := 0.08

static var _seq: int = 0

## 结算一张掉落表，返回物品实例数组（不含随机数状态）。
static func roll(drop_table_id: String, rng: RandomNumberGenerator = null) -> Array:
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
		var item := _roll_entry(e, r)
		if not item.is_empty():
			out.append(item)
	return out

## 生成单个掉落项。
static func _roll_entry(e: Dictionary, r: RandomNumberGenerator) -> Dictionary:
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
			return {"kind": KIND_POTION, "itemId": pid, "count": 1}
		KIND_RUNE:
			var ids = e.get("itemIds", [])
			if not (ids is Array) or ids.is_empty():
				return {}
			var rid := String(ids[r.randi_range(0, ids.size() - 1)])
			return {"kind": KIND_RUNE, "itemId": rid, "count": 1}
		KIND_EQUIP:
			return _roll_equip(e, r)
	return {}

## 生成一件装备实例（品质按权重 → 基础属性按等级缩放 → 随机词条）。
static func _roll_equip(e: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var quality := _weighted_quality(e.get("qualityWeight", {}), r)
	var lr = e.get("levelRange", [1, 1])
	var lo := int(lr[0]) if lr is Array and lr.size() >= 1 else 1
	var hi := int(lr[1]) if lr is Array and lr.size() >= 2 else lo
	var level := r.randi_range(lo, maxi(lo, hi))

	var tpl := _pick_equip_template(level, r)
	if tpl.is_empty():
		return {}
	var base := _scale_base_attrs(tpl.get("baseAttrs", {}), level, int(tpl.get("levelReq", 1)))
	var affixes: Array = []
	var pct: Array = []
	if quality != "legendary":
		var cnt_range: Array = AFFIX_COUNT.get(quality, [0, 0])
		var n := r.randi_range(int(cnt_range[0]), int(cnt_range[1]))
		affixes = _roll_affixes(n, r)
		if quality in ["rare", "epic"] and r.randf() < PCT_AFFIX_CHANCE:
			var p = PCT_AFFIX_POOL[r.randi_range(0, PCT_AFFIX_POOL.size() - 1)]
			pct.append({"stat": p.stat, "value": snappedf(r.randf_range(p.min, p.max), 0.001)})
	_seq += 1
	return {
		"kind": KIND_EQUIP,
		"itemId": String(tpl.get("id", "")),
		"instanceId": "inst_%d_%d" % [Time.get_ticks_msec(), _seq],
		"quality": quality,
		"level": level,
		"baseAttrs": base,
		"affixes": affixes,
		"pctAttrs": pct,
		"star": 0,
		"count": 1,
	}

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

## 选取等级适配的装备模板：优先 tier 匹配（每 10 级一套，5.2），否则回退全表随机。
## 无可用模板时返回空字典。
## 带 "debug": true 标记的模板（开发期测试装备）不参与抽取，避免污染正式掉落。
static func _pick_equip_template(level: int, r: RandomNumberGenerator) -> Dictionary:
	var tier := int(ceil(float(level) / 10.0))
	var all: Array = []
	var matched: Array = []
	var t = DataLoader.get_table("equipments")
	if t is Array:
		for e in t:
			if not (e is Dictionary):
				continue
			if bool(e.get("debug", false)):
				continue
			all.append(e)
			if int(e.get("tier", 1)) == tier:
				matched.append(e)
	var pool: Array = matched if not matched.is_empty() else all
	if pool.is_empty():
		return {}
	var pick: Dictionary = pool[r.randi_range(0, pool.size() - 1)]
	return pick

## 基础属性按等级线性缩放（min 1），保持整数属性。
static func _scale_base_attrs(base_attrs, level: int, level_req: int) -> Dictionary:
	var out := {}
	if not (base_attrs is Dictionary):
		return out
	var factor := 1.0 + EQUIP_LV_SCALE * float(level - level_req)
	for k in base_attrs.keys():
		out[k] = maxi(1, int(round(float(base_attrs[k]) * factor)))
	return out

## 抽取 n 条不重复词条的固定值。
static func _roll_affixes(n: int, r: RandomNumberGenerator) -> Array:
	var out: Array = []
	var used := {}
	var guard := 0
	while out.size() < n and guard < 30:
		guard += 1
		var p = AFFIX_POOL[r.randi_range(0, AFFIX_POOL.size() - 1)]
		if used.has(p.stat):
			continue
		used[p.stat] = true
		out.append({"stat": p.stat, "value": r.randi_range(int(p.min), int(p.max))})
	return out

static func _default_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r
