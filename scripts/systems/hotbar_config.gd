class_name HotbarConfig
extends RefCounted
## 12 格可配置操作。只持久化模板引用，不持有背包下标或运行时节点。

const SIZE := 12
const TOWN_SCROLL := "misc_town_scroll"
const ACTIVE_SKILLS := ["basic_slash", "earth_cleave", "whirlwind"]

static func defaults() -> Array:
	var slots: Array = [{"kind": "auto_potion", "id": "red"},
		{"kind": "auto_potion", "id": "blue"}, {"kind": "skill", "id": "basic_slash"}]
	while slots.size() < SIZE:
		slots.append(null)
	return slots

static func valid_entry(entry: Variant) -> bool:
	if entry == null:
		return true
	if not entry is Dictionary or entry.size() != 2 or not entry.get("kind") is String or not entry.get("id") is String:
		return false
	var id := String(entry.id)
	match String(entry.kind):
		"auto_potion": return id == "red" or id == "blue"
		"potion": return DataLoader.get_entry("potions", id) is Dictionary
		"skill": return ACTIVE_SKILLS.has(id) and DataLoader.get_entry("skills", id) is Dictionary
		"item": return id == TOWN_SCROLL and DataLoader.get_entry("miscItems", id) is Dictionary
	return false

static func valid_layout(layout: Variant) -> bool:
	if not layout is Array or layout.size() != SIZE:
		return false
	for entry in layout:
		if not valid_entry(entry):
			return false
	return true

static func entry_for_item(item: Dictionary) -> Dictionary:
	var entry := {"kind": "item" if String(item.get("kind", "")) == "misc" else "potion",
		"id": String(item.get("itemId", ""))}
	return entry if valid_entry(entry) else {}
