extends Node
## 工程 96：保星产物「暂时穿不上」的提示契约。
##
## 危险是「静默」的：提示写得不对，游戏照跑、保星照做，玩家只是某天一低头发现
## 背包里有件 12★ 紫装穿不上，又不知道差几级、也不知道是不是自己弄丢了。
## 所以断言压在三层：**规则层口径**（产物等级怎么算）、**UI 三层提示**（预览/确认/结果）、
## **文案正文**（不是「有没有 key」，而是「解析出来是不是那句话」）。
##
## 🔴 为什么口径层必须单独锁：`plan.required` 是**材料**等级，产物是现造的
## （`dynamic_tier_start(tier) + slot_offset`）。同档同部位时两者相等，靠的是隐含前提。
## 旧规则的逐级实例（145 级武器，`suit_start` 归到 141 档）会让材料等级比产物高 4 级 ——
## 少报的那个方向，玩家到手才发现穿不上。

const WEAPON := "c6_equip_weapon"
const OLD_TIER := 131      # 12★ 底件档
const NEW_TIER := 141      # 目标档（跨 1 档 = gap 1）
const PLAYER_LOW := 135    # 低于产物 141，差 6 级
const PLAYER_HIGH := 200   # 高于产物，穿得上
const TIER_FOR_SWEEP := 161

var failures: Array[String] = []
var _rng := RandomNumberGenerator.new()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[StarTransferLevelHintTest] " + label)

func _ready() -> void:
	_rng.seed = 20261023
	_test_output_level_matches_real_product()
	_test_output_level_ignores_stale_material()
	_test_locked_level_boundary()
	_test_text_body()
	_test_ui_preview_line()
	_test_ui_confirm_line()
	_test_ui_success_toast()
	_test_ui_worn_overlay_warning()
	_test_ui_no_hint_when_wearable()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[StarTransferLevelHintTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[StarTransferLevelHintTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 夹具 ----

## 干净状态：金币管够、面板需要的那几个全局都有值。
func _reset(level: int) -> void:
	GameState.reset_to_defaults()
	GameState.gold = 100000000
	GameState.player["level"] = level

## 12★ 底件（可放背包，也可穿身上）。
func _old_piece() -> Dictionary:
	var item := ItemFactory.make_equip_dynamic(WEAPON, OLD_TIER, "legendary", _rng)
	item.star = Upgrade.max_star()
	return item

func _new_piece() -> Dictionary:
	return ItemFactory.make_equip_dynamic(WEAPON, NEW_TIER, "legendary", _rng)

## 开保星面板并跳过拖放，直接把两件塞进材料格。
## `_on_requested` 会 `set_open(true)` → `_reset_materials()`，所以必须排在塞料之前。
func _open_panel(old: Dictionary, newer: Dictionary) -> Node:
	var panel := preload("res://scenes/ui/EquipmentFusionPanel.tscn").instantiate()
	add_child(panel)
	panel._on_requested(EquipmentFusion.STAR_TRANSFER, false)
	panel._selected[0] = old
	panel._selected[1] = newer
	panel._refresh_slots()
	panel._refresh_preview()
	return panel

func _close(panel: Node) -> void:
	panel.set_open(false)
	panel.queue_free()

# ---- 规则层 ----

## 口径契约：`transfer_output_level` 必须等于**真造出来的那件**的穿戴等级。
## 十个部位全扫 —— 只测武器会漏掉 `slot_offset` 那一半（武器偏移 0，永远对）。
func _test_output_level_matches_real_product() -> void:
	var sweep_rng := RandomNumberGenerator.new()
	sweep_rng.seed = 96
	var wrong := 0
	var detail := ""
	for kind in Equipment.slot_kinds():
		var expected := ItemFactory.dynamic_level_for(
			EquipmentFusion.template_for(TIER_FOR_SWEEP, kind), TIER_FOR_SWEEP)
		var made := EquipmentFusion.make_output(TIER_FOR_SWEEP, kind, sweep_rng)
		var claimed := EquipmentFusion.transfer_output_level(TIER_FOR_SWEEP, kind)
		if made.is_empty() or int(made.requiredLevel) != expected or claimed != expected:
			wrong += 1
			if detail.is_empty():
				detail = "%s：应为 %d，实造 %d，函数报 %d" % [
					kind, expected, int(made.get("requiredLevel", -1)), claimed]
	check(wrong == 0,
		"用例 1：产物等级口径必须与真造出来的实例一致（%d 个部位不符，首例 %s）" % [wrong, detail])
	# gift：偏移必须是 0—9 全用上，否则「十个部位差 7—16 级」这个前提就不成立。
	var levels: Array[int] = []
	for kind in Equipment.slot_kinds():
		levels.append(EquipmentFusion.transfer_output_level(TIER_FOR_SWEEP, kind))
	levels.sort()
	check(levels.size() == 10 and levels[0] == TIER_FOR_SWEEP and levels[9] == TIER_FOR_SWEEP + 9,
		"用例 1：161 档十个部位的产物等级应铺满 161—170，实际 %s" % str(levels))

## 材料是旧规则逐级件（145 级武器 → 归到 141 档）时，提示必须报**产物**的 141，
## 不能跟着材料的 145 报。`required` 保留材料语义（既有断言读它）。
func _test_output_level_ignores_stale_material() -> void:
	var old := _old_piece()
	var stale := ItemFactory.make_equip_exact(WEAPON, 145, "legendary", _rng)
	check(int(stale.get("requiredLevel", 0)) == 145, "用例 2：旧规则逐级件应为 145 级（前置）")
	var plan := EquipmentFusion.plan_transfer(old, stale)
	check(bool(plan.get("ok", false)), "用例 2：145 级 0★ 紫装应可作目标件，实际 %s" % str(plan))
	check(int(plan.get("required", 0)) == 145, "用例 2：required 保留材料等级 145（语义不动）")
	check(int(plan.get("outputLevel", 0)) == 141,
		"用例 2：产物等级应为 141，实际 %d（跟着材料报 145 就是错的口径）" % int(plan.get("outputLevel", -1)))

## 判据边界：等于可穿、高一级不可穿；差值为 0 表示「不提示」。
func _test_locked_level_boundary() -> void:
	check(EquipmentFusion.transfer_locked_level(141, 135) == 141, "用例 3：135 级面对 141 产物应提示 141")
	check(EquipmentFusion.transfer_locked_level(141, 140) == 141, "用例 3：差 1 级也要提示")
	check(EquipmentFusion.transfer_locked_level(141, 141) == 0, "用例 3：刚好够级不该提示")
	check(EquipmentFusion.transfer_locked_level(141, 200) == 0, "用例 3：超过门槛不该提示")

## 文案正文：四条都要能带参解析出预期正文。只断「key 存在」抓不到
## `%d` 个数与传参不符导致的 `incomplete format`（会原样返回带 % 的模板，测试照常 PASS）。
func _test_text_body() -> void:
	var preview := Localization.tr_key("ui.fusion.out_level", [141, 135, 6])
	check(preview.contains("Lv141") and preview.contains("Lv135") and preview.contains("还差 6 级")
		and not preview.contains("%"), "用例 4：预览文案应解析出 141/135/6，实际「%s」" % preview)
	var confirm := Localization.tr_key("ui.fusion.out_level_confirm", [141, 135, 6])
	check(confirm.contains("Lv141") and confirm.contains("等 6 级") and not confirm.contains("%"),
		"用例 4：确认文案应解析出等 6 级，实际「%s」" % confirm)
	var done := Localization.tr_key("ui.fusion.done_locked", ["测试之刃", 141])
	check(done.contains("测试之刃") and done.contains("需 Lv141") and not done.contains("%"),
		"用例 4：成功文案应带产物名与门槛，实际「%s」" % done)
	var worn := Localization.tr_key("ui.fusion.worn_locked_warning", ["测试之靴", 141])
	check(worn.contains("测试之靴") and worn.contains("Lv141") and worn.contains("少一件装备")
		and not worn.contains("%"), "用例 4：叠加警告应含部位名/门槛/掉战力，实际「%s」" % worn)

# ---- UI 层 ----

## P1：预览行必须是独立高亮行，且带「还差 X 级」的差值。
func _test_ui_preview_line() -> void:
	_reset(PLAYER_LOW)
	var old := _old_piece()
	var newer := _new_piece()
	GameState.inventory[0] = old
	GameState.inventory[1] = newer
	var panel := _open_panel(old, newer)
	check(panel._out_level.text.contains("Lv141") and panel._out_level.text.contains("还差 6 级"),
		"用例 5：预览行应提示产物 141、差 6 级，实际「%s」" % panel._out_level.text)
	check(not panel._summary.text.contains("Lv141"),
		"用例 5：提示不该再拼进 _summary（那里是四个模式共用的）")
	# R7：提示是告知，**不许**变成拦截。按钮只受金币影响。
	check(not panel._confirm.disabled, "用例 5：穿不上不得禁用确认按钮（金币充足）")
	# 撤料后必须清空，否则切换服务会留下上一轮的残留。
	panel._selected[1] = {}
	panel._refresh_slots()
	panel._refresh_preview()
	check(panel._out_level.text.is_empty(), "用例 5：撤下材料后提示必须清空")
	_close(panel)

## P2：二次确认是玩家真正做决定的时刻，必须再提一次；且第一次点击只提示、不消耗。
func _test_ui_confirm_line() -> void:
	_reset(PLAYER_LOW)
	var old := _old_piece()
	var newer := _new_piece()
	GameState.inventory[0] = old
	GameState.inventory[1] = newer
	var panel := _open_panel(old, newer)
	var used_before := GameState.inventory_used()
	panel._on_confirm()
	check(panel._feedback.text.contains("Lv141") and panel._feedback.text.contains("等 6 级"),
		"用例 6：确认区应提示产物 141、等 6 级，实际「%s」" % panel._feedback.text)
	check(GameState.inventory_used() == used_before,
		"用例 6：第一次点击只提示，材料不该被消耗（%d → %d）" % [used_before, GameState.inventory_used()])
	_close(panel)

## P3：成功 toast 必须带门槛；且用的是**产物实际等级**，不是预览时的预估。
func _test_ui_success_toast() -> void:
	_reset(PLAYER_LOW)
	var old := _old_piece()
	var newer := _new_piece()
	GameState.inventory[0] = old
	GameState.inventory[1] = newer
	var panel := _open_panel(old, newer)
	var toasts: Array[String] = []
	var capture := func(text: String, _kind: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(capture)
	panel._on_confirm()   # 第一次：确认
	panel._on_confirm()   # 第二次：执行
	EventBus.toast_requested.disconnect(capture)
	check(toasts.size() == 1, "用例 7：应恰好一条成功 toast，实际 %d 条" % toasts.size())
	if toasts.size() == 1:
		check(toasts[0].contains("需 Lv141"),
			"用例 7：产物穿不上时 toast 必须带门槛，实际「%s」" % toasts[0])
	check(GameState.inventory_used() == 1,
		"用例 7：两件换一件，背包应剩 1 件，实际 %d" % GameState.inventory_used())
	_close(panel)

## P4：身上件被吃 + 产物穿不上 = 该部位净空一件，必须用强化文案而不是普通「会空出来」。
func _test_ui_worn_overlay_warning() -> void:
	_reset(PLAYER_LOW)
	var old := _old_piece()
	var newer := _new_piece()
	GameState.equipment["weapon"] = old
	GameState.inventory[0] = newer
	var panel := _open_panel(old, newer)
	panel._on_confirm()
	check(panel._feedback.text.contains("Lv141") and panel._feedback.text.contains("少一件装备"),
		"用例 8：身上件被吃且产物穿不上时，应告警「会少一件装备」，实际「%s」" % panel._feedback.text)
	_close(panel)

## 穿得上就一句都别多说 —— 提示不该在正常的同档保星里常驻。
func _test_ui_no_hint_when_wearable() -> void:
	_reset(PLAYER_HIGH)
	var old := _old_piece()
	var newer := _new_piece()
	GameState.inventory[0] = old
	GameState.inventory[1] = newer
	var panel := _open_panel(old, newer)
	check(panel._out_level.text.is_empty(),
		"用例 9：200 级穿得上时预览行应为空，实际「%s」" % panel._out_level.text)
	panel._on_confirm()
	check(not panel._feedback.text.contains("Lv141"),
		"用例 9：穿得上时确认区不该提等级，实际「%s」" % panel._feedback.text)
	_close(panel)
