class_name CrashTrace
extends RefCounted
## 工程 116：闪退取证埋点。**只写日志文件，不改任何游戏行为、不碰存档。**
##
## 为什么需要它：本次闪退是 `SIGSEGV`（引擎 C++ 层），GDScript 层不会抛错，
## 日志里也找不到任何 `SCRIPT ERROR`。唯一能定位的办法是让程序在崩溃前
## 「自己说出最后做到了哪一步」，于是崩掉之后去看日志最后几行即可。
##
## 设计约束（都是踩过的坑）：
## 1. 🔴 **每条都 `flush()`**：崩溃时进程被信号杀死，用户态缓冲区不会落盘，
##    不刷盘等于最后几十行白记。
## 2. 🔴 **必须极轻**：埋点本身会改变帧时序，而本 bug 对时序高度敏感
##    （加 `--verbose` / `--fixed-fps` 就复现不出来）。所以：
##      关键事件 → 逐条写盘；逐帧信息 → 只在心跳里落一次（前 10 分钟 0.5s，之后 2s）。
## 3. 🔴 **不挂 autoload**：用 `static var` 就够了，避免影响 `--quit` 的 leak 基线
##    与既有面板计数断言。
## 4. 🔴 **日志必须活到崩溃那一刻**：本 bug 的复现点是**玩了三小时之后**，
##    所以文件写满时是归档成 `.prev` 而不是覆盖，心跳也会自动放慢 —— 见下方常量。
##
## 日志位置：`user://crash_trace.log`（写满后旧档归档为 `user://crash_trace.prev.log`）
##   macOS: ~/Library/Application Support/Godot/app_userdata/末法纪元：最后的守护者/crash_trace.log

## 一键关闭：把 `ENABLED` 改 false 即可，其余代码不用动。
const ENABLED := true

const PATH := "user://crash_trace.log"

## 上一份被挤出时的归档。玩家交日志时**两个文件都要**（真崩的那份常在这里）。
const PREV_PATH := "user://crash_trace.prev.log"

## 心跳节流：前 10 分钟内 0.5s 一条（看得清细节），之后放慢到 2s（够用且省盘）。
## 🔴 必须分档：本 bug 的复现点是**玩了三小时之后**，若全程 0.5s，
## 8000 行只够 66 分钟 —— 恰恰在崩溃前两小时就停记了，埋点等于白埋（本轮已踩）。
const FAST_PULSE_SECONDS := 0.5
const SLOW_PULSE_SECONDS := 2.0
const FAST_PULSES := 1200

## 行数硬上限：到顶后**只停心跳，关键事件照记**。按上面的分档，3 小时约 6000 行，
## 这里是 4 倍的余量，正常玩永远碰不到。
const MAX_LINES := 24000

static var _file: FileAccess = null
static var _lines := 0
static var _pulses := 0
static var _last_pulse_ms := 0
static var _pulse_stopped := false

## 单个日志文件的上限。超过就**归档到 .prev 再开新档**，绝不整体覆盖 ——
## 覆盖会把上一次崩溃的记录清掉，等于把唯一证据扔了。
const MAX_FILE_BYTES := 2 * 1048576

static func _rotate_if_needed() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var size := f.get_length()
	f.close()
	if size <= MAX_FILE_BYTES:
		return
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var prev_name := PREV_PATH.get_file()
	# 目标已存在时部分平台会报错，先删；只保留最近一份归档，不无限堆积。
	if dir.file_exists(prev_name):
		dir.remove(prev_name)
	dir.rename(PATH.get_file(), prev_name)

static func _open() -> bool:
	if _file != null:
		return true
	# 🔴 必须**追加**而不是覆盖：玩家崩溃后往往会立刻重开游戏再看一眼，
	# 若用 WRITE 覆盖，崩溃那一刻的记录会被下一次启动直接清掉 —— 等于白埋。
	_rotate_if_needed()
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.seek_end()
	_file = f
	_file.store_line("")
	_file.store_line("# ===== CrashTrace 会话开始 " + Time.get_datetime_string_from_system() + " =====")
	_file.store_line("# engine=" + String(Engine.get_version_info().get("string", "?"))
		+ " display=" + DisplayServer.get_name()
		+ " frames=" + str(Engine.get_process_frames()))
	_file.flush()
	return true

## 关键事件：立刻落盘。`tag` 用点号分层（`game.ready.monsters`），便于 grep。
static func mark(tag: String, extra: String = "") -> void:
	if not ENABLED:
		return
	if not _open():
		return
	if _file == null:
		return
	_lines += 1
	var line := "M " + ("%.3f" % (Time.get_ticks_msec() / 1000.0)) \
		+ " f" + str(Engine.get_process_frames()) + " " + tag
	if not extra.is_empty():
		line += " " + extra
	_file.store_line(line)
	# 🔴 崩溃时缓冲区会丢；这一行不能省。
	_file.flush()

## 当前档位的心跳间隔（毫秒）。
static func _pulse_interval_ms() -> int:
	if _pulses < FAST_PULSES:
		return int(FAST_PULSE_SECONDS * 1000.0)
	return int(SLOW_PULSE_SECONDS * 1000.0)

## 心跳闸门：上限 + 节流。**先过闸门再拼字符串** —— 每帧只做一次整数比较，
## 不能因为埋点把主循环拖慢（本 bug 对时序敏感，埋点本身不能改变它）。
static func _pulse_ready() -> bool:
	if not ENABLED or _pulse_stopped:
		return false
	if _lines >= MAX_LINES:
		_pulse_stopped = true
		mark("trace.pulse_stopped", "lines=" + str(_lines))
		return false
	var now := Time.get_ticks_msec()
	if now - _last_pulse_ms < _pulse_interval_ms():
		return false
	_last_pulse_ms = now
	_pulses += 1
	return true

## 逐帧类信息：按当前档位的间隔节流。
static func pulse(tag: String, extra: String = "") -> void:
	if not _pulse_ready():
		return
	mark(tag, extra)

## 结构化快照：把几个关键指标拼成一行，崩溃前若某项突变能直接看出来。
static func sample(tag: String, extra: String = "") -> void:
	if not ENABLED:
		return
	var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var body := "mem=%.1fMB obj=%d orphan=%d wt=%.1f" % [
		mem_mb,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		GameState.world_time]
	if not extra.is_empty():
		body += " " + extra
	pulse(tag, body)

## 逐帧心跳。节流判定在 `_pulse_ready()` 里，本函数只在过闸门后才拼字符串。
static func tick(player_pos: Vector2, extra: String = "") -> void:
	if not _pulse_ready():
		return
	var body := "pos=(%.0f,%.0f) mem=%.1fMB obj=%d wt=%.1f" % [
		player_pos.x, player_pos.y,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		GameState.world_time]
	if not extra.is_empty():
		body += " " + extra
	mark("tick", body)

## 面板打开时 `get_tree().paused = true`，`Game._process` 会整体停摆 ⇒ 逐帧心跳断掉。
## 而玩家正是在「开面板操作」时崩的，这段盲区必须补上：另挂一个
## `PROCESS_MODE_ALWAYS` 的空节点专做心跳，**只写日志、不读不写任何游戏状态**
## （除 `paused` 本身），因此不会改变任何玩法行为。
class Heartbeat extends Node:
	func _process(_delta: float) -> void:
		if not CrashTrace.ENABLED:
			return
		CrashTrace.pulse("hb", "paused=" + ("1" if get_tree().paused else "0"))

const HEARTBEAT_NAME := "CrashTraceHeartbeat"

## 挂心跳节点。可重复调用（切场景不会重复挂），节点挂在 root 下、不参与场景重载。
## 🔴 不把节点存进 `static var`：静态变量持有 Node 会在退出时变成悬垂引用，
## 直接污染 `--quit` 的 leak 基线。改成按名字查，注册表由场景树自己管。
static func attach_heartbeat(tree: SceneTree) -> void:
	if not ENABLED or tree == null:
		return
	if tree.root.get_node_or_null(HEARTBEAT_NAME) != null:
		return
	var node := Heartbeat.new()
	node.name = HEARTBEAT_NAME
	# 🔴 必须显式 ALWAYS：菜单/面板会 `get_tree().paused = true`，
	# 默认的继承模式会让心跳跟着一起停 —— 那正好是最需要日志的时候（已踩）。
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(node)
	mark("trace.heartbeat", "attached")
