extends Node2D
## 世界根节点：装配地面与实体，设置出生点与相机边界。
## 依据产品文档 7.2（相机平滑跟随、防露边界）。

@onready var _ground: IsoGround = $Ground
@onready var _player: PlayerCharacter = $Entities/Player
@onready var _camera: Camera2D = $Entities/Player/Camera2D

func _ready() -> void:
	# 出生点：地图中心
	_player.global_position = _ground.get_map_center_world()

	# 相机限制到地图包围盒，避免露出边界外的空白
	var b: Rect2 = _ground.get_world_bounds()
	_camera.limit_left = int(b.position.x)
	_camera.limit_top = int(b.position.y)
	_camera.limit_right = int(b.end.x)
	_camera.limit_bottom = int(b.end.y)
	_camera.reset_smoothing()
