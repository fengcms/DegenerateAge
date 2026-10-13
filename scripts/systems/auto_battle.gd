class_name AutoBattle
extends Node
## 自动战斗 / 自动拾取决策机（产品文档 3.14；4.6 手动接管；9.9 拾取）。
##
## 挂为 Player 的子节点（Player.tscn → AutoPilot），只做**决策**——
## 移动与攻击仍调用玩家自身接口（`set_auto_move` / `try_auto_attack`），
## 与手动操作共用同一条代码路径，不另写一套战斗逻辑（3.14 原则）。
##
## 状态机（3.14）：
##   OFF / SEARCH_TARGET / PATH_TO_TARGET / ATTACK_TARGET /
##   SEARCH_LOOT / PATH_TO_LOOT / PICK_UP / RECOVER / MANUAL_OVERRIDE / BLOCKED
##
## 硬性异常规则（3.14「必须实现」）逐条落地：
##   ① 连续 3 次不推进 → 目标短期黑名单重搜（T08 不可达改选）；
##   ② 目标消失 / 死亡 / 切图 → 停旧指令（每帧校验目标有效性）；
##   ③ 手动接管 → 立即取消、3 秒后恢复（4.6）；
##   ④ 背包满 → 不走向该掉落物、不循环重试（T10，靠节流 + 目标剔除，不做每帧重试）；
##   ⑤ MP / 冷却不足 → 不施放该技能（T11，见 choose_skill）；
##   ⑥ 死亡 → 自动转 off；暂停 / 后台 / 面板打开 → 停决策。
##
## M1 范围说明（见工程文档 02 / 产品文档 03 §3.14）：
##   · 玩家 Lv1 仅解锁普攻 basic_slash，故本阶段实际施放普攻；`choose_skill`
##     的 MP / 冷却 / 等级判据已按 3.14 完整实现并纳入回归（T11），
##     待 M3 技能系统接线后由 `WIRED_SKILLS` 放开即可直接生效；
##   · **药水已接线（M2.5）**：危险血量**自动喝药**（先红后蓝，按缺口选"够用的最小档"）；
##     **药尽仍继续战斗**（Q5 拍板，不再停战）——见工程文档 12；
##   · 地图为无障碍开阔地，接近采用「直线趋近 + 节流重算」替代 A*；
##     卡住检测与黑名单机制与地图形态无关，M3 换 TileMap 后可直接复用。
##   · **顺路拾取已降级为兜底**（工程文档 10 方案 C）：怪物掉落物**生成即认领**并
##     `remove_from_group("ground_items")`，本文件遍历的组里直接没有它，故以下
##     SEARCH_LOOT / PATH_TO_LOOT / PICK_UP 三态**零改动**，仅服务于「背包满留地」与
##     （未来的）「玩家丢弃」等**未认领**的地面物。`G` 开关语义不变。

enum State {
	OFF,
	SEARCH_TARGET,
	PATH_TO_TARGET,
	ATTACK_TARGET,
	SEARCH_LOOT,
	PATH_TO_LOOT,
	PICK_UP,
	RECOVER,
	MANUAL_OVERRIDE,
	BLOCKED,
	ROAM,
}

# ---- 节流与阈值（初始参数，试玩校准）----
const SEARCH_INTERVAL := 0.35          # 搜怪节流（s）：无目标待机时不得每帧搜索
const REPATH_INTERVAL := 0.25          # 接近方向重算节流（s）
const STUCK_INTERVAL := 0.3            # 卡住检测间隔（s）
const STUCK_PROGRESS_EPS := 6.0        # 两次检测间的最小接近量（px）
const STUCK_LIMIT := 3                 # 连续不推进次数上限 → 黑名单（3.14 ①）
const BLACKLIST_TIME := 8.0            # 目标黑名单时长（s）
const MANUAL_RESUME_DELAY := 3.0       # 手动接管后恢复延迟（s，4.6）
const BLOCKED_TIME := 1.0             # 受阻停留（s）
const LOOT_SEARCH_RADIUS := 6.0        # 顺路拾取搜索半径（格）
const LOOT_ARRIVE_EPS := 6.0           # 判定「已抵达掉落物」（px；≤1.5 格由 GroundItem 自动入包）
const STOP_GAP := 8.0                  # 攻击范围内提前停步（px，避免与目标互相顶开）
const ROAM_GRID_STEP := 7               # 巡游采样间隔（格），往返覆盖地图有效区域
const ROAM_ARRIVE_EPS := 12.0
## 喝药阈值兜底值（3.14 设置项）。正式取值一律读 `GameState.settings.potionThreshold`，
## 本常量仅在该字段缺失时生效——避免「常量 + 设置」两个事实源（M2.5 收敛，见工程文档 12 §3.4）。
const DEFAULT_POTION_THRESHOLD := 0.35
const DANGER_TOAST_CD := 4.0           # 「危险血量」提示节流（s）

## M1 已接线的自动施放技能（普攻由攻击间隔单独驱动，不进此表）。
## M3 技能系统落地后追加技能 id 即可让 choose_skill 的返回值真正生效。
const WIRED_SKILLS: Array[String] = []

var _player: PlayerCharacter = null
var _state: int = State.OFF
var _phase: String = ""

var _target: Node = null
var _loot: Node = null

var _search_t: float = 0.0
var _repath_t: float = 0.0
var _stuck_t: float = 0.0
var _last_dist: float = INF
var _stuck_count: int = 0
var _blocked_t: float = 0.0
var _manual_t: float = 0.0
var _danger_t: float = 0.0
var _background: bool = false
var _roam_points: Array[Vector2] = []
var _roam_index: int = -1
var _roam_last_dist := INF
var _roam_stuck_t := 0.0
var _roam_stuck_count := 0

## instance_id → 剩余秒数（短期黑名单，3.14 ①）
var _blacklist: Dictionary = {}

func _ready() -> void:
	_player = get_parent() as PlayerCharacter
	if _player == null:
		push_warning("[AutoBattle] 必须作为 PlayerCharacter 的子节点")
	EventBus.auto_state_changed.connect(_on_auto_state_changed)
	_on_auto_state_changed(GameState.auto_battle_on, GameState.auto_pickup_on)
	set_physics_process(true)

## 开启自动战斗时重置搜索节流。
func _on_auto_state_changed(battle: bool, _pickup: bool) -> void:
	if battle and _player != null:
		_search_t = 0.0
		_repath_t = 0.0
		_stuck_count = 0
		_last_dist = INF
		_blacklist.clear()
		_roam_index = -1
	else:
		_target = null
		_loot = null
		_roam_index = -1

## 切图/读档后丢弃旧世界的目标、走位与攻击意图；保留 F/G 开关。
func reset_after_travel() -> void:
	if _player == null:
		return
	_player.clear_travel_intent()
	_target = null
	_loot = null
	_roam_index = -1
	_manual_t = 0.0
	_blocked_t = 0.0
	_search_t = 0.0
	_repath_t = 0.0
	if GameState.auto_battle_on and MapService.is_in_rest_zone(GameState.current_map, _player.global_position):
		_set_state(State.RECOVER, "自动战斗暂停：出行休整区")
	elif not GameState.auto_battle_on:
		_set_state(State.OFF)

func _notification(what: int) -> void:
	# 应用失去焦点（切到后台）→ 停决策（3.14 ⑥）
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_background = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_background = false

func _physics_process(delta: float) -> void:
	_tick_blacklist(delta)
	if _player == null or not is_instance_valid(_player):
		return

	# 关闭：一律回到 OFF（优先于手动接管计时，保证随时关得掉）
	if not GameState.auto_battle_on:
		if _state != State.OFF:
			_player.set_auto_move(Vector2.ZERO)
			_target = null
			_loot = null
			_manual_t = 0.0
			_blocked_t = 0.0
			_set_state(State.OFF)
		return

	# ⑥ 死亡 → 自动转 off（4.7 / 3.14）。
	# 必须排在「手动接管计时」之前：否则接管期间阵亡会因 3 秒计时未走完而漏关。
	if _player.is_dead:
		_player.set_auto_move(Vector2.ZERO)
		_manual_t = 0.0
		GameState.set_auto_battle(false)
		_set_state(State.OFF)
		return
	if _player.is_sitting:
		_player.set_auto_move(Vector2.ZERO)
		_target = null
		_loot = null
		_set_state(State.RECOVER, "打坐中")
		return

	# ⑥ 面板打开 / 后台 / 暂停 → 停决策（不暂停世界模拟，仅停本机决策）
	if GameState.panel_open or _background or get_tree().paused:
		_player.set_auto_move(Vector2.ZERO)
		_set_state(State.RECOVER, "暂停中")
		return

	# 持续手动操作先刷新计时；松手后才开始倒计时，避免按住时提前恢复。
	if _player.map_move_active or _player.manual_attack_active or _has_manual_input():
		begin_manual_override()
		return
	if MapService.is_in_rest_zone(GameState.current_map, _player.global_position):
		_player.set_auto_move(Vector2.ZERO)
		_target = null
		_loot = null
		_roam_index = -1
		_set_state(State.RECOVER, "自动战斗暂停：出行休整区")
		return

	if _manual_t > 0.0:
		_manual_t = maxf(0.0, _manual_t - delta)
		if _manual_t > 0.0:
			_set_state(State.MANUAL_OVERRIDE, "手动接管 · %d 秒后恢复" % ceili(_manual_t))
			return
		_toast("自动战斗恢复", "info")
		_set_state(State.SEARCH_TARGET)

	_tick(delta)

## 输入事件到达即可取消旧决策，不依赖下一物理帧。
func begin_manual_override() -> void:
	_player.set_auto_move(Vector2.ZERO)
	_target = null
	_loot = null
	_roam_index = -1
	_manual_t = MANUAL_RESUME_DELAY if GameState.auto_battle_on else 0.0
	if GameState.auto_battle_on:
		_set_state(State.MANUAL_OVERRIDE, "手动接管 · 操作结束后恢复")

# ---- 决策主体 ----

func _tick(delta: float) -> void:
	# 受阻停留（3.14 ① 拉黑目标后的短暂停顿，避免同帧立即重选）
	if _blocked_t > 0.0:
		_blocked_t = maxf(0.0, _blocked_t - delta)
		_player.set_auto_move(Vector2.ZERO)
		_set_state(State.BLOCKED)
		return

	# 危险血量（3.14）：**先自动喝药**（与手动共用 Consumable 入口，不另写一套）。
	# Q5 拍板（2026-10-12）：**药尽仍继续战斗至死** —— 喝不到药不再停寻怪。
	var max_hp := GameState.max_hp()
	if max_hp > 0 and float(int(GameState.player.hp)) / float(max_hp) <= _potion_threshold():
		if _try_drink():
			_danger_t = 0.0
			return                                    # 已回血：本帧不再决策，下一帧按新血量行动
		_danger_t = maxf(0.0, _danger_t - delta)       # 无药 / 全在冷却 → 继续战斗（不停战）
		if _danger_t <= 0.0:
			_danger_t = DANGER_TOAST_CD
			_toast("生命过低且无药可用，继续战斗", "danger")

	# ② 每帧校验目标有效性（死亡 / 释放 / 进黑名单 → 停旧指令）
	if _target != null and (not is_instance_valid(_target)
			or _target.get("is_dead") == true or _is_blacklisted(_target)):
		_target = null
		_last_dist = INF
		_stuck_count = 0

	if _target == null:
		_search_t = maxf(0.0, _search_t - delta)
		if _search_t <= 0.0:
			_search_t = SEARCH_INTERVAL
			_target = _find_target()
			if _target != null:
				_roam_index = -1
				_player.select_target(_target as Node2D, _player.target_is_manual and _player.locked_target == _target)
				_last_dist = INF
				_stuck_count = 0
		if _target == null:
			# 无怪可打 → 自动拾取（9.9：G 仅控制自动战斗时是否顺路拾取）
			if GameState.auto_pickup_on and _tick_loot():
				return
			_tick_roam(delta)
		return

	var target2d := _target as Node2D
	var dist := _player.global_position.distance_to(target2d.global_position)
	var reach := _player.melee_range_px() - STOP_GAP

	if dist > reach:
		_set_state(State.PATH_TO_TARGET)
		_tick_stuck(delta, dist)
		if _blocked_t > 0.0:
			return
		_repath_t = maxf(0.0, _repath_t - delta)
		if _repath_t <= 0.0:
			_repath_t = REPATH_INTERVAL
			_player.set_auto_move((target2d.global_position - _player.global_position).normalized())
		return

	# 已在攻击范围内 → 停步并攻击（施放节奏由玩家自身攻击冷却控制，3.9 不绕过攻速）
	_player.set_auto_move(Vector2.ZERO)
	_set_state(State.ATTACK_TARGET)
	_stuck_count = 0
	_player.try_auto_attack(_target)

# ---- 自动喝药（M2.5；3.14「自动只调用与玩家相同的喝药接口」）----

## 喝药阈值（3.14 设置项，默认 35%）。
func _potion_threshold() -> float:
	return float(GameState.settings.get("potionThreshold", DEFAULT_POTION_THRESHOLD))

## 危险血量时尝试喝药（先红后蓝 —— Q2 拍板「自动红蓝一并开」）。返回是否成功喝到。
## 与手动喝药共用 `Consumable.use`，不另写一套实现；`silent` 抑制单次失败提示，由本层统一节流。
func _try_drink() -> bool:
	for kind in [Consumable.KIND_RED, Consumable.KIND_BLUE]:
		var idx := Consumable.pick_index(String(kind))
		if idx < 0:
			continue
		var res := Consumable.use(idx, true)
		if bool(res.get("ok", false)):
			_toast("自动喝药 · %s" % String(res.get("message", "")), "info")
			return true
	return false

# ---- 目标搜索 ----

## 当前画面可见区域内搜索敌人（3.14）。排除 Boss（除非设置允许）、黑名单目标。
## M1 目标优先级：距离最近；同距离取血量更低者（「优先低代价 / 弱目标」的最小实现）。
func _find_target() -> Node:
	# 明确选中的目标优先；黑名单仍生效，避免不可达目标循环。
	if _player.target_is_manual and _player.valid_target(_player.locked_target) and not _is_blacklisted(_player.locked_target):
		return _player.locked_target
	var allow_boss := bool(GameState.settings.get("allowBoss", false))
	var best: Node = null
	var best_dist := INF
	var best_hp := INF
	var world := get_tree().get_first_node_in_group("map_world")
	if world == null or not world.has_method("visible_enemies"):
		return null
	for e in world.visible_enemies():
		if not is_instance_valid(e) or e.get("is_dead") == true or not (e is Node2D):
			continue
		if _is_blacklisted(e):
			continue
		if not allow_boss:
			var tpl = e.get("template")
			if tpl is Dictionary and String(tpl.get("kind", "normal")) == "boss":
				continue
		var d := _player.global_position.distance_to((e as Node2D).global_position)
		var hp_v = e.get("hp")           # Node.get 只接受 1 个参数（无默认值重载）
		var hp := float(hp_v) if hp_v != null else 0.0
		if d < best_dist - 0.001 or (absf(d - best_dist) <= 0.001 and hp < best_hp):
			best_dist = d
			best_hp = hp
			best = e
	return best

## 顺路拾取目标（9.9）；T10：背包满时排除需要入包的掉落物（金币不受背包限制）。
## 注：怪物掉落物生成即认领并已离组（工程文档 10），故此路径通常只命中**未认领**的
## 留地物（背包满遗留 / 未来的玩家丢弃物）——属兜底，不影响主循环收益。
func _find_loot() -> GroundItem:
	var radius := LOOT_SEARCH_RADIUS * Iso.TILE_W
	var best: GroundItem = null
	var best_d := INF
	for g in get_tree().get_nodes_in_group("ground_items"):
		if not (g is GroundItem):
			continue
		var gi := g as GroundItem
		if gi.item.is_empty() or not _can_pick(gi):
			continue
		var d := _player.global_position.distance_to(gi.global_position)
		if d > radius:
			continue
		if d < best_d:
			best_d = d
			best = gi
	return best

func _tick_loot() -> bool:
	if _loot != null and (not is_instance_valid(_loot)
			or (_loot as GroundItem).item.is_empty() or not _can_pick(_loot as GroundItem)):
		_loot = null
	if _loot == null:
		_set_state(State.SEARCH_LOOT)
		_loot = _find_loot()
		if _loot == null:
			return false
	var d := _player.global_position.distance_to((_loot as Node2D).global_position)
	if d <= LOOT_ARRIVE_EPS:
		_player.set_auto_move(Vector2.ZERO)
		_set_state(State.PICK_UP)                 # 进入 1.5 格后由 GroundItem 自动入包（9.9）
		return true
	_set_state(State.PATH_TO_LOOT)
	_player.set_auto_move(((_loot as Node2D).global_position - _player.global_position).normalized())
	return true

## 无可见怪物时按地图有效格往返巡游；每个物理帧仍走上方的节流搜怪。
func _tick_roam(delta: float) -> void:
	if _roam_points.is_empty():
		_build_roam_points()
	if _roam_points.is_empty():
		_player.set_auto_move(Vector2.ZERO)
		_set_state(State.SEARCH_TARGET)
		return
	if _roam_index < 0:
		var nearest := INF
		for i in range(_roam_points.size()):
			var d := _player.global_position.distance_squared_to(_roam_points[i])
			if d < nearest:
				nearest = d
				_roam_index = i
		_reset_roam_progress()
	var point := _roam_points[_roam_index]
	var dist := _player.global_position.distance_to(point)
	if dist <= ROAM_ARRIVE_EPS:
		_advance_roam()
		point = _roam_points[_roam_index]
		dist = _player.global_position.distance_to(point)
	_roam_stuck_t += delta
	if _roam_stuck_t >= STUCK_INTERVAL:
		_roam_stuck_t = 0.0
		_roam_stuck_count = _roam_stuck_count + 1 if _roam_last_dist - dist < STUCK_PROGRESS_EPS else 0
		_roam_last_dist = dist
		if _roam_stuck_count >= STUCK_LIMIT:
			_advance_roam()
			point = _roam_points[_roam_index]
	_player.set_auto_move(_player.global_position.direction_to(point))
	_set_state(State.ROAM)

func _build_roam_points() -> void:
	_roam_points.clear()
	var world := get_tree().get_first_node_in_group("map_world")
	if world == null:
		return
	var ground := world.get_node_or_null("Ground") as IsoGround
	if ground == null:
		return
	var xs: Array[int] = []
	var ys: Array[int] = []
	for x in range(2, maxi(3, ground.grid_size.x - 2), ROAM_GRID_STEP):
		xs.append(x)
	for y in range(2, maxi(3, ground.grid_size.y - 2), ROAM_GRID_STEP):
		ys.append(y)
	if xs.is_empty() or xs.back() != ground.grid_size.x - 3:
		xs.append(maxi(2, ground.grid_size.x - 3))
	if ys.is_empty() or ys.back() != ground.grid_size.y - 3:
		ys.append(maxi(2, ground.grid_size.y - 3))
	for row in range(ys.size()):
		for col in range(xs.size()):
			var x: int = xs[col] if row % 2 == 0 else xs[xs.size() - col - 1]
			_roam_points.append(ground.clamp_to_map(Iso.grid_to_world(Vector2i(x, ys[row]))))

func _advance_roam() -> void:
	_roam_index = (_roam_index + 1) % _roam_points.size()
	_reset_roam_progress()

func _reset_roam_progress() -> void:
	_roam_last_dist = INF
	_roam_stuck_t = 0.0
	_roam_stuck_count = 0

## T10：该掉落物当前是否可被拾取（背包满则不可，避免无限拾取满背包）。
func _can_pick(gi: GroundItem) -> bool:
	if String(gi.item.get("kind", "")) == "coin":
		return not GameState.gold_is_capped()
	return Inventory.has_space_for(GameState.inventory, gi.item)

# ---- 卡住检测与黑名单（3.14 ①，T08）----

func _tick_stuck(delta: float, dist: float) -> void:
	_stuck_t += delta
	if _stuck_t < STUCK_INTERVAL:
		return
	_stuck_t = 0.0
	if _last_dist - dist < STUCK_PROGRESS_EPS:
		_stuck_count += 1
		if _stuck_count >= STUCK_LIMIT:
			_blacklist_target(_target)
		return
	_stuck_count = 0
	_last_dist = dist

## 目标短期拉黑并改选（寻路空 / 终点占位 / 连续不推进 → 3.14 ①）。
func _blacklist_target(t: Node) -> void:
	if t != null and is_instance_valid(t):
		_blacklist[t.get_instance_id()] = BLACKLIST_TIME
		_toast("目标不可达，已改选", "info")
	_target = null
	_last_dist = INF
	_stuck_count = 0
	_blocked_t = BLOCKED_TIME
	_set_state(State.BLOCKED)
	_player.set_auto_move(Vector2.ZERO)

func _tick_blacklist(delta: float) -> void:
	if _blacklist.is_empty():
		return
	var expired: Array = []
	for id in _blacklist.keys():
		_blacklist[id] = float(_blacklist[id]) - delta
		if float(_blacklist[id]) <= 0.0:
			expired.append(id)
	for id in expired:
		_blacklist.erase(id)

func _is_blacklisted(t: Node) -> bool:
	return _blacklist.has(t.get_instance_id())

## 当前被拉黑的目标数（供回归断言）。
func blacklist_size() -> int:
	return _blacklist.size()

# ---- 手动接管检测（4.6）----

func _has_manual_input() -> bool:
	if Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.05:
		return true
	if Input.is_action_pressed("attack") or Input.is_action_pressed("target_next"):
		return true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return true
	return false

# ---- 状态与提示 ----

func _set_state(s: int, phase_override: String = "") -> void:
	if _state == s and phase_override.is_empty():
		return
	_state = s
	var label := phase_override if not phase_override.is_empty() else state_name(s)
	if label != _phase:
		_phase = label
		EventBus.auto_phase_changed.emit(_phase)

func _toast(text: String, kind: String = "info") -> void:
	EventBus.toast_requested.emit(text, kind)

## 状态名（供 HUD 显示「自动中 / 手动接管 / 暂停中」等，4.6）。
static func state_name(s: int) -> String:
	match s:
		State.OFF:
			return "关闭"
		State.SEARCH_TARGET:
			return "搜索目标"
		State.PATH_TO_TARGET:
			return "接近目标"
		State.ATTACK_TARGET:
			return "攻击中"
		State.SEARCH_LOOT:
			return "搜索掉落"
		State.PATH_TO_LOOT:
			return "走向掉落"
		State.PICK_UP:
			return "拾取中"
		State.RECOVER:
			return "暂停中"
		State.MANUAL_OVERRIDE:
			return "手动接管"
		State.BLOCKED:
			return "受阻改选"
		State.ROAM:
			return "漫游寻怪"
		_:
			return "未知"

func current_state() -> int:
	return _state

func current_phase() -> String:
	return _phase

func current_target() -> Node:
	return _target

# ---- 技能选择（3.14「优先可用范围技（命中 ≥2），否则单体 / 普攻；不绕过冷却」）----

## T11：MP / 冷却 / 等级任一不足即**不施放**该技能。
## 返回选中的技能字典；`{}` = 不施放技能（回退普攻）。
## 纯静态函数，便于无头回归（不依赖场景与玩家节点）。
static func choose_skill(skills: Array, level: int, mp: int, cooldowns: Dictionary,
		target_count: int) -> Dictionary:
	var aoe := {}
	var single := {}
	for s in skills:
		if not (s is Dictionary):
			continue
		var sid := String(s.get("id", ""))
		if sid.is_empty() or sid == "basic_slash":
			continue                                   # 普攻由攻击间隔单独驱动
		if String(s.get("kind", "attack")) != "attack":
			continue
		if int(s.get("unlockLevel", 1)) > level:
			continue                                   # 未解锁
		if int(s.get("manaCost", 0)) > mp:
			continue                                   # MP 不足 → 不施放
		if float(cooldowns.get(sid, 0.0)) > 0.0:
			continue                                   # 冷却中 → 不施放
		var is_aoe := String(s.get("shape", "single")) != "single"
		if is_aoe and target_count >= 2:
			if aoe.is_empty() or int(s.get("manaCost", 0)) < int(aoe.get("manaCost", 0)):
				aoe = s
		elif String(s.get("shape", "single")) == "single":
			if single.is_empty() or float(s.get("coefficient", 0.0)) > float(single.get("coefficient", 0.0)):
				single = s
	if not aoe.is_empty():
		return aoe
	return single

## 自动战斗是否愿意施放该技能：必须已接线（M1 仅普攻）。
func can_cast(skill_id: String) -> bool:
	return WIRED_SKILLS.has(skill_id)
