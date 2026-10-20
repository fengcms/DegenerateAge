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
const QUALITY_ORDER: Array = ItemUtil.QUALITIES   # B-P3-6：品质枚举唯一来源在 ItemUtil，此处仅引用

## 6.4（2026-10-17 修订，工程 39）：货郎收购全部掉落品类，任务物品除外。
## 白名单之外的 `quest` / `coin` / `mount` 一律不收（任务袋独立 / 货币 / 拾取即解锁）。
const SELLABLE_KINDS := ["equip", "potion", "misc", "rune"]

## 非装备回收比例（工程 39 D-1 = 0.6 拍板）。装备保持 1.0 —— 现有售价断言数值不变。
const SELL_RATIO_NON_EQUIP := 0.6

## M10-6（D-14）：随身商队的**合成店铺 id**。
## 刻意不写进 `data/shops.json`：那里每条都必须被某个 NPC 的 `shopId` 引用，
## 凭空多一条会被启动校验判成孤立店铺；且它的货单与价格全部由模板表推导，不需要数据副本。
## 副作用是 `entry()` 对它返回空字典 ⇒ `sell_enabled()` 走默认 true，正是「就地变现」所需。
const PORTABLE_SHOP_ID := "portable_shop"

## 随身商店加价（D-14：模板价 × 1.2），用整数分子分母表达，避免浮点。
const PORTABLE_PRICE_NUM := 6
const PORTABLE_PRICE_DEN := 5

## 一键移入的筛选语义**永远是装备**（工程 39 G4）：与收购范围解耦。
## 若沿用 `can_sell` 判定，放行药水后「< Lv5 且 ≤ 普通」会把保命药整批塞进托盘。
static func matches_low_gear(item: Dictionary, level_limit: int, max_quality: String) -> bool:
	if String(item.get("kind", "")) != "equip" or not can_sell(item) or level_limit < 1:
		return false
	# 工程 77：破损件不进一键出售（修好还是好装备，卖了等于白扔）。
	if Durability.is_broken(item):
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

## 货郎是否收购物品（6.4）。
static func sell_enabled(shop_id: String) -> bool:
	return bool(entry(shop_id).get("sellEnabled", true))

## 是否为随身商队（M10-6 的合成店铺）。普通货郎一律 false。
## 供 UI 层决定标题文案 —— `Shop` 本身保持零本地化依赖，本地化留在面板里。
static func is_portable(shop_id: String) -> bool:
	return shop_id == PORTABLE_SHOP_ID

## 随身价 = ceil(模板价 × 1.2)，**纯整数运算**。
## 🔴 不要改写成 `ceil(base * 1.2)`：① `int / int` 会触发 `INTEGER_DIVISION` 警告，
## 而本项目 `warnings_as_errors` 开着，直接编译失败；② 浮点 1.2 实际存的是 1.1999999…，
## 某些基数乘出来会跨过整数边界多进 1。整数式对任意 base 精确，且能被测试直接传值验证。
@warning_ignore("integer_division")
static func portable_price(base: int) -> int:
	if base <= 0:
		return 0
	return (base * PORTABLE_PRICE_NUM + (PORTABLE_PRICE_DEN - 1)) / PORTABLE_PRICE_DEN

## 随身商队的全部货单（D-14：全部在售品类、模板价 × 1.2、不含装备）。
## 返回 `[{itemId, kind, price, count}]`，`price` 已含加价。
##
## 🔑 取货口径＝**模板三表全品类**。产品 13 §5.2 原文写「12 家店 `buyItems` 并集」，
## 但实测并集只有 9 种 —— 12 家店都不卖 `misc_firework` 与 4 种如意，而 §5.2 的清单
## 与验收都要求它们上架（详见工程 47 §0 C-1）。按模板取货还能让以后新增药水/如意自动上架。
## 过滤：有价 + 非任务物 + 用途不是 quest（挡 `spirit_shard` —— 上架等于花钱跳过收集）。
## 顺序＝表序（potions → miscItems → runes，表内保持 json 原序），结果稳定可预期。
## 零副作用：不读写 GameState、不缓存。
static func aggregate_offers() -> Array:
	var sources: Array = [
		{"table": "potions", "kind": "potion"},
		{"table": "miscItems", "kind": "misc"},
		{"table": "runes", "kind": "rune"},
	]
	var offers: Array = []
	for src in sources:
		var rows = DataLoader.get_table(String((src as Dictionary).get("table", "")))
		if not (rows is Array):
			continue
		for row in (rows as Array):
			if not (row is Dictionary):
				continue
			var tpl: Dictionary = row
			var base := int(tpl.get("price", 0))
			if base <= 0:
				continue
			if bool(tpl.get("questItem", false)):
				continue
			if String(tpl.get("useType", "")) == "quest":
				continue
			offers.append({
				"itemId": String(tpl.get("id", "")),
				"kind": String((src as Dictionary).get("kind", "")),
				"price": portable_price(base),
				"count": 1,
			})
	return offers

## 货郎出售的商品列表（buyItems）；随身商队走聚合货单（M10-6）。
## 分岔**只对合成 id 生效**，普通货郎行为逐字不变。
static func buy_items(shop_id: String) -> Array:
	if is_portable(shop_id):
		return aggregate_offers()
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
## M10-6 补 `runes`：此前缺这张表，4 种如意的说明会退化成裸 id（工程 47 §1 F-1）。
static func describe(item_id: String) -> String:
	for tbl in ["potions", "miscItems", "runes", "equipments"]:
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
	var tpl := _template(item)
	if not tpl.is_empty():
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

## 按品类取模板（找不到返回空字典，调用方不必再做类型判断）。
static func _template(item: Dictionary) -> Dictionary:
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
	return tpl if tpl is Dictionary else {}

## 任务物品标记（工程 39 D-4）：数据侧 `questItem: true` 才是唯一判据。
## 不复用 `useType == "quest"` —— 灵能碎片同属 quest 用途但设计上可售（会入包）。
static func is_quest_item(item: Dictionary) -> bool:
	return bool(_template(item).get("questItem", false))

## 实例品质：优先实例自带，缺失时回退模板（5.7）。模板字段名为 `defaultQuality`（B-P3-3）。
static func item_quality(item: Dictionary) -> String:
	var q := String(item.get("quality", ""))
	if q.is_empty():
		var tpl = DataLoader.get_entry("equipments", String(item.get("itemId", "")))
		if tpl is Dictionary:
			q = String(tpl.get("defaultQuality", "common"))
	return q if not q.is_empty() else "common"

## 6.2 售价公式：round(baseValue × qualityMult × (1 + star×0.08))，非装备再 × 回收比例。
## 工程 39 G2：**整叠计价** —— 此前忽略 `count`，一叠 99 瓶只算 1 瓶钱（装备 count 恒 1，故未暴露）。
## 先取整单价再乘数量，保证「单价 × 数量 = 总价」可被玩家手算复核。
## M10-8 D-15：**装备**额外乘等级轻缩放 `×(1 + 0.02 × (L − 60))`（参数见 `endgame.json` 的
## `resale`）。只改这一个调用点，货郎 / 背包一键卖出 / 随身商店自动统一 —— 否则同一件装备
## 在两处卖不同价。非装备不缩放（药水没有装备等级）。
static func sell_price(item: Dictionary) -> int:
	var base := base_value(item)
	if base <= 0:
		return 0
	var mult := float(QUALITY_SELL_MULT.get(item_quality(item), 1.0))
	var star := int(item.get("star", 0))
	var unit := float(base) * mult * (1.0 + float(star) * STAR_SELL_BONUS)
	if String(item.get("kind", "")) != "equip":
		unit *= SELL_RATIO_NON_EQUIP
	else:
		unit *= Reforge.resale_scale(Equipment.level_req(item))
	var count := maxi(1, int(item.get("count", 1)))
	return int(round(unit)) * count

## 该物品能否出售给货郎（6.4 修订：装备 / 药水 / 杂项 / 如意；任务物品与无价物品不收）。
## `base_value() <= 0` 一并拒绝 —— 宁可不收，也不静默卖 0 金币。
static func can_sell(item: Dictionary) -> bool:
	if not SELLABLE_KINDS.has(String(item.get("kind", ""))):
		return false
	if bool(item.get("favorite", false)):
		return false
	if is_quest_item(item):
		return false
	return base_value(item) > 0
