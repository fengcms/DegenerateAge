extends Node
## 工程 108 随身铁匠：道具 / 路由器 / 面板双模式 / 任务门槛 / 补领 / **费率同源**。
##
## 十条断言里，最值钱的是 5 与 9/10：
## 5. **回城模式零回归** —— `set_open` 改成按 `_portable` 分支之后，最容易出的错不是
##    「随身模式不对」，而是「回城模式被改坏了」（问候卡不出来、底部多一个空洞）。
##    面板是常驻节点，`visible` 不会自己回到 true ⇒ 这条必须**连开两次**才测得出继承状态。
## 9/10. **显示价 == 实扣** —— 本项目的费用是「面板显示」与「`GameState` 扣费」两处独立算的。
##    只改一处 = 按钮写一个数、实扣另一个数；`ceil` 与 `round` 混用 = 差 1 金。
##    这两条是「随身 +20%」这次改动里唯一守得住它的机制。

const TOOL := "tool_portable_blacksmith"
const QUEST := "C7S01"
const PANEL := "blacksmith"

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PortableBlacksmithTest] " + label)

func _ready() -> void:
	_test_item_contract()
	_test_router_registered()
	_test_double_click_opens_without_consuming()
	_test_portable_panel_skips_greeting()
	_test_local_mode_no_regression()
	_test_quest_contract()
	_test_not_droppable_and_not_on_sale()
	_test_reclaim_covers_fourth_tool()
	_test_upgrade_and_reforge_price_matches_charge()
	_test_repair_price_matches_charge()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[PortableBlacksmithTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[PortableBlacksmithTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 用例 1：道具契约 ----

## 与三件套同构：`panel` + `panelId` + `questItem` + 零价，且**不许新增 `bound`**。
## `bound` 在全库 `.gd` 里零命中，写进 JSON 既不校验也不生效 —— 它曾经是一条假防护。
func _test_item_contract() -> void:
	var tpl: Variant = DataLoader.get_entry("miscItems", TOOL)
	check(tpl is Dictionary, "%s 应存在于 miscItems" % TOOL)
	if not tpl is Dictionary:
		return
	var row: Dictionary = tpl
	check(String(row.get("useType", "")) == "panel", "useType 应为 panel")
	check(String(row.get("panelId", "")) == PANEL, "panelId 应为 %s，实际 %s" % [PANEL, row.get("panelId", "")])
	check(bool(row.get("questItem", false)), "应标 questItem（货郎拒收）")
	check(int(row.get("price", -1)) == 0, "price 应为 0")
	check(not row.has("bound"), "不应新增 bound 字段（既不校验也不生效的假防护）")
	check(not String(row.get("name", "")).is_empty(), "缺少 name")
	# 说明文案必须把「随身更贵」写出来：玩家看不到加价，就会把加价当成 bug。
	var desc := String(row.get("desc", ""))
	check(desc.contains("1.5") and desc.contains("两成"),
		"desc 应写明修理 1.5 倍与其余加价两成，实际「%s」" % desc)

# ---- 用例 2：路由器登记 ----

func _test_router_registered() -> void:
	check(PanelRouter.has(PANEL), "blacksmith 应登记在 PANELS")
	check(PanelRouter.is_ready(PANEL), "blacksmith 应 ready=true")
	check(PanelRouter.title(PANEL) == "随身铁匠",
		"标题应解析为「随身铁匠」，实际「%s」" % PanelRouter.title(PANEL))

# ---- 用例 3：双击广播且不消耗 ----

func _test_double_click_opens_without_consuming() -> void:
	GameState.reset_to_defaults()
	GameState.inventory[0] = ItemFactory.make_any(TOOL)
	var names: Array[String] = []
	var flags: Array[bool] = []
	var cb := func(npc_name: String, _greeting: String, portable: bool) -> void:
		names.append(npc_name)
		flags.append(portable)
	EventBus.blacksmith_panel_requested.connect(cb)
	var res: Dictionary = GameState.use_item(0)
	EventBus.blacksmith_panel_requested.disconnect(cb)
	check(bool(res.get("ok", false)), "双击随身铁匠应成功，实际 reason=%s" % res.get("reason", ""))
	check(names.size() == 1, "应广播 1 次面板请求，实际 %d" % names.size())
	check(flags.size() == 1 and flags[0], "经 Router 打开必须标记 portable=true")
	check(names.size() == 1 and names[0] == "", "随身模式不得传 NPC 名（标题由面板自己取）")
	var slot: Variant = GameState.inventory[0]
	check(slot is Dictionary, "使用后道具应仍在原格（永久工具不消耗）")
	if slot is Dictionary:
		check(String((slot as Dictionary).get("itemId", "")) == TOOL, "留在原格的应是该道具本身")
		check(int((slot as Dictionary).get("count", 0)) == 1, "数量应仍为 1，实际 %d"
			% int((slot as Dictionary).get("count", 0)))

# ---- 用例 4 / 5：面板双模式 ----

## 随身模式：跳过问候卡直接进服务菜单，且「离开」隐藏。
## ⚠ 只断「面板打开了」会被「打开了问候卡」骗过 —— 必须分别断两张卡。
func _test_portable_panel_skips_greeting() -> void:
	var dialogue := preload("res://scenes/ui/BlacksmithPanel.tscn").instantiate()
	add_child(dialogue)
	EventBus.blacksmith_panel_requested.emit("", "", true)
	check(dialogue._portable, "面板应进入随身模式")
	check(dialogue._service_card.visible, "随身模式应直接显示服务卡")
	check(not dialogue._greeting_card.visible, "随身模式不应显示问候卡")
	check(not dialogue._continue.visible, "随身模式不应显示「继续」")
	check(not dialogue._leave.visible, "随身模式应隐藏「离开」（无对话可离开，右上角 × 足够）")
	check(dialogue._upgrade.visible and dialogue._reforge.visible,
		"服务按钮必须全部可见 —— 「复用全部功能」是这个需求的原文")
	check(dialogue._title.text.contains("随身铁匠"),
		"标题应为「随身铁匠」，实际「%s」" % dialogue._title.text)
	dialogue.queue_free()

## 回城模式零回归 —— 而且必须**在随身模式之后**开，才能测出状态继承。
## 🔴 面板是常驻节点：`_leave.visible` 若只在随身分支里设 false、回城分支不设回 true，
##    回城铁匠的底部就会永久缺一个「离开」按钮，而任何「随身模式」断言都是绿的。
func _test_local_mode_no_regression() -> void:
	var dialogue := preload("res://scenes/ui/BlacksmithPanel.tscn").instantiate()
	add_child(dialogue)
	# 先用随身模式把它弄成「服务卡 + 离开隐藏」的状态。
	EventBus.blacksmith_panel_requested.emit("", "", true)
	# 再用当地模式打开同一个节点。
	EventBus.blacksmith_panel_requested.emit("铁匠", "炉火还旺。", false)
	check(not dialogue._portable, "第二次打开应回到当地模式")
	check(dialogue._greeting_card.visible, "当地模式应显示问候卡")
	check(dialogue._service_card.visible == false, "当地模式初态不应直接显示服务卡")
	check(dialogue._continue.visible, "当地模式应显示「继续」")
	check(dialogue._leave.visible, "当地模式的「离开」必须回到可见（继承 bug 就在这里）")
	check(dialogue._greeting.text.contains("炉火还旺"),
		"问候语应来自 NPC 配置，实际「%s」" % dialogue._greeting.text)
	check(dialogue._title.text.contains("铁匠") and not dialogue._title.text.contains("随身"),
		"当地模式标题应为 NPC 名而不是「随身铁匠」，实际「%s」" % dialogue._title.text)
	dialogue.queue_free()

# ---- 用例 6：任务契约 ----

## `requiresLevel` 79 拦 / 80 过；`prev` 挂 C6S07；`unlocks` 必须是**数组**。
## 🔴 写成单数 `unlock`（Q005 就是那种写法）会让存档校验把档判坏 —— 08 §5.31 的坑。
func _test_quest_contract() -> void:
	var tpl: Variant = Quest.template(QUEST)
	check(tpl is Dictionary and not (tpl as Dictionary).is_empty(), "%s 应存在于 quests" % QUEST)
	if not tpl is Dictionary:
		return
	var row: Dictionary = tpl
	check(int(row.get("requiresLevel", 0)) == 80, "requiresLevel 应为 80，实际 %d" % int(row.get("requiresLevel", 0)))
	check(String(row.get("prev", "")) == "C6S07", "前置应为 C6S07（先拿到三件套），实际「%s」" % row.get("prev", ""))
	check(String(row.get("giver", "")) == "camp_smith", "发布人应为 camp_smith")
	check(String(row.get("turnIn", "")) == "camp_smith", "交付人应为 camp_smith")
	check(not Quest.level_gate_reason(row, 79).is_empty(), "79 级应被拦")
	check(Quest.level_gate_reason(row, 80).is_empty(), "80 级应放行")
	var objective: Dictionary = row.get("objective", {})
	check(String(objective.get("kind", "")) == "kill", "目标类型应为 kill")
	check(String(objective.get("targetId", "")) == "c6_normal01", "目标应为 c6_normal01")
	check(int(objective.get("count", 0)) > 0, "击杀数应 > 0")
	var reward: Dictionary = row.get("reward", {})
	# 🔴 必须先判「字段真实存在」再看类型：`reward.get("unlocks", [])` 在字段被删/改名时
	#    返回默认 `[]`（同样是 Array），会让「必须是数组」这条恒绿 —— N-5 首轮就是这么漏的。
	var unlocks: Variant = reward.get("unlocks", [])
	check(reward.has("unlocks") and unlocks is Array, "reward.unlocks 必须是数组（字段须真实存在，写成单数 unlock 会让读档判档坏）")
	check(not reward.has("unlock"), "不得出现单数 unlock 字段")
	if unlocks is Array:
		check((unlocks as Array).has(TOOL), "unlocks 应含 %s" % TOOL)
	var items: Array = reward.get("items", [])
	var found := false
	for spec in items:
		if spec is Dictionary and String((spec as Dictionary).get("itemId", "")) == TOOL:
			found = true
	check(found, "奖励里应真的发一件该道具（只写 unlocks 不写 items = 领了没有）")
	# 发布点必须真的在营地里，且该 NPC 有 npcId —— 否则任务面板认不出他是发布人。
	check(MapService.map_for_npc("camp_smith") == "camp", "camp_smith 应解析到 camp，实际「%s」"
		% MapService.map_for_npc("camp_smith"))

# ---- 用例 7：两条既有防线对新道具生效 ----

func _test_not_droppable_and_not_on_sale() -> void:
	var item := ItemFactory.make_any(TOOL)
	check(not item.is_empty(), "应能经 ItemFactory 实例化")
	var drop: Dictionary = GameState.can_drop_item(item)
	check(not bool(drop.get("ok", true)), "随身工具不得丢到地面")
	check(String(drop.get("reason", "")) == "tool",
		"拒绝原因应为 tool（排在 questItem 之前），实际「%s」" % drop.get("reason", ""))
	check(not Shop.can_sell(item), "货郎不得收购")
	check(Shop.sell_price(item) == 0, "出售价应为 0")
	var on_sale := false
	for offer in Shop.aggregate_offers():
		if offer is Dictionary and String((offer as Dictionary).get("itemId", "")) == TOOL:
			on_sale = true
	check(not on_sale, "随身商队不得上架任务物（否则等于用钱买功能）")

# ---- 用例 8：补领覆盖第四件 ----

## 数据驱动的判据是否真的覆盖到第四件 —— 这条不是「再测一遍 panel_tool_ids()」，
## 而是端到端：只解锁这一件、两处都没有 ⇒ 补 1 件；已有 ⇒ 不补。
func _test_reclaim_covers_fourth_tool() -> void:
	check(ToolReclaim.panel_tool_ids().has(TOOL), "panel_tool_ids() 应包含第四件")
	var inv := Inventory.create(40)
	var wh := Inventory.create(40)
	var unlocks := {TOOL: true}
	var missing := ToolReclaim.missing_tools(unlocks, inv, wh)
	check(missing.size() == 1 and String(missing[0]) == TOOL,
		"应判 1 件缺失且是 %s，实际 %s" % [TOOL, str(missing)])
	var result := ToolReclaim.reclaim(unlocks, inv, wh)
	check((result.get("given", []) as Array).size() == 1, "应补发 1 件")
	check(ToolReclaim.holds(inv, TOOL), "补发的道具应真的在背包里")
	# 已有则不补（防重复刷）。
	var again := ToolReclaim.reclaim(unlocks, inv, wh)
	check((again.get("given", []) as Array).is_empty(), "已有该道具时不得再补")

# ---- 用例 9：升星 / 重铸 —— 显示价 == 实扣 ----

## 🔴 四个计算点一次覆盖：升星显示 / 升星扣费 / 重铸显示 / 重铸扣费。
## 「显示价」直接从面板的价签文本里抓数字，而不是重算一遍公式 —— 重算等于把被测对象
## 复制一份再和它自己比，那样两边一起写错也是绿的。
func _test_upgrade_and_reforge_price_matches_charge() -> void:
	var up := preload("res://scenes/ui/UpgradePanel.tscn").instantiate()
	add_child(up)
	# --- 升星：挑一个 base 不被 5 整除的星级 ---
	# 1.2 = 6/5 ⇒ base 被 5 整除时 ×1.2 是整数，`ceil` 与 `round` 同值，
	# 那种情况下**取整口径不一致是测不出来的**，必须避开。
	var star := -1
	var base_cost := 0
	for candidate in range(Upgrade.max_star()):
		var c := Upgrade.cost(candidate)
		if c > 0 and c % 5 != 0:
			star = candidate
			base_cost = c
			break
	check(star >= 0, "应能找到 base 不被 5 整除的星级（否则本用例测不出 ceil/round 差异）")
	if star < 0:
		up.queue_free()
		return
	_game_with_one_equip(star)
	up._on_requested(false)
	var local_price := _price_in(up._price.text, "费用")
	up._on_requested(true)
	var portable_price := _price_in(up._price.text, "费用")
	check(local_price == base_cost, "回城显示价应为原价 %d，实际 %d" % [base_cost, local_price])
	check(portable_price == int(ceil(float(base_cost) * ServiceFee.PORTABLE_RATE)),
		"随身显示价应为 ceil(%d × %.1f) = %d，实际 %d"
		% [base_cost, ServiceFee.PORTABLE_RATE,
			int(ceil(float(base_cost) * ServiceFee.PORTABLE_RATE)), portable_price])
	var before := GameState.gold
	up._on_upgrade()
	var spent := before - GameState.gold
	check(spent == portable_price,
		"随身升星**实扣 %d ≠ 按钮显示 %d** —— 显示与扣费不同源，玩家对账立刻发现" % [spent, portable_price])
	up.queue_free()

	# --- 重铸：必须**锁一条词条**，否则测不出取整差异 ---
	# 🔴 不锁词条时 base = 49125（level_req 51，endgame.json 口径），被 5 整除 ⇒ ×1.2 是整数，
	#    ceil 与 round/截断全部同值 —— N-7 首轮用 round 注入实测「全部通过」，是**假绿**；
	#    锁 1 条后 base = 73688，×1.2 = 88425.6 才非整数，截断(88425) 与进位(88426)才会分家。
	var rf := preload("res://scenes/ui/ReforgePanel.tscn").instantiate()
	add_child(rf)
	GameState.reset_to_defaults()
	GameState.gold = 10000000
	var rng := RandomNumberGenerator.new()
	rng.seed = 108
	var rf_item := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "epic", rng)
	GameState.inventory[0] = rf_item
	rf._on_requested(false)
	# 从装备自身取一条真实词条（不写死 stat 名 —— 数据变了这条要能自适应）。
	var lock_stat := ""
	for key in ["affixes", "pctAttrs"]:
		var arr: Variant = rf_item.get(String(key), [])
		if arr is Array:
			for e in arr as Array:
				if e is Dictionary and not String((e as Dictionary).get("stat", "")).is_empty():
					lock_stat = String((e as Dictionary).get("stat", ""))
					break
		if not lock_stat.is_empty():
			break
	check(not lock_stat.is_empty(), "重铸样本应有至少一条可锁词条（否则本用例测不出取整差异）")
	if lock_stat.is_empty():
		rf.queue_free()
		return
	# 必须在 `_on_requested` **之后**调 toggle_lock：面板打开时才会设好 `_locked_owner`，
	# 提前锁会被 `_refresh_details` 的 owner 切换逻辑清掉（reforge_panel.gd 第 399 行）。
	rf.toggle_lock(lock_stat)
	check(rf._locked.size() == 1, "应锁住 1 条词条，实际 %d" % rf._locked.size())
	var rf_base := Reforge.cost(Equipment.level_req(rf_item), 1)
	var rf_local := _price_in(rf._price.text, "重铸费用")
	check(rf_local == rf_base, "回城重铸价应为锁 1 条的原价 %d，实际 %d" % [rf_base, rf_local])
	# 切随身：`set_open` 不清锁（清锁只在关闭时，reforge_panel.gd 第 105 行），owner 不变 ⇒ 锁定保留。
	rf._on_requested(true)
	check(rf._locked.size() == 1, "切随身模式后 1 条锁定应保留")
	var rf_portable := _price_in(rf._price.text, "重铸费用")
	check(rf_portable == int(ceil(float(rf_base) * ServiceFee.PORTABLE_RATE)),
		"随身重铸显示价应为 ceil(%d × 1.2) = %d，实际 %d"
		% [rf_base, int(ceil(float(rf_base) * ServiceFee.PORTABLE_RATE)), rf_portable])
	var before_rf := GameState.gold
	rf._on_reforge()
	var spent_rf := before_rf - GameState.gold
	check(spent_rf == rf_portable,
		"随身重铸**实扣 %d ≠ 按钮显示 %d**" % [spent_rf, rf_portable])
	rf.queue_free()

## 造一个只有一件背包装备、金币充足的干净局面。
func _game_with_one_equip(star: int) -> void:
	GameState.reset_to_defaults()
	GameState.gold = 10000000
	var rng := RandomNumberGenerator.new()
	rng.seed = 1081
	var item := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "epic", rng)
	item["star"] = star
	GameState.inventory[0] = item

## 从价签文本里抓「<token><数字><unit>」的数字；抓不到返回 -1（会让断言红，不静默）。
## `unit` 必须由调用方给：升星/重铸写「金币」，而修理按钮写的是「金）」——
## 用一个正则兜两种文案的后果是「明明显示得出来却解析成 -1」，本用例第一次跑就是这么红的。
func _price_in(text: String, token: String, unit: String = "金币") -> int:
	var re := RegEx.new()
	re.compile(token + "\\s*(\\d+)\\s*" + unit)
	var found := re.search(text)
	if found == null:
		return -1
	return int(found.get_string(1))

# ---- 用例 10：修理 —— 显示价 == 实扣，且随身是回城的 1.5 倍 ----

## 修理的取整口径和成长服务**不一样**：`GameState.repair_equipment` 用的是 `round`
## （`total * rate`），而成长服务用 `ceil`。两处都想「加个价」但方向不同，就是差 1—N 金。
## 这条专测「修理的显示与扣费同源」，并且顺带钉死「随身 = 回城 × 1.5」这个产品口径。
func _test_repair_price_matches_charge() -> void:
	var dialogue := preload("res://scenes/ui/BlacksmithPanel.tscn").instantiate()
	add_child(dialogue)
	GameState.reset_to_defaults()
	GameState.gold = 10000000
	var rng := RandomNumberGenerator.new()
	rng.seed = 1082
	var item := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "epic", rng)
	# 磨掉一半耐久，让「一键修理」有活干。
	var maximum := Durability.max_durability()
	item["durability"] = int(maximum / 2)
	GameState.equipment["weapon"] = item

	dialogue._on_requested("铁匠", "", false)
	dialogue._show_menu()
	var local_text: String = dialogue._repair.text
	var local_price := _price_in(local_text, "一键修理（", "金）")
	check(local_price > 0, "回城修理价应可读，实际「%s」" % local_text)
	var before_local := GameState.gold
	dialogue._on_repair()
	var spent_local := before_local - GameState.gold
	check(spent_local == local_price, "回城修理**实扣 %d ≠ 显示 %d**" % [spent_local, local_price])

	# 磨回去，再走随身模式。
	item["durability"] = int(maximum / 2)
	GameState.equipment["weapon"] = item
	dialogue._on_requested("", "", true)
	var portable_text: String = dialogue._repair.text
	var portable_price := _price_in(portable_text, "一键修理（", "金）")
	check(portable_price > 0, "随身修理价应可读，实际「%s」" % portable_text)
	check(portable_price == int(round(float(local_price) * ServiceFee.REPAIR_PORTABLE_RATE)),
		"随身修理应为回城的 %.1f 倍（round 口径）：期望 %d，实际 %d"
		% [ServiceFee.REPAIR_PORTABLE_RATE,
			int(round(float(local_price) * ServiceFee.REPAIR_PORTABLE_RATE)), portable_price])
	var before_portable := GameState.gold
	dialogue._on_repair()
	var spent_portable := before_portable - GameState.gold
	check(spent_portable == portable_price,
		"随身修理**实扣 %d ≠ 显示 %d**" % [spent_portable, portable_price])
	dialogue.queue_free()
