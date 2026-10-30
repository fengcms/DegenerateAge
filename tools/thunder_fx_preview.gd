extends Node2D
## 雷电术落雷特效的**人工视觉预览**（工程 105 修订版）。
##
## 用途：把 `thunder_fx` 的四个时间点各渲染一张 PNG，用来核对「够不够长、够不够大、
## 分叉有没有甩出画面、落点有没有又长成范围圈」。**不是测试**，不参与任何断言。
##
## 🔴 必须用**窗口模式**跑（`--headless` 不渲染，截出来是空图）：
##     /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/thunder_fx_preview.tscn
## 🔴 不放 `tests/`：`--all` 会 glob `tests/*.tscn` 并当成测试跑。
##
## 冻结驱动：`set_process(false)` 后自己写 `_age`，保证每次截到的都是**同一时段**，
## 不受机器帧率影响。代价是没法验证「抖动节奏」，那一项只能实机看。

const ThunderFx := preload("res://scripts/systems/thunder_fx.gd")

const OUT_DIR := "/tmp/thunder_preview"
## 目标位置：模拟「玩家在屏幕下方、怪缠在正上方 3 格」的常见交战画面。
const TARGET := Vector2(640.0, 430.0)
const SHOTS := [0.02, 0.065, 0.095, 0.20]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	RenderingServer.set_default_clear_color(Color(0.09, 0.10, 0.12))
	var target := MockTarget.new()
	target.position = TARGET
	add_child(target)
	var tag := Label.new()
	tag.position = Vector2(24, 20)
	tag.text = "thunder_fx  BOLT_HEIGHT=%d  SEGMENTS=%d  MAX_TURN=%.2f  PULL_BACK=%.2f  BRANCH=%d" % [
		int(ThunderFx.BOLT_HEIGHT), ThunderFx.SEGMENTS, ThunderFx.MAX_TURN,
		ThunderFx.PULL_BACK, ThunderFx.BRANCH_COUNT]
	tag.add_theme_font_size_override("font_size", 20)
	add_child(tag)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for t in SHOTS:
		var fx := ThunderFx.new()
		fx.position = TARGET
		add_child(fx)
		fx.set_process(false)
		fx._age = float(t)
		fx._rebuild()
		fx.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save("t%03d" % int(round(float(t) * 1000.0)))
		fx.queue_free()
		await get_tree().process_frame
	print("PREVIEW 输出目录：", OUT_DIR)
	get_tree().quit(0)

func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var err := img.save_png(path)
	print("PREVIEW %s -> %s (err=%d, %dx%d)" % [shot_name, path, err,
		img.get_width(), img.get_height()])

## 只画「被雷劈的那只怪」的轮廓：地面阴影 + 身体 + 锁定环。
## 有参照物才能判断闪电是穿身而过还是停在头顶 —— 单独一张闪电看不出这些。
class MockTarget extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 18.0, Color(0, 0, 0, 0.40))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(Vector2(0, -12), 18.0, Color(0.52, 0.18, 0.20))
		draw_arc(Vector2(0, -12), 18.0, 0.0, TAU, 32, Color(0.16, 0.05, 0.06), 2.0, true)
		GroundFx.outline(self, Vector2(0, 8), 20.0, Color(0.40, 0.85, 0.95, 0.9), 2.5, 28)
