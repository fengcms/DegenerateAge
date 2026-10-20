class_name HotbarConfig
extends RefCounted
## 12 格可配置操作。只持久化模板引用，不持有背包下标或运行时节点。

const SIZE := 12
const TOWN_SCROLL := "misc_town_scroll"
const RANDOM_TICKET := "misc_random_ticket"
## 工程 80：可拖上快捷栏的 miscItems 类型 —— **必须与执行层同源**。
## 触发链路是 `GameState.use_item` → `_use_misc` 按 `useType` 分发，所以只有这里列出的类型
## 点了才有反应；口径放宽到「useType 非空」会把 `revive` / `quest` / `playAnimation`
## 也放进来，点上去弹「该物品无法使用」——那是**做出一个假功能**，不是多给一个格子。
## 新增类型时先确认 `_use_misc` 已实现该分支，再往这里加。
const USABLE_TYPES := ["townPortal", "randomTeleport", "panel"]
## R4-d：可装备技能必须与「引擎真的实现了该能力」同步。
## `armor_break`（L25，穿防 + 破甲）与 `spirit_storm`（L40，3 段）此前只存在于数据里，
## 引擎不认识 `defensePierce` / `debuff` / `hits`，加 id 会造出「描述写了、行为没有」的假技能。
const ACTIVE_SKILLS := ["basic_slash", "earth_cleave", "whirlwind", "battle_focus", "armor_break", "spirit_storm"]

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
		"item": return _usable_misc(id)
	return false

## 杂项能否拖上快捷栏：表里得有这条，且 `useType` 在 `USABLE_TYPES` 内（与 `_use_misc` 同源）。
static func _usable_misc(id: String) -> bool:
	var template: Variant = DataLoader.get_entry("miscItems", id)
	if not template is Dictionary:
		return false
	return USABLE_TYPES.has(String((template as Dictionary).get("useType", "")))

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
