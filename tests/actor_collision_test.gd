extends Node
## 玩家和怪物碰撞层验收：战斗目标不能成为硬路障，地图静态墙仍须阻挡移动。
## 只在隔离场景中实例化物理体，不修改地图或玩家存档。

var failures: Array[String] = []

## 放置密集怪群与静态墙，直接查询两类碰撞而不依赖攻击输入。
func _ready() -> void:
	GameState.reset_to_defaults()
	var player := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as PlayerCharacter
	player.position = Vector2.ZERO
	add_child(player)
	player.set_physics_process(false)
	var first_monster: Monster = null
	for i in range(5):
		var monster := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
		monster.ai_enabled = false
		monster.position = Vector2(30 + i * 20, 0)
		add_child(monster)
		monster.set_physics_process(false)
		if i == 0:
			first_monster = monster
	await get_tree().physics_frame
	_check(player.collision_layer == 2 and player.collision_mask == 1, "玩家只与地形层物理碰撞")
	_check(not player.test_move(player.global_transform, Vector2(100, 0)), "密集怪群不能阻挡玩家横向移动")
	_check(first_monster.collision_layer == 4 and first_monster.collision_mask == 1
		and not first_monster.test_move(first_monster.global_transform, Vector2(-30, 0)),
		"怪物也不会推动玩家或其他怪物")
	var wall := StaticBody2D.new()
	wall.position = Vector2(150, 0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 80)
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	_check(player.test_move(player.global_transform, Vector2(180, 0)), "同一路线仍被静态墙阻挡")
	_check(first_monster.test_move(first_monster.global_transform, Vector2(130, 0)), "怪物仍被静态墙阻挡")
	print("[ActorCollisionTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 将实际物理行为失败记录为非零退出码，避免只检查配置值。
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ActorCollisionTest] " + message)
