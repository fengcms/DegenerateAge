extends Node
## Check the actual equipment, skill panel and hotbar texture paths used by players.

var failures: Array[String] = []

func _ready() -> void:
	for template in DataLoader.get_table("equipments"):
		var id := String(template.id)
		var item := ItemFactory.make_equip(id)
		var icon := SampleArt.icon_for(item)
		check(icon != null and icon.get_size() == Vector2(48, 48), "%s equipment icon" % id)
		check(icon != null and icon.resource_path == String(template.icon), "%s uses configured icon" % id)
	# 全套药水、如意与已制作的杂项图标必须通过物品实例入口进入背包和地面。
	var designed_items := [
		"potion_hp_small", "potion_mp_small", "potion_hp_mid", "potion_mp_mid",
		"potion_hp_large", "potion_mp_large", "rune_iron", "rune_jade",
		"rune_gold", "rune_diamond", "misc_firework", "misc_random_ticket",
		"misc_town_scroll", "misc_revive_scroll", "spirit_shard",
	]
	for id in designed_items:
		var item := ItemFactory.make_any(id)
		var icon := SampleArt.icon_for(item)
		check(icon != null and icon.get_size() == Vector2(48, 48)
			and icon.resource_path == "res://assets/sprites/items/%s.png" % id,
			"%s uses delivered item icon" % id)
		check(SampleArt.ground_for(item) == icon, "%s ground drop uses delivered icon" % id)
	var coin := {"kind": "coin", "itemId": "coin", "gold": 1, "count": 1}
	check(SampleArt.ground_for(coin) != null
		and SampleArt.ground_for(coin).resource_path == "res://assets/sprites/items/coin.png",
		"ground coin uses delivered icon")
	check(HotbarVisual.binding_icon({"kind": "auto_potion", "id": "red"}) == SampleArt.icon_for(ItemFactory.make_any("potion_hp_small"))
		and HotbarVisual.binding_icon({"kind": "auto_potion", "id": "blue"}) == SampleArt.icon_for(ItemFactory.make_any("potion_mp_small")),
		"hotbar automatic potions use delivered red and blue icons")
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
	for index in range(2):
		var kind := "red" if index == 0 else "blue"
		var button := panel._potion_buttons[kind] as SkillDragButton
		check(button.icon == SampleArt.binding_icon({"kind": "auto_potion", "id": kind})
			and button.text.is_empty(), "%s automatic potion picker icon" % kind)
	if failures.is_empty():
		print("[IconIntegrationTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
