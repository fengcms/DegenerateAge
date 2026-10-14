class_name MonsterProjectile
extends Node2D
## Fixed-direction hostile projectile. The player can move out of its path.

var source: Monster
var direction := Vector2.RIGHT
var speed := 340.0
var remaining := 520.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(source) or source.is_dead:
		queue_free()
		return
	var step := direction * minf(remaining, speed * delta)
	global_position += step
	remaining -= step.length()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and player.get("is_dead") != true \
			and player.global_position.distance_to(global_position) <= 20.0:
		source._do_attack(player, false)
		queue_free()
		return
	if remaining <= 0.0 or MapService.is_in_rest_zone(GameState.current_map, global_position):
		queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 7.0, Color("ffb45c"))
	draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 16, Color("7f3224"), 2.0, true)
