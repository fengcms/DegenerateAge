extends Node
## 隔离日志边界：运行期轮转、单条截断、事件聚合、心跳预算及文件错误保留证据。
var failures: Array[String] = []

## 聚合失败，不使用任何玩家目录或存档。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 仅删除当前隔离项目的日志夹具，复位静态诊断状态。
func reset_trace() -> void:
	CrashTrace.close()
	for path in [CrashTrace.PATH,CrashTrace.PREV_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	CrashTrace._disabled = false
	CrashTrace._last_error = OK
	CrashTrace._counts.clear()

## 先验证持续写入再模拟轮转失败，确认诊断错误不会继续覆盖证据。
func _ready() -> void:
	reset_trace()
	var payload := "汉".repeat(3000)
	for i in range(450):
		CrashTrace.mark("critical",payload)
	check(FileAccess.file_exists(CrashTrace.PREV_PATH), "运行过程中已轮转，不依赖重启")
	check(FileAccess.get_file_as_bytes(CrashTrace.PATH).size() <= CrashTrace.MAX_FILE_BYTES, "当前日志受大小上限约束")
	check(FileAccess.get_file_as_bytes(CrashTrace.PREV_PATH).size() <= CrashTrace.MAX_FILE_BYTES, "上一份日志受大小上限约束")
	check(FileAccess.get_file_as_string(CrashTrace.PATH).contains("[truncated]"), "超长单条已截断")
	var count_before := CrashTrace._lines
	for i in range(1000):
		CrashTrace.count_event("normal.dead")
	check(CrashTrace._lines == count_before, "普通事件不逐条刷盘")
	CrashTrace._last_pulse_ms = -10000
	CrashTrace._lines = 999999
	CrashTrace.pulse("hb")
	check(FileAccess.get_file_as_string(CrashTrace.PATH).contains("normal.dead=1000"), "心跳输出聚合且不受关键事件条数截断")
	reset_trace()
	CrashTrace.mark("evidence","keep")
	var padding := PackedByteArray()
	padding.resize(CrashTrace.MAX_FILE_BYTES)
	CrashTrace._file.store_buffer(padding)
	CrashTrace._file.flush()
	DirAccess.make_dir_absolute(CrashTrace.PREV_PATH)
	CrashTrace.mark("rotation","must_stop")
	check(CrashTrace._disabled and CrashTrace._last_error != OK, "轮转错误只停诊断")
	check(FileAccess.get_file_as_string(CrashTrace.PATH).begins_with("M "), "轮转失败保留原文件证据")
	DirAccess.remove_absolute(CrashTrace.PREV_PATH)
	reset_trace()
	print("[CrashTraceTest] ","全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
