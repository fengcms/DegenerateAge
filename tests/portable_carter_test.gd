extends Node
## M10-7 随身车夫（工程 48 §4）：七分组 / 跨章目的地 / 双模式面板 / 发放任务 / 三件套端到端。
##
## 两条底线：
## ① **用例 3**：`c7_arena` 必须落 `60+`、`c6_map05` 必须落 `51-60`。两者推荐等级**都是 60**，
##    所以「只按 recommendedLevel 分桶」的实现会立刻红 —— 它是「60+ 组不是空的」唯一守门人。
## ② **用例 14**：`unlocks` 写成单数会静默毁档（R-1，最高危）。这里走**真文件往返**
##    （槽 3），只有白名单认账才算过；纯内存断言发现不了这个坑。
##
## 用例 12 → 13 → 14 是同一条数据链（先接取、再交付、再用道具并存档），
## 前置失败时后续用例直接 return，避免连带制造假红。

const CAMP := "camp"
const TOKEN := "tool_boss_token"
const SHOP_TOOL := "tool_portable_shop"
const CARTER_TOOL := "tool_portable_carter"
const QUEST_ID := "C6S07"
const C6_NPC := "c6_npc01"
const TEST_SLOT := 3

## 七组的期望键序（产品 13 §5.3）。写死比对：改顺序 / 少一组都要红。
const EXPECTED_GROUPS := ["1-10", "11-20", "21-30", "31-40", "41-50", "51-60", "60+"]

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PortableCarterTest] " + label)

func _ready() -> void:
	_test_group_keys()
	_test_row_set()
	_test_arena_group()
	_test_stable_order()
	_test_cost()
	_test_locked_reason()
	_test_unvisited_reason()
	_test_visited_open()
	_test_travel_anywhere_chain()
	_test_rejections()
	_test_panel_modes()
	_test_quest_gate()
	_test_reward_and_toast()
	_test_all_three_usable_and_save()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[PortableCarterTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[PortableCarterTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 1) 七组键序固定 ----

func _test_group_keys() -> void:
	check(MapService.LEVEL_GROUPS == EXPECTED_GROUPS,
		"七个分组键与顺序必须固定，实际 %s" % str(MapService.LEVEL_GROUPS))
	for entry in DataLoader.get_table("maps"):
		if not entry is Dictionary:
			continue
		var map_id := String((entry as Dictionary).get("id", ""))
		var group := MapService.level_group_of(map_id)
		check(EXPECTED_GROUPS.has(group),
			"%s 的分组键「%s」不在固定七组内（会渲染出空标题/丢行）" % [map_id, group])

# ---- 2) 行集：全表 36 图 − 当前图 = 35 行，每图恰好一次 ----

func _test_row_set() -> void:
	GameState.reset_to_defaults()
	check(GameState.current_map == CAMP, "前置：新档应在营地，实际 %s" % GameState.current_map)
	var rows := MapService.anywhere_destinations()
	var all := _all_map_ids()
	check(rows.size() == all.size() - 1,
		"应列出除当前图外的全部地图：期望 %d 行，实际 %d" % [all.size() - 1, rows.size()])
	var seen := {}
	for raw in rows:
		var id := String((raw as Dictionary).get("id", ""))
		check(not seen.has(id), "%s 在列表里出现了不止一次" % id)
		seen[id] = true
	for id in all:
		if id == CAMP:
			check(not seen.has(id), "当前图 %s 不应出现在目的地列表里" % CAMP)
			continue
		check(seen.has(id), "列表缺少地图 %s" % id)

# ---- 3) 60+ 组不能空（C-2 的守门用例）----

func _test_arena_group() -> void:
	check(MapService.recommended_level("c7_arena") == MapService.recommended_level("c6_map05"),
		"前置：c7_arena 与 c6_map05 的推荐等级应相同（都是 60），否则本用例失去意义")
	check(MapService.level_group_of("c7_arena") == "60+",
		"循环图 c7_arena 必须落 60+ 组，实际「%s」" % MapService.level_group_of("c7_arena"))
	check(MapService.level_group_of("c6_map05") == "51-60",
		"c6_map05 必须落 51-60 组，实际「%s」" % MapService.level_group_of("c6_map05"))
	check(MapService.level_group_of(CAMP) == "1-10",
		"营地应落 1-10 组，实际「%s」" % MapService.level_group_of(CAMP))
	var arena := _row(MapService.anywhere_destinations(), "c7_arena")
	check(not arena.is_empty() and String(arena.get("group", "")) == "60+",
		"列表里 c7_arena 的 group 也必须是 60+，实际「%s」" % arena.get("group", ""))

# ---- 4) 排序稳定且组内等级非降 ----

func _test_stable_order() -> void:
	var a := MapService.anywhere_destinations()
	var b := MapService.anywhere_destinations()
	check(a.size() == b.size(), "连续两次调用行数应一致（%d vs %d）" % [a.size(), b.size()])
	for i in range(mini(a.size(), b.size())):
		check((a[i] as Dictionary) == (b[i] as Dictionary),
			"第 %d 行两次调用结果不一致（排序不稳定会让玩家每次打开看到不同顺序）" % i)
	var last_index := -1
	var last_group := ""
	var last_level := -1
	for raw in a:
		var row: Dictionary = raw
		var group := String(row.get("group", ""))
		var index := EXPECTED_GROUPS.find(group)
		check(index >= last_index, "分组顺序应与常量一致：%s 出现在 %s 之后" % [group, last_group])
		last_index = index
		if group != last_group:
			last_group = group
			last_level = -1
		var level := int(row.get("recommendedLevel", 0))
		check(level >= last_level, "组 %s 内推荐等级应非降：%d 出现在 %d 之后" % [group, level, last_level])
		last_level = level

# ---- 5) 报价必须是随身口径（20 × 等级，下限 50）----

func _test_cost() -> void:
	var rows := MapService.anywhere_destinations()
	for raw in rows:
		var row: Dictionary = raw
		var id := String(row.get("id", ""))
		var cost := int(row.get("cost", -1))
		check(cost == MapService.fee_anywhere(id),
			"%s 的报价应与 fee_anywhere 一致（行 %d vs API %d）" % [id, cost, MapService.fee_anywhere(id)])
		check(cost >= 50, "%s 的随身报价不得低于下限 50，实际 %d" % [id, cost])
	check(int(_row(rows, "c6_map05").get("cost", -1)) == 1200,
		"c6_map05（L60）随身报价应为 1200，实际 %d" % int(_row(rows, "c6_map05").get("cost", -1)))
	check(int(_row(rows, "c7_arena").get("cost", -1)) == 1200,
		"c7_arena 随身报价应为 1200，实际 %d" % int(_row(rows, "c7_arena").get("cost", -1)))

# ---- 6) 未解锁：显示但置灰（不隐藏）----

func _test_locked_reason() -> void:
	GameState.reset_to_defaults()
	var row := _row(MapService.anywhere_destinations(), "c6_map00")
	check(not row.is_empty(), "未解锁的地图也应出现在列表里（置灰 + 原因，而不是隐藏）")
	check(not bool(row.get("unlocked", true)), "chapter6 未解锁时 c6_map00 不应可前往")
	check(String(row.get("reason", "")) == Localization.tr_key("msg.map_service.p011"),
		"未解锁原因应为「尚未解锁」，实际「%s」" % row.get("reason", ""))

# ---- 7) 已解锁未到访：仍不可直达（不能跳剧情）----

func _test_unvisited_reason() -> void:
	GameState.reset_to_defaults()
	GameState.unlocks["chapter6"] = true
	var row := _row(MapService.anywhere_destinations(), "c6_map00")
	check(not bool(row.get("unlocked", true)), "已解锁但未到访仍不应可直达")
	check(String(row.get("reason", "")) == Localization.tr_key("msg.map_service.p012"),
		"未到访原因应为「先步行到访，开放直达」，实际「%s」" % row.get("reason", ""))

# ---- 8) 已解锁 + 已到访 = 可前往；且教学例外与 API 同源 ----

func _test_visited_open() -> void:
	GameState.reset_to_defaults()
	GameState.unlocks["chapter6"] = true
	GameState.mark_visited("c6_map00")
	var row := _row(MapService.anywhere_destinations(), "c6_map00")
	check(bool(row.get("unlocked", false)), "已解锁 + 已到访应显示可前往")
	check(String(row.get("reason", "")).is_empty(), "可前往的行不应带原因，实际「%s」" % row.get("reason", ""))
	# 教学例外：营地出发时 wild_trial 未到访也放行 —— 面板与 `_travel_checks` 必须同源，
	# 否则会出现「面板写着能去、点了报『先步行到访』」。
	var taught := _row(MapService.anywhere_destinations(), "wild_trial")
	check(bool(taught.get("unlocked", false)),
		"营地出发时 wild_trial 应因教学例外放行（面板灰、API 却能走就是双轨）")

# ---- 9) 跨章直达全链：扣费 / 切图 / 落点 / 回滚 ----

func _test_travel_anywhere_chain() -> void:
	GameState.reset_to_defaults()
	GameState.unlocks["chapter6"] = true
	GameState.unlocks["c6_access_05"] = true
	GameState.mark_visited("c6_map05")
	GameState.gold = 5000
	var res := MapService.travel_anywhere("c6_map05")
	check(bool(res.get("ok", false)), "营地直达 c6_map05 应成功：%s" % String(res.get("reason", "")))
	if not bool(res.get("ok", false)):
		GameState.reset_to_defaults()
		return
	check(GameState.gold == 3800, "应精确扣 1200，实际余额 %d" % GameState.gold)
	check(GameState.current_map == "c6_map05", "应已切到 c6_map05，实际 %s" % GameState.current_map)
	check(GameState.has_save_pos and GameState.save_pos == MapService.carter_arrival("c6_map05"),
		"落点应为车夫落点，实际 %s" % str(GameState.save_pos))
	MapService.rollback_travel()
	check(GameState.current_map == CAMP, "回滚后应回到营地，实际 %s" % GameState.current_map)
	check(GameState.gold == 5000, "回滚应退还车费，实际 %d" % GameState.gold)
	GameState.reset_to_defaults()

# ---- 10) 拒绝链三条：文案必须指名地图 ----

func _test_rejections() -> void:
	# ① 已解锁未到访 → p017
	GameState.reset_to_defaults()
	GameState.unlocks["chapter6"] = true
	GameState.gold = 5000
	var unvisited := MapService.travel_anywhere("c6_map00")
	check(not bool(unvisited.get("ok", false)), "未到访的图不得直达")
	check(String(unvisited.get("reason", "")).contains(MapService.display_name("c6_map00")),
		"未到访文案应指名地图，实际「%s」" % unvisited.get("reason", ""))
	# ② 未解锁 → p016
	GameState.reset_to_defaults()
	GameState.gold = 5000
	var locked := MapService.travel_anywhere("c6_map00")
	check(not bool(locked.get("ok", false)), "未解锁的图不得直达")
	check(String(locked.get("reason", "")).contains(MapService.display_name("c6_map00")),
		"未解锁文案应指名地图，实际「%s」" % locked.get("reason", ""))
	# ③ 当前图 → p014
	GameState.reset_to_defaults()
	var here := MapService.travel_anywhere(CAMP)
	check(not bool(here.get("ok", false)), "当前图不得直达")
	check(String(here.get("reason", "")).contains(MapService.display_name(CAMP)),
		"当前图文案应指名地图，实际「%s」" % here.get("reason", ""))
	check(MapService.pending_travel.is_empty(), "三次拒绝都不得留下出行事务")

# ---- 11) 面板级：模式真的串到了 UI ----

func _test_panel_modes() -> void:
	GameState.reset_to_defaults()
	var scene: PackedScene = load("res://scenes/ui/CarterPanel.tscn")
	check(scene != null, "CarterPanel.tscn 应可加载")
	if scene == null:
		return
	var panel: Variant = scene.instantiate()
	add_child(panel)

	EventBus.carter_panel_requested.emit("随身车夫", true)
	var keys: Array[String] = panel.section_keys()
	check(keys == EXPECTED_GROUPS, "随身模式应渲染七个分组标题且顺序一致，实际 %s" % str(keys))
	check(panel.row_count() == 35, "随身模式应渲染 35 行，实际 %d" % int(panel.row_count()))

	EventBus.carter_panel_requested.emit("石辕", false)
	check((panel.section_keys() as Array).is_empty(),
		"当地模式不应有分组标题，实际 %s" % str(panel.section_keys()))
	check(panel.row_count() == MapService.destinations().size(),
		"当地模式行数应与 destinations() 一致（%d vs %d）" % [int(panel.row_count()), MapService.destinations().size()])
	check(panel.row_count() == 4, "营地当地车夫应恰好 4 行（与既有车夫面板一致），实际 %d" % int(panel.row_count()))

	# 出行 API 分岔：同一个目标，两条 API 在**金币不足**时报不同原因 ——
	# `travel_anywhere` 先过连通性、卡在钱上（金币不足）；`travel_to` 卡在拓扑（车夫无法直达）。
	# 只断言「渲染对了」抓不住漏改 `_on_travel` 的实现，这条才是 N-5 的牙。
	GameState.unlocks["chapter6"] = true
	GameState.unlocks["c6_access_05"] = true
	GameState.mark_visited("c6_map05")
	GameState.gold = 0
	EventBus.carter_panel_requested.emit("随身车夫", true)
	panel._on_travel("c6_map05")
	check(panel.hint_text().contains("金币不足"),
		"随身模式应走 travel_anywhere（报金币不足），实际「%s」" % panel.hint_text())
	EventBus.carter_panel_requested.emit("石辕", false)
	panel._on_travel("c6_map05")
	check(panel.hint_text().contains("车夫无法直达"),
		"当地模式应走 travel_to（报车夫无法直达），实际「%s」" % panel.hint_text())
	check(MapService.pending_travel.is_empty(), "两次失败都不得留下出行事务")

	panel.set_open(false)
	panel.queue_free()
	GameState.reset_to_defaults()

# ---- 12) 发放任务：prev 锁 + 等级门槛 60 ----

func _test_quest_gate() -> void:
	GameState.reset_to_defaults()
	check(Quest.template(QUEST_ID).get("type", "") == "side", "C6S07 应为支线（第六章 C6Q## 是主线编号）")
	check(not bool(Quest.template(QUEST_ID).get("abandonable", true)), "一次性发放任务不应可放弃")
	check(Quest.state_of(QUEST_ID) == Quest.STATE_LOCKED, "C6Q12 未领奖时 C6S07 应锁定")
	GameState.quest_states["C6Q12"] = {"state": Quest.STATE_REWARDED, "progress": 1}
	check(Quest.state_of(QUEST_ID) == Quest.STATE_AVAILABLE, "C6Q12 领奖后 C6S07 应可接取")

	GameState.player.level = 59
	GameState.current_map = MapService.map_for_npc(C6_NPC)
	var blocked: Dictionary = Quest.accept(QUEST_ID, C6_NPC)
	check(not bool(blocked.get("ok", false)), "59 级不应能接 60 级的发放任务")
	check(String(blocked.get("reason", "")).contains("60"),
		"拦截原因应带出所需等级 60，实际「%s」" % blocked.get("reason", ""))
	check(Quest.state_of(QUEST_ID) == Quest.STATE_AVAILABLE, "被门槛拦下不应把任务置成 active")

	GameState.player.level = 60
	var ok: Dictionary = Quest.accept(QUEST_ID, C6_NPC)
	check(bool(ok.get("ok", false)), "60 级应能接取：%s" % String(ok.get("reason", "")))
	check(Quest.state_of(QUEST_ID) == Quest.STATE_COMPLETED, "交谈任务接取即达标（talkOnAccept）")

# ---- 13) 发奖：三件入包 + unlocks 三键 + 提示列名 + 不可重复 ----

func _test_reward_and_toast() -> void:
	if Quest.state_of(QUEST_ID) != Quest.STATE_COMPLETED:
		check(false, "前置：C6S07 应处于待交付态（用例 12 失败会连带到这里）")
		return
	var toasts: Array[String] = []
	var cb := func(text: String, _kind: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(cb)
	var res: Dictionary = Quest.deliver(QUEST_ID, C6_NPC)
	EventBus.toast_requested.disconnect(cb)
	check(bool(res.get("ok", false)), "交付应成功：%s" % String(res.get("reason", "")))
	if not bool(res.get("ok", false)):
		return
	var joined := "\n".join(PackedStringArray(toasts))
	for item_id in [TOKEN, SHOP_TOOL, CARTER_TOOL]:
		var name := ItemUtil.display_name(ItemFactory.make_any(String(item_id)))
		check(not name.is_empty() and joined.contains(name), "交付提示应列出「%s」，实际「%s」" % [name, joined])
		check(_count_item(String(item_id)) == 1,
			"背包应恰好 1 件 %s，实际 %d" % [item_id, _count_item(String(item_id))])
		check(bool(GameState.unlocks.get(String(item_id), false)), "unlocks 应记录 %s" % item_id)
	check(not bool(Quest.deliver(QUEST_ID, C6_NPC).get("ok", false)), "已领奖的任务不得重复发放")

# ---- 14) 三件全能用 + 存档往返（R-1 守门）----

func _test_all_three_usable_and_save() -> void:
	for item_id in [TOKEN, SHOP_TOOL, CARTER_TOOL]:
		if _count_item(String(item_id)) < 1:
			check(false, "前置：%s 应在背包里（用例 13 失败会连带到这里）" % item_id)
			return
	var seen := {"carter": 0, "boss_token": 0, "shop": 0}
	var carter_cb := func(_npc_name: String, _portable: bool) -> void: seen["carter"] += 1
	var token_cb := func(_title: String) -> void: seen["boss_token"] += 1
	var shop_cb := func(_shop_id: String) -> void: seen["shop"] += 1
	EventBus.carter_panel_requested.connect(carter_cb)
	EventBus.boss_token_panel_requested.connect(token_cb)
	EventBus.shop_open_requested.connect(shop_cb)
	for item_id in [TOKEN, SHOP_TOOL, CARTER_TOOL]:
		var index := _find_item(String(item_id))
		var res: Dictionary = GameState.use_item(index) if index >= 0 else {"ok": false, "reason": "不在背包"}
		check(bool(res.get("ok", false)), "%s 应能直接用（拿到即可用）：%s" % [item_id, String(res.get("reason", ""))])
	EventBus.carter_panel_requested.disconnect(carter_cb)
	EventBus.boss_token_panel_requested.disconnect(token_cb)
	EventBus.shop_open_requested.disconnect(shop_cb)
	check(seen["carter"] == 1, "随身车夫应真广播 1 次，实际 %d" % int(seen["carter"]))
	check(seen["boss_token"] == 1, "追猎令牌应真广播 1 次，实际 %d" % int(seen["boss_token"]))
	check(seen["shop"] == 1, "随身商队应真广播 1 次，实际 %d" % int(seen["shop"]))
	for item_id in [TOKEN, SHOP_TOOL, CARTER_TOOL]:
		check(_count_item(String(item_id)) == 1, "面板类工具使用后不得消耗 %s" % item_id)

	# 真文件往返：`unlocks` 若被写成单数，白名单不认账 → 读档直接判存档损坏。
	check(SaveManager.save_slot(TEST_SLOT, true), "写测试槽 %d 应成功" % TEST_SLOT)
	var read: Dictionary = SaveManager.read_slot(TEST_SLOT)
	check(bool(read.get("ok", false)),
		"读档应通过校验（unlocks 白名单认账），实际「%s」" % String(read.get("message", "")))
	var data: Dictionary = read.get("data", {})
	var unlocks: Variant = data.get("unlocks", {})
	for item_id in [TOKEN, SHOP_TOOL, CARTER_TOOL]:
		check(unlocks is Dictionary and bool((unlocks as Dictionary).get(String(item_id), false)),
			"存档应保留 unlocks.%s" % item_id)

# ---- 辅助 ----

func _all_map_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in DataLoader.get_table("maps"):
		if entry is Dictionary:
			var id := String((entry as Dictionary).get("id", ""))
			if not id.is_empty():
				out.append(id)
	return out

func _row(rows: Array, map_id: String) -> Dictionary:
	for raw in rows:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == map_id:
			return raw
	return {}

func _count_item(item_id: String) -> int:
	var total := 0
	for slot in GameState.inventory:
		if slot is Dictionary and String((slot as Dictionary).get("itemId", "")) == item_id:
			total += int((slot as Dictionary).get("count", 0))
	return total

func _find_item(item_id: String) -> int:
	for i in range(GameState.inventory.size()):
		var slot: Variant = GameState.inventory[i]
		if slot is Dictionary and String((slot as Dictionary).get("itemId", "")) == item_id:
			return i
	return -1
