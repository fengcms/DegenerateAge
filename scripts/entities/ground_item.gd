class_name GroundItem
extends Node2D
## 地面掉落物（产品文档 9.9 拾取交互 / 3.14 自动拾取 / 工程文档 10 掉落飞行动画）。
##
## 持有物品实例（Dictionary）；渲染占位图形，颜色按品质 / 品类区分。
##
## 生命周期（方案 C：立即入包 + 追踪式抛物线）：
##   ⓪ **出场门控**（M6-0d，创意 07 §9）：`appear_delay` 之前**不可见 / 不可拾取 / 不渲染**；
##      到点做落地弧线动画（`land_time`）——让装备雨「一份一份」落下，而不是同帧糊一坨。
##   ① **生成即认领**（`auto_claim`）：第 1 帧尝试入包——金币入账 / 物品入背包（不可逆）。
##      成功 → 立即 `remove_from_group("ground_items")`（顺路拾取从此看不见它），
##      节点降级为**纯表现节点**，进入 落地 → HOLD → FLY 动画；此后玩家怎么跑都不影响收益。
##   ② **HOLD**：原地停驻 `hold_time`（+ 同批 `stagger_delay` 错峰），让「掉了什么」被看见。
##   ③ **FLY**：二次贝塞尔抛物线**追踪玩家当前位置**，缩小淡出，抵达回收。
##   ④ 「拾取」提示在**飞行结束**时弹出，使「掉落 → 飞行 → 入包」在时间上成立。
##
## 未认领（关闭自动拾取、玩家丢弃物，或认领失败＝背包满 / 金币满）：
##   关闭 G 时只接受左键点击；开启 G 后保护期结束才允许靠近自动拾取；
##   背包满则留地并节流提示（9.9 / 3.14 T10 不破）；地面存在 60s 后淡出。
##
## `G` 同时控制生成认领、靠近拾取和自动战斗顺路拾取；已认领物的飞行不受切换影响。

const MONO_FONT := preload("res://assets/themes/mono_font.tres")

const PICKUP_RANGE_PX := 1.5 * Iso.TILE_W   # 1.5 格（7.1：tileW=64，单一来源 Iso.TILE_W）
const LIFETIME := 60.0                 # 未认领物的地面存在时长（s）
const BLOCK_TOAST_CD := 1.5            # 「背包已满」提示节流（s）
const DROP_ARC_TIME := 0.32            # 出场落地弧线时长（s，默认值；实际由 `land_time` 决定）
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
## （M6-0d 后由 `LootBurst` 直接算入 `hold_time`；本字段保留给非编排来源的兜底错峰。）
const STAGGER_PER_ITEM := 0.07
const STAGGER_MAX := 0.35
## 飞行兜底余量（s）：超过 fly_time + 此值仍未回收 → 强制结束（防异常挂死）。
const FLY_TIMEOUT_EXTRA := 0.4
## 单帧目标点跳变阈值（px）：读档 / 回城卷 / 瞬移 → 不拉长弧，直接淡出回收。
const TELEPORT_BREAK := 220.0
## 工程 93（D-31）：同批件数 ≥ 此值 ⇒ 稀有以上的地面名字只悬停显示（见 `batch_size` 注释）。
const LABEL_CROWD_LIMIT := 20

## 工程 104：动画重绘半径（格）。屏幕半宽 1920 时约 15 格、2560 时约 20 格，
## 取 22 格保证「看得见的都在动」，同时把屏幕外的积压件彻底停掉重绘。
const ANIM_RANGE_TILES := 22.0
## 范围内重绘间隔（s）：浮动只有 ±2px，10 Hz 肉眼无差。
const ANIM_REDRAW_INTERVAL := 0.1
## 范围外复查间隔（s）：玩家走近后最多 0.3s 恢复动画。
const ANIM_RANGE_CHECK := 0.3

## 工程 93：某件掉落是否**常显**地面名字（与 `_draw_label` 共用，供测试直接断言）。
## 稀有以上默认常显；但同批 ≥ `LABEL_CROWD_LIMIT` 件时改为悬停才显示，避免名字糊成一团。
static func should_always_show_label(quality: String, batch_size: int) -> bool:
	if not (quality in ["rare", "epic", "legendary"]):
		return false
	return batch_size < LABEL_CROWD_LIMIT

enum Stage { GROUND, HOLD, FLY }

## 停驻 / 保护期（s）。导出以便测试注入 0 复用即时拾取语义。
@export var hold_time: float = HOLD_TIME
## 生成即认领：怪物掉落 = true；**玩家丢弃物应传 false**（留地 + 60s 消失，见工程文档 10 §5）。
@export var auto_claim: bool = false
## 工程 89（2026-10-22）：玩家主动丢弃物 = true ⇒ **只能点击拾取**。
## 不参与「靠近自动拾取」，也不进自动战斗的顺路拾取候选（`AutoBattle._can_pick`）。
## 🔴 为什么不沿用普通未认领语义：丢弃物落在玩家脚边，而拾取半径 96px、保护期仅 0.2s，
## 且 F 开自动战斗会联动打开 G —— 松手 0.2 秒后就被原样捡回，功能等于不可用。
@export var manual_only: bool = false
## 同批多件起飞错峰（s）：由掉落方按序号传入（`Monster._spawn_drop`）。
@export var stagger_delay: float = 0.0
## M6-0c（创意 07 §11）：精英 / Boss 掉落为 true ⇒ 入包失败登记为「未领取战利品」，
## **不走 60s 淡出**，跨图 / 跨档保留，直到领取或玩家主动丢弃。普通怪 / 玩家丢弃物保持 false。
@export var persistent: bool = false
## M6-0c（创意 07 §8）：所属掉落批次 ID（仅信息用途，便于批次级提示 / 排查）。
@export var batch_id: String = ""
## M6-0d（创意 07 §9）：出场延迟（s，相对批次 t=0）。在此之前不可见 / 不可拾取。
@export var appear_delay: float = 0.0
## M6-0d：出场落地动画时长（s）。精英 0.25 / Boss 0.30（§9）。
@export var land_time: float = DROP_ARC_TIME
## M6-0d：飞行时长（s）。精英 0.70 / Boss 0.90（§9）。
@export var fly_time: float = FLY_TIME
## M6-0e（创意 07 §10）：精英 / Boss 装备为 true ⇒ 入包成功**不弹**「拾取」提示
## （件数多，改由批次摘要统一说明，不逐件播报）。普通怪 / 玩家丢弃物保持 false。
@export var silent_pickup: bool = false
## 工程 93（D-31）：本批掉落总件数（由 `Monster._spawn_drop` 传入）。
## 同批 ≥ `LABEL_CROWD_LIMIT` 时，稀有以上的地面名字改为**仅悬停显示**。
## 🔴 为什么必须这样做：格铺后格距 64px，而名字绘制宽度 **240px**（跨 3.75 格），
## 一屏 100 个名字必然叠成读不出信息的糊字。品质已由光柱高度 / 颜色区分，
## 「看到有多少件」比「读到每一件的名字」重要；名字仍可悬停查看，批次摘要也会列出稀有以上。
@export var batch_size: int = 0

@export var item: Dictionary = {}

## M6-0c：登记后的未领取记录 uid（空 = 未登记）；领取成功时据此注销（§11.3）。
var claim_uid: String = ""
## 工程 63：本件装备被「拾取自动出售」换成的金币（0 = 未自动出售）。
## 只读快照，供 `Monster._settle_rewards` 统计批次摘要里的「· 自动出售 N 件 +X 金币」。
var auto_sold_gold: int = 0

## 工程 104：本节点累计请求重绘的次数（只读，供距离门控的回归断言）。
## 🔴 只统计 `_tick_redraw` 里的调度决策，**不含**出场 `_reveal()` 与悬停切换 —— 后者是一次性事件，
##    混进来会让「远处静止件不重绘」这条断言失去意义。
var redraw_count: int = 0

var _life: float = LIFETIME
var _blocked_cd: float = 0.0
var _phase: float = 0.0
var _spawn_t: float = 0.0
var _revealed: bool = false
var _hovered: bool = false

var _stage: int = Stage.GROUND
var _stage_t: float = 0.0              # 当前阶段已过时间（s）
var _hold_until: float = 0.0           # HOLD 结束时刻（相对进入 HOLD 起算）
var _fly_elapsed: float = 0.0
var _fly_from: Vector2 = Vector2.ZERO  # 抛物线起点（认领点）
var _fly_to: Vector2 = Vector2.ZERO    # 抛物线终点（每帧追踪玩家）
var _has_fly_to: bool = false
var _claimed: bool = false
var _pickup_msg: String = ""           # 待播的「拾取」提示（飞行结束时弹，Q2）
var _redraw_t: float = 0.0             # 低频重绘计时（工程 104）
var _range_t: float = 0.0              # 距玩家复查计时（工程 104）
var _near_anim: bool = false           # 玩家是否在动画半径内（工程 104）

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("ground_items")
	# M6-0d（创意 07 §9）：名称等世界文字 —— 入组供改地图倍率时重绘（_draw 按当时倍率取字号）。
	add_to_group("world_text")
	_phase = randf() * TAU
	# 出场门控：`appear_delay > 0` 时先隐藏，到点在 _physics_process 里 _reveal()
	visible = appear_delay <= 0.0
	if visible:
		_reveal()
	var area := get_node_or_null("ClickArea") as Area2D
	if area != null:
		area.mouse_entered.connect(_on_hover.bind(true))
		area.mouse_exited.connect(_on_hover.bind(false))
	queue_redraw()
	# 生成即认领（方案 C 核心）：不再依赖玩家走近。工程 101 起面板打开也照捡。
	if auto_claim and GameState.auto_pickup_on:
		_try_claim()
	elif persistent:
		_register_unclaimed.call_deferred()

## 出场（可见 + 缩放回弹）。M6-0d：出场时刻由 `appear_delay` 决定。
func _reveal() -> void:
	if _revealed:
		return
	_revealed = true
	visible = true
	scale = Vector2(0.55, 0.55)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()

## 出场后经过时间（≤0 视为未出场）。
func _appear_t() -> float:
	return maxf(0.0, _spawn_t - appear_delay)

func _physics_process(delta: float) -> void:
	_spawn_t += delta
	_blocked_cd = maxf(0.0, _blocked_cd - delta)
	# M6-0d（创意 07 §9）：出场时刻前不可见 / 不拾取 / 不渲染
	if _spawn_t < appear_delay:
		return
	if not _revealed:
		_reveal()
	_phase += delta * 3.0
	_tick_redraw(delta)   # 工程 104：不再无条件重绘（积压场景下的主要开销）

	# 已认领（收益不可逆）→ 只推进表现：落地 → HOLD → FLY → 回收
	if _claimed:
		_stage_step(delta)
		return

	# ---- 未认领：地面物旧语义 ----
	# M6-0c：精英 / Boss 未领取战利品（persistent）不参与 60s 淡出，持续到领取（§11）。
	if not persistent:
		_life -= delta
		if _life <= 0.0:
			_fade_out()
			return
	# 停驻 / 保护期内不自动拾取（点击不受限，见 _on_click_area_input_event）
	if _spawn_t < appear_delay + maxf(hold_time, 0.0):
		return
	# 工程 89：玩家丢弃物只认点击 —— 否则丢在脚边会被立刻捡回去。
	if manual_only:
		return
	# G 关闭时任何地面物都必须由玩家点击拾取。工程 101 起面板打开不作限制。
	if not GameState.auto_pickup_on:
		return
	# 靠近自动拾取（9.9）
	var player := _get_player()
	if player != null and player.global_position.distance_to(global_position) <= PICKUP_RANGE_PX:
		if _try_pickup():
			_claimed = true
			queue_free()

# ---- 重绘调度（工程 104）----

## 把「每帧无条件 `queue_redraw()`」改成按需重绘。三类情况必须每帧：
##   ① 已认领（落地 / HOLD / FLY 动画中，且 1 秒内就回收）；② 鼠标悬停；③ 出场 / 停驻高亮期。
## 其余：玩家在 `ANIM_RANGE_TILES` 内 → 10 Hz 低频（浮动只有 ±2px，看不出跳帧）；
## 更远 → **完全不重绘**，每 `ANIM_RANGE_CHECK` 复查一次距离，走近自动恢复。
##
## 🔴 为什么不干脆全部停掉：浮动 / 渐隐高亮是「这是掉落物」的视觉信号，静止会像装饰物。
## 🔴 为什么不担心淡出：`_fade_out()` 用 tween 改 `modulate`，CanvasItem 属性变化不依赖 `_draw`。
func _tick_redraw(delta: float) -> void:
	# 已认领（动画中）与悬停必须每帧：这里不做任何距离判断，先短路掉。
	if _claimed or _hovered:
		redraw_count += 1
		queue_redraw()
		return
	_redraw_t -= delta
	_range_t -= delta
	if _range_t <= 0.0:
		_range_t = ANIM_RANGE_CHECK
		_near_anim = _player_within(ANIM_RANGE_TILES * Iso.TILE_W)
	# 🔴 远处 = 每帧只做两次减法与一次比较（探针实测 0.02 µs/件），
	#    连 `_guard_ratio()` 都不算 —— 这是「屏幕外零成本」的关键。
	if not _near_anim:
		return
	if _guard_ratio() > 0.0 or _redraw_t <= 0.0:
		_redraw_t = ANIM_REDRAW_INTERVAL
		redraw_count += 1
		queue_redraw()

## 玩家是否在给定像素半径内。玩家不可用（死亡 / 未生成）时保守返回 true：
## 宁可多画，也不要在地图上留一堆冻住的残影。
func _player_within(px: float) -> bool:
	var p := _get_player()
	if p == null:
		return true
	return p.global_position.distance_squared_to(global_position) <= px * px

# ---- 认领（方案 C）----

## 生成瞬间尝试入包。成功 → 脱离 `ground_items` 组并进入表现阶段；
## 失败（背包满 / 金币满）→ 保持未认领，回退旧留地语义（不静默丢失）。
func _try_claim() -> void:
	if not _try_pickup(false, persistent):        # 静默入包：拾取提示改在飞行结束时弹（Q2）
		# M6-0c：精英 / Boss 入包失败 ⇒ 登记未领取战利品（§11.1）。
		# ⚠ 延后一帧登记：掉落方在 `add_child` **之后**才设最终落点（`Monster._spawn_drop`），
		#   立即登记会记到默认位置。deferred 在当前帧末 flush，此时落点已定。
		_register_unclaimed.call_deferred()
		return
	_claimed = true
	remove_from_group("ground_items")  # 关键收敛点：AutoBattle 顺路拾取立刻看不见它
	if not _fly_enabled():
		_announce_pickup()
		queue_free()
		return
	# M6-0d：保留 GROUND 阶段 —— 出场落地动画（`land_time`）结束后再由 `_stage_step` 转入 HOLD → FLY
	queue_redraw()

## M6-0c（创意 07 §11.2）：登记为「未领取战利品」。仅 persistent（精英 / Boss）、
## 未认领、且未登记过时生效（幂等）。记录地图 ID / 批次 ID / 实例数据 / 落点。
func _register_unclaimed() -> void:
	if not persistent or _claimed or not claim_uid.is_empty():
		return
	if not EventBus.unclaimed_loot_evicted.is_connected(_on_unclaimed_evicted):
		EventBus.unclaimed_loot_evicted.connect(_on_unclaimed_evicted)
	claim_uid = GameState.add_unclaimed_loot(GameState.current_map, batch_id, item, global_position)
	SaveManager.request_autosave()

## 未领取记录被系统按上限丢弃时销毁自身地面物（记录已从 `unclaimed_loot` 移除，不再重建）。
func _on_unclaimed_evicted(uid: String) -> void:
	if claim_uid.is_empty() or uid != claim_uid:
		return
	claim_uid = ""
	queue_free()

## M6-0c（创意 07 §11.3）：领取成功 → 注销未领取记录并请求保存（幂等；未登记时为 no-op）。
func _clear_unclaimed_record() -> void:
	if claim_uid.is_empty():
		return
	GameState.remove_unclaimed_loot(claim_uid)
	claim_uid = ""
	SaveManager.request_autosave()

## 是否播放飞行动画（设置项 10.3，默认开；关闭 = 认领后立即入包并消失）。
func _fly_enabled() -> bool:
	return bool(GameState.settings.get("dropFlyAnim", true))

func _stage_step(delta: float) -> void:
	if _stage == Stage.GROUND:
		# M6-0d：出场落地动画（`land_time`）结束 → 进入停驻
		if _appear_t() >= land_time:
			_stage = Stage.HOLD
			_stage_t = 0.0
			_hold_until = maxf(hold_time, 0.0) + maxf(stagger_delay, 0.0)
			_fly_from = global_position
		return
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
	var t := clampf(_fly_elapsed / maxf(0.05, fly_time), 0.0, 1.0)
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
	if t >= 1.0 or _fly_elapsed >= fly_time + FLY_TIMEOUT_EXTRA:
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
	if _stage == Stage.FLY or _appear_t() >= land_time:
		return 0.0
	var t := _appear_t() / maxf(0.001, land_time)
	return -DROP_ARC_HEIGHT * pow(1.0 - t, 2.0)

## 距落地剩余时间比例（1 = 刚生成，0 = 已落地）；用于阴影与高亮圈。
func _air_ratio() -> float:
	if _appear_t() >= land_time:
		return 0.0
	return 1.0 - _appear_t() / maxf(0.001, land_time)

## 高亮圈强度（1 → 0）：地面阶段按保护期渐隐，停驻阶段按停驻期渐隐。
## 工程 104：`_draw` 与 `_tick_redraw` 共用同一口径（后者要知道「是否还在高亮期」）。
func _guard_ratio() -> float:
	if _stage == Stage.GROUND:
		return 1.0 - clampf(_appear_t() / maxf(0.001, land_time + hold_time), 0.0, 1.0)
	if _stage == Stage.HOLD:
		return 1.0 - clampf(_stage_t / maxf(0.001, _hold_until), 0.0, 1.0)
	return 0.0

# ---- 入包 ----

## 拾取一次。金币 → 入金币（受上限约束，不占背包）；其余 → 入背包。
## `announce` 控制「拾取」提示是否立即广播（认领时静默，改在飞行结束时弹）。
## `quiet_block`（M6-0e）＝入包失败不播「背包已满」逐件提示（精英 / Boss 生成帧，
##   由批次摘要统一说明，§11.1）；之后靠近 / 点击拾取传 false，仍给节流反馈。
## 背包满 / 金币满 → 留地并节流提示（不静默丢失）。
func _try_pickup(announce: bool = true, quiet_block: bool = false) -> bool:
	if item.is_empty():
		_clear_unclaimed_record()
		queue_free()
		return true

	# 金币：直接入账（6.2，达上限后不再拾取并提示）
	if String(item.get("kind", "")) == "coin":
		if GameState.gold_is_capped():
			if _blocked_cd <= 0.0:
				_blocked_cd = BLOCK_TOAST_CD
				EventBus.toast_requested.emit(Localization.tr_key("msg.ground_item.p001"), "danger")
			return false
		var got := GameState.add_gold(int(item.get("gold", 0)))
		EventBus.item_picked.emit("coin")
		_pickup_msg = Localization.tr_key("msg.ground_item.p002") % got
		if announce:
			_announce_pickup()
		_clear_unclaimed_record()
		return true
	if String(item.get("kind", "")) == "mount":
		var mount_id := String(item.get("itemId", ""))
		if not DataLoader.get_entry("mounts", mount_id) is Dictionary:
			return false
		var fresh := GameState.collect_mount(mount_id)
		_pickup_msg = Localization.tr_key("msg.ground_item.p003") % ItemUtil.display_name(item) if fresh else Localization.tr_key("msg.ground_item.p004")
		if announce:
			_announce_pickup()
		_clear_unclaimed_record()
		return true

	# 工程 63：装备可能被「拾取自动出售」当场变现 —— 判定在 `GameState.pickup_loot()` 里，
	# 本节点只负责时机与文案。`auto_sold_gold` 会被掉落方读走做批次摘要。
	var res := GameState.pickup_loot(item)
	if bool(res.get("ok", false)):
		if bool(res.get("auto_sold", false)):
			auto_sold_gold = int(res.get("gold", 0))
			if not silent_pickup:
				_pickup_msg = Localization.tr_key("msg.game_state.p055") % [
					ItemUtil.display_name(item), auto_sold_gold]
		elif String(res.get("reason", "")) == "gold_capped":
			# 金币满 ⇒ 按设计不卖（装备留在背包）。必须说一句，否则玩家会以为功能坏了。
			# 与「背包已满」共用 `_blocked_cd` 节流：同一时刻只提示一条。
			if _blocked_cd <= 0.0:
				_blocked_cd = BLOCK_TOAST_CD
				EventBus.toast_requested.emit(
					Localization.tr_key("msg.game_state.p056") % ItemUtil.display_name(item), "danger")
		elif not silent_pickup:
			_pickup_msg = Localization.tr_key("msg.ground_item.p005") + ItemUtil.display_name(item)
		if announce:
			_announce_pickup()
		_clear_unclaimed_record()
		return true
	# M6-0e（创意 07 §11.1）：精英 / Boss 未领取战利品**只发一条批次级提示**（批次摘要统一追加），
	# 生成帧的失败不逐件播报（`quiet_block`）；之后靠近 / 点击仍给节流提示，避免玩家手动拾取无反馈。
	if _blocked_cd <= 0.0 and not quiet_block:
		_blocked_cd = BLOCK_TOAST_CD
		EventBus.toast_requested.emit(Localization.tr_key("msg.ground_item.p006") + ItemUtil.display_name(item), "danger")
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

func _on_hover(state: bool) -> void:
	if _hovered == state:
		return
	_hovered = state
	queue_redraw()

## 左键点击拾取（9.9）。已认领（飞行中）的物品不再响应点击。
func _on_click_area_input_event(viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _claimed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if viewport is Viewport:
			(viewport as Viewport).set_input_as_handled()
		if _try_pickup():
			_claimed = true
			queue_free()

# ---- 表现 ----

## 认领物是否已完成入包（供回归断言）。
func is_claimed() -> bool:
	return _claimed

func _draw() -> void:
	var kind := String(item.get("kind", "misc"))
	var quality := String(item.get("quality", "common"))
	var col := ItemUtil.kind_color(kind)
	if kind == "equip":
		col = ItemUtil.quality_color(quality)
	# 地面阴影：空中时更小更淡，落地后还原（纵向比走 Iso.GROUND_SQUASH 唯一来源）
	var air := _air_ratio()
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, Iso.GROUND_SQUASH))
	draw_circle(Vector2.ZERO, 11.0 * (1.0 - 0.45 * air), Color(0, 0, 0, 0.28 * (1.0 - 0.5 * air)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# M6-0d（创意 07 §9）：稀有以上光柱 + 底座（在物品之下绘制）
	_draw_quality_augment(kind, quality, col)
	# M6-0d（§10 / §11）：未领取战利品仍须有可见地面标记（与动画开关无关）
	# 工程 104：装饰环一律走 `GroundFx.ring()`（预渲染纹理）；折线描边在积压场景是主要瓶颈。
	if persistent and not _claimed:
		GroundFx.ring(self, Vector2(0, 8), 26.0, Color(1.0, 0.62, 0.30), 0.85)
		GroundFx.ring(self, Vector2(0, 8), 30.0, Color(1.0, 0.62, 0.30), 0.45)
	# 高亮圈：地面阶段＝保护期渐隐；停驻阶段＝停驻期渐隐（帮助玩家第一时间注意到掉落）
	var guard := _guard_ratio()
	if guard > 0.0:
		var rr := 20.0 + 18.0 * (1.0 - guard)
		# 圆心与阴影圆心（y=8）对齐，压扁后才不会错位（工程 53 D-3）
		GroundFx.ring(self, Vector2(0, 8), rr, Color(1.0, 0.94, 0.70), 0.6 * guard * guard)
	# 物品图形（上下浮动 + 出场弧线）：已接入图标等比显示为 32 像素，缺图继续回退图形。
	var lift := sin(_phase) * 2.0 + _drop_offset()
	var c := Vector2(0, -16 + lift)
	var sample_texture := SampleArt.ground_for(item)
	if sample_texture != null:
		draw_texture_rect(sample_texture, Rect2(c + Vector2(-16, -24), Vector2(32, 32)), false)
		_draw_label(kind, quality, col, c)
		return
	if kind == "coin":
		draw_circle(c, 8.0, col)
		draw_arc(c, 8.0, 0.0, TAU, 18, Color(0, 0, 0, 0.55), 1.5, true)
		draw_circle(c + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.7))
		_draw_label(kind, quality, col, c)
		return
	var pts := PackedVector2Array([
		c + Vector2(0, -11), c + Vector2(9, 0), c + Vector2(0, 11), c + Vector2(-9, 0),
	])
	draw_colored_polygon(pts, col)
	var outline := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
	draw_polyline(outline, Color(0, 0, 0, 0.55), 1.5)
	# 品质 / 品类高光点
	draw_circle(c + Vector2(0, -2), 2.5, Color(1, 1, 1, 0.75))
	_draw_label(kind, quality, col, c)

## M6-0d（创意 07 §9「颜色、光柱和名称」）：稀有细短光柱 / 史诗宽光柱 + 双圈底座 /
## 传说最高光柱 + 星形底座。高度按稀有 36 / 史诗 60 / 传说 90 世界像素起步。
func _draw_quality_augment(kind: String, quality: String, col: Color) -> void:
	if kind != "equip":
		return
	var h := 0.0
	var w := 0.0
	match quality:
		"rare":
			h = 36.0
			w = 3.0
		"epic":
			h = 60.0
			w = 7.0
		"legendary":
			h = 90.0
			w = 10.0
		_:
			return
	var foot := Vector2(0, 6)
	var tint := Color(col.r, col.g, col.b)
	var beam := Color(tint.r, tint.g, tint.b, 0.30)
	draw_rect(Rect2(foot.x - w * 0.5, foot.y - h, w, h), beam)
	draw_line(foot, foot + Vector2(0.0, -h), Color(tint.r, tint.g, tint.b, 0.85), 1.5, true)
	if quality == "epic":
		# 双圈底座（工程 104：装饰环走预渲染纹理）
		GroundFx.ring(self, Vector2(0, 8), 16.0, Color(tint.r, tint.g, tint.b), 0.60)
		GroundFx.ring(self, Vector2(0, 8), 23.0, Color(tint.r, tint.g, tint.b), 0.35)
	elif quality == "legendary":
		# 星形底座
		var star := PackedVector2Array()
		for i in range(10):
			var ang := -PI * 0.5 + PI * float(i) / 5.0
			var rr := 20.0 if i % 2 == 0 else 9.0
			star.append(Vector2(0, 8) + Vector2(cos(ang), sin(ang) * Iso.GROUND_SQUASH) * rr)
		draw_colored_polygon(star, Color(tint.r, tint.g, tint.b, 0.38))
		var loop := PackedVector2Array(star)
		loop.append(star[0])
		draw_polyline(loop, Color(tint.r, tint.g, tint.b, 0.8), 1.4)

## M6-0d（§9）：装备名称与品质 —— 稀有以上常显，普通 / 优秀悬停显示。
## 工程 93：同批件数过多时稀有以上也改为悬停显示（名字宽 240px ≫ 一格 64px，会糊成一团）。
## 世界文字：抵消地图倍率，并按最终文字倍率显示。
func _draw_label(kind: String, quality: String, col: Color, center: Vector2) -> void:
	if kind != "equip":
		return
	if not (should_always_show_label(quality, batch_size) or _hovered):
		return
	var font_size := 13.0 * SettingsRuntime.world_text_scale_value()
	draw_string(MONO_FONT, Vector2(center.x - 120.0, center.y - 20.0), ItemUtil.display_name(item),
		HORIZONTAL_ALIGNMENT_CENTER, 240.0, font_size, col)
