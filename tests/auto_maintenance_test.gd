extends Node
## 工程 95：挂机自动维护（自动修复 + 自动四金合紫）契约。
##
## 这两条流程的危险是「静默」的：倍率配错、阈值判反、漏金币校验、误吃 12 星金装 ——
## 游戏都能跑、能挂机、不报错，玩家只会在某天发现「金币少了」或「12 星金装没了」。
## 所以断言一律压在**结果**上（耐久数值 / 金币实扣 / 背包件数），不看函数返回值就完事。
##
## 数值口径：`Durability` 的阈值、磨损、费用都**从配置派生**，不写死 800 / 12 / 0.2 ——
## 写死的话调 JSON 后测试会静默失效（工程 08 第 35 条）。

const WEAPON := "c6_equip_weapon"
const GOLD_TIER := 61          # 十级档起点；用例里造料与产物都按它对齐
## 🔴 产品红线（用户 2026-10-23 拍板），**故意不复用** `Durability.auto_repair_fee_rate()`
## 当期望值：复用被测常量会让「json 悄悄改成 1.0」也照样绿（工程 08 第 37 条）。
## 改这两个数 = 改产品定价，必须同时改这里，不能只改 json。
const EXPECTED_FEE_RATE := 1.5
const EXPECTED_FEE_SHARE := 0.5

var failures: Array[String] = []
var _rng := RandomNumberGenerator.new()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[AutoMaintenanceTest] " + label)

func _ready() -> void:
	_rng.seed = 20261023
	_test_repair_triggers_below_threshold()
	_test_repair_skips_above_threshold()
	_test_repair_fee_ratio()
	_test_repair_worn_only()
	_test_repair_insufficient_gold()
	_test_forge_success()
	_test_forge_too_few()
	_test_forge_skips_starred()
	_test_forge_same_tier()
	_test_smithy_stays_free()
	_test_forge_insufficient_gold()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[AutoMaintenanceTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[AutoMaintenanceTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 夹具 ----

## 每个用例都从干净状态起：开关全开、自动战斗开、金币管够。
## 🔑 `auto_battle_on` 必须为真，否则 `auto_repair_enabled()` / `auto_forge_enabled()`
##    会因 Q1（只在挂机时生效）直接返回 false，用例会全绿但什么也没验到。
func _reset() -> void:
	GameState.reset_to_defaults()
	GameState.auto_battle_on = true
	GameState.settings["autoRepairEquip"] = true
	GameState.settings["autoForgeGold"] = true
	GameState.gold = 10000000

## 造一件可穿戴装备；`durability < 0` 表示不写字段（= 满耐久，旧档语义）。
func _equip(level: int, quality: String, star: int = 0, durability: int = -1) -> Dictionary:
	var item := ItemFactory.make_equip_dynamic(WEAPON, level, quality, _rng)
	item["star"] = star
	if durability >= 0:
		item["durability"] = durability
	return item

func _worn_durability() -> int:
	return Durability.current(GameState.equipment["weapon"])

# ---- 用例 ----

## 用例 1：耐久 15%（< 20%）→ 击杀一次后回满，且金币**实际减少**。
func _test_repair_triggers_below_threshold() -> void:
	_reset()
	var maximum := Durability.max_durability()
	GameState.equipment["weapon"] = _equip(138, "legendary", 12, int(maximum * 0.15))
	var gold_before := GameState.gold
	GameState.wear_equipment("boss")
	check(_worn_durability() == maximum,
		"用例 1：耐久 15%% 击杀一次应自动修满，实际 %d / %d" % [_worn_durability(), maximum])
	check(GameState.gold < gold_before,
		"用例 1：自动修复必须真扣金币（只断返回值会漏掉「免费修」），前后 %d → %d"
			% [gold_before, GameState.gold])

## 用例 2：耐久 30%（> 20%）→ 击杀后零花费，耐久只减一个磨损量。
## `>` 写成 `>=` 会把「刚好 20%」也当触发点，这条用例专门夹住边界。
func _test_repair_skips_above_threshold() -> void:
	_reset()
	var maximum := Durability.max_durability()
	var start := int(maximum * 0.3)
	GameState.equipment["weapon"] = _equip(138, "legendary", 12, start)
	var gold_before := GameState.gold
	GameState.wear_equipment("boss")
	var wear := Durability.wear_per_kill("boss")
	check(GameState.gold == gold_before,
		"用例 2：未跌破阈值不应扣钱，实际 %d → %d" % [gold_before, GameState.gold])
	check(_worn_durability() == start - wear,
		"用例 2：未跌破阈值只应磨损 %d 点（%d → %d），实际 %d"
			% [wear, start, start - wear, _worn_durability()])
	# 边界：刚好等于阈值也不修（严格小于）
	GameState.equipment["weapon"]["durability"] = int(maximum * Durability.auto_repair_threshold())
	check(GameState.auto_repair_pending() == 0,
		"用例 2：耐久恰好等于阈值时不应触发（严格小于），待修件数 %d"
			% GameState.auto_repair_pending())

## 用例 3：费用比例 —— 同一件 0 耐久，自动路径 == round(铁匠价 × 1.5)。
## 倍率从 JSON 派生，不写死 1.5；写死会在调 `autoRepair.feeRate` 后静默失效。
func _test_repair_fee_ratio() -> void:
	_reset()
	# 配置层：先确认 JSON 就是产品价（否则下面的结果层断言会跟着「坏常量」一起绿）
	var configured := Durability.auto_repair_fee_rate()
	check(is_equal_approx(configured, EXPECTED_FEE_RATE),
		"用例 3：autoRepair.feeRate 应为 %.2f（产品红线），实际 %.2f"
			% [EXPECTED_FEE_RATE, configured])
	GameState.equipment["weapon"] = _equip(138, "legendary", 12, 0)
	var manual := GameState.repair_equipment(1.0)
	check(bool(manual.get("ok", false)),
		"用例 3：铁匠 1.0× 基准价应可算出，实际 %s" % str(manual))
	GameState.equipment["weapon"]["durability"] = 0
	var auto := GameState.try_auto_repair()
	check(bool(auto.get("ok", false)),
		"用例 3：自动修复应成功，实际 %s" % str(auto))
	var expected := int(round(float(manual.get("cost", 0)) * EXPECTED_FEE_RATE))
	check(int(auto.get("cost", -1)) == expected,
		"用例 3：自动修复应为铁匠 ×%.2f（铁匠 %d → 应为 %d，实际 %d）"
			% [EXPECTED_FEE_RATE, int(manual.get("cost", 0)), expected, int(auto.get("cost", -1))])

## 用例 4：只修身上 —— 背包里 0 耐久件**必须仍是 0**（它可能是留卖/留合成的料）。
func _test_repair_worn_only() -> void:
	_reset()
	GameState.equipment["weapon"] = _equip(138, "legendary", 12, 0)
	GameState.inventory[0] = _equip(138, "legendary", 12, 0)
	GameState.try_auto_repair()
	check(_worn_durability() == Durability.max_durability(),
		"用例 4：身上的件应被修满，实际 %d" % _worn_durability())
	check(Durability.current(GameState.inventory[0]) == 0,
		"用例 4：背包件不应被修（修了白花钱），实际耐久 %d"
			% Durability.current(GameState.inventory[0]))

## 用例 5：金币不足 → 一件不修、金币不变、失败提示被节流。
func _test_repair_insufficient_gold() -> void:
	_reset()
	GameState.gold = 0
	GameState.equipment["weapon"] = _equip(138, "legendary", 12, 100)
	var result := GameState.try_auto_repair()
	check(not bool(result.get("ok", true)),
		"用例 5：金币不足时不应报告成功，实际 %s" % str(result))
	check(_worn_durability() == 100,
		"用例 5：金币不足应一件不修（全有或全无），实际耐久 %d" % _worn_durability())
	check(GameState.gold == 0,
		"用例 5：金币不足不应扣钱，实际 %d" % GameState.gold)
	var stamp := GameState._auto_repair_warn_ms
	check(stamp > 0, "用例 5：失败提示时间戳应被更新，实际 %d" % stamp)
	GameState.try_auto_repair()
	check(GameState._auto_repair_warn_ms == stamp,
		"用例 5：节流窗口内第二次失败不应重复提示（%d → %d）"
			% [stamp, GameState._auto_repair_warn_ms])

## 用例 6：4 件同档 0 星金装 → 剩 1 件紫装，金币减少 == 服务费。
func _test_forge_success() -> void:
	_reset()
	var mats: Array[Dictionary] = []
	for i in range(4):
		var item := _equip(GOLD_TIER, "epic", 0)
		GameState.inventory[i] = item
		mats.append(item.duplicate(true))
	var fee := GameState.auto_forge_fee(mats)
	# 绝对判据：服务费 = 同档单件**修满价** × 0.5。只断「扣了 fee」会被「fee 自己算错」骗过。
	var full := Durability.repair_full_price(mats[0])
	var expected_fee := maxi(1, int(round(float(full) * EXPECTED_FEE_SHARE)))
	check(fee == expected_fee,
		"用例 6：服务费应为单件修满价 %d × %.2f = %d，实际 %d"
			% [full, EXPECTED_FEE_SHARE, expected_fee, fee])
	var gold_before := GameState.gold
	var result := GameState.auto_forge_gold()
	check(bool(result.get("ok", false)),
		"用例 6：4 件同档金装应合成成功，实际 %s" % str(result))
	check(GameState.inventory_used() == 1,
		"用例 6：4 进 1 出后应只剩 1 件，实际 %d 件" % GameState.inventory_used())
	var produced: Dictionary = result.get("item", {})
	check(String(produced.get("quality", "")) == "legendary",
		"用例 6：产物应为紫装，实际 %s" % String(produced.get("quality", "")))
	check(gold_before - GameState.gold == fee,
		"用例 6：服务费应为 %d，实际扣了 %d" % [fee, gold_before - GameState.gold])
	check(fee > 0, "用例 6：服务费应大于 0（自动路径必须收费），实际 %d" % fee)

## 用例 7：只有 3 件背包料（即使身上还穿着一件同档金装）→ 不合成、金币不变。
## 🔴 后半句是「只吃背包」的**行为级**护栏：把 `equipment.values()` 也喂给挑料函数时，
##    3+1 恰好凑成 4 件，会把**穿戴中的装备**吃掉 —— 玩家身上直接少一件、战力骤降。
##    只断言「背包里 3 件没动」抓不到这条（背包确实没动，动的是身上）。
func _test_forge_too_few() -> void:
	_reset()
	for i in range(3):
		GameState.inventory[i] = _equip(GOLD_TIER, "epic", 0)
	GameState.equipment["weapon"] = _equip(GOLD_TIER, "epic", 0)
	var worn_id := String(GameState.equipment["weapon"].get("instanceId", ""))
	var gold_before := GameState.gold
	var result := GameState.auto_forge_gold()
	check(not bool(result.get("ok", true)),
		"用例 7：背包不足 4 件不应合成，实际 %s" % str(result))
	check(GameState.inventory_used() == 3,
		"用例 7：材料不应被消耗，实际 %d 件" % GameState.inventory_used())
	check(GameState.gold == gold_before,
		"用例 7：不合成不应扣钱，实际 %d → %d" % [gold_before, GameState.gold])
	var worn: Variant = GameState.equipment.get("weapon")
	check(worn is Dictionary and String(worn.get("instanceId", "")) == worn_id,
		"用例 7：穿戴中的装备绝不能被当成合成材料吃掉")

## 用例 11：金币不足 → 不合成、材料一件不少。
## ⚠ 方案 7.1 原本没列这条，但它是 N-3（漏金币校验）唯一的判据 ——
##   金币管够时漏掉校验完全看不出来，只有「钱不够还照合」才会暴露。
func _test_forge_insufficient_gold() -> void:
	_reset()
	GameState.gold = 0
	for i in range(4):
		GameState.inventory[i] = _equip(GOLD_TIER, "epic", 0)
	var result := GameState.auto_forge_gold()
	check(not bool(result.get("ok", true)),
		"用例 11：金币不足不应合成，实际 %s" % str(result))
	check(GameState.inventory_used() == 4,
		"用例 11：金币不足时材料应一件不少（应为 4，实际 %d）" % GameState.inventory_used())
	check(GameState.gold == 0,
		"用例 11：金币不足不应扣钱，实际 %d" % GameState.gold)
	check(GameState._auto_forge_warn_ms > 0,
		"用例 11：合成失败提示时间戳应被更新，实际 %d" % GameState._auto_forge_warn_ms)

## 用例 8：4 件里有 1 件 12 星 → 只挑得到 3 件合规料 → 不合成。
## 🔴 12 星金装吃了就是毁号；`random_materials` 的 `star != 0` 守卫是唯一防线。
func _test_forge_skips_starred() -> void:
	_reset()
	for i in range(3):
		GameState.inventory[i] = _equip(GOLD_TIER, "epic", 0)
	GameState.inventory[3] = _equip(GOLD_TIER, "epic", Upgrade.max_star())
	var gold_before := GameState.gold
	var result := GameState.auto_forge_gold()
	check(not bool(result.get("ok", true)),
		"用例 8：只剩 3 件 0 星料时不应合成，实际 %s" % str(result))
	check(GameState.inventory_used() == 4,
		"用例 8：12 星金装绝不能被吃掉，实际剩 %d 件" % GameState.inventory_used())
	check(GameState.gold == gold_before,
		"用例 8：不合成不应扣钱，实际 %d → %d" % [gold_before, GameState.gold])

## 用例 9：跨档共存 → 必须按**同档**取料，产物落在材料档（最低合格档），不是别的档。
## 🔴 `plan_four` 对四金**不校验同档**，混档会按最低档产出并白白浪费高档材料；
##    所以自动路径必须先按档分组，再只取一组。
func _test_forge_same_tier() -> void:
	_reset()
	var low := GOLD_TIER
	var high := GOLD_TIER + ItemFactory.TIER_SPAN
	for i in range(4):
		GameState.inventory[i] = _equip(low, "epic", 0)
	for i in range(4, 6):
		GameState.inventory[i] = _equip(high, "epic", 0)
	var result := GameState.auto_forge_gold()
	check(bool(result.get("ok", false)),
		"用例 9：低档凑满 4 件时应合成成功，实际 %s" % str(result))
	var produced: Dictionary = result.get("item", {})
	check(EquipmentFusion.tier_start(produced) == low,
		"用例 9：产物应落在材料档 %d，实际 %d"
			% [low, EquipmentFusion.tier_start(produced)])
	check(GameState.inventory_used() == 3,
		"用例 9：只该消耗低档 4 件（6 - 4 + 1 = 3），实际 %d 件" % GameState.inventory_used())

## 用例 10：铁匠手动合成**仍然免费** —— 服务费只收在自动入口。
## 🔴 这条是「不许改 `forge_equipment` 的 cost 语义」的护栏：
##    一旦有人把服务费写进 plan/forge，铁匠会跟着涨价，与需求完全相反。
func _test_smithy_stays_free() -> void:
	_reset()
	var mats: Array[Dictionary] = []
	for i in range(4):
		var item := _equip(GOLD_TIER, "epic", 0)
		GameState.inventory[i] = item
		mats.append(item.duplicate(true))
	var gold_before := GameState.gold
	var result := GameState.forge_equipment(EquipmentFusion.GOLD_TO_PURPLE, mats)
	check(bool(result.get("ok", false)),
		"用例 10：铁匠四金合紫应成功，实际 %s" % str(result))
	check(GameState.gold == gold_before,
		"用例 10：铁匠四金合紫必须免费（自动才收服务费），实际 %d → %d"
			% [gold_before, GameState.gold])
