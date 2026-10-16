class_name SampleArt
extends RefCounted
## 运行时预载正式装备与物品图标，保证 JSON 配置的资源进入导出包。
## 尚未制作的素材继续走既有文字或程序绘制回退；旧专名图标不再独立入表。

const ICONS := {
	"weapon_iron": preload("res://assets/sprites/equip/weapon_starter.png"),
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
	"potion_mp_small": preload("res://assets/sprites/items/potion_mp_small.png"),
	"potion_hp_mid": preload("res://assets/sprites/items/potion_hp_mid.png"),
	"potion_mp_mid": preload("res://assets/sprites/items/potion_mp_mid.png"),
	"potion_hp_large": preload("res://assets/sprites/items/potion_hp_large.png"),
	"potion_mp_large": preload("res://assets/sprites/items/potion_mp_large.png"),
	"rune_iron": preload("res://assets/sprites/items/rune_iron.png"),
	"rune_jade": preload("res://assets/sprites/items/rune_jade.png"),
	"rune_gold": preload("res://assets/sprites/items/rune_gold.png"),
	"rune_diamond": preload("res://assets/sprites/items/rune_diamond.png"),
	"misc_firework": preload("res://assets/sprites/items/misc_firework.png"),
	"misc_random_ticket": preload("res://assets/sprites/items/misc_random_ticket.png"),
	"misc_town_scroll": preload("res://assets/sprites/items/misc_town_scroll.png"),
	"misc_revive_scroll": preload("res://assets/sprites/items/misc_revive_scroll.png"),
	"spirit_shard": preload("res://assets/sprites/items/spirit_shard.png"),
	"coin": preload("res://assets/sprites/items/coin.png"),
}
const GROUND := {
	"weapon_iron": preload("res://assets/sprites/items/weapon_starter_ground.png"),
}
const MOUNT_ICONS := {
	"mount_corrupted_wing": preload("res://assets/sprites/mounts/mount_corrupted_wing.png"),
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
	if String(item.get("kind", "")) == "mount":
		return MOUNT_ICONS.get(String(item.get("itemId", ""))) as Texture2D
	if String(item.get("kind", "")) == "equip":
		var item_id := String(item.get("itemId", ""))
		if ICONS.has(item_id):
			return ICONS[item_id] as Texture2D
		var template := Equipment.template_of(item)
		var path := String(template.get("icon", ""))
		if path.begins_with("res://") and ResourceLoader.exists(path, "Texture2D"):
			return load(path) as Texture2D
	return ICONS.get(String(item.get("itemId", ""))) as Texture2D

## 地面动画会反复重绘；只读取预载表，避免在绘制热路径动态加载装备模板贴图。
static func ground_for(item: Dictionary) -> Texture2D:
	var item_id := String(item.get("itemId", ""))
	if GROUND.has(item_id):
		return GROUND[item_id] as Texture2D
	if String(item.get("kind", "")) == "mount":
		return MOUNT_ICONS.get(item_id) as Texture2D
	return ICONS.get(item_id) as Texture2D

static func binding_icon(binding: Variant) -> Texture2D:
	if not binding is Dictionary:
		return null
	if binding.get("kind") == "skill":
		return skill_icon(String(binding.get("id", "")))
	if binding.get("kind") == "auto_potion":
		return ICONS.potion_hp_small if binding.get("id") == "red" else ICONS.potion_mp_small if binding.get("id") == "blue" else null
	return ICONS.get(String(binding.get("id", ""))) as Texture2D

static func decorate(button: Button, texture: Texture2D) -> void:
	if button is HotbarSlot and (button as HotbarSlot).entry is Dictionary:
		var binding: Dictionary = (button as HotbarSlot).entry
		if String(binding.get("kind", "")) == "skill":
			texture = skill_icon(String(binding.get("id", "")))
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 34)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if texture != null:
		button.text = ""
