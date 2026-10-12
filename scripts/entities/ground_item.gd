class_name GroundItem
extends Node2D
## 地面掉落物（产品文档 9.9 拾取交互 / 3.14 自动拾取 / 工程文档 10 掉落飞行动画）。
##
## 持有物品实例（Dictionary）；渲染占位图形，颜色按品质 / 品类区分。
##
## 生命周期（方案 C：立即入包 + 追踪式抛物线）：
##   ① **生成即认领**（`auto_claim`）：第 1 帧尝试入包——金币入账 / 物品入背包（不可逆）。
##      成功 → 立即 `remove_from_group("ground_items")`（顺路拾取从此看不见它），
##      节点降级为**纯表现节点**，进入 HOLD / FLY 动画；此后玩家怎么跑都不影响收益。
##   ② **HOLD**：原地停驻 `hold_time`（+ 同批 `stagger_delay` 错峰），让「掉了什么」被看见。
##   ③ **FLY**：二次贝塞尔抛物线**追踪玩家当前位置**，缩小淡出，抵达回收。
##   ④ 「拾取」提示在**飞行结束**时弹出，使「掉落 → 飞行 → 入包」在时间上成立。
##
## 未认领（`auto_claim=false` 的玩家丢弃物，或认领失败＝背包满 / 金币满）：
##   保持**地面物旧语义**——`hold_time` 内不自动拾取（左键点击不受限），之后靠近 / 点击入包；
##   背包满则留地并节流提示（9.9 / 3.14 T10 不破）；地面存在 60s 后淡出。
##
## 说明：`G`（自动拾取开关）只控制 AutoBattle 是否**顺路拾取未认领物**；
## 已认领物的飞行只是表现，与 G 无关，照飞（工程文档 10 Q4）。

const PICKUP_RANGE_PX := 1.5 * 64.0   # 1.5 格（7.1：tileW=64）
const LIFETIME := 60.0                 # 未认领物的地面存在时长（s）
const BLOCK_TOAST_CD := 1.5            # 「背包已满」提示节流（s）
const DROP_ARC_TIME := 0.32            # 出场落地弧线时长（s）
const DROP_ARC_HEIGHT := 46.0          # 出场起点离地高度（px）

## 停驻时长（s）：认领后的「看得见」窗口；未认领时即落地保护期。
const HOLD_TIME := 0.2
## 飞行时长（s）。HOLD + FLY ≈ 1.2s，对齐设计原案。
const FLY_TIME := 1.0
## 抛物线控制点抬升高度（px）：∝ 距离，夹在上下限之间（距离越远拱得越高）。
const ARC_MIN := 34.0
const ARC_MAX := 76.0
const ARC_RATIO := 0.35
## 同批多件起飞错峰（s）：第 i 件延后 i×PER，封顶 MAX，避免叠成一坨看不出件数。
const STAGGER_PER_ITEM := 0.07
const STAGGER_MAX := 0.35
## 飞行兜底余量（s）：超过 FLY_TIME + 此值仍未回收 → 强制结束（防异常挂死）。
const FLY_TIMEOUT_EXTRA := 0.4
## 单帧目标点跳变阈值（px）：读档 / 回城卷 / 瞬移 → 不拉长弧，直接淡出回收。
const TELEPORT_BREAK := 220.0

enum Stage { GROUND, HOLD, FLY }

## 停驻 / 保护期（s）。导出以便测试注入 0 复用即时拾取语义。
@export var hold_time: float = HOLD_TIME
## 生成即认领：怪物掉落 = true；**玩家丢弃物应传 false**（留地 + 60s 消失，见工程文档 10 §5）。
@export var auto_claim: bool = true
## 同批多件起飞错峰（s）：由掉落方按序号传入（`Monster._spawn_drop`）。
@export var stagger_delay: float = 0.0

@export var item: Dictionary = {}

var _life: float = LIFETIME
var _blocked_cd: float = 0.0
var _phase: float = 0.0
var _spawn_t: float = 0.0

var _stage: int = Stage.GROUND
var _stage_t: float = 0.0              # 当前阶段已过时间（s）
var _hold_until: float = 0.0           # HOLD 结束时刻（相对进入 HOLD 起算）
var _fly_elapsed: float = 0.0
var _fly_from: Vector2 = Vector2.ZERO  # 抛物线起点（认领点）
var _fly_to: Vector2 = Vector2.ZERO    # 抛物线终点（每帧追踪玩家）
var _has_fly_to: bool = false
var _claimed: bool = false
var _pickup_msg: String = ""           # 待播的「拾取」提示（飞行结束时弹，Q2）

func _ready() -> void:
	add_to_group("ground_items")
	_phase = randf() * TAU
	# 出场落地（视觉反馈）：落点缩放回弹 + 弧线下落（见 _drop_offset）
	scale = Vector2(0.55, 0.55)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()
	# 生成即认领（方案 C 核心）：不再依赖玩家走近
	if auto_claim:
		_try_claim()

func _physics_process(delta: float) -> void:
	_spawn_t += delta
	_phase += delta * 3.0
	_blocked_cd = maxf(0.0, _blocked_cd - delta)
	queue_redraw()   # 浮动 / 落地 / 高亮 / 飞行需持续重绘

	# 已认领（收益不可逆）→ 只推进表现：HOLD → FLY → 回收
	if _claimed:
		_stage_step(delta)
		return

	# ---- 未认领：地面物旧语义 ----
	_life -= delta
	if _life <= 0.0:
		_fade_out()
		return
	# 停驻 / 保护期内不自动拾取（点击不受限，见 _on_click_area_input_event）
	if _spawn_t < hold_time:
		return
	# 靠近自动拾取（9.9）
	var player := _get_player()
	if player != null and player.global_position.distance_to(global_position) <= PICKUP_RANGE_PX:
		if _try_pickup():
			queue_free()

# ---- 认领（方案 C）----

## 生成瞬间尝试入包。成功 → 脱离 `ground_items` 组并进入表现阶段；
## 失败（背包满 / 金币满）→ 保持未认领，回退旧留地语义（不静默丢失）。
func _try_claim() -> void:
	if not _try_pickup(false):        # 静默入包：拾取提示改在飞行结束时弹（Q2）
		return
	_claimed = true
	remove_from_group("ground_items")  # 关键收敛点：AutoBattle 顺路拾取立刻看不见它
	if not _fly_enabled():
		_announce_pickup()
		queue_free()
		return
	_stage = Stage.HOLD
	_stage_t = 0.0
	_hold_until = maxf(hold_time, 0.0) + maxf(stagger_delay, 0.0)
	_fly_from = global_position
	queue_redraw()

## 是否播放飞行动画（设置项 10.3，默认开；关闭 = 认领后立即入包并消失）。
func _fly_enabled() -> bool:
	return bool(GameState.settings.get("dropFlyAnim", true))

func _stage_step(delta: float) -> void:
	if _stage == Stage.GROUND:
		return   # 认领后未进入动画（如已关闭飞行）→ 不做表现推进
	_stage_t += delta
	if _stage == Stage.HOLD:
		if _stage_t >= _hold_until:
			_stage = Stage.FLY
			_stage_t = 0.0
			_fly_elapsed = 0.0
			_fly_from = global_position
			_fly_to = _player_pos()
			_has_fly_to = true
		return
	_fly_step(delta)

## 抛物线追踪：P0=认领点（固定）、P2=玩家当前位置（每帧更新）、P1=中点抬升 h。
## 位置 = 二次贝塞尔(P0, P1, P2, ease_out(t))；抵达 → 回收。
func _fly_step(delta: float) -> void:
	_fly_elapsed += delta
	var t := clampf(_fly_elapsed / FLY_TIME, 0.0, 1.0)
	# 追踪玩家当前位置（Q3）；玩家不可用时沿用上一次目标
	var target := _player_pos()
	if _has_fly_to and target.distance_to(_fly_to) > TELEPORT_BREAK:
		# 单帧目标跳变（读档 / 回城卷 / 瞬移）→ 不拉长弧，直接结束
		_finish_fly()
		return
	_fly_to = target
	_has_fly_to = true

	var te := 1.0 - pow(1.0 - t, 2.0)          # ease-out：先快后慢，“被吸住”的手感
	var mid := (_fly_from + _fly_to) * 0.5
	var h := clampf(_fly_from.distance_to(_fly_to) * ARC_RATIO, ARC_MIN, ARC_MAX)
	var ctrl := mid + Vector2(0.0, -h)
	global_position = (1.0 - te) * (1.0 - te) * _fly_from \
		+ 2.0 * (1.0 - te) * te * ctrl + te * te * _fly_to
	# 缩小 + 淡出
	scale = Vector2.ONE.lerp(Vector2(0.45, 0.45), te)
	modulate.a = 1.0 - te * te
	# 正常抵达 或 超时兜底 → 回收
	if t >= 1.0 or _fly_elapsed >= FLY_TIME + FLY_TIMEOUT_EXTRA:
		_finish_fly()

## 飞行结束：弹「拾取」提示（Q2）+ 回收节点。
func _finish_fly() -> void:
	set_physics_process(false)
	_announce_pickup()
	queue_free()

func _announce_pickup() -> void:
	if _pickup_msg.is_empty():
		return
	EventBus.toast_requested.emit(_pickup_msg, "pickup")
	_pickup_msg = ""   # 防重复播报

func _player_pos() -> Vector2:
	var p := _get_player()
	return p.global_position if p != null else global_position

# ---- 入场落地表现 ----

## 出场弧线偏移：从上方 DROP_ARC_HEIGHT 处加速落至地面，落地后归零。
## 飞行动画自成一体的位置控制，故此阶段强制归零（避免与贝塞尔轨迹叠加抖动）。
func _drop_offset() -> float:
	if _stage == Stage.FLY or _spawn_t >= DROP_ARC_TIME:
		return 0.0
	var t := _spawn_t / DROP_ARC_TIME
	return -DROP_ARC_HEIGHT * pow(1.0 - t, 2.0)

## 距落地剩余时间比例（1 = 刚生成，0 = 已落地）；用于阴影与高亮圈。
func _air_ratio() -> float:
	if _spawn_t >= DROP_ARC_TIME:
		return 0.0
	return 1.0 - _spawn_t / DROP_ARC_TIME

# ---- 入包 ----

## 拾取一次。金币 → 入金币（受上限约束，不占背包）；其余 → 入背包。
## `announce` 控制「拾取」提示是否立即广播（认领时静默，改在飞行结束时弹）。
## 背包满 / 金币满 → 留地并节流提示（不静默丢失）。
func _try_pickup(announce: bool = true) -> bool:
	if item.is_empty():
		queue_free()
		return true

	# 金币：直接入账（6.2，达上限后不再拾取并提示）
	if String(item.get("kind", "")) == "coin":
		if GameState.gold_is_capped():
			if _blocked_cd <= 0.0:
				_blocked_cd = BLOCK_TOAST_CD
				EventBus.toast_requested.emit("金币已达上限", "danger")
			return false
		var got := GameState.add_gold(int(item.get("gold", 0)))
		EventBus.item_picked.emit("coin")
		_pickup_msg = "拾取：金币 +%d" % got
		if announce:
			_announce_pickup()
		return true
	if String(item.get("kind", "")) == "mount":
		var mount_id := String(item.get("itemId", ""))
		if not DataLoader.get_entry("mounts", mount_id) is Dictionary:
			return false
		var fresh := GameState.collect_mount(mount_id)
		_pickup_msg = "获得坐骑：%s" % ItemUtil.display_name(item) if fresh else "该坐骑已收藏"
		if announce:
			_announce_pickup()
		return true

	if Inventory.add(GameState.inventory, item):
		EventBus.item_picked.emit(String(item.get("itemId", "")))
		EventBus.inventory_changed.emit()
		_pickup_msg = "拾取：" + ItemUtil.display_name(item)
		if announce:
			_announce_pickup()
		return true
	if _blocked_cd <= 0.0:
		_blocked_cd = BLOCK_TOAST_CD
		EventBus.toast_requested.emit("背包已满，无法拾取：" + ItemUtil.display_name(item), "danger")
	return false

func _fade_out() -> void:
	set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)

func _get_player() -> Node2D:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or p.get("is_dead") == true:
		return null
	return p as Node2D

## 左键点击拾取（9.9）。已认领（飞行中）的物品不再响应点击。
func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _claimed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _try_pickup():
			queue_free()

# ---- 表现 ----

## 认领物是否已完成入包（供回归断言）。
func is_claimed() -> bool:
	return _claimed

func _draw() -> void:
	var kind := String(item.get("kind", "misc"))
	var col := ItemUtil.kind_color(kind)
	if kind == "equip":
		col = ItemUtil.quality_color(String(item.get("quality", "common")))
	# 地面阴影：空中时更小更淡，落地后还原
	var air := _air_ratio()
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 11.0 * (1.0 - 0.45 * air), Color(0, 0, 0, 0.28 * (1.0 - 0.5 * air)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 高亮圈：地面阶段＝保护期渐隐；停驻阶段＝停驻期渐隐（帮助玩家第一时间注意到掉落）
	var guard := 0.0
	if _stage == Stage.GROUND:
		guard = 1.0 - clampf(_spawn_t / maxf(0.001, hold_time), 0.0, 1.0)
	elif _stage == Stage.HOLD:
		guard = 1.0 - clampf(_stage_t / maxf(0.001, _hold_until), 0.0, 1.0)
	if guard > 0.0:
		var rr := 20.0 + 18.0 * (1.0 - guard)
		draw_arc(Vector2(0, 4), rr, 0.0, TAU, 30, Color(1.0, 0.94, 0.70, 0.6 * guard * guard), 2.0, true)
	# 物品图形（上下浮动 + 出场弧线）：金币为圆片，其余为菱形（占位素材，R5）
	var lift := sin(_phase) * 2.0 + _drop_offset()
	var c := Vector2(0, -16 + lift)
	if kind == "coin":
		draw_circle(c, 8.0, col)
		draw_arc(c, 8.0, 0.0, TAU, 18, Color(0, 0, 0, 0.55), 1.5, true)
		draw_circle(c + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.7))
		return
	var pts := PackedVector2Array([
		c + Vector2(0, -11), c + Vector2(9, 0), c + Vector2(0, 11), c + Vector2(-9, 0),
	])
	draw_colored_polygon(pts, col)
	var outline := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
	draw_polyline(outline, Color(0, 0, 0, 0.55), 1.5)
	# 品质 / 品类高光点
	draw_circle(c + Vector2(0, -2), 2.5, Color(1, 1, 1, 0.75))
