class_name CrashTrace
extends RefCounted
## 有界崩溃取证：关键事件立即落盘，心跳限频，普通怪死亡聚合。
## 仅写user目录日志，不修改存档或玩法；保留当前及上一份各2MiB，写入失败只停诊断。

const ENABLED := true
const PATH := "user://crash_trace.log"
const PREV_PATH := "user://crash_trace.prev.log"
const MAX_FILE_BYTES := 2 * 1048576
const MAX_EXTRA_CHARS := 1800
const FAST_PULSE_SECONDS := 0.5
const SLOW_PULSE_SECONDS := 2.0
const FAST_PULSES := 1200
const HEARTBEAT_NAME := "CrashTraceHeartbeat"

static var _file: FileAccess
static var _lines := 0
static var _pulses := 0
static var _last_pulse_ms := 0
static var _disabled := false
static var _last_error := OK
static var _counts: Dictionary = {}
static var _deep := OS.get_environment("DEGENERATEAGE_TRACE_VERBOSE") == "1"

## 关闭当前句柄，供轮转与隔离验证使用，不删除任何证据。
static func close() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null

## 文件错误只警告一次并停用当前会话诊断，避免反复I/O或影响交易结算。
static func _stop(error: int) -> bool:
	close()
	_last_error = error
	if not _disabled:
		push_warning("CrashTrace日志写入已停止，错误码：%d" % error)
	_disabled = true
	return false

## 写入前检查当前文件，而非只在进程启动时轮转；错误时保留当前证据并停止追加。
static func _rotate_if_needed(incoming_bytes: int = 0) -> bool:
	var size := 0
	if _file != null:
		size = _file.get_length()
	elif FileAccess.file_exists(PATH):
		var existing := FileAccess.open(PATH, FileAccess.READ)
		if existing == null:
			return _stop(FileAccess.get_open_error())
		size = existing.get_length()
		existing.close()
	if size + incoming_bytes <= MAX_FILE_BYTES:
		return true
	close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return _stop(DirAccess.get_open_error())
	# 不删除同名目录，也不在rename失败后覆盖当前日志。
	if dir.dir_exists(PREV_PATH.get_file()):
		return _stop(ERR_ALREADY_EXISTS)
	if dir.file_exists(PREV_PATH.get_file()):
		var removed := dir.remove(PREV_PATH.get_file())
		if removed != OK:
			return _stop(removed)
	var renamed := dir.rename(PATH.get_file(), PREV_PATH.get_file())
	if renamed != OK:
		return _stop(renamed)
	return true

## 追加打开日志，只有文件不存在才新建；不能以WRITE兜底破坏既有只读证据。
static func _open() -> bool:
	if _disabled:
		return false
	if _file != null:
		return true
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(PATH) else FileAccess.WRITE
	_file = FileAccess.open(PATH, mode)
	if _file == null:
		return _stop(FileAccess.get_open_error())
	_file.seek_end()
	return true

## 关键事件立即flush；限制单条长度并转义换行，防单条超大记录越过轮转上限。
static func mark(tag: String, extra: String = "") -> void:
	if not ENABLED or _disabled:
		return
	var line := "M %s +%.3f f%d %s" % [Time.get_datetime_string_from_system(),Time.get_ticks_msec()/1000.0, Engine.get_process_frames(), tag.left(96).replace("\n","\\n")]
	if not extra.is_empty():
		line += " " + extra.left(MAX_EXTRA_CHARS).replace("\n","\\n")
	if extra.length() > MAX_EXTRA_CHARS:
		line += " [truncated]"
	var bytes := line.to_utf8_buffer().size() + 1
	if not _rotate_if_needed(bytes) or not _open():
		return
	_file.store_line(line)
	_file.flush()
	if _file.get_error() != OK:
		_stop(_file.get_error())
	_lines += 1

## 是否开启逐事件取证；常态保留关键事件，深度模式由启动环境变量显式启用。
static func verbose_enabled() -> bool:
	return _deep

## 高频事件只累计计数；键数固定上限，不能因动态tag无限占用内存。
static func count_event(tag: String) -> void:
	if not ENABLED or _disabled:
		return
	if _deep:
		mark(tag)
		return
	var key := tag if _counts.has(tag) or _counts.size() < 31 else "other"
	_counts[key] = int(_counts.get(key,0)) + 1

## 心跳独立于关键事件条数，不因连续重铸而提前停记；文件边界由轮转保证。
static func _pulse_ready() -> bool:
	if not ENABLED or _disabled:
		return false
	var interval := FAST_PULSE_SECONDS if _pulses < FAST_PULSES else SLOW_PULSE_SECONDS
	var now := Time.get_ticks_msec()
	if now - _last_pulse_ms < int(interval * 1000.0):
		return false
	_last_pulse_ms = now
	_pulses += 1
	return true

## 取走本次心跳前聚合的少量计数，避免普通击杀逐条刷盘。
static func _summary() -> String:
	var parts: Array[String] = []
	for key in _counts:
		parts.append("%s=%d" % [key,int(_counts[key])])
	_counts.clear()
	return " counts=" + ",".join(parts) if not parts.is_empty() else ""

## 写节流后的心跳，保留关键事件即时写入的独立通道。
static func pulse(tag: String, extra: String = "") -> void:
	if _pulse_ready():
		mark(tag, extra + _summary())

## 仅在过心跳闸门后采集内存与节点指标，避免无意义的高频格式化。
static func sample(tag: String, extra: String = "") -> void:
	if not _pulse_ready():
		return
	mark(tag, "mem=%.1fMB obj=%d orphan=%d wt=%.1f %s" % [
		Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),GameState.world_time,extra] + _summary())

## 世界运行时的节流快照；暂停时由ALWAYS心跳补位，共用同一节流闸门。
static func tick(player_pos: Vector2, extra: String = "") -> void:
	if not _pulse_ready():
		return
	mark("tick", "pos=(%.0f,%.0f) mem=%.1fMB obj=%d wt=%.1f %s" % [
		player_pos.x,player_pos.y,Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),GameState.world_time,extra] + _summary())

class Heartbeat extends Node:
	## 面板暂停时仍保留限频取证；没有场景对象的静态强引用。
	func _process(_delta: float) -> void:
		CrashTrace.pulse("hb", "paused=" + ("1" if get_tree().paused else "0"))

## 挂载唯一的低频心跳宿主，跨场景重载复用；不建立额外autoload。
static func attach_heartbeat(tree: SceneTree) -> void:
	if not ENABLED or tree == null or tree.root.get_node_or_null(HEARTBEAT_NAME) != null:
		return
	var node := Heartbeat.new()
	node.name = HEARTBEAT_NAME
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(node)
	mark("trace.session", "engine=" + String(Engine.get_version_info().get("string","?")) + " display=" + DisplayServer.get_name())
