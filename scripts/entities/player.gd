class_name PlayerCharacter
extends CharacterBody2D
## 玩家角色：八向归一化移动（产品文档 4.6 操控 / 7.2 移动）。
## M1 仅实现移动；战斗、属性、动画在后续子步骤接入。

const RADIUS := 12.0
const COLOR_BODY := Color("e8c07d")
const COLOR_EDGE := Color("6d4c1f")

## 移动速度（像素/秒）= 属性表 movementSpeed（格/秒）× 瓦片宽
var _speed: float = 256.0

func _ready() -> void:
	_speed = float(GameState.player.get("movementSpeed", 4.0)) * Iso.TILE_W

func _physics_process(_delta: float) -> void:
	# Input.get_vector 已做归一化：斜向不会比正向更快（八向移动）
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * _speed
	move_and_slide()

func _draw() -> void:
	# 占位角色：圆形身体 + 描边（脚底碰撞体见 CollisionShape2D）
	draw_circle(Vector2.ZERO, RADIUS, COLOR_BODY)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 28, COLOR_EDGE, 2.0, true)
