class_name Shop
extends RefCounted
## 货郎交易逻辑层（产品文档 6.4 购买 / 出售，6.2 售价公式）。
##
## 本层只做交易语义——读 shops.json、算价、构造物品实例；不依赖 UI 与 Autoload 单例，
## 由 GameState.shop_* 调用后统一广播事件（金币 / 背包 / 提示），便于单测与解耦。
## 数据驱动（10.2）：新增货郎 / 改价 = 改 shops.json，无需改代码。

## 6.2 品质售价倍率：普 1 / 优 1.5 / 稀 3 / 史 6 / 传 12。
const QUALITY_SELL_MULT := {
	"common": 1.0,
	"uncommon": 1.5,
	"rare": 3.0,
	"epic": 6.0,
	"legendary": 12.0,
}
const QUALITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary"]

static func matches_low_gear(item: Dictionary, level_limit: int, max_quality: String) -> bool:
	if not can_sell(item) or level_limit < 1:
		return false
	var quality_rank := QUALITY_ORDER.find(item_quality(item))
	var maximum_rank := QUALITY_ORDER.find(max_quality)
	return quality_rank >= 0 and maximum_rank >= 0 \
		and Equipment.level_req(item) < level_limit and quality_rank <= maximum_rank

## 6.2 每星加价 +8%。
const STAR_SELL_BONUS := 0.08

# ---- 读配置 ----

## 取货郎配置（shops.json，以 npcId 为唯一键）。不存在返回空字典。
static func entry(shop_id: String) -> Dictionary:
	var e = DataLoader.get_entry("shops", shop_id)
	return e if e is Dictionary else {}

## 货郎显示名（如「货郎（营地）」）。
static func display_name(shop_id: String) -> String:
	var e := entry(shop_id)
	return String(e.get("name", shop_id))

## 货郎是否收购装备（6.4）。
static func sell_enabled(shop_id: String) -> bool:
	return bool(entry(shop_id).get("sellEnabled", true))

## 货郎出售的商品列表（buyItems）。
static func buy_items(shop_id: String) -> Array:
	var arr = entry(shop_id).get("buyItems", [])
	return arr if arr is Array else []

## 购买单价；-1 = 该货郎不出售此物。
static func buy_price(shop_id: String, item_id: String) -> int:
	for it in buy_items(shop_id):
		if it is Dictionary and String(it.get("itemId", "")) == item_id:
			return int(it.get("price", -1))
	return -1

# ---- 物品构造 ----

## 依 id 构造一件待售物品实例（品类由配置表反查，构造统一收敛到 ItemFactory）。
## 药水 → potion；杂项 → misc；装备 → equip 实例；找不到则空字典（不静默凭空造物）。
static func make_item(item_id: String) -> Dictionary:
	return ItemFactory.make_any(item_id, 1)

## 商品简介（9.6 / 6.4 购买面板每项含介绍）。取配置 desc，缺省回退名称。
static func describe(item_id: String) -> String:
	for tbl in ["potions", "miscItems", "equipments"]:
		var e = DataLoader.get_entry(tbl, item_id)
		if e is Dictionary:
			var d := String(e.get("desc", ""))
			if not d.is_empty():
				return d
			return String(e.get("name", item_id))
	return item_id

# ---- 售价（6.2）----

## 物品模板基础价（baseValue）：装备 equipments.price / 药水 potions.price /
## 杂项 miscItems.price / 如意 runes.price。
static func base_value(item: Dictionary) -> int:
	var id := String(item.get("itemId", ""))
	var tpl = null
	match String(item.get("kind", "")):
		"equip":
			tpl = DataLoader.get_entry("equipments", id)
		"potion":
			tpl = DataLoader.get_entry("potions", id)
		"misc", "quest":
			tpl = DataLoader.get_entry("miscItems", id)
		"rune":
			tpl = DataLoader.get_entry("runes", id)
	if tpl is Dictionary:
		var price := int(tpl.get("price", 0))
		if String(item.get("kind", "")) == "equip":
			var multipliers: Dictionary = ItemFactory.rules().get("tierValueMultiplier", {})
			var tier_key := str(ItemFactory.tier_start_for_template(id))
			if not multipliers.has(tier_key):
				push_error("[Shop] %s 缺少第 %s 套售价倍率" % [id, tier_key])
				return 0
			price = int(round(float(price) * float(multipliers[tier_key])))
		return price
	return 0

## 实例品质：优先实例自带，缺失时回退模板（5.7）。
static func item_quality(item: Dictionary) -> String:
	var q := String(item.get("quality", ""))
	if q.is_empty():
		var tpl = DataLoader.get_entry("equipments", String(item.get("itemId", "")))
		if tpl is Dictionary:
			q = String(tpl.get("quality", "common"))
	return q if not q.is_empty() else "common"

## 6.2 售价公式：round(baseValue × qualityMult × (1 + star×0.08))。
static func sell_price(item: Dictionary) -> int:
	var base := base_value(item)
	if base <= 0:
		return 0
	var mult := float(QUALITY_SELL_MULT.get(item_quality(item), 1.0))
	var star := int(item.get("star", 0))
	return int(round(float(base) * mult * (1.0 + float(star) * STAR_SELL_BONUS)))

## 该物品能否出售给货郎（6.4：只收购装备）。
static func can_sell(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "equip"
