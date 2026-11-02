extends Node
## 按帧布局契约：同帧合并、末次更新、暂停期间可执行及销毁后的回调取消。
var failures: Array[String] = []

class Host extends Node:
	var scheduler: FrameLayoutScheduler
	var wanted := 1
	var applied := 0
	var calls := 0
	var frames: Dictionary = {}
	## 模拟布局中同步发出最小尺寸变化信号，第二次更新必须留到下一帧。
	func apply_layout() -> void:
		calls += 1
		var frame := Engine.get_process_frames()
		frames[frame] = int(frames.get(frame,0)) + 1
		applied = wanted
		if calls == 1:
			wanted = 2
			scheduler.request()

## 收集独立契约失败，不改游戏数据。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 以真实帧信号推进并验证没有无限deferred循环或丢失尾部请求。
func _ready() -> void:
	var host := Host.new()
	add_child(host)
	host.scheduler = FrameLayoutScheduler.new(host, host.apply_layout)
	for i in range(100):
		host.scheduler.request()
	for i in range(6):
		await get_tree().process_frame
	check(host.calls == 2 and host.applied == 2, "本帧100次请求合并且保留执行中的末次变化")
	for count in host.frames.values():
		check(count == 1, "每帧至多执行一次")
	get_tree().paused = true
	host.wanted = 3
	host.scheduler.request()
	for i in range(3):
		await get_tree().process_frame
	get_tree().paused = false
	check(host.applied == 3, "面板暂停期间仍可重排")
	var calls_before := host.calls
	for i in range(100):
		host.scheduler.flush_now()
	check(host.calls <= calls_before + 1, "同步入口也不能绕过帧预算")
	for i in range(3):
		await get_tree().process_frame
	host.scheduler.request()
	host.queue_free()
	for i in range(3):
		await get_tree().process_frame
	check(not is_instance_valid(host), "挂起的帧请求不延长宿主生命周期")
	print("[FrameLayoutSchedulerTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
