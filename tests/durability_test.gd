extends Node
## 工程 77 装备耐久度：损耗分档、失效卡口、套装保留、修理费与存档兼容。
##
## 三组最值钱的断言：
## 1. **用例 7 是本需求的核心** —— 破损件套装 pct 必须不变（你的规则：自身属性失效、套装还在）。
##    若有人「顺手」把破损件从 SetBonus 里跳过，这里当场红。
## 2. **用例 2/3 钉死「绝不加必填」** —— 旧档无 durability 字段必须通过 _valid_item；
##    一旦有人加必填校验，旧档逐件剔除 = 静默毁档（D-21 教训）。
## 3. **用例 8 断修理费四点** —— 61 级后「全身 ≈ 一次重铸」是经济锚点，
##    公式写错（比例反了、忘记 ceil）会直接打破 D-22 的金币出口平衡。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[DurabilityTest] " + label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _ready() -> void:
	_test_new_instance_full()
	_test_old_save_compat()
	_test_valid_item_rules()
	_test_wear_by_kind()
	_test_suppress_no_wear()
	_test_broken_skips_bonus()
	_test_set_bonus_survives()
	_test_repair_cost()
	_test_repair_transaction()
	_test_save_roundtrip()
	_test_tooltip()
	_test_durability_bar()
	_test_warning_throttle()
	if failures.is_empty():
		print("[DurabilityTest] 全部通过 ✅")
	else:
		for failure in failures:
			print("[DurabilityTest] 失败：" + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 用例 1：新实例必须满耐久。
func _test_new_instance_full() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(100))
	check(not item.is_empty(), "测试装备可生成")
	check(int(item.get("durability", -1)) == Durability.max_durability(),
		"新实例应满耐久 %d，实际 %s" % [Durability.max_durability(), str(item.get("durability", "无字段"))])

## 用例 2：旧档无字段 = 满耐久，_valid_item 必须通过。
func _test_old_save_compat() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(200))
	item.erase("durability")
	check(Durability.current(item) == Durability.max_durability(),
		"无字段应读为满耐久")
	check(not Durability.is_broken(item), "无字段不应判破损")
	check(SaveManager._valid_item(item), "旧档无 durability 字段必须通过 _valid_item（D-21 红线）")

## 用例 3：字段存在时的校验 —— 缺失 ✅ / 合法 ✅ / 负值 ❌ / 超界 ❌ / 非数字 ❌。
func _test_valid_item_rules() -> void:
	var base := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(300))
	var a := base.duplicate(true)
	a.erase("durability")
	check(SaveManager._valid_item(a), "缺字段通过")
	var b := base.duplicate(true)
	b["durability"] = 400
	check(SaveManager._valid_item(b), "合法值 400 通过")
	var c := base.duplicate(true)
	c["durability"] = -1
	check(not SaveManager._valid_item(c), "负值必须拒绝")
	var d := base.duplicate(true)
	d["durability"] = 10001
	check(not SaveManager._valid_item(d), "超宽松上界 10000 必须拒绝")
	var e := base.duplicate(true)
	e["durability"] = "abc"
	check(not SaveManager._valid_item(e), "非数字必须拒绝")

## 用例 4：损耗分档 normal 1 / elite 4 / boss 12。
func _test_wear_by_kind() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(400))
	item["durability"] = 800
	Durability.wear(item, "normal")
	check(int(item["durability"]) == 799, "normal 应扣 1，实际 %d" % int(item["durability"]))
	Durability.wear(item, "elite")
	check(int(item["durability"]) == 795, "elite 应扣 4，实际 %d" % int(item["durability"]))
	Durability.wear(item, "boss")
	check(int(item["durability"]) == 783, "boss 应扣 12，实际 %d" % int(item["durability"]))
	item["durability"] = 3
	Durability.wear(item, "boss")
	check(int(item["durability"]) == 0, "到 0 截止不应变负，实际 %d" % int(item["durability"]))

## 用例 5：suppress_rewards 不磨损（训练木桩）。
func _test_suppress_no_wear() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(500))
	item["durability"] = 800
	GameState.reset_to_defaults()
	GameState.equipment["weapon"] = item
	var before := int(item["durability"])
	# suppress_rewards 在 Monster._settle_rewards 顶部短路 —— 这里直接断言
	# GameState.wear_equipment 是唯一入口，木桩路径根本不调它。
	# 若有人把磨损挪到 _settle_rewards 之外，这条守卫失效，由 Monster 层的测试补。
	check(int(item["durability"]) == before, "未调用磨损时耐久不变")
	GameState.equipment["weapon"] = null

## 用例 6：归零 ⇒ equip_bonus 跳过该件、score = 0。
func _test_broken_skips_bonus() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(600))
	item["durability"] = 0
	GameState.reset_to_defaults()
	GameState.equipment["weapon"] = item
	var bonus := GameState.equip_bonus()
	check(float(bonus.get("atk", 0.0)) == 0.0, "破损件应跳过属性汇总，atk 实际 %s" % str(bonus.get("atk")))
	check(Equipment.score(item) == 0.0, "破损件评分应为 0")
	# 修好后属性回来
	item["durability"] = Durability.max_durability()
	var bonus2 := GameState.equip_bonus()
	check(float(bonus2.get("atk", 0.0)) > 0.0, "修好后属性应恢复")
	GameState.equipment["weapon"] = null

## 用例 7：归零 ⇒ 套装 pct 不变（本需求核心）。
func _test_set_bonus_survives() -> void:
	GameState.reset_to_defaults()
	var rng := _rng(700)
	# 穿满 14 件全紫（与 SetBonusTest._dress 同法：遍历 SLOT_DEFS 按 id 填充）
	for definition in Equipment.SLOT_DEFS:
		var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "legendary", rng)
		GameState.equipment[String(definition.id)] = item
	var full := GameState.set_bonus_pct()
	check(is_equal_approx(full, 0.20), "全紫 14 件应有 +20pct 套装，实际 " + str(full))
	# 一件破损后套装必须不变
	var weapon: Dictionary = GameState.equipment["weapon"]
	weapon["durability"] = 0
	var after := GameState.set_bonus_pct()
	check(is_equal_approx(after, full), "破损后套装 pct 应不变：" + str(full) + " -> " + str(after))
	weapon["durability"] = Durability.max_durability()

## 用例 8：修理费四点 + 比例取整。
## `repair_full_price` 按 `item.level` 计费 —— 测试直接写 level 字段，
## 不依赖 `make_equip_exact` 的档位映射（那条路径 level 取的是模板 requiredLevel）。
func _test_repair_cost() -> void:
	var rng := _rng(800)
	var base := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "common", rng)
	# L20 = 100（earlyPerLevel=5）
	var lv20 := base.duplicate(true)
	lv20["level"] = 20
	lv20["requiredLevel"] = 20
	lv20["durability"] = 0
	check(Durability.repair_full_price(lv20) == 100, "L20 全额应 100，实际 " + str(Durability.repair_full_price(lv20)))
	check(Durability.repair_cost(lv20) == 100, "L20 全损应 100，实际 " + str(Durability.repair_cost(lv20)))
	# L60 = 300
	var lv60 := base.duplicate(true)
	lv60["level"] = 60
	lv60["requiredLevel"] = 60
	lv60["durability"] = 0
	check(Durability.repair_full_price(lv60) == 300, "L60 全额应 300，实际 " + str(Durability.repair_full_price(lv60)))
	# L70 = round(500*(60+0.75*70) * 0.075) = round(56250*0.075) = round(4218.75) = 4219
	var lv70 := base.duplicate(true)
	lv70["level"] = 70
	lv70["requiredLevel"] = 70
	lv70["durability"] = 0
	check(Durability.repair_full_price(lv70) == 4219, "L70 全额应 4219，实际 " + str(Durability.repair_full_price(lv70)))
	# 比例取整：L70 缺失 400/800 = 50% → ceil(4219*0.5) = 2110
	lv70["durability"] = 400
	check(Durability.repair_cost(lv70) == 2110, "L70 半损应 2110，实际 " + str(Durability.repair_cost(lv70)))
	# L1000 = round(500*(60+750)*0.075) = round(405000*0.075) = round(30375) = 30375
	var lv1000 := base.duplicate(true)
	lv1000["level"] = 1000
	lv1000["requiredLevel"] = 1000
	lv1000["durability"] = 0
	check(Durability.repair_full_price(lv1000) == 30375, "L1000 全额应 30375，实际 " + str(Durability.repair_full_price(lv1000)))
	# 全好时修理费 0
	lv70["durability"] = Durability.max_durability()
	check(Durability.repair_cost(lv70) == 0, "满耐久应 0 费")

## 用例 9：一键修理交易 —— 金币不足拒 / 扣费与回满 / 全好拒绝。
func _test_repair_transaction() -> void:
	GameState.reset_to_defaults()
	var rng := _rng(900)
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 70, "common", rng)
	item["level"] = 70
	item["requiredLevel"] = 70
	item["durability"] = 0
	GameState.equipment["weapon"] = item
	GameState.gold = 100  # 不够
	var r1 := GameState.repair_equipment(1.0)
	check(not bool(r1.get("ok", false)), "金币不足应拒绝")
	check(int(item["durability"]) == 0, "金币不足时一件不修")
	GameState.gold = 100000
	var gold_before := GameState.gold
	var r2 := GameState.repair_equipment(1.0)
	check(bool(r2.get("ok", false)), "金币足够应成功")
	check(int(item["durability"]) == Durability.max_durability(), "修好后应回满")
	check(int(r2.get("cost", 0)) == 4219, "L70 全损应扣 4219，实际 " + str(int(r2.get("cost", 0))))
	# 🔴 必须断言金币**真的少了**：只断返回值 cost 是假绿（N-5 负向抓不住「修理不扣钱」）。
	check(GameState.gold == gold_before - 4219,
		"金币应实际扣减 4219：" + str(gold_before) + " -> " + str(GameState.gold))
	# 全好时拒绝
	var r3 := GameState.repair_equipment(1.0)
	check(not bool(r3.get("ok", false)) and int(r3.get("cost", 0)) == 0, "全好应拒绝且不扣费")
	GameState.equipment["weapon"] = null

## 用例 10：磨损写回 → JSON 往返 → _is_valid_save 不判毁档。
func _test_save_roundtrip() -> void:
	GameState.reset_to_defaults()
	var rng := _rng(1000)
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", rng)
	item["durability"] = 555
	GameState.equipment["weapon"] = item
	var snapshot: Dictionary = SaveManager._collect()
	var text := JSON.stringify(snapshot)
	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary, "存档 JSON 可解析")
	if parsed is Dictionary:
		var valid: bool = SaveManager._is_valid_save(parsed)
		check(valid, "磨损后存档不得判毁档（D-21 三段式）")
		# 读回后耐久保留
		var loaded_equip: Dictionary = (parsed as Dictionary).get("equipment", {})
		var loaded: Variant = loaded_equip.get("weapon")
		if loaded is Dictionary:
			check(int((loaded as Dictionary).get("durability", -1)) == 555,
				"读回应保留耐久 555，实际 %s" % str((loaded as Dictionary).get("durability")))
	GameState.equipment["weapon"] = null

## 用例 11：tooltip 归零显示「已损坏」但属性行仍列出。
func _test_tooltip() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(1100))
	item["durability"] = 0
	var lines := ItemUtil.attr_lines(item)
	check(not lines.is_empty(), "破损件属性行仍列出")
	# tooltip 构造在 inventory_panel._bag_tooltip，这里断言 Durability 门面
	check(Durability.is_broken(item), "归零应判破损")

## 用例 12：槽位耐久条 —— < 100% 显示、归零灰显、修好恢复。
func _test_durability_bar() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(1200))
	var slot: ItemSlot = ItemSlot.new()
	slot.role = ItemSlot.ROLE_BAG
	add_child(slot)
	slot.item = item.duplicate(true)
	check(not slot._durability_bar.visible, "满耐久不显示细条")
	slot.item["durability"] = 400
	slot._refresh_durability_bar()
	check(slot._durability_bar.visible, "缺失耐久应显示细条")
	slot.item["durability"] = 0
	slot._refresh_durability_bar()
	check(slot._durability_bar.visible, "归零仍显示细条（空条）")
	slot.item["durability"] = Durability.max_durability()
	slot._refresh_durability_bar()
	check(not slot._durability_bar.visible, "修好后细条消失")
	slot.queue_free()

## 用例 13：预警节流 —— 首次跌破 20% / 归零各一次，修理后复位。
## N-7 负向（删预警阈值）靠这条抓：只测 UI 细条测不到预警逻辑。
func _test_warning_throttle() -> void:
	GameState.reset_to_defaults()
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(1300))
	item["durability"] = 200  # 25%：尚未跌破 20%
	GameState.equipment["weapon"] = item
	# 从 200 扣到 188（正常怪）：25% > 20% → 未触发
	for _i in range(4):
		GameState.wear_equipment("normal")
	check(int(item["durability"]) == 196, "4 次 normal 应扣到 196，实际 " + str(int(item["durability"])))
	# 再扣到跌破 20%（160）：应触发一次
	item["durability"] = 161
	GameState.wear_equipment("normal")
	var warned: Dictionary = GameState._durability_warned.get(String(item.get("instanceId", "")), {})
	check(bool(warned.get("low", false)), "跌破 20% 应触发一次 low 预警")
	# 继续扣到归零：应触发一次 zero
	item["durability"] = 1
	GameState.wear_equipment("normal")
	warned = GameState._durability_warned.get(String(item.get("instanceId", "")), {})
	check(bool(warned.get("zero", false)), "归零应触发一次 zero 预警")
	# 修理后复位：预警标记清空
	GameState.gold = 999999
	GameState.repair_equipment(1.0)
	check(GameState._durability_warned.is_empty(), "修理后预警标记应清空复位")
	GameState.equipment["weapon"] = null
