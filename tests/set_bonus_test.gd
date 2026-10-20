extends Node
## 工程 66 套装加成：品质档 + 星级档，独立判定后**相加**。
##
## 三组最值钱的断言：
## 1. **用例 1 是 `PaceTest` 的守护** —— 全 common ⇒ 0%。`PaceTest._dress()` 全程穿 common，
##    一旦有人给白装加哪怕 1%，三条护栏（≤1.30 / 锯齿 ±2% / 可挨打 ≥5.5）会同时变红。
##    这条把「为什么不能动白装」写成了可执行的约束。
## 2. **用例 10 是 `max_hp()` 不二次放大的证据** —— 若 `max_hp` 内部误用 `total_attack()`，
##    血条会从 ×1.4 变成 ×1.96。只断「面板攻击变 1.4 倍」抓不到这个，必须断血条。
## 3. **用例 8 断的是加法** —— 全紫 12 星 = 0.40；乘法会得 0.44，差 4 个百分点。
##
## 判定基数锁定 14 槽：遍历 `Equipment.SLOT_DEFS` 而不是 `slots.keys()`，
## 用例外加一条「脏档多键不改变结果」来证明这一点。

## 部位 → 槽位（与 `Equipment.SLOT_DEFS` 同源，十部位十四槽）。
const SLOT_MAP := {
	"weapon": ["weapon"], "shield": ["shield"], "helmet": ["helmet"],
	"armor": ["armor"], "shoes": ["shoes"], "necklace": ["necklace"],
	"bracer": ["bracer_1", "bracer_2"], "knee": ["knee_1", "knee_2"],
	"bracelet": ["bracelet_1", "bracelet_2"], "ring": ["ring_1", "ring_2"],
}

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[SetBonusTest] " + label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _ready() -> void:
	_test_common_is_zero()
	_test_quality_tiers()
	_test_lowest_quality_wins()
	_test_empty_slot_breaks_set()
	_test_star_tiers()
	_test_lowest_star_wins()
	_test_additive_not_multiplicative()
	_test_next_tier_need()
	_test_dirty_extra_keys()
	_test_hp_scaled_once()
	_test_hp_clamped_after_set_break()
	_test_inverse_attr()
	_test_speed_follows_equipment()
	_test_panel_text()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[SetBonusTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[SetBonusTest] 失败 %d 项 ❌" % failures.size())
		get_tree().quit(1)

# ---- 夹具 ----

## `tierBases` 只有 "51" 一档的十个循环套型号（与 PaceTest 同源）。
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

## 给 14 槽穿满同品质、同星级的循环套。level 60 ⇒ 走静态基底 51 档。
func _dress(quality: String, star: int) -> void:
	GameState.equipment = {}
	var seed := 66066
	for id in _dynamic_ids():
		var tpl: Variant = DataLoader.get_entry("equipments", String(id))
		if not tpl is Dictionary:
			continue
		var slots: Array = SLOT_MAP.get(String((tpl as Dictionary).get("slot", "")), [])
		if slots.is_empty():
			continue
		var item := ItemFactory.make_equip_dynamic(String(id), 60, quality, _rng(seed))
		if item.is_empty():
			continue
		item["star"] = star
		for slot_id in slots:
			GameState.equipment[slot_id] = item

func _setup(level: int) -> void:
	GameState.reset_to_defaults()
	GameState.player.level = level
	GameState.player.attack = Balance.base_attack(level)
	GameState.player.defense = Balance.base_defense(level)

# ---- 1) 白装恒 0：PaceTest 的守护 ----

func _test_common_is_zero() -> void:
	_setup(60)
	_dress("common", 0)
	var info := GameState.set_bonus()
	check(bool(info.get("full", false)), "全 common 也算成套（14 槽穿满）")
	check(is_zero_approx(float(info.get("pct", -1.0))), "全 common 0 星加成必须为 0（PaceTest 基线）")
	check(is_zero_approx(GameState.set_bonus_pct()), "set_bonus_pct() 与 evaluate() 同源")

# ---- 2) 品质四档 ----

func _test_quality_tiers() -> void:
	for entry in [["uncommon", 0.02], ["rare", 0.05], ["epic", 0.10], ["legendary", 0.20]]:
		_setup(60)
		_dress(String(entry[0]), 0)
		var got := GameState.set_bonus_pct()
		check(is_equal_approx(got, float(entry[1])),
			"全 %s 0★ 应 +%.0f%%，实际 %.3f" % [String(entry[0]), float(entry[1]) * 100.0, got])
		check(is_zero_approx(float(GameState.set_bonus().get("star_pct", -1.0))),
			"%s 0★ 的星级档应为 0" % String(entry[0]))

# ---- 3) 最低品质决定档位 ----

func _test_lowest_quality_wins() -> void:
	_setup(60)
	_dress("legendary", 0)
	# 只把戒指②降成 uncommon，其余 13 件仍是传说 ⇒ 档位掉到 2%。
	var poor := ItemFactory.make_equip_dynamic("c6_equip_ring", 60, "uncommon", _rng(99))
	poor["star"] = 0
	GameState.equipment["ring_2"] = poor
	var info := GameState.set_bonus()
	check(is_equal_approx(float(info.get("pct", -1.0)), 0.02),
		"13 紫 + 1 蓝应按最低品质算 2%%，实际 %.3f" % float(info.get("pct", -1.0)))
	check(String(info.get("quality", "")) == "uncommon", "最低品质必须是 uncommon")

# ---- 4) 空槽即不成套 ----

func _test_empty_slot_breaks_set() -> void:
	_setup(60)
	_dress("legendary", 12)
	GameState.equipment["ring_2"] = null
	var info := GameState.set_bonus()
	check(not bool(info.get("full", false)), "空 1 槽不得算成套")
	check(is_zero_approx(float(info.get("pct", -1.0))), "不成套时加成为 0")
	check(int(info.get("missing", 0)) == 1, "missing 应为 1，实际 %d" % int(info.get("missing", -1)))
	check(int(info.get("worn", 0)) == 13, "worn 应为 13，实际 %d" % int(info.get("worn", -1)))

# ---- 5) 星级四档 ----

func _test_star_tiers() -> void:
	for entry in [[6, 0.03], [8, 0.05], [10, 0.10], [12, 0.20]]:
		_setup(60)
		_dress("common", int(entry[0]))
		var info := GameState.set_bonus()
		check(is_equal_approx(float(info.get("star_pct", -1.0)), float(entry[1])),
			"全 +%d 星应 +%.0f%%，实际 %.3f" % [int(entry[0]), float(entry[1]) * 100.0,
			float(info.get("star_pct", -1.0))])
		check(int(info.get("star", 0)) == int(entry[0]),
			"star 档位应为 %d，实际 %d" % [int(entry[0]), int(info.get("star", 0))])
	# 5 星不足门槛
	_setup(60)
	_dress("common", 5)
	check(is_zero_approx(GameState.set_bonus_pct()), "全 +5 星不得触发任何星级档")

# ---- 6) 最低星级决定档位 ----

func _test_lowest_star_wins() -> void:
	_setup(60)
	_dress("common", 12)
	GameState.equipment["knee_2"]["star"] = 6
	var info := GameState.set_bonus()
	check(is_equal_approx(float(info.get("star_pct", -1.0)), 0.03),
		"13 件 12★ + 1 件 6★ 只算 3%%，实际 %.3f" % float(info.get("star_pct", -1.0)))
	GameState.equipment["knee_2"]["star"] = 8
	check(is_equal_approx(float(GameState.set_bonus().get("star_pct", -1.0)), 0.05),
		"最低升到 8★ 后应 5%")

# ---- 7) 加法而非乘法（40% 的锚点）----

func _test_additive_not_multiplicative() -> void:
	_setup(60)
	_dress("legendary", 12)
	var info := GameState.set_bonus()
	check(is_equal_approx(float(info.get("quality_pct", -1.0)), 0.20), "全紫品质档 = 20%")
	check(is_equal_approx(float(info.get("star_pct", -1.0)), 0.20), "全 12 星星级档 = 20%")
	check(is_equal_approx(float(info.get("pct", -1.0)), 0.40),
		"全紫全 12 星必须恰好 40%%（乘法会得 44%%），实际 %.3f" % float(info.get("pct", -1.0)))
	# 全紫全 6 星：20 + 3 = 23%（乘法会是 20.6%）
	_setup(60)
	_dress("legendary", 6)
	check(is_equal_approx(GameState.set_bonus_pct(), 0.23),
		"全紫 6★ 应 23%%，实际 %.3f" % GameState.set_bonus_pct())

# ---- 8) 「距下一档还差几件」 ----

func _test_next_tier_need() -> void:
	_setup(60)
	_dress("rare", 6)
	var info := GameState.set_bonus()
	check(String(info.get("next_quality", "")) == "epic", "稀有档的下一档应是史诗")
	check(int(info.get("next_quality_need", -1)) == 14,
		"全稀有要凑史诗需 14 件，实际 %d" % int(info.get("next_quality_need", -1)))
	check(int(info.get("next_star", 0)) == 8, "6★ 的下一档应是 8★")
	check(int(info.get("next_star_need", -1)) == 14,
		"全 6★ 要凑 8★ 需 14 件，实际 %d" % int(info.get("next_star_need", -1)))
	# 混搭后只差 2 件
	var better := ItemFactory.make_equip_dynamic("c6_equip_ring", 60, "epic", _rng(7))
	better["star"] = 8
	GameState.equipment["ring_1"] = better
	GameState.equipment["ring_2"] = better
	var mixed := GameState.set_bonus()
	check(int(mixed.get("next_quality_need", -1)) == 12,
		"2 件升到史诗后还差 12 件，实际 %d" % int(mixed.get("next_quality_need", -1)))
	# 顶档时 next 为空 / 已满标记
	_setup(60)
	_dress("legendary", 12)
	var top := GameState.set_bonus()
	check(String(top.get("next_quality", "")) == "" and bool(top.get("quality_maxed", false)),
		"全紫时品质档应标记已满")
	check(bool(top.get("star_maxed", false)), "全 12 星时星级档应标记已满")

# ---- 9) 脏档多出非标准键：遍历 SLOT_DEFS 的证明 ----

func _test_dirty_extra_keys() -> void:
	_setup(60)
	_dress("legendary", 12)
	var before := GameState.set_bonus_pct()
	# 脏档里混进一个**白装**非标准键：只看 `slots.keys()` 会把它算进最低品质 ⇒ 加成清零。
	# 这是「必须遍历 SLOT_DEFS」的真正判据（混个传奇进去是测不出来的）。
	GameState.equipment["ghost_slot"] = {"itemId": "c6_equip_ring", "quality": "common", "star": 0}
	check(is_equal_approx(GameState.set_bonus_pct(), before),
		"脏档里多一个白装非标准槽位不得拉低加成（遍历 keys 会把 min 拉成 common）")
	GameState.equipment.erase("ghost_slot")
	# 反过来：把标准槽删掉（不是置 null）也必须算空槽
	var backup: Variant = GameState.equipment.get("ring_2")
	GameState.equipment.erase("ring_2")
	check(not bool(GameState.set_bonus().get("full", false)),
		"标准槽整个缺失必须按空槽处理")
	GameState.equipment["ring_2"] = backup

# ---- 10) max_hp 只放大一次（不是 1.96 倍）----

func _test_hp_scaled_once() -> void:
	for entry in [["common", 12], ["legendary", 12]]:
		_setup(60)
		_dress(String(entry[0]), int(entry[1]))
		var pct := GameState.set_bonus_pct()
		check(pct > 0.0, "%s 12★ 必须有加成" % String(entry[0]))
		var bonus := GameState.equip_bonus()
		# 复现「不含套装」的原始 HP 公式，套装只在最外层乘一次
		var raw := (GameState.BASE_HP + 60.0 * GameState.HP_PER_LV
			+ float(GameState._base_attack()) * GameState.HP_PER_ATK
			+ float(GameState._base_defense()) * GameState.HP_PER_DEF) \
			* (1.0 + float(bonus.get("hpPercent", 0.0))) + float(bonus.get("hp", 0.0))
		var want := int(round(raw * (1.0 + pct)))
		check(GameState.max_hp() == want,
			"%s 12★ 的 max_hp 应 = 原式 × %.2f = %d，实际 %d" % [String(entry[0]), 1.0 + pct, want, GameState.max_hp()])
		# 二次放大（1.4 × 1.4）必须被这条挡住
		var doubled := int(round(raw * (1.0 + pct) * (1.0 + pct)))
		check(GameState.max_hp() < doubled,
			"%s 12★ 的 max_hp 不得二次放大（×%.2f² = %d）" % [String(entry[0]), 1.0 + pct, doubled])
	# total_attack 本身仍是 1.4 倍
	_setup(60)
	_dress("legendary", 12)
	var pct2 := GameState.set_bonus_pct()
	var want_atk := int(round(float(GameState._base_attack()) * (1.0 + pct2)))
	check(GameState.total_attack() == want_atk,
		"total_attack 应 = 基础 × %.2f = %d，实际 %d" % [1.0 + pct2, want_atk, GameState.total_attack()])

# ---- 11) 套装失效后 HP 收敛到新上限 ----

func _test_hp_clamped_after_set_break() -> void:
	_setup(60)
	_dress("legendary", 12)
	GameState.player.hp = GameState.max_hp()
	var peak := GameState.max_hp()
	check(GameState.player.hp == peak and peak > 0, "先满血")
	GameState.equipment["ring_2"] = null
	GameState._after_equip_change()
	check(not bool(GameState.set_bonus().get("full", false)), "卸一件后不再成套")
	check(GameState.max_hp() < peak, "套装失效后上限必须下降")
	check(int(GameState.player.hp) <= GameState.max_hp(),
		"当前 HP 必须收敛到新上限，实际 %d > %d" % [int(GameState.player.hp), GameState.max_hp()])

# ---- 12) 反向属性：攻击间隔用除法 ----

func _test_inverse_attr() -> void:
	_setup(60)
	_dress("legendary", 12)
	var pct := GameState.set_bonus_pct()
	var base_interval := float(GameState.player.get("attackInterval", 0.8))
	var want := base_interval / (1.0 + pct)
	check(is_equal_approx(GameState.total_attack_interval(), want),
		"攻击间隔应 ÷%.2f = %.4f，实际 %.4f" % [1.0 + pct, want, GameState.total_attack_interval()])
	check(GameState.total_attack_interval() < base_interval, "攻击间隔必须变短（乘 1.4 是负收益）")
	# 正向属性
	check(GameState.total_move_speed() > 4.0, "移速应被放大")
	check(is_equal_approx(GameState.total_crit_chance(),
		clampf(0.05 * (1.0 + pct), 0.0, Combat.MAX_CRIT_CHANCE)), "暴击率应被放大且截断上限")

# ---- 13) 换装后移速必须重算（`_speed` 是缓存，不是每帧现算）----

func _test_speed_follows_equipment() -> void:
	_setup(60)
	_dress("legendary", 12)
	var player := PlayerCharacter.new()
	player.set_physics_process(false)
	add_child(player)
	var boosted := player._speed
	check(is_equal_approx(boosted, GameState.total_move_speed() * Iso.TILE_W),
		"移速必须取派生门面（%.1f vs %.1f）" % [boosted, GameState.total_move_speed() * Iso.TILE_W])
	check(boosted > 4.0 * Iso.TILE_W, "套装加成后移速应变快，实际 %.1f" % boosted)
	# 卸一件 → 套装失效 → equipment_changed → 缓存的 _speed 必须跟着回落
	GameState.equipment["ring_2"] = null
	EventBus.equipment_changed.emit()
	check(player._speed < boosted,
		"套装失效后移速必须回落（只在 _ready 算一次会永远停在 %0.1f）" % boosted)
	player.queue_free()

# ---- 14) 面板文案真的渲染出来了（不是只有逻辑对）----
## 文案走 `%` 格式化，参数个数错了不会崩、只会输出原串或 `%!` 垃圾 ——
## 所以必须断言「成品文本里出现预期片段」，不能只断言 `set_bonus()` 的返回值。

func _test_panel_text() -> void:
	_setup(60)
	_dress("legendary", 12)
	var panel := preload("res://scenes/ui/CharacterPanel.tscn").instantiate()
	add_child(panel)
	panel._refresh()
	var text := String(panel._stats.text)
	check(text.contains("套装  "), "面板应含套装行，实际末段：%s" % text.substr(maxi(0, text.length() - 90)))
	check(text.contains("套装  传说  +20.0%"), "全紫应显示「套装  传说  +20.0%」")
	check(text.contains("全 +12 星"), "全 12 星应显示强化行")
	check(text.contains("已达最高档"), "顶档应显示已达最高档")
	# 占位符没被替换是最典型的「逻辑对、界面坏」：`%s` 残留说明参数个数对不上。
	check(not text.contains("%s") and not text.contains("%d"),
		"文案不得残留未替换的占位符")
	check(not text.contains("%!"), "文案格式化不得留下 %! 占位错误")
	# 卸一件后同一面板重刷：必须切成「未成套」
	GameState.equipment["ring_2"] = null
	panel._refresh()
	var broken := String(panel._stats.text)
	check(broken.contains("未成套（13/14）"), "卸一件应显示未成套（13/14），实际末段：%s"
		% broken.substr(maxi(0, broken.length() - 60)))
	check(broken.contains("穿满 14 个槽位后生效"), "未成套应给出生效条件")
	panel.queue_free()
