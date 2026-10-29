extends Node
## M10-6 随身商店（工程 47 §4）：聚合货单 / 定价 / 排除规则 / 购买链路 / 面板点亮 / 说明文案。
##
## 底线：这份测试里最有钱的一条是**用例 2**。D-14 拍板的是「模板价 × 1.2 向上取整」，
## 少加一次、或多进一位都不会报错，只会让玩家每瓶药多付/少付几金 —— 所以价格表在这里
## 逐项写死比对；模板调价时这条会红，那是**要人来看一眼**，不是噪音。
##
## 第二条是**用例 1 的精确 14 种**：`>= 14` 挡不住「任务物混进来」这种错，
## 必须集合相等。

const PORTABLE := "portable_shop"

## 期望货单（D-14 + 产品 13 §5.2）：itemId → 随身价。
## 顺序＝表序（potions → miscItems → runes，表内 json 原序），用例 3 顺带锁住。
const EXPECTED := {
	"potion_hp_small": 24,
	"potion_mp_small": 24,
	"potion_hp_mid": 72,
	"potion_mp_mid": 72,
	"potion_hp_large": 180,
	"potion_mp_large": 180,
	"misc_firework": 36,
	"misc_random_ticket": 120,
	"misc_town_scroll": 96,
	"misc_revive_scroll": 144,
	"rune_iron": 360,
	"rune_jade": 960,
	"rune_gold": 2400,
	"rune_diamond": 72000,
}

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PortableShopTest] " + label)

func _ready() -> void:
	_test_exact_stock()
	_test_prices()
	_test_order_stable()
	_test_exclusions()
	_test_filters_on_synthetic_rows()
	_test_buy_price_agrees()
	_test_buy_real()
	_test_buy_insufficient_gold()
	_test_no_arbitrage()
	_test_normal_shops_unaffected()
	_test_router_opens_shop()
	_test_openable_and_all_ready()
	_test_describe_covers_runes()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[PortableShopTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[PortableShopTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 1) 货单集合必须精确相等 ----

func _test_exact_stock() -> void:
	var offers := Shop.aggregate_offers()
	check(offers.size() == EXPECTED.size(),
		"随身商队应恰好 %d 种，实际 %d" % [EXPECTED.size(), offers.size()])
	var got := {}
	for o in offers:
		if o is Dictionary:
			got[String((o as Dictionary).get("itemId", ""))] = int((o as Dictionary).get("price", -1))
	for id in EXPECTED:
		check(got.has(id), "货单缺少 %s" % id)
	for id in got:
		check(EXPECTED.has(id), "货单多出未登记项 %s（价 %d）" % [id, int(got[id])])

# ---- 2) 价格逐项匹配（D-14：模板价 × 1.2 向上取整）----

func _test_prices() -> void:
	var offers := Shop.aggregate_offers()
	for o in offers:
		if not (o is Dictionary):
			continue
		var id := String((o as Dictionary).get("itemId", ""))
		var price := int((o as Dictionary).get("price", -1))
		check(price == int(EXPECTED.get(id, -1)),
			"%s 的随身价应为 %d，实际 %d" % [id, int(EXPECTED.get(id, -1)), price])
	# 纯函数直测：非 10 的倍数才咬得住「该进位没进位」，5→6 / 1→2 是两个最小的坑位。
	check(Shop.portable_price(5) == 6, "portable_price(5) 应向上取整为 6，实际 %d" % Shop.portable_price(5))
	check(Shop.portable_price(1) == 2, "portable_price(1) 应向上取整为 2，实际 %d" % Shop.portable_price(1))
	check(Shop.portable_price(20) == 24, "portable_price(20) 应为 24，实际 %d" % Shop.portable_price(20))
	check(Shop.portable_price(0) == 0, "portable_price(0) 应为 0（无价物品不上架）")
	check(Shop.portable_price(-5) == 0, "portable_price(-5) 应为 0")

# ---- 3) 顺序稳定：同样调用两次结果逐条相等，首尾固定 ----

func _test_order_stable() -> void:
	var a := Shop.aggregate_offers()
	var b := Shop.aggregate_offers()
	check(a.size() == b.size(), "两次聚合结果数量应一致")
	for i in range(mini(a.size(), b.size())):
		check(String((a[i] as Dictionary).get("itemId", "")) == String((b[i] as Dictionary).get("itemId", "")),
			"第 %d 条两次调用不一致（顺序不稳定）" % i)
	if not a.is_empty():
		check(String((a[0] as Dictionary).get("itemId", "")) == "potion_hp_small",
			"首条应为 potion_hp_small（表序），实际 %s" % String((a[0] as Dictionary).get("itemId", "")))
		check(String((a[a.size() - 1] as Dictionary).get("itemId", "")) == "rune_diamond",
			"末条应为 rune_diamond（表序），实际 %s" % String((a[a.size() - 1] as Dictionary).get("itemId", "")))

# ---- 4) 三条排除规则各自独立：装备 / 任务物 / 用途为 quest 的收集物 ----

func _test_exclusions() -> void:
	var ids := {}
	for o in Shop.aggregate_offers():
		if o is Dictionary:
			ids[String((o as Dictionary).get("itemId", ""))] = String((o as Dictionary).get("kind", ""))
	for id in ids:
		check(String(ids[id]) != "equip", "%s 属装备，不得上架" % id)
	# 任务物点名（数据里真有这些 id，不是构造出来的）
	for quest_id in ["c6_item_q03", "tool_boss_token", "tool_portable_shop", "tool_portable_carter",
			"tool_portable_blacksmith"]:
		check(not ids.has(quest_id), "任务物 %s 不得上架" % quest_id)
	# 灵能碎片：price 16 > 0 且 questItem=false，只能靠 useType == quest 挡住
	check(not ids.has("spirit_shard"), "spirit_shard（useType=quest）不得上架，否则等于花钱跳过收集任务")

# ---- 4b) 三条过滤各自是否真的在生效 —— 必须靠**合成行**，现网数据分不开 ----
## 现网里 21 条任务物的 `price` 是 null、3 件工具是 0 ⇒ 单靠 `price > 0` 就把它们全挡了，
## 于是「questItem 过滤」和「price 过滤」看真实数据**各自都测不出来**（去掉任一条，14 种照样成立）。
## 必须注入「有价任务物 / 零价普通物 / 有价收集物 / 有价普通物」四行，才能一条条咬住；
## 最后那行是**对照**：证明前面三条不是「把什么都挡了」。
func _test_filters_on_synthetic_rows() -> void:
	var misc = DataLoader.get_table("miscItems")
	check(misc is Array, "miscItems 表应能读到")
	if not (misc is Array):
		return
	var table: Array = misc
	var original_size := table.size()
	table.append({"id": "test_priced_quest", "name": "合成任务物", "price": 10, "questItem": true})
	table.append({"id": "test_zero_price", "name": "合成零价物", "price": 0})
	table.append({"id": "test_quest_use", "name": "合成收集物", "price": 10, "useType": "quest"})
	table.append({"id": "test_ok_misc", "name": "合成普通物", "price": 10, "useType": "playAnimation"})
	var ids := {}
	for o in Shop.aggregate_offers():
		if o is Dictionary:
			ids[String((o as Dictionary).get("itemId", ""))] = true
	table.resize(original_size)   # 立刻还原，后面的用例仍跑真实数据
	check(not ids.has("test_priced_quest"), "有价任务物（questItem=true）不得上架")
	check(not ids.has("test_zero_price"), "零价物品不得上架（否则会以 0 金白送）")
	check(not ids.has("test_quest_use"), "useType=quest 的收集物不得上架")
	check(ids.has("test_ok_misc"), "合成的普通有价杂项应正常上架 —— 否则上面三条等于「全挡」")
	check(Shop.aggregate_offers().size() == EXPECTED.size(), "注入还原后应回到 14 种")

# ---- 5) buy_price 与货单同源；未知 id 返回 -1 ----

func _test_buy_price_agrees() -> void:
	for id in EXPECTED:
		var p := Shop.buy_price(PORTABLE, String(id))
		check(p == int(EXPECTED[id]),
			"buy_price(%s) 应为 %d，实际 %d" % [id, int(EXPECTED[id]), p])
	check(Shop.buy_price(PORTABLE, "potion_unknown") == -1, "未知商品应返回 -1（不可购买）")
	check(Shop.buy_price(PORTABLE, "c6_equip_sword01") == -1, "装备不得可购买")
	check(Shop.sell_enabled(PORTABLE), "随身商队必须收购（野外就地变现是 R-18 的前提）")

# ---- 6) 真买一件：扣对钱、东西真进包 ----

func _test_buy_real() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 10000
	var before := _count_of("rune_gold")
	var res := GameState.shop_buy(PORTABLE, "rune_gold")
	check(bool(res.get("ok", false)), "买金如意应成功，实际 reason=%s" % String(res.get("reason", "")))
	check(GameState.gold == 10000 - 2400, "应扣 2400 金（聚合价，不是模板价 2000），实际余额 %d" % GameState.gold)
	check(_count_of("rune_gold") == before + 1, "金如意应入包 1 个")

# ---- 7) 金币不足：失败且金币与背包都不动 ----

func _test_buy_insufficient_gold() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 100
	var used_before := GameState.inventory_used()
	var res := GameState.shop_buy(PORTABLE, "rune_diamond")
	check(not bool(res.get("ok", false)), "金币不足时买钻石如意应失败")
	check(GameState.gold == 100, "失败不得扣金，实际余额 %d" % GameState.gold)
	check(GameState.inventory_used() == used_before, "失败不得入包，实际 %d→%d" % [used_before, GameState.inventory_used()])

# ---- 8) 无套利：随身买 24、货郎回收只给 12 ----

func _test_no_arbitrage() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000
	var res := GameState.shop_buy(PORTABLE, "potion_hp_small")
	check(bool(res.get("ok", false)), "买小红应成功")
	check(GameState.gold == 1000 - 24, "小红随身价应为 24，实际余额 %d" % GameState.gold)
	var refund := Shop.sell_price({"kind": "potion", "itemId": "potion_hp_small", "count": 1})
	check(refund == 12, "小红回收应为 12（20 × 0.6），实际 %d" % refund)
	check(refund < 24, "回收价必须低于随身价，否则可无限套利")

# ---- 9) 普通货郎不受影响：shop_id 分岔只对合成 id 生效 ----

func _test_normal_shops_unaffected() -> void:
	var shops = DataLoader.get_table("shops")
	check(shops is Array and (shops as Array).size() > 0, "shops.json 应能读到")
	var n := 0
	for s in (shops as Array):
		if not (s is Dictionary):
			continue
		var row: Dictionary = s
		var npc_id := String(row.get("npcId", ""))
		check(not Shop.is_portable(npc_id), "普通货郎 %s 不得被判成随身商队" % npc_id)
		var raw_items: Array = []
		raw_items.assign(row.get("buyItems", []))
		check(Shop.buy_items(npc_id).size() == raw_items.size(),
			"%s 的商品列表应仍来自 shops.json" % npc_id)
		n += 1
	check(n >= 12, "应遍历到至少 12 家货郎，实际 %d" % n)
	check(Shop.is_portable(PORTABLE), "合成 id 本身应为随身商队")

# ---- 10) 面板链路：open("shop") 必须真广播，不能静默成功 ----

func _test_router_opens_shop() -> void:
	check(PanelRouter.has("shop"), "shop 应登记在 PANELS")
	check(PanelRouter.is_ready("shop"), "shop 随 M10-6 应 ready=true")
	var received: Array[String] = []
	var cb := func(shop_id: String) -> void: received.append(shop_id)
	EventBus.shop_open_requested.connect(cb)
	var res: Dictionary = PanelRouter.open("shop")
	EventBus.shop_open_requested.disconnect(cb)
	check(bool(res.get("ok", false)), "open(shop) 应成功，实际 reason=%s" % String(res.get("reason", "")))
	check(received.size() == 1, "商店面板请求应广播 1 次，实际 %d" % received.size())
	if received.size() == 1:
		check(received[0] == Shop.PORTABLE_SHOP_ID,
			"广播的店铺 id 应为合成 id，实际「%s」" % received[0])

# ---- 11) 未点亮分支：三个面板全亮后没有真实数据可用了，只能靠纯函数 + 合成数据 ----
## 「全部登记项已点亮」的断言在 `portable_tools_test.gd` 用例 4；这里只锁判定语义本身。

func _test_openable_and_all_ready() -> void:
	check(not PanelRouter.is_openable({"ready": false, "title": "x"}), "{ready:false} 应判为不可打开")
	check(PanelRouter.is_openable({"ready": true}), "{ready:true} 应判为可打开")
	check(not PanelRouter.is_openable({}), "缺 ready 字段应按未点亮处理")
	check(not PanelRouter.is_openable(null), "null 应按未点亮处理")
	check(not PanelRouter.is_openable("shop"), "非字典类型应按未点亮处理")

# ---- 12) 说明文案：如意此前会退化成裸 id（F-1）----

func _test_describe_covers_runes() -> void:
	var desc := Shop.describe("rune_iron")
	check(not desc.is_empty(), "rune_iron 的说明不应为空")
	check(desc != "rune_iron", "rune_iron 的说明不应退化成裸 id")
	for id in EXPECTED:
		check(not Shop.describe(String(id)).is_empty(), "%s 的说明不应为空" % id)
	# 🔴 撞号回归：`ui.shop_panel.p020` 早已被「该物品已不在背包」占用（JSON 里后者胜出、
	# 不报错也不警告）。新增说明文案复用同号会**静默被覆盖** —— 这条断言就是防它。
	const HINT := "随身商队按模板价上浮 20% 出售。"
	check(Localization.tr_key("ui.shop_panel.p031") == HINT,
		"p031 应解析出说明正文（撞号会静默覆盖），实际「%s」" % Localization.tr_key("ui.shop_panel.p031"))

# ---- 工具 ----

## 背包里某 itemId 的总数量。
func _count_of(item_id: String) -> int:
	var n := 0
	for it in GameState.inventory:
		if it is Dictionary and String((it as Dictionary).get("itemId", "")) == item_id:
			n += int((it as Dictionary).get("count", 1))
	return n
