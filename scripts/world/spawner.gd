class_name MonsterSpawner
extends Node2D
## 怪物点生成与刷新（产品文档 07 章 7.9）：按怪物点规格生成，击杀后按刷新时间重生。
## M1 用显式测试规格驱动；M3 起改为读 maps.json 的 spawnPoints（接口不变）。

const MONSTER_SCENE := preload("res://scenes/entities/Monster.tscn")
const MIN_SPAWN_DIST := 220.0   # 与玩家出生点的最小距离（px），避免开局被贴脸

var _ground: IsoGround = null
var _player: Node2D = null
var _rng := RandomNumberGenerator.new()
var _points: Array[Dictionary] = []

func setup(ground: IsoGround, player: Node2D) -> void:
	_ground = ground
	_player = player
	_rng.randomize()

## 从怪物点规格批量生成。传入 map_id 时，怪物等级按该地图 tierRange 约束。
## 无 map_id 的显式测试规格沿用原有等级，不受当前地图影响。
func spawn_from_specs(specs: Array, map_id: String = "") -> void:
	var tier_range: Array = []
	if not map_id.is_empty():
		var map_data: Variant = DataLoader.get_entry("maps", map_id)
		if map_data is Dictionary:
			var configured_tier: Variant = map_data.get("tierRange", [])
			if configured_tier is Array:
				tier_range = configured_tier
	for s in specs:
		if not (s is Dictionary):
			continue
		var monster_id := String(s.get("monsterId", s.get("id", "wolf_corrupted")))
		var spawn_level := int(s.get("level", 0))
		if tier_range.size() == 2:
			if spawn_level <= 0:
				var template: Variant = DataLoader.get_entry("monsters", monster_id)
				if template is Dictionary:
					spawn_level = int(template.get("level", 1))
			spawn_level = clampi(spawn_level, int(tier_range[0]), int(tier_range[1]))
		var count := int(s.get("count", 1))
		for _i in range(count):
			var point := {
				"monster_id": monster_id,
				"level": spawn_level,
				"respawn_time": maxf(1.0, float(s.get("respawnTime", 30.0))),
				"ai": bool(s.get("ai", true)),
				"entry": null,
				"tombstone": bool(s.get("tombstone", false)),
				"marker": null,
				"timer": 0.0,
			}
			_points.append(point)
			_spawn(point)

## 从地图数据（maps.json 的 spawnPoints）生成（M3 使用）。
func spawn_from_map(map_id: String) -> void:
	var m = DataLoader.get_entry("maps", map_id)
	if m == null:
		return
	var pts = m.get("spawnPoints", [])
	if pts is Array:
		spawn_from_specs(pts, map_id)

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

func _process(delta: float) -> void:
	# 已死亡的怪物点按 respawnTime 重新生成（7.9）
	for p in _points:
		if p.entry != null and is_instance_valid(p.entry):
			continue
		p.timer = float(p.timer) + delta
		if is_instance_valid(p.marker):
			p.marker.set_remaining(maxf(0, float(p.respawn_time) - float(p.timer)))
		if float(p.timer) >= float(p.respawn_time):
			_spawn(p)

## UI 使用当前实际刷新区域，死亡后保留旧点直到本点重生。
func marker_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for point in _points:
		if point.has("position"):
			out.append({"monster_id": point.monster_id, "position": point.position})
	return out

func _spawn(point: Dictionary) -> void:
	var m: Monster = MONSTER_SCENE.instantiate()
	m.monster_id = String(point.get("monster_id", "wolf_corrupted"))
	m.spawn_level = int(point.get("level", 0))
	m.ai_enabled = bool(point.get("ai", true))
	var pos: Vector2 = point.position if point.tombstone and point.has("position") else _random_spawn_position()
	if is_instance_valid(point.marker):
		point.marker.queue_free()
	point.marker = null
	point.position = pos
	m.position = pos
	m.spawn_position = pos
	m.died.connect(func(_id: String) -> void: _on_monster_died(point))
	add_child(m)
	point.entry = m
	point.timer = 0.0

func _on_monster_died(point: Dictionary) -> void:
	if point.tombstone and is_instance_valid(point.entry):
		point.position = point.entry.position
		var marker := BossTombstone.new()
		marker.position = point.position
		marker.set_remaining(float(point.respawn_time))
		add_child(marker)
		point.marker = marker
	point.entry = null
	point.timer = 0.0

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
		if pos.distance_to(center) >= MIN_SPAWN_DIST:
			return pos
	return Iso.grid_to_world(Vector2i(gs.x / 2 + 8, gs.y / 2 + 8))
