extends Node
## 工程 86：重铸精炼（投入紫装抬高本次未锁定词条下限）—— 8 组用例。
##
## 三条最值钱的断言：
## 1. **有效件数按档位折算，不是按件数** —— 低档料按 1:1 平替同档料会让「四紫升档」与
##    保星的材料价值被重铸吸干，必须用 0.5 / 0.25 的折价把低档料挡在上限外。
## 2. **下限真的生效且只作用于未锁定词条** —— 只断「参数传进去了」是假绿；这里用
##    `floor_ratio = 1.0` 把区间压成一点，逐条比对上下界。
## 3. **先掷后扣** —— 材料缺失 / 收藏 / 非紫装都必须整单拒绝且**一件不扣、金币不扣**；
##    成功时材料与金币同批扣除，目标实例的 id / 品质 / 星级 / 等级一律不变。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[RefineTest] " + label)

func _ready() -> void:
	_test_floor_points()
	_test_tier_conversion()
	_test_cap()
	_test_can_refine_rejections()
	_test_floor_applied_to_bounds()
	_test_locked_entry_untouched()
	_test_settlement_consumes_materials()
	_test_settlement_rejects_without_consuming()
	_test_ui_material_slots()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[RefineTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error(failure)
		print("[RefineTest] 失败 %d 项" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- 工具 ----

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func _make(item_id: String, level: int, quality: String, seed_value: int) -> Dictionary:
	if level > Balance.SOFTCAP_LEVEL:
		return ItemFactory.make_equip_exact(item_id, level, quality, _rng(seed_value))
	return ItemFactory.make_equip_roll(item_id, ItemFactory.tier_start_for_template(item_id),
		quality, _rng(seed_value))

## 与 `ItemFactory.reroll_affixes` 同口径的词条倍率（按实例等级）。
func _affix_scale(level: int) -> float:
	var scales: Dictionary = ItemFactory.rules().get("affixTierScale", {})
	var dynamic := level > Balance.SOFTCAP_LEVEL
	var key := str(ItemFactory.DYNAMIC_BASE_TIER) if dynamic else str(ItemFactory.tier_for_level(level))
	var factor := Balance.scale(level - Balance.SOFTCAP_LEVEL) if dynamic else 1.0
	return float(scales.get(key, 0.0)) * factor

func _fixed_bounds(stat: String, level: int) -> Vector2i:
	var cfg: Dictionary = ItemFactory.rules().get("fixedAffixes", {})
	if not cfg.has(stat):
		return Vector2i(-1, -1)
	var bounds: Dictionary = cfg[stat]
	var scale := _affix_scale(level)
	var lo := maxi(1, int(round(float(bounds.min) * scale)))
	return Vector2i(lo, maxi(lo, int(round(float(bounds.max) * scale))))

# ---- 1) 下限比例四个点 ----

func _test_floor_points() -> void:
	check(is_equal_approx(Reforge.floor_ratio(0.0), 0.0), "0 件下限应为 0")
	check(is_equal_approx(Reforge.floor_ratio(1.0), 0.15), "1 件下限应为 15%")
	check(is_equal_approx(Reforge.floor_ratio(4.0), 0.60), "4 件下限应为 60%")
	check(is_equal_approx(Reforge.floor_ratio(9.0), 0.60), "超过上限仍应封顶 60%")
	check(is_equal_approx(Reforge.floor_ratio(-1.0), 0.0), "负数应按 0 处理")

# ---- 2) 档位折算：同档 1 / 高一档 2 / 低一档 0.5 / 低两档 0.25 / 12★ +1 ----

func _test_tier_conversion() -> void:
	var target := _make("c6_equip_necklace", 100, "legendary", 2401)
	check(not target.is_empty(), "目标实例应能生成")
	if target.is_empty():
		return
	var same := _make("c6_equip_weapon", 100, "legendary", 2402)
	var higher := _make("c6_equip_weapon", 110, "legendary", 2403)
	var low1 := _make("c6_equip_weapon", 90, "legendary", 2404)
	var low2 := _make("c6_equip_weapon", 80, "legendary", 2405)
	check(is_equal_approx(Reforge.refine_value(same, target), 1.0), "同档应折算 1 件")
	check(is_equal_approx(Reforge.refine_value(higher, target), 2.0), "高一档应折算 2 件")
	check(is_equal_approx(Reforge.refine_value(low1, target), 0.5), "低一档应折算 0.5 件")
	check(is_equal_approx(Reforge.refine_value(low2, target), 0.25), "低两档应折算 0.25 件")
	var maxed := same.duplicate(true)
	maxed["star"] = Upgrade.max_star()
	check(is_equal_approx(Reforge.refine_value(maxed, target), 2.0), "12★ 应额外 +1")
	var materials: Array = [same, same.duplicate(true), same.duplicate(true), same.duplicate(true)]
	check(is_equal_approx(Reforge.refine_count(materials, target), 4.0),
		"4 件同档应计入 4 有效件，实际 %.2f" % Reforge.refine_count(materials, target))

# ---- 3) 封顶：低档料凑再多样也最多 4 件 ----

func _test_cap() -> void:
	var target := _make("c6_equip_necklace", 100, "legendary", 2411)
	var low2 := _make("c6_equip_weapon", 80, "legendary", 2412)
	var materials: Array = []
	for i in range(20):
		materials.append(low2.duplicate(true))
	check(is_equal_approx(Reforge.refine_count(materials, target), 4.0),
		"20 件低两档应按 4 有效件封顶，实际 %.2f" % Reforge.refine_count(materials, target))

# ---- 4) 可投判定：非紫装 / 收藏 / 同实例 / 非装备一律拒绝 ----

func _test_can_refine_rejections() -> void:
	var target := _make("c6_equip_necklace", 100, "legendary", 2421)
	var epic := _make("c6_equip_weapon", 100, "epic", 2422)
	check(not bool(Reforge.can_refine(epic, target).get("ok", true)), "金装不应可作精炼材料")
	var favorite := _make("c6_equip_weapon", 100, "legendary", 2423)
	favorite["favorite"] = true
	check(not bool(Reforge.can_refine(favorite, target).get("ok", true)), "收藏件不应可作精炼材料")
	check(not bool(Reforge.can_refine(target, target).get("ok", true)), "目标自身不应可作材料")
	var potion := {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	check(not bool(Reforge.can_refine(potion, target).get("ok", true)), "非装备不应可作精炼材料")
	var valid := _make("c6_equip_weapon", 100, "legendary", 2424)
	check(bool(Reforge.can_refine(valid, target).get("ok", false)), "同档紫装应可作精炼材料")

# ---- 5) 下限真的落到数值上：ratio = 1.0 时区间压成一点 ----

func _test_floor_applied_to_bounds() -> void:
	var item := _make("c6_equip_necklace", 100, "legendary", 2431)
	check(not item.is_empty(), "待精炼实例应能生成")
	if item.is_empty():
		return
	var rolled := ItemFactory.reroll_affixes(item, _rng(2432), [], 1.0)
	check(bool(rolled.get("ok", false)), "精炼重掷应成功")
	if not bool(rolled.get("ok", false)):
		return
	var level := int(item.get("requiredLevel", 1))
	for e in rolled.affixes:
		if not e is Dictionary:
			continue
		var stat := String((e as Dictionary).get("stat", ""))
		var bounds := _fixed_bounds(stat, level)
		check(bounds.x >= 0, "固定词条 %s 应有区间" % stat)
		if bounds.x < 0:
			continue
		check(int((e as Dictionary).get("value", 0)) == bounds.y,
			"ratio=1.0 时 %s 应等于上界 %d，实际 %d" % [stat, bounds.y, int((e as Dictionary).get("value", 0))])
	var pct_cfg: Dictionary = ItemFactory.rules().get("percentAffixes", {})
	for e in rolled.pctAttrs:
		if not e is Dictionary:
			continue
		var stat := String((e as Dictionary).get("stat", ""))
		var bounds: Dictionary = pct_cfg.get(stat, {})
		check(is_equal_approx(float((e as Dictionary).get("value", 0.0)), float(bounds.get("max", 0.0))),
			"ratio=1.0 时百分比 %s 应等于上界" % stat)

# ---- 6) 锁定词条不吃精炼下限 ----

func _test_locked_entry_untouched() -> void:
	var item := _make("c6_equip_necklace", 100, "legendary", 2441)
	var locked_entry: Dictionary = item.affixes[0]
	var rolled := ItemFactory.reroll_affixes(item, _rng(2442),
		[String(locked_entry.get("stat", ""))], 1.0)
	check(bool(rolled.get("ok", false)), "带锁定的精炼重掷应成功")
	if not bool(rolled.get("ok", false)):
		return
	var found := false
	for e in rolled.affixes:
		if e is Dictionary and String((e as Dictionary).get("stat", "")) == String(locked_entry.get("stat", "")):
			found = true
			check(e == locked_entry, "锁定词条应原样保留（含数值），实际 %s" % str(e))
	check(found, "锁定词条应出现在结果里")

# ---- 7) 结算：材料与金币同批扣除，目标本体不变 ----

func _test_settlement_consumes_materials() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var target := _make("c6_equip_necklace", 100, "legendary", 2451)
	var m0 := _make("c6_equip_weapon", 100, "legendary", 2452)
	var m1 := _make("c6_equip_shoes", 100, "legendary", 2453)
	GameState.inventory[0] = target
	GameState.inventory[1] = m0
	GameState.inventory[2] = m1
	var before_gold := GameState.gold
	var result := GameState.reforge_equipment("bag", 0, String(target.get("instanceId", "")),
		_rng(2454), [], [String(m0.get("instanceId", "")), String(m1.get("instanceId", ""))])
	check(bool(result.get("ok", false)), "精炼重铸应成功：%s" % String(result.get("reason", "")))
	if not bool(result.get("ok", false)):
		return
	check(is_equal_approx(float(result.get("refined", 0.0)), 2.0),
		"2 件同档应为 2 有效件，实际 %.2f" % float(result.get("refined", 0.0)))
	check(GameState.gold == before_gold - int(result.get("cost", 0)), "金币应按重铸费实扣")
	check(GameState.inventory[1] == null and GameState.inventory[2] == null, "材料应被扣除")
	check(GameState.inventory[0] != null, "目标装备应仍在原格")
	var after: Dictionary = GameState.inventory[0]
	check(String(after.get("instanceId", "")) == String(target.get("instanceId", "")), "实例 id 不应变")
	check(String(after.get("quality", "")) == "legendary", "品质不应变")
	check(int(after.get("star", 0)) == int(target.get("star", 0)), "星级不应变")
	check(int(after.get("requiredLevel", 0)) == int(target.get("requiredLevel", 0)), "需求等级不应变")
	# 下限确实落在数值上（2 件 → 30% 分位）。
	var level := int(after.get("requiredLevel", 1))
	for e in after.affixes:
		if not e is Dictionary:
			continue
		var bounds := _fixed_bounds(String((e as Dictionary).get("stat", "")), level)
		if bounds.x < 0:
			continue
		var floor_value := bounds.x + int(round(float(bounds.y - bounds.x) * 0.30))
		check(int((e as Dictionary).get("value", 0)) >= floor_value,
			"词条 %s 应不低于 30%% 分位 %d，实际 %d" % [
				String((e as Dictionary).get("stat", "")), floor_value,
				int((e as Dictionary).get("value", 0))])

# ---- 8) 拒绝路径一件不扣 ----

func _test_settlement_rejects_without_consuming() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var target := _make("c6_equip_necklace", 100, "legendary", 2461)
	var epic := _make("c6_equip_weapon", 100, "epic", 2462)
	GameState.inventory[0] = target
	GameState.inventory[1] = epic
	var before_gold := GameState.gold
	var rejected := GameState.reforge_equipment("bag", 0, String(target.get("instanceId", "")),
		_rng(2463), [], [String(epic.get("instanceId", ""))])
	check(not bool(rejected.get("ok", true)), "金装作材料应被拒绝")
	check(GameState.gold == before_gold, "拒绝时金币不应扣")
	check(GameState.inventory[1] != null, "拒绝时材料不应扣")
	# 材料已不在背包：同样整单拒绝。
	var missing := GameState.reforge_equipment("bag", 0, String(target.get("instanceId", "")),
		_rng(2464), [], ["inst_missing"])
	check(not bool(missing.get("ok", true)), "不存在的材料应被拒绝")
	check(GameState.inventory[1] != null, "不存在的材料不应影响背包")

# ---- 9) UI：材料格可投放、提示下限、重铸后清空 ----

func _test_ui_material_slots() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var target := _make("c6_equip_necklace", 100, "legendary", 2471)
	var m0 := _make("c6_equip_weapon", 100, "legendary", 2472)
	var m1 := _make("c6_equip_shoes", 100, "legendary", 2473)
	GameState.inventory[0] = target
	GameState.inventory[1] = m0
	GameState.inventory[2] = m1
	var panel: Control = (load("res://scenes/ui/ReforgePanel.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.set_open(true)
	check(panel.refine_slots().size() == int(Reforge.REFINE_MAX_EFFECTIVE),
		"精炼格应为 4 个，实际 %d" % panel.refine_slots().size())
	panel.drop_refine_material(0, 1)
	panel.drop_refine_material(1, 2)
	check(panel.refine_materials().size() == 2, "应已放入 2 件材料")
	var hint := String(panel._refine_hint.text)
	check(hint.contains("30"), "2 件同档的下限应为 30%%，实际提示「%s」" % hint)
	panel._on_reforge()
	check(panel.refine_materials().is_empty(), "重铸后材料格应清空")
	check(GameState.inventory[1] == null and GameState.inventory[2] == null, "重铸后材料应被扣除")
	panel.set_open(false)
	panel.queue_free()
