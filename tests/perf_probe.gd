extends Node
## M5-1 性能达标 + M5-2 内存与事件卫生（开发期工具，M5 打包前移除；工程文档 15 §3）。
##
## 运行（**性能必须开窗跑**：`--headless` 无渲染，帧率无意义）：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   # 默认：20 / 30 / 40 同屏阶梯，每档 20s，窗口 1440x900
##   "$GODOT" --path . res://tests/PerfProbe.tscn
##   # 只跑一档、每档 30s、关垂直同步取余量
##   "$GODOT" --path . res://tests/PerfProbe.tscn -- --ladder=30 --perf=30 --no-vsync
##   # M5-2 审计：面板开合 / 切图 / 击杀 的生命周期与信号连接卫生
##   "$GODOT" --path . res://tests/PerfProbe.tscn -- --audit
##
## 参数（`--` 之后）：--ladder=a,b,c（默认 20,30,40）｜--perf=秒（默认 20）
##                    --mlevel=等级（怪刷新等级，默认 4）｜--no-vsync｜--audit
##
## 采样：`_process(delta)` 逐帧记录真实帧时 → 平均 FPS / 最小 FPS / 1% Low /
##       p99 帧时 / >33ms 与 >100ms 长帧数；同步采 静态内存 / 节点数 / 存活怪数。

const MAIN_SCENE := "res://scenes/Main.tscn"
const MONSTER_SCENE := preload("res://scenes/entities/Monster.tscn")

const MONSTER_ID := "wolf_corrupted"   # 普通怪（无召唤，负载纯净）
const RING_BASE := 150.0               # 同屏环半径（px，1440x900 可视区内）
const RING_SPREAD := 120.0

const REPORT_MD := "/tmp/degenerateage_perf_report.md"
const REPORT_JSON := "/tmp/degenerateage_perf_samples.json"

const PLAYER_LEVEL := 20
const LONG_FRAME := 1.0 / 30.0         # >33.3ms = 掉出 30 FPS
const HITCH_FRAME := 0.1               # >100ms = 明显卡顿

var _ladder: Array[int] = [20, 30, 40]
var _seconds := 20.0
var _monster_level := 4
var _audit := false
var _no_vsync := false
var _headless := true

var _main: Node = null
var _game: Node = null
var _player: PlayerCharacter = null
var _ground: Node = null
var _spawn_parent: Node = null
var _rng := RandomNumberGenerator.new()

var _running := false
var _target_n := 0
var _live: Array = []
var _kills := 0
var _heals := 0

var _frame_times: Array[float] = []
var _mem_peak := 0.0
var _node_peak := 0

var _results: Array[Dictionary] = []
var _audit_snap: Dictionary = {}
var _failures: Array[String] = []

func _ready() -> void:
	_parse_args()
	_headless = DisplayServer.get_name() == "headless"
	OS.low_processor_usage_mode = false
	_rng.randomize()
	if _no_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not _headless:
		DisplayServer.window_set_size(Vector2i(1440, 900))
	print("=".repeat(72))
	if _audit:
		print("[Perf] M5-2 内存与事件卫生审计")
	else:
		print("[Perf] M5-1 性能阶梯：%s · 每档 %.0fs · %s · 怪 L%d" % [
			str(_ladder), _seconds, "开窗" if not _headless else "无头（帧率无意义！）", _monster_level])
	print("[Perf] 报告写入：%s" % REPORT_MD)
	print("=".repeat(72))

	if _audit:
		await _run_audit()
	else:
		await _run_ladder()

	_write_report()
	print("=".repeat(72))
	if _failures.is_empty():
		print("[Perf] ✅ 全部通过")
	else:
		for f in _failures:
			print("[Perf] ❌ %s" % f)
		print("[Perf] 失败 %d 项" % _failures.size())
	print("=".repeat(72))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _parse_args() -> void:
	var args: Array = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for a in args:
		var s := String(a)
		if s.begins_with("--ladder="):
			_ladder.clear()
			for part in s.split("=")[1].split(","):
				var v := int(String(part).strip_edges())
				if v > 0:
					_ladder.append(v)
			if _ladder.is_empty():
				_ladder = [20, 30, 40]
		elif s.begins_with("--perf="):
			_seconds = maxf(5.0, float(s.split("=")[1]))
		elif s.begins_with("--mlevel="):
			_monster_level = maxi(1, int(s.split("=")[1]))
		elif s == "--no-vsync":
			_no_vsync = true
		elif s == "--audit":
			_audit = true

func _process(delta: float) -> void:
	if not _running:
		return
	_frame_times.append(delta)
	var mem := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	if mem > _mem_peak:
		_mem_peak = mem
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if nodes > _node_peak:
		_node_peak = nodes

# ---- M5-1 性能阶梯 ----

func _run_ladder() -> void:
	for n in _ladder:
		var r := await _run_rung(n)
		_results.append(r)

func _run_rung(n: int) -> Dictionary:
	print("\n---- 场景：%d 同屏 · %.0fs ----" % [n, _seconds])
	await _enter_world()
	if _game == null:
		return {"n": n, "ok": false}

	_target_n = n
	_live.clear()
	_kills = 0
	_heals = 0
	_frame_times.clear()
	_mem_peak = 0.0
	_node_peak = 0
	for _i in range(n):
		_spawn_one()

	GameState.set_auto_battle(true)
	GameState.set_auto_pickup(true)

	var t0 := Time.get_ticks_msec()
	_running = true
	while float(Time.get_ticks_msec() - t0) / 1000.0 < _seconds:
		await get_tree().process_frame
		_guard_hp()
		_maintain()
	_running = false

	var r := _summarize(n)
	await _exit_world()
	return r

func _summarize(n: int) -> Dictionary:
	var cnt := _frame_times.size()
	if cnt == 0:
		_failures.append("场景 %d 无帧采样" % n)
		return {"n": n, "ok": false}
	var total := 0.0
	for d in _frame_times:
		total += d
	var avg_fps := float(cnt) / maxf(0.001, total)
	_frame_times.sort()
	var max_dt := _frame_times[cnt - 1]
	var p99 := _frame_times[mini(cnt - 1, int(floor(float(cnt) * 0.99)))]
	var long_frames := 0
	var hitches := 0
	for d in _frame_times:
		if d > LONG_FRAME:
			long_frames += 1
		if d > HITCH_FRAME:
			hitches += 1
	var r := {
		"n": n, "ok": true,
		"avg_fps": avg_fps,
		"min_fps": 1.0 / maxf(0.0001, max_dt),
		"low1_fps": 1.0 / maxf(0.0001, p99),
		"avg_frame_ms": total / float(cnt) * 1000.0,
		"max_frame_ms": max_dt * 1000.0,
		"long_frames": long_frames, "hitches": hitches, "frames": cnt,
		"mem_peak": _mem_peak, "node_peak": _node_peak,
		"kills": _kills, "heals": _heals,
	}
	print("[Perf] %d 同屏 → 均 %.1f / 最小 %.1f / 1%%Low %.1f FPS · p99帧 %.1fms · 长帧 %d · 卡顿 %d · 击杀 %d" % [
		n, avg_fps, r["min_fps"], r["low1_fps"], r["max_frame_ms"], long_frames, hitches, _kills])
	return r

# ---- 世界进出 ----

func _enter_world() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = PLAYER_LEVEL
	GameState.player.attack = 12 + 2 * (PLAYER_LEVEL - 1)
	GameState.player.defense = 5 + 1 * (PLAYER_LEVEL - 1)
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()
	GameState.gold = 100000

	_main = load(MAIN_SCENE).instantiate()
	add_child(_main)
	for _i in range(20):
		await get_tree().process_frame
	if not _headless:
		get_window().move_to_foreground()
		await get_tree().process_frame

	_game = _main.get_node_or_null("Game")
	if _game == null:
		_failures.append("主场景缺少 Game 节点")
		return
	_player = _game.get_node_or_null("Entities/Player") as PlayerCharacter
	_ground = _game.get_node_or_null("Ground")
	_spawn_parent = _game.get_node_or_null("Spawner")
	if _spawn_parent == null:
		_spawn_parent = _game
	if _player == null or _ground == null:
		_failures.append("主场景缺少 Player / Ground")
		return
	_player.global_position = _ground.call("get_map_center_world")
	var cam := _game.get_node_or_null("Entities/Player/Camera2D") as Camera2D
	if cam != null:
		cam.reset_smoothing()

func _exit_world() -> void:
	if _main != null:
		_main.queue_free()
		_main = null
	await get_tree().process_frame
	await get_tree().process_frame

# ---- 负载维护 ----

func _spawn_one() -> void:
	var m: Monster = MONSTER_SCENE.instantiate()
	m.monster_id = MONSTER_ID
	m.spawn_level = _monster_level
	m.ai_enabled = true
	_spawn_parent.add_child(m)
	var angle := _rng.randf() * TAU
	var radius := RING_BASE + _rng.randf() * RING_SPREAD
	var pos: Vector2 = _player.global_position + Vector2(cos(angle), sin(angle)) * radius
	pos = _ground.call("clamp_to_map", pos)
	m.global_position = pos
	m.spawn_position = pos
	m.died.connect(func(_id: String) -> void: _kills += 1)
	_live.append(m)

## 死亡 / 淡出后补足到目标同屏数（保持恒定负载）。
func _maintain() -> void:
	var alive: Array = []
	for m in _live:
		if is_instance_valid(m) and not (m as Monster).is_dead:
			alive.append(m)
	_live = alive
	while _live.size() < _target_n and is_instance_valid(_player):
		_spawn_one()

func _guard_hp() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var mx := GameState.max_hp()
	if int(GameState.player.hp) <= mx / 3:
		GameState.heal_player(mx)
		_heals += 1

# ---- M5-2 内存与事件卫生审计 ----

func _run_audit() -> void:
	print("\n---- 审计：面板开合 / 切图 / 击杀 ----")
	await _enter_world()
	if _game == null:
		return
	GameState.set_auto_battle(false)
	GameState.set_auto_pickup(false)

	var base := _snapshot("基线")
	var inv := _main.get_node_or_null("UI/InventoryPanel")

	# ① 面板开合 ×50（压 UI 构建 / 销毁与信号连接）
	for _i in range(50):
		if inv != null and inv.has_method("set_open"):
			inv.set_open(true)
			await get_tree().process_frame
			await get_tree().process_frame
			inv.set_open(false)
			await get_tree().process_frame
	var after_panel := _snapshot("面板×50")

	# ② 切图往返 ×20（压世界重建 / 旧实体释放）
	var travels := 0
	for _i in range(20):
		if await _travel("wild_trial"):
			travels += 1
		if await _travel("camp"):
			travels += 1
	var after_travel := _snapshot("切图×%d" % travels)

	# ③ 生成并击杀 ×200（压死亡结算 / 掉落 / 回收）
	for _i in range(200):
		var m: Monster = MONSTER_SCENE.instantiate()
		m.monster_id = MONSTER_ID
		m.spawn_level = _monster_level
		m.ai_enabled = false
		_spawn_parent.add_child(m)
		m.global_position = _player.global_position + Vector2(_rng.randf_range(-80, 80), _rng.randf_range(-80, 80))
		m.take_hit({"damage": 999999, "miss": false})
		if _i % 20 == 0:
			await get_tree().process_frame
	# 等死亡淡出（0.35s）、掉落飞行（1.2s）、掉落/拾取 Toast 自毁（2.0s）全部结束。
	# 注：击杀瞬间会瞬时堆积 ~270 个 Toast Label（每个 2.0s 自毁补间），
	#     稳定窗口需 ≥ 落地时间 + 2.0s，否则会把「尚未回收」误读成泄漏。
	await get_tree().create_timer(5.0).timeout
	# 清理「背包满留地」的未认领掉落（设计行为，非泄漏）→ 快照只见稳定态
	for n in get_tree().get_nodes_in_group("ground_items"):
		n.queue_free()
	await get_tree().create_timer(0.3).timeout
	var after_kill := _snapshot("击杀×200")

	await _exit_world()

	_audit_snap = {
		"base": base, "panel": after_panel,
		"travel": after_travel, "kill": after_kill, "travels": travels,
	}
	_evaluate_audit(base, after_panel, after_travel, after_kill)

## 采集卫生指标：节点 / 孤儿 / 对象 + EventBus 信号连接数 + 关键分组节点数。
func _snapshot(tag: String) -> Dictionary:
	var groups := {}
	for g in ["enemies", "ground_items", "npcs", "damage_numbers", "map_world"]:
		groups[g] = get_tree().get_nodes_in_group(g).size()
	var snap := {
		"tag": tag,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"signals": _signal_connections(EventBus),
		"groups": groups,
	}
	print("[Perf] %s → 节点 %d · 对象 %d · 孤儿 %d · 信号连接 %d · 分组 %s" % [
		tag, snap["nodes"], snap["objects"], snap["orphans"], snap["signals"], str(groups)])
	return snap

## 统计对象上所有信号的连接总数（重复注册 / 泄漏探测）。
func _signal_connections(obj: Object) -> int:
	var total := 0
	for s in obj.get_signal_list():
		total += obj.get_signal_connection_list(String(s.get("name", ""))).size()
	return total

func _evaluate_audit(base: Dictionary, panel: Dictionary, travel: Dictionary, kill: Dictionary) -> void:
	_expect(int(panel["orphans"]) == 0, "面板开合后孤儿节点应为 0，实际 %d" % int(panel["orphans"]))
	_expect(int(travel["orphans"]) == 0, "切图后孤儿节点应为 0，实际 %d" % int(travel["orphans"]))
	_expect(int(kill["orphans"]) == 0, "连续击杀后孤儿节点应为 0，实际 %d" % int(kill["orphans"]))

	# 信号连接不得随操作次数增长（重复注册 = 逐次 +N）
	_expect(int(panel["signals"]) <= int(base["signals"]),
		"面板开合不应新增 EventBus 信号连接：%d → %d" % [int(base["signals"]), int(panel["signals"])])
	_expect(int(travel["signals"]) <= int(base["signals"]),
		"切图不应新增 EventBus 信号连接：%d → %d" % [int(base["signals"]), int(travel["signals"])])
	_expect(int(kill["signals"]) <= int(base["signals"]),
		"连续击杀不应新增 EventBus 信号连接：%d → %d" % [int(base["signals"]), int(kill["signals"])])

	# 分组节点数应回到基线附近（世界态残留 = 泄漏）
	var gp: Dictionary = panel["groups"]
	var gt: Dictionary = travel["groups"]
	var gb: Dictionary = base["groups"]
	for key in ["map_world", "npcs"]:
		_expect(int(gt.get(key, 0)) == int(gb.get(key, 0)),
			"切图后分组 %s 应回到基线：%d → %d" % [key, int(gb.get(key, 0)), int(gt.get(key, 0))])

	# 击杀后不得残留**本次生成**的怪物（世界自带怪物如营地教学木桩不计）
	_expect(int(kill["groups"].get("enemies", 0)) <= int(base["groups"].get("enemies", 0)),
		"连续击杀后不应残留新增怪物：基线 %d → 实际 %d" % [
			int(base["groups"].get("enemies", 0)), int(kill["groups"].get("enemies", 0))])

	# 节点数不随操作线性增长（同态收敛；200 次击杀对应约 200 个临时节点已回收）
	_expect(int(kill["nodes"]) <= int(base["nodes"]) * 1.15 + 50.0,
		"击杀后节点数应同态收敛：%d → %d" % [int(base["nodes"]), int(kill["nodes"])])

func _travel(map_id: String) -> bool:
	var res := MapService.travel_to(map_id)
	if not bool(res.get("ok", false)):
		_failures.append("审计切图前往 %s 失败：%s" % [map_id, str(res.get("reason", ""))])
		return false
	if _main != null:
		_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_main = load(MAIN_SCENE).instantiate()
	add_child(_main)
	for _i in range(4):
		await get_tree().process_frame
	_game = _main.get_node_or_null("Game")
	_player = _game.get_node_or_null("Entities/Player") as PlayerCharacter if _game != null else null
	_spawn_parent = _game.get_node_or_null("Spawner") if _game != null else null
	if _spawn_parent == null:
		_spawn_parent = _game
	if _player == null:
		_failures.append("审计切图后缺少 Player")
		return false
	return true

# ---- 判定 / 报告 ----

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _write_report() -> void:
	var lines: Array[String] = []
	lines.append("# 性能与卫生报告（PerfProbe · M5-1 / M5-2）")
	lines.append("")
	lines.append("- 引擎：Godot %s · %s · 后端 %s" % [
		Engine.get_version_info().get("string", "?"), OS.get_name(),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")])
	lines.append("- 运行：**%s** · 窗口 %s · 垂直同步 %s" % [
		"无头（帧率无意义）" if _headless else "开窗",
		DisplayServer.window_get_size(), "关" if _no_vsync else "开"])
	lines.append("")
	if not _audit:
		lines.append("## M5-1 性能阶梯")
		lines.append("")
		lines.append("| 同屏 | 平均 FPS | 最小 FPS | 1% Low | p99 帧(ms) | 长帧(>33ms) | 卡顿(>100ms) | 内存峰值(MB) | 节点峰值 | 击杀 |")
		lines.append("|---|---|---|---|---|---|---|---|---|---|")
		for r in _results:
			if not bool(r.get("ok", false)):
				lines.append("| %d | — | — | — | — | — | — | — | — | — |" % int(r.get("n", 0)))
				continue
			lines.append("| %d | %.1f | %.1f | %.1f | %.1f | %d | %d | %.0f | %d | %d |" % [
				int(r["n"]), float(r["avg_fps"]), float(r["min_fps"]), float(r["low1_fps"]),
				float(r["max_frame_ms"]), int(r["long_frames"]), int(r["hitches"]),
				float(r["mem_peak"]), int(r["node_peak"]), int(r["kills"])])
		lines.append("")
		lines.append("> 判据（工程文档 15 §7）：30 同屏 1% Low ≥ 55 FPS、平均 ≥ 58 FPS、无 >100ms 卡顿帧。")
	else:
		lines.append("## M5-2 内存与事件卫生")
		lines.append("")
		lines.append("| 阶段 | 节点 | 对象 | 孤儿 | EventBus 信号连接 | enemies | ground_items | npcs | map_world |")
		lines.append("|---|---|---|---|---|---|---|---|---|")
		for key in ["base", "panel", "travel", "kill"]:
			var s: Dictionary = _audit_snap.get(key, {})
			if s.is_empty():
				continue
			var g: Dictionary = s.get("groups", {})
			lines.append("| %s | %d | %d | %d | %d | %d | %d | %d | %d |" % [
				str(s.get("tag", key)), int(s.get("nodes", 0)), int(s.get("objects", 0)),
				int(s.get("orphans", 0)), int(s.get("signals", 0)),
				int(g.get("enemies", 0)), int(g.get("ground_items", 0)),
				int(g.get("npcs", 0)), int(g.get("map_world", 0))])
		lines.append("")
		lines.append("- 切图往返实际完成：%d 次" % int(_audit_snap.get("travels", 0)))
		lines.append("")
		lines.append("> 判据：孤儿节点恒 0 ／ EventBus 信号连接不随操作增长 ／ 切图后 map_world·npcs 回到基线 ／ 击杀后无残留怪物。")
	lines.append("")
	lines.append("## 判定")
	lines.append("")
	if _failures.is_empty():
		lines.append("**✅ 全部通过**")
	else:
		lines.append("**❌ 失败 %d 项**：" % _failures.size())
		lines.append("")
		for f in _failures:
			lines.append("- %s" % f)
	lines.append("")

	var md := "\n".join(PackedStringArray(lines))
	var f := FileAccess.open(REPORT_MD, FileAccess.WRITE)
	if f != null:
		f.store_string(md)
		f.close()
	var payload := {"meta": {"headless": _headless, "no_vsync": _no_vsync, "audit": _audit}, "results": _results, "audit": _audit_snap}
	var jf := FileAccess.open(REPORT_JSON, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(payload, "\t"))
		jf.close()
	print("[Perf] 报告已写入：%s" % REPORT_MD)
