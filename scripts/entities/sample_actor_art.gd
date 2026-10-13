class_name SampleActorArt
extends Sprite2D
## Eight screen directions, eight key-pose rows. Presentation only.
## Rows: idle A/B, walk A/B, attack A/B, hit, death.

var facing := 0
var pose := "idle"
var _clock := 0.0
var _attack_left := 0.0
var _attack_duration := 0.28
var _hit_left := 0.0

static func attach(actor: Node2D, path: String, pivot: Vector2) -> SampleActorArt:
	var art := SampleActorArt.new()
	art.name = "SampleArt"
	art.texture = load(path) as Texture2D
	art.hframes = 8
	art.vframes = 8
	art.centered = false
	art.offset = -pivot
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	actor.add_child(art)
	return art

func face(vector: Vector2) -> void:
	if vector.length_squared() > 0.01:
		facing = posmod(roundi((vector.angle() - PI / 2.0) / (PI / 4.0)), 8)

func attack(vector: Vector2, interval: float) -> void:
	face(vector)
	_attack_duration = clampf(interval * 0.65, 0.12, 0.36)
	_attack_left = _attack_duration
	_hit_left = 0.0
	# Damage has already been resolved by the owner. Start at contact,
	# then recover: this animation has no gameplay callbacks.
	frame_coords = Vector2i(facing, 5)

func hit() -> void:
	_hit_left = 0.12

func _process(delta: float) -> void:
	_clock += delta
	_attack_left = maxf(0.0, _attack_left - delta)
	_hit_left = maxf(0.0, _hit_left - delta)
	var actor := get_parent() as CharacterBody2D
	if actor == null:
		return
	actor.z_index = clampi(roundi(actor.global_position.y), -3500, 3500)
	var row := 0
	if actor.get("is_dead") == true:
		pose = "death"
		row = 7
	elif _hit_left > 0.0:
		pose = "hit"
		row = 6
	elif _attack_left > 0.0:
		pose = "attack"
		row = 5 if _attack_left > _attack_duration * 0.5 else 4
	elif actor.velocity.length_squared() > 1.0:
		pose = "walk"
		face(actor.velocity)
		row = 2 + posmod(int(_clock * 10.0), 2)
	else:
		pose = "idle"
		row = posmod(int(_clock * 3.0), 2)
	frame_coords = Vector2i(facing, row)
