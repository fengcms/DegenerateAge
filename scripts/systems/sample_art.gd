class_name SampleArt
extends RefCounted
## Runtime icon references are preloaded so JSON-selected equipment also survives export.
## Unmade assets continue to use the existing text/procedural fallback.

const ICONS := {
	"weapon_starter": preload("res://assets/sprites/equip/weapon_starter.png"),
	"weapon_wolfking": preload("res://assets/sprites/equip/weapon_wolfking.png"),
	"weapon_legendary_vein_guard": preload("res://assets/sprites/equip/weapon_legendary_vein_guard.png"),
	"weapon_iron": preload("res://assets/sprites/equip/weapon_starter.png"),
	"potion_hp_small": preload("res://assets/sprites/items/potion_hp_small.png"),
	"spirit_shard": preload("res://assets/sprites/items/spirit_shard.png"),
}
const GROUND := {
	"weapon_starter": preload("res://assets/sprites/items/weapon_starter_ground.png"),
	"potion_hp_small": preload("res://assets/sprites/items/potion_hp_small_ground.png"),
	"spirit_shard": preload("res://assets/sprites/items/spirit_shard_ground.png"),
}

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
	if binding.get("kind") == "auto_potion" and binding.get("id") == "red":
		return ICONS.potion_hp_small
	return ICONS.get(String(binding.get("id", ""))) as Texture2D

static func decorate(button: Button, texture: Texture2D) -> void:
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 34)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if texture != null:
		button.text = ""
