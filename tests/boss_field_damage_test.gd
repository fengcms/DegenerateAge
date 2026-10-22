extends Node
## 工程 94（D-32）百首禁域「必须能打疼玩家」契约。
##
## 为什么需要这个文件：`endgame_cycle_map_test` 只断「配置是 3.0」——那守的是**数字**，
## 不是**结果**。真正要守的是「Boss 打得动满紫 12 星的玩家」。这两者会在三种情况下分叉：
##   ① 有人调低 Boss 的 `norm.atk`（`endgame.json` 数值表调整）；
##   ② 有人改装备防御公式 / 套装加成（`EquipmentMath` / `SetBonus`）；
##   ③ 玩家继续升级 / 换更肉装备，防御涨过 Boss 攻击（破防是**差值**，极敏感）。
## 这三种情况下 `atkMultiplier == 3.0` **全绿**，但游戏又变回血包（每击恒保底 60）。
## 工程 91 就是这么发布的：配置写了、测试绿了、玩家站着打 148 秒只掉 1.9% 血。
##
## 🔴 **不造装备**：本文件第一版用 `ItemFactory` 造了一套紫装 12 星，跑出来 103 万血
## （真实存档 40.8 万）——造出来的玩家比真人肉 2.5 倍，「每击占比」「60 秒掉血」全部失真。
## 玩家侧属性取决于**真实词条骰子**，造不出来。所以改用实测快照常数（下方 `SNAPSHOT_*`）。
##
## Boss 侧则走**完整生产链路**：真实例化 `Monster`（`add_child` → `_ready` → `_load_template`），
## `attack_power` 已含 `Endgame.norm()` + `Balance.scale()` + `atk_multiplier`。

## 玩家侧快照（2026-10-22 用户真实存档 `slot_3`，140 级全身紫装 12 星）。
## 来源：`tools/boss_ttk_probe` 读真实存档复算，与 docs/工程文档/94 §1 同一份数据。
## 🔴 这两个数**无法从代码推导**（取决于玩家实际词条），只能实测。
##    玩家升级 / 换装后请重跑探针并更新此处，否则本测试守的是**旧玩家**。
const SNAPSHOT_LEVEL := 140
const SNAPSHOT_DEFENSE := 41857.0
const SNAPSHOT_MAX_HP := 408288.0

## Boss 实际出手率：技能动作 / 走位期间不出普攻。工程 92 实测 14.7 秒挨 4.5 击
## （`interval 1.8s` 理论 8.2 击 × 0.55）。拿它把「每击」换算成「一段时间掉多少血」。
const HIT_RATE := 0.55
## 每击至少是保底的 50 倍 —— 保底 60 是「打不动」的同义词。
## 快照玩家实际 87 倍（5,246 / 60），留 74% 余量给「玩家换装更肉」。
const MIN_HIT_FACTOR := 50.0
## 配置倍率相对破防阈值至少留 20% 余量（快照玩家 3.0 / 2.3987 ≈ 1.25，实留 25%）。
const MIN_HEADROOM := 1.20
## 站桩 60 秒至少掉 20% 血 —— 低于这个数血条看不出变化（快照玩家 23.5%）。
const HP_DROP_60S := 0.20

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[BossFieldDamageTest] " + label)

func _ready() -> void:
	var specs := _boss_specs()
	if specs.is_empty():
		check(false, "百首禁域必须能读出 bossSpawns")
	else:
		_test_break_through(specs)
		_test_headroom(specs)
		_test_60s_hp_drop(specs)
	if failures.is_empty():
		print("[BossFieldDamageTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[BossFieldDamageTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 取值 ----

## 保底口径与 `monster.gd::_min_hit_on_player()` 一致（`clampi(maxHP×0.25%, 10, 60)`）。
## 🔴 用快照血池算完还要断言它**顶到 60 上限**：否则血池常数被改小后，
##    保底跟着变小，后面「每击 ≥ 保底×50」会跟着放松而全绿。
func _min_hit() -> int:
	return clampi(int(round(SNAPSHOT_MAX_HP * 0.0025)), 10, 60)

## 从真实地图配置取出去重后的怪种与**最低**倍率。
## 🔴 不写死 3.0：改配置本测试要跟着走；取最低倍率是不让「某席配错高倍率」把整体抬过去。
func _boss_specs() -> Array:
	var map: Dictionary = DataLoader.get_entry("maps", "c7_boss_field")
	var seats: Array = map.get("bossSpawns", [])
	if seats.is_empty():
		return []
	var lowest_atk := INF
	var lowest_hp := INF
	var ids := {}
	for raw in seats:
		var seat: Dictionary = raw
		ids[String(seat.get("monsterId", ""))] = true
		lowest_atk = minf(lowest_atk, float(seat.get("atkMultiplier", 1.0)))
		lowest_hp = minf(lowest_hp, float(seat.get("hpMultiplier", 1.0)))
	var specs: Array = []
	for mid in ids.keys():
		specs.append({"mid": String(mid), "atk": lowest_atk, "hp": lowest_hp})
	specs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["mid"]) < String(b["mid"]))
	return specs

## 真实例化一只 Boss：`add_child` 触发 `_ready` → `_load_template`，
## `attack_power` 已含 `Balance.scale` 与 `atk_multiplier`（monster.gd 第 221 行）。
## 🔴 `stat_norm` 必须与 `spawner.gd` 第 100 行同源（`Endgame.norm(id)` if `scaleStats`）：
##    漏了它会走 `elif scale_stats: attack_power *= scaled` 分支（模板原始攻 × 等级缩放），
##    算出的是**另一个游戏的数值**（实测同一只怪从 26,174 变成 1,371），结论完全相反。
func _make_boss(spec: Dictionary) -> Monster:
	var m := Monster.new()
	m.monster_id = String(spec["mid"])
	m.spawn_level = SNAPSHOT_LEVEL
	m.stat_norm = Endgame.norm(String(spec["mid"]))
	m.atk_multiplier = float(spec["atk"])
	m.hp_multiplier = float(spec["hp"])
	m.scale_stats = true
	add_child(m)
	return m

func _hit(m: Monster) -> int:
	var res := Combat.resolve(m.attack_power, SNAPSHOT_DEFENSE, 1.0, 0.0, 1.5, 0.0, null, _min_hit())
	return int(res.get("damage", 0))

# ---- 用例 ----

## 1) 破防：每击必须远超保底。
func _test_break_through(specs: Array) -> void:
	var min_hit := _min_hit()
	check(min_hit == 60, "快照血池 %.0f 的保底应顶到上限 60（实际 %d）；血池常数被改小会让本文件整体放松"
		% [SNAPSHOT_MAX_HP, min_hit])
	var need := int(float(min_hit) * MIN_HIT_FACTOR)
	for spec in specs:
		var m := _make_boss(spec)
		var damage := _hit(m)
		check(damage >= need,
			"%s 每击 %d 应 ≥ 保底 %d 的 %.0f 倍（%d）；Boss 实攻 %.0f / 玩家防御 %.0f / 破防线 %.0f"
			% [String(spec["mid"]), damage, min_hit, MIN_HIT_FACTOR, need,
			   m.attack_power, SNAPSHOT_DEFENSE, SNAPSHOT_DEFENSE * 0.5])
		m.free()

## 2) 余量：配置倍率必须明显高于「破防阈值倍数」。
##    这条比「等于 3.0」有牙得多 —— 它守的是**关系**：Boss 数值表或装备公式任一侧被改动都会红。
func _test_headroom(specs: Array) -> void:
	for spec in specs:
		var m := _make_boss(spec)
		var base_atk := m.attack_power / maxf(m.atk_multiplier, 0.001)
		var threshold := SNAPSHOT_DEFENSE * 0.5 / maxf(base_atk, 0.001)
		var headroom := m.atk_multiplier / maxf(threshold, 0.001)
		check(headroom >= MIN_HEADROOM,
			"%s 攻击倍率 %.2f 相对破防阈值 %.2f 倍只余 %.0f%%，应 ≥ %.0f%%（防御涨过 Boss 攻击就会变血包）"
			% [String(spec["mid"]), m.atk_multiplier, threshold, (headroom - 1.0) * 100.0,
			   (MIN_HEADROOM - 1.0) * 100.0])
		m.free()

## 3) 体感：站桩 60 秒要能掉 20% 血。
func _test_60s_hp_drop(specs: Array) -> void:
	for spec in specs:
		var m := _make_boss(spec)
		var damage := float(_hit(m))
		var hits := 60.0 / maxf(m.attack_interval, 0.1) * HIT_RATE
		var drop := damage * hits / maxf(SNAPSHOT_MAX_HP, 1.0)
		check(drop >= HP_DROP_60S,
			"%s 站桩 60 秒应掉 ≥ %.0f%% 血（每击 %d × %.1f 击 ÷ %.0f），实际 %.1f%%"
			% [String(spec["mid"]), HP_DROP_60S * 100.0, int(damage), hits, SNAPSHOT_MAX_HP, drop * 100.0])
		m.free()
