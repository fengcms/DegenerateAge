class_name ItemUtil
extends RefCounted
## 物品通用工具（产品文档 05 章 / 10.2）：品质枚举、颜色、名称、可堆叠判定。
##
## 品质与颜色（5.7）：普通白 / 优秀蓝 / 稀有绿 / 史诗黄 / 传说紫。
## 供地面物品绘制、背包（M1-7）与提示复用，避免颜色散落在各处。

const QUALITIES := ["common", "uncommon", "rare", "epic", "legendary"]

const QUALITY_NAME := {
	"common": "普通",
	"uncommon": "优秀",
	"rare": "稀有",
	"epic": "史诗",
	"legendary": "传说",
}

## 5.7 颜色：白 / 蓝 / 绿 / 黄 / 紫
const QUALITY_COLOR := {
	"common": Color("d8d8d8"),
	"uncommon": Color("4aa3e0"),
	"rare": Color("46c46a"),
	"epic": Color("e0c04a"),
	"legendary": Color("b46ae0"),
}

## 分类（kind）→ 默认图标底色（占位；正式图标见 assets/sprites）
const KIND_COLOR := {
	"coin": Color("e8c24a"),
	"potion": Color("cf4a4a"),
	"equip": Color("6f8fd0"),
	"rune": Color("8ad2c8"),
	"misc": Color("b8a06a"),
	"quest": Color("d8a03a"),
}

## 可堆叠物品（药品 / 杂项 / 如意 / 任务物）；装备不可堆叠（5.8）。
const STACKABLE_KINDS := ["potion", "misc", "rune", "quest"]

## 默认堆叠上限（无 stackMax 配置时，5.8：药品 / 材料堆叠 99）。
const DEFAULT_STACK_MAX := 99

static func is_valid_quality(q: String) -> bool:
	return QUALITIES.has(q)

static func quality_color(q: String) -> Color:
	return QUALITY_COLOR.get(q, QUALITY_COLOR["common"])

static func quality_name(q: String) -> String:
	return QUALITY_NAME.get(q, "普通")

static func kind_color(kind: String) -> Color:
	return KIND_COLOR.get(kind, Color("cccccc"))

static func is_stackable(item: Dictionary) -> bool:
	return STACKABLE_KINDS.has(String(item.get("kind", "")))

## 堆叠上限：药品读 potions.json 的 stackMax，其余用默认 99。
static func stack_max(item: Dictionary) -> int:
	if String(item.get("kind", "")) == "potion":
		var p = DataLoader.get_entry("potions", String(item.get("itemId", "")))
		if p is Dictionary:
			return int(p.get("stackMax", DEFAULT_STACK_MAX))
	return DEFAULT_STACK_MAX

## 界面显示名：装备带品质前缀与等级（如「稀有 狼王之刃 Lv4」）。
static func display_name(item: Dictionary) -> String:
	var kind := String(item.get("kind", ""))
	var base := _base_name(item)
	if kind == "coin":
		return "金币 ×%d" % int(item.get("gold", 0))
	if kind == "equip":
		var q := String(item.get("quality", "common"))
		var lv := int(item.get("level", 1))
		return "%s %s Lv%d" % [quality_name(q), base, lv]
	var n := int(item.get("count", 1))
	return base if n <= 1 else "%s ×%d" % [base, n]

## 从各配置表解析基础名（模板名）。
static func _base_name(item: Dictionary) -> String:
	var id := String(item.get("itemId", ""))
	var kind := String(item.get("kind", ""))
	var table := "equipments"
	match kind:
		"potion": table = "potions"
		"rune": table = "runes"
		"misc", "quest": table = "miscItems"
	var e = DataLoader.get_entry(table, id)
	if e is Dictionary:
		return String(e.get("name", id))
	return id
