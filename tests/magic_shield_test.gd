extends Node
## 工程 98 Q4=A：魔法盾契约（受伤 35% 转由法力承担，1 伤害 = 1 蓝）。
##
## 这条是「传奇味」的全部来源，也是最容易做成白送的地方（R6）：
## 只减伤不扣蓝 ⇒ 法师直接强于武士，而且测试照样绿（如果只断「掉血变少」）。
## 所以每个用例都同时断**扣了多少血**与**扣了多少蓝**，两侧夹逼。
##
## 另外两个必须钉死的边界：
##   · 蓝不够时按**剩余量**转嫁，余下全部扣血（不是「蓝不够就完全免伤」）；
##   · 武士没有任何 buff 带这个键 ⇒ 行为必须逐位不变（0.0 早退路径）。

const TILE := 64.0

var failures: Array[String] = []

## 收集魔法盾的行为与表现断言，交由隔离运行器统一报告。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[MagicShieldTest] " + label)

## 按开盾、续盾、承伤、视觉与职业隔离的顺序运行契约测试。
func _ready() -> void:
	_test_cast_costs_mana()
	_test_refresh_and_rank_snapshot()
	_test_auto_refresh_window()
	_test_absorbs_share()
	_test_mana_exhausted()
	_test_partial_mana()
	_test_expired()
	_test_rank_effect()
	_test_aura_lifecycle()
	_test_aura_animation()
	_test_warrior_unchanged()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[MagicShieldTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[MagicShieldTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

## 新建无场景画层的逻辑玩家，验证技能结算且不依赖视觉节点。
func _make_player() -> PlayerCharacter:
	GameState.reset_to_defaults("mage")
	GameState.current_map = "wild_trial"
	GameState.player.level = 60
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(4000, 4000)
	# 血 / 蓝都给到远高于单次 1000 的量：`apply_damage` 的返回值会被 `mini(伤害, 当前血)`
	# 夹到现存血量，血少了会让「扣血 650」变成「扣血 = 当前血」，把用例本身测坏。
	GameState.player.hp = 100000
	GameState.player.mp = 100000
	return player

## 开盾要花 6% 上限的蓝，并且进入冷却。
func _test_cast_costs_mana() -> void:
	var player := _make_player()
	var cost := GameState.skill_mana_cost(SkillProgression.current("magic_shield"))
	var before := int(GameState.player.mp)
	check(player.cast_skill("magic_shield"), "Lv60 应能开启魔法盾")
	check(int(GameState.player.mp) == before - cost,
		"开盾应扣 %d 点蓝（%d → %d）" % [cost, before, int(GameState.player.mp)])
	check(GameState.buff_remaining("magic_shield") > 0.0, "开盾后 buff 必须生效")
	check(player.skill_cooldown("magic_shield") > 0.0, "开盾必须进入冷却")
	player.queue_free()

## CD 已结束时手动重施，必须完整付费并覆盖剩余时间；升阶后取新效果、不叠加旧效果。
func _test_refresh_and_rank_snapshot() -> void:
	var player := _make_player()
	var skill := SkillProgression.current("magic_shield")
	check(float(skill.get("cooldown", 0.0)) < float(skill.get("duration", 0.0)),
		"魔法盾基础 CD 必须短于持续时间")
	check(player.cast_skill("magic_shield"), "首次开启魔法盾")
	GameState.tick_buffs(20.0)
	player.skill_cooldowns["magic_shield"] = 0.0
	GameState.skill_ranks["magic_shield"] = 5
	var mp_before := int(GameState.player.mp)
	var cost := GameState.skill_mana_cost(SkillProgression.current("magic_shield"))
	check(player.request_skill("magic_shield"), "冷却结束后允许手动刷新有效魔法盾")
	check(is_equal_approx(GameState.buff_remaining("magic_shield"), 30.0),
		"重施只刷新到 30 秒，不累加旧盾剩余时间")
	check(int(GameState.player.mp) == mp_before - cost and player.skill_cooldown("magic_shield") > 0.0,
		"重施应再次耗蓝并进入冷却")
	check(is_equal_approx(GameState.buff_effect_total("damageToManaPct"), 0.47),
		"重施用新阶效果覆盖旧阶快照，不叠加")
	check(not player.request_skill("magic_shield") and int(GameState.player.mp) == mp_before - cost,
		"冷却内不可重复扣蓝")
	player.queue_free()

## 自动战斗只在到期前五秒内续盾；缺蓝或冷却未好时保留原盾。
func _test_auto_refresh_window() -> void:
	var player := _make_player()
	var pilot := AutoBattle.new()
	pilot.name = "AutoPilot"
	player.add_child(pilot)
	pilot.set_physics_process(false)
	check(player.cast_skill("magic_shield"), "自动补盾场景先开盾")
	GameState.tick_buffs(24.0)
	player.skill_cooldowns["magic_shield"] = 0.0
	check(not pilot._tick_mage_shield(), "剩余六秒时不提前浪费法力")
	GameState.tick_buffs(1.2)
	var before := int(GameState.player.mp)
	check(pilot._tick_mage_shield(), "剩余不足五秒时自动补盾")
	check(is_equal_approx(GameState.buff_remaining("magic_shield"), 30.0)
		and int(GameState.player.mp) < before, "自动补盾刷新时间并扣蓝")
	GameState.tick_buffs(26.0)
	player.skill_cooldowns["magic_shield"] = 1.0
	check(not pilot._tick_mage_shield(), "冷却未好时不得刷新")
	player.skill_cooldowns["magic_shield"] = 0.0
	GameState.player.mp = 0
	check(not pilot._tick_mage_shield() and GameState.buff_remaining("magic_shield") > 0.0,
		"缺蓝时不续盾也不删除尚有效的旧盾")
	player.queue_free()

## 核心：1000 点伤害 → 扣血 650 / 扣蓝 350（按 buff 的 0.35 转嫁）。
func _test_absorbs_share() -> void:
	var player := _make_player()
	GameState.start_buff("magic_shield")
	var mp_before := int(GameState.player.mp)
	var hp_before := int(GameState.player.hp)
	var taken := player.apply_damage(1000)
	check(taken == 650, "开盾后 1000 点伤害应只扣 650 血，实际 %d" % taken)
	check(hp_before - int(GameState.player.hp) == 650,
		"血条应减少 650，实际 %d" % (hp_before - int(GameState.player.hp)))
	check(mp_before - int(GameState.player.mp) == 350,
		"蓝条应减少 350（只减伤不扣蓝就是白送），实际 %d" % (mp_before - int(GameState.player.mp)))
	player.queue_free()

## 蓝干了：转嫁 0，1000 点全额扣血 —— 这就是「断蓝即变脆」。
func _test_mana_exhausted() -> void:
	var player := _make_player()
	GameState.start_buff("magic_shield")
	GameState.player.mp = 0
	var taken := player.apply_damage(1000)
	check(taken == 1000, "蓝为 0 时 1000 点伤害必须全额扣血，实际 %d" % taken)
	check(int(GameState.player.mp) == 0, "蓝为 0 时不得变成负数")
	player.queue_free()

## 蓝只够转嫁一部分：余下照常扣血（不能出现「蓝不足 ⇒ 免伤」）。
func _test_partial_mana() -> void:
	var player := _make_player()
	GameState.start_buff("magic_shield")
	GameState.player.mp = 100
	var taken := player.apply_damage(1000)
	check(taken == 900, "蓝只有 100 时应转嫁 100、扣血 900，实际 %d" % taken)
	check(int(GameState.player.mp) == 0, "剩余蓝应被扣干")
	player.queue_free()

## 盾到期（buff 移除）后恢复全额扣血。
func _test_expired() -> void:
	var player := _make_player()
	GameState.start_buff("magic_shield")
	GameState.tick_buffs(31.0)
	check(GameState.buff_remaining("magic_shield") == 0.0, "31 秒后盾应过期（持续 30 秒）")
	var mp_before := int(GameState.player.mp)
	check(player.apply_damage(1000) == 1000, "盾过期后应全额扣血")
	check(int(GameState.player.mp) == mp_before, "盾过期后不得扣蓝")
	player.queue_free()

## 升阶必须真生效：5 阶 = 47%，不是写死 35%。
func _test_rank_effect() -> void:
	var player := _make_player()
	GameState.skill_ranks["magic_shield"] = 5
	GameState.start_buff("magic_shield")
	check(is_equal_approx(GameState.buff_effect_total("damageToManaPct"), 0.47),
		"5 阶盾的转嫁比例应为 0.47，实际 %.2f" % GameState.buff_effect_total("damageToManaPct"))
	check(player.apply_damage(1000) == 530, "5 阶盾下 1000 点伤害应扣 530 血")
	player.queue_free()

## 正式玩家场景的护罩须跟随 Buff、蓝量、骑乘和死亡切换，且不改变碰撞层。
func _test_aura_lifecycle() -> void:
	GameState.reset_to_defaults("mage")
	GameState.current_map = "wild_trial"
	GameState.player.level = 60
	GameState.player.mp = GameState.max_mp()
	var player := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as PlayerCharacter
	add_child(player)
	player.set_physics_process(false)
	var back := player.get_node("MagicShieldBack") as MagicShieldAura
	var front := player.get_node("MagicShieldFront") as MagicShieldAura
	check(not back.visible and not front.visible, "无盾时世界护罩不绘制")
	check(player.cast_skill("magic_shield"), "正式玩家场景能开启魔法盾")
	check(back.visible and front.visible and back.z_index < 0 and front.z_index > 0,
		"开盾后人物前后两层护罩立即出现")
	check(back.outline_bounds() == front.outline_bounds(), "护罩前后轮廓应吻合")
	GameState.player.mp = 0
	player._sync_magic_shield_visual()
	check(not back.visible and not front.visible, "蓝量耗尽时护罩熄灭")
	GameState.player.mp = 100
	player._sync_magic_shield_visual()
	check(back.visible and front.visible, "Buff 仍有效时回蓝可恢复护罩")
	GameState.collect_mount("mount_corrupted_wing")
	check(bool(GameState.ride_mount("mount_corrupted_wing").get("ok", false)), "护罩测试坐骑可骑乘")
	check(back.outline_bounds().size.x > 120.0 and back.outline_bounds() == front.outline_bounds(),
		"骑乘时前后护罩同步扩大")
	GameState.clear_buffs()
	player._sync_magic_shield_visual()
	check(not back.visible and not front.visible, "盾到期或清除后护罩消失")
	GameState.start_buff("magic_shield")
	player.is_dead = true
	player._sync_magic_shield_visual()
	check(not back.visible and not front.visible, "死亡时即使 Buff 未清理也不显示护罩")
	player.queue_free()

## 工程 106 §3.5：护罩是持续 30 秒的状态，改前完全静止 —— 玩家只能靠 UI 图标判断盾在不在。
## 现在靠「呼吸 + 能量网」自己证明自己活着。本用例守两件事：
##   · 不可见时**不得**推进动画（30 秒常态下的每秒 8 条折线开销）；
##   · 可见时两个观测量都必须真的在变（只断「函数被调用了」会被空实现骗过）。
func _test_aura_animation() -> void:
	GameState.reset_to_defaults("mage")
	GameState.current_map = "wild_trial"
	GameState.player.level = 60
	GameState.player.mp = GameState.max_mp()
	var player := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as PlayerCharacter
	add_child(player)
	player.set_physics_process(false)
	var front := player.get_node("MagicShieldFront") as MagicShieldAura
	check(not front.visible, "动画前提：新玩家节点无盾时护罩应隐藏")
	var idle_breath := front.breath
	var idle_phase := front.net_phase
	for _i in range(10):
		front._process(0.05)
	check(is_equal_approx(front.breath, idle_breath) and is_equal_approx(front.net_phase, idle_phase),
		"护罩隐藏时不得推进动画（否则无盾时也在白跑每秒 8 条折线的重绘）")
	check(player.cast_skill("magic_shield"), "动画用例：应能开盾")
	var b0 := front.breath
	var p0 := front.net_phase
	for _i in range(12):
		front._process(0.05)
	check(absf(front.breath - b0) > 0.01,
		"呼吸：护罩亮度应随时间起伏（改前是恒定 alpha，这是「盾还活着」的唯一自证）")
	check(absf(front.net_phase - p0) > 0.01,
		"能量网：相位应随时间推进（否则网是静止的，等于没加）")
	check(front.breath > 0.5 and front.breath < 0.9,
		"呼吸幅度应落在 0.5—0.9：更高会盖住角色贴图，更低在静态截图里几乎看不见盾")
	player.queue_free()

## 武士路径逐位不变：没有任何 buff 提供 damageToManaPct ⇒ 全额扣血、蓝不动。
func _test_warrior_unchanged() -> void:
	GameState.reset_to_defaults("warrior")
	GameState.current_map = "wild_trial"
	GameState.player.level = 60
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(4200, 4200)
	GameState.player.hp = 100000
	GameState.start_buff("battle_focus")
	var mp_before := int(GameState.player.mp)
	var taken := player.apply_damage(1000)
	check(taken == 1000, "武士 1000 点伤害应全额扣血，实际 %d" % taken)
	check(int(GameState.player.mp) == mp_before, "武士受击不得扣蓝")
	player.queue_free()
