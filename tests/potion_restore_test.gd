extends Node
## M10-10 药水百分比续航（工程 51 §4.6）：10 组用例。
##
## 三条最值钱的断言：
## 1. **用例 2 是本批的唯一硬约束** —— 「1–60 逐位不变」**不能**靠「L60 的 `maxHp × pct` ≤ 固定值」
##    来保证：产品验算用的 2390 只是 `common` 品质满装的数，实测 L60 穿 `rare` 满装
##    `maxHp = 5051` ⇒ 20% = **1010**。必须靠 `level <= 60` 硬切，**与装备品质无关**。
##    这条同时是方案 A（纯公式）的失败判据。
## 2. **用例 8 盯的是 `pick_index` 用实际量还是模板固定值** —— 用固定值时高等级永远选大药，
##    Q1「够用的最小档」策略静默失效，而且任何「只断言选中了某一格」的弱写法都发现不了
##    （必须让两种口径选出**不同**的那一格）。
## 3. **用例 6/7 是 M2.5 的回归** —— 满值不浪费 / 超量按缺口截断，本轮一行没改，但改的是同一个函数。

## 装备 kind → 槽位 id（十部位，护腕 / 护膝 / 手镯 / 戒指各两格）。
const SLOT_MAP := {
	"weapon": ["weapon"], "shield": ["shield"], "helmet": ["helmet"],
	"armor": ["armor"], "shoes": ["shoes"], "necklace": ["necklace"],
	"bracer": ["bracer_1", "bracer_2"], "knee": ["knee_1", "knee_2"],
	"bracelet": ["bracelet_1", "bracelet_2"], "ring": ["ring_1", "ring_2"],
}

## 三档药水的固定恢复量（与 potions.json 一致；用例 1/3/9 的基准）。
const FIXED_SMALL := 80
const FIXED_MID := 220
const FIXED_LARGE := 500

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PotionRestoreTest] " + label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

## 取药水模板（不存在返回空字典，让断言给出可读的失败文案）。
func _tpl(id: String) -> Dictionary:
	var v: Variant = DataLoader.get_entry("potions", id)
	if v is Dictionary:
		return v as Dictionary
	check(false, "药水模板 %s 不存在" % id)
	return {}

func _ready() -> void:
	_test_pure_formula()
	_test_guard_ignores_quality()
	_test_three_tiers_scale()
	_test_real_gear_end_to_end()
	_test_use_restores_percent()
	_test_full_value_no_waste()
	_test_gap_truncation()
	_test_pick_index_uses_effective()
	_test_blue_potion()
	_test_missing_field_falls_back()
	GameState.reset_to_defaults()
	Consumable.reset()
	if failures.is_empty():
		print("[PotionRestoreTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[PotionRestoreTest] 失败 %d 项 ❌" % failures.size())
		get_tree().quit(1)

# ---- 1) 纯函数五档精确值（不依赖装备模板，最稳的一条）----

func _test_pure_formula() -> void:
	var large := _tpl("potion_hp_large")
	# (cap, level, 期望)：L60 守护 → 500；61 的 524.4 → 524；100 的 2967.8 → 2968；
	# 1000 的 748735.4 → 748735。整条链在验「round 而非 floor」。
	var cases := [
		[2390, 60, 500], [2622, 61, 524], [14839, 100, 2968],
		[3743677, 1000, 748735], [5000, 1000, 1000],
		# 61 级以上「百分比 < 固定值」的采样点：2000×0.2 = 400 < 500 ⇒ 必须取固定值。
		# 少了这一条，「删掉 maxi(fixed, …)」的注入不会变红（08 §7 第 20 号坑）。
		[2000, 61, 500],
	]
	for c in cases:
		var cap := int(c[0])
		var level := int(c[1])
		var want := int(c[2])
		var got := Consumable.restore_of(large, cap, level)
		check(got == want, "cap=%d lv=%d 大红应为 %d，实际 %d" % [cap, level, want, got])

# ---- 2) L≤60 与装备品质无关（方案 B 的核心；方案 A 必红）----

func _test_guard_ignores_quality() -> void:
	var tpls := [_tpl("potion_hp_small"), _tpl("potion_hp_mid"), _tpl("potion_hp_large")]
	var fixed := [FIXED_SMALL, FIXED_MID, FIXED_LARGE]
	# 这四个 cap 分别是「空装 / common / rare / epic 满装」的 L60 真实 maxHp。
	# 若守护失效，rare(5051) 的大红会变成 1010、epic(6033) 变成 1207。
	for cap in [1046, 2390, 5051, 6033]:
		for i in range(3):
			var got := Consumable.restore_of(tpls[i], cap, 60)
			check(got == fixed[i],
				"L60 cap=%d 第 %d 档应恒为 %d（与品质无关），实际 %d" % [cap, i + 1, fixed[i], got])
	# 反向锚点：同一 cap 用 61 级必须**不再**等于固定值（证明守护真的在起作用）
	var rare_cap := 5051
	check(Consumable.restore_of(tpls[2], rare_cap, 61) == 1010,
		"L61 cap=5051 大红应为 1010，实际 %d" % Consumable.restore_of(tpls[2], rare_cap, 61))
	check(Consumable.restore_of(tpls[2], rare_cap, 61) != FIXED_LARGE,
		"L61 起必须脱离固定值（守护改成恒真即红）")

# ---- 3) 三档比例（3% / 9% / 20%）----

func _test_three_tiers_scale() -> void:
	var cap := 3743677
	var level := 1000
	var small := Consumable.restore_of(_tpl("potion_hp_small"), cap, level)
	var mid := Consumable.restore_of(_tpl("potion_hp_mid"), cap, level)
	var large := Consumable.restore_of(_tpl("potion_hp_large"), cap, level)
	check(small == 112310, "L1000 小红应回 112,310，实际 %d" % small)
	check(mid == 336931, "L1000 中红应回 336,931，实际 %d" % mid)
	check(large == 748735, "L1000 大红应回 748,735，实际 %d" % large)
	check(small < mid and mid < large, "三档必须严格递增：%d / %d / %d" % [small, mid, large])
	# 比例本身：模板里就是 0.03 / 0.09 / 0.20
	var checks := [["potion_hp_small", 0.03], ["potion_hp_mid", 0.09], ["potion_hp_large", 0.2]]
	for row in checks:
		var t := _tpl(String(row[0]))
		var pct := float(t.get("restorePercent", 0.0))
		check(is_equal_approx(pct, float(row[1])),
			"%s 的 restorePercent 应为 %.2f，实际 %.4f" % [String(row[0]), float(row[1]), pct])

# ---- 4) 真实装备端到端（穿满 common 套，用真实 max_hp）----

func _dynamic_ids() -> Array:
	var out: Array = []
	var rows: Variant = DataLoader.get_table("equipments")
	if rows is Array:
		for row in rows:
			if not row is Dictionary:
				continue
			var bases: Variant = (row as Dictionary).get("tierBases", {})
			if bases is Dictionary and (bases as Dictionary).size() == 1 and (bases as Dictionary).has("51"):
				out.append(String((row as Dictionary).get("id", "")))
	return out

func _dress(level: int, quality: String) -> void:
	GameState.equipment = {}
	var seed := 1000 + level
	for id in _dynamic_ids():
		var tpl: Variant = DataLoader.get_entry("equipments", id)
		if not tpl is Dictionary:
			continue
		var slots: Array = SLOT_MAP.get(String((tpl as Dictionary).get("slot", "")), [])
		if slots.is_empty():
			continue
		var item: Dictionary
		if level <= 60:
			item = ItemFactory.make_equip_roll(id, 51, quality, _rng(seed))
		else:
			item = ItemFactory.make_equip_dynamic(id, level, quality, _rng(seed))
		for slot_id in slots:
			GameState.equipment[slot_id] = item

func _setup(level: int, quality: String = "common") -> void:
	GameState.reset_to_defaults()
	Consumable.reset()
	GameState.player.level = level
	GameState.player.attack = Balance.base_attack(level)
	GameState.player.defense = Balance.base_defense(level)
	_dress(level, quality)
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()

func _test_real_gear_end_to_end() -> void:
	var large := _tpl("potion_hp_large")
	# L60：三档都必须等于固定值（这是产品验收原文）
	_setup(60)
	var cap60 := GameState.max_hp()
	check(cap60 > 2000 and cap60 < 3000, "L60 common 满装 maxHp 应在 2,000–3,000，实际 %d" % cap60)
	check(Consumable.restore_of(large, cap60, 60) == FIXED_LARGE,
		"L60 大红应恒为 %d，实际 %d" % [FIXED_LARGE, Consumable.restore_of(large, cap60, 60)])
	# L61：真的按比例（此时 maxHp 已跨过 500 / 0.2 = 2500）
	_setup(61)
	var cap61 := GameState.max_hp()
	check(Consumable.restore_of(large, cap61, 61) > FIXED_LARGE,
		"L61 大红应大于 %d，实际 %d（cap=%d）" % [FIXED_LARGE, Consumable.restore_of(large, cap61, 61), cap61])
	# L1000：≈ 20%（容差 ±1 来自 round）
	_setup(1000)
	var cap1000 := GameState.max_hp()
	var got := Consumable.restore_of(large, cap1000, 1000)
	check(absi(got - int(round(float(cap1000) * 0.2))) <= 1,
		"L1000 大红应 ≈ maxHp×20%%（%d），实际 %d" % [int(round(float(cap1000) * 0.2)), got])
	# 同一件药水在 60 级的实际量必须 ≥ L60 maxHp 的 20%（否则「药水失效」没修好）
	_setup(60)
	var pct60 := float(Consumable.restore_of(large, GameState.max_hp(), 60)) / float(GameState.max_hp())
	check(pct60 >= 0.2, "L60 大红应至少回 20%% maxHp，实际 %.1f%%" % (pct60 * 100.0))

# ---- 5) use() 真的按比例回血（不是只改了 tooltip）----

func _test_use_restores_percent() -> void:
	_setup(1000)
	var cap := GameState.max_hp()
	var expect := Consumable.restore_of(_tpl("potion_hp_large"), cap, 1000)
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_large", "count": 1}
	GameState.player.hp = 0
	var res := Consumable.use(0)
	check(bool(res.get("ok", false)), "L1000 喝大红应成功，实际 %s" % String(res.get("reason", "")))
	check(int(res.get("restored", 0)) == expect,
		"L1000 实际恢复应为 %d，实际 %d" % [expect, int(res.get("restored", 0))])
	check(int(GameState.player.hp) == expect, "L1000 喝完后 hp 应为 %d，实际 %d" % [expect, int(GameState.player.hp)])
	check(GameState.inventory[0] == null or int((GameState.inventory[0] as Dictionary).get("count", 0)) == 0,
		"单瓶应被消耗掉")

# ---- 6) 满值不浪费（M2.5 回归）----

func _test_full_value_no_waste() -> void:
	_setup(60)
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_large", "count": 3}
	GameState.player.hp = GameState.max_hp()
	var res := Consumable.use(0)
	check(not bool(res.get("ok", false)), "满血时喝药应失败")
	check(int((GameState.inventory[0] as Dictionary).get("count", 0)) == 3, "满血时不得扣药")
	check(Consumable.cd_of("potion_hp_large") == 0.0, "满血时不得进冷却")

# ---- 7) 超量按缺口截断（M2.5 回归）----

func _test_gap_truncation() -> void:
	_setup(1000)
	var cap := GameState.max_hp()
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_large", "count": 2}
	GameState.player.hp = cap - 100
	var res := Consumable.use(0)
	check(bool(res.get("ok", false)), "缺 100 时喝大红应成功")
	check(int(res.get("restored", 0)) == 100,
		"超量应截断到缺口 100，实际 %d" % int(res.get("restored", 0)))
	check(int(GameState.player.hp) == cap, "喝完后应满血")
	check(int((GameState.inventory[0] as Dictionary).get("count", 0)) == 1,
		"截断后仍应消耗一瓶（否则是无限药）")

# ---- 8) pick_index 用实际量（用固定值必选错档）----

func _test_pick_index_uses_effective() -> void:
	_setup(1000)
	var cap := GameState.max_hp()
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 5}
	GameState.inventory[1] = {"kind": "potion", "itemId": "potion_hp_mid", "count": 5}
	GameState.inventory[2] = {"kind": "potion", "itemId": "potion_hp_large", "count": 5}
	# 缺口 200,000：实际量下「够用的最小档」是中药（336,931 ≥ 200,000）；
	# 若仍用模板固定值（80/220/500），三档都不够 ⇒ 退化为「取最大」= 大药（下标 2）。
	GameState.player.hp = cap - 200000
	var idx := Consumable.pick_index(Consumable.KIND_RED)
	check(idx == 1, "缺口 200,000 应选中红药（下标 1），实际 %d" % idx)
	# 缺口极小（500）时仍应选最小的那档
	GameState.player.hp = cap - 500
	var idx2 := Consumable.pick_index(Consumable.KIND_RED)
	check(idx2 == 0, "缺口 500 应选小红药（下标 0），实际 %d" % idx2)
	# 缺口大到三档都不够时，退回取最大
	GameState.player.hp = 0
	var idx3 := Consumable.pick_index(Consumable.KIND_RED)
	check(idx3 == 2, "缺口极大时应选大红药（下标 2），实际 %d" % idx3)

# ---- 9) 蓝药同规则 ----

func _test_blue_potion() -> void:
	var large := _tpl("potion_mp_large")
	_setup(60)
	var mp60 := GameState.max_mp()
	check(Consumable.restore_of(large, mp60, 60) == FIXED_LARGE,
		"L60 大蓝应恒为 %d，实际 %d（maxMp=%d）" % [FIXED_LARGE, Consumable.restore_of(large, mp60, 60), mp60])
	_setup(1000)
	var mp1000 := GameState.max_mp()
	var expect := int(round(float(mp1000) * 0.2))
	var got := Consumable.restore_of(large, mp1000, 1000)
	check(absi(got - expect) <= 1, "L1000 大蓝应 ≈ maxMp×20%%（%d），实际 %d" % [expect, got])
	check(got > FIXED_LARGE, "L1000 大蓝应远大于固定值，实际 %d" % got)

# ---- 10) restorePercent 缺省 / 脏值一律退回固定值 ----

func _test_missing_field_falls_back() -> void:
	var no_pct := {"restoreAmount": 500}
	var zero_pct := {"restoreAmount": 500, "restorePercent": 0.0}
	var ok_pct := {"restoreAmount": 500, "restorePercent": 0.2}
	check(Consumable.restore_of(no_pct, 10000, 1000) == 500,
		"缺 restorePercent 应退回固定值 500，实际 %d" % Consumable.restore_of(no_pct, 10000, 1000))
	check(Consumable.restore_of(zero_pct, 10000, 1000) == 500,
		"restorePercent=0 应退回固定值，实际 %d" % Consumable.restore_of(zero_pct, 10000, 1000))
	check(Consumable.restore_of(ok_pct, 10000, 1000) == 2000,
		"restorePercent=0.2 且 cap=10000 应为 2000，实际 %d" % Consumable.restore_of(ok_pct, 10000, 1000))
	# cap <= 0 是脏状态（未初始化），也不能把固定值抹成 0
	check(Consumable.restore_of(ok_pct, 0, 1000) == 500,
		"cap=0 时应退回固定值，实际 %d" % Consumable.restore_of(ok_pct, 0, 1000))
