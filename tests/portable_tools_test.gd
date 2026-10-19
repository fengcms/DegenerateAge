extends Node
## M10-4 能力层（工程 45）：`useType: "panel"` 分发链 + `PanelRouter` + 任务等级门槛。
##
## 范围说明：Q-2 选「道具一拿到就要能全用」⇒ **C6Q13 发放任务整条挪到 M10-7**，
## 本批只交付能力层（道具数据已在表内，但还没有发放途径；M10-7 加任务即通）。
##
## 核心底线：
## 1. `panel` 道具**不消耗** —— 三件套是永久工具，不是卷轴。
## 2. `ready=false` 必须**明确失败**（有 reason、有 toast），绝不静默打开空壳面板。
## 3. `panelId` 与 `useType` **两个方向**都受校验，脏数据在启动期就死。

const TOOL_BOSS_TOKEN := "tool_boss_token"
const TOOL_SHOP := "tool_portable_shop"
const TOOL_CARTER := "tool_portable_carter"

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PortableToolsTest] " + label)

func _ready() -> void:
	_test_item_contract()
	_test_not_sellable()
	_test_router_opens_carter()
	_test_router_unready()
	_test_double_click_opens_without_consuming()
	_test_unready_toast_without_consuming()
	_test_level_gate()
	_test_level_gate_no_regression()
	_test_tooltip_mentions_panel()
	_test_save_roundtrip()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[PortableToolsTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[PortableToolsTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

## 用例 1：三件道具的数据契约（含「不许新增 bound 字段」）。
func _test_item_contract() -> void:
	var expected := {
		TOOL_BOSS_TOKEN: "boss_token",
		TOOL_SHOP: "shop",
		TOOL_CARTER: "carter",
	}
	for item_id in expected:
		var tpl: Variant = DataLoader.get_entry("miscItems", String(item_id))
		check(tpl is Dictionary, "%s 应存在于 miscItems" % item_id)
		if not tpl is Dictionary:
			continue
		var row: Dictionary = tpl
		check(String(row.get("useType", "")) == "panel", "%s 的 useType 应为 panel" % item_id)
		check(String(row.get("panelId", "")) == String(expected[item_id]),
			"%s 的 panelId 应为 %s，实际 %s" % [item_id, expected[item_id], row.get("panelId", "")])
		check(bool(row.get("questItem", false)), "%s 应标 questItem（不可出售）" % item_id)
		check(int(row.get("price", -1)) == 0, "%s 的 price 应为 0" % item_id)
		check(not row.has("bound"), "%s 不应新增 bound 字段（既不校验也不生效的假防护）" % item_id)
		check(not String(row.get("name", "")).is_empty(), "%s 缺少 name" % item_id)

## 用例 2：任务物品不可卖给货郎，单价恒 0。
func _test_not_sellable() -> void:
	for item_id in [TOOL_BOSS_TOKEN, TOOL_SHOP, TOOL_CARTER]:
		var item := ItemFactory.make_any(String(item_id))
		check(not item.is_empty(), "%s 应能经 ItemFactory 实例化" % item_id)
		check(String(item.get("kind", "")) == "misc", "%s 的 kind 应为 misc" % item_id)
		check(not Shop.can_sell(item), "%s 不得可售（questItem 必须拒收）" % item_id)
		check(Shop.sell_price(item) == 0, "%s 的出售价应为 0" % item_id)

## 用例 3：已点亮的面板（`carter` / `boss_token`）—— 打开成功且真的广播了面板请求。
func _test_router_opens_carter() -> void:
	check(PanelRouter.has("carter"), "carter 应登记在 PANELS")
	check(PanelRouter.is_ready("carter"), "carter 应 ready=true")
	var received: Array[String] = []
	var flags: Array[bool] = []
	var cb := func(npc_name: String, portable: bool) -> void:
		received.append(npc_name)
		flags.append(portable)
	EventBus.carter_panel_requested.connect(cb)
	var res: Dictionary = PanelRouter.open("carter")
	EventBus.carter_panel_requested.disconnect(cb)
	check(bool(res.get("ok", false)), "open(carter) 应成功，实际 reason=%s" % res.get("reason", ""))
	check(received.size() == 1, "carter 面板请求应广播 1 次，实际 %d" % received.size())
	if received.size() == 1:
		check(received[0] == "随身车夫", "面板标题应为「随身车夫」，实际「%s」" % received[0])
		# M10-7：第二参必须是 true —— 传 false 会让随身车夫列成同集群的当地线路。
		check(flags.size() == 1 and flags[0], "经面板路由打开时必须标记为随身模式（portable=true）")
	# M10-5：追猎令牌已随本批点亮 —— 同样必须是「真广播」而不是静默成功。
	check(PanelRouter.is_ready("boss_token"), "boss_token 随 M10-5 应 ready=true")
	var token_titles: Array[String] = []
	var token_cb := func(title: String) -> void: token_titles.append(title)
	EventBus.boss_token_panel_requested.connect(token_cb)
	var token_res: Dictionary = PanelRouter.open("boss_token")
	EventBus.boss_token_panel_requested.disconnect(token_cb)
	check(bool(token_res.get("ok", false)), "open(boss_token) 应成功，实际 reason=%s" % token_res.get("reason", ""))
	check(token_titles.size() == 1, "追猎令牌面板请求应广播 1 次，实际 %d" % token_titles.size())
	if token_titles.size() == 1:
		check(token_titles[0] == "追猎令牌", "面板标题应为「追猎令牌」，实际「%s」" % token_titles[0])

## 用例 4：未点亮 / 未登记必须显式失败，且原因可读。
## ⚠ M10-6 起 `shop` 也点亮了 —— **真实数据里再没有「未点亮」可供断言**
## （M10-5 时这条锚点由 `shop` 承接，这次没有下一个承接者）。
## 该分支的覆盖改由 `is_openable` 纯函数 + 合成 `{ready:false}` 承担，
## 放在 `portable_shop_test.gd` 的用例 11；这里改为断言「全部登记项都已点亮」+「未登记仍报错」。
## **断言一条没松，只换了锚点。**
func _test_router_unready() -> void:
	check(PanelRouter.PANELS.size() >= 3, "PANELS 应至少登记三件套，实际 %d" % PanelRouter.PANELS.size())
	for panel_id in PanelRouter.PANELS.keys():
		var entry: Variant = PanelRouter.PANELS[panel_id]
		check(PanelRouter.is_openable(entry), "%s 的登记项应可打开" % panel_id)
		check(PanelRouter.is_ready(String(panel_id)), "%s 应 ready=true" % panel_id)
	check(not PanelRouter.has("nonsense"), "未登记的 panelId 不应通过 has()")
	var bad: Dictionary = PanelRouter.open("nonsense")
	check(not bool(bad.get("ok", false)), "open(nonsense) 应失败")
	check(String(bad.get("reason", "")).contains("nonsense"),
		"未登记 panelId 的原因应带出该 id，实际「%s」" % bad.get("reason", ""))
	check(PanelRouter.title("nonsense").is_empty(), "未登记 panelId 的标题应为空串")

## 用例 5：双击随身车夫 —— 面板请求发出，且道具**不被消耗**。
func _test_double_click_opens_without_consuming() -> void:
	GameState.reset_to_defaults()
	GameState.inventory[0] = ItemFactory.make_any(TOOL_CARTER)
	var received: Array[String] = []
	var flags: Array[bool] = []
	var cb := func(npc_name: String, portable: bool) -> void:
		received.append(npc_name)
		flags.append(portable)
	EventBus.carter_panel_requested.connect(cb)
	var res: Dictionary = GameState.use_item(0)
	EventBus.carter_panel_requested.disconnect(cb)
	check(bool(res.get("ok", false)), "双击随身车夫应成功，实际 reason=%s" % res.get("reason", ""))
	check(received.size() == 1, "双击应广播 1 次面板请求，实际 %d" % received.size())
	check(flags.size() == 1 and flags[0], "双击道具打开必须是随身模式（portable=true）")
	var slot: Variant = GameState.inventory[0]
	check(slot is Dictionary, "使用后道具应仍在原格（永久工具不消耗）")
	if slot is Dictionary:
		check(int((slot as Dictionary).get("count", 0)) == 1,
			"使用后数量应仍为 1，实际 %d" % int((slot as Dictionary).get("count", 0)))
		check(String((slot as Dictionary).get("itemId", "")) == TOOL_CARTER, "使用后物品 id 不应变化")

## 用例 6：随身商队（M10-6 交付）—— 双击真广播商店请求，且道具**不被消耗**。
## 三件套里 `carter` / `boss_token` 已分别在用例 3、5 验过；这条补上最后一个，
## 并顺带断言「不再弹『该功能尚未开放』」——否则面板亮着、双击还报未开放就是双轨。
func _test_unready_toast_without_consuming() -> void:
	GameState.reset_to_defaults()
	GameState.inventory[0] = ItemFactory.make_any(TOOL_SHOP)
	var toasts: Array[String] = []
	var cb := func(text: String, _kind: String) -> void: toasts.append(text)
	var shops: Array[String] = []
	var shop_cb := func(shop_id: String) -> void: shops.append(shop_id)
	EventBus.toast_requested.connect(cb)
	EventBus.shop_open_requested.connect(shop_cb)
	var res: Dictionary = GameState.use_item(0)
	EventBus.toast_requested.disconnect(cb)
	EventBus.shop_open_requested.disconnect(shop_cb)
	check(bool(res.get("ok", false)), "双击随身商队应成功，实际 reason=%s" % String(res.get("reason", "")))
	check(shops.size() == 1, "随身商队应广播 1 次商店请求，实际 %d" % shops.size())
	if shops.size() == 1:
		check(shops[0] == Shop.PORTABLE_SHOP_ID,
			"广播的店铺 id 应为合成 id，实际「%s」" % shops[0])
	check(not toasts.has("该功能尚未开放"), "已点亮的面板不得再弹「该功能尚未开放」，实际 %s" % str(toasts))
	var slot: Variant = GameState.inventory[0]
	check(slot is Dictionary and int((slot as Dictionary).get("count", 0)) == 1,
		"永久工具使用后不得被消耗")

## 用例 7：等级门槛本身（59 拒 / 60 过 / 无字段不拦 / 0 视同无门槛）。
func _test_level_gate() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 59
	var blocked := Quest.level_gate_reason({"requiresLevel": 60})
	check(not blocked.is_empty(), "59 级接 60 级任务应被拦")
	check(blocked.contains("60"), "拦截原因应带出所需等级 60，实际「%s」" % blocked)
	GameState.player.level = 60
	check(Quest.level_gate_reason({"requiresLevel": 60}).is_empty(), "60 级应放行 60 级任务")
	check(Quest.level_gate_reason({}).is_empty(), "无 requiresLevel 的任务不得被拦")
	check(Quest.level_gate_reason({"requiresLevel": 0}).is_empty(), "requiresLevel=0 视同无门槛")
	check(not Quest.level_gate_reason({"requiresLevel": 61}).is_empty(), "60 级接 61 级任务应被拦")

## 用例 8：不误伤 —— 不带该字段的任务一律放行；带了的在 1 级必须被拦。
func _test_level_gate_no_regression() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 1
	for tpl in Quest.all():
		if not tpl is Dictionary:
			continue
		var row: Dictionary = tpl
		var qid := String(row.get("id", "?"))
		if row.has("requiresLevel"):
			check(not Quest.level_gate_reason(row, 1).is_empty(), "%s 带 requiresLevel，1 级应被拦" % qid)
			continue
		var reason := Quest.level_gate_reason(row, 1)
		check(reason.is_empty(), "%s 无 requiresLevel，1 级也不应被拦（实际「%s」）" % [qid, reason])

## 用例 9：说明文案 —— 面板类道具写「使用：打开<面板名>」，不能落到「暂未开放使用」。
func _test_tooltip_mentions_panel() -> void:
	var panel: Variant = preload("res://scripts/ui/inventory_panel.gd").new()
	var lines: Array = panel._non_equip_tooltip(ItemFactory.make_any(TOOL_CARTER))
	panel.free()
	var joined := "\n".join(PackedStringArray(lines))
	check(joined.contains("随身车夫"), "随身车夫的说明应含面板名「随身车夫」，实际「%s」" % joined)
	check(joined.contains("打开"), "说明应写清「打开」动作，实际「%s」" % joined)
	check(not joined.contains("暂未开放使用"),
		"面板类道具不得回退到「暂未开放使用」，实际「%s」" % joined)

## 用例 10：真文件往返 —— 三件 questItem 杂项写槽 3 再读回，不被剔除、数量不变。
func _test_save_roundtrip() -> void:
	GameState.reset_to_defaults()
	GameState.inventory[0] = ItemFactory.make_any(TOOL_BOSS_TOKEN)
	GameState.inventory[1] = ItemFactory.make_any(TOOL_SHOP)
	GameState.inventory[2] = ItemFactory.make_any(TOOL_CARTER)
	check(SaveManager._is_valid_save(SaveManager._collect()),
		"含三件套的存档应可读，拒绝原因：%s" % SaveManager._last_invalid_reason)
	check(SaveManager.save_slot(3, true), "含三件套的存档应能写盘")
	var res: Dictionary = SaveManager.read_slot(3)
	check(bool(res.get("ok", false)), "含三件套的存档应能读回：%s" % str(res.get("message", "")))
	var data: Dictionary = res.get("data", {})
	var found := {}
	for slot in (data.get("inventory", []) as Array):
		if slot is Dictionary:
			found[String((slot as Dictionary).get("itemId", ""))] = int((slot as Dictionary).get("count", 0))
	for item_id in [TOOL_BOSS_TOKEN, TOOL_SHOP, TOOL_CARTER]:
		check(found.has(String(item_id)), "读回后 %s 不应被剔除" % item_id)
		check(int(found.get(String(item_id), 0)) == 1, "读回后 %s 数量应为 1" % item_id)
	GameState.reset_to_defaults()
