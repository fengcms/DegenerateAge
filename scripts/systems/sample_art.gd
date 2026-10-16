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
	"c2_road_blade": preload("res://assets/sprites/equip/c2_road_blade.png"),
	"c2_copper_shield": preload("res://assets/sprites/equip/c2_copper_shield.png"),
	"c2_road_armor": preload("res://assets/sprites/equip/c2_road_armor.png"),
	"c2_road_helmet": preload("res://assets/sprites/equip/c2_road_helmet.png"),
	"c2_road_shoes": preload("res://assets/sprites/equip/c2_road_shoes.png"),
	"c2_road_bracer": preload("res://assets/sprites/equip/c2_road_bracer.png"),
	"c2_road_knee": preload("res://assets/sprites/equip/c2_road_knee.png"),
	"c2_copper_bracelet": preload("res://assets/sprites/equip/c2_copper_bracelet.png"),
	"c2_road_ring": preload("res://assets/sprites/equip/c2_road_ring.png"),
	"c2_warm_necklace": preload("res://assets/sprites/equip/c2_warm_necklace.png"),
	"c2_pressure_plate": preload("res://assets/sprites/items/c2_pressure_plate.png"),
	"c2_worker_badge": preload("res://assets/sprites/items/c2_worker_badge.png"),
	"c2_heat_component": preload("res://assets/sprites/items/c2_heat_component.png"),
	"c2_named_badge": preload("res://assets/sprites/items/c2_named_badge.png"),
	"c3_equip_weapon": preload("res://assets/sprites/equip/c3_equip_weapon.png"),
	"c3_equip_shoes": preload("res://assets/sprites/equip/c3_equip_shoes.png"),
	"c3_equip_armor": preload("res://assets/sprites/equip/c3_equip_armor.png"),
	"c3_equip_helmet": preload("res://assets/sprites/equip/c3_equip_helmet.png"),
	"c3_equip_bracer": preload("res://assets/sprites/equip/c3_equip_bracer.png"),
	"c3_equip_knee": preload("res://assets/sprites/equip/c3_equip_knee.png"),
	"c3_equip_shield": preload("res://assets/sprites/equip/c3_equip_shield.png"),
	"c3_equip_bracelet": preload("res://assets/sprites/equip/c3_equip_bracelet.png"),
	"c3_equip_ring": preload("res://assets/sprites/equip/c3_equip_ring.png"),
	"c3_equip_necklace": preload("res://assets/sprites/equip/c3_equip_necklace.png"),
	"c3_item_q03": preload("res://assets/sprites/items/c3_item_q03.png"),
	"c3_item_q06": preload("res://assets/sprites/items/c3_item_q06.png"),
	"c3_item_s02": preload("res://assets/sprites/items/c3_item_s02.png"),
	"c3_item_s03": preload("res://assets/sprites/items/c3_item_s03.png"),
	"c4_equip_weapon": preload("res://assets/sprites/equip/c4_equip_weapon.png"),
	"c4_equip_shoes": preload("res://assets/sprites/equip/c4_equip_shoes.png"),
	"c4_equip_armor": preload("res://assets/sprites/equip/c4_equip_armor.png"),
	"c4_equip_helmet": preload("res://assets/sprites/equip/c4_equip_helmet.png"),
	"c4_equip_bracer": preload("res://assets/sprites/equip/c4_equip_bracer.png"),
	"c4_equip_knee": preload("res://assets/sprites/equip/c4_equip_knee.png"),
	"c4_equip_shield": preload("res://assets/sprites/equip/c4_equip_shield.png"),
	"c4_equip_bracelet": preload("res://assets/sprites/equip/c4_equip_bracelet.png"),
	"c4_equip_ring": preload("res://assets/sprites/equip/c4_equip_ring.png"),
	"c4_equip_necklace": preload("res://assets/sprites/equip/c4_equip_necklace.png"),
	"c4_item_q02": preload("res://assets/sprites/items/c4_item_q02.png"),
	"c4_item_q06": preload("res://assets/sprites/items/c4_item_q06.png"),
	"c4_item_s02": preload("res://assets/sprites/items/c4_item_s02.png"),
	"c4_item_s03": preload("res://assets/sprites/items/c4_item_s03.png"),
	"c5_equip_weapon": preload("res://assets/sprites/equip/c5_equip_weapon.png"),
	"c5_equip_shoes": preload("res://assets/sprites/equip/c5_equip_shoes.png"),
	"c5_equip_armor": preload("res://assets/sprites/equip/c5_equip_armor.png"),
	"c5_equip_helmet": preload("res://assets/sprites/equip/c5_equip_helmet.png"),
	"c5_equip_bracer": preload("res://assets/sprites/equip/c5_equip_bracer.png"),
	"c5_equip_knee": preload("res://assets/sprites/equip/c5_equip_knee.png"),
	"c5_equip_shield": preload("res://assets/sprites/equip/c5_equip_shield.png"),
	"c5_equip_bracelet": preload("res://assets/sprites/equip/c5_equip_bracelet.png"),
	"c5_equip_ring": preload("res://assets/sprites/equip/c5_equip_ring.png"),
	"c5_equip_necklace": preload("res://assets/sprites/equip/c5_equip_necklace.png"),
	"c5_item_q03": preload("res://assets/sprites/items/c5_item_q03.png"),
	"c5_item_q06": preload("res://assets/sprites/items/c5_item_q06.png"),
	"c5_item_s02": preload("res://assets/sprites/items/c5_item_s02.png"),
	"c5_item_s03": preload("res://assets/sprites/items/c5_item_s03.png"),
	"c5_item_s06": preload("res://assets/sprites/items/c5_item_s06.png"),
	"c6_equip_weapon": preload("res://assets/sprites/equip/c6_equip_weapon.png"),
	"c6_equip_shoes": preload("res://assets/sprites/equip/c6_equip_shoes.png"),
	"c6_equip_armor": preload("res://assets/sprites/equip/c6_equip_armor.png"),
	"c6_equip_helmet": preload("res://assets/sprites/equip/c6_equip_helmet.png"),
	"c6_equip_bracer": preload("res://assets/sprites/equip/c6_equip_bracer.png"),
	"c6_equip_knee": preload("res://assets/sprites/equip/c6_equip_knee.png"),
	"c6_equip_shield": preload("res://assets/sprites/equip/c6_equip_shield.png"),
	"c6_equip_bracelet": preload("res://assets/sprites/equip/c6_equip_bracelet.png"),
	"c6_equip_ring": preload("res://assets/sprites/equip/c6_equip_ring.png"),
	"c6_equip_necklace": preload("res://assets/sprites/equip/c6_equip_necklace.png"),
	"c6_item_q03": preload("res://assets/sprites/items/c6_item_q03.png"),
	"c6_item_q06": preload("res://assets/sprites/items/c6_item_q06.png"),
	"c6_item_s01": preload("res://assets/sprites/items/c6_item_s01.png"),
	"c6_item_s03": preload("res://assets/sprites/items/c6_item_s03.png"),
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

## 读取预载技能图标；找不到时返回空，供快捷栏保留文字回退。
static func skill_icon(skill_id: String) -> Texture2D:
	return SKILL_ICONS.get(skill_id) as Texture2D

## 按物品实例 ID 读取预载图标；装备旧路径只作过渡回退。
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

## 返回快捷键绑定对应的物品或技能图标，未配置时返回空。
static func binding_icon(binding: Variant) -> Texture2D:
	if not binding is Dictionary:
		return null
	if binding.get("kind") == "skill":
		return skill_icon(String(binding.get("id", "")))
	if binding.get("kind") == "auto_potion":
		return ICONS.potion_hp_small if binding.get("id") == "red" else ICONS.potion_mp_small if binding.get("id") == "blue" else null
	return ICONS.get(String(binding.get("id", ""))) as Texture2D

## 将图标应用到快捷栏按钮；只调整视觉，不改变绑定行为。
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
