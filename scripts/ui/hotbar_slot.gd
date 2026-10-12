class_name HotbarSlot
extends Button

signal skill_dropped(index: int, skill_id: String)

var index := 0

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind") == "hotbar_skill" and data.get("id") == "basic_slash"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	skill_dropped.emit(index, String(data.id))
