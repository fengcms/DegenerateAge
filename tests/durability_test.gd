extends Node
## 工程 77 装备耐久度：损耗分档、失效卡口、套装保留、修理费与存档兼容。
## 工程 88 改失效语义：耐久归零**只砍词条**，基底（品质 × 星级）照常生效。
##
## 四组最值钱的断言：
## 1. **用例 6 是本需求的核心** —— 破损后 atk/def 必须**严格等于** `base_attrs()`、
##    且**严格小于**满耐久。两条缺一不可：只断「等于基底」时把 `attrs_for_use` 写成
##    恒返 `base_attrs` 也绿（词条根本没接上）；只断「小于满耐久」时把基底也砍光也绿。
## 2. **用例 14 是保险丝** —— 破损态必须仍在 `Combat.resolve` 的「不破防」侧。
##    基底留下后 def 仍高于怪物攻击，挨打走保底；一旦有人调高后期怪攻击或砍掉基底，
##    伤害从 60 跳到四位数，**是断崖不是渐变**，所以用「最凶的怪」+ 1.2 倍余量来卡。
## 3. **用例 2/3 钉死「绝不加必填」** —— 旧档无 durability 字段必须通过 _valid_item；
##    一旦有人加必填校验，旧档逐件剔除 = 静默毁档（D-21 教训）。
## 4. **用例 8 断修理费四点** —— 61 级后「全身 ≈ 一次重铸」是经济锚点，
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
	_test_broken_keeps_base()
	_test_set_bonus_survives()
	_test_repair_cost()
	_test_repair_transaction()
	_test_save_roundtrip()
	_test_tooltip()
	_test_durability_bar()
	_test_warning_throttle()
	_test_broken_keeps_unbroken_guard()
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

## 用例 6（本需求核心，工程 88）：归零 ⇒ **只砍词条**，基底（品质 × 星级）仍在。
## 词条固定写入已知值 —— 不依赖 rng 是否掷出 atk，否则「这条实例本来就没词条」时
## 「等于基底」与「词条没接上」两种状态区分不开（假绿）。
func _test_broken_keeps_base() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(600))
	item["affixes"] = [{"stat": "atk", "value": 500.0}, {"stat": "def", "value": 300.0}]
	item["pctAttrs"] = [{"stat": "hpPercent", "value": 0.10}]
	var base := EquipmentMath.base_attrs(item)
	var star := EquipmentMath.star_factor(item)
	var base_atk := float(base.get("atk", 0.0))
	var base_def := float(base.get("def", 0.0))
	var full_atk := base_atk + 500.0 * star
	var full_def := base_def + 300.0 * star
	var full_score := Equipment.score(item)
	check(base_atk > 0.0 and full_atk > base_atk, "构造前提：基底与词条都非零")
	item["durability"] = 0
	GameState.reset_to_defaults()
	GameState.equipment["weapon"] = item
	var bonus := GameState.equip_bonus()
	check(is_equal_approx(float(bonus.get("atk", 0.0)), base_atk),
		"破损件 atk 应等于基底 %.1f，实际 %.1f" % [base_atk, float(bonus.get("atk", 0.0))])
	check(is_equal_approx(float(bonus.get("def", 0.0)), base_def),
		"破损件 def 应等于基底 %.1f，实际 %.1f" % [base_def, float(bonus.get("def", 0.0))])
	check(float(bonus.get("atk", 0.0)) < full_atk,
		"破损件 atk 必须小于满耐久 %.1f（否则词条根本没失效）" % full_atk)
	check(float(bonus.get("def", 0.0)) < full_def, "破损件 def 必须小于满耐久 %.1f" % full_def)
	check(is_zero_approx(float(bonus.get("hpPercent", 0.0))),
		"破损件 hpPercent 词条应失效，实际 " + str(bonus.get("hpPercent")))
	var broken_score := Equipment.score(item)
	check(broken_score > 0.0, "破损件评分不应为 0（否则「属性更高」提示会谎报）")
	check(broken_score < full_score,
		"破损件评分应低于满耐久：%.1f vs %.1f" % [broken_score, full_score])
	# 修好后词条重新生效
	item["durability"] = Durability.max_durability()
	var bonus2 := GameState.equip_bonus()
	check(is_equal_approx(float(bonus2.get("atk", 0.0)), full_atk),
		"修好后 atk 应回到满耐久 %.1f，实际 %.1f" % [full_atk, float(bonus2.get("atk", 0.0))])
	check(is_equal_approx(Equipment.score(item), full_score), "修好后评分应回到满耐久")
	GameState.equipment["weapon"] = null

## 用例 7：归零 ⇒ 套装 pct 不变（`SetBonus` 数槽位、不数属性，天然成立但必须钉住）。
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
	## 🔴 文案必须**真的能格式化**：`ui.durability.warn_low` 原为「…不足 20%」，
	## 裸 `%` 遇 `tr_key(key, [name])` 会触发 `incomplete format`，
	## 玩家看到的是原样「「%s」耐久不足 20%」（既有 bug，本次随文案一并修）。
	## 断「等于预期正文」而不是「不含 %s」—— 前者连「改成 20%% 却漏了 %s」也抓得住。
	var low_text := Localization.tr_key("ui.durability.warn_low", ["测试件"])
	check(low_text == "「测试件」耐久不足 20%",
		"预警文案应完成占位填充，实际：" + low_text)
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

## 用例 14：破损态仍「不破防」（工程 88 R1 保险丝）。
##
## `Combat.resolve` 的破防判据是 `攻击 − 防御×0.5 ≤ 0`，不破防才走保底伤害
## （`maxHP × 0.25%`，上限 60）。基底留下后 def 仍在「攻击×2」之上 ⇒ 挨打伤害
## 与满耐久**完全一样**，变的只有血池。这条一旦破，伤害会从 60 直接跳到四位数。
##
## 🔴 用**最凶的那只金脉怪**（不是均值）作分母，并要求 **1.2 倍余量**：
##    只断「刚好不破防」时，攻击力上调 1% 就会红在别处、这条仍然绿。
## 🔴 两档等级都断（L96 / L174）：二次段 `scale()` 在 d>12 后加速，
##    只测一档无法发现「高等级段被拉开」。
func _test_broken_keeps_unbroken_guard() -> void:
	var cfg: Variant = DataLoader.get_table("endgame")
	var rows: Variant = (cfg as Dictionary).get("goldFieldNormals", []) if cfg is Dictionary else []
	var worst_norm := 0.0
	if rows is Array:
		for row in (rows as Array):
			if row is Dictionary:
				var n: Variant = (row as Dictionary).get("norm", {})
				if n is Dictionary:
					worst_norm = maxf(worst_norm, float((n as Dictionary).get("atk", 0.0)))
	check(worst_norm > 0.0, "金脉普通怪必须登记 norm.atk（否则本用例失去判据）")
	for level: int in [96, 174]:
		GameState.reset_to_defaults()
		GameState.player["level"] = level
		GameState.player["attack"] = Balance.base_attack(level)
		GameState.player["defense"] = Balance.base_defense(level)
		var rng := _rng(level)
		# 14 槽全传说 12★、全部归零：这是「后期玩家挂机到全身破损」的最坏合法状态。
		for definition in Equipment.SLOT_DEFS:
			var item := ItemFactory.make_equip_dynamic("c6_equip_" + String(definition.kind),
				level, "legendary", rng)
			check(not item.is_empty(), "L%d 生成 %s 失败" % [level, String(definition.kind)])
			item["star"] = 12
			item["durability"] = 0
			GameState.equipment[String(definition.id)] = item
		var def_broken := float(GameState.total_defense())
		var worst_atk := worst_norm * Balance.scale(level - Balance.SOFTCAP_LEVEL)
		var margin := def_broken * 0.5 / worst_atk
		check(margin >= 1.2,
			"L%d 破损态必须仍不破防且留 1.2 倍余量：def %.0f × 0.5 / 最凶怪 %.0f = %.2fx"
				% [level, def_broken, worst_atk, margin])
		# 血池还得撑过「一次挂机小节」：破损血池 ÷ 60 ≥ 600 击（≈15 分钟 @1.5s/击）。
		var hp_broken := float(GameState.max_hp())
		check(hp_broken / 60.0 >= 600.0,
			"L%d 破损血池 %.0f 撑不到 600 击保底伤害" % [level, hp_broken])
	GameState.reset_to_defaults()
