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
