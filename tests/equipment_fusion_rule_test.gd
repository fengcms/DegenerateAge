extends Node
## 铁匠三项新服务的十级档、品质、星级与动态实例规则回归。

var failures: Array[String] = []

## 用真实工厂实例覆盖混档、同档、保星与旧档／动态档输出。
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5719
	var lv51 := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "epic", rng)
	var lv61 := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", rng)
	var lv71 := ItemFactory.make_equip_dynamic("c6_equip_weapon", 71, "epic", rng)
	var lv83 := ItemFactory.make_equip_dynamic("c6_equip_armor", 81, "epic", rng)
	var gold: Array[Dictionary] = [lv51, lv61, lv71, lv83]
	check([lv51, lv61, lv71, lv83].all(func(it: Dictionary) -> bool: return not it.is_empty()), "四档测试装备均可生成")
	var plan := EquipmentFusion.plan_four(gold, EquipmentFusion.GOLD_TO_PURPLE)
	check(bool(plan.get("ok", false)) and int(plan.get("tier", 0)) == 51,
		"51、61、71、83 混档金装取 51 档")
	lv83.star = 9
	check(bool(EquipmentFusion.plan_four(gold, EquipmentFusion.GOLD_TO_PURPLE).get("ok", false)),
		"金装材料不限 0 星")
	var purple: Array[Dictionary] = []
	for _i in range(4):
		purple.append(ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng))
	check(bool(EquipmentFusion.plan_four(purple, EquipmentFusion.PURPLE_TARGET, "weapon").get("ok", false)),
		"同档四只紫戒指可指定紫武器")
	purple[0].star = 11
	check(bool(EquipmentFusion.plan_four(purple, EquipmentFusion.PURPLE_TARGET, "weapon").get("ok", false)),
		"11 星紫装仍可作为定向材料")
	purple[0].star = 12
	check(not bool(EquipmentFusion.plan_four(purple, EquipmentFusion.PURPLE_TARGET, "weapon").get("ok", false)),
		"12 星紫装不能作为定向材料")
	purple[0].star = 0
	purple[0] = ItemFactory.make_equip_dynamic("c6_equip_ring", 71, "legendary", rng)
	check(not bool(EquipmentFusion.plan_four(purple, EquipmentFusion.PURPLE_TARGET, "weapon").get("ok", false)),
		"跨档紫装不得指定合成")
	var old := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	old.star = 12
	var new_weapon := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "legendary", rng)
	var transfer := EquipmentFusion.plan_transfer(old, new_weapon)
	check(bool(transfer.get("ok", false)) and int(transfer.get("tier", 0)) == 61
		and int(transfer.get("cost", 0)) == 128747 and int(transfer.get("gap", 0)) == 1,
		"51→61 同类型保星与金币和")
	# 跨档：每多跨一档就多收一份基准价（100→110 是 x，100→130 是 3x）。
	var two_tier := ItemFactory.make_equip_dynamic("c6_equip_weapon", 71, "legendary", rng)
	var up_two := EquipmentFusion.plan_transfer(old, two_tier)
	check(bool(up_two.get("ok", false)) and int(up_two.get("tier", 0)) == 71
		and int(up_two.get("cost", 0)) == 257494 and int(up_two.get("gap", 0)) == 2,
		"51→71 跨两档允许且收 2 倍金币")
	var three_tier := ItemFactory.make_equip_dynamic("c6_equip_weapon", 81, "legendary", rng)
	var up_three := EquipmentFusion.plan_transfer(old, three_tier)
	check(bool(up_three.get("ok", false)) and int(up_three.get("tier", 0)) == 81
		and int(up_three.get("cost", 0)) == 386241 and int(up_three.get("gap", 0)) == 3,
		"51→81 跨三档收 3 倍金币")
	# 同档、降档、非整档都不构成跨档，必须仍然拒绝。
	var same_tier := ItemFactory.make_equip_dynamic("c6_equip_weapon", 51, "legendary", rng)
	check(EquipmentFusion.transfer_gap(51, 51) == 0
		and not bool(EquipmentFusion.plan_transfer(old, same_tier).get("ok", false)),
		"同档不算跨档，仍然拒绝保星")
	var lower_old := two_tier.duplicate(true)
	lower_old.star = 12
	check(EquipmentFusion.transfer_gap(71, 61) == 0
		and not bool(EquipmentFusion.plan_transfer(lower_old, new_weapon).get("ok", false)),
		"降档不算跨档，仍然拒绝保星")
	check(EquipmentFusion.transfer_gap(51, 65) == 0 and EquipmentFusion.transfer_gap(0, 61) == 0,
		"档差非十级整数倍或旧档无效时不算跨档")
	# 上限前置：真正的失败点在 make_output，规则层必须先把话说清楚。
	var beyond := ItemFactory.make_equip_dynamic("c6_equip_weapon", 991, "legendary", rng)
	beyond.requiredLevel = 9991
	check(EquipmentFusion.transfer_max_tier() == 9990
		and not bool(EquipmentFusion.plan_transfer(old, beyond).get("ok", false)),
		"目标档超过实例等级上限时拒绝保星")
	check(EquipmentFusion.make_output(9991, "weapon", rng).is_empty(),
		"超过上限的档位产物确实无法生成，规则层必须前置拦截")
	var other_kind := ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
	check(not bool(EquipmentFusion.plan_transfer(old, other_kind).get("ok", false)), "不同类型拒绝保星")
	var output := EquipmentFusion.make_output(61, "weapon", rng)
	check(not output.is_empty() and EquipmentFusion.tier_start(output) == 61
		and String(output.get("quality", "")) == "legendary" and SaveManager._valid_item(output),
		"动态紫装产物经工厂生成且存档有效")
	_test_random_materials()
	_test_purple_up_tier()
	if failures.is_empty():
		print("[EquipmentFusionRuleTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 累计断言失败并在测试末尾统一打印。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

## 验证随机预选不混档、不重选、只取 0 星未收藏件，且不改变原背包。
func _test_random_materials() -> void:
	var factory_rng := RandomNumberGenerator.new()
	factory_rng.seed = 8024
	var bag: Array = []
	for tier in [51, 61]:
		for _i in range(5):
			bag.append(ItemFactory.make_equip_dynamic("c6_equip_weapon", tier, "epic", factory_rng))
	bag[0].star = 4
	bag[5].favorite = true
	var before := bag.duplicate(true)
	var pick_rng := RandomNumberGenerator.new()
	pick_rng.seed = 42
	var chosen := EquipmentFusion.random_materials(bag, EquipmentFusion.GOLD_TO_PURPLE, pick_rng)
	var ids := {}
	var valid := chosen.size() == 4
	for item in chosen:
		ids[String(item.instanceId)] = true
		valid = valid and EquipmentFusion.tier_start(item) == EquipmentFusion.tier_start(chosen[0]) \
			and int(item.get("star", -1)) == 0 and not bool(item.get("favorite", false))
	check(valid and ids.size() == 4 and bag == before,
		"随机四金只预选同档四件不同的 0 星未收藏装备")
	pick_rng.seed = 42
	var again := EquipmentFusion.random_materials(bag, EquipmentFusion.GOLD_TO_PURPLE, pick_rng)
	check(chosen == again, "相同种子可复现随机预选")
	for i in range(1, 5):
		bag[i].star = 2
	check(EquipmentFusion.random_materials(bag, EquipmentFusion.GOLD_TO_PURPLE, pick_rng).size() == 4,
		"一档不足四件时仍可从另一档预选")
	for i in range(6, 10):
		bag[i].star = 2
	check(EquipmentFusion.random_materials(bag, EquipmentFusion.GOLD_TO_PURPLE, pick_rng).is_empty(),
		"没有四件同档 0 星装备时不产生预选")
	check(EquipmentFusion.random_materials(bag, EquipmentFusion.STAR_TRANSFER, pick_rng).is_empty(),
		"保星升级不提供随机放入")

## 四紫升紫只认同档紫装，下一档随机部位；顶档、12 星和混档在预览前拒绝。
func _test_purple_up_tier() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6842
	var items: Array[Dictionary] = []
	for _i in range(4):
		items.append(ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng))
	var plan := EquipmentFusion.plan_four(items, EquipmentFusion.PURPLE_UP_TIER)
	check(bool(plan.get("ok", false)) and int(plan.get("tier", 0)) == 71
		and String(plan.get("target_kind", "x")).is_empty(), "同档四紫升到下一档且不指定部位")
	items[0].star = 11
	check(bool(EquipmentFusion.plan_four(items, EquipmentFusion.PURPLE_UP_TIER).get("ok", false)),
		"11 星紫装可手动投入")
	items[0].star = 12
	check(not bool(EquipmentFusion.plan_four(items, EquipmentFusion.PURPLE_UP_TIER).get("ok", false)),
		"12 星紫装不能用于升档")
	items[0] = ItemFactory.make_equip_dynamic("c6_equip_ring", 71, "legendary", rng)
	check(not bool(EquipmentFusion.plan_four(items, EquipmentFusion.PURPLE_UP_TIER).get("ok", false)),
		"混档紫装不能升档")
	items[0] = ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "epic", rng)
	check(not bool(EquipmentFusion.plan_four(items, EquipmentFusion.PURPLE_UP_TIER).get("ok", false)),
		"金装不能用于四紫升档")
	items.clear()
	for _i in range(4):
		items.append(ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng))
	check(int(EquipmentFusion.plan_four(items, EquipmentFusion.PURPLE_UP_TIER).get("tier", 0)) == 61,
		"51 档紫装升到首个动态档 61")
	var bag: Array = items.duplicate(true)
	bag[0].star = 3
	for _i in range(4):
		bag.append(ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng))
	var before := bag.duplicate(true)
	# 51 档 3 件、61 档 4 件，两档都合格 —— 任何一次调用都必须给 51 档。
	# 单次调用抓不住「等概率抽档」（它可能恰好抽中最低档），所以扫 32 个种子：
	# 等概率实现在 32 次里次次都抽中 51 档的概率是 2⁻³²，实际必然被抓。
	var lowest_only := true
	for candidate in range(32):
		var pick := RandomNumberGenerator.new()
		pick.seed = 1000 + candidate
		var picked := EquipmentFusion.random_materials(bag, EquipmentFusion.PURPLE_UP_TIER, pick)
		if picked.size() != 3:
			lowest_only = false
			continue
		for item in picked:
			if int(item.get("star", -1)) != 0 or EquipmentFusion.tier_start(item) != 51:
				lowest_only = false
	check(lowest_only and bag == before,
		"随机放入 32 次采样都只取最低合格档 3 件，从不去动 61 档那 4 件")
	# 最低档凑不满 2 件时跳到下一档；旧实现是「不够四件的档直接不算」，会漏掉 2—3 件的档。
	bag[1].star = 3
	bag[2].star = 3
	var fallback := EquipmentFusion.random_materials(bag, EquipmentFusion.PURPLE_UP_TIER, rng)
	check(fallback.size() == 4 and fallback.all(func(item: Dictionary) -> bool:
		return EquipmentFusion.tier_start(item) == 61 and int(item.get("star", -1)) == 0),
		"最低档只剩 1 件时跳到下一档并取满四件")
	items.clear()
	for _i in range(4):
		items.append(ItemFactory.make_equip_dynamic("c6_equip_weapon", 9981, "legendary", rng))
	check(not bool(EquipmentFusion.plan_four(items, EquipmentFusion.PURPLE_UP_TIER).get("ok", false))
		and EquipmentFusion.random_materials(items, EquipmentFusion.PURPLE_UP_TIER, rng).is_empty(),
		"最高可用档不再继续升档，随机放入也不选不可合成档")
	# ---- 工程 75：件数换成功率，期望材料消耗恒为 4 件 ----
	check(EquipmentFusion.material_range(EquipmentFusion.PURPLE_UP_TIER) == Vector2i(2, 4)
		and EquipmentFusion.material_range(EquipmentFusion.GOLD_TO_PURPLE) == Vector2i(4, 4)
		and EquipmentFusion.material_range(EquipmentFusion.PURPLE_TARGET) == Vector2i(4, 4)
		and EquipmentFusion.material_range(EquipmentFusion.STAR_TRANSFER) == Vector2i(2, 2),
		"只有四紫升紫允许 2—4 件，其余服务件数固定")
	check(is_equal_approx(EquipmentFusion.success_rate(4), 1.0)
		and is_equal_approx(EquipmentFusion.success_rate(3), 0.75)
		and is_equal_approx(EquipmentFusion.success_rate(2), 0.5)
		and is_equal_approx(EquipmentFusion.success_rate(1), 0.25)
		and is_equal_approx(EquipmentFusion.success_rate(0), 0.0)
		and is_equal_approx(EquipmentFusion.success_rate(9), 1.0),
		"成功率按件数线性且越界被夹取")
	var expectation_ok := true
	for count in [2, 3, 4]:
		if not is_equal_approx(float(count) / EquipmentFusion.success_rate(count), 4.0):
			expectation_ok = false
	check(expectation_ok, "2 / 3 / 4 件的期望材料消耗都等于 4 件（不是打折，只是方差不同）")
	var two: Array[Dictionary] = []
	var three: Array[Dictionary] = []
	for i in range(4):
		var fresh := ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
		if i < 2:
			two.append(fresh)
		if i < 3:
			three.append(fresh)
	var plan_two := EquipmentFusion.plan_four(two, EquipmentFusion.PURPLE_UP_TIER)
	var plan_three := EquipmentFusion.plan_four(three, EquipmentFusion.PURPLE_UP_TIER)
	check(bool(plan_two.get("ok", false)) and is_equal_approx(float(plan_two.get("rate", 0.0)), 0.5)
		and int(plan_two.get("tier", 0)) == 71,
		"两件同档紫装可升档，成功率 50%")
	check(bool(plan_three.get("ok", false)) and is_equal_approx(float(plan_three.get("rate", 0.0)), 0.75)
		and int(plan_three.get("tier", 0)) == 71,
		"三件同档紫装可升档，成功率 75%")
	var mixed := three.duplicate()
	mixed.append(ItemFactory.make_equip_dynamic("c6_equip_ring", 71, "legendary", rng))
	check(not bool(EquipmentFusion.plan_four(mixed, EquipmentFusion.PURPLE_UP_TIER).get("ok", false)),
		"件数放宽后仍然禁止跨档混用")
	var single: Array[Dictionary] = [ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)]
	check(not bool(EquipmentFusion.plan_four(single, EquipmentFusion.PURPLE_UP_TIER).get("ok", false)),
		"一件紫装不能合成")
	check(not bool(EquipmentFusion.plan_four(two, EquipmentFusion.GOLD_TO_PURPLE).get("ok", false))
		and not bool(EquipmentFusion.plan_four(two, EquipmentFusion.PURPLE_TARGET, "weapon").get("ok", false)),
		"四金与四紫定向仍然必须四件")
