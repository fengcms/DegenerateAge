extends Node2D
## Decorative sample props; they do not add interaction or blocking geometry.

func _ready() -> void:
	_add_prop("res://assets/tiles/camp/campfire.png", Vector2i(18, 18), Vector2(32, 64))
	_add_prop("res://assets/tiles/camp/crate.png", Vector2i(17, 19), Vector2(32, 48))
	_add_prop("res://assets/tiles/camp/crate.png", Vector2i(16, 19), Vector2(32, 48))

func _add_prop(path: String, cell: Vector2i, pivot: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(path) as Texture2D
	sprite.centered = false
	sprite.offset = -pivot
	sprite.position = Iso.grid_to_world(cell)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_as_relative = false
	sprite.z_index = clampi(roundi(sprite.position.y), -3500, 3500)
	add_child(sprite)
