class_name SkillDragButton
extends Button

var skill_id := ""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or skill_id.is_empty():
		return null
	var layer := get_tree().get_first_node_in_group("drag_ghost_layer")
	if layer != null and get_viewport().gui_is_dragging():
		DragGhost.spawn_text(layer, text)
	elif get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = text
		set_drag_preview(preview)
	return {"kind": "hotbar_skill", "id": skill_id}
