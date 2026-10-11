extends Node2D
## 世界根节点：装配地面、玩家、怪物生成器，设置出生点与相机边界。
## 依据产品文档 7.2（相机平滑跟随、防露边界）、7.9（怪物点刷新）。

## M1 测试怪物点（在营地图上验证 AI；M3 改为读 maps.json 的 spawnPoints）。
## 木桩 ai=false（静态教学目标）；野狼 ai=true（会巡逻 / 追击 / 攻击）。
const TEST_SPAWNS := [
	{"monsterId": "wolf_corrupted", "level": 2, "count": 2, "respawnTime": 15.0, "ai": true},
	{"monsterId": "training_dummy", "level": 1, "count": 1, "respawnTime": 600.0, "ai": false},
]

@onready var _ground: IsoGround = $Ground
@onready var _player: PlayerCharacter = $Entities/Player
@onready var _camera: Camera2D = $Entities/Player/Camera2D
@onready var _spawner: MonsterSpawner = $Spawner
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

func _unhandled_input(event: InputEvent) -> void:
	# 开发期验证键（M5 移除）：H = 自伤 15，用于验证 HUD 血条实时刷新。
	if OS.is_debug_build() and event.is_action_pressed("debug_hurt"):
		GameState.damage_player(15)
		get_viewport().set_input_as_handled()
