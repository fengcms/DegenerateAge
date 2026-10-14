extends Node
## Check the actual equipment, skill panel and hotbar texture paths used by players.

var failures: Array[String] = []

func _ready() -> void:
	for template in DataLoader.get_table("equipments"):
		var id := String(template.id)
		for tier in [1, 10]:
			var item := ItemFactory.make_equip_roll(id, tier, "common")
			var icon := SampleArt.icon_for(item)
			check(icon != null and icon.get_size() == Vector2(48, 48), "%s Lv%d equipment icon" % [id, tier])
			check(icon != null and icon.resource_path == String(template.icon), "%s Lv%d uses configured icon" % [id, tier])
	var panel: Variant = preload("res://scripts/ui/skill_panel.gd").new()
	add_child(panel)
	panel._refresh()
	var rows: VBoxContainer = panel._list
	var skills: Array = DataLoader.get_table("skills")
	for index in range(skills.size()):
		var skill: Dictionary = skills[index]
		var id := String(skill.id)
		var texture := SampleArt.skill_icon(id)
		check(texture != null and texture.get_size() == Vector2(48, 48), id + " loaded texture")
		check(ResourceLoader.exists(String(skill.icon), "Texture2D"), id + " data path")
		var button := rows.get_child(index).get_child(0) as SkillDragButton
		check(button.icon == texture and button.text.is_empty(), id + " skill panel icon")
		check(button.drag_label == String(skill.name), id + " drag preview label")
		var slot := HotbarSlot.new()
		add_child(slot)
		slot.entry = {"kind": "skill", "id": id}
		SampleArt.decorate(slot, null)
		check(slot.icon == texture, id + " hotbar icon")
		slot.queue_free()
	if failures.is_empty():
		print("[IconIntegrationTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
