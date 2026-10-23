extends Node
## 工程 98 第三层：冰咆哮减速契约。
##
## 减速是「写进数据就算实现」的头号嫌疑人：`debuff` 字段放着不动也能过启动校验，
## 玩家只会看到「技能打出去了、怪还是原速追上来」。所以本文件只用**真实例化的 Monster**
## 验证移速乘子，不看 `debuff` 字段本身。
##
## 另外守 R8：Boss 的减速时长必须减半 —— 否则百首禁域 100 席可以无限减速刷，整张图变木桩。

const NORMAL := "c6_normal01"
const BOSS := "c6_boss03"

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[MageSlowTest] " + label)

func _ready() -> void:
	_test_applies_and_expires()
	_test_stronger_wins()
	_test_boss_halved()
	_test_no_debuff_is_identity()
	_test_frost_roar_end_to_end()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[MageSlowTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[MageSlowTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

func _monster(monster_id: String) -> Monster:
	var m := Monster.new()
	m.monster_id = monster_id
	m.spawn_level = 60
	m.scale_stats = true
	add_child(m)
	return m

## 0.35 减速 ⇒ 移速乘子 0.65；3 秒后自动恢复。
func _test_applies_and_expires() -> void:
	var m := _monster(NORMAL)
	var base := m.move_speed_px
	check(base > 0.0, "用例前提：%s 应有非零移速" % NORMAL)
	m.apply_slow(0.35, 3.0)
	check(is_equal_approx(m.movement_multiplier(), 0.65),
		"减速 35%% 后移速乘子应为 0.65，实际 %.2f" % m.movement_multiplier())
	check(is_equal_approx(m.current_move_speed(), base * 0.65),
		"实际移速应为 %.1f，实际 %.1f" % [base * 0.65, m.current_move_speed()])
	m.tick_status(2.9)
	check(is_equal_approx(m.movement_multiplier(), 0.65), "2.9 秒时减速仍应生效")
	m.tick_status(0.2)
	check(is_equal_approx(m.movement_multiplier(), 1.0), "3.1 秒后移速必须恢复")
	check(is_equal_approx(m.current_move_speed(), base), "恢复后移速应回到原值")
	m.free()

## 同强度刷新时长、弱效果不覆盖强效果（否则连续小减速能把冰咆哮顶掉）。
func _test_stronger_wins() -> void:
	var m := _monster(NORMAL)
	m.apply_slow(0.35, 3.0)
	m.apply_slow(0.15, 3.0)
	check(is_equal_approx(m.movement_multiplier(), 0.65),
		"弱减速不得覆盖强减速，实际乘子 %.2f" % m.movement_multiplier())
	m.apply_slow(0.5, 2.0)
	check(is_equal_approx(m.movement_multiplier(), 0.5),
		"更强的减速应覆盖，实际乘子 %.2f" % m.movement_multiplier())
	m.free()

## Boss 时长减半（R8）。只断「有减速」会让 100 席禁域被无限刷。
func _test_boss_halved() -> void:
	var boss := _monster(BOSS)
	boss.apply_slow(0.35, 3.0)
	check(is_equal_approx(boss.slow_remaining(), 1.5),
		"Boss 的减速时长应减半到 1.5 秒，实际 %.2f" % boss.slow_remaining())
	boss.tick_status(1.6)
	check(is_equal_approx(boss.movement_multiplier(), 1.0), "Boss 的减速应在 1.5 秒后结束")
	boss.free()
	var normal := _monster(NORMAL)
	normal.apply_slow(0.35, 3.0)
	check(is_equal_approx(normal.slow_remaining(), 3.0),
		"普通怪不得被减半（实际 %.2f）" % normal.slow_remaining())
	normal.free()

## 没中减速时乘子恒 1.0（默认值 ⇒ 既有战斗逐位不变）。
func _test_no_debuff_is_identity() -> void:
	var m := _monster(NORMAL)
	check(is_equal_approx(m.movement_multiplier(), 1.0), "未减速时乘子必须为 1.0")
	check(is_equal_approx(m.current_move_speed(), m.move_speed_px), "未减速时移速应等于基础值")
	m.apply_slow(0.0, 3.0)
	check(is_equal_approx(m.movement_multiplier(), 1.0), "0 比例减速不得生效")
	m.free()

## 端到端：冰咆哮的真实数据经 `player._apply_skill_debuff` 落到怪身上。
func _test_frost_roar_end_to_end() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 30
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var m := _monster(NORMAL)
	var skill: Dictionary = SkillProgression.current("frost_roar")
	check(String(skill.get("debuff", {}).get("type", "")) == "slow", "冰咆哮的数据里必须有 slow 减益")
	player.call("_apply_skill_debuff", m, skill)
	check(is_equal_approx(m.movement_multiplier(), 0.65),
		"冰咆哮命中后移速乘子应为 0.65，实际 %.2f" % m.movement_multiplier())
	m.free()
	# 没有 debuff 的技能不得留下任何减速（反向对照）。
	var clean := _monster(NORMAL)
	player.call("_apply_skill_debuff", clean, SkillProgression.current("meteor"))
	check(is_equal_approx(clean.movement_multiplier(), 1.0), "陨石术不应附带减速")
	clean.free()
	player.queue_free()
