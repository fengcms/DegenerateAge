extends Node2D
## Visible landmarks sit on blocked rock cells; collision comes from CaveLayout.

const PROPS := [
	[0, 6, 20], [1, 16, 15], [2, 29, 8], [3, 25, 24],
	[1, 15, 34], [0, 34, 33], [3, 43, 20],
]

func _ready() -> void:
	for entry in PROPS:
		var sprite := Sprite2D.new()
		sprite.texture = load("res://assets/tiles/cave/prop_%d.png" % entry[0]) as Texture2D
		sprite.centered = false
		sprite.offset = Vector2(-40, -72)
		sprite.position = Iso.grid_to_world(Vector2i(entry[1], entry[2]))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.z_as_relative = false
		sprite.z_index = clampi(roundi(sprite.position.y), -3500, 3500)
		add_child(sprite)
