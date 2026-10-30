extends Node2D
## 工程 106 批 1 的**人工视觉预览**：陨石术各阶段 + 升级后的火球投射物。
##
## 用途：核对「预警环有没有又长成一块盘、陨石落点对不对、冲击波扫到哪、
## 火球的彗尾能不能读出方向」。**不是测试**，不参与任何断言。
##
## 🔴 必须用**窗口模式**跑（`--headless` 不渲染，截出来是空图）：
##     /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/mage_fx_preview.tscn
## 🔴 不放 `tests/`：`--all` 会 glob `tests/*.tscn` 并当成测试跑。
##
## 冻结驱动：`set_process(false)` 后自己写内部计时，保证每次截到同一时段，不受帧率影响。

const MeteorFx := preload("res://scripts/systems/meteor_fx.gd")
const Projectile := preload("res://scripts/systems/player_projectile.gd")
const FlameBurstFx := preload("res://scripts/systems/flame_burst_fx.gd")
const FrostRoarFx := preload("res://scripts/systems/frost_roar_fx.gd")
const ShieldAura := preload("res://scripts/entities/magic_shield_aura.gd")
# 工程 107：武士五个主动技能。
const EarthCleaveFx := preload("res://scripts/systems/earth_cleave_fx.gd")
const WhirlwindFx := preload("res://scripts/systems/whirlwind_fx.gd")
const BattleFocusFx := preload("res://scripts/systems/battle_focus_fx.gd")
const ArmorBreakFx := preload("res://scripts/systems/armor_break_fx.gd")
const SpiritStormFx := preload("res://scripts/systems/spirit_storm_fx.gd")

const OUT_DIR := "/tmp/mage_fx_after"
## 陨石落点：屏幕中上方偏右，模拟「怪在前方」。
const TARGET := Vector2(560.0, 380.0)
## `range = 7` 格 ⇒ 地面半径 448px，与 skills.json 一致（不在这里另写一份）。
const RADIUS := 7.0 * 64.0
## 火焰喷发 `range = 3.5` 格；冰咆哮 `range = 4.5` 格。半径一律从 skills.json 的格数算出来。
const FLAME_RADIUS := 3.5 * 64.0
const FROST_RADIUS := 4.5 * 64.0
## 以自身为中心的技能，施法者站在屏幕偏下（相机跟随玩家，玩家通常在画面中下）。
const CASTER := Vector2(640.0, 560.0)

## 陨石时间轴：预警 0—0.45 / 落下 0.45—0.60 / 冲击 0.60—0.70 / 余韵 0.70—0.95
const METEOR_SHOTS := [0.08, 0.38, 0.52, 0.64, 0.72, 0.90]
## 火球：飞行中段 + 命中爆点。
const FIREBALL_SHOTS := [0.25, 0.6, 0.9]
const FIREBALL_IMPACT := [0.03, 0.07]
## 火焰喷发：预兆 0—0.10 / 爆发 0.10—0.22 / 余韵 0.22—0.50
const FLAME_SHOTS := [0.06, 0.14, 0.22, 0.34, 0.48]
## 冰咆哮：预兆 0—0.08 / 推进 0.08—0.30 / 冰晶 0.12—0.55 / 余韵 0.30—0.58
const FROST_SHOTS := [0.05, 0.15, 0.22, 0.32, 0.46]
## 魔法盾：`_t` 取 1.8s 周期里的四个相位（呼吸最低 / 中点 / 最高 / 中点）。
const SHIELD_SHOTS := [0.0, 0.45, 0.9, 1.35]

## 武士技能的地面半径一律从 skills.json 的格数算出来（不在预览里另写一份真相）。
const CLEAVE_RADIUS := 3.0 * 64.0
const WHIRL_RADIUS := 2.2 * 64.0
const STORM_RADIUS := 4.0 * 64.0
## 破甲重击是单体，没有地面范围；96px 只用来摆目标位置。
const ARMOR_REACH := 1.5 * 64.0
## 各技能时间轴的取样点，取在「形态变化最明显」的时刻上。
const CLEAVE_SHOTS := [0.05, 0.10, 0.16, 0.24, 0.38]
const WHIRL_SHOTS := [0.02, 0.08, 0.14, 0.22, 0.32]
const FOCUS_SHOTS := [0.04, 0.10, 0.18, 0.30, 0.52]
const ARMOR_SHOTS := [0.03, 0.07, 0.11, 0.20, 0.40]
const STORM_SHOTS := [0.05, 0.12, 0.22, 0.34, 0.52, 0.70]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	RenderingServer.set_default_clear_color(Color(0.09, 0.10, 0.12))
	# 守夜：`RenderingServer.frame_post_draw` 在某些环境下不触发会让 await 永久挂起，
	# 表现为「进程被外部杀掉、日志一个字都没有」。超时自退至少留下现场。
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		printerr("PREVIEW TIMEOUT")
		get_tree().quit(2))
	printerr("PREVIEW stage: ready")
	await get_tree().process_frame
	printerr("PREVIEW stage: first process_frame")
	await RenderingServer.frame_post_draw
	printerr("PREVIEW stage: first frame_post_draw")
	await _render_meteor()
	printerr("PREVIEW stage: meteor done")
	await _render_fireball()
	printerr("PREVIEW stage: fireball done")
	await _render_flame_burst()
	printerr("PREVIEW stage: flame done")
	await _render_frost_roar()
	printerr("PREVIEW stage: frost done")
	await _render_shield()
	printerr("PREVIEW stage: shield done")
	await _render_earth_cleave()
	printerr("PREVIEW stage: earth_cleave done")
	await _render_whirlwind()
	printerr("PREVIEW stage: whirlwind done")
	await _render_battle_focus()
	printerr("PREVIEW stage: battle_focus done")
	await _render_armor_break()
	printerr("PREVIEW stage: armor_break done")
	await _render_spirit_storm()
	printerr("PREVIEW stage: spirit_storm done")
	print("PREVIEW 输出目录：", OUT_DIR)
	get_tree().quit(0)

func _render_meteor() -> void:
	for t in METEOR_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		var target := MockTarget.new()
		target.position = TARGET
		stage.add_child(target)
		var fx := MeteorFx.new()
		stage.add_child(fx)
		fx.set_process(false)
		fx.set("_radius", RADIUS)
		fx.set("_age", float(t))
		fx.global_position = TARGET
		fx.queue_redraw()
		_add_tag(stage, "meteor  t=%.2fs  radius=%.0fpx（range 7 格）  ANCHOR=target" % [
			float(t), RADIUS])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		# 🔴 别写成 `"x%03d" % int(...) * 10`：`%` 比 `*` 结合得紧，会变成「字符串 × 整数」
		# 直接 Parse Error，而脚本加载失败后窗口不会自己退出（表现为进程被外部杀掉、日志空白）。
		_save("meteor_t%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

func _render_fireball() -> void:
	var from := Vector2(360.0, 620.0)
	var to := Vector2(760.0, 400.0)
	for ratio in FIREBALL_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		var bolt := Projectile.new() as Node2D
		stage.add_child(bolt)
		bolt.set_process(false)
		bolt.call("setup", from, to, Color("ffb347"), 8.0, 0.20)
		bolt.set("_elapsed", 0.20 * float(ratio))
		bolt.set("global_position", from.lerp(to, float(ratio)))
		bolt.queue_redraw()
		_add_tag(stage, "fireball  %.0f%% 飞行  时长 0.20s（旧版固定 0.14s）" % (float(ratio) * 100.0))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("fireball_t%03d" % int(round(float(ratio) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame
	for t in FIREBALL_IMPACT:
		var stage := Node2D.new()
		add_child(stage)
		var bolt := Projectile.new() as Node2D
		stage.add_child(bolt)
		bolt.set_process(false)
		bolt.call("setup", from, to, Color("ffb347"), 8.0, 0.20)
		bolt.set("_impacting", true)
		bolt.set("_impact_t", float(t))
		bolt.set("global_position", to)
		bolt.queue_redraw()
		_add_tag(stage, "fireball  命中爆点 t=%.2fs（不存在于旧版）" % float(t))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("fireball_impact_%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

## 火焰喷发（工程 106 §3.2）。范围内放三只怪，其中一只**贴着施法者**——
## 近战怪一定会站到 3.5 格内，它是「火舌有没有把怪盖住」的唯一判据。
func _render_flame_burst() -> void:
	for t in FLAME_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		for offset: Vector2 in [Vector2(-70.0, 14.0), Vector2(120.0, 6.0), Vector2(30.0, -90.0)]:
			var target := MockTarget.new()
			target.position = CASTER + offset
			stage.add_child(target)
		var caster := MockCaster.new()
		caster.position = CASTER
		stage.add_child(caster)
		var fx := FlameBurstFx.new() as Node2D
		stage.add_child(fx)
		# 🔴 复刻生产层级：`player._spawn_cast_node()` 用 `move_child(fx, 0)` 把地面系特效
		#    压到所有角色之下。漏掉这一步，预览会显示「火舌盖住怪」的假问题。
		stage.move_child(fx, 0)
		fx.set_process(false)
		fx.set("_radius", FLAME_RADIUS)
		fx.set("_age", float(t))
		fx.global_position = CASTER
		fx.queue_redraw()
		_add_tag(stage, "flame_burst  t=%.2fs  radius=%.0fpx（range 3.5 格）  ANCHOR=origin" % [
			float(t), FLAME_RADIUS])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("flame_t%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

## 冰咆哮（工程 106 §3.3）。扇形朝屏幕**右**：右方两只怪在扇形内、左方一只在扇形外，
## 一眼就能看出「朝向有没有跟错」。
func _render_frost_roar() -> void:
	for t in FROST_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		for offset: Vector2 in [Vector2(150.0, -25.0), Vector2(230.0, 20.0), Vector2(-175.0, 0.0)]:
			var target := MockTarget.new()
			target.position = CASTER + offset
			stage.add_child(target)
		var caster := MockCaster.new()
		caster.position = CASTER
		stage.add_child(caster)
		var fx := FrostRoarFx.new() as Node2D
		stage.add_child(fx)
		stage.move_child(fx, 0)
		fx.set_process(false)
		fx.set("_radius", FROST_RADIUS)
		fx.set("_facing", Vector2.RIGHT)
		fx.set("_age", float(t))
		fx.global_position = CASTER
		fx.queue_redraw()
		_add_tag(stage, "frost_roar  t=%.2fs  radius=%.0fpx（range 4.5 格）  ARC=90°  朝向→右" % [
			float(t), FROST_RADIUS])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("frost_t%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

## 魔法盾（工程 106 §3.5）。取 1.8s 呼吸周期的四个相位，看「呼吸是否可辨、网是否在转」。
## 后层（填充）+ 角色 + 前层（轮廓 + 网）三层，与 `Player.tscn` 的节点顺序一致。
func _render_shield() -> void:
	for t in SHIELD_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		var back := ShieldAura.new() as Node2D
		stage.add_child(back)
		var caster := MockCaster.new()
		caster.position = CASTER
		stage.add_child(caster)
		var front := ShieldAura.new() as Node2D
		stage.add_child(front)
		for node in [back, front]:
			var aura := node as Node2D
			aura.set_process(false)
			aura.position = CASTER
		back.set("front_pass", false)
		front.set("front_pass", true)
		for node in [back, front]:
			var aura := node as Node2D
			# 手算 _process 的产物，不走真计时：`set_process(false)` 之后内部状态不会自己推进。
			aura.set("breath", 0.70 + 0.15 * sin(TAU * float(t) / 1.8))
			aura.set("net_phase", TAU * float(t) / 30.0)
			aura.queue_redraw()
		_add_tag(stage, "magic_shield  t=%.2fs  breath=%.2f  net=%.1f°" % [
			float(t), 0.70 + 0.15 * sin(TAU * float(t) / 1.8), 360.0 * float(t) / 30.0])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("shield_t%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

## 裂地斩（工程 107）。扇形朝屏幕**右**：右前方三只怪在扇形内（maxTargets 3），
## 左后方一只在扇形外 —— 一眼看出「裂缝方向与扇形张角对不对」。
func _render_earth_cleave() -> void:
	for t in CLEAVE_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		for offset: Vector2 in [Vector2(70.0, 18.0), Vector2(130.0, -20.0), Vector2(100.0, 40.0), Vector2(-90.0, 0.0)]:
			var target := MockTarget.new()
			target.position = CASTER + offset
			stage.add_child(target)
		var caster := MockCaster.new()
		caster.position = CASTER
		stage.add_child(caster)
		var fx := EarthCleaveFx.new() as Node2D
		stage.add_child(fx)
		stage.move_child(fx, 0)
		fx.set_process(false)
		fx.set("_radius", CLEAVE_RADIUS)
		fx.set("_facing", Vector2.RIGHT)
		fx.set("_age", float(t))
		fx.global_position = CASTER
		fx.queue_redraw()
		_add_tag(stage, "earth_cleave  t=%.2fs  radius=%.0fpx（range 3.0 格）  ARC=90°  朝向→右" % [
			float(t), CLEAVE_RADIUS])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("cleave_t%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

## 旋风斩（工程 107）。环周 2.2 格，四周各放一只怪 —— 刀光转到哪个角度，
## 对应方位的怪就应该「已经被扫过」。
func _render_whirlwind() -> void:
	for t in WHIRL_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		# 四只怪要**都看得见**：正上方那只如果只放 40px 会被角色身体完全挡住，
		# 而「刀光转到上方时那只已经挨过打」正是这条预览要核对的东西。
		for offset: Vector2 in [Vector2(76.0, 0.0), Vector2(-76.0, 0.0), Vector2(0.0, 52.0), Vector2(0.0, -56.0)]:
			var target := MockTarget.new()
			target.position = CASTER + offset
			stage.add_child(target)
		var caster := MockCaster.new()
		caster.position = CASTER
		stage.add_child(caster)
		var fx := WhirlwindFx.new() as Node2D
		stage.add_child(fx)
		stage.move_child(fx, 0)
		fx.set_process(false)
		fx.set("_radius", WHIRL_RADIUS)
		fx.set("_age", float(t))
		fx.global_position = CASTER
		fx.queue_redraw()
		_add_tag(stage, "whirlwind  t=%.2fs  radius=%.0fpx（range 2.2 格）  两道刀光转满一圈" % [
			float(t), WHIRL_RADIUS])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("whirl_t%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

## 战意觉醒（工程 107）。自身增益，没有范围 —— 只看「红环 + 三道气浪升腾」是否成立。
func _render_battle_focus() -> void:
	for t in FOCUS_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		var caster := MockCaster.new()
		caster.position = CASTER
		stage.add_child(caster)
		var fx := BattleFocusFx.new() as Node2D
		stage.add_child(fx)
		stage.move_child(fx, 0)
		fx.set_process(false)
		fx.set("_age", float(t))
		fx.global_position = CASTER
		fx.queue_redraw()
		_add_tag(stage, "battle_focus  t=%.2fs  DRAWS_AREA=false（self 无范围）  减伤 20%% / 攻速 +15%%" % float(t))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("focus_t%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

## 破甲重击（工程 107）。单体：**只打一只**，旁边再放一只作为「没被打到」的对照。
func _render_armor_break() -> void:
	var hit_point := CASTER + Vector2(ARMOR_REACH * 0.62, -6.0)
	for t in ARMOR_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		var struck := MockTarget.new()
		struck.position = hit_point
		stage.add_child(struck)
		var bystander := MockTarget.new()
		bystander.position = CASTER + Vector2(-70.0, 30.0)
		stage.add_child(bystander)
		var caster := MockCaster.new()
		caster.position = CASTER
		stage.add_child(caster)
		var fx := ArmorBreakFx.new() as Node2D
		stage.add_child(fx)
		stage.move_child(fx, 0)
		fx.set_process(false)
		fx.set("_age", float(t))
		fx.global_position = hit_point
		fx.set("_hit_dir", Vector2.RIGHT)
		fx.queue_redraw()
		_add_tag(stage, "armor_break  t=%.2fs  ANCHOR=target（单体，不打左侧那只）" % float(t))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("armor_t%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

## 灵刃风暴（工程 107）。4 格共 256px，是武士最大的范围。八只怪摆一圈正好等于
## `maxTargets: 8` —— 三波刃光收完时，一圈的怪都应被扫过。
func _render_spirit_storm() -> void:
	for t in STORM_SHOTS:
		var stage := Node2D.new()
		add_child(stage)
		for i in range(8):
			var angle := TAU * float(i) / 8.0
			var target := MockTarget.new()
			target.position = CASTER + Vector2(cos(angle) * 150.0, sin(angle) * 150.0 * Iso.GROUND_SQUASH + 10.0)
			stage.add_child(target)
		var caster := MockCaster.new()
		caster.position = CASTER
		stage.add_child(caster)
		var fx := SpiritStormFx.new() as Node2D
		stage.add_child(fx)
		stage.move_child(fx, 0)
		fx.set_process(false)
		fx.set("_radius", STORM_RADIUS)
		fx.set("_age", float(t))
		fx.global_position = CASTER
		fx.queue_redraw()
		_add_tag(stage, "spirit_storm  t=%.2fs  radius=%.0fpx（range 4.0 格）  三波刃光内收 = 3 段" % [
			float(t), STORM_RADIUS])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("storm_t%03d" % int(round(float(t) * 100.0)))
		stage.queue_free()
		await get_tree().process_frame

func _add_tag(stage: Node2D, text: String) -> void:
	var tag := Label.new()
	tag.add_theme_font_size_override("font_size", 18)
	tag.position = Vector2(24.0, 20.0)
	tag.text = text
	stage.add_child(tag)

func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	img.save_png(path)
	print("PREVIEW %s -> %s" % [shot_name, path])

## 被砸的那只怪：地面阴影 + 身体 + 锁定环。有参照物才判断得出
## 「冲击波扫过时怪还在不在」。
class MockTarget extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 18.0, Color(0, 0, 0, 0.40))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(Vector2(0, -12), 18.0, Color(0.52, 0.18, 0.20))
		draw_arc(Vector2(0, -12), 18.0, 0.0, TAU, 32, Color(0.16, 0.05, 0.06), 2.0, true)

## 施法者：等距视角下的简化法师（长袍 + 头 + 法杖）。有它才判断得出
## 「火舌/冰晶有没有盖住人」「护罩有没有罩住整个身体」。
## 高度按 `MagicShieldAura.outline_bounds()` 反推：站立时护罩 y 从 -93 到 +19。
class MockCaster extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, Iso.GROUND_SQUASH))
		draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.42))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-16, 4), Vector2(16, 4), Vector2(11, -52), Vector2(-11, -52),
		]), Color(0.24, 0.30, 0.52))
		draw_circle(Vector2(0, -62), 10.0, Color(0.86, 0.74, 0.62))
		draw_line(Vector2(14, -8), Vector2(24, -74), Color(0.42, 0.32, 0.20), 3.0, true)
		draw_circle(Vector2(24, -76), 5.0, Color(0.55, 0.86, 1.0))
