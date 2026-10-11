extends Node2D
## 世界根节点：装配地面、玩家、怪物生成器、安全区 NPC，设置出生点与相机边界。
## 依据产品文档 7.2（相机平滑跟随、防露边界）、7.9（怪物点刷新）、6.3（安全区 NPC）。

const NPC_SCENE := preload("res://scenes/entities/Npc.tscn")

## M1 测试怪物点（在营地图上验证 AI；M3 改为读 maps.json 的 spawnPoints）。
## 木桩 ai=false（静态教学目标）；野狼 ai=true（会巡逻 / 追击 / 攻击）。
const TEST_SPAWNS := [
	{"monsterId": "wolf_corrupted", "level": 2, "count": 2, "respawnTime": 15.0, "ai": true},
	{"monsterId": "training_dummy", "level": 1, "count": 1, "respawnTime": 600.0, "ai": false},
]

## M1 安全区 NPC（6.3：每个地图的安全区聚集功能性 NPC；M3 改为读 maps.json 的 NPC 点）。
## cell 为等距网格坐标；货郎放在出生点附近（营地中心偏西 4 格），开局即可走到。
const TEST_NPCS := [
	{"shopId": "peddler_camp", "cell": Vector2i(16, 20)},
]

@onready var _ground: IsoGround = $Ground
@onready var _player: PlayerCharacter = $Entities/Player
@onready var _camera: Camera2D = $Entities/Player/Camera2D
@onready var _spawner: MonsterSpawner = $Spawner
@onready var _npcs: Node2D = $Npcs
@onready var _damage_numbers: Node2D = $DamageNumbers

func _ready() -> void:
	_damage_numbers.add_to_group("damage_numbers")

	# 出生点：地图中心
	_player.global_position = _ground.get_map_center_world()

	# 相机限制到地图包围盒，避免露出边界外的空白
	var b: Rect2 = _ground.get_world_bounds()
	_camera.limit_left = int(b.position.x)
	_camera.limit_top = int(b.position.y)
	_camera.limit_right = int(b.end.x)
	_camera.limit_bottom = int(b.end.y)
	_camera.reset_smoothing()

	# 怪物点（M1-5）
	_spawner.setup(_ground, _player)
	_spawner.spawn_from_specs(TEST_SPAWNS)

	# 安全区 NPC（M1-8）
	_spawn_npcs()

## 按测试规格生成 NPC（6.3）。M3 起改为读 maps.json 的 NPC 点。
func _spawn_npcs() -> void:
	for spec in TEST_NPCS:
		if not (spec is Dictionary):
			continue
		var npc: Npc = NPC_SCENE.instantiate()
		npc.shop_id = String(spec.get("shopId", ""))
		var cell: Vector2i = spec.get("cell", Vector2i.ZERO)
		npc.position = Iso.grid_to_world(cell)
		_npcs.add_child(npc)

func _unhandled_input(event: InputEvent) -> void:
	# 开发期验证键（M5 移除）：H = 自伤 15，用于验证 HUD 血条实时刷新。
	if OS.is_debug_build() and event.is_action_pressed("debug_hurt"):
		GameState.damage_player(15)
		get_viewport().set_input_as_handled()
		return

	# 与 NPC 交互（6.3 通用交互）：靠近后按 E；面板打开时不响应
	if event.is_action_pressed("interact") and not GameState.panel_open:
		if _try_interact():
			get_viewport().set_input_as_handled()

## 就近与 NPC 交互：成功派发返回 true（6.3 通用交互入口，后续对话系统 9.8 在此扩展）。
func _try_interact() -> bool:
	var npc := nearest_npc()
	if npc == null:
		return false
	if not npc.shop_id.is_empty():
		EventBus.shop_open_requested.emit(npc.shop_id)
		return true
	return false

## 交互半径内的最近 NPC（无则 null）。
func nearest_npc() -> Npc:
	var best: Npc = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("npcs"):
		if not (n is Npc):
			continue
		var npc := n as Npc
		if not npc.is_player_in_range():
			continue
		var d := npc.global_position.distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = npc
	return best

