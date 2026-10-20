extends Node
## 如意如意：四格选材排序、库存堆叠与现有扣料校验的隔离回归。

var failures: Array[String] = []

func _ready() -> void:
	var full := _inventory(4, 4, 4, 4)
	var before := full.duplicate(true)
	_check(Upgrade.auto_runes(100.0, full).ids == ["", "", "", ""], "基础 100% 不放如意")
	_check(Upgrade.auto_runes(90.0, full).ids == ["rune_iron", "rune_iron", "", ""],
		"90% 优先两枚铁如意而非一枚玉如意")
	_check(Upgrade.auto_runes(80.0, full).ids == ["rune_iron", "rune_iron", "rune_iron", "rune_iron"],
		"80% 优先四枚铁如意而非一枚钻石如意")
	_check(Upgrade.auto_runes(70.0, full).ids == ["rune_iron", "rune_iron", "rune_jade", "rune_jade"],
		"70% 少用高级如意且恰好凑满")
	_check(Upgrade.auto_runes(50.0, full).ids == ["rune_jade", "rune_jade", "rune_gold", "rune_gold"],
		"50% 用玉金组合，保留钻石如意")
	_check(Upgrade.auto_runes(20.0, full).ids == ["rune_diamond", "rune_diamond",
		"rune_diamond", "rune_diamond"], "20% 四钻凑满 100%")
	var hard := Upgrade.auto_runes(5.0, full)
	_check(hard.ids == ["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"]
		and is_equal_approx(float(hard.rate), 85.0) and not bool(hard.reached),
		"5% 无法凑满时选四枚最高如意，得到 85%")
	_check(full == before, "选材不修改背包")
	_check(Upgrade.auto_runes(70.0, full).ids == Upgrade.auto_runes(70.0, full).ids,
		"同一输入产生稳定结果")
	var split: Array = [
		{"kind": "rune", "itemId": "rune_iron", "count": 1},
		{"kind": "rune", "itemId": "rune_iron", "count": 1},
		{"kind": "rune", "itemId": "rune_jade", "count": 1},
		{"kind": "misc", "itemId": "rune_diamond", "count": 99},
		{"kind": "rune", "itemId": "rune_diamond", "count": 0},
	]
	var split_pick := Upgrade.auto_runes(90.0, split)
	_check(split_pick.ids == ["rune_iron", "rune_iron", "", ""]
		and bool(Upgrade.rune_plan(split, split_pick.ids).ok), "同类跨堆叠汇总且忽略非如意与零库存")
	var shortage := Upgrade.auto_runes(5.0, split)
	_check(shortage.ids == ["rune_jade", "rune_iron", "rune_iron", ""]
		and is_equal_approx(float(shortage.rate), 25.0), "凑不满时只取现有最高的三枚")
	_check(not Upgrade.has_usable_runes([]) and not bool(Upgrade.auto_runes(90.0, []).available)
		and Upgrade.has_usable_runes(split), "按钮库存状态只认有效正数如意")
	if failures.is_empty():
		print("[UpgradeAutoRuneTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _inventory(iron: int, jade: int, gold: int, diamond: int) -> Array:
	return [
		{"kind": "rune", "itemId": "rune_iron", "count": iron},
		{"kind": "rune", "itemId": "rune_jade", "count": jade},
		{"kind": "rune", "itemId": "rune_gold", "count": gold},
		{"kind": "rune", "itemId": "rune_diamond", "count": diamond},
	]

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
