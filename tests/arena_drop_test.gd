extends Node
## M10-2 循环掉落接入契约（工程 42 §8）：
## `DT_C7_Arena_Boss` 的装备条目按 `levelFromBoss` 取等级，`Loot.roll` 的
## `source_level` 必须真的穿透到生成器；同时既有静态表一个字节都不许变。
## 核心底线：**参数透传链断开时循环图只会掉 60 档旧装**，而那种「能跑、能穿、就是不爽」
## 的退化最容易漏掉，所以 N-3/N-4 两把锁都压在 `requiredLevel` 上。

const ARENA_TABLE := "DT_C7_Arena_Boss"
const STATIC_TABLE := "DT_C6_Boss"
const STATIC_MONSTER := "c6_boss03"

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ArenaDropTest] " + label)

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func _ready() -> void:
	_test_table_contract()
	_test_level_follows()
	_test_count_range()
	_test_sellable()
	_test_default_fallback()
	_test_static_table_untouched()
	_test_static_still_v4()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[ArenaDropTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[ArenaDropTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

## 表结构契约：三件套互斥口径必须是「有 levelFromBoss、没有 levelRange / tierStart」。
func _test_table_contract() -> void:
	var table: Variant = DataLoader.get_entry("dropTables", ARENA_TABLE)
	check(table is Dictionary, "%s 必须存在于掉落表" % ARENA_TABLE)
	if not table is Dictionary:
		return
	var entries: Array = table.get("entries", [])
	check(entries.size() == 7, "循环 Boss 表应为 7 个条目，实际 %d" % entries.size())
	var equip_count := 0
	for en in entries:
		if not (en is Dictionary):
			continue
		if String(en.get("kind", "")) != "equip":
			continue
		equip_count += 1
		check(bool(en.get("levelFromBoss", false)), "循环表的 equip 条目必须标 levelFromBoss")
		check(not en.has("tierStart"), "levelFromBoss 条目不许带 tierStart（两者互斥）")
		check(not en.has("levelRange"), "levelFromBoss 条目不许带 levelRange（等级来自击杀目标）")
		check(not en.has("requiredLevel"), "equip 条目一律不许带 requiredLevel")
		var qsum := 0.0
		var qw: Variant = en.get("qualityWeight", {})
		if qw is Dictionary:
			for q in qw.keys():
				qsum += float(qw[q])
		check(absf(qsum - 100.0) <= 0.5, "equip 条目品质权重应合计 100，实际 %.1f" % qsum)
	check(equip_count == 3, "循环 Boss 表应有 3 个 equip 条目，实际 %d" % equip_count)

## 等级跟随：v5 实例的 reqLv 与全部基底属性都要由 source_level 决定。
func _test_level_follows() -> void:
	for level in [61, 70, 100, 1000]:
		var items := _roll_equips(level, 3)
		check(not items.is_empty(), "%d 级档应能滚出装备" % level)
		for item in items:
			check(int(item.get("equipmentRuleVersion", 0)) == ItemFactory.RULE_VERSION_DYNAMIC,
				"%d 级档装备版本应为 5，实际 %d" % [level, int(item.get("equipmentRuleVersion", 0))])
			check(int(item.get("requiredLevel", 0)) == level,
				"%d 级档 requiredLevel 应为 %d，实际 %d" % [level, level, int(item.get("requiredLevel", 0))])
			check(int(item.get("level", 0)) == level,
				"%d 级档 level 字段应为 %d，实际 %d" % [level, level, int(item.get("level", 0))])
			_check_raw_bases(item, level)
		# 武器是唯一能一眼对表的口径：61 → 84、1000 → 150630。
		var weapon_expect := {61: 84, 70: 165, 100: 564, 1000: 150630}
		for item in items:
			if String(item.get("itemId", "")) != "c6_equip_weapon":
				continue
			var atk := int((item.get("rawBaseAttrs", {}) as Dictionary).get("atk", 0))
			check(atk == int(weapon_expect[level]),
				"%d 级武器基底 atk 应为 %d，实际 %d" % [level, int(weapon_expect[level]), atk])

## 基底逐属性比对：maxi(1, round(tier51 原值 × S(level−60)))。
func _check_raw_bases(item: Dictionary, level: int) -> void:
	var found: Variant = DataLoader.get_entry("equipments", String(item.get("itemId", "")))
	if not found is Dictionary:
		check(false, "型号 %s 不在装备表" % String(item.get("itemId", "")))
		return
	var tpl: Dictionary = found
	var bases: Dictionary = tpl.get("tierBases", {})
	var raw_origin: Variant = bases.get(str(ItemFactory.DYNAMIC_BASE_TIER))
	if not raw_origin is Dictionary:
		check(false, "%s 缺少第 %d 套基底" % [String(item.get("itemId", "")), ItemFactory.DYNAMIC_BASE_TIER])
		return
	var factor := Balance.scale(level - Balance.SOFTCAP_LEVEL)
	var raw: Dictionary = item.get("rawBaseAttrs", {})
	for stat in raw_origin.keys():
		var expect := maxi(1, int(round(float(raw_origin[stat]) * factor)))
		var actual := int(raw.get(String(stat), -1))
		check(actual == expect,
			"%s @%d 的 %s 应为 %d（基底 %d × S），实际 %d"
				% [String(item.get("itemId", "")), level, String(stat), expect, int(raw_origin[stat]), actual])

## 件数区间：单只 Boss 7—10 件（5—8 普通 + 2 好装 + 5% 传说）。
func _test_count_range() -> void:
	for i in range(20):
		var rolled := Loot.roll(ARENA_TABLE, _rng(1000 + i), "arena_boss", 61)
		var count := _count_kind(rolled, Loot.KIND_EQUIP)
		check(count >= 7 and count <= 10,
			"第 %d 轮单只 Boss 应掉 7—10 件装备，实际 %d" % [i + 1, count])

## 全部可卖：金币口径不随等级缩放，单件回收落在 300—480。
func _test_sellable() -> void:
	var items := _roll_equips(1000, 3)
	check(not items.is_empty(), "1000 级档应能滚出装备")
	for item in items:
		check(Shop.can_sell(item), "%s 应可卖店" % String(item.get("itemId", "")))
		var value := Shop.base_value(item)
		check(value >= 300 and value <= 480,
			"%s 单件回收应落在 300—480，实际 %d（金币不随等级缩放）" % [String(item.get("itemId", "")), value])

## 缺省兜底：调用点忘了改也必须不掉 v5（宁可旧装，也不能写出读不回的档）。
func _test_default_fallback() -> void:
	var rolled := Loot.roll(ARENA_TABLE, _rng(77), "arena_boss")
	var items := _filter_kind(rolled, Loot.KIND_EQUIP)
	check(not items.is_empty(), "缺省 source_level 时也应滚出装备")
	for item in items:
		check(int(item.get("equipmentRuleVersion", 0)) == ItemFactory.RULE_VERSION_BASE,
			"缺省 source_level 应回落 v4，实际 %d" % int(item.get("equipmentRuleVersion", 0)))
		var tpl: Variant = DataLoader.get_entry("equipments", String(item.get("itemId", "")))
		var expect := int((tpl as Dictionary).get("requiredLevel", 0)) if tpl is Dictionary else -1
		check(int(item.get("requiredLevel", 0)) == expect,
			"缺省兜底 reqLv 应为模板值 %d，实际 %d" % [expect, int(item.get("requiredLevel", 0))])

## 静态表零影响：多传一个 source_level 不得改变任何一个字节的结果。
func _test_static_table_untouched() -> void:
	var before := Loot.roll(STATIC_TABLE, _rng(4242), STATIC_MONSTER)
	var after := Loot.roll(STATIC_TABLE, _rng(4242), STATIC_MONSTER, 100)
	check(before.size() == after.size(),
		"静态表多传 source_level 不应改变件数（%d vs %d）" % [before.size(), after.size()])
	var left := _strip_volatile(before)
	var right := _strip_volatile(after)
	check(left.size() == right.size(), "剔除易变字段后件数应一致")
	for i in range(mini(left.size(), right.size())):
		var a: Dictionary = left[i]
		var b: Dictionary = right[i]
		check(a.size() == b.size(), "第 %d 件的字段数应一致（%d vs %d）" % [i, a.size(), b.size()])
		for key in a.keys():
			check(b.has(key), "第 %d 件应含字段 %s" % [i, String(key)])
			check(_same_value(a[key], b.get(key)),
				"第 %d 件的 %s 应一致：%s vs %s" % [i, String(key), str(a[key]), str(b.get(key))])

## 静态表仍是 v4：动态分支没有把既有掉落带偏。
func _test_static_still_v4() -> void:
	var rolled := Loot.roll(STATIC_TABLE, _rng(4242), STATIC_MONSTER, 100)
	var items := _filter_kind(rolled, Loot.KIND_EQUIP)
	check(not items.is_empty(), "静态 Boss 表应能滚出装备")
	for item in items:
		check(int(item.get("equipmentRuleVersion", 0)) == ItemFactory.RULE_VERSION_BASE,
			"静态表装备版本应恒为 4，实际 %d" % int(item.get("equipmentRuleVersion", 0)))

## 滚若干轮并只留装备。
func _roll_equips(level: int, rounds: int) -> Array:
	var out: Array = []
	for i in range(rounds):
		out.append_array(_filter_kind(Loot.roll(ARENA_TABLE, _rng(level * 31 + i), "arena_boss", level), Loot.KIND_EQUIP))
	return out

func _filter_kind(items: Array, kind: String) -> Array:
	var out: Array = []
	for item in items:
		if item is Dictionary and String(item.get("kind", "")) == kind:
			out.append(item)
	return out

func _count_kind(items: Array, kind: String) -> int:
	return _filter_kind(items, kind).size()

## instanceId 由 Crypto 随机生成，不参与随机流比对。
func _strip_volatile(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if not (item is Dictionary):
			continue
		var copy: Dictionary = (item as Dictionary).duplicate(true)
		copy.erase("instanceId")
		out.append(copy)
	return out

## 深比较：Dictionary / Array 逐层比，其余按值比（数字统一转 float 规避 int/float 混比）。
func _same_value(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for key in (a as Dictionary).keys():
			if not (b as Dictionary).has(key):
				return false
			if not _same_value((a as Dictionary)[key], (b as Dictionary)[key]):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in range((a as Array).size()):
			if not _same_value((a as Array)[i], (b as Array)[i]):
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b
