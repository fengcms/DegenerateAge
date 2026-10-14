extends Node

class CountingLayout extends CaveLayout:
	var path_calls := 0
	func path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
		path_calls += 1
		return super.path(from_cell, to_cell)

class CountingPilot extends AutoBattle:
	var builds := 0
	func _build_roam_points() -> void:
		builds += 1
		super._build_roam_points()

func fixture(path: String, rows: Array, points: Dictionary = {}) -> CaveLayout:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"grid_size": [rows[0].length(), rows.size()],
		"walkable_rows": rows, "points": points}))
	file.close()
	return CaveLayout.new(path)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze(child)

func _ready() -> void:
	GameState.reset_to_defaults()
	var diagonal := fixture("user://connectivity-diagonal.json", ["100", "010", "001"])
	assert(not diagonal.reachable(Vector2i.ZERO, Vector2i(1, 1)), "Diagonal corner cutting remains forbidden")
	var gate := fixture("user://connectivity-gate.json", ["1111111", "1111111", "1111111", "1111111", "1111111"], {"gate": [3, 2]})
	var left := Vector2i(2, 2)
	var right := Vector2i(4, 2)
	assert(gate.reachable(left, right))
	gate.set_access_gate_open(false)
	assert(not gate.reachable(left, right), "Closing gate splits connected regions")
	var revision := gate.navigation_revision
	gate.set_access_gate_open(false)
	assert(gate.navigation_revision == revision, "Unchanged gate does not invalidate caches")
	var ground := IsoGround.new()
	ground.grid_size = gate.size
	ground.cave = gate
	var nav := CaveNavigator.new()
	var origin := Iso.grid_to_world(left)
	var destination := Iso.grid_to_world(right)
	assert(nav.direction(ground, origin, destination) == Vector2.ZERO)
	gate.set_access_gate_open(true)
	assert(gate.reachable(left, right))
	assert(nav.direction(ground, origin, destination) != Vector2.ZERO, "Opening gate retries cached unreachable route")
	gate.set_access_gate_open(false)
	assert(nav.direction(ground, origin, destination) == Vector2.ZERO, "Closing gate rejects a cached route")
	ground.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 741
	for map_id in ["corruption_source", "c2_lower_works", "c2_well_core"]:
		var layout := CaveLayout.new(String(MapService.data_for(map_id).layoutPath))
		for i in range(32):
			var a := Vector2i(rng.randi_range(0, layout.size.x - 1), rng.randi_range(0, layout.size.y - 1))
			var b := Vector2i(rng.randi_range(0, layout.size.x - 1), rng.randi_range(0, layout.size.y - 1))
			assert(layout.reachable(a, b) == not layout.path(a, b).is_empty(), "Connectivity must match AStar")
	GameState.current_map = "c2_lower_works"
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	freeze(main)
	var real_ground := main.get_node("Game/Ground") as IsoGround
	var counting := CountingLayout.new(String(MapService.data_for(GameState.current_map).layoutPath))
	real_ground.cave = counting
	var pilot := main.get_node("Game/Entities/Player/AutoPilot") as AutoBattle
	pilot._build_roam_points()
	assert(pilot._roam_points.size() == 624)
	assert(counting.path_calls == 0, "Roam candidates must not construct full routes")
	assert(pilot._roam_built)
	# A reachable island with no 7-grid sample is a valid empty result.
	var empty_samples := fixture("user://connectivity-empty-samples.json", [
		"0000000", "0000000", "0000000", "0001000", "0000000", "0000000", "0000000"])
	real_ground.cave = empty_samples
	real_ground.grid_size = empty_samples.size
	var player := main.get_node("Game/Entities/Player") as PlayerCharacter
	player.position = Iso.grid_to_world(Vector2i(3, 3))
	var counter := CountingPilot.new()
	player.add_child(counter)
	counter.set_physics_process(false)
	counter._tick_roam(0.0)
	counter._tick_roam(0.0)
	assert(counter._roam_points.is_empty() and counter.builds == 1, "Empty roam list is not rebuilt every frame")
	print("[CaveConnectivityTest] PASS")
	get_tree().quit()
