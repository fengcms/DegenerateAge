class_name ItemUtil
extends RefCounted
## 物品通用工具（产品文档 05 章 / 10.2）：品质枚举、颜色、名称、可堆叠判定。
##
## 品质与颜色（5.7）：普通白 / 优秀蓝 / 稀有绿 / 史诗黄 / 传说紫。
## 供地面物品绘制、背包（M1-7）与提示复用，避免颜色散落在各处。

## 五品质枚举（B-P3-6：本常量是品质顺序的唯一来源，`Shop.QUALITY_ORDER` 引用此处）。
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

## 装备品质唯一解析口径：优先实例自带，缺失回退模板 `defaultQuality`（工程 111 收敛）。
## 原先这段逻辑只存在于 `Shop.item_quality()`，导致背包 / 地面掉落用的是裸
## `item.get("quality","common")` —— 同一件装备在货郎托盘按模板品质上色、
## 在地上按白色上色。三处口径统一走这里，`Shop.item_quality()` 改为委托。
static func quality_of(item: Dictionary) -> String:
	var q := String(item.get("quality", ""))
	if q.is_empty():
		var tpl = DataLoader.get_entry("equipments", String(item.get("itemId", "")))
		if tpl is Dictionary:
			q = String(tpl.get("defaultQuality", "common"))
	return q if not q.is_empty() else "common"

static func quality_name(q: String) -> String:
	return QUALITY_NAME.get(q, "普通")

static func kind_color(kind: String) -> Color:
	return KIND_COLOR.get(kind, Color("cccccc"))

## ---- 如意分档强调色（工程 111，方案 A：复用装备品质色） ----
## 四档如意的图标几乎一模一样（四张图平均色明度差不到 10%），而格内文字又被
## `SampleArt.decorate()` 在有图标时清成空串 ⇒ **边框色是这个界面唯一真实可见的区分**。
## 取值刻意与 `QUALITY_COLOR` 的 uncommon/rare/epic/legendary 同值：蓝/绿/金/紫是
## 玩家已熟悉的品质语汇，不另造一套色号。
## 🔴 若将来调整 `QUALITY_COLOR`，须同步这四个值 —— `RuneAccentTest` 断言两者相等。
const ACCENT_COLOR := {
	"steel": Color("4aa3e0"),    # = uncommon 蓝
	"jade": Color("46c46a"),     # = rare 绿
	"gold": Color("e0c04a"),     # = epic 金
	"diamond": Color("b46ae0"),  # = legendary 紫
}

## 界面强调色唯一入口：格子边框 / 格内文字 / 地面装备名牌与光柱 / 缺图色块全用它。
## （地面只有**装备**有名字与光柱，如意落地看不到分色 —— 见工程 111 §9.2 / 坑 100。）
## 🔴 禁止在面板里再写 `if kind == "rune"`：背包 / 仓库 / 货郎托盘 / 地面掉落四处
## 各写一份判定，就是四份必须同步维护的分支（111 §2.1，08 坑 64 的老相识）。
static func item_accent_color(item: Dictionary) -> Color:
	# 缺 `kind` 时按 `misc` 兜底：四处消费点原本三处就是这么写的，
	# 空串会落到 `kind_color()` 的 `#cccccc`，等于把「没有 kind 的杂项」从土黄变成灰。
	var kind := String(item.get("kind", "misc"))
	if kind == "equip":
		return quality_color(quality_of(item))
	if kind == "rune":
		return rune_accent_color(String(item.get("itemId", "")))
	return kind_color(kind)

## 如意按模板 `accent` 分档。未配置（老档 / 将来新增未登记）回落品类青绿，
## 不落白框也不会崩 —— 兜底色仍是 `KIND_COLOR["rune"]`。
## 🔑 按 itemId 查模板、不读实例字段：老存档里的如意没有 `accent` 也照样正确上色，
## 不需要任何存档迁移（111 R-6）。
static func rune_accent_color(rune_id: String) -> Color:
	var tpl = DataLoader.get_entry("runes", rune_id)
	var accent := String(tpl.get("accent", "")) if tpl is Dictionary else ""
	return ACCENT_COLOR.get(accent, KIND_COLOR["rune"])

## ---- 星级角标（工程 76） ----
## 颜色取「亮化版」品质色：品质框本身是 蓝/绿/金/紫，星级若用同色会出现
## 「金角标 + 绿边框」的误读，故各提亮一档拉开明度差（见工程 76 §5.1）。
const STAR_BADGE_COLOR := {
	"low": Color("5ac8fa"),    # 1—5 星：亮蓝（uncommon #4aa3e0 的提亮版）
	"mid": Color("7bee8c"),    # 6—8 星：亮绿（rare #46c46a 的提亮版）
	"high": Color("ffd24a"),   # 9—11 星：亮金（epic #e0c04a 的提亮版）
	"max": Color("ffb347"),    # 12 星：暖橙占位（emoji 太阳不认 font_color，仅供断言与兜底）
}
const STAR_BADGE_SIZE := 11
## 满星 13px：emoji 太阳在小字号下射线会糊成一团橙点，加 2px 才认得出。
const STAR_BADGE_SIZE_MAX := 13

## 0 星返回空串（不显示）；满星返回 **彩色 emoji 太阳**，其余 `★N`。
## 必须用 ★(U+2605) 而不是 ⭐(U+2B50)：后者是彩色 emoji，font_color 无效，
## 做不出「1—5 蓝 / 6—8 绿 / 9—11 金」的颜色分档（实测见工程 76 §2）。
static func star_badge_text(star: int) -> String:
	if star <= 0:
		return ""
	if star >= Upgrade.max_star():
		return "☀️"
	return "★%d" % star

static func star_badge_color(star: int) -> Color:
	if star <= 0:
		return Color.TRANSPARENT
	if star >= Upgrade.max_star():
		return STAR_BADGE_COLOR["max"]
	if star >= 9:
		return STAR_BADGE_COLOR["high"]
	if star >= 6:
		return STAR_BADGE_COLOR["mid"]
	return STAR_BADGE_COLOR["low"]

static func star_badge_font_size(star: int) -> int:
	return STAR_BADGE_SIZE_MAX if star >= Upgrade.max_star() else STAR_BADGE_SIZE

static func is_stackable(item: Dictionary) -> bool:
	return STACKABLE_KINDS.has(String(item.get("kind", "")))

## 堆叠上限：药品与如意读取模板 stackMax，未配置沿用默认 99。
static func stack_max(item: Dictionary) -> int:
	var kind := String(item.get("kind", ""))
	if kind in ["potion", "rune"]:
		var p = DataLoader.get_entry("potions" if kind == "potion" else "runes", String(item.get("itemId", "")))
		if p is Dictionary:
			return int(p.get("stackMax", DEFAULT_STACK_MAX))
	return DEFAULT_STACK_MAX

## 界面显示名：装备带品质前缀与等级（如「稀有 铁制短刃 Lv1」）。
static func display_name(item: Dictionary) -> String:
	var kind := String(item.get("kind", ""))
	var base := _base_name(item)
	if kind == "coin":
		return "金币 ×%d" % int(item.get("gold", 0))
	if kind == "equip":
		var q := String(item.get("quality", "common"))
		var lv := int(item.get("requiredLevel", 1))
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

## 与战斗共用三轴结算：显示未升星基底、品质增量及各分项升星增量。
## 合成公式由 EquipmentMath 唯一提供（B-P3-5），本层只取分项文本。
static func attr_lines(item: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var star_factor := EquipmentMath.star_factor(item)
	var breakdown := EquipmentMath.base_breakdown(item)
	for stat in breakdown.keys():
		var parts: Dictionary = breakdown[stat]
		var line := stat_line(String(stat), float(parts.get("raw", 0.0)))
		var quality_bonus := float(parts.get("quality", 0.0))
		if not is_zero_approx(quality_bonus):
			line += "  品质 %s" % stat_value(String(stat), quality_bonus)
		var star_bonus := float(parts.get("star", 0.0))
		if not is_zero_approx(star_bonus):
			line += "  升星 %s" % stat_value(String(stat), star_bonus)
		lines.append(line)
	for key in ["affixes", "pctAttrs"]:
		var arr = item.get(key, [])
		if arr is Array:
			for e in arr:
				if e is Dictionary:
					var stat := String(e.get("stat", ""))
					var value := float(e.get("value", 0.0))
					var line := "词条 %s" % stat_line(stat, value)
					if not is_equal_approx(star_factor, 1.0):
						line += "  升星 %s" % stat_value(stat, value * (star_factor - 1.0))
					lines.append(line)
	if ReforgeAffixes.unlocked(item):
		lines.append(Localization.tr_key("ui.item.fifth_unlocked"))
	return lines

## 只列词条的文本（M10-8 重铸面板：新词条 / 旧词条对比）。
## 与 `attr_lines()` 的区别：**不混基底、不掺升星增量** —— 重铸改的就是这两个数组，
## 玩家需要看到的是「这一掷换来了什么」，掺进基底会让对比失去意义。
static func affix_lines(item: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key in ["affixes", "pctAttrs"]:
		var arr = item.get(key, [])
		if not arr is Array:
			continue
		for e in arr:
			if e is Dictionary:
				lines.append(stat_line(String(e.get("stat", "")), float(e.get("value", 0.0))))
	return lines

## 单条属性文本，如「攻击 +5」「生命 +6.5%」。
static func stat_line(stat: String, value: float) -> String:
	var label := String(STAT_LABEL.get(stat, stat))
	return "%s %s" % [label, stat_value(stat, value)]

## 属性数值片段，升星加成与原始值使用相同单位和精度。
static func stat_value(stat: String, value: float) -> String:
	if PERCENT_STATS.has(stat):
		return "+%.1f%%" % (value * 100.0)
	return "+%d" % int(round(value)) if is_equal_approx(value, round(value)) else "+%.1f" % value

## 装备模板名（槽内缩写 / 文本引用用）。
static func template_name(item: Dictionary) -> String:
	return _base_name(item)
