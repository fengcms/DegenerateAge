extends Node
## Validate the visible quality animation on both inventory and equipment slots.

var failures: Array[String] = []

func _ready() -> void:
	for role in [ItemSlot.ROLE_BAG, ItemSlot.ROLE_EQUIP]:
		var slot := ItemSlot.new() if role == ItemSlot.ROLE_BAG else EquipmentSlot.new()
		slot.role = role
		if slot is EquipmentSlot:
			(slot as EquipmentSlot).slot_id = "weapon"
		slot.custom_minimum_size = Vector2(46, 46) if role == ItemSlot.ROLE_BAG else Vector2(52, 52)
		add_child(slot)
		await get_tree().process_frame
		check(slot._quality_frame.size == slot.size, "quality frame fills the item slot")
		for quality in ["uncommon", "rare", "epic", "legendary"]:
			var item := ItemFactory.make_equip_roll("weapon_starter", 10, quality)
			slot.item = item
			SampleArt.decorate(slot, SampleArt.icon_for(item))
			var frame := slot._quality_frame as QualityFrameOverlay
			check(frame.visible and frame.texture is AtlasTexture, "%s %s animated frame" % [role, quality])
			check(frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "frame does not intercept input")
			check((frame.texture as AtlasTexture).atlas == QualityFrameOverlay.ATLASES[quality], "correct atlas for " + quality)
			check((frame.texture as AtlasTexture).region == Rect2(0, 0, 64, 64), "initial frame for " + quality)
			frame._process(0.2)
			check((frame.texture as AtlasTexture).region != Rect2(0, 0, 64, 64), "frame advances for " + quality)
			check(slot.get_theme_constant("icon_max_width") == int(slot.custom_minimum_size.x), "slot artwork fills canvas")
		slot.item = ItemFactory.make_equip_roll("weapon_starter", 10, "common")
		check(not slot._quality_frame.visible and slot._quality_frame.texture == null, "common equipment has no effect")
		slot.item = {"kind": "potion", "itemId": "potion_hp_small"}
		check(not slot._quality_frame.visible, "non-equipment has no effect")
		slot.queue_free()
	if failures.is_empty():
		print("[QualityFrameTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
