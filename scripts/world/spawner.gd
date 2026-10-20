class_name MonsterSpawner
extends Node2D
## 怪物点生成与刷新（产品文档 07 章 7.9）：按怪物点规格生成，击杀后按刷新时间重生。
## 数据源：`maps.json` 的 `spawnPoints`（普通怪 / 精英）与 `bossSpawn`（Boss，M3）。
##
## M4-10（工程文档 14 §3.1）：**刷新倒计时跨地图 / 跨存档保持**。
##   ① 状态存于 `GameState.spawn_respawn`（Autoload，跨场景存活），由 `GameState.world_time` 统一驱动；
##   ② key = `map_id#monster_id#同种序号`（**稳定**，不用数组下标 → 地图增减点不错位，14 §5 R-a）；
##   ③ 带 `tombstone:true` 的点在等待期显示墓碑；其余点静默等待（跨图回来未到点就不生成）。
##
## ⚠ 旧实现把倒计时累加在场景运行态（`p.timer += delta`）——切图重载即清零，Boss 立刻复活
##   （工程文档 14 §1.1 的根因）。现改为读全局剩余时间，**本节点不再自持时钟**。

const MONSTER_SCENE := preload("res://scenes/entities/Monster.tscn")
const MIN_SPAWN_DIST := 220.0   # 与玩家出生点的最小距离（px），避免开局被贴脸
const ACTIVE_DISTANCE := 760.0
const RETIRE_DISTANCE := 1100.0
## E1（工程文档 30 §4）：刷新预算改由**每图配置**驱动 —— 读 `maps.json` 的
## `normalCap` / `eliteCap` / `bossCap`。未配置的旧图沿用旧行为：`c2_` 前缀限普通 10、其余不限。
const LEGACY_NORMAL_CAP := 10
const UNLIMITED_CAP := -1
## 无地图的显式测试规格（`spawn_from_specs` 未传 map_id）所用的状态前缀 ——
## 保证这类点同样受刷新状态管理（否则会「击杀即重生」，违反 7.9）。
const LOCAL_MAP_ID := "_local"

var _ground: IsoGround = null
var _player: Node2D = null
var _rng := RandomNumberGenerator.new()
var _points: Array[Dictionary] = []
## 当前装配的地图 id（M4-10：刷新状态 key 需要）。显式测试规格为空 → 用 LOCAL_MAP_ID。
var _map_id: String = ""
## 本图刷新预算（kind → cap；UNLIMITED_CAP = 该档不限）。装配期读一次，供批量生成 / _process 共用。
var _caps: Dictionary = {}
## 本图装配期的「同种怪物序号」计数（跨 spawnPoints / bossSpawn 两次调用累计）。
var _ordinal: Dictionary = {}
## M10-3（工程文档 43 §5.2）：本图怪物的**等级下限**。> 0 表示「等级跟随玩家」——
## 装配期不再按 `tierRange` 夹紧，改在 `_spawn` 里每次生成时现算（P-5：600s 复活
## 出来的不能永远是进图那天的等级）。存量图恒 0，整段是空操作。
var _level_min := 0

func setup(ground: IsoGround, player: Node2D) -> void:
	_ground = ground
	_player = player
	_rng.randomize()

## 从地图数据（maps.json 的 spawnPoints）生成（M3 使用）。
## 同时重置本图装配计数 —— 同图装配分两次调用（spawnPoints → bossSpawn），序号需连续。
func spawn_from_map(map_id: String) -> void:
	var m = DataLoader.get_entry("maps", map_id)
	if m == null:
		return
	_map_id = map_id
	_load_caps()
	_ordinal.clear()
	var pts = m.get("spawnPoints", [])
	if pts is Array:
		spawn_from_specs(pts, map_id)

## 从怪物点规格批量生成。传入 map_id 时，怪物等级按该地图 tierRange 约束；
## 配了 `levelFromPlayer.enabled` 的图（M10-3 循环图）不夹紧，改用 `_level_min`。
## 无 map_id 的显式测试规格沿用原有等级，状态归入 LOCAL_MAP_ID 前缀。
func spawn_from_specs(specs: Array, map_id: String = "") -> void:
	if not map_id.is_empty():
		_map_id = map_id
		_load_caps()
	var tier_range: Array = []
	var level_min := 0
	if not _map_id.is_empty():
		var map_data: Variant = DataLoader.get_entry("maps", _map_id)
		if map_data is Dictionary:
			# M10-3：等级跟随玩家的图**不配 tierRange**（启动校验强制），等级在 _spawn 里现算。
			var from_player: Variant = (map_data as Dictionary).get("levelFromPlayer", null)
			if from_player is Dictionary and bool((from_player as Dictionary).get("enabled", false)):
				level_min = maxi(1, int((from_player as Dictionary).get("minLevel", 1)))
			else:
				var configured: Variant = (map_data as Dictionary).get("tierRange", [])
				if configured is Array:
					tier_range = configured
	_level_min = level_min
	var active := _active_counts()
	for s in specs:
		if not (s is Dictionary):
			continue
		var spec: Dictionary = s
		var monster_id := String(spec.get("monsterId", spec.get("id", "wolf_corrupted")))
		var spawn_level := int(spec.get("level", 0))
		if tier_range.size() == 2:
			if spawn_level <= 0:
				var template: Variant = DataLoader.get_entry("monsters", monster_id)
				if template is Dictionary:
					spawn_level = int((template as Dictionary).get("level", 1))
			spawn_level = clampi(spawn_level, int(tier_range[0]), int(tier_range[1]))
		var count := int(spec.get("count", 1))
		# M10-3：`scaleStats` 的图（循环图）用 endgame.json 的归一化基底替换模板数值；
		# 未登记 norm 时留空字典，Monster 侧回退模板（不静默变成 1 血的纸 Boss）。
		var scale_stats := bool(spec.get("scaleStats", false))
		var norm: Dictionary = Endgame.norm(monster_id) if scale_stats else {}
		for _i in range(count):
			var ordinal := int(_ordinal.get(monster_id, 0))
			_ordinal[monster_id] = ordinal + 1
			var point := {
				"monster_id": monster_id,
				"ordinal": ordinal,
				"level": spawn_level,
				"respawn_time": maxf(1.0, float(spec.get("respawnTime", 30.0))),
				"ai": bool(spec.get("ai", true)),
				"kind": String(spec.get("kind", "normal")),
				"requires_unlock": String(spec.get("requiresUnlock", "")),
				"drop_table": String(spec.get("dropTableId", "")),
				"stat_norm": norm,
				"scale_stats": scale_stats,
				"xp_from_curve": bool(spec.get("xpFromCurve", false)),
				"xp_curve_divisor": maxi(1, int(spec.get("xpCurveDivisor", 1))),
				"xp_multiplier": float(spec.get("xpMultiplier", 1.0)),
				"hp_multiplier": float(spec.get("hpMultiplier", 1.0)),
				"atk_multiplier": float(spec.get("atkMultiplier", 1.0)),
				"entry": null,
				"tombstone": bool(spec.get("tombstone", false)),
				"marker": null,
			}
			var cells: Variant = spec.get("cells", null)
			var fixed_cell: Variant = cells[_i] if cells is Array and _i < cells.size() else spec.get("cell", null)
			if fixed_cell is Array and fixed_cell.size() == 2:
				point["position"] = Iso.grid_to_world(Vector2i(int(fixed_cell[0]), int(fixed_cell[1])))
				point["fixed"] = true
			_points.append(point)
			if _spawn(point, active):
				var kind := String(point.kind)
				active[kind] = int(active.get(kind, 0)) + 1

## 当前存活怪物数（测试 / 调试用）。
func alive_count() -> int:
	var n := 0
	for p in _points:
		if p.entry != null and is_instance_valid(p.entry):
			n += 1
	return n

## 怪物点总数。
func point_count() -> int:
	return _points.size()

func _process(_delta: float) -> void:
	# Each pass owns a budget snapshot; never rescan all sites for each candidate.
	var active := _active_counts()
	# M4-10：倒计时由 `GameState.world_time` 统一驱动（本节点不再累加 delta）。
	for p in _points:
		var kind := String(p.get("kind", "normal"))
		if p.entry != null and is_instance_valid(p.entry):
			if bool(p.get("fixed", false)) and _player != null \
					and (p.entry as Node2D).global_position.distance_to(_player.global_position) > RETIRE_DISTANCE:
				p.entry.queue_free()
				p.entry = null
				active[kind] = int(active.get(kind, 0)) - 1
			continue
		var remaining := _remaining(p)
		if remaining > 0.0:
			# M4-10 修复：等待期墓碑可能因装配时序缺失（未解锁 → 本图内解锁、
			# 预算、旧档），这里幂等补建；已存在时 `_place_tombstone` 首行即返回，
			# 只刷新剩余秒数，与原先的开销等价。
			if bool(p.get("tombstone", false)):
				_place_tombstone(p, remaining)
			elif is_instance_valid(p.marker):
				p.marker.set_remaining(remaining)
			continue
		if _spawn(p, active):
			active[kind] = int(active.get(kind, 0)) + 1

## 该点距刷新完成的剩余时间（秒）；无状态 → 0（可立即生成）。
func _remaining(point: Dictionary) -> float:
	return GameState.spawn_remaining(
		_state_map_id(), String(point.get("monster_id", "")), int(point.get("ordinal", 0)))

## 刷新状态所用的地图标识（显式测试规格归入 LOCAL_MAP_ID）。
func _state_map_id() -> String:
	return _map_id if not _map_id.is_empty() else LOCAL_MAP_ID

## UI 使用当前实际刷新区域，死亡后保留旧点直到本点重生。
func marker_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for point in _points:
		if point.has("position"):
			out.append({"monster_id": point.monster_id, "position": point.position})
	return out

func _spawn(point: Dictionary, active: Variant = null) -> bool:
	var unlock := String(point.get("requires_unlock", ""))
	if not unlock.is_empty() and not bool(GameState.unlocks.get(unlock, false)):
		return false
	# M4-10 修复（审阅 2026-10-17「Boss 墓碑跨地图消失」）：等待期先落墓碑。
	# 墓碑是刷新状态的可视化，不能被「玩家当前距离」「本图生成预算」这类**生成**前置
	# 条件挡住 —— 否则 fixed 点在远程装配时（跨图回来、从入口进图）永不显示墓碑。
	var remaining := _remaining(point)
	if remaining > 0.0:
		if bool(point.get("tombstone", false)):
			_place_tombstone(point, remaining)
		point.entry = null
		return false
	if bool(point.get("fixed", false)) and _player != null \
			and (point.position as Vector2).distance_to(_player.global_position) > ACTIVE_DISTANCE:
		return false
	# 批次调用方传入快照并自行维护增减；独立调用（不传 active）自算一次快照。
	var counts: Dictionary = active if active is Dictionary else _active_counts()
	# E1：按 kind 取本图上限（未配置 / 旧图 → UNLIMITED_CAP 或旧行为）。
	var kind := String(point.get("kind", "normal"))
	var cap := _cap_for(kind)
	if cap != UNLIMITED_CAP and int(counts.get(kind, 0)) >= cap:
		return false

	# M10-3（P-5）：等级跟随玩家的图必须在**每次生成**时现算并回写。
	# 600s 复活、跨图回来补建都走这里 ⇒ 不会固化成「进图那天的等级」。
	# 顺序放在 cap 之后、实例化之前：不改变任何既有分支的判定结果（`_level_min` 恒 0 时是空操作）。
	if _level_min > 0:
		point["level"] = maxi(_level_min, int(GameState.player.level))

	var m: Monster = MONSTER_SCENE.instantiate()
	m.monster_id = String(point.get("monster_id", "wolf_corrupted"))
	m.drop_table_override = String(point.get("drop_table", ""))
	m.spawn_level = int(point.get("level", 0))
	m.ai_enabled = bool(point.get("ai", true))
	var norm: Variant = point.get("stat_norm", {})
	m.stat_norm = norm if norm is Dictionary else {}
	m.scale_stats = bool(point.get("scale_stats", false))
	m.xp_from_curve = bool(point.get("xp_from_curve", false))
	m.xp_curve_divisor = int(point.get("xp_curve_divisor", 1))
	m.xp_multiplier = float(point.get("xp_multiplier", 1.0))
	m.hp_multiplier = float(point.get("hp_multiplier", 1.0))
	m.atk_multiplier = float(point.get("atk_multiplier", 1.0))
	var pos := _spawn_position(point)
	if is_instance_valid(point.marker):
		point.marker.queue_free()
	point.marker = null
	point.position = pos
	m.position = pos
	m.spawn_position = pos
	m.died.connect(func(_id: String) -> void: _on_monster_died(point))
	add_child(m)
	point.entry = m
	return true

## 本图存活怪物数（按 kind 分桶）—— 刷新预算快照用。
func _active_counts() -> Dictionary:
	var counts := {}
	for point in _points:
		if not is_instance_valid(point.get("entry")):
			continue
		var kind := String(point.get("kind", "normal"))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts

## 本图某档的刷新上限（E1）：优先读 `maps.json` 的 `normalCap`/`eliteCap`/`bossCap`；
## 未配置的旧图保留旧行为（`c2_` 前缀普通 10），其余不限。
func _cap_for(kind: String) -> int:
	if _caps.has(kind):
		return int(_caps[kind])
	if kind == "normal" and _map_id.begins_with("c2_"):
		return LEGACY_NORMAL_CAP
	return UNLIMITED_CAP

## 装配期缓存本图 cap 配置（无地图 / 显式测试规格 → 全不限）。
func _load_caps() -> void:
	_caps.clear()
	if _map_id.is_empty():
		return
	var m: Variant = DataLoader.get_entry("maps", _map_id)
	if not (m is Dictionary):
		return
	for kind in ["normal", "elite", "boss"]:
		var key: String = String(kind) + "Cap"
		if (m as Dictionary).has(key):
			_caps[String(kind)] = int((m as Dictionary).get(key, UNLIMITED_CAP))

func _on_monster_died(point: Dictionary) -> void:
	var pos := Vector2.ZERO
	var node := point.entry as Node2D
	if node != null and is_instance_valid(node):
		pos = node.global_position
	point.position = pos
	# M4-10：登记刷新状态（到点时刻 + 死亡位置）→ 跨图 / 跨档保持
	GameState.mark_spawn_dead(
		_state_map_id(),
		String(point.get("monster_id", "")),
		int(point.get("ordinal", 0)),
		float(point.get("respawn_time", 0.0)),
		pos)
	if bool(point.get("tombstone", false)):
		_place_tombstone(point, float(point.get("respawn_time", 0.0)))
	point.entry = null

## 放置 / 更新墓碑（位置取状态记录 → 本会话旧位置 → 随机兜底）。
func _place_tombstone(point: Dictionary, remaining: float) -> void:
	if is_instance_valid(point.marker):
		point.marker.set_remaining(remaining)
		return
	var pos := _tombstone_position(point)
	var marker := BossTombstone.new()
	marker.position = pos
	marker.set_remaining(remaining)
	add_child(marker)
	point.marker = marker
	point.position = pos

## 墓碑位置：优先取刷新状态里记录的死亡处（跨图 / 读档后在原处重建）。
func _tombstone_position(point: Dictionary) -> Vector2:
	var recorded: Variant = GameState.spawn_dead_pos(
		_state_map_id(), String(point.get("monster_id", "")), int(point.get("ordinal", 0)))
	if recorded is Vector2:
		return _ground.clamp_to_map(recorded) if _ground != null else recorded
	var previous: Variant = point.get("position", null)
	if previous is Vector2:
		return _ground.clamp_to_map(previous) if _ground != null else previous
	return _random_spawn_position()

## 生成位置：墓碑类点沿用固定位置（原位复活），其余随机。
func _spawn_position(point: Dictionary) -> Vector2:
	if bool(point.get("fixed", false)):
		return point.position
	if _ground != null and _ground.cave != null and String(point.get("monster_id", "")) == "boss_corrupted_beast":
		var boss_cell: Array = _ground.cave.points.get("beast", _ground.cave.points.get("boss_arena", [40, 26]))
		return Iso.grid_to_world(Vector2i(int(boss_cell[0]), int(boss_cell[1])))
	if bool(point.get("tombstone", false)):
		var saved := _tombstone_position(point)
		return _random_spawn_position() if MapService.is_in_rest_zone(_map_id, saved) else saved
	return _random_spawn_position()

## 在（网格）地图内随机取点，且与玩家出生点保持 MIN_SPAWN_DIST 以上距离。
func _random_spawn_position() -> Vector2:
	var gs := Vector2i(40, 40)
	if _ground != null:
		gs = _ground.grid_size
	var center := Vector2.ZERO
	if _player != null:
		center = _player.global_position
	var lo := 3
	var hx := maxi(lo + 1, gs.x - 4)
	var hy := maxi(lo + 1, gs.y - 4)
	for _i in range(40):
		var c := Vector2i(_rng.randi_range(lo, hx), _rng.randi_range(lo, hy))
		var pos := Iso.grid_to_world(c)
		if pos.distance_to(center) >= MIN_SPAWN_DIST and not MapService.is_in_rest_zone(_map_id, pos) and (_ground == null or _ground.is_walkable_cell(c)):
			return pos
	# 随机采样极端情况下可能连中休整区；确定性扫描保证兜底仍在区外。
	for y in range(lo, hy + 1):
		for x in range(lo, hx + 1):
			var pos := Iso.grid_to_world(Vector2i(x, y))
			if pos.distance_to(center) >= MIN_SPAWN_DIST and not MapService.is_in_rest_zone(_map_id, pos) and (_ground == null or _ground.is_walkable_cell(Vector2i(x, y))):
				return pos
	for y in range(lo, hy + 1):
		for x in range(lo, hx + 1):
			var pos := Iso.grid_to_world(Vector2i(x, y))
			if not MapService.is_in_rest_zone(_map_id, pos) and (_ground == null or _ground.is_walkable_cell(Vector2i(x, y))):
				return pos
	push_warning("[MonsterSpawner] 地图 %s 没有休整区外的可用刷新格" % _map_id)
	return center
