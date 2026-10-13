extends Node2D
## Purely visual scene landmarks; navigation and collisions stay data-driven.

var map_id := "wild_trial"

const WILD_CELLS := [
	[0, 14, 21], [1, 18, 37], [2, 25, 18], [3, 38, 23],
	[0, 43, 38], [1, 48, 20], [2, 35, 43], [3, 10, 40],
]
const ASH_CELLS := [
	[0, 13, 20], [1, 20, 39], [2, 26, 18], [3, 37, 22],
	[0, 44, 40], [1, 50, 19], [2, 39, 44], [3, 11, 41],
]

func _ready() -> void:
	var theme := "wild" if map_id == "wild_trial" else "ash"
	var cells: Array = WILD_CELLS if map_id == "wild_trial" else ASH_CELLS
	for entry in cells:
		var sprite := Sprite2D.new()
		sprite.texture = load("res://assets/tiles/%s/prop_%d.png" % [theme, entry[0]]) as Texture2D
		sprite.centered = false
		sprite.offset = Vector2(-40, -72)
		sprite.position = Iso.grid_to_world(Vector2i(entry[1], entry[2]))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.z_as_relative = false
		sprite.z_index = clampi(roundi(sprite.position.y), -3500, 3500)
		add_child(sprite)
