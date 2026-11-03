extends Node
## 背包与穿戴格品质框验收：图标原画布与34像素边距，以及原动画输入契约。

var failures: Array[String] = []

## 在两类真实格子中验证图标、品质动画与输入边界，验证回归后的原画布显示尺寸。
func _ready() -> void:
	for role in [ItemSlot.ROLE_BAG, ItemSlot.ROLE_EQUIP]:
		var slot := ItemSlot.new() if role == ItemSlot.ROLE_BAG else EquipmentSlot.new()
		slot.role = role
		if slot is EquipmentSlot:
			(slot as EquipmentSlot).slot_id = "weapon"
		slot.custom_minimum_size = Vector2(46, 46) if role == ItemSlot.ROLE_BAG else Vector2(52, 52)
		add_child(slot)
		await get_tree().process_frame
		check(slot._quality_frame.size == slot.size + Vector2(4, 4), "quality frame reaches the slot edge")
		for quality in ["uncommon", "rare", "epic", "legendary"]:
			var item := ItemFactory.make_equip_roll("weapon_iron", 1, quality)
			slot.item = item
			SampleArt.decorate(slot, SampleArt.icon_for(item))
			var original_icon := SampleArt.icon_for(item)
			SampleArt.decorate(slot, SampleArt.icon_for(item))
			check(is_same(original_icon,slot.icon), "复用原画布纹理，不裁边放大")
			var frame := slot._quality_frame as QualityFrameOverlay
			check(frame.visible and frame.texture is AtlasTexture, "%s %s animated frame" % [role, quality])
			check(frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "frame does not intercept input")
			check((frame.texture as AtlasTexture).atlas == QualityFrameOverlay.ATLASES[quality], "correct atlas for " + quality)
			check((frame.texture as AtlasTexture).region == Rect2(0, 0, 64, 64), "initial frame for " + quality)
			frame._started_usec = Time.get_ticks_usec() - 200000
			frame._process(0.0)
			check((frame.texture as AtlasTexture).region != Rect2(0, 0, 64, 64), "frame advances for " + quality)
			check(slot.get_theme_constant("icon_max_width") == 34, "图标保留34像素上限，不铺满格子")
			check(slot.get_theme_constant("icon_max_width") < int(slot.custom_minimum_size.x),
				"背包及穿戴格保留图标边距")
			if role == ItemSlot.ROLE_BAG:
				var bag_panel := preload("res://scripts/ui/inventory_panel.gd").new()
				bag_panel._apply_slot_style(slot, ItemUtil.quality_color(quality), true)
				bag_panel.free()
			else:
				var character_panel := preload("res://scripts/ui/character_panel.gd").new()
				character_panel._style_equipment_slot(slot, item)
				character_panel.free()
			check((slot.get_theme_stylebox("normal") as StyleBoxFlat).border_color.a == 0.0,
				"animated frame replaces static quality border")
		slot.item = ItemFactory.make_equip_roll("weapon_iron", 1, "common")
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

## 聚合视觉契约失败，不以正常退出掩盖断言错误。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
