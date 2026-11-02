extends Node
## 必须通过tools/run_isolated_probe.py启动；隔离由项目身份强制检查，不能只依赖HOME约定。
## 工程 116：**玩家完整路径**崩溃复现探针（只读，必须隔离 HOME）。
##
## 路径：读档 → `reload_world()`（整场景重载）→ 新场景建世界 → 打开重铸面板
##       → 持续重铸 N 秒（每 0.2 秒一次，接近玩家手速）。
##
## 覆盖世界负载与重铸并行的调查路径；第三轮已确认主要触发是布局反馈，墓碑负载不是必要条件。
##
## 运行：
##   HOME=/tmp/deg_iso Godot --path . res://tools/FullPathProbe.tscn
##
## 🔴 必须隔离 HOME：会读档，引擎退出回写 `last_slot`（MEMORY 坑 106）。

## 重铸持续秒数。
const REFORGE_SECONDS := 8.0

## 两次重铸的间隔（秒）。玩家实测约 0.66 秒/次（3 小时 1.6 万次），
## 这里取 0.2 秒压测，同一个 bug 只会更早暴露。
const REFORGE_INTERVAL := 0.2

const STAGE_FILE := "user://full_path_probe_stage.txt"
const RUNE_ID := "rune_diamond"

## 隔离身份通过后按阶段继续完整路径探针。
func _ready() -> void:
	if not DiagnosticProbeGuard.require_isolated(self):
		return
	var stage := _read_stage()
	print("[Probe] _ready 阶段=%d" % stage)
	if stage == 0:
		await _stage_a()
	else:
		await _stage_b()

## 在隔离目录读取副本并发起场景重载。
func _stage_a() -> void:
	_write_stage(1)
	SaveManager.active_slot = -1
	GameState.menu_mode = "world"
	var res: Dictionary = SaveManager.load_into_game(1)
	print("[Probe][A] 读档 ok=%s → reload_world" % res.get("ok", false))
	MapService.reload_world()
	await get_tree().create_timer(30.0).timeout
	print("[Probe][A] ⚠ 30 秒未发生重载")

## 重载后打开真实面板并持续操作。
func _stage_b() -> void:
	print("[Probe][B] 重载完成，建世界")
	SaveManager.active_slot = 1
	GameState.menu_mode = "world"
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = main
	await get_tree().process_frame

	var panel: Node = main.get_node_or_null("UI/ReforgePanel")
	if panel == null:
		print("[Probe][B] ❌ 无重铸面板")
		get_tree().quit(1)
		return
	panel.set_open(true)
	await get_tree().process_frame

	var picked := -1
	var choices: Array = panel.get("_choices")
	for i in range(choices.size()):
		var row: Dictionary = choices[i]
		if String(row.get("source", "")) == "worn" and String(row.get("key", "")) == "weapon":
			picked = i
			break
	if picked < 0:
		print("[Probe][B] ❌ 候选中没有穿戴武器（%d 条）" % choices.size())
		get_tree().quit(1)
		return
	panel.select_choice(picked)
	var runes: Array = [RUNE_ID, RUNE_ID, RUNE_ID, RUNE_ID]
	panel.set("_rune_choices", runes)
	panel.call("_refresh_runes")
	await get_tree().process_frame
	print("[Probe][B] 面板就绪，候选 %d 条，开始连续重铸" % choices.size())

	var rounds := int(REFORGE_SECONDS / REFORGE_INTERVAL)
	for i in range(rounds):
		panel.call("_on_reforge")
		await get_tree().create_timer(REFORGE_INTERVAL).timeout
		var weapon: Dictionary = GameState.equipment.get("weapon", {})
		print("[Probe][B] 第 %d 次重铸完成 frame=%d gold=%d tier=%s" % [
			i + 1, Engine.get_process_frames(), GameState.gold,
			weapon.get("reforgeAffixTier", 0)])

	print("[Probe][B] === 连续重铸 %.1f 秒未崩溃 ===" % REFORGE_SECONDS)
	_write_stage(0)
	get_tree().quit(0)

## 读取隔离user目录的探针阶段标记。
func _read_stage() -> int:
	if not FileAccess.file_exists(STAGE_FILE):
		return 0
	var f := FileAccess.open(STAGE_FILE, FileAccess.READ)
	return 0 if f == null else int(f.get_as_text().strip_edges())

## 写入本次隔离探针的重载阶段标记。
func _write_stage(value: int) -> void:
	var f := FileAccess.open(STAGE_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(str(value))
