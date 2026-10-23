extends Node
## 工程 98 修订：法师「技能当普攻打」的冷却契约。
##
## 需求原话：「雷电术的 cd 时间太长了，应该和普攻差不多；其他技能，除了魔法盾，
## 其他技能应该都是和普攻一样的 cd，或者稍长一点点。毕竟法师是不能硬扛怪物的，
## 都是使用技能攻击的。」
##
## 为什么不能只改 CD：`player.gd::cast_skill` 收尾写着
## `_attack_cd = effective_attack_interval()` —— **技能本身就占攻击槽位**。
## 所以「CD 缩短」等于「技能从偶尔一发变成每槽位一发」，普攻被挤掉。
## 若系数不跟着降，单怪输出 ×1.84、多怪 ×2.54 —— 这不是手感问题，是职业平衡崩了。
##
## 本文件守四件事：
##   ① CD 必须真的短（雷电 ≤ 1s，AOE ≤ 4s），且保留「大招最长」的层次；
##   ② 魔法盾的 CD 一个字节都不许动（用户明确排除）；
##   ③ **单次伤害必须降到 0.5—0.65 倍** —— 这是「缩短 CD」的数学对价，
##      不是可选优化；有人把系数调回去，这里必须红；
##   ④ 综合系数产出（槽位约束下）相对旧配在 [0.95, 1.20]，即「略强 +9%」。
##
## 🔴 第 ③④ 条的期望值全部是**测试内的绝对判据**（写死旧配的数字），
##    不复用 `data/skills.json` 的任何常量 —— 否则数据被改坏也照样绿（08 §7 第 37 条）。

const TILE := 64.0
## 满级实测攻击间隔 0.571s（163 级存档，`class_balance_probe`），这里按 0.5s 取整
## ⇒ 每秒 2 个攻击槽位。它是一个**模型常量**，不是从存档读出来的，
## 所以换存档、换等级不会让本文件的比值漂移。
const SLOTS_PER_SEC := 2.0
## 旧配（工程 98 初版）的四条数据，作为比值的分母 —— 写死，不从数据表取。
const OLD := {
	"lightning":   {"cooldown": 5.0,  "total": 2.20},
	"flame_burst": {"cooldown": 9.0,  "total": 4.80},
	"frost_roar":  {"cooldown": 7.0,  "total": 3.00},
	"meteor":      {"cooldown": 18.0, "total": 3.50},
}

class TestEnemy extends Node2D:
	var is_dead := false
	var hits := 0
	func _ready() -> void:
		add_to_group("enemies")
	func get_defense() -> float:
		return 0.0
	func get_dodge() -> float:
		return 0.0
	func take_hit(_result: Dictionary, _from: Node = null) -> void:
		hits += 1

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[MageRotationTest] " + label)

func _ready() -> void:
	_test_cooldowns()
	_test_shield_untouched()
	_test_basic_untouched()
	_test_single_hit_power()
	_test_rotation_output()
	_test_can_chain_cast()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[MageRotationTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[MageRotationTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

func _entry(sid: String) -> Dictionary:
	return DataLoader.get_entry("skills", sid)

## 总系数 = 系数 × 段数（`hits` 缺省 1）。三段技的总伤害必须按三段算，
## 否则火焰喷发的 2.85 会被当成 0.95 看，比值判定整体失真。
func _total(sid: String) -> float:
	var e := _entry(sid)
	return float(e.get("coefficient", 0.0)) * float(maxi(1, int(e.get("hits", 1))))

## ① CD 真的短了，且层次还在。
func _test_cooldowns() -> void:
	check(float(_entry("lightning").get("cooldown", 99.0)) <= 1.0,
		"雷电术 CD 必须 ≤ 1 秒（现在是 %.2f）—— 它是法师的普攻，不该让玩家等"
		% float(_entry("lightning").get("cooldown", 99.0)))
	for sid in ["flame_burst", "frost_roar", "meteor"]:
		var cd := float(_entry(sid).get("cooldown", 99.0))
		check(cd <= 4.0, "%s 的 CD 必须 ≤ 4 秒（现在是 %.2f）" % [sid, cd])
		check(cd > float(_entry("lightning").get("cooldown", 0.0)),
			"%s 的 CD 必须长于雷电术（保留「小技能 / 大招」的层次）" % sid)
	# 旧的 5 / 7 / 9 / 18 秒一律不许回来。
	for sid in OLD:
		check(float(_entry(sid).get("cooldown", 0.0)) < float(OLD[sid].cooldown),
			"%s 的 CD 必须比旧配 %.1fs 短" % [sid, float(OLD[sid].cooldown)])

## ② 魔法盾：用户明确排除，CD 与转嫁比例都要留在原位。
func _test_shield_untouched() -> void:
	var shield := _entry("magic_shield")
	check(is_equal_approx(float(shield.get("cooldown", 0.0)), 10.0),
		"魔法盾 CD 必须保持 10 秒（现在是 %.2f）" % float(shield.get("cooldown", 0.0)))
	check(is_equal_approx(float(shield.get("manaCostPct", 0.0)), 0.06),
		"魔法盾开盾蓝耗必须保持 6%")
	check(is_equal_approx(float((shield.get("effects", {}) as Dictionary).get("damageToManaPct", 0.0)), 0.35),
		"魔法盾转嫁比例必须保持 0.35")

## ③ 普攻：CD 恒 0（由攻击间隔节流），系数恒 1.0 —— 法师的火球是这个口径的锚。
func _test_basic_untouched() -> void:
	var basic := _entry("basic_fireball")
	check(bool(basic.get("basic", false)), "火球术必须仍带 basic 标记")
	check(is_equal_approx(float(basic.get("cooldown", -1.0)), 0.0),
		"普攻 CD 必须为 0（靠攻击间隔节流，不是靠冷却）")
	check(is_equal_approx(float(basic.get("coefficient", 0.0)), 1.0), "普攻系数必须保持 1.0")

## ④ 「缩短 CD」的对价：单次伤害必须降到 0.5—0.65 倍。
## 只断「CD 变短」会让「CD 变短 + 系数不动」蒙混过关 —— 那是 +84% / +154%。
func _test_single_hit_power() -> void:
	var single_now := _total("lightning")
	var single_old := float(OLD.lightning.total)
	var single_ratio := single_now / single_old
	check(single_ratio >= 0.50 and single_ratio <= 0.65,
		"雷电术单次伤害必须降到旧配的 0.50—0.65 倍（现在 %.3f：%.2f / %.2f）"
		% [single_ratio, single_now, single_old])

	var aoe_now := (_total("flame_burst") + _total("frost_roar") + _total("meteor")) / 3.0
	var aoe_old := (float(OLD.flame_burst.total) + float(OLD.frost_roar.total) + float(OLD.meteor.total)) / 3.0
	var aoe_ratio := aoe_now / aoe_old
	check(aoe_ratio >= 0.50 and aoe_ratio <= 0.68,
		"三条 AOE 的平均单次伤害必须降到旧配的 0.50—0.68 倍（现在 %.3f：%.2f / %.2f）"
		% [aoe_ratio, aoe_now, aoe_old])

## ⑤ 槽位约束下的综合产出相对旧配必须落在 [0.95, 1.20]。
## 模型：按价值从高到低抢槽位，抢不到想要的频率就吃剩下的；余额给普攻（系数 1.0）。
## 这不等于真实 DPS（暴击、破防、目标数另算），但足以卡住「系数被整体调回去」。
func _test_rotation_output() -> void:
	var single_now := _rate(["lightning"])
	var single_old := _rate_old(["lightning"])
	var single_ratio := single_now / single_old
	check(single_ratio >= 0.95 and single_ratio <= 1.20,
		"单怪场景的系数产出比必须落在 0.95—1.20（现在 %.3f：%.3f / %.3f）"
		% [single_ratio, single_now, single_old])

	var aoe_ids := ["flame_burst", "frost_roar", "meteor"]
	var aoe_now := _rate(aoe_ids)
	var aoe_old := _rate_old(aoe_ids)
	var aoe_ratio := aoe_now / aoe_old
	check(aoe_ratio >= 0.95 and aoe_ratio <= 1.20,
		"多怪场景的系数产出比必须落在 0.95—1.20（现在 %.3f：%.3f / %.3f）"
		% [aoe_ratio, aoe_now, aoe_old])

## 贪心填槽：价值 = 总系数（与 `AutoBattle.skill_value` 同口径），按价值降序分配。
func _rate(skill_ids: Array) -> float:
	var pool: Array = []
	for sid in skill_ids:
		pool.append({"total": _total(String(sid)), "freq": 1.0 / maxf(0.01, float(_entry(String(sid)).get("cooldown", 1.0)))})
	return _fill(pool)

func _rate_old(skill_ids: Array) -> float:
	var pool: Array = []
	for sid in skill_ids:
		pool.append({"total": float(OLD[String(sid)].total), "freq": 1.0 / float(OLD[String(sid)].cooldown)})
	return _fill(pool)

func _fill(pool: Array) -> float:
	pool.sort_custom(func(a, b): return float(a.total) > float(b.total))
	var left := SLOTS_PER_SEC
	var out := 0.0
	for item in pool:
		var take := minf(float(item.freq), left)
		if take <= 0.0:
			continue
		out += take * float(item.total)
		left -= take
	out += maxf(0.0, left) * 1.0     # 余额给普攻（系数 1.0）
	return out

## ⑥ 实战：雷电术连续三次施放，唯一瓶颈是攻击间隔，不是冷却。
## 只读数据不断这条，测不出 `cast_skill` 里那句 `_attack_cd = ...` 的耦合。
func _test_can_chain_cast() -> void:
	GameState.reset_to_defaults("mage")
	GameState.current_map = "wild_trial"
	GameState.player.level = 30
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(3000, 3000)
	var enemy := TestEnemy.new()
	add_child(enemy)
	enemy.global_position = player.global_position + Vector2(3.0 * TILE, 0)
	GameState.player.mp = GameState.max_mp()
	for i in 3:
		# 模拟「已经等够一个攻击间隔」：这是玩家真实的施放节奏。
		player._attack_cd = 0.0
		player.skill_cooldowns["lightning"] = 0.0
		check(player.cast_skill("lightning", enemy),
			"第 %d 次雷电术必须能施放（CD 不该成为瓶颈）" % (i + 1))
		check(player.skill_cooldown("lightning") <= 0.6 + 0.001,
			"第 %d 次施放后冷却必须 ≤ 0.6 秒（现在 %.3f）" % [i + 1, player.skill_cooldown("lightning")])
		check(player._attack_cd > 0.0, "施放技能必须占用攻击间隔（否则会零帧连发）")
	check(enemy.hits == 3, "三次施放应结算三次伤害（实际 %d）" % enemy.hits)
	player.queue_free()
	enemy.queue_free()
