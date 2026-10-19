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
	_test_tier_normalize()
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
## 🔴 本表刻意走 `make_equip_exact`：它锁的是**公式本身**（等级 → 基底），
## 与「十级一套」归一无关。门面的归一由 `_test_tier_normalize` 单独守，
## 两件事混在一张表里，改归一就会连带改这张表，回归原因就说不清了。
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
		var item := ItemFactory.make_equip_exact(String(row.id), int(row.level), "common", _rng(1))
		check(not item.is_empty(), "%s @%d 应能生成" % [row.id, row.level])
		if item.is_empty():
			continue
		var raw: Dictionary = item.rawBaseAttrs
		var actual := int(raw.get(String(row.attr), -1))
		check(actual == int(row.expect),
			"%s @%d 的 %s 应为 %d，实际 %d" % [row.id, row.level, row.attr, row.expect, actual])

## D-21「十级一套」：门面必须把来源等级归一到「套起点 + 槽位偏移」。
## 三条判据缺一不可：
## ① 十个型号各自落在 61—70 这**一整段**内（武器 61、鞋 62 … 项链 70）；
## ② 同一套内任意两级的产物**逐字段相同**（套内不成长）；
## ③ 换套整体 +10（71—80），且数值按槽位等级缩放（不是按来源等级）。
## 旧行为（直接用来源等级）在 ① 必然红：L67 的项链会是 67 而不是 70。
func _test_tier_normalize() -> void:
	var expected := {
		"c6_equip_weapon": 61, "c6_equip_shoes": 62, "c6_equip_armor": 63,
		"c6_equip_helmet": 64, "c6_equip_bracer": 65, "c6_equip_knee": 66,
		"c6_equip_shield": 67, "c6_equip_bracelet": 68, "c6_equip_ring": 69,
		"c6_equip_necklace": 70,
	}
	check(ItemFactory.TIER_SPAN == 10, "十级一套的跨度必须是 10，实际 %d" % ItemFactory.TIER_SPAN)
	for item_id in expected.keys():
		var want := int(expected[item_id])
		check(ItemFactory.slot_offset_for_template(String(item_id)) == want - 61,
			"%s 的槽位偏移应为 %d（reqLv − 51），实际 %d"
				% [item_id, want - 61, ItemFactory.slot_offset_for_template(String(item_id))])
		# 套内每一级都应该落回同一个槽位等级（61—70 整段不分级）。
		for level in [61, 63, 67, 70]:
			var item := ItemFactory.make_equip_dynamic(String(item_id), level, "common", _rng(level))
			check(not item.is_empty(), "%s @%d 应能生成" % [item_id, level])
			if item.is_empty():
				continue
			check(int(item.get("requiredLevel", 0)) == want,
				"%s @L%d 的 requiredLevel 应为 %d，实际 %d（直接用来源等级即逐级装备）"
					% [item_id, level, want, int(item.get("requiredLevel", 0))])
			check(ItemFactory.dynamic_level_for(String(item_id), level) == want,
				"%s @L%d 的归一等级应为 %d" % [item_id, level, want])
		# 换套：同型号 +10，数值随之放大（武器 61→84 / 71→174）。
		var next_tier := ItemFactory.make_equip_dynamic(String(item_id), 71, "common", _rng(71))
		check(int(next_tier.get("requiredLevel", 0)) == want + 10,
			"%s 在 L71 的 requiredLevel 应为 %d，实际 %d"
				% [item_id, want + 10, int(next_tier.get("requiredLevel", 0))])
	# 套内逐字段相同：L61 与 L70 生成的同型号装备，基底必须一模一样。
	var low := ItemFactory.make_equip_dynamic("c6_equip_armor", 61, "common", _rng(5))
	var high := ItemFactory.make_equip_dynamic("c6_equip_armor", 70, "common", _rng(5))
	check(low.get("rawBaseAttrs") == high.get("rawBaseAttrs"),
		"套内（L61 与 L70）同型号基底必须相同（套内不成长），实际 %s vs %s"
			% [str(low.get("rawBaseAttrs")), str(high.get("rawBaseAttrs"))])
	# 归一后的基底按**槽位等级**缩放：L61 的甲 = 63 级 = def 54 / hp 150。
	var armor := ItemFactory.make_equip_dynamic("c6_equip_armor", 61, "common", _rng(1))
	var armor_raw: Dictionary = armor.get("rawBaseAttrs", {})
	check(int(armor_raw.get("def", 0)) == 54 and int(armor_raw.get("hp", 0)) == 150,
		"L61 的铠甲应按 63 级缩放到 def 54 / hp 150，实际 %s" % str(armor_raw))
	# 末档保护：9999 级玩家的项链不能造出 10000 级实例（`_valid_item` 会拒 ⇒ 毁档）。
	for item_id in expected.keys():
		var top := ItemFactory.dynamic_level_for(String(item_id), GameState.PLAYER_LEVEL_CAP)
		check(top <= GameState.PLAYER_LEVEL_CAP,
			"%s 在等级上限处的穿戴等级应 ≤ %d，实际 %d"
				% [item_id, GameState.PLAYER_LEVEL_CAP, top])
	check(ItemFactory.INSTANCE_LEVEL_CAP == GameState.PLAYER_LEVEL_CAP,
		"ItemFactory 的实例上限必须与 GameState.PLAYER_LEVEL_CAP 同步（%d vs %d）"
			% [ItemFactory.INSTANCE_LEVEL_CAP, GameState.PLAYER_LEVEL_CAP])

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
## 🔴 还要盖住 **D-21 之前的逐级实例**（本机存档里真实存在 102/104/106/117/118 级）：
## 它们不落在十级档上，但必须**继续合法**。任何人给 `_valid_item` 加「必须是十级档」的校验，
## 这些实例会在读档时被逐件剔除 —— 那是静默毁档，这条断言是唯一防线（R-1）。
func _test_valid_item_v5() -> void:
	for level in [61, 100, 1000, GameState.PLAYER_LEVEL_CAP]:
		var item := ItemFactory.make_equip_dynamic("c6_equip_shield", level, "epic", _rng(level))
		check(not item.is_empty(), "%d 级 v5 实例应能生成" % level)
		check(SaveManager._valid_item(item),
			"%d 级 v5 实例应通过校验（入口 ② 上限必须放进 5）" % level)

	for level in [102, 104, 106, 117, 118]:
		var legacy_dyn := ItemFactory.make_equip_exact("c6_equip_weapon", level, "rare", _rng(level))
		check(not legacy_dyn.is_empty(), "旧档逐级实例（%d 级）应能重建" % level)
		check(SaveManager._valid_item(legacy_dyn),
			"旧档逐级实例（%d 级）必须继续通过校验 —— 加「十级档」校验就是毁档" % level)

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
	# D-21：1000 级属于 991—1000 这一套，武器的槽位偏移是 0 ⇒ 实例等级 991。
	check(int(item.get("requiredLevel", 0)) == 991, "1000 级武器的实例等级应为 991，实际 %d" % int(item.get("requiredLevel", 0)))
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
		check(int((found.get("rawBaseAttrs", {}) as Dictionary).get("atk", 0)) == 147807,
			"读回后 atk 应保持 147807，实际 %d" % int((found.get("rawBaseAttrs", {}) as Dictionary).get("atk", 0)))
		check(int(found.get("requiredLevel", 0)) == 991, "读回后 requiredLevel 应为 991")
	GameState.reset_to_defaults()

## 穿戴门槛只读实例 requiredLevel：L71 可穿 71 级武器，L70 不可。
## D-21 后还要守「同套内的鞋比武器晚一级」——L61 掉落的鞋是 62 级，当时穿不上，
## 这与前 60 级完全一致（L51 也掉 52 级鞋），不是缺陷。
func _test_level_gate() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 71, "common", _rng(1))
	check(int(item.get("requiredLevel", 0)) == 71, "L71 的武器应为 71 级，实际 %d" % int(item.get("requiredLevel", 0)))
	check(Equipment.meets_level(item, 71), "L71 应可穿 71 级武器")
	check(not Equipment.meets_level(item, 70), "L70 不可穿 71 级武器")
	# 70 级属于 61—70 那一套：武器仍是 61 级（套内不成长）。
	var in_suit := ItemFactory.make_equip_dynamic("c6_equip_weapon", 70, "common", _rng(1))
	check(int(in_suit.get("requiredLevel", 0)) == 61, "L70 的武器应为 61 级（61—70 套），实际 %d" % int(in_suit.get("requiredLevel", 0)))
	var shoes := ItemFactory.make_equip_dynamic("c6_equip_shoes", 61, "common", _rng(1))
	check(int(shoes.get("requiredLevel", 0)) == 62, "L61 掉的鞋应为 62 级，实际 %d" % int(shoes.get("requiredLevel", 0)))
	check(not Equipment.meets_level(shoes, 61), "L61 不可穿 62 级鞋（与前 60 级同规矩）")
	check(Equipment.meets_level(shoes, 62), "L62 可穿 62 级鞋")
	var slots := Equipment.create()
	var inv: Array = Inventory.create()
	inv[0] = item
	var result: Dictionary = Equipment.equip_from_inventory(slots, inv, "weapon", 0, 70)
	check(not bool(result.get("ok", true)), "L70 穿戴 71 级武器应被拒")
	result = Equipment.equip_from_inventory(slots, inv, "weapon", 0, 71)
	check(bool(result.get("ok", false)), "L71 穿戴 71 级武器应成功：%s" % String(result.get("reason", "")))

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
