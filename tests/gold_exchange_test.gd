extends Node
## 工程 109 仓库兑换台：汇率契约 / 双向闭环 / 堆叠分格 / 金币上限 / 仓库满 / 余数 / 绑定守卫。
##
## 十条里最值钱的是 5 与 6：
## 5. **金币上限必须拒绝而不是夹取** —— `add_gold` 会 `clampi`，若靠它兜底，玩家兑回
##    1000 万时超出上限的部分会被静默吞掉。这条判的是「一分都没动」，不是「没报错」。
## 6. **仓库满不许扣钱** —— 先扣后判的典型症状是金币少了、金条没给；这里同样断言
##    「金币与仓库都保持原样」，而不是只看返回值 ok=false。
##
## 判据里的 100 万 / 10 / 1000 万是**产品口径**，必须在测试里写死（不能从被测算常量取），
## 否则汇率写错测试也会跟着绿。

const PAIR_TO_INGOT := "gold_to_ingot"
const PAIR_TO_BRICK := "ingot_to_brick"
const PAIR_INGOT_GOLD := "ingot_to_gold"
const PAIR_BRICK_GOLD := "brick_to_gold"
const INGOT := "gold_ingot"
const BRICK := "gold_brick"
const UNIT := 1000000          # 一块金条的币值（产品口径）

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[GoldExchangeTest] " + label)

func _ready() -> void:
	_test_rate_contract()
	_test_forward_chain()
	_test_stack_split()
	_test_brick_to_gold_direct()
	_test_gold_cap_refused()
	_test_warehouse_full_refused()
	_test_remainder_kept()
	_test_bound_guards()
	_test_icon_registered()
	_test_product_shape()
	_test_rate_text_from_data()
	_test_cost_text_scales()
	_test_batch_full_success()
	_test_batch_over_max_not_moved()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[GoldExchangeTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[GoldExchangeTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 用例 1：汇率契约（产品口径） ----

func _test_rate_contract() -> void:
	var expect := {
		PAIR_TO_INGOT: ["gold", INGOT, UNIT, 1],
		PAIR_TO_BRICK: [INGOT, BRICK, 10, 1],
		PAIR_INGOT_GOLD: [INGOT, "gold", 1, UNIT],
		PAIR_BRICK_GOLD: [BRICK, "gold", 1, UNIT * 10],
	}
	for pair_id in expect:
		var row := GoldExchange.pair(String(pair_id))
		check(not row.is_empty(), "兑换对应存在：%s" % pair_id)
		if row.is_empty():
			continue
		var want: Array = expect[pair_id]
		check(String(row.get("from", "")) == String(want[0]), "%s 的 from 应为 %s" % [pair_id, want[0]])
		check(String(row.get("to", "")) == String(want[1]), "%s 的 to 应为 %s" % [pair_id, want[1]])
		check(int(row.get("fromCount", 0)) == int(want[2]), "%s 的 fromCount 应为 %d，实际 %d"
			% [pair_id, want[2], int(row.get("fromCount", 0))])
		check(int(row.get("toCount", 0)) == int(want[3]), "%s 的 toCount 应为 %d，实际 %d"
			% [pair_id, want[3], int(row.get("toCount", 0))])

# ---- 用例 2：正向链条 金币 → 金条 → 金砖 ----

func _test_forward_chain() -> void:
	_reset(10 * UNIT)
	var first := GameState.exchange(PAIR_TO_INGOT, 10)
	check(bool(first.get("ok", false)), "1000 万金币应能换 10 块金条，失败原因：%s" % first.get("reason", ""))
	check(GameState.gold == 0, "换完金币应归零，实际 %d" % GameState.gold)
	check(_count(INGOT) == 10, "仓库应有 10 块金条，实际 %d" % _count(INGOT))
	var second := GameState.exchange(PAIR_TO_BRICK, 1)
	check(bool(second.get("ok", false)), "10 块金条应能合 1 块金砖，失败原因：%s" % second.get("reason", ""))
	check(_count(INGOT) == 0 and _count(BRICK) == 1,
		"合砖后应剩 0 条 1 砖，实际 %d 条 %d 砖" % [_count(INGOT), _count(BRICK)])
	check(GameState.gold == 0, "合砖不应再动金币，实际 %d" % GameState.gold)

# ---- 用例 3：堆叠上限分格 ----

func _test_stack_split() -> void:
	_reset(100 * UNIT)
	GameState.exchange(PAIR_TO_INGOT, 100)
	var stacks := _stacks(INGOT)
	var probe := GoldExchange.stack_item(INGOT, 1)
	var maximum := ItemUtil.stack_max(probe)
	check(maximum == 99, "金条堆叠上限应为 99（需求口径），实际 %d" % maximum)
	check(_count(INGOT) == 100, "100 次兑换应得到 100 块，实际 %d" % _count(INGOT))
	check(stacks.size() == 2, "100 块应占 2 格（99 + 1），实际 %d 格：%s" % [stacks.size(), str(stacks)])
	for n in stacks:
		check(int(n) <= maximum, "单格不得超过堆叠上限 %d，实际 %d" % [maximum, int(n)])
	check(stacks.has(99) and stacks.has(1), "两格应为 99 与 1，实际 %s" % str(stacks))

# ---- 用例 4：金砖可直兑 1000 万（不经过金条） ----

func _test_brick_to_gold_direct() -> void:
	_reset(0)
	Inventory.add(GameState.warehouse, GoldExchange.stack_item(BRICK, 1))
	var result := GameState.exchange(PAIR_BRICK_GOLD, 1)
	check(bool(result.get("ok", false)), "1 块金砖应能直兑金币，失败原因：%s" % result.get("reason", ""))
	check(GameState.gold == 10 * UNIT, "1 砖应兑 1000 万金币，实际 %d" % GameState.gold)
	check(_count(BRICK) == 0, "兑换后金砖应从仓库扣除")

# ---- 用例 5：金币上限必须拒绝，且一分不动 ----

func _test_gold_cap_refused() -> void:
	# 差 500 万到上限，手里有 1 砖（值 1000 万）⇒ 必然超上限。
	_reset(GameState.GOLD_CAP - 5 * UNIT)
	Inventory.add(GameState.warehouse, GoldExchange.stack_item(BRICK, 1))
	var gold_before := GameState.gold
	var store_before: Array = GameState.warehouse.duplicate(true)
	var result := GameState.exchange(PAIR_BRICK_GOLD, 1)
	check(not bool(result.get("ok", false)), "超出金币上限时必须拒绝，而不是夹取")
	check(GameState.gold == gold_before, "被拒时金币不得变动（实为 %d，原 %d）" % [GameState.gold, gold_before])
	check(_count(BRICK) == 1, "被拒时金砖必须仍在仓库")
	check(GameState.warehouse == store_before, "被拒时仓库必须原样（含格位与数量）")

# ---- 用例 6：仓库满必须拒绝，且不扣金币 ----

func _test_warehouse_full_refused() -> void:
	_reset(2 * UNIT)
	# 仓库压满：每格都是无关物品且已叠满，既没有空格、也没有可合并的金条堆。
	var slot_count := GameState.warehouse.size()
	var probe := ItemUtil.stack_max({"kind": "misc", "itemId": "misc_firework", "count": 1})
	for i in range(slot_count):
		GameState.warehouse[i] = {"kind": "misc", "itemId": "misc_firework", "count": probe}
	var gold_before := GameState.gold
	var result := GameState.exchange(PAIR_TO_INGOT, 1)
	check(not bool(result.get("ok", false)), "仓库放不下时必须拒绝")
	check(GameState.gold == gold_before, "仓库放不下时不得扣金币（实为 %d，原 %d）" % [GameState.gold, gold_before])
	check(_count(INGOT) == 0, "被拒时不得凭空产生金条")

# ---- 用例 7：去余数（99 条 = 9 砖 + 9 条） ----

func _test_remainder_kept() -> void:
	_reset(0)
	Inventory.add(GameState.warehouse, GoldExchange.stack_item(INGOT, 99))
	check(GoldExchange.max_times(PAIR_TO_BRICK) == 9,
		"99 条最多合 9 砖，max_times 实际 %d" % GoldExchange.max_times(PAIR_TO_BRICK))
	var result := GameState.exchange(PAIR_TO_BRICK, 9)
	check(bool(result.get("ok", false)), "99 条应能合 9 砖，失败原因：%s" % result.get("reason", ""))
	check(_count(BRICK) == 9, "应得 9 块金砖，实际 %d" % _count(BRICK))
	check(_count(INGOT) == 9, "余数 9 条必须保留，实际 %d" % _count(INGOT))

# ---- 用例 8：绑定守卫（不可售 / 不可丢 / 不冒用任务物品语义） ----

func _test_bound_guards() -> void:
	for item_id in [INGOT, BRICK]:
		var item := ItemFactory.make_any(item_id)
		check(not item.is_empty(), "%s 应能实例化" % item_id)
		check(not Shop.can_sell(item), "%s 不得被货郎收购（否则同一资产有两条换钱通道）" % item_id)
		check(Shop.sell_price(item) == 0, "%s 出售价应为 0" % item_id)
		var drop := GameState.can_drop_item(item)
		check(not bool(drop.get("ok", true)), "%s 不得丢到地面" % item_id)
		check(String(drop.get("reason", "")) == "bound",
			"%s 的拒绝原因应为 bound，实际「%s」" % [item_id, drop.get("reason", "")])
		# 刻意不用 questItem：否则玩家丢它会看到「任务物品不能丢弃」，语义错位。
		check(not Shop.is_quest_item(item), "%s 不应标 questItem（语义会串到任务链）" % item_id)

# ---- 用例 9：图标必须登记（漏登记 = 空白格，不报错） ----

func _test_icon_registered() -> void:
	for item_id in [INGOT, BRICK]:
		var icon := SampleArt.icon_for(ItemFactory.make_any(item_id))
		check(icon != null, "%s 必须有图标（SampleArt.ICONS 未登记会空白）" % item_id)
		if icon != null:
			check(icon.get_size() == Vector2(48, 48), "%s 图标应为 48×48，实际 %s" % [item_id, str(icon.get_size())])

# ---- 用例 10：产物形态（可堆叠 misc、无装备字段、双击无用法） ----

func _test_product_shape() -> void:
	_reset(2 * UNIT)
	GameState.exchange(PAIR_TO_INGOT, 2)
	var entries := _entries(INGOT)
	check(entries.size() == 1, "2 块金条应占 1 格，实际 %d" % entries.size())
	if entries.is_empty():
		return
	var row: Dictionary = entries[0]
	check(String(row.get("kind", "")) == "misc", "产物 kind 应为 misc（才走 99 堆叠），实际 %s" % row.get("kind", ""))
	check(String(row.get("itemId", "")) == INGOT, "产物 itemId 应为 %s" % INGOT)
	check(int(row.get("count", 0)) == 2, "产物数量应为 2，实际 %d" % int(row.get("count", 0)))
	check(not row.has("instanceId"), "储值物不得带装备实例字段")
	# 双击无用法：走 use_item 的兜底分支，不消耗、不弹面板。
	var item := ItemFactory.make_any(INGOT)
	GameState.inventory[0] = item.duplicate(true)
	var used := GameState.use_item(0)
	check(not bool(used.get("ok", true)), "金条不应可被使用")
	check(GameState.inventory[0] != null, "使用失败不得吞掉物品")
	GameState.inventory[0] = null

# ---- 用例 11：汇率说明行必须从数据推导，不能是硬编码字符串 ----

func _test_rate_text_from_data() -> void:
	# 判据用**产品口径**（100 万）而不是读 exchange.json 再自比 ——
	# 汇率被改成 150 万时，这里必须红（「不复用被测常量」）。
	var text := GoldExchange.rate_text(PAIR_TO_INGOT)
	check(text.find(str(UNIT)) >= 0, "汇率说明应含 %d，实际「%s」" % [UNIT, text])
	check(text.find("金币") >= 0, "汇率说明应含来源「金币」，实际「%s」" % text)
	check(text.find("金条") >= 0, "汇率说明应含目标「金条」，实际「%s」" % text)
	var brick := GoldExchange.rate_text(PAIR_TO_BRICK)
	check(brick.find("10") >= 0 and brick.find("金砖") >= 0,
		"合砖说明应含 10 与「金砖」，实际「%s」" % brick)

# ---- 用例 12：消耗文案随笔数缩放 ----

func _test_cost_text_scales() -> void:
	check(GoldExchange.cost_text(PAIR_TO_INGOT, 1).find(str(UNIT)) >= 0,
		"1 次应写 %d，实际「%s」" % [UNIT, GoldExchange.cost_text(PAIR_TO_INGOT, 1)])
	check(GoldExchange.cost_text(PAIR_TO_INGOT, 3).find(str(UNIT * 3)) >= 0,
		"3 次应写 %d，实际「%s」" % [UNIT * 3, GoldExchange.cost_text(PAIR_TO_INGOT, 3)])
	check(GoldExchange.cost_text(PAIR_TO_INGOT, 0).is_empty(), "0 次不应产生消耗文案")

# ---- 用例 13：批量跑满上限必须成功（批量入口的核心承诺） ----

func _test_batch_full_success() -> void:
	_reset(7 * UNIT)
	var maximum := GoldExchange.max_times(PAIR_TO_INGOT)
	check(maximum == 7, "700 万金币最多换 7 次，max_times 实际 %d" % maximum)
	var result := GameState.exchange(PAIR_TO_INGOT, 7)
	check(bool(result.get("ok", false)), "跑满 7 次应成功，失败原因：%s" % result.get("reason", ""))
	check(GameState.gold == 0, "跑满后金币应归零，实际 %d" % GameState.gold)
	check(_count(INGOT) == 7, "应得 7 块金条，实际 %d" % _count(INGOT))

# ---- 用例 14：批量超上限整笔拒绝，且一分不动 ----

func _test_batch_over_max_not_moved() -> void:
	_reset(7 * UNIT)
	var gold_before := GameState.gold
	var store_before: Array = GameState.warehouse.duplicate(true)
	var result := GameState.exchange(PAIR_TO_INGOT, 8)
	check(not bool(result.get("ok", false)), "超出可换次数必须整笔拒绝，而不是换 7 次")
	check(GameState.gold == gold_before, "被拒时金币不得变动（实为 %d，原 %d）" % [GameState.gold, gold_before])
	check(GameState.warehouse == store_before, "被拒时仓库必须原样（含格位与数量）")

# ---- 助手 ----

func _reset(gold: int) -> void:
	GameState.reset_to_defaults()
	GameState.gold = gold

func _count(item_id: String) -> int:
	return GoldExchange.count_in(GameState.warehouse, item_id)

func _entries(item_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in GameState.warehouse:
		if entry is Dictionary and String((entry as Dictionary).get("itemId", "")) == item_id:
			out.append(entry as Dictionary)
	return out

func _stacks(item_id: String) -> Array:
	var out := []
	for entry in _entries(item_id):
		out.append(int(entry.get("count", 0)))
	return out
