class_name BossAction
extends RefCounted
## 共享 Boss 线 / 扇 / 圈预警动作组件（工程文档 30 §4 E1；创意 第三章/03 与 90 §47—49）。
##
## 生命周期：**锁定 → 预警 → 命中 → 后摇 → 结束**。两套招式：
##   - A 招（`shape` + `segments`）：多段形态，每段独立预警；**前一段伤害结算完成、
##     再间隔 `delay` 秒**，下一段才开始（"前一段伤害结束后下一段才可开始"）；
##     **同段只命中一次**，不靠多碰撞格重复计伤。
##   - B 招（`phaseB`）：生命降到 `triggerHp` 后进入二阶段，先 `warn` 抬臂预警，
##     再打「内圈 `inner` 格以外、半径 `radius` 格以内」的局部环击（中心 / 圈外可避），
##     随后 `window` 秒输出窗；每 `interval` 秒重复。
## A / B **互斥**，任一次动作结束后保留 `MIN_LOCK` 秒公共动作锁，避免预警占满全场。
##
## 单位：长度 / 宽度 / 半径 / 角度一律按**逻辑格**配置，判定与绘制乘 `Iso.TILE_W`
## 换算为像素。形态语义（与 monsters.json 的 `bossSkill` 一致）：
##   - `line`：`offset = [垂直偏移, 沿朝向偏移]` 格，线自首领位置沿朝向延伸 `length` 格，宽 `width` 格。
##   - `circle`：`offset = [x, y]` 为**世界轴**格偏移（相对首领位置），半径 `radius` 格。
##   - `fan`：`angle` 为相对朝向的度数，扇区以首领为心，半径 `radius` 格、张角 `arcDeg` 度。
##
## 状态全部自持（含首放 / 复刷倒计时），宿主只需每帧调用 [method update] 并转交伤害。

const MIN_LOCK := 1.0   # 公共动作锁（创意：≥1 秒）

enum Stage { IDLE, TELEGRAPH, GAP, RECOVERY }
enum Move { NONE, A, B }

## 形态类别（`shape` 字段）。
var shape := ""
## A 招分段：`offset`（line / circle）或 `angle`（fan）+ `delay`（相对上一段伤害的前置间隔）。
var segments: Array = []
var length_t := 10.0     # line 长度（格）
var width_t := 2.0       # line 宽度（格）
var radius_t := 2.5      # circle / fan 半径（格）
var arc_deg := 70.0      # fan 张角（度）
var warn_t := 1.0        # 每段独立预警时长（秒）
var interval := 8.0      # A 招重复间隔（秒）
var first_delay := 4.0   # 进战后首次 A 招延迟（秒）
var coeff := 1.15        # A 招每段伤害系数
var recovery := 0.8      # A 招结束硬直（秒）
## B 招（phaseB）；无配置时 `has_b == false`，组件退化为纯 A 招。
var phase_b: Dictionary = {}
var has_b := false

var stage: int = Stage.IDLE
var move: int = Move.NONE
## 锁定瞬间首领位置与朝向（预警与命中共用，**命中前不追踪玩家**）。
var _origin := Vector2.ZERO
var _facing := Vector2.RIGHT
var _seg := 0
var _t := 0.0            # 当前阶段剩余时间
var _lock := 0.0         # 公共动作锁剩余
var _a_countdown := 0.0  # 距下次 A 招
var _b_countdown := 0.0  # 距下次 B 招
var _b_fired := false    # 本场战斗是否已首次触发 B

func _init(skill: Dictionary) -> void:
	shape = String(skill.get("shape", ""))
	segments = skill.get("segments", [])
	if not segments is Array:
		segments = []
	length_t = float(skill.get("length", length_t))
	width_t = float(skill.get("width", width_t))
	radius_t = float(skill.get("radius", radius_t))
	arc_deg = float(skill.get("arcDeg", arc_deg))
	warn_t = float(skill.get("warn", warn_t))
	interval = float(skill.get("interval", interval))
	first_delay = float(skill.get("firstDelay", first_delay))
	coeff = float(skill.get("coeff", coeff))
	recovery = float(skill.get("recovery", recovery))
	var b: Variant = skill.get("phaseB", {})
	if b is Dictionary and not (b as Dictionary).is_empty():
		phase_b = b
		has_b = true
	_a_countdown = first_delay

## 是否存在可执行的 A 招（形态与分段齐备）。
func has_a() -> bool:
	return not shape.is_empty() and not segments.is_empty()

## 进战（首次仇恨）时重置 A / B 计时：首放延迟 4 秒。
func reset_for_engage() -> void:
	stage = Stage.IDLE
	move = Move.NONE
	_seg = 0
	_t = 0.0
	_lock = 0.0
	_a_countdown = first_delay
	_b_countdown = 0.0
	_b_fired = false

## 脱战 / 复位 / 死亡：清空阶段与动作锁，不改变"是否已进战"。
func cancel() -> void:
	stage = Stage.IDLE
	move = Move.NONE
	_seg = 0
	_t = 0.0
	_lock = 0.0

## 本帧是否由动作组件接管（禁止移动 / 普通攻击）。
func is_busy() -> bool:
	return stage != Stage.IDLE

## 是否处于预警阶段（需要绘制警示形状）。
func is_warning() -> bool:
	return stage == Stage.TELEGRAPH

## 每帧驱动。返回 true 表示本帧动作组件接管。
## `origin` / `facing` 为锁定参考；`target_valid` 表示可正常索敌；`hp_ratio` 供 B 招阈值；
## `on_hit` 为伤害回调 `func(coeff: float) -> void`（每段 / 环击各调用一次）。
func update(delta: float, origin: Vector2, facing: Vector2, target_valid: bool,
		hp_ratio: float, on_hit: Callable) -> bool:
	_lock = maxf(0.0, _lock - delta)
	_a_countdown -= delta
	_b_countdown -= delta
	if stage == Stage.IDLE:
		if _lock > 0.0 or not target_valid:
			return false
		if has_b and hp_ratio <= float(phase_b.get("triggerHp", 0.5)) and _b_countdown <= 0.0:
			_start(origin, facing, Move.B)
		elif has_a() and _a_countdown <= 0.0:
			_start(origin, facing, Move.A)
		else:
			return false
		return true
	_t -= delta
	match stage:
		Stage.TELEGRAPH:
			if _t <= 0.0:
				_resolve_hit(on_hit)
		Stage.GAP:
			if _t <= 0.0:
				_seg += 1
				_begin_telegraph()
		Stage.RECOVERY:
			if _t <= 0.0:
				_finish()
	return true

## 开始一次动作：锁定朝向，进入首段预警。
func _start(origin: Vector2, facing: Vector2, kind: int) -> void:
	_origin = origin
	_facing = facing.normalized() if facing.length() > 0.001 else Vector2.RIGHT
	move = kind
	_seg = 0
	_lock = 0.0
	if kind == Move.B:
		_b_fired = true
		_b_countdown = float(phase_b.get("interval", 12.0))
		_t = float(phase_b.get("warn", 1.3))
	else:
		_a_countdown = interval
		_t = warn_t
	stage = Stage.TELEGRAPH

## 段间推进：进入当前 `_seg` 段的预警。
func _begin_telegraph() -> void:
	_t = warn_t
	stage = Stage.TELEGRAPH

## 一次命中结算（每段 / 环击各一次）。随后按是否有后续段决定进入段间间隔或后摇。
func _resolve_hit(on_hit: Callable) -> void:
	if move == Move.B:
		on_hit.call(float(phase_b.get("coeff", 1.3)))
		_t = float(phase_b.get("window", 2.0))
		stage = Stage.RECOVERY
		return
	on_hit.call(coeff)
	if _seg + 1 < segments.size():
		_t = _segment_delay(_seg + 1)
		stage = Stage.GAP
		return
	_t = recovery
	stage = Stage.RECOVERY

## 结束动作：置空闲并压上公共动作锁。
func _finish() -> void:
	stage = Stage.IDLE
	move = Move.NONE
	_seg = 0
	_t = 0.0
	_lock = MIN_LOCK

func _segment_delay(idx: int) -> float:
	var seg: Variant = segments[idx]
	if seg is Dictionary:
		return maxf(0.0, float((seg as Dictionary).get("delay", 0.0)))
	return 0.0

## 当前预警段的判定几何（世界坐标）。非预警阶段返回空字典。
func geometry() -> Dictionary:
	if stage != Stage.TELEGRAPH:
		return {}
	var tc := float(Iso.TILE_W)
	if move == Move.B:
		return {
			"kind": "ring",
			"center": _origin,
			"inner": float(phase_b.get("inner", 2.0)) * tc,
			"radius": float(phase_b.get("radius", 5.0)) * tc,
		}
	var seg: Variant = segments[_seg] if _seg < segments.size() else {}
	var item: Dictionary = seg if seg is Dictionary else {}
	match shape:
		"line":
			var off := _offset(item)
			var perp := Vector2(-_facing.y, _facing.x)
			var start := _origin + (perp * off.x + _facing * off.y) * tc
			return {"kind": "line", "from": start, "to": start + _facing * length_t * tc,
				"half": maxf(1.0, width_t * tc * 0.5)}
		"circle":
			var off := _offset(item)
			return {"kind": "circle", "center": _origin + off * tc, "radius": radius_t * tc}
		"fan":
			var dir := _facing.rotated(deg_to_rad(float(item.get("angle", 0.0))))
			return {"kind": "fan", "center": _origin, "dir": dir,
				"radius": radius_t * tc, "arc": deg_to_rad(arc_deg)}
	return {}

## 某点在当前预警几何内是否会被命中。
func hits(point: Vector2) -> bool:
	var geo := geometry()
	if geo.is_empty():
		return false
	match String(geo.kind):
		"line":
			var closest := Geometry2D.get_closest_point_to_segment(point, geo["from"], geo["to"])
			return closest.distance_to(point) <= float(geo.half)
		"circle":
			return point.distance_to(geo["center"]) <= float(geo.radius)
		"fan":
			var to := point - (geo["center"] as Vector2)
			if to.length() > float(geo.radius):
				return false
			return absf((geo["dir"] as Vector2).angle_to(to)) <= float(geo["arc"]) * 0.5
		"ring":
			var d := point.distance_to(geo["center"])
			return d >= float(geo.inner) and d <= float(geo.radius)
	return false

## 段偏移（格）：line 为 `[垂直, 沿朝向]`；circle 为世界轴 `[x, y]`。
func _offset(item: Dictionary) -> Vector2:
	var raw: Variant = item.get("offset", [])
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO

## 绘制当前预警（在宿主 `_draw` 内调用；坐标转宿主本地空间）。
func draw(canvas: CanvasItem) -> void:
	var geo := geometry()
	if geo.is_empty():
		return
	var fill := Color(1.0, 0.18, 0.08, 0.24)
	var edge := Color("ff7744")
	match String(geo.kind):
		"line":
			var from: Vector2 = geo["from"]
			var to: Vector2 = geo["to"]
			var side := (to - from).normalized().orthogonal() * float(geo.half)
			canvas.draw_colored_polygon(PackedVector2Array([
				canvas.to_local(from + side), canvas.to_local(to + side),
				canvas.to_local(to - side), canvas.to_local(from - side)]), fill)
			canvas.draw_line(canvas.to_local(from), canvas.to_local(to), edge, 2.0, true)
		"circle":
			var center: Vector2 = geo["center"]
			canvas.draw_circle(canvas.to_local(center), float(geo.radius), fill)
			canvas.draw_arc(canvas.to_local(center), float(geo.radius), 0.0, TAU, 48, edge, 2.0, true)
		"fan":
			var fcenter: Vector2 = geo["center"]
			var dir: Vector2 = geo["dir"]
			var half := float(geo.arc) * 0.5
			var points := PackedVector2Array([canvas.to_local(fcenter)])
			for i in range(13):
				var a := -half + float(geo.arc) * float(i) / 12.0
				points.append(canvas.to_local(fcenter + dir.rotated(a) * float(geo.radius)))
			canvas.draw_colored_polygon(points, fill)
			canvas.draw_arc(canvas.to_local(fcenter), float(geo.radius),
				dir.angle() - half, dir.angle() + half, 24, edge, 2.0, true)
		"ring":
			var rcenter: Vector2 = geo["center"]
			canvas.draw_circle(canvas.to_local(rcenter), float(geo.radius), fill)
			canvas.draw_circle(canvas.to_local(rcenter), float(geo.inner), Color(0.06, 0.04, 0.05, 0.9))
			canvas.draw_arc(canvas.to_local(rcenter), float(geo.radius), 0.0, TAU, 48, Color("ffb454"), 3.0, true)
			canvas.draw_arc(canvas.to_local(rcenter), float(geo.inner), 0.0, TAU, 32, Color("ffb454"), 2.0, true)
