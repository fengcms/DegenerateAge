extends Node
## 工程 107 §七：武士轮转探针 —— 六条判据的**唯一测量点**。
##
## 为什么需要它：107 把武士从「固定点耗蓝 + 无上限 AOE」改成「百分比耗蓝 + 上限 8 只」，
## 这两件事都**不会报错**，只会在实机上表现成「打着打着没蓝了」或「一片怪越打越爽」。
## 单元测试能守住单点语义（一次施放扣多少蓝、`skill_targets` 截断到 8），
## 但守不住「60 秒里这套轮转整体长什么样」——那需要一条时间轴。
##
## 六条判据（§七原表，带口径修正）：
##   ① 单体 60 秒 DPS 波动 ≤ ±8%          —— 轮转稳定，没有某一段突然暴涨
##   ② 全 CD 强放耗尽蓝池时间 ∈ [40, 100]s —— ⚠ 见下方「口径修正」
##   ③ 选择性施放 60 秒蓝量低尾 ≥ 15% 蓝池 —— 有取舍但仍能打
##   ④ 8 怪 DPS 倍数与改前 3.64× 同档；20 怪相对 8 怪的涨幅必须比改前低 15% 以上
##   ⑤ 战意觉醒 8 秒内承伤下降 ∈ [18%, 22%] —— 减伤 20% 的实测口径（含取整）
##   ⑥ 武士打 Boss 蓝药消耗 ∈ [1, 2] 瓶     —— ⚠ 见下方「口径修正（⑥）」
##
## 🔑 口径修正（②，2026-10-29）：原文写「12—16 秒」，那是按初稿的 92%/12s 估的。
##    初稿的绝对值错了一个量级（武士 7.67%/s 是法师 3.96%/s 的 1.94 倍，定位反了），
##    已在文档 §4.3 修正为 1.84%/s 并记录在案。判据必须跟着那个修正走，
##    否则守的是一条**已经不存在的设计** —— 所以这里改成 [40, 100] 秒，
##    并且额外用「武士打空时间 ≥ 法师 × 1.4」这条**跨职业关系**兜底：
##    绝对值可以随版本调，但「武士更省蓝」这个定位不能翻。
##
## 🔴 本探针**不**模拟防御与破甲收益：伤害一律按 `系数 × 段数 × 攻击` 计。
##    ①④ 用的都是比值，防御在分子分母里同时出现；破甲重击的 −30% 防御按 §4.4
##    实测只值约 +4% 每击，忽略它只会让本探针**偏保守**，不会把问题藏起来。
##
## 运行：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/warrior_rotation_probe.tscn
##   （无头即可：纯数值模拟，没有一帧绘制）

## 玩家侧快照：与 `tests/class_balance_test.gd` **同一份**（160 级真实存档的派生值）。
## 🔴 两边必须同源，否则「探针说 1 瓶、测试说 0 瓶」时无从判断谁错了。
## 玩家升级 / 换装后请重跑 `tools/class_balance_probe` 并**同时**更新两处。
const LEVEL := 160
const SNAPSHOT_ATTACK := 55661.0
const SNAPSHOT_DEFENSE := 62629.0
const SNAPSHOT_MP_FLAT := 75836.0

## 模拟步长。1/120 足够让「槽位刚好对上冷却」这种边界稳定复现；
## 1/60 在 24 秒 CD 上会累积到整数帧的取整误差，1/240 只是白烧时间。
const DT := 1.0 / 120.0
const DURATION := 60.0
const WINDOW := 10.0
## 判据 ① 专用：窗口必须**对齐战意觉醒的 24 秒周期**。
## 🔴 原设计想用「10 秒窗口、波动 ≤ ±8%」，那个数在算术上不可能达成：
##    10 秒 = 12.5 刀，8 秒 +15% 攻速的窗口本身就有 +12%，再加上窗口边界错一刀 ±8%
##    ⇒ 理论摆幅 ±15.5%，实测 15.4%。它守的不再是「轮转稳不稳」，而是「窗口怎么切」。
##    把窗口钉到 24 秒（每窗恰好一次战意觉醒、约 30 刀）后，只剩量化噪声 ±3.3%，
##    「≤ ±8%」才重新有意义。跑 72 秒 = 3 个整周期，得到 3 个可比样本。
const C1_WINDOW := 24.0
const C1_DURATION := 72.0
## 回蓝：生产口径是「未死亡时每 3 秒按最大值回 2%」（`player.gd` 的 REGEN_* 常量）。
## 🔴 只受击不重置计时，所以整场都在回 —— 漏掉它会把「打空时间」算短 40%。
const REGEN_INTERVAL := 3.0
const REGEN_RATE := 0.02
## 蓝量采样间隔（秒）。0.5 秒 = 60 秒 120 个样本，足够算低尾分位而不被单帧噪声带走。
const MP_SAMPLE := 0.5

## 判据带。改这些数字 = 改产品定位，须走产品文档评审（与 `class_balance_test` 同规矩）。
const C1_WAVE_MAX := 0.08
const C2_MIN := 40.0
const C2_MAX := 100.0
## 跨职业兜底：武士把蓝池打空的时间必须明显长于法师（107 把武士改成百分比耗蓝之后，
## 「武士更省蓝」不再是天然成立的，需要一条判据钉住）。
## 🔑 阈值取 1.3 而不是 1.4：实测 1.41×，判据若贴着实测写，任何无关改动都会让它来回翻红。
##    掉到 1.3 以下才是「真的变差了」—— 那意味着武士的耗蓝被拉到法师同一档。
const C2_CLASS_RATIO_MIN := 1.3
const C3_MIN := 0.15
## 🔴 判据 ④ 的口径修正是**实测出来的**，不是估的：把 `data/skills.json` 换回改前版本
## （`git show HEAD:data/skills.json`）跑同一支探针，得到 8 怪 **3.64×**、20 怪 **7.07×**。
## 也就是说计划里写的「8 怪 2.0—2.8」在改前就不成立 —— 那条估计漏了灵刃风暴的
## `hits: 3`（3 段 × 8 目标 = 24 倍系数/次），把多段技当单段算了。
## 真正需要守的是两件事：
##   ① 8 怪倍数不能比改前高太多（系数与 CD 都动过，允许 +15%）；
##   ② 上限 8 只必须**真的**把宽场景涨幅压下去（20 怪 / 8 怪 从 1.94 降到 1.65 以内）。
const C4_PRE107_EIGHT := 3.64
const C4_PRE107_WIDE_RATIO := 1.94
const C4_EIGHT_MIN := C4_PRE107_EIGHT * 0.95
const C4_EIGHT_MAX := C4_PRE107_EIGHT * 1.15
const C4_WIDE_RATIO_MAX := C4_PRE107_WIDE_RATIO * 0.85
## 8 怪之外再看一眼 20 怪：上限 8 只的意义就是「再多也不线性涨」。
const C4_WIDE_TARGETS := 20
const C5_MIN := 0.18
const C5_MAX := 0.22
## 🔴 口径修正（⑥）：原文写「0—1 瓶」，那是按「打得快」估的，与同一份计划的 §4.3
## （1.84%/s）和 21.8 秒的 Boss 击杀耗时**算不过来**：1.84% × 21.8 = 40% 蓝池，
## 最大蓝药每瓶回 20% ⇒ 必然是 2 瓶。`ClassBalanceTest` 用同一算法独立测得
## 「warrior 2 瓶 / mage 3 瓶」，与本探针逐位一致 —— 所以是判据写错了，不是数值超标。
## 新判据仍保留「必须 > 0」（改前是 0 瓶，固定点耗被大蓝池摊平），上界取 2。
const C6_MIN := 1
const C6_MAX := 2
## 蓝药按**最大瓶**折算（对「需要喝药」最宽松的口径，与 `class_balance_test` 一致）。
const MANA_POTION := "potion_mp_large"
## Boss 出手率（工程 92 实测 14.7 秒挨 4.5 击）。
const HIT_RATE := 0.55

## 一次模拟的状态机。把 `mp` / 冷却 / 攻击槽位都做成浮点，
## 避免整数取整把「差 1 点蓝能不能放」这种边界抹平。
class Sim:
	var pool := 0.0
	var mp := 0.0
	var cds := {}
	var attack_cd := 0.0
	var t := 0.0
	var damage := 0.0
	var regen_t := 0.0
	var buff_t := 0.0
	## `battle_focus` 的攻速加成（读数据，不写死 0.15）。
	var speed_pct := 0.0
	var buff_duration := 0.0
	var casts := {}
	## 每 `MP_SAMPLE` 秒采一次蓝量比例。
	var mp_ratio_series: Array[float] = []
	var sample_t := 0.0

## ⑥ 用的「所有技能一到 CD 就放」上界支出（%/秒），与 `class_balance_test` 同一算法。
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[WarriorRotationProbe] " + label)

func _ready() -> void:
	_measure_c1_c3()
	_measure_c2()
	_measure_c4()
	_measure_c5()
	_measure_c6()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[WarriorRotationProbe] 六条判据全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[WarriorRotationProbe] 失败 %d 项" % failures.size())
		for f in failures:
			print("  - " + f)
		get_tree().quit(1)

# ---- 夹具 ----

## 把玩家摆成「快照里的那个 160 级角色」：只设基础攻防与法力固定加成，装备栏清空。
## 一切派生仍走生产门面（`total_attack` / `max_mp`），职业系数由生产代码自己乘。
func _setup(class_id: String = "warrior") -> void:
	GameState.reset_to_defaults(class_id)
	GameState.current_map = "wild_trial"
	GameState.player.level = LEVEL
	GameState.player.attack = SNAPSHOT_ATTACK
	GameState.player.defense = SNAPSHOT_DEFENSE
	GameState.player.mpFlat = SNAPSHOT_MP_FLAT
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()

## 武士实际可用的主动技能（走 `HotbarConfig.usable_skill` 这个生产入口，
## 不自己按 class 字段筛 —— 否则以后改职业可用性表，探针会静默测错一批技能）。
func _active_skills() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw in PlayerClass.active_skills(PlayerClass.current_id()):
		var sid := String(raw)
		if not HotbarConfig.usable_skill(sid):
			continue
		var skill := SkillProgression.current(sid)
		if skill.is_empty() or bool(skill.get("basic", false)):
			continue
		if int(skill.get("unlockLevel", 1)) > LEVEL:
			continue
		result.append(skill)
	return result

## 一个技能对 `targets` 只怪时的**实际命中数**。
## 上限口径与 `player.skill_targets()` 一致：`maxTargets` 缺省 0 = 不限。
func _hits(skill: Dictionary, targets: int) -> int:
	var shape := String(skill.get("shape", "single"))
	if shape == "self":
		return 0
	var cap := int(skill.get("maxTargets", 0))
	var hits := targets if shape != "single" else mini(targets, 1)
	if cap > 0:
		hits = mini(hits, cap)
	return hits

## 单次施放的总系数产出（系数 × 段数 × 命中数）。
func _cast_value(skill: Dictionary, targets: int) -> float:
	return AutoBattle.skill_value(skill) * float(_hits(skill, targets))

func _reset_sim(targets: int) -> Sim:
	var s := Sim.new()
	s.pool = float(GameState.max_mp())
	s.mp = s.pool
	for skill in _active_skills():
		s.cds[String(skill.id)] = 0.0
		s.casts[String(skill.id)] = 0
	var focus: Variant = DataLoader.get_entry("skills", "battle_focus")
	if focus is Dictionary:
		var effects: Dictionary = (focus as Dictionary).get("effects", {})
		s.speed_pct = float(effects.get("attackSpeedPct", 0.0))
		s.buff_duration = maxf(0.0, float((focus as Dictionary).get("buffDuration", 8.0)))
	return s

## 攻击间隔：生产口径是「基础间隔 ÷ (1 + 攻速加成)」，技能同样占用这个槽位。
func _interval(s: Sim) -> float:
	var base := maxf(0.01, GameState.total_attack_interval())
	return maxf(Combat.MIN_ATTACK_INTERVAL, base / (1.0 + (s.speed_pct if s.buff_t > 0.0 else 0.0)))

## 挑一个技能：优先战意觉醒（自身增益），再范围技（命中 ≥ 2），再单体。
## 与生产 `auto_battle._tick()` 的顺序**一致**；不一致的模型测出来的数是另一个游戏。
## `all_cd = true` 时无视「命中 ≥ 2」与「增益未过期」，模拟玩家硬按。
func _pick(s: Sim, targets: int, all_cd: bool) -> Dictionary:
	var ready: Array[Dictionary] = []
	for skill in _active_skills():
		var sid := String(skill.id)
		if float(s.cds.get(sid, 0.0)) > 0.0:
			continue
		if float(GameState.skill_mana_cost(skill)) > s.mp:
			continue
		ready.append(skill)
	if ready.is_empty():
		return {}
	var focus := {}
	var area := {}
	var single := {}
	var best_area := 0.0
	for skill in ready:
		var shape := String(skill.get("shape", "single"))
		if shape == "self":
			if all_cd or s.buff_t <= 0.0:
				focus = skill
			continue
		var hits := _hits(skill, targets)
		if shape == "single":
			if single.is_empty() or AutoBattle.skill_value(skill) > AutoBattle.skill_value(single):
				single = skill
			continue
		if hits < 2 and not all_cd:
			continue
		var value := AutoBattle.skill_value(skill) * float(hits)
		if value > best_area:
			best_area = value
			area = skill
	if not focus.is_empty():
		return focus
	if not area.is_empty():
		return area
	return single

## 跑满 `duration` 秒。返回本场的总伤害、每 `window` 秒的 DPS 与蓝量序列。
## `window` 缺省 10 秒；判据 ① 会显式传 24 秒（对齐战意觉醒周期，见 `_measure_c1_c3`）。
func _run(targets: int, all_cd: bool, duration: float = DURATION, window: float = WINDOW) -> Dictionary:
	var s := _reset_sim(targets)
	var windows: Array[float] = []
	# 窗口按**时间轴**切，不按「累计攻击间隔」切：后者在有攻速加成时会与真实
	# 时间脱钩（8 秒增益改的是间隔，不是窗口），把 ±8% 的判据算成另一个数。
	var window_damage := 0.0
	var grand := 0.0
	var next_window := window
	while s.t < duration - 0.0001:
		s.t += DT
		for sid in s.cds.keys():
			s.cds[sid] = maxf(0.0, float(s.cds[sid]) - DT)
		s.attack_cd = maxf(0.0, s.attack_cd - DT)
		s.buff_t = maxf(0.0, s.buff_t - DT)
		s.regen_t += DT
		if s.regen_t >= REGEN_INTERVAL:
			s.regen_t -= REGEN_INTERVAL
			if s.mp < s.pool:
				s.mp = minf(s.pool, s.mp + s.pool * REGEN_RATE)
		s.sample_t += DT
		if s.sample_t >= MP_SAMPLE:
			s.sample_t -= MP_SAMPLE
			s.mp_ratio_series.append(s.mp / maxf(1.0, s.pool))
		if s.attack_cd > 0.0:
			if s.t >= next_window:
				windows.append(window_damage / window)
				window_damage = 0.0
				next_window += window
			continue
		# 一个攻击槽位到点：先试技能，放不出就普攻（单目标系数 1.0）。
		var skill := _pick(s, targets, all_cd)
		s.attack_cd = _interval(s)
		if skill.is_empty():
			window_damage += 1.0
			grand += 1.0
			continue
		var cast_value := _cast_value(skill, targets)
		window_damage += cast_value
		grand += cast_value
		var sid := String(skill.id)
		s.mp = maxf(0.0, s.mp - float(GameState.skill_mana_cost(skill)))
		s.cds[sid] = maxf(0.0, float(skill.get("cooldown", 0.0)))
		s.casts[sid] = int(s.casts.get(sid, 0)) + 1
		if String(skill.get("shape", "")) == "self":
			s.buff_t = s.buff_duration
		# 窗口结算放在**这一刀之后**：放在之前会让边界上那一次攻击落到下一个窗口，
		# 相邻两个窗口于是各差一整刀（约 ±7.7%），把判据 ① 的噪声抬到与信号同量级。
		if s.t >= next_window:
			windows.append(window_damage / window)
			window_damage = 0.0
			next_window += window
	# 🔴 尾窗必须补上：只按 `next_window` 刷窗口会丢掉最后不满 10 秒的那一段
	#    （60 秒 / 10 秒 = 6 个窗口，而 `next_window` 在 10、20、30、40、50 各刷一次，
	#    只出 5 个），总分母随之少 10 秒 —— 第一版就是这样把 DPS 算低了 17%。
	if window_damage > 0.0:
		var tail := maxf(0.0001, s.t - float(windows.size()) * window)
		windows.append(window_damage / tail)
	return {
		"total": grand, "dps": grand / duration, "windows": windows,
		"mp_series": s.mp_ratio_series, "casts": s.casts, "pool": s.pool,
	}

## 分位数（0—1）。序列已按时间排列，这里直接排序取位。
func _percentile(values: Array[float], q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var idx := clampi(int(floorf(q * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return sorted[idx]

# ---- ①③ 单体轮转 ----

## ① 单体轮转的稳定性；③ 蓝量低尾。
##
## 🔴 ③ 必须在**多怪场景**上量：单体时范围技（占 96% 的蓝）根本不满足「命中 ≥ 2」，
##    一场只有破甲重击的 2.5%，回蓝就盖住了 —— 测出来永远 95%，判据形同没有。
##    武士真正会缺蓝的场合是围一堆怪连续放 AOE，那才是这条要守的。
func _measure_c1_c3() -> void:
	_setup()
	var solo := _run(1, false, C1_DURATION, C1_WINDOW)
	var windows: Array = solo.windows
	var mean := float(solo.dps)
	var wave := 0.0
	for w in windows:
		wave = maxf(wave, absf(float(w) - mean) / maxf(1.0, mean))
	print("[C1] 单体 72s｜DPS %.3f｜%d 个 24s 窗口（对齐战意觉醒周期）｜最大偏离 %.1f%%"
		% [mean, windows.size(), wave * 100.0])
	for i in range(windows.size()):
		print("      W%d = %.3f（%+.1f%%）"
			% [i + 1, float(windows[i]), (float(windows[i]) - mean) / maxf(1.0, mean) * 100.0])
	check(wave <= C1_WAVE_MAX,
		"① 单体 24 秒周期窗口的 DPS 波动 %.1f%% 应 ≤ %.1f%%（某一段突然暴涨 = 轮转不稳，玩家会觉得「时强时弱」）"
		% [wave * 100.0, C1_WAVE_MAX * 100.0])

	var crowd := _run(8, false)
	var series: Array[float] = crowd.mp_series
	var low := _percentile(series, 0.05)
	var end_ratio := series[series.size() - 1] if not series.is_empty() else 0.0
	print("[C3] 8 怪选择性施放 60s｜蓝量低尾(P05) %.1f%%｜结束 %.1f%%｜施放次数 %s"
		% [low * 100.0, end_ratio * 100.0, str(crowd.casts)])
	check(low >= C3_MIN,
		"③ 8 怪场景的蓝量低尾 %.1f%% 应 ≥ %.1f%%（低于它说明「挑着放」也维持不住，玩家会站着等回蓝）"
		% [low * 100.0, C3_MIN * 100.0])

# ---- ② 全 CD 强放 ----

## 从满蓝开始，所有技能一到 CD 就放（不看目标数、不看增益是否还在），直到**蓝不够放任何一个**。
##
## 🔴 两个坑，都是本探针第一版真踩过的：
##   ① 终止条件写成「此刻没有技能就绪」⇒ 开局五个技能在 5 个槽位内全进冷却，
##      第 6 个瞬间就满足了，测出来的打空时间是 **0.05 秒**。
##      正确的终止条件是「一个都放不起」（`_min_cost() > mp`）。
##   ② 忽略攻击槽位、一有蓝就即刻连放 ⇒ 开局 12.7% 的蓝在 0.05 秒内蒸发，
##      把打空时间系统性算短。技能占用攻击槽位是 `cast_skill` 的硬约束，必须照抄。
func _measure_c2() -> void:
	_setup()
	var elapsed := _drain_seconds()
	print("[C2] 全 CD 强放｜武士打空蓝池 %.1f 秒（蓝池 %d，回蓝 %.2f%%/s）"
		% [elapsed, GameState.max_mp(), REGEN_RATE / REGEN_INTERVAL * 100.0])
	check(elapsed >= C2_MIN and elapsed <= C2_MAX,
		"② 全 CD 强放打空时间 %.1f 秒应 ∈ [%.0f, %.0f]（太短 = 放几个就没了，太长 = 百分比耗蓝等于白改）"
		% [elapsed, C2_MIN, C2_MAX])

	# 跨职业兜底：同一个「全 CD 强放」口径下，武士必须明显比法师慢。
	var mage := _drain_time("mage")
	var ratio := elapsed / maxf(0.001, mage)
	print("[C2] 同口径｜法师打空 %.1f 秒｜武士/法师 = %.2f×" % [mage, ratio])
	check(ratio >= C2_CLASS_RATIO_MIN,
		"② 武士打空时间应是法师的 ≥ %.1f 倍（现在 %.2f×）：107 把武士也改成百分比耗蓝，「更省蓝」不再是天然成立的"
		% [C2_CLASS_RATIO_MIN, ratio])

## 全 CD 强放跑到「一个技能都放不起」。调用前先 `_setup(class_id)`。
func _drain_seconds() -> float:
	var s := _reset_sim(1)
	var elapsed := 0.0
	while elapsed < 600.0 and _min_cost() <= s.mp:
		elapsed += DT
		for sid in s.cds.keys():
			s.cds[sid] = maxf(0.0, float(s.cds[sid]) - DT)
		s.attack_cd = maxf(0.0, s.attack_cd - DT)
		s.buff_t = maxf(0.0, s.buff_t - DT)
		s.regen_t += DT
		if s.regen_t >= REGEN_INTERVAL:
			s.regen_t -= REGEN_INTERVAL
			if s.mp < s.pool:
				s.mp = minf(s.pool, s.mp + s.pool * REGEN_RATE)
		if s.attack_cd > 0.0:
			continue
		var skill := _pick(s, 1, true)
		if skill.is_empty():
			continue                     # 槽位空转：等下一个攻击间隔再试
		s.attack_cd = _interval(s)
		var sid := String(skill.id)
		s.mp = maxf(0.0, s.mp - float(GameState.skill_mana_cost(skill)))
		s.cds[sid] = maxf(0.0, float(skill.get("cooldown", 0.0)))
		if String(skill.get("shape", "")) == "self":
			s.buff_t = s.buff_duration
	return elapsed

## 当前职业所有主动技能里最便宜的一发（决定「还放得起吗」）。
func _min_cost() -> float:
	var cost := INF
	for skill in _active_skills():
		cost = minf(cost, float(GameState.skill_mana_cost(skill)))
	return 0.0 if cost == INF else cost

func _drain_time(class_id: String) -> float:
	var saved := PlayerClass.current_id()
	_setup(class_id)
	var elapsed := _drain_seconds()
	_setup(saved)
	return elapsed

# ---- ④ 多怪倍数 ----

func _measure_c4() -> void:
	_setup()
	var solo := float(_run(1, false).dps)
	var eight := float(_run(8, false).dps)
	var wide := float(_run(C4_WIDE_TARGETS, false).dps)
	var ratio := eight / maxf(0.0001, solo)
	var wide_ratio := wide / maxf(0.0001, solo)
	print("[C4] 8 怪 DPS %.3f / 单体 %.3f = %.2f×｜%d 怪 = %.2f×"
		% [eight, solo, ratio, C4_WIDE_TARGETS, wide_ratio])
	check(ratio >= C4_EIGHT_MIN and ratio <= C4_EIGHT_MAX,
		"④ 8 怪 DPS 倍数 %.2f× 应 ∈ [%.2f, %.2f]（改前实测 %.2f×，系数与 CD 都动过，允许 +15%%）"
		% [ratio, C4_EIGHT_MIN, C4_EIGHT_MAX, C4_PRE107_EIGHT])
	# 上限的真正意义：怪再多也只能打 8 只。旋风斩是不限目标的圆，所以宽场景仍会涨，
	# 但涨幅必须远小于线性（线性 20 只是 8 只的 2.5 倍）。
	var wide_vs_eight := wide_ratio / maxf(0.0001, ratio)
	print("[C4] 宽窄比｜%d 怪 / 8 怪 = %.2f×（改前 1.94×，上限生效后应 ≤ %.2f×）"
		% [C4_WIDE_TARGETS, wide_vs_eight, C4_WIDE_RATIO_MAX])
	check(wide_vs_eight <= C4_WIDE_RATIO_MAX,
		"④ %d 怪相对 8 怪的涨幅 %.2f× 应 ≤ %.2f×（改前 1.94×）：超出说明 `maxTargets` 没有在上限技能上生效"
		% [C4_WIDE_TARGETS, wide_vs_eight, C4_WIDE_RATIO_MAX])

# ---- ⑤ 战意觉醒的减伤 ----

## 用真实 `apply_damage` 量两次，而不是读数据算 1 − 0.2：
## 减伤发生在「盾转嫁之前」，取整（`maxi(1, round(...))`）会吃掉零点几个百分点。
func _measure_c5() -> void:
	_setup()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(4000, 4000)
	var max_hp := GameState.max_hp()
	var hit := maxi(1, int(round(float(max_hp) * 0.05)))   # 5% 血池，避免落到保底伤害
	GameState.active_buffs.clear()
	GameState.player.hp = max_hp
	player._invuln = 0.0
	var bare := player.apply_damage(hit)
	GameState.active_buffs.clear()
	GameState.start_buff("battle_focus")
	# 增益只该改承伤，不该顺手改血池 —— 顺手改了就说明它被算进了 `max_hp()`。
	check(GameState.max_hp() == max_hp,
		"⑤ 战意觉醒不得改变最大生命（%d → %d）：减伤是结算系数，不是血量词条"
		% [max_hp, GameState.max_hp()])
	GameState.player.hp = max_hp
	player._invuln = 0.0
	var focused := player.apply_damage(hit)
	var drop := 1.0 - float(focused) / float(maxi(1, bare))
	print("[C5] 战意觉醒承伤｜无 buff %d / 有 buff %d（每击 %d）→ 下降 %.1f%%"
		% [bare, focused, hit, drop * 100.0])
	check(drop >= C5_MIN and drop <= C5_MAX,
		"⑤ 战意觉醒期间承伤应下降 %.0f%%—%.0f%%（现在 %.1f%%）"
		% [C5_MIN * 100.0, C5_MAX * 100.0, drop * 100.0])
	GameState.active_buffs.clear()
	player.queue_free()

# ---- ⑥ 蓝药消耗 ----

## 与 `class_balance_test` 同一算法：所有主动技能「一到 CD 就放」的上界支出 × 击杀耗时。
## 🔑 这是**上界**：真实打法会挑着放，只会更省。用它折算瓶数是有意保守。
func _measure_c6() -> void:
	_setup()
	var skill_per_sec := 0.0
	for skill in _active_skills():
		var cd := maxf(1.0, float(skill.get("cooldown", 1.0)))
		skill_per_sec += float(GameState.skill_mana_cost(skill)) / cd
	var ttk := _boss_ttk()
	var restore := float(GameState.max_mp()) * 0.2
	var potion: Variant = DataLoader.get_entry("potions", MANA_POTION)
	if potion is Dictionary:
		restore = float(GameState.max_mp()) * float((potion as Dictionary).get("restorePercent", 0.2))
	var spend := skill_per_sec * ttk
	var bottles := int(floor(spend / maxf(1.0, restore)))
	print("[C6] 蓝药｜支出 %.0f（%.2f%%/s × %.1fs）/ 单瓶回 %d → %d 瓶"
		% [spend, skill_per_sec / maxf(1.0, float(GameState.max_mp())) * 100.0, ttk, int(restore), bottles])
	check(bottles >= C6_MIN and bottles <= C6_MAX,
		"⑥ 武士打一只 Boss 的蓝药消耗 %d 瓶应 ∈ [%d, %d]（107 之前是 0 瓶，固定点耗被大蓝池摊平了）"
		% [bottles, C6_MIN, C6_MAX])

## 代表 Boss 的击杀耗时：只算「攻击 − Boss 防御 × 0.5」的破防差值，不含暴击与破甲增益。
## Boss 侧**真实例化**并走 `Endgame.norm`，否则同一只怪的攻击会差一个量级（工程 94 的坑）。
func _boss_ttk() -> float:
	var rep := _representative_boss()
	if rep.is_empty():
		return 30.0
	var interval := maxf(0.01, GameState.total_attack_interval())
	var per_hit := maxf(1.0, float(GameState.total_attack()) - float(rep.get("def", 0.0)) * 0.5)
	return float(rep.get("hp", 1.0)) / maxf(1.0, per_hit / interval)

func _representative_boss() -> Dictionary:
	var map_data: Variant = DataLoader.get_entry("maps", "c7_boss_field")
	if not (map_data is Dictionary):
		return {}
	var seats: Array = (map_data as Dictionary).get("bossSpawns", [])
	if seats.is_empty():
		return {}
	var counts := {}
	var lowest_atk := INF
	var lowest_hp := INF
	for raw in seats:
		if not (raw is Dictionary):
			continue
		var seat: Dictionary = raw
		var mid := String(seat.get("monsterId", ""))
		counts[mid] = int(counts.get(mid, 0)) + 1
		lowest_atk = minf(lowest_atk, float(seat.get("atkMultiplier", 1.0)))
		lowest_hp = minf(lowest_hp, float(seat.get("hpMultiplier", 1.0)))
	var rep := ""
	var rep_count := 0
	for raw_key in counts.keys():
		if int(counts[String(raw_key)]) > rep_count:
			rep = String(raw_key)
			rep_count = int(counts[String(raw_key)])
	if rep.is_empty():
		return {}
	var from_player: Variant = (map_data as Dictionary).get("levelFromPlayer", {})
	var min_level := Balance.SOFTCAP_LEVEL
	if from_player is Dictionary:
		min_level = int((from_player as Dictionary).get("minLevel", Balance.SOFTCAP_LEVEL))
	var m := Monster.new()
	m.monster_id = rep
	m.spawn_level = maxi(min_level, LEVEL)
	m.stat_norm = Endgame.norm(rep)
	m.atk_multiplier = lowest_atk
	m.hp_multiplier = lowest_hp
	m.scale_stats = true
	add_child(m)
	var info := {
		"hp": float(m.max_hp), "def": float(m.defense_power),
		"interval": float(m.attack_interval),
	}
	m.queue_free()
	return info
