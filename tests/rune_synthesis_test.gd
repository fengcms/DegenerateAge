extends Node
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func store(iron: int, jade: int, gold: int, diamond: int) -> Array:
	var out: Array = []
	out.resize(40)
	for pair in [["rune_iron", iron], ["rune_jade", jade], ["rune_gold", gold], ["rune_diamond", diamond]]:
		if pair[1] > 0:
			check(Inventory.add(out, ItemFactory.make_any(pair[0], pair[1])), "测试材料入库")
	return out

func _ready() -> void:
	check(DataLoader.validate_all().is_empty(), "正式配置校验")
	for row in [[0, 0, 0, false], [3, 0, 0, false], [4, 0, 0, true], [5, 0, 0, true], [0, 3, 0, false], [0, 4, 0, true], [0, 0, 39, false], [0, 0, 40, true], [0, 0, 41, true]]:
		var source := store(row[0], row[1], row[2], 0)
		var snapshot := source.duplicate(true)
		var result := RuneSynthesis.plan(source)
		check(result.ok == row[3], "材料阈值 " + str(row))
		check(source == snapshot, "计划不修改原容器")
	var chain := RuneSynthesis.plan(store(640, 0, 0, 0))
	check(chain.ok and RuneCharge.inventory_counts(chain.store).get("rune_diamond") == 1 and Inventory.used_slots(chain.store) == 1, "640 铁贯通至一钻石")
	var mixed := RuneSynthesis.plan(store(19, 3, 39, 2))
	check(mixed.ok and RuneCharge.inventory_counts(mixed.store) == {"rune_iron": 3, "rune_jade": 3, "rune_diamond": 3}, "混合余数与已有钻石")
	var full: Array = [ItemFactory.make_any("rune_iron", 5)]
	check(not RuneSynthesis.plan(full).ok and full[0].count == 5, "满仓余数占格整笔失败")
	full = [ItemFactory.make_any("rune_iron", 4)]
	check(RuneSynthesis.plan(full).ok, "满仓释放格位成功")
	full = [ItemFactory.make_any("rune_iron", 5), ItemFactory.make_any("rune_jade", 1)]
	check(RuneSynthesis.plan(full).ok, "满仓合堆成功")
	check(ItemUtil.stack_max(ItemFactory.make_any("rune_diamond")) == 999 and ItemUtil.stack_max(ItemFactory.make_any("rune_gold")) == 99, "仅钻石提升到999")
	var packed: Array = [null, null]
	check(Inventory.add(packed, ItemFactory.make_any("rune_diamond", 1000)) and packed[0].count == 999 and packed[1].count == 1, "钻石跨堆叠999边界")
	var overflow := RuneSynthesis.plan([ItemFactory.make_any("rune_gold", 80), ItemFactory.make_any("rune_diamond", 998)])
	check(overflow.ok and overflow.store[0].count == 1 and overflow.store[1].count == 999, "产物超过999拆堆")
	var bad := Warehouse.config().duplicate(true)
	bad.runeSynthesis[0].sourceCount = 0
	check(not RuneSynthesis.validate_config(bad).is_empty(), "拒绝零比例")
	bad = Warehouse.config().duplicate(true)
	bad.runeSynthesis[0].targetId = "rune_iron"
	check(not RuneSynthesis.validate_config(bad).is_empty(), "拒绝自环配方")
	if failures.is_empty():
		print("[RuneSynthesisTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)
