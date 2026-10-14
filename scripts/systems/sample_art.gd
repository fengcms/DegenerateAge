class_name SampleArt
extends RefCounted
## Runtime icon references are preloaded so JSON-selected equipment also survives export.
## Unmade assets continue to use the existing text/procedural fallback.

const ICONS := {
	"weapon_starter": preload("res://assets/sprites/equip/weapon_starter.png"),
	"weapon_wolfking": preload("res://assets/sprites/equip/weapon_wolfking.png"),
	"weapon_legendary_vein_guard": preload("res://assets/sprites/equip/weapon_legendary_vein_guard.png"),
	"weapon_iron": preload("res://assets/sprites/equip/weapon_starter.png"),
	"armor_starter": preload("res://assets/sprites/equip/armor_starter.png"),
	"armor_cloth": preload("res://assets/sprites/equip/armor_starter.png"),
	"helmet_cloth": preload("res://assets/sprites/equip/helmet_cloth.png"),
	"shoes_cloth": preload("res://assets/sprites/equip/shoes_cloth.png"),
	"shield_basic": preload("res://assets/sprites/equip/shield_basic.png"),
	"bracer_basic": preload("res://assets/sprites/equip/bracer_basic.png"),
	"knee_basic": preload("res://assets/sprites/equip/knee_basic.png"),
	"bracelet_basic": preload("res://assets/sprites/equip/bracelet_basic.png"),
	"ring_basic": preload("res://assets/sprites/equip/ring_basic.png"),
	"necklace_basic": preload("res://assets/sprites/equip/necklace_basic.png"),
	"potion_hp_small": preload("res://assets/sprites/items/potion_hp_small.png"),
	"spirit_shard": preload("res://assets/sprites/items/spirit_shard.png"),
}
const GROUND := {
	"weapon_starter": preload("res://assets/sprites/items/weapon_starter_ground.png"),
	"potion_hp_small": preload("res://assets/sprites/items/potion_hp_small_ground.png"),
	"spirit_shard": preload("res://assets/sprites/items/spirit_shard_ground.png"),
}
const SKILL_ICONS := {
	"basic_slash": preload("res://assets/sprites/skills/basic_slash.png"),
	"earth_cleave": preload("res://assets/sprites/skills/earth_cleave.png"),
	"whirlwind": preload("res://assets/sprites/skills/whirlwind.png"),
	"battle_focus": preload("res://assets/sprites/skills/battle_focus.png"),
	"armor_break": preload("res://assets/sprites/skills/armor_break.png"),
	"spirit_storm": preload("res://assets/sprites/skills/spirit_storm.png"),
}

static func skill_icon(skill_id: String) -> Texture2D:
	return SKILL_ICONS.get(skill_id) as Texture2D

static func icon_for(item: Variant) -> Texture2D:
	if not item is Dictionary:
		return null
	if String(item.get("kind", "")) == "equip":
		var item_id := String(item.get("itemId", ""))
		if ICONS.has(item_id):
			return ICONS[item_id] as Texture2D
		var template := Equipment.template_of(item)
		var path := String(template.get("icon", ""))
		if path.begins_with("res://") and ResourceLoader.exists(path, "Texture2D"):
			return load(path) as Texture2D
	return ICONS.get(String(item.get("itemId", ""))) as Texture2D

static func ground_for(item: Dictionary) -> Texture2D:
	return GROUND.get(String(item.get("itemId", ""))) as Texture2D

static func binding_icon(binding: Variant) -> Texture2D:
	if not binding is Dictionary:
		return null
	if binding.get("kind") == "skill":
		return skill_icon(String(binding.get("id", "")))
	if binding.get("kind") == "auto_potion" and binding.get("id") == "red":
		return ICONS.potion_hp_small
	return ICONS.get(String(binding.get("id", ""))) as Texture2D

static func decorate(button: Button, texture: Texture2D) -> void:
	if button is HotbarSlot and (button as HotbarSlot).entry is Dictionary:
		var binding: Dictionary = (button as HotbarSlot).entry
		if String(binding.get("kind", "")) == "skill":
			texture = skill_icon(String(binding.get("id", "")))
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var icon_width := 34
	if button is ItemSlot and (button as ItemSlot).role in [ItemSlot.ROLE_BAG, ItemSlot.ROLE_EQUIP]:
		# PNG artwork already keeps 12.5% transparent padding on each side.
		# Fill the slot canvas to make the painted subject occupy about 75%.
		icon_width = roundi(button.custom_minimum_size.x)
	button.add_theme_constant_override("icon_max_width", icon_width)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if texture != null:
		button.text = ""
