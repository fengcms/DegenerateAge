extends Node2D
## 世界根节点：装配地面、实体与测试目标，设置出生点与相机边界。
## 依据产品文档 7.2（相机平滑跟随、防露边界）。

## M1-4 静态测试目标（AI 于 M1-5 接入）：2 只腐化野狼 + 1 个教学木桩。
const MONSTER_SCENE := preload("res://scenes/entities/Monster.tscn")
const TEST_TARGETS := [
	{"id": "wolf_corrupted", "offset": Vector2(56.0, 0.0)},
	{"id": "wolf_corrupted", "offset": Vector2(-70.0, -20.0)},
	{"id": "training_dummy", "offset": Vector2(0.0, -70.0)},
]

@onready var _ground: IsoGround = $Ground
@onready var _player: PlayerCharacter = $Entities/Player
@onready var _camera: Camera2D = $Entities/Player/Camera2D
@onready var _targets: Node2D = $Targets
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

	_spawn_test_targets()

func _spawn_test_targets() -> void:
	var center := _ground.get_map_center_world()
	for spec in TEST_TARGETS:
		var m: Node2D = MONSTER_SCENE.instantiate()
		m.monster_id = String(spec["id"])
		m.position = center + Vector2(spec["offset"])
		_targets.add_child(m)

func _unhandled_input(event: InputEvent) -> void:
	# 开发期验证键（M5 移除）：H = 自伤 15，用于验证 HUD 血条实时刷新。
	if OS.is_debug_build() and event.is_action_pressed("debug_hurt"):
		GameState.damage_player(15)
		get_viewport().set_input_as_handled()
