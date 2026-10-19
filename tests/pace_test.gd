extends Node
## M10-9 升级节奏与战斗不变量（工程 50 §4.1）：5 组用例。
##
## 三条最值钱的断言：
## 1. **用例 1 是「经验链闭合」的端到端证据** —— 用真实 `GameState.add_xp` + 真实
##    `LevelGap` + 真实 `boss_xp`，从 60 级空经验一路打到 70 级，统计实际击杀数。
##    它同时盖住三件事：`boss_xp = round(E/K)` 的取整、升级余数结转、Boss 等级锁定
##    带来的经验衰减。任何一处改成「按公式反推」都会让这条失去意义。
## 2. **用例 3 是产品 13 §2.3 + D-21 的签收标准** —— 击杀次数不再是常数：
##    「十级一套」下装备在套内不成长，曲线变成**锯齿**（套首最轻松、套末最肉、换套回弹）。
##    数据全部来自真实装备模板与真实聚合（`total_attack()` / `max_hp()`），不硬编码推导值。
##    这条同时防两个方向：**变肉失控**（> 基线 1.30 倍）与**锯齿消失**（= 有人把归一改回逐级）。
## 3. **用例 4 盯的是 `LevelGap` 真的生效** —— 循环图 Boss 等级在生成时锁定，玩家升级后
##    场上旧 Boss 经验 ×0.96。若有人「为了避免漂移」把它改成恒 1.0，这条必须红。

## 装备 kind → 槽位 id（十部位，护腕 / 护膝 / 手镯 / 戒指各两格）。
const SLOT_MAP := {
	"weapon": ["weapon"], "shield": ["shield"], "helmet": ["helmet"],
	"armor": ["armor"], "shoes": ["shoes"], "necklace": ["necklace"],
	"bracer": ["bracer_1", "bracer_2"], "knee": ["knee_1", "knee_2"],
	"bracelet": ["bracelet_1", "bracelet_2"], "ring": ["ring_1", "ring_2"],
}

## 产品 13 §2.3 的基线击杀次数（60 级满装打 c6_boss03 归一化数值）。
const BASE_KILLS := 123.7
## c6_boss03 的归一化数值（endgame.json 的 arenaBosses，与产品 §4.2 同源）。
const BOSS_NORM_HP := 24300.0
const BOSS_NORM_ATK := 420.0
const BOSS_NORM_DEF := 141.0

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PaceTest] " + label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _ready() -> void:
	_test_level_pace_60_to_70()
	_test_per_level_kills()
	_test_combat_invariant()
	_test_level_gap_applies()
	_test_curve_bounds()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[PaceTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[PaceTest] 失败 %d 项 ❌" % failures.size())
		get_tree().quit(1)

# ---- 装备与聚合（真实模板，不硬编码属性）----

## 循环套十个型号：`tierBases` 只有 51 一档的那些。
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

## 给玩家穿满一套。`level <= 60` 走静态档（模板自身的 requiredLevel），否则走动态实例。
## 品质固定 `common`：产品 §2.3 的基线是「纯基底」，`affixCount = 0` 才不会混进词条。
func _dress(level: int) -> void:
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
			item = ItemFactory.make_equip_roll(id, 51, "common", _rng(seed))
		else:
			item = ItemFactory.make_equip_dynamic(id, level, "common", _rng(seed))
		for slot_id in slots:
			GameState.equipment[slot_id] = item

func _setup(level: int) -> void:
	GameState.reset_to_defaults()
	GameState.player.level = level
	GameState.player.attack = Balance.base_attack(level)
	GameState.player.defense = Balance.base_defense(level)
	_dress(level)
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()

## 击杀一只 Boss 需要的次数（产品 §2.3 的公式：max(1, 攻 − 防×0.5)）。
func _kill_count(level: int) -> float:
	var s := Balance.scale(level - 60)
	var dmg := maxf(1.0, float(GameState.total_attack()) - BOSS_NORM_DEF * s * 0.5)
	return BOSS_NORM_HP * s / dmg

## 能被 Boss 打几次（同上口径）。
func _hurt_count(level: int) -> float:
	var s := Balance.scale(level - 60)
	var taken := maxf(1.0, BOSS_NORM_ATK * s - float(GameState.total_defense()) * 0.5)
	return float(GameState.max_hp()) / taken

# ---- 1) 60 → 70 的实际击杀数（经验链端到端）----

## 模拟：10 只 Boss、每只 150s、复活 600s；**Boss 等级在生成那一刻锁定**。
## 这不是「按公式反推」，而是照实跑 `GameState.add_xp`。
func _simulate_pace() -> Dictionary:
	_setup(60)
	var spawn_level: Array = []
	var respawn_at: Array = []
	for _i in range(10):
		spawn_level.append(60)
		respawn_at.append(0.0)
	var t := 0.0
	var kills := 0
	var per_level: Dictionary = {}
	while int(GameState.player.level) < 70 and kills < 2000:
		var best := 0
		for i in range(1, 10):
			if float(respawn_at[i]) < float(respawn_at[best]):
				best = i
		if float(respawn_at[best]) > t:
			t = float(respawn_at[best])
		var player_level := int(GameState.player.level)
		var boss_level := int(spawn_level[best])
		var xp := LevelGap.kill_xp(Balance.boss_xp(boss_level), player_level, boss_level)
		GameState.add_xp(xp)
		kills += 1
		per_level[player_level] = int(per_level.get(player_level, 0)) + 1
		t += 150.0
		respawn_at[best] = t + 600.0
		spawn_level[best] = maxi(60, int(GameState.player.level))
	return {"kills": kills, "seconds": t, "per_level": per_level}

func _test_level_pace_60_to_70() -> void:
	var sum_k := 0.0
	for lv in range(60, 70):
		sum_k += Balance.kills_per_level(lv)
	var sim := _simulate_pace()
	var kills := int(sim.get("kills", 0))
	var per_level: Dictionary = sim.get("per_level", {})
	check(int(GameState.player.level) == 70, "模拟应升到 70 级，实际 %d" % int(GameState.player.level))
	# 上界 128.1 × 1.155 ≈ 148：防「越打越慢」；下界 120：防「白送经验」。
	check(kills <= 148, "60→70 击杀数应 ≤ 148（= ΣK 的 115%%），实际 %d（ΣK=%.1f）" % [kills, sum_k])
	check(kills > 120, "60→70 击杀数应 > 120（低于即经验被放大），实际 %d" % kills)
	# 每级都要真的经过一遍，防「一次 add_xp 跳两级」把统计抹平。
	for lv in range(60, 70):
		check(int(per_level.get(lv, 0)) > 0, "升 %d→%d 应有击杀记录，实际没有" % [lv, lv + 1])
	var seconds := float(sim.get("seconds", 0.0))
	check(seconds > 18000.0 and seconds < 23000.0,
		"60→70 总耗时应 ≈ 20,250s（5.6h），实际 %.0fs" % seconds)

# ---- 2) 每级击杀数的上下界（`boss_xp` 取整 + 衰减）----

func _test_per_level_kills() -> void:
	var sim := _simulate_pace()
	var per_level: Dictionary = sim.get("per_level", {})
	for lv in range(60, 70):
		var n := int(per_level.get(lv, 0))
		var k := Balance.kills_per_level(lv)
		check(float(n) >= k - 1.0, "L%d 击杀数 %d 低于 K(%.2f)−1（经验被放大）" % [lv, n, k])
		check(float(n) <= k + 2.0, "L%d 击杀数 %d 高于 K(%.2f)+2（经验衰减过头）" % [lv, n, k])

# ---- 3) 战斗曲线：套内锯齿 + 换套回弹（产品 §2.3 / D-21）----

## D-21 落地（2026-10-19）后的实测锚点。数值 = common 满装打归一化 Boss 的击杀次数。
## 读法：**套首**（L61/71/81…）玩家整套管用、比基线轻 8%–20%；**套末**（L70/80/90…）
## 装备没长而怪长了，落后 1%–27.5%；跨过套边界立刻回弹。
## 高等级锯齿收敛（L1000 只差 0.8%），因为基线 `130×S(d)` 逐渐压过装备。
const SAW_START := {61: 98.95, 71: 109.16, 81: 111.05, 91: 112.96}
const SAW_END := {70: 157.75, 80: 146.24, 90: 142.58, 100: 140.06}

func _test_combat_invariant() -> void:
	# ① 60 级基线一位不动（1—60 完全不受 D-21 影响）。
	_setup(60)
	var base := _kill_count(60)
	var base_delta := absf(base - BASE_KILLS) / BASE_KILLS
	check(base_delta < 0.015,
		"L60 击杀次数应 ≈ %.1f（±1.5%%），实际 %.1f" % [BASE_KILLS, base])
	# ② 八个采样点全部守住「不失控、不白送」：套末最差 +27.5%，套首最好 −20%。
	for lv in [61, 67, 70, 71, 80, 100, 500, 1000]:
		_setup(lv)
		var kills := _kill_count(lv)
		check(kills <= BASE_KILLS * 1.30,
			"L%d 击杀 %.2f 超过基线的 1.30 倍（套内落后失控）" % [lv, kills])
		check(kills >= BASE_KILLS * 0.75,
			"L%d 击杀 %.2f 低于基线的 0.75 倍（等级/装备白送）" % [lv, kills])
		# 可挨打次数：逐级装备时代最差 6.24；套末最差 5.60（D-21 的必然代价），下限取 5.5。
		check(_hurt_count(lv) >= 5.5,
			"L%d 可挨打次数应 ≥ 5.5，实际 %.2f" % [lv, _hurt_count(lv)])
	# ③ 锯齿形状本身：四个采样点各自 ±2%（这条是「归一真的生效」的判据）。
	for lv in SAW_START.keys():
		_setup(lv)
		var want := float(SAW_START[lv])
		var got := _kill_count(lv)
		check(absf(got - want) / want < 0.02,
			"L%d 套首击杀应 ≈ %.1f，实际 %.1f（直接用 Boss 等级 ⇒ 回到 123.7 即红）" % [lv, want, got])
	for lv in SAW_END.keys():
		_setup(lv)
		var want := float(SAW_END[lv])
		var got := _kill_count(lv)
		check(absf(got - want) / want < 0.02,
			"L%d 套末击杀应 ≈ %.1f，实际 %.1f（归一被改回逐级即红）" % [lv, want, got])
	# ④ 结构判据（不依赖具体数字）：套末必须明显比套首肉，换套必须明显回弹。
	#    只对前四套断言 —— 191 套之后基线占主导，锯齿本就收敛到 ±8%，不该硬凑。
	for start in [61, 71, 81, 91]:
		_setup(start)
		var head := _kill_count(start)
		_setup(start + 9)
		var tail := _kill_count(start + 9)
		check(tail / head >= 1.20,
			"%d—%d 套：套末/套首应 ≥ 1.20（装备在套内不成长），实际 %.2f" % [start, start + 9, tail / head])
		if start < 91:
			_setup(start + 10)
			var next_head := _kill_count(start + 10)
			check(next_head / tail <= 0.85,
				"%d 套换套回弹不足：%.1f → %.1f（应 ≤ 0.85 倍）" % [start + 10, tail, next_head])

# ---- 4) `LevelGap` 真实生效（循环图 Boss 等级锁定）----

func _test_level_gap_applies() -> void:
	var xp60 := Balance.boss_xp(60)
	var same := LevelGap.kill_xp(xp60, 60, 60)
	check(same == xp60, "同级击杀经验应为满额 %d，实际 %d" % [xp60, same])
	var behind := LevelGap.kill_xp(xp60, 70, 60)
	check(behind == int(round(float(xp60) * 0.6)),
		"玩家 70 打 60 级 Boss 应为 ×0.6 = %d，实际 %d" % [int(round(float(xp60) * 0.6)), behind])
	check(behind < same, "等级落后必须让经验变少（改成恒 1.0 即红）")
	# 循环图反过来的方向：玩家 60 打 70 级 Boss 是 ×1.5 上限内（不在本图出现，仅锁语义）。
	var ahead := LevelGap.kill_xp(Balance.boss_xp(70), 60, 70)
	check(ahead > Balance.boss_xp(70), "越级击杀经验应高于满额（上限 1.5 倍）")

# ---- 5) 曲线边界（9999 级护栏）----

func _test_curve_bounds() -> void:
	var e := Balance.xp_to_next(9999)
	check(e > 0 and e < 9223372036854775807, "E(9999) 必须落在 int64 内，实际 %d" % e)
	check(Balance.kills_per_level(9999) > 0.0, "K(9999) 应为正")
	var bx := Balance.boss_xp(9999)
	check(bx >= 1, "boss_xp(9999) 至少为 1，实际 %d" % bx)
	# 反推的闭合性：K 只 × boss_xp 必须够一级（除不尽的余数由下一只补）。
	var need := Balance.xp_to_next(9999)
	check(float(bx) * Balance.kills_per_level(9999) >= float(need) - Balance.kills_per_level(9999),
		"9999 级「K 只」的经验不应比一级需求少一只以上")
