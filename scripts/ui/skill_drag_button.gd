class_name SkillDragButton
extends Button

var skill_id := ""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or skill_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return {"kind": "hotbar_skill", "id": skill_id}
