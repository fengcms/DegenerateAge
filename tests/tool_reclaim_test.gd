extends Node
## 工程 79 随身工具补领：缺失自愈 + 防重复刷 + 防新档误发 + 背包满走仓库。
##
## 四组最值钱的断言：
## 1. **用例 4 钉死「解锁键未置不补」** —— 判据一旦丢掉 unlocks 条件，每个新档都会白送三件工具，
##    那是把任务奖励变成开局赠品；这也是本判据唯一真正的误伤面。
## 2. **用例 3 钉死「已拥有不补」** —— 丢了这条就是无限刷（虽然现在不可卖不可丢，
##    但判据必须与「不可消耗」解耦，不能靠别处的约束兜底）。
## 3. **用例 7 钉死读档自愈端到端** —— 光测纯函数测不出**接线**：必须在
##    `SaveManager.apply_to_game_state` 之后，物品真的出现在 `GameState.inventory` 里。
## 4. **用例 5/6 钉死兜底链路** —— 背包满走仓库（Q2），两者都满必须记 failed 而不是静默消失。

## 判据的**业务期望清单**：必须手写，不能从 `ToolReclaim.panel_tool_ids()` 取长度再断言它自己
## （那是同义反复的假绿）。数据里新增 panel 类道具时，这里要跟着加 id ——
## 用例 1 会红着提醒你「补领范围得重新评估」，这正是它存在的意义。
## 工程 108 加第四件（随身铁匠）时，本清单从 3 变 4，下面所有计数都改为按它推导。
const EXPECTED_TOOLS := [
	"tool_boss_token",
	"tool_portable_shop",
	"tool_portable_carter",
	"tool_portable_blacksmith",
]

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ToolReclaimTest] " + label)

func _ready() -> void:
	_test_panel_ids()
	_test_missing_reclaim()
	_test_owned_not_reclaimed()
	_test_unlocked_false_not_reclaimed()
	_test_full_inventory_falls_to_warehouse()
	_test_both_full_records_failed()
	_test_load_self_heal()
	_test_no_notice_when_complete()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[ToolReclaimTest] 全部通过 ✅")
	else:
		for failure in failures:
			print("[ToolReclaimTest] 失败：" + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- 夹具 ----

func _all_unlocked() -> Dictionary:
	var out := {}
	for item_id in EXPECTED_TOOLS:
		out[String(item_id)] = true
	return out

## 造一个**真满**的容器：每格塞到堆叠上限，让 `has_space_for` 无处可放
## （塞 count=1 的可堆叠物会被并进已有堆，那不是满）。
func _filled(size: int) -> Array:
	var out := Inventory.create(size)
	var probe := ItemFactory.make_any("potion_hp_mid", 1)
	var cap := ItemUtil.stack_max(probe)
	for i in range(out.size()):
		out[i] = ItemFactory.make_any("potion_hp_mid", cap)
	return out

func _holds_any(container: Array, ids: Array[String]) -> int:
	var n := 0
	for item_id in ids:
		if ToolReclaim.holds(container, item_id):
			n += 1
	return n

# ---- 用例 ----

## 用例 1：判据的原料锚点 —— `useType == "panel"` 的道具必须与 `EXPECTED_TOOLS` 一一对应。
## 数据表若新增 panel 类道具而不更新本清单，这里会红，提醒同步评估补领范围；
## 反过来，清单里写了数据里没有的 id 也会红（防止「清单自我膨胀」）。
func _test_panel_ids() -> void:
	var ids := ToolReclaim.panel_tool_ids()
	check(ids.size() == EXPECTED_TOOLS.size(),
		"panel 类道具应为 %d 件，实际 %d" % [EXPECTED_TOOLS.size(), ids.size()])
	for item_id in EXPECTED_TOOLS:
		check(ids.has(item_id), "panel 类道具应包含 " + String(item_id))

## 用例 2：全部键已解锁且两处都没有 ⇒ 全补，且补完再判为空（幂等）。
func _test_missing_reclaim() -> void:
	var inv := Inventory.create(40)
	var wh := Inventory.create(40)
	var missing := ToolReclaim.missing_tools(_all_unlocked(), inv, wh)
	check(missing.size() == EXPECTED_TOOLS.size(),
		"全解锁且全缺失时应判 %d 件缺失，实际 %d" % [EXPECTED_TOOLS.size(), missing.size()])
	var result := ToolReclaim.reclaim(_all_unlocked(), inv, wh)
	var given := result.get("given", []) as Array
	check(given.size() == EXPECTED_TOOLS.size(), "应补发 %d 件，实际 %d"
		% [EXPECTED_TOOLS.size(), given.size()])
	check((result.get("to_warehouse", []) as Array).is_empty(), "背包有空间时不得进仓库")
	check((result.get("failed", []) as Array).is_empty(), "不应有补发失败")
	check(_holds_any(inv, ToolReclaim.panel_tool_ids()) == EXPECTED_TOOLS.size(), "全部都应出现在背包里")
	# 幂等：再判一次必须为空，否则每次读档都会补一遍。
	check(ToolReclaim.missing_tools(_all_unlocked(), inv, wh).is_empty(), "补发后不应再判缺失")

## 用例 3：已拥有的不补 —— 这是防重复刷的唯一闸门，必须单独钉死。
func _test_owned_not_reclaimed() -> void:
	var inv := Inventory.create(40)
	var wh := Inventory.create(40)
	var ids := ToolReclaim.panel_tool_ids()
	Inventory.add(inv, ItemFactory.make_any(ids[0], 1))
	var missing := ToolReclaim.missing_tools(_all_unlocked(), inv, wh)
	check(not missing.has(ids[0]), "已在背包的工具不得再判缺失")
	check(missing.size() == EXPECTED_TOOLS.size() - 1,
		"应只剩 %d 件缺失，实际 %d" % [EXPECTED_TOOLS.size() - 1, missing.size()])
	# 仓库里有的同样算「已拥有」。
	Inventory.add(wh, ItemFactory.make_any(ids[1], 1))
	check(ToolReclaim.missing_tools(_all_unlocked(), inv, wh).size() == EXPECTED_TOOLS.size() - 2,
		"仓库里有的也应算已拥有（应剩 %d 件）" % (EXPECTED_TOOLS.size() - 2))

## 用例 4：解锁键未置 ⇒ 一件不补（新档不得白送）。
func _test_unlocked_false_not_reclaimed() -> void:
	var inv := Inventory.create(40)
	var wh := Inventory.create(40)
	check(ToolReclaim.missing_tools({}, inv, wh).is_empty(), "未解锁时不得判缺失")
	var result := ToolReclaim.reclaim({}, inv, wh)
	check((result.get("given", []) as Array).is_empty(), "未解锁时不得补发任何东西")
	# 只解锁一件 ⇒ 只补那一件。
	var partial := ToolReclaim.reclaim({"tool_boss_token": true}, inv, wh)
	check((partial.get("given", []) as Array).size() == 1, "只解锁一件时只补一件")

## 用例 5（Q2）：背包满 ⇒ 走仓库，不能因为放不下就丢。
func _test_full_inventory_falls_to_warehouse() -> void:
	var inv := _filled(40)
	var wh := Inventory.create(40)
	var result := ToolReclaim.reclaim(_all_unlocked(), inv, wh)
	check((result.get("given", []) as Array).size() == EXPECTED_TOOLS.size(),
		"背包满也应补发 %d 件（进仓库）" % EXPECTED_TOOLS.size())
	check((result.get("to_warehouse", []) as Array).size() == EXPECTED_TOOLS.size(),
		"%d 件都应落进仓库" % EXPECTED_TOOLS.size())
	check(_holds_any(wh, ToolReclaim.panel_tool_ids()) == EXPECTED_TOOLS.size(), "全部应真在仓库里")

## 用例 6：背包与仓库都满 ⇒ 记 failed，绝不静默。
func _test_both_full_records_failed() -> void:
	var inv := _filled(40)
	var wh := _filled(40)
	var result := ToolReclaim.reclaim(_all_unlocked(), inv, wh)
	check((result.get("given", []) as Array).is_empty(), "两处都满时不得报补发成功")
	check((result.get("failed", []) as Array).size() == EXPECTED_TOOLS.size(),
		"全部都应记为失败，实际 %d" % (result.get("failed", []) as Array).size())

## 用例 7：读档自愈端到端 —— `apply_to_game_state` 之后物品真的在 `GameState` 里，且有提示。
func _test_load_self_heal() -> void:
	GameState.reset_to_defaults()
	SaveManager._last_reclaim_notice = ""
	GameState.unlocks = _all_unlocked()
	var payload := SaveManager._collect()
	check(ToolReclaim.missing_tools(payload.get("unlocks", {}),
			payload.get("inventory", []), payload.get("warehouse", [])).size() == EXPECTED_TOOLS.size(),
		"夹具本身应处于「全部缺失」状态")
	SaveManager.apply_to_game_state(payload)
	var got := _holds_any(GameState.inventory, ToolReclaim.panel_tool_ids()) \
		+ _holds_any(GameState.warehouse, ToolReclaim.panel_tool_ids())
	check(got == EXPECTED_TOOLS.size(), "读档自愈后应持有 %d 件随身工具，实际 %d"
		% [EXPECTED_TOOLS.size(), got])
	check(SaveManager._last_reclaim_notice != "", "补发后应生成读档提示（否则玩家看不懂背包为什么多了东西）")

## 用例 8：全部齐全 ⇒ 不弹提示（避免每次读档都打扰）。
func _test_no_notice_when_complete() -> void:
	GameState.reset_to_defaults()
	SaveManager._last_reclaim_notice = ""
	GameState.unlocks = _all_unlocked()
	for item_id in ToolReclaim.panel_tool_ids():
		Inventory.add(GameState.inventory, ItemFactory.make_any(item_id, 1))
	SaveManager.apply_to_game_state(SaveManager._collect())
	check(SaveManager._last_reclaim_notice == "", "全部齐全时不得弹补领提示")
