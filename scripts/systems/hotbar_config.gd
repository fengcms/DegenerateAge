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
## 引擎真的实现了该能力的技能并集（工程 98：两职业各 6 条）。
## 启动校验 `tests/skill_capability_test.gd` 断言它等于「所有职业 `skills` 并集」且等于 `skills.json` 全量，
## 少一条就等于玩家永远拖不进，多一条就是假技能。
## ⚠ 单职业视角用 `active_skills(class_id)`；本常量只用于「格式是否可拖入」这一个纯静态判定
## （`valid_entry` 没有职业上下文，也不该有 —— 它会读到别人的档）。
const ACTIVE_SKILLS := [
	"basic_slash", "earth_cleave", "whirlwind", "battle_focus", "armor_break", "spirit_storm",
	"basic_fireball", "lightning", "flame_burst", "magic_shield", "frost_roar", "meteor",
]

## 本职业可拖上快捷栏的技能（含普攻）。`class_id` 留空 = 当前存档职业。
static func active_skills(class_id: String = "") -> Array:
	return PlayerClass.active_skills(class_id)

## 该技能是否属于指定职业（留空 = 当前职业）。施放与技能面板都走这里，避免两处各写一遍。
static func usable_skill(skill_id: String, class_id: String = "") -> bool:
	return active_skills(class_id).has(skill_id)

## 默认快捷栏：红药 / 蓝药 / 本职业普攻。第三格的技能 id 必须按职业取，
## 否则法师新档第 3 格挂的是破甲前的 `basic_slash`（点下去无反应且不在技能面板里）。
static func defaults(class_id: String = "") -> Array:
	var slots: Array = [{"kind": "auto_potion", "id": "red"},
		{"kind": "auto_potion", "id": "blue"},
		{"kind": "skill", "id": PlayerClass.basic_skill(class_id)}]
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
