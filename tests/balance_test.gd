extends Node
## M10-0 数值地基契约（工程 40 §5）：三条曲线、两段基线、等级 / 属性上界、读档幂等对齐。
## 目的：把「1–60 逐位不变」与「1000 级存档必须可读」两条底线钉死——
## 曲线或上界一旦被改错，这里必须红，而不是等玩家满级后才发现号读不回来。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[BalanceTest] " + label)

func _near(actual: float, expected: float, label: String) -> void:
	check(is_equal_approx(actual, expected), "%s（实际 %f，期望 %f）" % [label, actual, expected])

func _ready() -> void:
	_test_scale()
	_test_curves()
	_test_legacy_range()
	_test_caps()
	_test_save_roundtrip_1000()
	_test_level_up_cross_softcap()
	_test_align_idempotent()
	_test_ceiling_guard()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[BalanceTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[BalanceTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

## S(d) = 1 + 0.12d + 0.0022·max(0, d−12)²；二次段从 d = 13 起（存量最大 d = 9，故不受影响）。
func _test_scale() -> void:
	_near(Balance.scale(0), 1.0, "S(0) 应为 1.0")
	_near(Balance.scale(10), 2.2, "S(10) 应为 2.2（10 级差线性）")
	_near(Balance.scale(12), 2.44, "S(12) 应为 2.44（二次段边界）")
	_near(Balance.scale(13), 2.5622, "S(13) 应为 2.5622（二次段首级）")
	_near(Balance.scale(40), 7.5248, "S(40) 应为 7.5248")
	_near(Balance.scale(140), 53.8448, "S(140) 应为 53.8448")
	_near(Balance.scale(940), 2008.4048, "S(940) 应为 2008.4048")
	_near(Balance.scale(-5), 1.0, "负等级差按 0 处理")

## §5.2 逐值断言表：存量段 + 新曲线段。
func _test_curves() -> void:
	var xp_cases := {1: 100, 10: 3981, 30: 23088, 59: 68134, 60: 69991,
		61: 74023, 70: 116439, 100: 348677, 500: 29555639, 1000: 184239545}
	for level in xp_cases.keys():
		check(Balance.xp_to_next(int(level)) == int(xp_cases[level]),
			"E(%d) 应为 %d，实际 %d" % [int(level), int(xp_cases[level]), Balance.xp_to_next(int(level))])

	_near(Balance.kills_per_level(60), 12.0, "K(60) 应为 12")
	_near(Balance.kills_per_level(100), 19.2, "K(100) 应为 19.2")
	_near(Balance.kills_per_level(1000), 181.2, "K(1000) 应为 181.2")

	var boss_cases := {60: 5833, 100: 18160, 1000: 1016775}
	for level in boss_cases.keys():
		check(Balance.boss_xp(int(level)) == int(boss_cases[level]),
			"boss_xp(%d) 应为 %d，实际 %d" % [int(level), int(boss_cases[level]), Balance.boss_xp(int(level))])

	var atk_cases := {1: 12, 60: 130, 61: 146, 100: 978, 1000: 261093}
	for level in atk_cases.keys():
		check(Balance.base_attack(int(level)) == int(atk_cases[level]),
			"base_attack(%d) 应为 %d，实际 %d" % [int(level), int(atk_cases[level]), Balance.base_attack(int(level))])

	var def_cases := {1: 5, 60: 64, 61: 72, 100: 482, 1000: 128538}
	for level in def_cases.keys():
		check(Balance.base_defense(int(level)) == int(def_cases[level]),
			"base_defense(%d) 应为 %d，实际 %d" % [int(level), int(def_cases[level]), Balance.base_defense(int(level))])

## §5.3 存量不变：1..60 全量与旧公式逐位比对（180 条）。这是本批最重要的断言。
func _test_legacy_range() -> void:
	var xp_diff := 0
	var atk_diff := 0
	var def_diff := 0
	for level in range(1, 61):
		if Balance.xp_to_next(level) != int(round(100.0 * pow(float(level), 1.6))):
			xp_diff += 1
		if Balance.base_attack(level) != 12 + (level - 1) * 2:
			atk_diff += 1
		if Balance.base_defense(level) != 5 + (level - 1):
			def_diff += 1
	check(xp_diff == 0, "1–60 经验必须与旧公式 round(100·L^1.6) 逐位一致，差异 %d 级" % xp_diff)
	check(atk_diff == 0, "1–60 基线攻必须等于 12+2(L−1)，差异 %d 级" % atk_diff)
	check(def_diff == 0, "1–60 基线防必须等于 5+(L−1)，差异 %d 级" % def_diff)

## 等级 / 属性上界：联动关系 + 真存档可读性（N-1 必须有牙：断言的是"能不能存读"，不是常量本身）。
func _test_caps() -> void:
	check(GameState.PLAYER_LEVEL_CAP == 9999, "等级上界应为 9999")
	check(int(GameState.PLAYER_STAT_CAP) == 99999999, "属性上界应为 99,999,999")
	check(Balance.base_attack(GameState.PLAYER_LEVEL_CAP) < int(GameState.PLAYER_STAT_CAP),
		"等级上限处的基础攻 %d 必须低于属性上限 %d（否则 1915 级会撞 cap）"
			% [Balance.base_attack(GameState.PLAYER_LEVEL_CAP), int(GameState.PLAYER_STAT_CAP)])

	# 旧上限 999 的档仍必须可读（不能为了抬上限而破旧档）。
	_write_state_at(999)
	check(SaveManager._is_valid_save(SaveManager._collect()),
		"999 级存档仍应可读，拒绝原因：%s" % SaveManager._last_invalid_reason)

	# P-14：1000 级（旧上限之上）必须能存能读，否则「整份存档被判无效」。
	_write_state_at(1000)
	check(SaveManager._is_valid_save(SaveManager._collect()),
		"1000 级存档应可读（P-14），拒绝原因：%s" % SaveManager._last_invalid_reason)

	# 护栏边界：9999 级本身合法。
	_write_state_at(9999)
	check(SaveManager._is_valid_save(SaveManager._collect()),
		"9999 级存档应可读（上界含端点），拒绝原因：%s" % SaveManager._last_invalid_reason)

	# 越界必须被拦（否则护栏形同虚设）。
	GameState.player.level = GameState.PLAYER_LEVEL_CAP + 1
	GameState.player.hp = GameState.max_hp()
	check(not SaveManager._is_valid_save(SaveManager._collect()),
		"10000 级应被拒收，实际放行")

## §6.2 第二条：真文件能存能读（JSON 往返会把整数变成 float，`_whole` 必须仍然放行）。
func _test_save_roundtrip_1000() -> void:
	_write_state_at(1000)
	check(SaveManager.save_slot(3, true), "1000 级档应能写盘（P-14 的另一半）")
	var res: Dictionary = SaveManager.read_slot(3)
	check(bool(res.get("ok", false)), "1000 级档应能读回：%s" % str(res.get("message", "")))
	var data: Dictionary = res.get("data", {})
	var saved: Dictionary = data.get("player", {})
	check(int(saved.get("level", 0)) == 1000, "读回的等级应为 1000，实际 %d" % int(saved.get("level", 0)))
	check(int(saved.get("attack", 0)) == Balance.base_attack(1000),
		"读回的基础攻应保持曲线值 978，实际 %d" % int(saved.get("attack", 0)))

## 把运行态摆到某一等级：攻防取曲线值，HP / MP 补满（读数要自洽，否则先被其他校验拦下）。
func _write_state_at(level: int) -> void:
	GameState.reset_to_defaults()
	GameState.player.level = level
	GameState.player.attack = Balance.base_attack(level)
	GameState.player.defense = Balance.base_defense(level)
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()

## 升级改道：60 之内逐级 +2/+1 不变，跨过 60 立刻抬到曲线基线。
func _test_level_up_cross_softcap() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 59
	GameState.player.attack = 128
	GameState.player.defense = 63
	GameState.player.hp = GameState.max_hp()
	GameState._level_up()
	check(int(GameState.player.level) == 60, "59→60 等级应 +1")
	check(int(GameState.player.attack) == 130, "59→60 攻应 +2（实际 %d）" % int(GameState.player.attack))
	check(int(GameState.player.defense) == 64, "59→60 防应 +1（实际 %d）" % int(GameState.player.defense))

	GameState.player.level = 60
	GameState.player.attack = 130
	GameState.player.defense = 64
	GameState.player.hp = GameState.max_hp()
	GameState._level_up()
	check(int(GameState.player.level) == 61, "60→61 等级应 +1")
	check(int(GameState.player.attack) == 146,
		"60→61 攻应抬到曲线基线 146（实际 %d）" % int(GameState.player.attack))
	check(int(GameState.player.defense) == 72,
		"60→61 防应抬到曲线基线 72（实际 %d）" % int(GameState.player.defense))

## 读档幂等对齐：旧档（线性成长）读入后抬到曲线基线；再读一次结果不变；HP 按比例结转不补满。
func _test_align_idempotent() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 100
	# 刻意给一个"低于曲线"的攻防（旧档线性成长到 L100 是 12+99×2 = 210，
	# 这里取更小的值，用来验证 maxi 只升不降、且不会把已有更高值压回去）。
	GameState.player.attack = 128
	GameState.player.defense = 63
	GameState.player.hp = maxi(1, GameState.max_hp() / 2)
	GameState.player.mp = 10
	var ratio := float(GameState.player.hp) / float(GameState.max_hp())

	SaveManager.apply_to_game_state(SaveManager._collect())
	check(int(GameState.player.attack) == 978,
		"L100 的基线攻应为 978（实际 %d）—— align_baseline_stats 未生效或被回退" % int(GameState.player.attack))
	check(int(GameState.player.defense) == 482,
		"L100 的基线防应为 482（实际 %d）" % int(GameState.player.defense))
	check(int(GameState.player.hp) < GameState.max_hp(), "对齐不得把 HP 补满（读档时可能正残血）")
	check(absf(float(GameState.player.hp) - float(GameState.max_hp()) * ratio) <= 1.0,
		"对齐后 HP 应按比例结转：实际 %d，期望约 %.1f" % [int(GameState.player.hp), float(GameState.max_hp()) * ratio])

	var attack_once := int(GameState.player.attack)
	var defense_once := int(GameState.player.defense)
	var hp_once := int(GameState.player.hp)
	SaveManager.apply_to_game_state(SaveManager._collect())
	check(int(GameState.player.attack) == attack_once and int(GameState.player.defense) == defense_once,
		"重复读档不得继续抬升攻防（幂等）")
	check(absi(int(GameState.player.hp) - hp_once) <= 1, "重复读档 HP 漂移不得超过 1")

## 9999 护栏：经验与基线在新曲线上单调递增且在数值类型内；到顶后 add_xp 不再升级。
func _test_ceiling_guard() -> void:
	var prev_xp := 0
	var prev_atk := 0
	var monotonic := true
	for level in [1000, 2000, 5000, 9999]:
		var xp_now: int = Balance.xp_to_next(level)
		var atk_now: int = Balance.base_attack(level)
		if xp_now <= prev_xp or atk_now <= prev_atk:
			monotonic = false
		prev_xp = xp_now
		prev_atk = atk_now
	check(monotonic, "1000→9999 的经验与基线攻必须单调递增")
	check(Balance.xp_to_next(9999) > 0 and Balance.xp_to_next(9999) < 9223372036854775807,
		"E(9999) 必须落在 int64 内，实际 %d" % Balance.xp_to_next(9999))

	_write_state_at(9999)
	GameState.player.xp = 0
	GameState.add_xp(Balance.xp_to_next(GameState.PLAYER_LEVEL_CAP))
	check(int(GameState.player.level) == GameState.PLAYER_LEVEL_CAP,
		"到顶后 add_xp 不得越过等级上界（实际 %d）" % int(GameState.player.level))
	check(int(GameState.player.xp) >= Balance.xp_to_next(GameState.PLAYER_LEVEL_CAP),
		"到顶后经验仍应累积，不得静默丢弃")
