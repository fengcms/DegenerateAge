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
const CHAPTER_TWO_NORMAL_BUDGET := 10
## 无地图的显式测试规格（`spawn_from_specs` 未传 map_id）所用的状态前缀 ——
## 保证这类点同样受刷新状态管理（否则会「击杀即重生」，违反 7.9）。
const LOCAL_MAP_ID := "_local"

var _ground: IsoGround = null
var _player: Node2D = null
var _rng := RandomNumberGenerator.new()
var _points: Array[Dictionary] = []
## 当前装配的地图 id（M4-10：刷新状态 key 需要）。显式测试规格为空 → 用 LOCAL_MAP_ID。
var _map_id: String = ""
## 本图装配期的「同种怪物序号」计数（跨 spawnPoints / bossSpawn 两次调用累计）。
var _ordinal: Dictionary = {}

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
	_ordinal.clear()
	var pts = m.get("spawnPoints", [])
	if pts is Array:
		spawn_from_specs(pts, map_id)

## 从怪物点规格批量生成。传入 map_id 时，怪物等级按该地图 tierRange 约束。
## 无 map_id 的显式测试规格沿用原有等级，状态归入 LOCAL_MAP_ID 前缀。
func spawn_from_specs(specs: Array, map_id: String = "") -> void:
	if not map_id.is_empty():
		_map_id = map_id
	var tier_range: Array = []
	if not _map_id.is_empty():
		var map_data: Variant = DataLoader.get_entry("maps", _map_id)
		if map_data is Dictionary:
			var configured: Variant = (map_data as Dictionary).get("tierRange", [])
			if configured is Array:
				tier_range = configured
	var active_normal := _active_normal_count() if _map_id.begins_with("c2_") else 0
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
			if _spawn(point, active_normal) and String(point.kind) == "normal":
				active_normal += 1

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
	var active_normal := _active_normal_count() if _map_id.begins_with("c2_") else 0
	# M4-10：倒计时由 `GameState.world_time` 统一驱动（本节点不再累加 delta）。
	for p in _points:
		if p.entry != null and is_instance_valid(p.entry):
			if bool(p.get("fixed", false)) and _player != null \
					and (p.entry as Node2D).global_position.distance_to(_player.global_position) > RETIRE_DISTANCE:
				p.entry.queue_free()
				p.entry = null
				if String(p.kind) == "normal":
					active_normal -= 1
			continue
		var remaining := _remaining(p)
		if remaining > 0.0:
			if is_instance_valid(p.marker):
				p.marker.set_remaining(remaining)
			continue
		if _spawn(p, active_normal) and String(p.kind) == "normal":
			active_normal += 1

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

func _spawn(point: Dictionary, active_normal: int = -1) -> bool:
	var unlock := String(point.get("requires_unlock", ""))
	if not unlock.is_empty() and not bool(GameState.unlocks.get(unlock, false)):
		return false
	if bool(point.get("fixed", false)) and _player != null \
			and (point.position as Vector2).distance_to(_player.global_position) > ACTIVE_DISTANCE:
		return false
	# A standalone call may compute its own snapshot; batch callers supply one.
	if active_normal < 0:
		active_normal = _active_normal_count()
	if _map_id.begins_with("c2_") and String(point.get("kind", "normal")) == "normal" \
			and active_normal >= CHAPTER_TWO_NORMAL_BUDGET:
		return false
	# M4-10：仍在刷新等待期 → 不生成怪物；「墓碑点」显示墓碑，其余静默等待。
	var remaining := _remaining(point)
	if remaining > 0.0:
		if bool(point.get("tombstone", false)):
			_place_tombstone(point, remaining)
		point.entry = null
		return false

	var m: Monster = MONSTER_SCENE.instantiate()
	m.monster_id = String(point.get("monster_id", "wolf_corrupted"))
	m.drop_table_override = String(point.get("drop_table", ""))
	m.spawn_level = int(point.get("level", 0))
	m.ai_enabled = bool(point.get("ai", true))
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

func _active_normal_count() -> int:
	var count := 0
	for point in _points:
		if String(point.get("kind", "normal")) == "normal" and is_instance_valid(point.get("entry")):
			count += 1
	return count

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
