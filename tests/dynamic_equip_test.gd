extends Node
## M10-1 动态等级装备契约（工程 41 §5 / §6）：
## 61+ 实例的生成数值、字段契约、存档校验按版本分流（v5 放开、v4 不动）。
## 核心底线：**v4 的严格等级校验一个字都不许松**——否则改档就能造「70 级新手剑」。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[DynamicEquipTest] " + label)

## 固定种子的随机数发生器（同一 seed 下词条抽取可复现）。
func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func _ready() -> void:
	_test_generate_values()
	_test_field_contract()
	_test_affix_counts()
	_test_affix_scale()
	_test_fallback_softcap()
	_test_foreign_template()
	_test_valid_item_v5()
	_test_valid_item_tampered()
	_test_save_roundtrip()
	_test_level_gate()
	_test_attr_sum()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[DynamicEquipTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[DynamicEquipTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

## §5 数值表：基底 = maxi(1, round(tier51基底 × S(level−60)))。
func _test_generate_values() -> void:
	var cases := [
		{"id": "c6_equip_weapon", "level": 61, "attr": "atk", "expect": 84},
		{"id": "c6_equip_armor", "level": 61, "attr": "def", "expect": 45},
		{"id": "c6_equip_armor", "level": 61, "attr": "hp", "expect": 123},
		{"id": "c6_equip_armor", "level": 63, "attr": "def", "expect": 54},
		{"id": "c6_equip_armor", "level": 63, "attr": "hp", "expect": 150},
		{"id": "c6_equip_shoes", "level": 61, "attr": "def", "expect": 20},
		{"id": "c6_equip_shoes", "level": 61, "attr": "mp", "expect": 49},
		{"id": "c6_equip_ring", "level": 61, "attr": "atk", "expect": 15},
		{"id": "c6_equip_ring", "level": 61, "attr": "mp", "expect": 39},
		{"id": "c6_equip_weapon", "level": 71, "attr": "atk", "expect": 174},
		{"id": "c6_equip_weapon", "level": 81, "attr": "atk", "expect": 277},
		{"id": "c6_equip_weapon", "level": 91, "attr": "atk", "expect": 414},
		{"id": "c6_equip_weapon", "level": 101, "attr": "atk", "expect": 583},
		{"id": "c6_equip_weapon", "level": 111, "attr": "atk", "expect": 785},
		{"id": "c6_equip_weapon", "level": 1000, "attr": "atk", "expect": 150630},
	]
	for row in cases:
		var item := ItemFactory.make_equip_dynamic(String(row.id), int(row.level), "common", _rng(1))
		check(not item.is_empty(), "%s @%d 应能生成" % [row.id, row.level])
		if item.is_empty():
			continue
		var raw: Dictionary = item.rawBaseAttrs
		var actual := int(raw.get(String(row.attr), -1))
		check(actual == int(row.expect),
			"%s @%d 的 %s 应为 %d，实际 %d" % [row.id, row.level, row.attr, row.expect, actual])

## 字段契约：版本 5、等级与模板脱钩、count 1、instanceId 前缀 dyn。
func _test_field_contract() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "rare", _rng(7))
	check(int(item.get("equipmentRuleVersion", 0)) == ItemFactory.RULE_VERSION_DYNAMIC,
		"v5 实例的规则版本应为 5，实际 %d" % int(item.get("equipmentRuleVersion", 0)))
	check(int(item.get("requiredLevel", 0)) == 61, "requiredLevel 应为 61，实际 %d" % int(item.get("requiredLevel", 0)))
	check(int(item.get("level", 0)) == 61, "level 应为 61，实际 %d" % int(item.get("level", 0)))
	check(int(item.get("count", 0)) == 1, "装备实例 count 恒为 1")
	check(String(item.get("instanceId", "")).begins_with("dyn_"), "instanceId 前缀应为 dyn_")
	var twin := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "rare", _rng(7))
	check(String(item.instanceId) != String(twin.instanceId), "两次生成的 instanceId 必须不同")

## 词条数量：rare 2 / epic 3 / legendary 4；percentage 至多 1 条。
func _test_affix_counts() -> void:
	var expected := {"rare": 2, "epic": 3, "legendary": 4}
	for quality in expected.keys():
		for seed_value in [1, 2, 3, 4, 5]:
			var item := ItemFactory.make_equip_dynamic("c6_equip_armor", 80, String(quality), _rng(seed_value))
			var total: int = (item.get("affixes", []) as Array).size() + (item.get("pctAttrs", []) as Array).size()
			check(total == int(expected[quality]),
				"%s 品质（seed %d）词条应 %d 条，实际 %d" % [quality, seed_value, expected[quality], total])
			check((item.get("pctAttrs", []) as Array).size() <= 1, "%s 品质百分比词条至多 1 条" % quality)

## 词条下界：61 级 uncommon 的词条值 = round(min × 6.0 × S(1))。
## 固定池最小值是 atk/def 的 2 ⇒ 下界 13；最大值是 hp 的 20 ⇒ 上界 134。
func _test_affix_scale() -> void:
	var lower := maxi(1, int(round(2.0 * 6.0 * Balance.scale(1))))
	var upper := maxi(1, int(round(20.0 * 6.0 * Balance.scale(1))))
	check(lower == 13, "61 级词条下界应为 13，实际 %d" % lower)
	for seed_value in [11, 12, 13, 14]:
		var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "uncommon", _rng(seed_value))
		var affixes: Array = item.get("affixes", [])
		check(affixes.size() == 1, "uncommon 应恰有 1 条固定词条")
		if affixes.is_empty():
			continue
		var value := int((affixes[0] as Dictionary).value)
		check(value >= lower and value <= upper,
			"61 级词条应落在 [%d, %d]，实际 %d" % [lower, upper, value])

## ≤ 60 回退：60 级拿到的仍是 tier51 原版（版本 4、reqLv 51、atk 75）。
func _test_fallback_softcap() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 60, "common", _rng(1))
	check(int(item.get("equipmentRuleVersion", 0)) == ItemFactory.RULE_VERSION_BASE,
		"60 级回退应为版本 4，实际 %d" % int(item.get("equipmentRuleVersion", 0)))
	check(int(item.get("requiredLevel", 0)) == 51, "60 级回退的 reqLv 应为模板值 51，实际 %d" % int(item.get("requiredLevel", 0)))
	check(int((item.get("rawBaseAttrs", {}) as Dictionary).get("atk", 0)) == 75,
		"60 级回退的 atk 应为 75")
	check(SaveManager._valid_item(item), "60 级回退实例必须通过存档校验（v4 路径）")

## 非循环型号：c5（tier41）传 70 级必须显式失败，不得生成「41 套的动态实例」。
func _test_foreign_template() -> void:
	var item := ItemFactory.make_equip_dynamic("c5_equip_weapon", 70, "common", _rng(1))
	check(item.is_empty(), "c5 型号不属于循环套，应返回空字典，实际生成了 %s" % String(item.get("itemId", "")))
	# 直接调 make_equip_roll 传动态等级 + 非 51 套也必须失败（防止绕过门面）。
	var rolled := ItemFactory.make_equip_roll("c5_equip_weapon", 41, "common", _rng(1), "inst", 70)
	check(rolled.is_empty(), "动态等级必须挂在第 51 套，混套应返回空字典")

## v5 实例应通过校验；v4 存量实例也应继续通过（未回退）。
func _test_valid_item_v5() -> void:
	for level in [61, 100, 1000, GameState.PLAYER_LEVEL_CAP]:
		var item := ItemFactory.make_equip_dynamic("c6_equip_shield", level, "epic", _rng(level))
		check(not item.is_empty(), "%d 级 v5 实例应能生成" % level)
		check(SaveManager._valid_item(item),
			"%d 级 v5 实例应通过校验（入口 ② 上限必须放进 5）" % level)

	var legacy := ItemFactory.make_equip("c6_equip_weapon")
	check(SaveManager._valid_item(legacy), "v4 存量实例必须仍通过校验")

## 手改四连：v5 等级 ≤ 60 / v5 等级字段不一致 / v4 抬等级 / v5 挂非循环套。
func _test_valid_item_tampered() -> void:
	var base := ItemFactory.make_equip_dynamic("c6_equip_weapon", 70, "common", _rng(1))
	check(SaveManager._valid_item(base), "对照实例应先合法")

	var low := base.duplicate(true)
	low["requiredLevel"] = 60
	low["level"] = 60
	check(not SaveManager._valid_item(low), "v5 但等级 60 必须拒（版本与等级耦合）")

	var mismatch := base.duplicate(true)
	mismatch["level"] = 71
	check(not SaveManager._valid_item(mismatch), "level 与 requiredLevel 不一致必须拒")

	var legacy_raised := ItemFactory.make_equip("c6_equip_weapon")
	legacy_raised["requiredLevel"] = 70
	legacy_raised["level"] = 70
	check(not SaveManager._valid_item(legacy_raised),
		"v4 但 reqLv 抬到 70 必须拒 —— v4 的严格等级校验不许被放宽")

	var foreign := ItemFactory.make_equip("c5_equip_weapon")
	foreign["equipmentRuleVersion"] = ItemFactory.RULE_VERSION_DYNAMIC
	foreign["requiredLevel"] = 70
	foreign["level"] = 70
	check(not SaveManager._valid_item(foreign), "v5 但挂在非 tier51 型号必须拒")

	var over_cap := base.duplicate(true)
	over_cap["requiredLevel"] = GameState.PLAYER_LEVEL_CAP + 1
	over_cap["level"] = GameState.PLAYER_LEVEL_CAP + 1
	check(not SaveManager._valid_item(over_cap), "v5 越过等级上界必须拒")

## 真文件往返：v5 实例写槽 3 再读回，不被剔除、数值不变。
func _test_save_roundtrip() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 1000
	GameState.player.attack = Balance.base_attack(1000)
	GameState.player.defense = Balance.base_defense(1000)
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 1000, "legendary", _rng(99))
	check(not item.is_empty(), "1000 级 v5 实例应能生成")
	GameState.inventory[0] = item
	check(SaveManager._is_valid_save(SaveManager._collect()),
		"含 v5 实例的存档应可读，拒绝原因：%s" % SaveManager._last_invalid_reason)
	check(SaveManager.save_slot(3, true), "含 v5 实例的存档应能写盘")
	var res: Dictionary = SaveManager.read_slot(3)
	check(bool(res.get("ok", false)), "含 v5 实例的存档应能读回：%s" % str(res.get("message", "")))
	var data: Dictionary = res.get("data", {})
	var inv: Array = data.get("inventory", [])
	var found: Dictionary = {}
	for slot in inv:
		if slot is Dictionary and String(slot.get("instanceId", "")) == String(item.instanceId):
			found = slot
			break
	check(not found.is_empty(), "读回后 v5 实例不应被剔除（P-1：入口 ② 放行）")
	if not found.is_empty():
		check(int(found.get("equipmentRuleVersion", 0)) == ItemFactory.RULE_VERSION_DYNAMIC,
			"读回后规则版本仍应为 5")
		check(int((found.get("rawBaseAttrs", {}) as Dictionary).get("atk", 0)) == 150630,
			"读回后 atk 应保持 150630，实际 %d" % int((found.get("rawBaseAttrs", {}) as Dictionary).get("atk", 0)))
		check(int(found.get("requiredLevel", 0)) == 1000, "读回后 requiredLevel 应为 1000")
	GameState.reset_to_defaults()

## 穿戴门槛只读实例 requiredLevel：L70 可穿 70 级武器，L69 不可。
func _test_level_gate() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 70, "common", _rng(1))
	check(Equipment.meets_level(item, 70), "L70 应可穿 70 级武器")
	check(not Equipment.meets_level(item, 69), "L69 不可穿 70 级武器")
	var slots := Equipment.create()
	var inv: Array = Inventory.create()
	inv[0] = item
	var result: Dictionary = Equipment.equip_from_inventory(slots, inv, "weapon", 0, 69)
	check(not bool(result.get("ok", true)), "L69 穿戴 70 级武器应被拒")
	result = Equipment.equip_from_inventory(slots, inv, "weapon", 0, 70)
	check(bool(result.get("ok", false)), "L70 穿戴 70 级武器应成功：%s" % String(result.get("reason", "")))

## 属性汇总：基底 atk × 品质倍率，加上词条里的固定 atk（都是 float 累加）。
func _test_attr_sum() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(3))
	var raw_atk := float((item.get("rawBaseAttrs", {}) as Dictionary).get("atk", 0))
	var affix_atk := 0.0
	for entry in item.get("affixes", []):
		if String((entry as Dictionary).get("stat", "")) == "atk":
			affix_atk += float((entry as Dictionary).get("value", 0.0))
	var expected := raw_atk * 1.9 + affix_atk  # epic baseMultiplier，star 0
	var slots := Equipment.create()
	slots["weapon"] = item
	var bonus: Dictionary = Equipment.bonus(slots)
	check(is_equal_approx(float(bonus.get("atk", 0.0)), expected),
		"汇总 atk 应为 %.1f（基底 %.0f × 1.9 + 词条 %.0f），实际 %.1f"
			% [expected, raw_atk, affix_atk, float(bonus.get("atk", 0.0))])
