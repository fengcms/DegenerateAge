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
		and int(transfer.get("cost", 0)) == 128747, "51→61 同类型保星与金币和")
	var too_far := ItemFactory.make_equip_dynamic("c6_equip_weapon", 71, "legendary", rng)
	check(not bool(EquipmentFusion.plan_transfer(old, too_far).get("ok", false)), "51→71 跨两档拒绝")
	var other_kind := ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
	check(not bool(EquipmentFusion.plan_transfer(old, other_kind).get("ok", false)), "不同类型拒绝保星")
	var output := EquipmentFusion.make_output(61, "weapon", rng)
	check(not output.is_empty() and EquipmentFusion.tier_start(output) == 61
		and String(output.get("quality", "")) == "legendary" and SaveManager._valid_item(output),
		"动态紫装产物经工厂生成且存档有效")
	_test_random_materials()
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
