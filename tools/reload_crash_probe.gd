extends Node
## 必须通过tools/run_isolated_probe.py启动；隔离由项目身份强制检查，不能只依赖HOME约定。
## 工程 116：**读档重载**崩溃复现探针（只读，必须隔离 HOME）。
##
## 复现的是玩家真实路径：读档 → `MapService.reload_world()` → `reload_current_scene()`
## → 新场景 `_ready` → 之后若干秒。
##
## 两阶段设计（因为重载会把本探针自身销毁重建）：
##   阶段 A：写标记 → `load_into_game` → `reload_world()`（触发整场景重载）
##   阶段 B：重载后再次进入 `_ready`，检测到标记 → 建立 Main 世界 → 观察 N 秒
##
## 运行：
##   HOME=/tmp/deg_iso Godot --path . res://tools/ReloadCrashProbe.tscn
##   HOME=/tmp/deg_iso Godot --path . --quit-after 1800 res://tools/ReloadCrashProbe.tscn
##
## 🔴 必须隔离 HOME：本探针会读档，而引擎退出时会回写 `last_slot`（MEMORY 坑 106）。

## 阶段 B 观察时长（秒）。玩家崩溃发生在重载后十几秒内。
const WATCH_SECONDS := 12.0

const STAGE_FILE := "user://reload_probe_stage.txt"

## 隔离身份通过后复核读档与世界重载。
func _ready() -> void:
	if not DiagnosticProbeGuard.require_isolated(self):
		return
	var stage := _read_stage()
	print("[Probe] 进入 _ready，阶段=%d（headless=%s）" % [stage, DisplayServer.get_name()])
	if stage == 0:
		await _stage_a()
	else:
		await _stage_b(stage)

## 阶段 A：读档并触发重载。
func _stage_a() -> void:
	_write_stage(1)
	SaveManager.active_slot = -1
	GameState.menu_mode = "world"
	var res: Dictionary = SaveManager.load_into_game(1)
	print("[Probe][A] load_into_game ok=%s，即将 reload_world" % res.get("ok", false))
	MapService.reload_world()
	# 重载会销毁本节点，下面代码正常情况下不会执行到。
	await get_tree().create_timer(30.0).timeout
	print("[Probe][A] ⚠ 等了 30 秒仍未发生重载")

## 阶段 B：重载后的新场景，建立与玩家一致的世界并观察。
func _stage_b(stage: int) -> void:
	print("[Probe][B] 重载后场景就绪，开始构建世界")
	# 🔑 先看读档后的刷新状态：本轮要确认「100 个墓碑」是存档带来的，
	# 还是装配时新写进去的。两者含义完全不同。
	var respawn: Dictionary = GameState.spawn_respawn
	var boss_field := 0
	for raw_key in respawn.keys():
		if String(raw_key).begins_with("c7_boss_field#"):
			boss_field += 1
	print("[Probe][B] spawn_respawn 总条目=%d，c7_boss_field 前缀=%d，world_time=%.3f"
		% [respawn.size(), boss_field, GameState.world_time])
	var shown := 0
	for raw_key in respawn.keys():
		if String(raw_key).begins_with("c7_boss_field#") and shown < 8:
			var rec: Dictionary = respawn[raw_key]
			print("   %s readyAt=%.3f" % [String(raw_key), float(rec.get("readyAt", 0.0))])
			shown += 1
	SaveManager.active_slot = 1
	GameState.menu_mode = "world"

	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = main
	print("[Probe][B] Main 已建好，世界节点=%s" % (main.get_node_or_null("Game") != null))

	# 0.1 秒精度打点：崩溃发生在几秒，就能把范围缩到那一刻的异步流程。
	# 只打「存活」不加业务量 —— 目的是找崩溃时刻，不是测性能。
	var ticks := 0
	var total_ticks := int(WATCH_SECONDS * 10.0)
	while ticks < total_ticks:
		await get_tree().create_timer(0.1).timeout
		ticks += 1
		print("[Probe][B] tick=%d (t=%.1fs) frame=%d 存活" % [
			ticks, float(ticks) / 10.0, Engine.get_process_frames()])

	print("[Probe][B] === 观察 %.0f 秒未崩溃 ===" % WATCH_SECONDS)
	_write_stage(0)
	get_tree().quit(0)

## 读取隔离重载探针的阶段标记。
func _read_stage() -> int:
	if not FileAccess.file_exists(STAGE_FILE):
		return 0
	var f := FileAccess.open(STAGE_FILE, FileAccess.READ)
	if f == null:
		return 0
	return int(f.get_as_text().strip_edges())

## 保存隔离重载探针的阶段标记。
func _write_stage(value: int) -> void:
	var f := FileAccess.open(STAGE_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(str(value))
