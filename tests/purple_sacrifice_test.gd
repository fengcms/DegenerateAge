extends Node
## 工程 87：紫装献祭换经验的数值与事务契约。9 组用例。
##
## 四条最值钱的断言：
## 1. **组 1「按装备需求等级计价」** —— L80 玩家的武器实例 `requiredLevel` 是 **71**（十级一套：
##    `dynamic_tier_start(80) = 71` + 武器偏移 0），所以一件换的是 `boss_xp(71) = 8,717`，
##    不是 `boss_xp(80) = 11,375`。这条钉住「不能按玩家等级计价」的落地形态。
## 2. **组 2「星级加成 = 1.96 倍」** —— 与卖价 `Shop.STAR_SELL_BONUS` 同构，且仍远低于升星成本
##    （128,747 金币），不会形成「金币 → 经验」的套利通道。
## 3. **组 8「任一件不合规整批不扣」** —— 混杂一件穿戴中的件时，合法的那 5 件必须原样留在背包。
## 4. **组 9「升级结转不丢经验」** —— `add_xp` 内部是 while 连升，逐级扣门槛后余额必须分毫不差。

const DYNAMIC_TIER := 51
const OPEN_LEVEL := 61

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PurpleSacrificeTest] " + label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _ready() -> void:
	_test_xp_formula()
	_test_star_multiplier()
	_test_eligible()
	_test_plan_group_and_limit()
	_test_settle()
	_test_worn_rejected()
	_test_low_level()
	_test_atomic_batch()
	_test_level_up()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[PurpleSacrificeTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[PurpleSacrificeTest] 失败 %d 项 ❌" % failures.size())
		get_tree().quit(1)

# ---- 夹具 ----

## 重置到干净状态。`add_xp` 的升级分支会读 `max_hp()`，所以攻防也要抬到曲线基线。
func _fresh(level: int) -> void:
	GameState.reset_to_defaults()
	GameState.player.level = level
	GameState.player.xp = 0
	GameState.player.attack = Balance.base_attack(level)
	GameState.player.defense = Balance.base_defense(level)
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()

## 循环套里的武器模板 id —— 偏移 0，`requiredLevel == dynamic_tier_start(level)`，便于精确断言。
func _weapon_id() -> String:
	var rows: Variant = DataLoader.get_table("equipments")
	if rows is Array:
		for row in rows:
			if not row is Dictionary:
				continue
			var entry: Dictionary = row
			if String(entry.get("slot", "")) != "weapon":
				continue
			var bases: Variant = entry.get("tierBases", {})
			if bases is Dictionary and (bases as Dictionary).size() == 1 \
					and (bases as Dictionary).has(str(DYNAMIC_TIER)):
				return String(entry.get("id", ""))
	return ""

## 造一件真实紫装（走生产入口 `make_equip_dynamic`，不硬编数值）。
func _purple(level: int, star: int = 0) -> Dictionary:
	var item_id := _weapon_id()
	check(not item_id.is_empty(), "应存在第 51 套武器型号")
	var item := ItemFactory.make_equip_dynamic(item_id, level, "legendary", _rng(level), "tst")
	check(not item.is_empty(), "L%d 紫装应能生成" % level)
	item.star = star
	return item

func _put(item: Dictionary) -> int:
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i] == null:
			GameState.inventory[i] = item
			return i
	check(false, "背包已满，测试夹具放不下")
	return -1

func _ids(items: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for item in items:
		out.append(String((item as Dictionary).get("instanceId", "")))
	return out

# ---- 组 1：按装备需求等级计价 ----

func _test_xp_formula() -> void:
	_fresh(80)
	var item := _purple(80)
	var required := int(item.get("requiredLevel", 0))
	check(required == 71, "L80 玩家的武器实例需求等级应为 71（十级一套），实际 %d" % required)
	check(Sacrifice.xp_of(item) == Balance.boss_xp(required),
		"一件 0★ 应等于 boss_xp(%d)=%d，实际 %d"
			% [required, Balance.boss_xp(required), Sacrifice.xp_of(item)])
	check(Sacrifice.xp_of(item) == 8717, "L80 档武器一件应为 8,717（boss_xp(71)），实际 %d" % Sacrifice.xp_of(item))
	# 逐值覆盖三个套起点，确认不是「碰巧对上」。
	for level in [61, 71, 91]:
		var sample := _purple(level)
		var lv := int(sample.get("requiredLevel", 0))
		check(lv == level, "L%d 武器需求等级应等于套起点 %d，实际 %d" % [level, level, lv])
		check(Sacrifice.xp_of(sample) == Balance.boss_xp(lv),
			"L%d 一件应为 boss_xp(%d)=%d，实际 %d" % [level, lv, Balance.boss_xp(lv), Sacrifice.xp_of(sample)])

# ---- 组 2：星级加成 ----

func _test_star_multiplier() -> void:
	_fresh(80)
	var zero := _purple(80, 0)
	var full := _purple(80, 12)
	var lv := int(zero.get("requiredLevel", 0))
	var expected := int(round(float(Balance.boss_xp(lv)) * (1.0 + 12.0 * Sacrifice.STAR_BONUS)))
	check(Sacrifice.xp_of(full) == expected,
		"12★ 一件应为 round(boss_xp×1.96)=%d，实际 %d" % [expected, Sacrifice.xp_of(full)])
	var ratio := float(Sacrifice.xp_of(full)) / float(maxi(1, Sacrifice.xp_of(zero)))
	check(ratio > 1.95 and ratio < 1.97, "12★ / 0★ 应在 1.95—1.97，实际 %.3f" % ratio)
	# 升星总成本远高于换来的经验 ⇒ 不存在「花金币买经验」的套利。
	check(EquipmentFusion.full_star_cost() > Sacrifice.xp_of(full),
		"升满 12★ 的金币成本（%d）必须高于一件 12★ 换来的经验（%d），否则金币可套利"
			% [EquipmentFusion.full_star_cost(), Sacrifice.xp_of(full)])

# ---- 组 3：白名单 ----

func _test_eligible() -> void:
	_fresh(80)
	var good := _purple(80)
	check(Sacrifice.eligible(good), "普通紫装应可献祭")
	var favored := good.duplicate(true)
	favored.favorite = true
	check(not Sacrifice.eligible(favored), "收藏件不可献祭")
	check(Sacrifice.xp_of(favored) == 0, "收藏件经验应为 0")
	var golden := _purple(80)
	golden.quality = "epic"
	check(not Sacrifice.eligible(golden), "金装不可献祭")
	check(Sacrifice.xp_of(golden) == 0, "金装经验应为 0")
	var potion := {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	check(not Sacrifice.eligible(potion), "药水不可献祭")
	var bad_star := _purple(80)
	bad_star.star = 13
	check(not Sacrifice.eligible(bad_star), "星级超过上限不可献祭")
	check(not Sacrifice.eligible({}), "空字典不可献祭")

# ---- 组 4：分组与单次上限 ----

func _test_plan_group_and_limit() -> void:
	_fresh(80)
	for i in range(10):
		_put(_purple(61))
	for i in range(10):
		_put(_purple(71))
	for i in range(5):
		_put(_purple(81))
	var plan := Sacrifice.plan(GameState.inventory)
	check(int(plan.get("count", 0)) == Sacrifice.MAX_BATCH,
		"单次应取满 %d 件，实际 %d" % [Sacrifice.MAX_BATCH, int(plan.get("count", 0))])
	check(int(plan.get("remaining", 0)) == 5, "剩 5 件未计入，实际 %d" % int(plan.get("remaining", 0)))
	var groups: Array = plan.get("groups", [])
	check(groups.size() == 2, "只应出现 61 与 71 两档，实际 %d 组" % groups.size())
	if groups.size() == 2:
		var first: Dictionary = groups[0]
		var second: Dictionary = groups[1]
		check(int(first.get("tier", 0)) == 61 and int(first.get("count", 0)) == 10,
			"最低档应优先：61 档 10 件")
		check(int(second.get("tier", 0)) == 71 and int(second.get("count", 0)) == 10,
			"次低档：71 档 10 件")
	var total := 0
	for group in groups:
		total += int((group as Dictionary).get("xp", 0))
	check(total == int(plan.get("xp", 0)), "分组经验之和应等于总经验")
	# 12★ 默认单列、不计入；勾选后才并入。
	var maxed := _purple(71, 12)
	_put(maxed)
	var with_max := Sacrifice.plan(GameState.inventory)
	check(int(with_max.get("star12_count", 0)) == 1, "12★ 应被单列计数")
	check(int(with_max.get("star12_xp", 0)) == Sacrifice.xp_of(maxed), "12★ 单列经验应正确")
	var included := Sacrifice.plan(GameState.inventory, true)
	check(int(included.get("count", 0)) == Sacrifice.MAX_BATCH,
		"含 12★ 时仍受单次上限约束")
	check(int(included.get("star12_count", 0)) == 1, "计入后 12★ 仍要能被界面提示")

# ---- 组 5：真实结算守恒 ----

func _test_settle() -> void:
	_fresh(80)
	var items: Array[Dictionary] = []
	for i in range(5):
		items.append(_purple(71))
	for item in items:
		_put(item)
	var bystander := ItemFactory.make_equip_dynamic(_weapon_id(), 71, "rare", _rng(7), "tst")
	var bystander_index := _put(bystander)
	var expected_xp := 0
	for item in items:
		expected_xp += Sacrifice.xp_of(item)
	var before_level := int(GameState.player.level)
	var before_xp := int(GameState.player.xp)
	var result := GameState.sacrifice_purple(_ids(items))
	check(bool(result.get("ok", false)), "合法献祭应成功：%s" % result.get("reason", ""))
	check(int(result.get("count", 0)) == 5, "应消耗 5 件，实际 %d" % int(result.get("count", 0)))
	check(int(result.get("xp", 0)) == expected_xp, "返回经验应为 %d，实际 %d"
		% [expected_xp, int(result.get("xp", 0))])
	var left := 0
	for entry in GameState.inventory:
		if entry is Dictionary and String((entry as Dictionary).get("quality", "")) == "legendary":
			left += 1
	check(left == 0, "5 件紫装应全部消失，实际还剩 %d 件" % left)
	check(GameState.inventory[bystander_index] != null, "同批次的非紫装必须原样保留")
	check(int(GameState.player.level) == before_level, "5 件经验不足一级，不应升级")
	check(int(GameState.player.xp) == before_xp + expected_xp,
		"经验应为 %d，实际 %d" % [before_xp + expected_xp, int(GameState.player.xp)])
	# 重复 id 必须被拒（防同一件被算两次）。
	var dup := PackedStringArray()
	dup.append(String(items[0].get("instanceId", "")))
	dup.append(String(items[0].get("instanceId", "")))
	var replay := GameState.sacrifice_purple(dup)
	check(not bool(replay.get("ok", false)), "重复实例 ID 必须被拒")

# ---- 组 6：穿戴中的件不可献祭 ----

func _test_worn_rejected() -> void:
	_fresh(80)
	var worn := _purple(71)
	GameState.equipment["weapon"] = worn
	var result := GameState.sacrifice_purple(_ids([worn]))
	check(not bool(result.get("ok", false)), "穿戴中的紫装必须被拒")
	check(GameState.equipment.get("weapon") != null, "被拒后身上那件必须还在")
	var plan := Sacrifice.plan(GameState.inventory)
	check(int(plan.get("count", 0)) == 0, "plan 不应把穿戴件算进背包")

# ---- 组 7：低等级不开放 ----

func _test_low_level() -> void:
	_fresh(60)
	var item := _purple(60)
	_put(item)
	var result := GameState.sacrifice_purple(_ids([item]))
	check(not bool(result.get("ok", false)), "L60 应被拒（护住前 60 级节奏锚点）")
	check(GameState.inventory[_find_index(item)] != null, "被拒后件必须还在")
	_fresh(OPEN_LEVEL)
	var ok_item := _purple(OPEN_LEVEL)
	_put(ok_item)
	check(bool(GameState.sacrifice_purple(_ids([ok_item])).get("ok", false)),
		"L%d 应开放献祭" % OPEN_LEVEL)

func _find_index(item: Dictionary) -> int:
	var id := String(item.get("instanceId", ""))
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i] is Dictionary \
				and String((GameState.inventory[i] as Dictionary).get("instanceId", "")) == id:
			return i
	return -1

# ---- 组 8：任一件不合规整批不扣 ----

func _test_atomic_batch() -> void:
	_fresh(80)
	var good: Array[Dictionary] = []
	for i in range(5):
		var item := _purple(71)
		_put(item)
		good.append(item)
	var worn := _purple(71)
	GameState.equipment["weapon"] = worn
	var mixed := _ids(good)
	mixed.append(String(worn.get("instanceId", "")))
	var result := GameState.sacrifice_purple(mixed)
	check(not bool(result.get("ok", false)), "混入穿戴件必须整批拒绝")
	var survived := 0
	for item in good:
		if _find_index(item) >= 0:
			survived += 1
	check(survived == 5, "被拒后 5 件合法件必须原样在背包，实际剩 %d 件" % survived)
	check(int(GameState.player.xp) == 0, "整批被拒不能给经验，实际 %d" % int(GameState.player.xp))
	# 超过单次上限同样整批拒绝，不做静默截断。
	var many := PackedStringArray()
	for i in range(Sacrifice.MAX_BATCH + 1):
		many.append("x_%d" % i)
	var over := GameState.sacrifice_purple(many)
	check(not bool(over.get("ok", false)), "超过 %d 件必须被拒" % Sacrifice.MAX_BATCH)

# ---- 组 9：升级结转不丢经验 ----

func _test_level_up() -> void:
	_fresh(80)
	var items: Array[Dictionary] = []
	for i in range(Sacrifice.MAX_BATCH):
		var item := _purple(91)
		_put(item)
		items.append(item)
	var gain := 0
	for item in items:
		gain += Sacrifice.xp_of(item)
	var before_level := int(GameState.player.level)
	var before_xp := 177000
	GameState.player.xp = before_xp
	var result := GameState.sacrifice_purple(_ids(items))
	check(bool(result.get("ok", false)), "满批献祭应成功：%s" % result.get("reason", ""))
	check(int(GameState.player.level) > before_level, "满批应至少升 1 级")
	var consumed := 0
	var lv := before_level
	while lv < int(GameState.player.level):
		consumed += GameState.xp_to_next(lv)
		lv += 1
	check(int(GameState.player.xp) == before_xp + gain - consumed,
		"升级结转应分毫不差：期望 %d，实际 %d" % [before_xp + gain - consumed, int(GameState.player.xp)])
	check(int(GameState.player.xp) < GameState.xp_to_next(int(GameState.player.level)),
		"结转后剩余经验必须低于下一级门槛")
	check(int(GameState.player.level) <= GameState.PLAYER_LEVEL_CAP, "等级不得越过上限")
