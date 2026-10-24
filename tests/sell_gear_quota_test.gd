extends Node
## 工程 102：同部位「升级候选」按槽位数限额 —— 背包每个部位只保留评分最高的 N 件
## （N = 该部位槽位数：戒指/护腕/护膝/手镯 2，其余 1），超出的不再享受「评分可提升」保护。
##
## 守十件事：单槽/双槽额度、金紫占额度但不卖（口径 B）、星级等硬保护优先、端到端透传、
## 同分排序稳定、空槽规则不变、破损件口径不变、拾取驱逐、拾取让位（含同分让位）。
##
## ⚠ 代表件全部来自真实 `ItemFactory` 模板，高下由 `Equipment.score()` **现算**再断方向，
##   不写死分数 —— 改数值表不会让这份测试静默失效，只会让「夹具前提」那条断言先红。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[SellGearQuotaTest] " + label)

func _ready() -> void:
	_test_single_quota()
	_test_double_quota()
	_test_legendary_counts_but_never_sells()
	_test_hard_protections_win()
	_test_end_to_end_wiring()
	_test_tie_is_stable()
	_test_empty_slot_unchanged()
	_test_damaged_still_blocked()
	_test_pickup_evicts_weaker()
	_test_pickup_lets_better_stay()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[SellGearQuotaTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[SellGearQuotaTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- A 单槽额度：武器只留 1 件 ----

func _test_single_quota() -> void:
	_stage()
	var worn := _roll("weapon_iron", "common", 1)
	GameState.equipment["weapon"] = worn
	var weaker := _roll("c2_road_blade", "rare", 2)
	var best := _roll("c3_equip_weapon", "rare", 3)
	check(Equipment.score(best) > Equipment.score(weaker), "夹具前提：高阶武器评分更高")
	check(Equipment.score(weaker) > Equipment.score(worn), "夹具前提：两件候选都高于已穿戴")
	_bag([weaker, best])
	var rows := _rule_rows(SellGearPolicy.AGGRESSIVE)
	var row_best := _find_row(rows, String(best.instanceId))
	var row_weaker := _find_row(rows, String(weaker.instanceId))
	check(not bool(row_best.get("default_selected", true)), "额度内（第 1 名）的升级候选仍受保护")
	check(not (row_best.get("reasons") as Array).has("duplicate"), "额度内的件不该带 duplicate")
	check(bool(row_weaker.get("default_selected", false)), "武器额度 = 1 ⇒ 第 2 名默认勾选出售")
	check((row_weaker.get("reasons") as Array).has("duplicate"), "超额度件必须带 duplicate 原因")

# ---- B 双槽额度：戒指留 2 件，且留的必须是分数最高的两件 ----

func _test_double_quota() -> void:
	_stage()
	var worn_a := _roll("ring_basic", "common", 11)
	var worn_b := _roll("ring_basic", "common", 12)
	GameState.equipment["ring_1"] = worn_a
	GameState.equipment["ring_2"] = worn_b
	var low := _roll("c3_equip_ring", "rare", 13)
	var mid := _roll("c4_equip_ring", "rare", 14)
	var high := _roll("c5_equip_ring", "rare", 15)
	check(Equipment.score(low) < Equipment.score(mid) and Equipment.score(mid) < Equipment.score(high),
		"夹具前提：三件戒指评分递增")
	_bag([low, mid, high])
	var rows := _rule_rows(SellGearPolicy.AGGRESSIVE)
	check(bool(_find_row(rows, String(low.instanceId)).get("default_selected", false)),
		"戒指额度 = 2 ⇒ 第 3 名（分数最低）被默认勾选")
	check(not bool(_find_row(rows, String(mid.instanceId)).get("default_selected", true)),
		"第 2 名留在额度内")
	check(not bool(_find_row(rows, String(high.instanceId)).get("default_selected", true)),
		"第 1 名留在额度内")
	# 保留下来的必须真的按评分排序，而不是按背包格序取前两件
	check(SellGearPolicy.quota_for("ring") == 2 and SellGearPolicy.quota_for("weapon") == 1,
		"额度取槽位数：戒指 2、武器 1")

# ---- C 口径 B：金紫占额度，但自己永不被卖 ----

func _test_legendary_counts_but_never_sells() -> void:
	_stage()
	GameState.equipment["ring_1"] = _roll("ring_basic", "common", 21)
	GameState.equipment["ring_2"] = _roll("ring_basic", "common", 22)
	var legend := _roll("c6_equip_ring", "legendary", 23)
	var better_rare := _roll("c5_equip_ring", "rare", 24)
	var worse_rare := _roll("c4_equip_ring", "rare", 25)
	check(Equipment.score(legend) > Equipment.score(better_rare), "夹具前提：传说评分高于两件稀有")
	check(Equipment.score(better_rare) > Equipment.score(worse_rare), "夹具前提：两件稀有评分递减")
	_bag([legend, better_rare, worse_rare])
	var rows := _rule_rows(SellGearPolicy.AGGRESSIVE)
	var row_legend := _find_row(rows, String(legend.instanceId))
	var row_worse := _find_row(rows, String(worse_rare.instanceId))
	check(not bool(row_legend.get("default_selected", true)) and (row_legend.get("reasons") as Array).has("quality"),
		"传说件永远不被勾选（品质高于预设上限）")
	# 🔑 这一条就是「口径 B」的判据：传说占了 2 个名额中的 1 个，
	# 于是评分最低的稀有对落在额度外被卖掉。若改成「金紫不占额度」，它会被保护 ⇒ 本断言变红。
	check(bool(row_worse.get("default_selected", false)),
		"金紫占额度 ⇒ 同组第 3 名的稀有件被卖掉（口径 B）")

# ---- D 硬保护优先：星级件即使落在额度外也不卖 ----

func _test_hard_protections_win() -> void:
	_stage()
	GameState.equipment["ring_1"] = _roll("ring_basic", "common", 31)
	GameState.equipment["ring_2"] = _roll("ring_basic", "common", 32)
	var top := _roll("c6_equip_ring", "rare", 33)
	var second := _roll("c5_equip_ring", "rare", 34)
	var capped := _roll("c4_equip_ring", "rare", 35)
	capped["star"] = 1
	check(Equipment.score(top) > Equipment.score(second) and Equipment.score(second) > Equipment.score(capped),
		"夹具前提：星级件评分最低（落在额度外）")
	_bag([top, second, capped])
	var row := _find_row(_rule_rows(SellGearPolicy.AGGRESSIVE), String(capped.instanceId))
	check((row.get("reasons") as Array).has("duplicate"), "落在额度外的件会带 duplicate")
	check(not bool(row.get("default_selected", true)) and (row.get("reasons") as Array).has("starred"),
		"额度外 + 已升星 ⇒ 仍不被勾选（硬保护优先于额度）")

# ---- E 端到端：额度上下文必须真的从 GameState 透传到规则层 ----

func _test_end_to_end_wiring() -> void:
	_stage()
	GameState.equipment["weapon"] = _roll("weapon_iron", "common", 41)
	var low := _roll("c2_road_blade", "rare", 42)
	var mid := _roll("c3_equip_weapon", "rare", 43)
	var high := _roll("c4_equip_weapon", "rare", 44)
	check(Equipment.score(low) < Equipment.score(mid) and Equipment.score(mid) < Equipment.score(high),
		"夹具前提：三件武器评分递增")
	_bag([low, mid, high])
	var rows := GameState.preview_equipment_sale()
	check(rows.size() == 3, "夹具前提：三件武器都进清单（实际 %d）" % rows.size())
	var selected := 0
	for row in rows:
		if bool(row.get("default_selected", false)):
			selected += 1
	# 🔑 这是防「`keep_ids` 漏传」的**唯一有效**断言：漏传时三件全被保护，selected 会变成 0。
	check(selected == 2, "武器额度 1 ⇒ 清单里只留 1 件、勾 2 件（实际勾 %d 件）" % selected)
	check(not bool(_find_row(rows, String(high.instanceId)).get("default_selected", true)),
		"留在额度内的应是评分最高的那件")
	# 确认层必须算出同一份额度，否则玩家按「已勾选」提交时会收到「所选装备需要再次确认」
	# —— 两个入口各算一套是这类功能的经典翻车方式（工程 102 R2）。
	var chosen: Array[Dictionary] = []
	for row in rows:
		if bool(row.get("default_selected", false)):
			chosen.append(row)
	var checked := GameState.validate_equipment_sale(chosen)
	check(bool(checked.get("ok", false)),
		"确认层与清单层必须算出同一份额度（实际「%s」）" % String(checked.get("reason", "")))

# ---- F 同分排序必须稳定（否则确认时假报「清单已变化」） ----

func _test_tie_is_stable() -> void:
	_stage()
	GameState.equipment["weapon"] = _roll("weapon_iron", "common", 51)
	# 同模板同品质同种子 ⇒ 词条完全一致，评分相同（instanceId 用随机字节生成，天然不同）
	var first_item := _roll("c3_equip_weapon", "rare", 52)
	var second_item := _roll("c3_equip_weapon", "rare", 52)
	check(is_equal_approx(Equipment.score(first_item), Equipment.score(second_item)),
		"夹具前提：两件评分相同")
	_bag([first_item, second_item])
	var rows_a := _rule_rows(SellGearPolicy.AGGRESSIVE)
	var rows_b := _rule_rows(SellGearPolicy.AGGRESSIVE)
	check(rows_a.size() == rows_b.size(), "两次构建行数应一致")
	var mismatch := 0
	for i in range(mini(rows_a.size(), rows_b.size())):
		if bool(rows_a[i].get("default_selected", false)) != bool(rows_b[i].get("default_selected", true)):
			mismatch += 1
	check(mismatch == 0, "同分件两次构建的勾选状态必须完全一致（实际不一致 %d 行）" % mismatch)
	check(bool(_find_row(rows_a, String(second_item.instanceId)).get("default_selected", false))
		and not bool(_find_row(rows_a, String(first_item.instanceId)).get("default_selected", true)),
		"同分时保留背包格序靠前的那件（排序必须有确定 tiebreak）")

# ---- G 空槽规则不变 ----

func _test_empty_slot_unchanged() -> void:
	_stage()
	check(GameState.equipment.get("weapon") == null, "夹具前提：武器槽为空")
	var fresh := _roll("weapon_iron", "common", 61)
	_bag([fresh])
	var row := _find_row(_rule_rows(SellGearPolicy.AGGRESSIVE), String(fresh.instanceId))
	check(bool(row.get("default_selected", true)), "空槽的第一件不参与额度（V1 规则不变）")
	check(not (row.get("reasons") as Array).has("duplicate"), "空槽件不该被判成超额度")

# ---- H 破损件口径不变：额度给它让路，但自动出售仍然拦住 ----

func _test_damaged_still_blocked() -> void:
	_stage()
	var worn := _roll("weapon_iron", "common", 71)
	GameState.equipment["weapon"] = worn
	var held := _roll("c5_equip_weapon", "rare", 72)
	# 破损件排**额度外**：它比身上好（是升级候选），但比背包里那件差 ⇒ 会被判成超额度。
	# 若没有 `damaged` 这条否决，它就会按 `duplicate` 被卖掉 —— 这正是要守的那条线。
	var broken := _roll("c3_equip_weapon", "rare", 73)
	broken["durability"] = 0
	check(Equipment.score(held) > Equipment.score(broken), "夹具前提：破损件评分更低（落在额度外）")
	check(Equipment.score(broken) > Equipment.score(worn), "夹具前提：破损件仍然高于已穿戴（是升级候选）")
	var decision := SellGearPolicy.auto_sell(broken, 60, GameState.equipment,
		SellGearPolicy.AGGRESSIVE, false, [held])
	check(not bool(decision.get("sell", true)) and String(decision.get("reason", "")) == "damaged",
		"破损件落在额度外也不自动出售（工程 99 的刻意口径，`damaged` 不属于 SELL_THROUGH）")

# ---- I 拾取驱逐：新件更好 ⇒ 挤掉名额内最弱的一件并当场卖掉 ----

func _test_pickup_evicts_weaker() -> void:
	_stage()
	GameState.equipment["weapon"] = _roll("weapon_iron", "common", 81)
	var held := _roll("c3_equip_weapon", "rare", 82)
	_bag([held])
	var incoming := _roll("c4_equip_weapon", "rare", 83)
	check(Equipment.score(incoming) > Equipment.score(held), "夹具前提：新件评分更高")
	var price := Shop.sell_price(held)
	check(price > 0, "夹具前提：被驱逐件有售价")
	var res := GameState.pickup_loot(incoming)
	check(bool(res.get("ok", false)), "驱逐后新件应入包")
	check(not bool(res.get("auto_sold", true)), "更好的一件不该被卖掉")
	check(int(res.get("gold", 0)) == price, "被挤掉那件的金币应入账（期望 %d，实际 %d）"
		% [price, int(res.get("gold", 0))])
	check(GameState.gold == price, "金币总额应只来自驱逐（实际 %d）" % GameState.gold)
	check(_bag_count() == 1, "背包件数应保持额度 1（实际 %d）" % _bag_count())
	check(_bag_has(String(incoming.instanceId)), "背包里应是新件")
	check(not _bag_has(String(held.instanceId)), "旧的较差件应已移出背包")

# ---- J 拾取让位：新件更差 / 同分 ⇒ 卖新件，背包不动 ----

func _test_pickup_lets_better_stay() -> void:
	_stage()
	GameState.equipment["weapon"] = _roll("weapon_iron", "common", 91)
	var held := _roll("c4_equip_weapon", "rare", 92)
	_bag([held])
	var worse := _roll("c3_equip_weapon", "rare", 93)
	check(Equipment.score(worse) < Equipment.score(held), "夹具前提：新件评分更低")
	var price := Shop.sell_price(worse)
	var res := GameState.pickup_loot(worse)
	check(bool(res.get("auto_sold", false)), "额度已满且新件更差 ⇒ 新件当场卖出")
	check(int(res.get("gold", 0)) == price, "入账应为新件售价（期望 %d，实际 %d）"
		% [price, int(res.get("gold", 0))])
	check(_bag_count() == 1 and _bag_has(String(held.instanceId)), "背包应原样保留那件更好的")
	# 同分让位：不能出现「刚捡的顶掉刚留的」
	var tie := _roll("c4_equip_weapon", "rare", 92)
	check(is_equal_approx(Equipment.score(tie), Equipment.score(held)), "夹具前提：与背包那件同分")
	var tie_res := GameState.pickup_loot(tie)
	check(bool(tie_res.get("auto_sold", false)), "同分时新件让位（卖掉新捡的那件）")
	check(_bag_count() == 1 and _bag_has(String(held.instanceId)), "同分时背包里仍是原来那件")
	check(GameState.gold == price + Shop.sell_price(tie), "两笔自动出售都要入账（实际 %d）" % GameState.gold)

# ---- 夹具 ----

## 60 级的标准局面：积极档、金币清零、装备清空、背包清空、拾取自动出售已开启。
## 积极档不限等级、只放行到稀有，正好把「品质」与「额度」两条判据分开考。
func _stage() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 60
	GameState.gold = 0
	GameState.settings["autoSellEquipOnPickup"] = true
	GameState.set_sell_gear_preset(SellGearPolicy.AGGRESSIVE)
	GameState.equipment = Equipment.create()
	_bag([])

func _bag(items: Array) -> void:
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null
	for i in range(items.size()):
		GameState.inventory[i] = items[i]

func _bag_count() -> int:
	var n := 0
	for it in GameState.inventory:
		if it is Dictionary:
			n += 1
	return n

func _bag_has(instance_id: String) -> bool:
	for it in GameState.inventory:
		if it is Dictionary and String((it as Dictionary).get("instanceId", "")) == instance_id:
			return true
	return false

func _find_row(rows: Array, instance_id: String) -> Dictionary:
	for row in rows:
		if String(row.get("instance_id", "")) == instance_id:
			return row
	return {}

## 规则层的清单：自己算额度再逐件套用，**不经过 `GameState`**。
## 分层是刻意的 —— 负向 N-3 只改 `build_preview()` 的透传，必须**只**让 E 组（端到端）变红；
## 其余各组若也走 `GameState`，这条负向就会连带打红六七条，牙齿的独立性就没了。
func _rule_rows(preset: String) -> Array:
	var rows: Array = []
	var quota := SellGearPolicy.rank_context(GameState.inventory, 60, GameState.equipment, preset)
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i] is Dictionary:
			rows.append(SellGearPolicy.entry(GameState.inventory[i], i, 60,
				GameState.equipment, preset, quota))
	return rows

## 按真实模板滚一件装备。套位读模板自己的 `tierBases` 键，**不从 requiredLevel 反推**：
## `necklace_basic` 是 19 级却只挂了第 1 套基底，反推会去找不存在的第 11 套并 push_error。
func _roll(item_id: String, quality: String, seed_value: int) -> Dictionary:
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	var bases: Variant = (tpl as Dictionary).get("tierBases", {})
	if not bases is Dictionary or (bases as Dictionary).is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return ItemFactory.make_equip_roll(item_id, int(String((bases as Dictionary).keys()[0])),
		quality, rng)
