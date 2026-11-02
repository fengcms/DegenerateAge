class_name FrameLayoutScheduler
extends RefCounted
## 按帧合并容器布局请求，保留执行期间产生的末次更新，禁止同帧deferred自激。
## 每个宿主持有一个实例；首轮同帧合并，后续脏更新跨帧，宿主释放后安全放弃回调。

var _owner: WeakRef
var _action: Callable
var _pending := false
var _running := false
var _dirty := false
var _last_frame := -1

## 为一个已进树的宿主绑定布局动作；不接管宿主的显示、交易或拖动状态。
func _init(owner: Node, action: Callable) -> void:
	_owner = weakref(owner)
	_action = action

## 标记待布局。已有请求或正在执行时只保留dirty，不重复塞入消息队列。
func request() -> void:
	_dirty = true
	if not _pending and not _running:
		_arm()

## 用户打开或改变分区时允许本帧即时布局；本帧已执行则保留请求到下一帧。
func flush_now() -> void:
	_dirty = true
	if _running or _last_frame == Engine.get_process_frames():
		request()
		return
	_run()

## 首轮走同帧deferred保持响应；已经执行过布局则订阅下一帧，不持有宿主强引用。
func _arm() -> void:
	var owner: Node = _owner.get_ref()
	if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion():
		_dirty = false
		return
	_pending = true
	if _last_frame == Engine.get_process_frames():
		owner.get_tree().process_frame.connect(_on_frame, CONNECT_ONE_SHOT)
	else:
		_on_frame.call_deferred()

## 帧开始时处理待更新状态；多次请求合并，销毁后的宿主不再执行。
func _on_frame() -> void:
	_pending = false
	if not _dirty:
		return
	_run()

## 每个渲染帧至多调用一次动作；动作内的新请求留待下一帧，不能静默丢弃。
func _run() -> void:
	var owner: Node = _owner.get_ref()
	if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion() or not _action.is_valid():
		_dirty = false
		return
	if _last_frame == Engine.get_process_frames():
		if not _pending:
			_arm()
		return
	_last_frame = Engine.get_process_frames()
	_dirty = false
	_running = true
	_action.call()
	_running = false
	if _dirty and not _pending:
		_arm()
