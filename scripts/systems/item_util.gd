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
	"mount": Color("a68be2"),
}

## 可堆叠物品（药品 / 杂项 / 如意 / 任务物）；装备不可堆叠（5.8）。
const STACKABLE_KINDS := ["potion", "misc", "rune", "quest"]

## 默认堆叠上限（无 stackMax 配置时，5.8：药品 / 材料堆叠 99）。
const DEFAULT_STACK_MAX := 99

## 药品始终以形状文字区分；友好预设同时换成色弱更容易辨识的黄/青组合。
static func potion_kind(item_id: String) -> String:
	var template = DataLoader.get_entry("potions", item_id)
	return String(template.get("kind", "")) if template is Dictionary else ""

static func potion_marker(kind: String) -> String:
	return "十" if kind == "red" else ("滴" if kind == "blue" else "")

static func potion_marker_color(kind: String) -> Color:
	var friendly := String(GameState.settings.get("colorblindMode", "off")) == "friendly"
	if kind == "red":
		return Color("f2c14e") if friendly else Color("ff8585")
	if kind == "blue":
		return Color("56d2c9") if friendly else Color("80aaff")
	return Color.WHITE

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
		var star := int(item.get("star", 0))
		return "%s %s Lv%d%s" % [quality_name(q), base, lv, " +%d" % star if star > 0 else ""]
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
		"mount": table = "mounts"
	var e = DataLoader.get_entry(table, id)
	if e is Dictionary:
		return String(e.get("name", id))
	return id

# ---- 属性文本化（5.2 / 5.10；供装备 tooltip 与对比面板使用）----

## 属性键 → 界面文案（4.2 属性表 / 5.10 词条池）。
const STAT_LABEL := {
	"atk": "攻击", "def": "防御", "hp": "生命", "mp": "法力",
	"hpPercent": "生命", "mpPercent": "法力",
	"criticalChance": "暴击率", "criticalMultiplier": "暴击伤害",
	"attackInterval": "攻击间隔", "dodge": "闪避", "block": "格挡",
	"cdr": "冷却缩减", "movementSpeed": "移动速度",
}

## 以百分比显示的属性键。
const PERCENT_STATS := [
	"hpPercent", "mpPercent", "criticalChance", "dodge", "block", "cdr",
]

## 把一件装备的属性整理成可显示行：基础属性 → 随机词条 → 百分比词条。
static func attr_lines(item: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var base = Upgrade.base_attrs(item)
	if base is Dictionary:
		for k in base.keys():
			lines.append(stat_line(String(k), float(base[k])))
	for key in ["affixes", "pctAttrs"]:
		var arr = item.get(key, [])
		if arr is Array:
			for e in arr:
				if e is Dictionary:
					lines.append(stat_line(String(e.get("stat", "")), float(e.get("value", 0.0))))
	return lines

## 单条属性文本，如「攻击 +5」「生命 +6.5%」。
static func stat_line(stat: String, value: float) -> String:
	var label := String(STAT_LABEL.get(stat, stat))
	if PERCENT_STATS.has(stat):
		return "%s +%.1f%%" % [label, value * 100.0]
	return "%s +%d" % [label, int(round(value))]

## 装备模板名（槽内缩写 / 文本引用用）。
static func template_name(item: Dictionary) -> String:
	return _base_name(item)
