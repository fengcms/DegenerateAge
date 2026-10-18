extends Node
## M10-8 装备重铸 + D-15 回收价轻缩放（工程 49 §6）：16 组用例。
##
## 三条最值钱的断言：
## 1. **用例 14 是重构安全网** —— 快照来自**重构前 HEAD 的真实输出**（固定种子跑一遍导出），
##    不是按公式反推。`_roll_affixes` 抽取只要挪动一次随机数调用，1—60 级全部掉落结果就变，
##    而游戏照常运行、没有任何报错 —— 只有这份快照能发现。
## 2. **用例 16 的分岔必须靠 `kind`** —— 真实数据里非装备都没有 `requiredLevel`，
##    所以「D-15 对全品类生效」这个错误在真实数据上看不出来（等级回退 1 ⇒ 倍率 1.0）。
##    必须注入一行带 `requiredLevel: 1000` 的药水作探针，才能证明分岔是结构性的。
## 3. **用例 10/11 的拒绝必须有牙** —— 普通品质重铸一次就是 36,000 金打水漂。

## 随机流快照（重构前导出，20 行 × 固定种子 1000+序号）。
## 每行：{id, tier, quality, level, affixes: [[stat, value]…], pctAttrs: [[stat, value]…]}。
## level == 0 表示 1—60 静态实例（走 make_equip_roll），> 0 表示动态实例（走 make_equip_dynamic）。
const SNAPSHOT := [
	{"id": "weapon_iron", "tier": 1, "quality": "legendary", "level": 0, "affixes": [[&"atk", 3], [&"hp", 8], [&"def", 3]], "pctAttrs": [[&"mpPercent", 0.032]]},
	{"id": "weapon_iron", "tier": 1, "quality": "rare", "level": 0, "affixes": [[&"hp", 14], [&"mp", 6]], "pctAttrs": []},
	{"id": "shield_basic", "tier": 1, "quality": "epic", "level": 0, "affixes": [[&"mp", 11], [&"hp", 14]], "pctAttrs": [[&"mpPercent", 0.076]]},
	{"id": "armor_cloth", "tier": 1, "quality": "uncommon", "level": 0, "affixes": [[&"hp", 17]], "pctAttrs": []},
	{"id": "c2_road_blade", "tier": 11, "quality": "legendary", "level": 0, "affixes": [[&"hp", 26], [&"atk", 6], [&"def", 10], [&"mp", 19]], "pctAttrs": []},
	{"id": "c2_road_helmet", "tier": 11, "quality": "rare", "level": 0, "affixes": [[&"atk", 5]], "pctAttrs": [[&"cdr", 0.041]]},
	{"id": "c3_equip_weapon", "tier": 21, "quality": "epic", "level": 0, "affixes": [[&"atk", 14], [&"hp", 39], [&"mp", 35]], "pctAttrs": []},
	{"id": "c3_equip_bracelet", "tier": 21, "quality": "legendary", "level": 0, "affixes": [[&"hp", 38], [&"atk", 13], [&"mp", 36]], "pctAttrs": [[&"hpPercent", 0.05]]},
	{"id": "c4_equip_armor", "tier": 31, "quality": "rare", "level": 0, "affixes": [[&"hp", 71], [&"def", 10]], "pctAttrs": []},
	{"id": "c4_equip_ring", "tier": 31, "quality": "legendary", "level": 0, "affixes": [[&"mp", 20], [&"atk", 16], [&"hp", 75]], "pctAttrs": [[&"mpPercent", 0.072]]},
	{"id": "c5_equip_shoes", "tier": 41, "quality": "epic", "level": 0, "affixes": [[&"atk", 20], [&"mp", 39], [&"hp", 97]], "pctAttrs": []},
	{"id": "c5_equip_necklace", "tier": 41, "quality": "uncommon", "level": 0, "affixes": [[&"atk", 16]], "pctAttrs": []},
	{"id": "c6_equip_weapon", "tier": 51, "quality": "legendary", "level": 0, "affixes": [[&"def", 25], [&"mp", 43], [&"hp", 76], [&"atk", 21]], "pctAttrs": []},
	{"id": "c6_equip_helmet", "tier": 51, "quality": "epic", "level": 0, "affixes": [[&"hp", 110], [&"def", 13]], "pctAttrs": [[&"hpPercent", 0.021]]},
	{"id": "c6_equip_bracelet", "tier": 51, "quality": "rare", "level": 0, "affixes": [[&"hp", 101], [&"atk", 28]], "pctAttrs": []},
	{"id": "c6_equip_knee", "tier": 51, "quality": "legendary", "level": 0, "affixes": [[&"mp", 51], [&"atk", 17], [&"hp", 86], [&"def", 16]], "pctAttrs": []},
	{"id": "c6_equip_weapon", "tier": 51, "quality": "legendary", "level": 61, "affixes": [[&"atk", 16], [&"hp", 124], [&"mp", 66], [&"def", 21]], "pctAttrs": []},
	{"id": "c6_equip_armor", "tier": 51, "quality": "epic", "level": 100, "affixes": [[&"def", 132], [&"hp", 749]], "pctAttrs": [[&"mpPercent", 0.049]]},
	{"id": "c6_equip_ring", "tier": 51, "quality": "legendary", "level": 1000, "affixes": [[&"atk", 49789], [&"hp", 225944], [&"mp", 64929]], "pctAttrs": [[&"cdr", 0.026]]},
	{"id": "c6_equip_shoes", "tier": 51, "quality": "rare", "level": 75, "affixes": [[&"atk", 43]], "pctAttrs": [[&"hpPercent", 0.054]]},
]

## 品质 → 词条条数（`equipmentRules.json` 的 affixCount，用例 5 逐品质锁死）。
const AFFIX_COUNT := {"uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ReforgeTest] " + label)

func _ready() -> void:
	_test_cost_points()
	_test_cost_params_wired()
	_test_missing_config()
	_test_fields_unchanged()
	_test_affix_count_preserved()
	_test_affix_ranges()
	_test_level_scale_follows_instance()
	_test_gold_deducted()
	_test_insufficient_gold()
	_test_common_rejected()
	_test_dirty_instance_rejected()
	_test_worn_broadcast_and_bonus()
	_test_bag_broadcast_and_slot()
	_test_random_stream_unchanged()
	_test_d15_three_steps()
	_test_d15_does_not_leak()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[ReforgeTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[ReforgeTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 工具 ----

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

## 造一件合法实例：`level > 60` 走动态分支，否则挂模板所属套。
func _make(item_id: String, level: int, quality: String, seed_value: int) -> Dictionary:
	var rng := _rng(seed_value)
	if level > Balance.SOFTCAP_LEVEL:
		return ItemFactory.make_equip_dynamic(item_id, level, quality, rng)
	return ItemFactory.make_equip_roll(item_id, ItemFactory.tier_start_for_template(item_id),
		quality, rng)

## 固定词条里某属性（atk / def / hp / mp）的合计值。
func _fixed_sum(item: Dictionary, stat: String) -> int:
	var total := 0
	for e in item.get("affixes", []):
		if e is Dictionary and String((e as Dictionary).get("stat", "")) == stat:
			total += int((e as Dictionary).get("value", 0))
	return total

## 模板词条池（用例 6 断言 stat 必须落在池内）。
func _affix_pool(item_id: String) -> Array:
	var tpl = DataLoader.get_entry("equipments", item_id)
	return (tpl as Dictionary).get("affixPool", []) if tpl is Dictionary else []

# ---- 1) 费用四个点（产品 D-17）----

func _test_cost_points() -> void:
	check(Reforge.cost(60) == 36000, "L60 重铸费应为 36,000，实际 %d" % Reforge.cost(60))
	check(Reforge.cost(61) == 36200, "L61 重铸费应为 36,200，实际 %d" % Reforge.cost(61))
	check(Reforge.cost(100) == 44000, "L100 重铸费应为 44,000，实际 %d" % Reforge.cost(100))
	check(Reforge.cost(1000) == 224000, "L1000 重铸费应为 224,000，实际 %d" % Reforge.cost(1000))

# ---- 2) 参数必须真的接线（改了 json 立刻生效）----

func _test_cost_params_wired() -> void:
	var cfg: Dictionary = DataLoader.get_table("endgame")
	var reforge: Dictionary = cfg.get("reforge", {})
	var original_base := int(reforge.get("baseGold", 0))
	var original_factor := float(reforge.get("levelFactor", 0.0))
	reforge["baseGold"] = 800
	check(Reforge.cost(60) == 72000, "baseGold 改成 800 后 L60 应为 72,000（写死 400 即红）")
	reforge["baseGold"] = original_base
	reforge["levelFactor"] = 0.0
	check(Reforge.cost(100) == 24000, "levelFactor 归零后 L100 应等于 baseGold×levelBase（漏乘即红）")
	reforge["levelFactor"] = original_factor
	check(Reforge.cost(60) == 36000, "还原参数后应回到 36,000")

# ---- 3) 配置缺失：返回 -1 并拒绝，不回退常量 ----

func _test_missing_config() -> void:
	var cfg: Dictionary = DataLoader.get_table("endgame")
	var saved: Variant = cfg.get("reforge", {})
	cfg.erase("reforge")
	var item := _make("c6_equip_necklace", 60, "legendary", 7)
	check(Reforge.cost(60) == -1, "缺 reforge 配置时 cost 应返回 -1，实际 %d" % Reforge.cost(60))
	var guard := Reforge.can_reforge(item)
	check(not bool(guard.get("ok", false)), "缺配置时不得放行重铸")
	check(String(guard.get("reason", "")).contains("配置"),
		"拒绝原因应说明配置缺失，实际「%s」" % String(guard.get("reason", "")))
	cfg["reforge"] = saved
	check(Reforge.cost(60) == 36000, "配置还原后应恢复 36,000")

# ---- 4) 除词条外逐键相等 ----

func _test_fields_unchanged() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 50000
	var item := _make("c6_equip_necklace", 60, "legendary", 11)
	item["star"] = 3
	var before := item.duplicate(true)
	GameState.inventory[0] = item
	var res := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")), _rng(99))
	check(bool(res.get("ok", false)), "应能重铸：%s" % String(res.get("reason", "")))
	var after: Dictionary = GameState.inventory[0]
	for key in ["instanceId", "itemId", "kind", "quality", "star", "requiredLevel", "level", "count",
			"rawBaseAttrs", "qualityMultiplierSnapshot", "starMultiplierSnapshot", "equipmentRuleVersion"]:
		check(str(after.get(key)) == str(before.get(key)), "%s 不得因重铸改变" % key)
	check(ItemUtil.affix_lines(after) != ItemUtil.affix_lines(before),
		"词条应发生变化（固定种子下必然不同）")
	check(ItemUtil.affix_lines(after).size() == ItemUtil.affix_lines(before).size(),
		"词条条数不得变化")

# ---- 5) 条数恒等于品质 affixCount ----

func _test_affix_count_preserved() -> void:
	for quality in AFFIX_COUNT:
		var expected := int(AFFIX_COUNT[quality])
		var item := _make("c6_equip_necklace", 60, String(quality), 21)
		for i in range(8):
			var rolled := ItemFactory.reroll_affixes(item, _rng(100 + i))
			check(bool(rolled.get("ok", false)), "%s 第 %d 次重掷应成功" % [quality, i])
			item["affixes"] = rolled.get("affixes", [])
			item["pctAttrs"] = rolled.get("pctAttrs", [])
			var total: int = (item.affixes as Array).size() + (item.pctAttrs as Array).size()
			check(total == expected, "%s 词条条数应恒为 %d，第 %d 次后为 %d" % [quality, expected, i, total])

# ---- 6) 词条合法：池内属性 + 数值区间 ----

func _test_affix_ranges() -> void:
	var rules: Dictionary = ItemFactory.rules()
	var fixed_cfg: Dictionary = rules.get("fixedAffixes", {})
	var pct_cfg: Dictionary = rules.get("percentAffixes", {})
	var tier_scale := float((rules.get("affixTierScale", {}) as Dictionary).get("51", 1.0))
	var pool := _affix_pool("c6_equip_necklace")
	var item := _make("c6_equip_necklace", 60, "legendary", 31)
	for i in range(12):
		var rolled := ItemFactory.reroll_affixes(item, _rng(200 + i))
		if not bool(rolled.get("ok", false)):
			check(false, "第 %d 次重掷应成功" % i)
			continue
		for e in rolled.get("affixes", []):
			var stat := String((e as Dictionary).get("stat", ""))
			check(pool.has(stat), "固定词条 %s 必须来自模板 affixPool" % stat)
			if not fixed_cfg.has(stat):
				continue
			var bounds: Dictionary = fixed_cfg[stat]
			var lo := maxi(1, int(round(float(bounds.get("min", 0)) * tier_scale)))
			var hi := maxi(lo, int(round(float(bounds.get("max", 0)) * tier_scale)))
			var value := int((e as Dictionary).get("value", 0))
			check(value >= lo and value <= hi,
				"L60 的 %s 应落在 [%d, %d]，实际 %d（用错 scale 即红）" % [stat, lo, hi, value])
		for e in rolled.get("pctAttrs", []):
			var stat := String((e as Dictionary).get("stat", ""))
			check(pool.has(stat), "百分比词条 %s 必须来自模板 affixPool" % stat)
			if not pct_cfg.has(stat):
				continue
			var bounds: Dictionary = pct_cfg[stat]
			var value := float((e as Dictionary).get("value", 0.0))
			check(value >= float(bounds.get("min", 0.0)) and value <= float(bounds.get("max", 0.0)),
				"百分比词条 %s 应落在 [%s, %s]，实际 %s" % [stat, bounds.get("min"), bounds.get("max"), value])

# ---- 7) 等级缩放跟随**实例** ----

## 🔴 若用 `tier_start_for_template()` 推 scale，循环套恒 51 ⇒ 倍率 6.0，
## L1000 的词条会砸回 L60 的 12—30 —— 这条会红（负向 N-3）。
func _test_level_scale_follows_instance() -> void:
	var rules: Dictionary = ItemFactory.rules()
	var fixed_cfg: Dictionary = rules.get("fixedAffixes", {})
	var tier_scale := float((rules.get("affixTierScale", {}) as Dictionary).get("51", 1.0))
	var scale := tier_scale * Balance.scale(1000 - Balance.SOFTCAP_LEVEL)
	var item := _make("c6_equip_weapon", 1000, "legendary", 41)
	for i in range(30):
		var rolled := ItemFactory.reroll_affixes(item, _rng(300 + i))
		if not bool(rolled.get("ok", false)):
			check(false, "L1000 第 %d 次重掷应成功" % i)
			continue
		for e in rolled.get("affixes", []):
			var stat := String((e as Dictionary).get("stat", ""))
			if not fixed_cfg.has(stat):
				continue
			var bounds: Dictionary = fixed_cfg[stat]
			var lo := maxi(1, int(round(float(bounds.get("min", 0)) * scale)))
			var value := int((e as Dictionary).get("value", 0))
			check(value >= lo, "L1000 的 %s 应 ≥ %d，实际 %d（砸回 L60 数值即红）" % [stat, lo, value])

# ---- 8) 扣费正确 + 连点第二次失败 ----

func _test_gold_deducted() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 50000
	var item := _make("c6_equip_necklace", 60, "legendary", 51)
	GameState.inventory[0] = item
	var first := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")), _rng(1))
	check(bool(first.get("ok", false)), "首次重铸应成功")
	check(int(first.get("cost", 0)) == 36000, "L60 应扣 36,000，实际 %d" % int(first.get("cost", 0)))
	check(GameState.gold == 14000, "重铸后金币应为 14,000，实际 %d" % GameState.gold)
	var second := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")), _rng(2))
	check(not bool(second.get("ok", false)), "金币不足时第二次应失败")
	check(GameState.gold == 14000, "失败不得再扣费，实际 %d" % GameState.gold)

# ---- 9) 金币不足：不扣钱、词条不变 ----

func _test_insufficient_gold() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 100
	var item := _make("c6_equip_necklace", 60, "legendary", 61)
	GameState.inventory[0] = item
	var before := item.duplicate(true)
	var res := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")), _rng(3))
	check(not bool(res.get("ok", false)), "金币不足应失败")
	check(String(res.get("reason", "")).contains("金币不足"),
		"失败原因应含「金币不足」，实际「%s」" % String(res.get("reason", "")))
	check(GameState.gold == 100, "失败不得扣费，实际 %d" % GameState.gold)
	check(str(GameState.inventory[0]) == str(before), "失败时词条必须逐键未变")

# ---- 10) 普通品质必须拒绝（否则 36,000 金白烧）----

func _test_common_rejected() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 100000
	var item := _make("c6_equip_necklace", 60, "common", 71)
	GameState.inventory[0] = item
	var before := item.duplicate(true)
	var res := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")), _rng(4))
	check(not bool(res.get("ok", false)), "普通品质（affixCount=0）不得重铸")
	check(String(res.get("reason", "")).contains("词条"),
		"拒绝原因应指向词条，实际「%s」" % String(res.get("reason", "")))
	check(GameState.gold == 100000, "拒绝时不得扣费，实际 %d" % GameState.gold)
	check(str(GameState.inventory[0]) == str(before), "拒绝时词条必须逐键未变")

# ---- 11) 脏实例：拒绝，不猜不修 ----

func _test_dirty_instance_rejected() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 100000
	var item := _make("c6_equip_necklace", 60, "legendary", 81)
	var only: Array = [item.affixes[0]]   # 传说应 4 条，这里只留 1 条
	item["affixes"] = only
	item["pctAttrs"] = []
	GameState.inventory[0] = item
	var before := item.duplicate(true)
	var res := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")), _rng(5))
	check(not bool(res.get("ok", false)), "词条条数与品质不符的实例应拒绝")
	check(String(res.get("reason", "")).contains("词条"),
		"拒绝原因应指向词条，实际「%s」" % String(res.get("reason", "")))
	check(GameState.gold == 100000, "拒绝时不得扣费")
	check(str(GameState.inventory[0]) == str(before), "拒绝时不得静默截断或补齐")

# ---- 12) 已穿戴：广播 + 属性随之变化 ----

func _test_worn_broadcast_and_bonus() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 50000
	var item := _make("c6_equip_necklace", 60, "legendary", 91)
	GameState.equipment["necklace"] = item
	var old_atk := _fixed_sum(item, "atk")
	var before_bonus := Equipment.bonus(GameState.equipment)
	var counter := [0]
	var on_changed := func() -> void: counter[0] += 1
	EventBus.equipment_changed.connect(on_changed)
	var res := GameState.reforge_equipment("worn", "necklace", String(item.get("instanceId", "")), _rng(6))
	EventBus.equipment_changed.disconnect(on_changed)
	check(bool(res.get("ok", false)), "已穿戴装备应能重铸")
	check(int(counter[0]) == 1, "已穿戴重铸应广播 1 次 equipment_changed，实际 %d" % int(counter[0]))
	var after_bonus := Equipment.bonus(GameState.equipment)
	var delta := _fixed_sum(item, "atk") - old_atk
	var actual := float(after_bonus.get("atk", 0.0)) - float(before_bonus.get("atk", 0.0))
	check(is_equal_approx(actual, float(delta)),
		"属性变化应与词条差一致：期望 %d，实际 %.3f" % [delta, actual])

# ---- 13) 背包：广播 + 格子不搬家 ----

func _test_bag_broadcast_and_slot() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 50000
	var item := _make("c6_equip_necklace", 60, "legendary", 101)
	GameState.inventory[5] = item
	var counter := [0]
	var on_changed := func() -> void: counter[0] += 1
	EventBus.inventory_changed.connect(on_changed)
	var res := GameState.reforge_equipment("bag", 5, String(item.get("instanceId", "")), _rng(7))
	EventBus.inventory_changed.disconnect(on_changed)
	check(bool(res.get("ok", false)), "背包装备应能重铸")
	check(int(counter[0]) == 1, "背包重铸应广播 1 次 inventory_changed，实际 %d" % int(counter[0]))
	var after = GameState.inventory[5]
	check(after is Dictionary and String((after as Dictionary).get("instanceId", "")) == String(item.get("instanceId", "")),
		"重铸后物品应留在原格（不得顺手重排背包）")
	check(GameState.inventory[4] == null and GameState.inventory[6] == null, "相邻格不得被搬动")

# ---- 14) 随机流不变（重构安全网）----

func _test_random_stream_unchanged() -> void:
	for index in range(SNAPSHOT.size()):
		var row: Dictionary = SNAPSHOT[index]
		var level := int(row.get("level", 0))
		var item_id := String(row.get("id", ""))
		var quality := String(row.get("quality", ""))
		var rng := _rng(1000 + index)
		var item: Dictionary
		if level > 0:
			item = ItemFactory.make_equip_dynamic(item_id, level, quality, rng, "snap")
		else:
			item = ItemFactory.make_equip_roll(item_id, int(row.get("tier", 0)), quality, rng, "snap")
		var label := "%s@%d %s" % [item_id, level if level > 0 else int(row.get("tier", 0)), quality]
		check(not item.is_empty(), "%s 应能生成（快照第 %d 行）" % [label, index])
		if item.is_empty():
			continue
		_compare_entries(label + " 固定词条", item.get("affixes", []), row.get("affixes", []))
		_compare_entries(label + " 百分比词条", item.get("pctAttrs", []), row.get("pctAttrs", []))

## 逐条比对 [stat, value]：**顺序也一致** —— 位置互换也是随机流被改了。
func _compare_entries(label: String, actual: Array, expected: Array) -> void:
	check(actual.size() == expected.size(),
		"%s 条数应为 %d，实际 %d（抽取顺序被改即红）" % [label, expected.size(), actual.size()])
	for i in range(mini(actual.size(), expected.size())):
		var got: Dictionary = actual[i] if actual[i] is Dictionary else {}
		var want: Array = expected[i] if expected[i] is Array else []
		check(String(got.get("stat", "")) == String(want[0] if want.size() > 0 else ""),
			"%s 第 %d 条应为 %s，实际 %s" % [label, i, want[0] if want.size() > 0 else "", got.get("stat", "")])
		check(is_equal_approx(float(got.get("value", -1.0)), float(want[1] if want.size() > 1 else -2.0)),
			"%s 第 %d 条数值应为 %s，实际 %s" % [label, i, want[1] if want.size() > 1 else "", got.get("value", "")])

# ---- 15) D-15 三段 ----

func _test_d15_three_steps() -> void:
	# 同一型号同一品质，只有等级不同 —— 否则模板基价会干扰比较（necklace 70 vs weapon 50）。
	var item60 := _make("c6_equip_weapon", 60, "rare", 111)
	var item100 := _make("c6_equip_weapon", 100, "rare", 112)
	var item1000 := _make("c6_equip_weapon", 1000, "rare", 113)
	var base := float(Shop.base_value(item60))
	check(is_equal_approx(base, float(Shop.base_value(item1000))),
		"同一型号的模板基价不随等级变化（缩放只来自 resale）")
	var sell60 := Shop.sell_price(item60)
	var sell100 := Shop.sell_price(item100)
	var sell1000 := Shop.sell_price(item1000)
	check(is_equal_approx(float(sell60), base * 3.0), "L60 不缩放：应 %.0f，实际 %d" % [base * 3.0, sell60])
	check(absf(float(sell100) - base * 3.0 * 1.8) <= 1.0,
		"L100 应 ×1.8 ≈ %.0f，实际 %d" % [base * 3.0 * 1.8, sell100])
	check(absf(float(sell1000) - base * 3.0 * 19.8) <= 1.0,
		"L1000 应 ×19.8 ≈ %.0f，实际 %d" % [base * 3.0 * 19.8, sell1000])

# ---- 16) D-15 不外溢 ----

func _test_d15_does_not_leak() -> void:
	var potion := {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	var potion_expected := int(round(float(Shop.base_value(potion)) * 1.0 * Shop.SELL_RATIO_NON_EQUIP)) * 3
	check(Shop.sell_price(potion) == potion_expected,
		"药水价应为改动前的 %d，实际 %d" % [potion_expected, Shop.sell_price(potion)])
	var rune := {"kind": "rune", "itemId": "rune_iron", "count": 2}
	var rune_expected := int(round(float(Shop.base_value(rune)) * 1.0 * Shop.SELL_RATIO_NON_EQUIP)) * 2
	check(Shop.sell_price(rune) == rune_expected,
		"如意价应为改动前的 %d，实际 %d" % [rune_expected, Shop.sell_price(rune)])
	var misc := {"kind": "misc", "itemId": "misc_firework", "count": 1}
	var misc_expected := int(round(float(Shop.base_value(misc)) * 1.0 * Shop.SELL_RATIO_NON_EQUIP))
	check(Shop.sell_price(misc) == misc_expected,
		"杂项价应为改动前的 %d，实际 %d" % [misc_expected, Shop.sell_price(misc)])
	var low := _make("weapon_iron", 1, "common", 121)
	check(Shop.sell_price(low) == Shop.base_value(low),
		"L1 装备不得缩放（max(0, L−60) 的 max 不能省，否则售价归零），实际 %d" % Shop.sell_price(low))
	# 探针：非装备带上 requiredLevel —— 证明分岔靠 kind，而不是「恰好等级为 1」
	var probe := {"kind": "potion", "itemId": "potion_hp_small", "count": 3, "requiredLevel": 1000}
	check(Shop.sell_price(probe) == potion_expected,
		"非装备不得按等级缩放（哪怕带 requiredLevel），实际 %d" % Shop.sell_price(probe))
