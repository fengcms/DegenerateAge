class_name StableFollowCamera
extends Camera2D
## 玩家镜头使用真实时间指数跟随，游戏倍速只影响玩法，不放大相机插值系数。
## 相机脱离父变换但仍随玩家节点释放；无资源缓存、计时器或全局订阅。
const FOLLOW_RATE := 8.0
const MAX_REAL_STEP := 0.1
var _target: Node2D
var _follow_position := Vector2.ZERO
var _last_usec := 0

## 保留父节点作为跟随目标，关闭会在大scaled delta下发散的原生线性平滑。
func _ready() -> void:
	_target = get_parent() as Node2D
	position_smoothing_enabled = false
	top_level = true
	process_priority = 100
	snap_to_target()

## 使用单调微秒时钟；不除以Engine.time_scale，支持暂停、零倍率与运行时改倍率。
func _process(_scaled_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := maxf(0.0, (now - _last_usec) / 1000000.0)
	_last_usec = now
	advance_follow(real_delta)

## 同一正式步进入口供确定性测试；限制恢复首帧的时间跨度，避免长停顿后突然追赶。
func advance_follow(real_delta: float) -> void:
	if not is_instance_valid(_target):
		return
	if not _follow_position.is_finite() or not global_position.is_finite():
		snap_to_target()
		return
	var dt := clampf(real_delta, 0.0, MAX_REAL_STEP) if is_finite(real_delta) else 0.0
	var alpha := 1.0 - exp(-FOLLOW_RATE * dt)
	_follow_position = _bounded(_follow_position).lerp(_bounded(_target.global_position), alpha)
	global_position = _follow_position
	force_update_scroll()

## 明确传送或装配时直接落到玩家，清除旧镜头位置和真实时间基准。
func snap_to_target() -> void:
	if not is_instance_valid(_target):
		return
	_follow_position = _bounded(_target.global_position)
	global_position = _follow_position
	_last_usec = Time.get_ticks_usec()
	reset_smoothing()
	force_update_scroll()

## 缩放/窗口变化时同时约束内部状态；地图小于视口时居中，不产生反向clamp区间。
func _bounded(point: Vector2) -> Vector2:
	if not point.is_finite():
		point = _follow_position if _follow_position.is_finite() else Vector2.ZERO
	if not limit_enabled:
		return point
	var safe_zoom := zoom.abs()
	if not safe_zoom.is_finite() or safe_zoom.x < 0.0001 or safe_zoom.y < 0.0001:
		safe_zoom = Vector2.ONE
	var half := get_viewport_rect().size / safe_zoom * 0.5
	return Vector2(_axis_bound(point.x, limit_left, limit_right, half.x), _axis_bound(point.y, limit_top, limit_bottom, half.y))

## 单轴镜头中心必须让整个视口留在矩形边界；超大视口按地图中心显示。
static func _axis_bound(value: float, low: float, high: float, half: float) -> float:
	return (low + high) * 0.5 if high - low <= half * 2.0 else clampf(value, low + half, high - half)

## 正式传送/缩放与测试夹具共用的明确复位入口；普通Camera2D仍保持原语义。
static func snap(camera: Camera2D) -> void:
	if camera == null or not camera.is_inside_tree():
		return
	if camera is StableFollowCamera:
		(camera as StableFollowCamera).snap_to_target()
	else:
		camera.reset_smoothing()
