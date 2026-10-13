class_name Equipment
extends RefCounted
## 装备栏（14 槽）与穿脱规则（产品文档 5.1 / 5.2 / 5.7 / 5.9 / 10.1）。
##
## 槽位（5.1）：防御向 [头盔][护甲][鞋子][盾牌][护腕×2][护膝×2]
##              攻击向 [武器][手镯×2][戒指×2][项链]  = 14 位
## 规则：武器与盾牌可同时装备；**装备即更新派生属性、不改基础值**；卸下需背包有空位。
## 穿戴门槛（5.2 / 4.5）：Lv ≥ max(模板 levelReq, (tier−1)×10 + 1)。
## 实例属性永久保存，穿脱不重随（5.7 / 10.1）。
## 本层只做装备语义与属性汇总，不依赖 UI（面板见 scripts/ui/inventory_panel.gd）。

## 14 槽定义：id 唯一（双槽类用 _1 / _2 后缀），kind 对应 equipments.json 的 slot 字段。
const SLOT_DEFS := [
	{"id": "weapon", "kind": "weapon", "label": "武器"},
	{"id": "shield", "kind": "shield", "label": "盾牌"},
	{"id": "helmet", "kind": "helmet", "label": "头盔"},
	{"id": "armor", "kind": "armor", "label": "护甲"},
	{"id": "shoes", "kind": "shoes", "label": "鞋子"},
	{"id": "necklace", "kind": "necklace", "label": "项链"},
	{"id": "bracer_1", "kind": "bracer", "label": "护腕"},
	{"id": "bracer_2", "kind": "bracer", "label": "护腕"},
	{"id": "knee_1", "kind": "knee", "label": "护膝"},
	{"id": "knee_2", "kind": "knee", "label": "护膝"},
	{"id": "bracelet_1", "kind": "bracelet", "label": "手镯"},
	{"id": "bracelet_2", "kind": "bracelet", "label": "手镯"},
	{"id": "ring_1", "kind": "ring", "label": "戒指"},
	{"id": "ring_2", "kind": "ring", "label": "戒指"},
]

## 可参与汇总的词条属性键（5.10 词条池 + 4.2 属性表）。
const BONUS_KEYS := [
	"atk", "def", "hp", "mp",
	"hpPercent", "mpPercent",
	"criticalChance", "criticalMultiplier", "attackInterval",
	"dodge", "block", "cdr", "movementSpeed",
]

## 5.9 「属性更高」评分权重（初稿，试玩调优）。
const SCORE_WEIGHTS := {"atk": 1.0, "def": 1.0, "hp": 0.3, "mp": 0.3}

# ---- 槽位 ----

## 新建 14 个空槽（槽 id → null）。
static func create() -> Dictionary:
	var slots := {}
	for d in SLOT_DEFS:
		slots[String(d.id)] = null
	return slots

## 槽位定义（按 id）。
static func slot_def(slot_id: String) -> Dictionary:
	for d in SLOT_DEFS:
		if String(d.id) == slot_id:
			return d
	return {}

## 读装备模板的槽类型（如 "weapon" / "ring"）。实例只存 itemId，类型取自模板（5.7）。
static func item_kind(item: Dictionary) -> String:
	var tpl = DataLoader.get_entry("equipments", String(item.get("itemId", "")))
	if tpl is Dictionary:
		return String(tpl.get("slot", ""))
	return ""

## 该类型的全部槽 id（双槽类返回 2 个）。
static func slots_for_kind(kind: String) -> Array[String]:
	var out: Array[String] = []
	for d in SLOT_DEFS:
		if String(d.kind) == kind:
			out.append(String(d.id))
	return out

## 槽位是否接受该装备（类型匹配，5.1）。
static func slot_accepts(slot_id: String, item: Dictionary) -> bool:
	var d := slot_def(slot_id)
	if d.is_empty():
		return false
	return String(d.kind) == item_kind(item)

## 自动选槽：优先同类空槽，全占用则取第一个同类槽（用于替换）。
## 无匹配槽返回空串。
static func auto_slot_for(slots: Dictionary, item: Dictionary) -> String:
	var kind := item_kind(item)
	if kind.is_empty():
		return ""
	var ids := slots_for_kind(kind)
	for sid in ids:
		if slots.get(sid) == null:
			return sid
	return ids[0] if not ids.is_empty() else ""

# ---- 穿戴门槛 ----

## 装备的模板（equipments.json 条目）。
static func template_of(item: Dictionary) -> Dictionary:
	var tpl = DataLoader.get_entry("equipments", String(item.get("itemId", "")))
	return tpl if tpl is Dictionary else {}

## 穿戴等级门槛（5.2 / 4.5）：max(模板 levelReq, (tier−1)×10 + 1)。
static func level_req(item: Dictionary) -> int:
	var tpl := template_of(item)
	if tpl.is_empty():
		return 1
	var tier := int(tpl.get("tier", 1))
	return maxi(int(tpl.get("levelReq", 1)), (tier - 1) * 10 + 1)

## 等级是否满足穿戴门槛。
static func meets_level(item: Dictionary, level: int) -> bool:
	return level >= level_req(item)

# ---- 穿 / 卸 ----

## 从背包取出并穿上（成功后背包该格清空；被替换的旧装备回到背包）。
## 返回 {ok: bool, reason: String, replaced: Dictionary}。失败不改变任何状态。
static func equip_from_inventory(slots: Dictionary, inv: Array, slot_id: String,
		inv_index: int, level: int) -> Dictionary:
	if inv_index < 0 or inv_index >= inv.size() or inv[inv_index] == null:
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p001"), "replaced": {}}
	var item: Dictionary = inv[inv_index]
	if String(item.get("kind", "")) != "equip":
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p002"), "replaced": {}}
	if not slots.has(slot_id):
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p003"), "replaced": {}}
	if not slot_accepts(slot_id, item):
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p004"), "replaced": {}}
	if not meets_level(item, level):
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p005") % level_req(item), "replaced": {}}

	var old = slots[slot_id]
	# 新装备自身腾出的格始终足够容纳一件旧装备，直接交换保留实例属性。
	inv[inv_index] = old if old is Dictionary else null
	slots[slot_id] = item
	return {"ok": true, "reason": "", "replaced": old if old is Dictionary else {}}

## 卸下槽位 → 入背包（需空位，5.1）。成功返回 {ok, reason, item}。
static func unequip(slots: Dictionary, inv: Array, slot_id: String) -> Dictionary:
	var item = slots.get(slot_id)
	if not (item is Dictionary):
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p006"), "item": {}}
	if not Inventory.has_space_for(inv, item):
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p007"), "item": {}}
	Inventory.add(inv, item)
	slots[slot_id] = null
	return {"ok": true, "reason": "", "item": item}

## 拖到背包指定空格卸下；失败时两侧都不改变。
static func unequip_to_index(slots: Dictionary, inv: Array, slot_id: String, inv_index: int) -> Dictionary:
	var item: Variant = slots.get(slot_id)
	if not item is Dictionary:
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p006"), "item": {}}
	if inv_index < 0 or inv_index >= inv.size():
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p008"), "item": {}}
	if inv[inv_index] != null:
		return {"ok": false, "reason": Localization.tr_key("msg.equipment.p009"), "item": {}}
	inv[inv_index] = item
	slots[slot_id] = null
	return {"ok": true, "reason": "", "item": item}

# ---- 属性汇总 ----

## 汇总已穿戴装备的属性加成（固定值累加、百分比累加）。
## 返回含 BONUS_KEYS 全键的字典（未出现的键为 0）。
static func bonus(slots: Dictionary) -> Dictionary:
	var b := {}
	for k in BONUS_KEYS:
		b[k] = 0.0
	for sid in slots.keys():
		var it = slots[sid]
		if not (it is Dictionary):
			continue
		accumulate(b, Upgrade.base_attrs(it))
		accumulate(b, it.get("affixes", []))
		accumulate(b, it.get("pctAttrs", []))
	return b

## 把一处属性来源累加进目标字典。支持两种形态：
## 字典（baseAttrs: {atk: 5}）与数组（affixes / pctAttrs: [{stat, value}]）。
static func accumulate(target: Dictionary, src) -> void:
	if src is Dictionary:
		for k in src.keys():
			var key := String(k)
			if target.has(key):
				target[key] = float(target[key]) + float(src[k])
	elif src is Array:
		for e in src:
			if e is Dictionary:
				var key := String(e.get("stat", ""))
				if target.has(key):
					target[key] = float(target[key]) + float(e.get("value", 0.0))

## 5.9 「属性更高」评分（用于替换提示 / 一键出售排除）。
static func score(item: Dictionary) -> float:
	if item.is_empty():
		return 0.0
	var b := {}
	for k in BONUS_KEYS:
		b[k] = 0.0
	accumulate(b, Upgrade.base_attrs(item))
	accumulate(b, item.get("affixes", []))
	accumulate(b, item.get("pctAttrs", []))
	var s := 0.0
	for k in SCORE_WEIGHTS.keys():
		s += float(b[k]) * float(SCORE_WEIGHTS[k])
	s += float(b["hpPercent"]) * 100.0 * float(SCORE_WEIGHTS["hp"])
	s += float(b["mpPercent"]) * 100.0 * float(SCORE_WEIGHTS["mp"])
	return s

## 已穿戴装备总件数（存档 / UI 摘要用）。
static func worn_count(slots: Dictionary) -> int:
	var n := 0
	for sid in slots.keys():
		if slots[sid] is Dictionary:
			n += 1
	return n
