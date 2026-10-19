extends Node
## M10-9 金币产出与重铸频率（工程 50 §4.2）：6 组用例。
##
## 三条最值钱的断言：
## 1. **用例 3 是 D-17 的验收原文**（每小时 5–9 次），而产品 §6.1 的产出表漏算了
##    品质倍率与传说件 —— 所以这条必须用**真实掉落 + 真实售价**跑，不能拿表里的 6,300 反推。
## 2. **用例 4 盯「参数真接线」** —— 费用抽到 `endgame.json` 之后，最可能的错是
##    「改了 json 但代码写死」。只断 `cost()` 数值不够，必须让**频率**跟着动。
## 3. **用例 6 盯「金币不缩放」** —— 回收价按 D-15 涨 19.8 倍，但单只金币掉落必须恒在
##    3,000–3,400。一旦有人顺手让金币跟着 S 涨，`GOLD_CAP` 会在百来小时内被打满。

## 产品 §6.1 / §2.1 的统一核算口径：每小时 30 只（= 120s/只，两处已对齐）。
const KILLS_PER_HOUR := 30
## D-17 的目标区间。
const RATE_MIN := 5.0
const RATE_MAX := 9.0

var failures: Array[String] = []
var _stats: Dictionary = {}

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[EconomyTest] " + label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _ready() -> void:
	GameState.reset_to_defaults()
	for lv in [60, 70, 100, 1000]:
		_stats[lv] = _measure(lv, 500)
	_test_single_kill_output()
	_test_d15_ratio()
	_test_reforge_rate()
	_test_params_wired()
	_test_gold_cap()
	_test_gold_not_scaled()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[EconomyTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[EconomyTest] 失败 %d 项 ❌" % failures.size())
		get_tree().quit(1)

# ---- 采集：真实掉落表 + 真实回收价 ----

## 返回 `{gold, equip, other, total}`（均为「每只」均值）。`other` 是药水 / 如意，不计入总产出。
func _measure(level: int, samples: int) -> Dictionary:
	var r := _rng(7000 + level)
	var gold_sum := 0
	var equip_sum := 0
	var other_sum := 0
	for _i in range(samples):
		var rows: Array = Loot.roll("DT_C7_Arena_Boss", r, "c6_boss03", level)
		for row in rows:
			if not row is Dictionary:
				continue
			var d: Dictionary = row
			match String(d.get("kind", "")):
				"coin":
					gold_sum += int(d.get("gold", 0))
				"equip":
					equip_sum += Shop.sell_price(d)
				_:
					other_sum += Shop.sell_price(d)
	var n := float(maxi(1, samples))
	return {
		"gold": float(gold_sum) / n,
		"equip": float(equip_sum) / n,
		"other": float(other_sum) / n,
		"total": float(gold_sum + equip_sum) / n,
	}

## 每小时可重铸次数 = 单只产出 × 30 ÷ 当前重铸费。
func _rate(level: int) -> float:
	var per_kill := float((_stats[level] as Dictionary).get("total", 0.0))
	var fee := Reforge.cost(level)
	if fee <= 0:
		return -1.0
	return per_kill * float(KILLS_PER_HOUR) / float(fee)

# ---- 1) 单只产出（L60 三点）----

func _test_single_kill_output() -> void:
	var s: Dictionary = _stats[60]
	var gold := float(s.get("gold", 0.0))
	var equip := float(s.get("equip", 0.0))
	var total := float(s.get("total", 0.0))
	check(gold >= 3150.0 and gold <= 3250.0,
		"L60 单只金币应 ≈ 3,200（3,150–3,250），实际 %.0f" % gold)
	check(equip >= 5500.0 and equip <= 6300.0,
		"L60 单只装备回收应 ≈ 5,894（5,500–6,300），实际 %.0f" % equip)
	check(absf(total - 9088.0) / 9088.0 < 0.05,
		"L60 单只总产出应 ≈ 9,088（±5%%），实际 %.0f" % total)

# ---- 2) D-15 缩放真接线（L1000 / L60 ≈ 19.8）----

func _test_d15_ratio() -> void:
	var base := float((_stats[60] as Dictionary).get("equip", 0.0))
	var top := float((_stats[1000] as Dictionary).get("equip", 0.0))
	check(base > 0.0, "L60 装备回收应大于 0")
	var ratio := top / maxf(1.0, base)
	check(absf(ratio - 19.8) / 19.8 < 0.03,
		"L1000 / L60 装备回收应 ≈ 19.8（D-15），实际 %.2f" % ratio)

# ---- 3) 四档重铸频率必须落在 5–9 次/小时（D-17 验收原文）----

func _test_reforge_rate() -> void:
	for lv in [60, 70, 100, 1000]:
		var rate := _rate(lv)
		check(rate >= RATE_MIN, "L%d 每小时重铸次数应 ≥ %.1f，实际 %.2f" % [lv, RATE_MIN, rate])
		check(rate <= RATE_MAX, "L%d 每小时重铸次数应 ≤ %.1f，实际 %.2f" % [lv, RATE_MAX, rate])

# ---- 4) 参数接线：改 json 必须改频率 ----

func _test_params_wired() -> void:
	var cfg: Dictionary = DataLoader.get_table("endgame")
	var reforge: Dictionary = cfg.get("reforge", {})
	var original_base := int(reforge.get("baseGold", 0))
	var original_factor := float(reforge.get("levelFactor", 0.0))
	var base_rate := _rate(60)
	reforge["baseGold"] = 800
	check(Reforge.cost(60) == 84000, "baseGold 改成 800 后 L60 费用应为 84,000，实际 %d" % Reforge.cost(60))
	var expensive := _rate(60)
	check(expensive < base_rate * 0.7,
		"费用涨 60%% 后频率应明显下降（%.2f → %.2f，写死常量即红）" % [base_rate, expensive])
	reforge["baseGold"] = original_base
	reforge["levelFactor"] = 0.0
	var flat := _rate(1000)
	check(flat > 15.0,
		"levelFactor 归零后 L1000 频率应 > 15（漏乘 levelFactor 即红），实际 %.2f" % flat)
	reforge["levelFactor"] = original_factor
	check(absf(_rate(60) - base_rate) < 0.01, "还原参数后频率应回到 %.2f" % base_rate)

# ---- 5) GOLD_CAP 不能被击穿（>200 小时）----

func _test_gold_cap() -> void:
	var cap := float(GameState.GOLD_CAP)
	for lv in [60, 1000]:
		var per_kill := float((_stats[lv] as Dictionary).get("total", 0.0))
		var hours := cap / (per_kill * float(KILLS_PER_HOUR))
		check(hours > 200.0, "L%d 打满 GOLD_CAP 应 > 200h，实际 %.0fh" % [lv, hours])

# ---- 6) 金币不缩放（L1000 与 L60 同区间）----

func _test_gold_not_scaled() -> void:
	for lv in [100, 1000]:
		var gold := float((_stats[lv] as Dictionary).get("gold", 0.0))
		check(gold >= 3150.0 and gold <= 3250.0,
			"L%d 单只金币应仍在 3,150–3,250（金币不缩放），实际 %.0f" % [lv, gold])
