extends Node
## 工程 80：随身三件套「能拖上快捷栏」+ 车夫 / 令牌面板布局收敛。
##
## 四组最值钱的断言：
## 1. **用例 2 钉死「放行口径与执行层同源」** —— 口径一旦放宽到「useType 非空」，
##    `revive` / `quest` / `playAnimation` 也能拖上去，点下去弹「该物品无法使用」，
##    那是做出一个假功能；这条线必须常红常绿分明。
## 2. **用例 4 钉死「三件工具格内可辨识」** —— 它们都没有图标资源，
##    拿不到图就显示名称首字 ⇒ 「随身车夫」「随身商队」两个字都是「随」，快捷栏上分不清。
## 3. **用例 6 钉死「折叠只改可见性、不改统计口径」** —— `row_count()` 是统计锚点（35），
##    折叠后它一旦变小，就是拿 UI 状态冒充业务口径。
## 4. **用例 9 钉死「过滤不回写规则层」** —— `BossToken.rows()` 恒 137（BossTokenTest 的锚点），
##    UI 侧过滤只能做视图裁剪。

## 工程 108：加第四件。本测试的多数用例遍历这张表，不加 = 新工具无人覆盖。
const TOOLS := ["tool_portable_carter", "tool_portable_shop", "tool_boss_token",
	"tool_portable_blacksmith"]
const CAMP := "camp"

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PortableToolsHotbarTest] " + label)

func _ready() -> void:
	_test_tools_draggable()
	_test_unimplemented_types_rejected()
	_test_unknown_ids_rejected()
	_test_short_labels_distinct()
	_test_panel_tools_hide_count()
	_test_missing_hint_distinguishes_warehouse()
	_test_carter_folding()
	_test_carter_default_expands_level_group()
	_test_token_rows_untouched()
	_test_token_filter_and_accordion()
	_test_filter_is_pure_view_clip()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[PortableToolsHotbarTest] 全部通过 ✅")
	else:
		for failure in failures:
			print("[PortableToolsHotbarTest] 失败：" + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- 用例 1—3：放行口径 ----

func _test_tools_draggable() -> void:
	for id in TOOLS:
		var entry := {"kind": "item", "id": id}
		check(HotbarConfig.valid_entry(entry), "随身工具 " + id + " 应可拖上快捷栏")
		var item := {"kind": "misc", "itemId": id}
		var built := HotbarConfig.entry_for_item(item)
		check(String(built.get("id", "")) == id and String(built.get("kind", "")) == "item",
			"entry_for_item 应为 " + id + " 生成 item 绑定，实际 " + str(built))
	# 与执行层同源：`PanelRouter` 必须真的接得住这三个 panelId，否则拖上去也是死格子。
	for id in TOOLS:
		var tpl: Variant = DataLoader.get_entry("miscItems", id)
		check(tpl is Dictionary, id + " 应在 miscItems 表里")
		var panel_id := String((tpl as Dictionary).get("panelId", ""))
		check(PanelRouter.has(panel_id), "panelId " + panel_id + " 必须已在 PanelRouter 注册")
		check(PanelRouter.is_ready(panel_id),
			"面板 " + panel_id + " 必须 ready（拖上去点得开，否则是死格子）")

## 🔴 假功能防线：`_use_misc` 没实现的 useType 一律不许拖上去。
func _test_unimplemented_types_rejected() -> void:
	var rejected: Array[String] = []
	for entry in DataLoader.get_table("miscItems"):
		if not entry is Dictionary:
			continue
		var d: Dictionary = entry
		var id := String(d.get("id", ""))
		var use_type := String(d.get("useType", ""))
		if use_type.is_empty() or HotbarConfig.USABLE_TYPES.has(use_type):
			continue
		var built := HotbarConfig.entry_for_item({"kind": "misc", "itemId": id})
		if not built.is_empty():
			rejected.append(id + "(" + use_type + ")")
	check(rejected.is_empty(), "未实现的 useType 不得拖上快捷栏：%s" % str(rejected))

func _test_unknown_ids_rejected() -> void:
	check(not HotbarConfig.valid_entry({"kind": "item", "id": "__nonexistent__"}),
		"不存在的杂项 id 不得通过 valid_entry")
	check(not HotbarConfig.valid_entry({"kind": "item"}),
		"缺字段的绑定不得通过 valid_entry")
	check(HotbarConfig.entry_for_item({"kind": "misc", "itemId": "__nonexistent__"}).is_empty(),
		"不存在的杂项应得到空绑定")

# ---- 用例 4：格内辨识（两个「随」的问题）----

func _test_short_labels_distinct() -> void:
	var seen: Dictionary = {}
	for id in TOOLS:
		var label := HotbarVisual.short_label({"kind": "item", "id": id})
		check(not label.is_empty(), id + " 必须有格内简称（否则会退化成名称首字）")
		check(label.length() <= 2, id + " 简称应不超过 2 字（42px 格子放不下）：" + label)
		check(not seen.has(label), "简称「" + label + "」重复，快捷栏上分不清（" + str(seen) + "）")
		seen[label] = id
	check(seen.size() == TOOLS.size(), "三件工具应有三个互不相同的简称，实际 " + str(seen))
	# 非工具物品不应被误改（回退空串 ⇒ 沿用名称首字）
	check(HotbarVisual.short_label({"kind": "item", "id": "misc_town_scroll"}).is_empty(),
		"非随身工具应回退空串（沿用名称首字）")

# ---- 用例 5：角标 ----

func _test_panel_tools_hide_count() -> void:
	for id in TOOLS:
		check(not HotbarVisual.shows_count({"kind": "item", "id": id}),
			"随身工具 " + id + " 不消耗，不应显示数量角标")
	check(HotbarVisual.shows_count({"kind": "item", "id": "misc_town_scroll"}),
		"回城卷是消耗品，应显示数量角标")
	check(not HotbarVisual.shows_count({"kind": "skill", "id": "basic_slash"}),
		"技能不应显示数量角标")

# ---- 用例 6：缺件提示要区分「不在背包」与「在仓库」----

func _test_missing_hint_distinguishes_warehouse() -> void:
	var binding := {"kind": "item", "id": "tool_portable_carter"}
	var not_owned := HotbarVisual.missing_item_hint(binding, false)
	var in_warehouse := HotbarVisual.missing_item_hint(binding, true)
	check(not_owned != in_warehouse, "两种缺件情形必须给不同提示（否则玩家不知道东西在哪儿）")
	check(in_warehouse.contains("仓库"), "在仓库时提示必须点明仓库：" + in_warehouse)
	check(not not_owned.contains("仓库"), "不在背包也不在仓库时不应提仓库：" + not_owned)

# ---- 用例 7—8：车夫面板折叠 ----

func _prepare_all_visited(level: int) -> void:
	GameState.reset_to_defaults()
	GameState.gold = 999999
	GameState.player.level = level
	GameState.current_map = CAMP
	for entry in DataLoader.get_table("maps"):
		if entry is Dictionary:
			GameState.mark_visited(String((entry as Dictionary).get("id", "")))

func _open_carter(level: int) -> Control:
	_prepare_all_visited(level)
	var panel: Control = load("res://scripts/ui/carter_panel.gd").new()
	add_child(panel)
	panel._portable = true
	panel.set_open(true)
	return panel

func _test_carter_folding() -> void:
	var panel := _open_carter(70)
	var total: int = panel.row_count()
	check(total > 0, "车夫应有目的地行")
	check(panel.section_keys().size() == 7, "随身车夫应渲染 7 个分组，实际 %d" % panel.section_keys().size())
	var visible: int = panel.visible_row_count()
	check(visible < total, "默认视图应折叠（可见 %d < 总数 %d），否则 35 行全摊平要滚 3 屏" % [visible, total])
	check(visible > 0, "默认视图至少展开一组，不该全收起")
	# 全展开后可见 == 统计口径 ⇒ 折叠确实只是「不建这些行」
	for key in panel.section_keys():
		if panel.is_collapsed(key):
			panel.toggle_section(key)
	check(panel.visible_row_count() == total,
		"全部展开后可见行数应等于 row_count（%d vs %d）" % [panel.visible_row_count(), total])
	# 收起全部
	for key in panel.section_keys():
		if not panel.is_collapsed(key):
			panel.toggle_section(key)
	check(panel.visible_row_count() == 0, "全部收起后可见行数应为 0")
	check(panel.row_count() == total,
		"🔴 折叠不得改变 row_count 统计口径（%d → %d）" % [total, panel.row_count()])
	panel.queue_free()

## 默认展开组必须跟着玩家等级走：70 级该开「51-60」和「60+」，7 级该开「1-10」和「60+」。
func _test_carter_default_expands_level_group() -> void:
	var high := _open_carter(70)
	check(not high.is_collapsed("51-60"), "70 级应默认展开「51-60」组")
	check(not high.is_collapsed("60+"), "任何等级都应默认展开「60+」循环组")
	check(high.is_collapsed("1-10"), "70 级不该默认展开「1-10」组")
	high.queue_free()
	var low := _open_carter(7)
	check(not low.is_collapsed("1-10"), "7 级应默认展开「1-10」组")
	check(low.is_collapsed("41-50"), "7 级不该默认展开「41-50」组")
	low.queue_free()

# ---- 用例 9—10：令牌面板 ----

func _open_token(map_id: String) -> Control:
	_prepare_all_visited(70)
	GameState.current_map = map_id
	var panel: Control = load("res://scripts/ui/boss_token_panel.gd").new()
	add_child(panel)
	panel.set_open(true)
	return panel

func _test_token_rows_untouched() -> void:
	var before := BossToken.rows().size()
	var panel := _open_token(CAMP)
	var after := BossToken.rows().size()
	check(before == after and before > 0,
		"🔴 过滤 / 折叠不得回写规则层：rows() %d → %d" % [before, after])
	check(panel.visible_row_count() <= after,
		"可见行数不得超过规则层行数（%d > %d）" % [panel.visible_row_count(), after])
	check(panel.visible_row_count() < after,
		"默认视图应折叠掉百席图的行（可见 %d vs 规则层 %d）" % [panel.visible_row_count(), after])
	panel.queue_free()

func _test_token_filter_and_accordion() -> void:
	var panel := _open_token("c7_boss_field")
	check(panel.expanded_group() != "", "站在 c7_boss_field 上应默认展开它的 A 组")
	# 手风琴：展开 B 组 ⇒ A 组必须收起，同时最多一组
	var first: String = panel.expanded_group()
	panel.toggle_group("c7_boss_field|B")
	check(panel.expanded_group() == "c7_boss_field|B", "点击 B 组应展开 B")
	check(panel.expanded_group() != first,
		"🔴 手风琴失效：展开新组后旧组仍展开，同时多组会 +100 行")
	# 再点一次收起
	panel.toggle_group("c7_boss_field|B")
	check(panel.expanded_group() == "", "再次点击同一组应收起")
	# 过滤切换不回写规则层
	var all_rows := BossToken.rows().size()
	panel.set_filter(panel.FILTER_ALIVE)
	check(panel.filter_mode() == panel.FILTER_ALIVE, "过滤档位应切到「仅存活」")
	check(BossToken.rows().size() == all_rows,
		"🔴 切换过滤不得改变 rows()（%d → %d）" % [all_rows, BossToken.rows().size()])
	panel.set_filter(panel.FILTER_COOLDOWN)
	check(BossToken.rows().size() == all_rows, "切换「冷却中」同样不得改变 rows()")
	panel.set_filter(panel.FILTER_ALL)
	check(panel.visible_row_count() <= all_rows, "回到「全部」后可见行数仍不得超过规则层")
	panel.queue_free()

## 过滤必须真的裁剪（否则过滤条只是摆设）。用合成两行直接打纯函数，
## 不依赖真实冷却数据 —— 全库 Boss 都存活时 `visible_row_count` 三档一样，看不出差异。
func _test_filter_is_pure_view_clip() -> void:
	var panel := _open_token(CAMP)
	var rows: Array[Dictionary] = [
		{"map_id": "m1", "group": "", "alive": true},
		{"map_id": "m2", "group": "", "alive": false},
	]
	panel.set_filter(panel.FILTER_ALL)
	check(panel._apply_filter(rows).size() == 2, "「全部」档应保留全部行")
	panel.set_filter(panel.FILTER_ALIVE)
	var alive_only: Array = panel._apply_filter(rows)
	check(alive_only.size() == 1 and bool((alive_only[0] as Dictionary).get("alive", false)),
		"🔴 过滤失效：「仅存活」应只剩存活行，实际 %d 行" % alive_only.size())
	panel.set_filter(panel.FILTER_COOLDOWN)
	var cooldown_only: Array = panel._apply_filter(rows)
	check(cooldown_only.size() == 1 and not bool((cooldown_only[0] as Dictionary).get("alive", true)),
		"「冷却中」应只剩冷却行，实际 %d 行" % cooldown_only.size())
	# 纯函数不得改写入参（视图裁剪 ≠ 就地过滤）
	check(rows.size() == 2, "过滤不得修改传入的数组（视图裁剪，不是就地过滤）")
	panel.queue_free()
