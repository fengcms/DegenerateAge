class_name SkillDragButton
extends Button

var skill_id := ""
var drag_label := ""
var binding: Dictionary = {}

func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or (skill_id.is_empty() and binding.is_empty()):
		return null
	var layer := get_tree().get_first_node_in_group("drag_ghost_layer")
	var label := drag_label if not drag_label.is_empty() else text
	if layer != null and get_viewport().gui_is_dragging():
		DragGhost.spawn_text(layer, label)
	elif get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = label
		set_drag_preview(preview)
	if not binding.is_empty():
		return {"kind": "hotbar_binding", "entry": binding.duplicate(true)}
	return {"kind": "hotbar_skill", "id": skill_id}
