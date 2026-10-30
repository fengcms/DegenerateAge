extends Node2D
## 法师其余技能**改前**视觉现状取证（工程 106 前置调查）。
##
## 用途：把 `skill_range_fx` 按 `skills.json` 里的真实 `range` 画一遍，量清楚
## 「这一块圆盘到底有多大、几秒一次」。**不是测试**，不参与任何断言。
##
## 🔴 必须用**窗口模式**跑（`--headless` 不渲染，截出来是空图）：
##     /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/mage_fx_before_preview.tscn
## 🔴 不放 `tests/`：`--all` 会 glob `tests/*.tscn` 并当成测试跑。
##
## 每张图只放**一个**技能，且按真实半径画 —— 四个叠在一张图上会互相盖住，
## 看不出「单个技能自己就占了半屏」这个结论。

const RangeFxScript := preload("res://scripts/systems/skill_range_fx.gd")

const OUT_DIR := "/tmp/mage_fx_before"
## 玩家站位：屏幕中下方，与实机常用交战视野一致。
const PLAYER := Vector2(640.0, 560.0)
## `skill_range_fx.LIFETIME = 0.3`，取三个时间点看清淡入淡出。
const SHOTS := [0.0, 0.15, 0.28]

## 取自 data/skills.json 的真实 shape / range / cooldown，**不在这里另写一份半径**。
const SKILLS := [
	{"id": "flame_burst", "shape": "circle", "range": 3.5, "cooldown": 3.2},
	{"id": "meteor", "shape": "circle", "range": 7.0, "cooldown": 3.8},
	{"id": "frost_roar", "shape": "cone", "range": 4.5, "cooldown": 2.8},
]

var _fx: Node2D = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	RenderingServer.set_default_clear_color(Color(0.09, 0.10, 0.12))
	var me := MockPlayer.new()
	me.position = PLAYER
	add_child(me)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for spec in SKILLS:
		for t in SHOTS:
			_render(spec, float(t))
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			_save("%s_t%03d" % [String(spec["id"]), int(round(float(t) * 1000.0))])
			if _fx != null:
				_fx.queue_free()
				_fx = null
			await get_tree().process_frame
	print("PREVIEW 输出目录：", OUT_DIR)
	get_tree().quit(0)

## 用**真实脚本 + 真实半径**，只冻结驱动以便定格截图。
func _render(spec: Dictionary, age: float) -> void:
	var fx := RangeFxScript.new() as Node2D
	add_child(fx)
	fx.set_process(false)
	fx.set("shape", String(spec["shape"]))
	fx.set("radius", float(spec["range"]) * Iso.TILE_W)
	fx.set("facing", Vector2(1.0, 0.35).normalized())
	fx.set("age", age)
	fx.position = PLAYER
	fx.queue_redraw()
	_fx = fx
	var tag := Label.new()
	tag.add_theme_font_size_override("font_size", 18)
	# 挂在 fx 下面，随 fx 一起释放 —— 挂根节点会逐张累积，多张标签叠成一团糊字。
	tag.position = Vector2(24.0, 20.0) - PLAYER
	tag.text = "%s  shape=%s  range=%.1f 格 → 地面半径 %.0fpx  |  屏幕横向直径 %.0fpx = 视口 1280 的 %.0f%%  |  CD %.1fs" % [
		String(spec["id"]), String(spec["shape"]), float(spec["range"]),
		float(spec["range"]) * Iso.TILE_W,
		float(spec["range"]) * Iso.TILE_W * 2.0,
		float(spec["range"]) * Iso.TILE_W * 2.0 / 1280.0 * 100.0,
		float(spec["cooldown"])]
	fx.add_child(tag)

func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	img.save_png(path)
	print("PREVIEW %s -> %s" % [shot_name, path])

## 玩家站位参照物：脚下一圈 + 身体 + 一根横向刻度尺（每格 64px，长刻度每 5 格）。
class MockPlayer extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 14.0, Color(0, 0, 0, 0.40))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(Vector2(0, -14), 14.0, Color(0.85, 0.72, 0.45))
		for i in range(-10, 11):
			var x := float(i) * Iso.TILE_W
			var tall := 8.0 if i % 5 == 0 else 4.0
			draw_line(Vector2(x, 14.0), Vector2(x, 14.0 + tall), Color(0.40, 0.45, 0.50, 0.9), 1.0)
