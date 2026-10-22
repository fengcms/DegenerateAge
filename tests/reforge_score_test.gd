extends Node
## 工程 90：重铸面板显示装备评分（当前值 + 与上一次重铸的差值）—— 8 组用例。
##
## 四条最值钱的断言：
## 1. **用例 1/2 用 `Equipment.score` 的返回值当判据** —— 面板若自己算一遍（例如按基底累加），
##    数值会与背包浮层分裂，玩家看到「面板 166.4 / 浮层 172.0」。
## 2. **用例 3/4 断的是文案里的差值本身**（`+22.8` / `-9.3` 逐字符比对），不是「调用过刷新」。
##    基准写错位置（例如放进 `_refresh_details`）时，界面会永远显示「持平」——这种错极易假绿。
## 3. **用例 6 必须双向断**：破损件评分 == `Equipment.score(破损件)` **且严格小于**满耐久评分。
##    只断前者，「把基底砍光」也绿；只断后者，「用满耐久分冒充」也绿（工程 88 用例 6 同型）。
## 4. **用例 8 断面板高度 ≤ 逻辑视口**：uiScale 2.0 时可用高只有 640，而面板自然高 623+；
##    不接 F-P2-3 内容滚动就必然出屏，且没有滚动条可救。

const PANEL_SCENE := preload("res://scenes/ui/ReforgePanel.tscn")

var failures: Array[String] = []
var _panel: Variant = null

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ReforgeScoreTest] " + label)

func _ready() -> void:
	_test_score_shown()
	_test_score_follows_selection()
	_test_delta_after_reforge()
	_test_baseline_advances()
	_test_baseline_cleared_on_close()
	_test_broken_item()
	_test_empty_state()
	await _test_no_overflow()
	GameState.reset_to_defaults()
	GameState.settings["uiScale"] = 1.0
	if failures.is_empty():
		print("[ReforgeScoreTest] 全部通过 ✅")
	else:
		for failure in failures:
			print("[ReforgeScoreTest] 失败：" + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- 工具 ----

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

## 与 `ReforgeLockTest` 同规格：51—60 档走 roll（挂模板所属套），保证有词条可重掷。
func _make(item_id: String, quality: String, seed_value: int) -> Dictionary:
	return ItemFactory.make_equip_roll(item_id, ItemFactory.tier_start_for_template(item_id),
		quality, _rng(seed_value))

func _clear_equipment() -> void:
	for slot in Equipment.SLOT_DEFS:
		GameState.equipment[String(slot.id)] = null

func _clear_bag() -> void:
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null

## 每个用例的干净起点：清穿戴 + 清背包 + 给足金币，再重开面板刷新候选。
func _reset(item_list: Array) -> void:
	GameState.reset_to_defaults()
	_clear_equipment()
	_clear_bag()
	GameState.gold = 5000000
	for i in range(item_list.size()):
		GameState.inventory[i] = item_list[i]
	_open_panel()
	_panel.set_open(false)
	_panel.set_open(true)

func _open_panel() -> void:
	if _panel != null:
		return
	_panel = PANEL_SCENE.instantiate()
	add_child(_panel)
	_panel.set_open(true)

func _score_label() -> Label:
	return _panel.get("_score") as Label

func _score_text() -> String:
	var label := _score_label()
	return label.text if label != null else ""

func _note_visible() -> bool:
	var label: Label = _panel.get("_score_note") as Label
	return label != null and label.visible

## 一位小数归一（与面板内部同约定，但**本函数是独立实现**：不复用被测代码的常量，
## 否则归一规则被改坏时两边一起变、断言照绿）。
func _round1(value: float) -> float:
	return roundf(value * 10.0) / 10.0

func _signed(value: float) -> String:
	return ("+%.1f" % value) if value > 0.0 else ("%.1f" % value)

## 期望文案：`较上次 ±N` 或 `与上次持平`。
func _expect_delta(from_score: float, to_score: float) -> String:
	var delta := _round1(to_score) - _round1(from_score)
	if absf(delta) < 0.005:
		return Localization.tr_key("ui.reforge_panel.p026")
	return Localization.tr_key("ui.reforge_panel.p025") % _signed(delta)

# ---- 用例 ----

## 1. 选中装备后评分行可见，文字与 `Equipment.score` 一致（且 key 真解析出「评分」两个字）。
func _test_score_shown() -> void:
	var item := _make("c6_equip_necklace", "legendary", 9001)
	_reset([item])
	var expect := Localization.tr_key("ui.equip_tip.score", [_round1(Equipment.score(item))])
	check(_score_label() != null and _score_label().visible, "选中装备后评分行必须可见")
	# 字面断言：key 撞号（后者静默胜出）时这里才会红。
	check(_score_text().contains("评分"), "评分文案必须真解析出「评分」，实际「%s」" % _score_text())
	check(_score_text().begins_with(expect), "评分应为「%s」，实际「%s」" % [expect, _score_text()])

## 2. 换装备后数字跟着变（两件评分不同，逐个对得上）。
func _test_score_follows_selection() -> void:
	var a := _make("c6_equip_necklace", "legendary", 9002)
	var b := _make("c6_equip_weapon", "rare", 9003)
	_reset([a, b])
	_panel.select_choice(0)
	check(_score_text().begins_with(Localization.tr_key("ui.equip_tip.score", [_round1(Equipment.score(a))])),
		"选第一件时评分应与之一致，实际「%s」" % _score_text())
	_panel.select_choice(1)
	check(_score_text().begins_with(Localization.tr_key("ui.equip_tip.score", [_round1(Equipment.score(b))])),
		"换到第二件后评分必须跟着变，实际「%s」" % _score_text())

## 3. 重铸成功后出现「较上次」/「与上次持平」，且差值与实际评分变化逐字符一致。
func _test_delta_after_reforge() -> void:
	var item := _make("c6_equip_necklace", "legendary", 9004)
	_reset([item])
	_panel.select_choice(0)
	var before := Equipment.score(GameState.inventory[0])
	_panel._on_reforge()
	var after := Equipment.score(GameState.inventory[0])
	var expect := _expect_delta(before, after)
	check(_score_text().contains(expect),
		"重铸后应显示「%s」（%.1f → %.1f），实际「%s」" % [
			expect, before, after, _score_text()])
	check(_score_text().begins_with(Localization.tr_key("ui.equip_tip.score", [_round1(after)])),
		"重铸后绝对值必须是**新**评分 %.1f，实际「%s」" % [after, _score_text()])

## 4. 连续两次重铸：第二次的基准是第一次**之后**的值（不是最初值）。
func _test_baseline_advances() -> void:
	var item := _make("c6_equip_necklace", "legendary", 9005)
	_reset([item])
	_panel.select_choice(0)
	# 先掷到一次「评分真的变了」的重铸，否则 c−a 与 c−b 恰好相等，本用例退化成空断言。
	var a := Equipment.score(GameState.inventory[0])
	var b := a
	for _i in range(6):
		_panel._on_reforge()
		b = Equipment.score(GameState.inventory[0])
		if absf(_round1(b) - _round1(a)) >= 0.1:
			break
	check(absf(_round1(b) - _round1(a)) >= 0.1,
		"前置条件不满足：6 次重铸都没改变评分（%.1f），本用例无法区分基准新旧" % a)
	_panel._on_reforge()
	var c := Equipment.score(GameState.inventory[0])
	check(_score_text().contains(_expect_delta(b, c)),
		"第二次重铸的基准应是第一次之后 %.1f（而非最初 %.1f），实际「%s」" % [b, a, _score_text()])

## 5. 关面板再打开：增量消失，只剩绝对值（基准不跨会话）。
func _test_baseline_cleared_on_close() -> void:
	var item := _make("c6_equip_necklace", "legendary", 9006)
	_reset([item])
	_panel.select_choice(0)
	_panel._on_reforge()
	_panel.set_open(false)
	_panel.set_open(true)
	var text := _score_text()
	check(not text.contains(Localization.tr_key("ui.reforge_panel.p025")),
		"重开面板后不应再显示「较上次」，实际「%s」" % text)
	check(not text.contains(Localization.tr_key("ui.reforge_panel.p026")),
		"重开面板后不应再显示「与上次持平」，实际「%s」" % text)
	check(text.contains("评分"), "重开面板后仍要显示当前评分，实际「%s」" % text)

## 6. 破损件：评分按基底算（严格低于满耐久），并出现「词条不生效」提示。
func _test_broken_item() -> void:
	var item := _make("c6_equip_necklace", "legendary", 9007)
	var repaired := item.duplicate(true)
	repaired["durability"] = Durability.max_durability()
	item["durability"] = 0
	check(Durability.is_broken(item), "前置：durability=0 应判定为破损")
	var broken_score := Equipment.score(item)
	var full_score := Equipment.score(repaired)
	# 这次顺序要反：`_reset` 里 reset_to_defaults 会重建物品，故先重置再塞破损件。
	_reset([item])
	GameState.inventory[0] = item
	_panel.set_open(false)
	_panel.set_open(true)
	check(_score_text().begins_with(Localization.tr_key("ui.equip_tip.score", [_round1(broken_score)])),
		"破损件评分应为基底分 %.1f，实际「%s」" % [broken_score, _score_text()])
	check(broken_score < full_score,
		"前置：满耐久评分必须更高（基底 %.1f / 满耐久 %.1f），否则本用例没有牙" % [
			broken_score, full_score])
	check(_note_visible(), "破损件必须显示「词条不生效，评分只含基底」提示")
	var note: Label = _panel.get("_score_note") as Label
	check(note != null and note.text.contains("词条不生效"),
		"破损提示正文不对，实际「%s」" % (note.text if note != null else "无"))

## 7. 无候选装备：评分行整行隐藏（不显示 0.0）。
func _test_empty_state() -> void:
	_reset([])
	var label := _score_label()
	check(label != null and not label.visible, "无候选装备时评分行必须隐藏，不能显示 0.0")
	check(not _note_visible(), "无候选装备时破损提示也必须隐藏")

## 8. 内容超出可用区时面板不顶穿，且出现纵向滚动条（F-P2-3）。
## 🔴 不能只断「当前自然高 623 < 可用高 640」—— 那只差 17px，「根本没接滚动」也会绿。
## 这里两件事一起做：① 把面板根控件压到 640×640（等价于 uiScale 2.0 下的逻辑视口，
## 真实运行时 `apply_ui_scale_to` 就是这么设的）；② 往内容区塞 400px 占位，
## 制造「以后又加了一个区块」的复发形态。
func _test_no_overflow() -> void:
	var item := _make("c6_equip_necklace", "legendary", 9008)
	_reset([item])
	var content: Control = _panel.get("_content") as Control
	var scroll: ScrollContainer = _panel.get("_scroll") as ScrollContainer
	check(content != null and scroll != null, "内容区与滚动容器必须存在")
	if content == null or scroll == null:
		return
	# 逻辑视口 640×640（= 1280 物理 / uiScale 2.0）。未缩放时 Control 的 size 由视口撑满，
	# 手动设定后不会被重算 —— 同步调 `_resize()` 让它按这个尺寸收敛。
	var logical := Vector2(640.0, 640.0)
	_panel.size = logical
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 400)
	content.add_child(pad)
	await get_tree().process_frame
	_panel._resize()
	for _i in range(4):
		await get_tree().process_frame
	var box: Control = _panel.get("_box") as Control
	check(box != null, "面板外框必须存在")
	if box != null:
		# 两侧夹逼：上界「不许顶穿」，下界「内容超高时也不许塌掉」。
		# 🔴 只断上界会被「塌成 103px」骗过 —— 塌掉当然也不超限，但玩家什么都点不到。
		check(box.size.y <= logical.y + 0.5,
			"内容超高时面板必须收敛到可用高 %.1f，实际 %.1f（未接内容滚动？）" % [
				logical.y, box.size.y])
		check(box.size.y >= logical.y - PanelChrome.HEADER_BAND_BOTTOM - 4.0,
			"内容超高时面板必须撑满可用区（≥ %.1f），实际 %.1f —— 塌掉说明内容滚动没接上" % [
				logical.y - PanelChrome.HEADER_BAND_BOTTOM - 4.0, box.size.y])
	# 🔴 只断「高度 ≤ 可用高」不够：撤掉 `set_content_scroll` 后面板会塌成 103px（比可用高还小），
	# 上限断言照样绿。真正要断的是「内容被压进了可视区」——压缩前 scroll 尺寸应严格小于内容自然高。
	check(scroll.size.y + 0.5 < content.get_combined_minimum_size().y,
		"内容必须被压缩进可视区（滚动区 %.1f vs 内容自然高 %.1f）" % [
			scroll.size.y, content.get_combined_minimum_size().y])
	check(scroll.get_v_scroll_bar().visible,
		"内容超出可用区时必须出现纵向滚动条，否则底部按钮永远点不到")
	pad.queue_free()
