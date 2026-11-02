extends Node
## 高窗口重铸正式回归：151候选、四紫装、四钻石如意，阈值窗口中布局须收敛且不重复交易。
var failures: Array[String] = []

## 聚合布局及交易契约；测试运行于独立项目user目录。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 等待真实容器与按帧调度完成，保留窗口渲染与无头逻辑两种验证入口。
func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

## 固定种子生成候选，目标每轮重新创建，覆盖首次解锁第五条导致的长结果文案。
func prepare() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 700
	GameState.gold = 1000000000
	GameState.inventory = Inventory.create(200)
	var rng := RandomNumberGenerator.new()
	rng.seed = 78912
	for i in range(150):
		GameState.inventory[i] = ItemFactory.make_equip_exact("c6_equip_weapon",500,"legendary",rng)
	GameState.equipment.weapon = ItemFactory.make_equip_exact("c6_equip_weapon",500,"legendary",rng)
	GameState.equipment.weapon.star = 12
	GameState.inventory[150] = ItemFactory.make_any("rune_diamond",4)

## 在四个阈值高度逐轮打开真实重铸/背包，检查最终尺寸稳定和结果可滚动阅读。
func _ready() -> void:
	get_window().content_scale_size = Vector2i.ZERO
	for height in [800,940,960,1200]:
		get_window().size = Vector2i(1280,height)
		prepare()
		var bag: Control = load("res://scenes/ui/InventoryPanel.tscn").instantiate()
		var panel: Control = load("res://scenes/ui/ReforgePanel.tscn").instantiate()
		add_child(bag)
		add_child(panel)
		panel.set_open(true)
		await frames(20)
		var picked := -1
		for i in range(panel._choices.size()):
			if panel._choices[i].source == "worn" and panel._choices[i].key == "weapon":
				picked = i
		check(picked >= 0 and panel._choices.size() == 151, "大候选夹具有效")
		panel.select_choice(picked)
		for i in range(4):
			panel.drop_refine_material(i,i)
		panel._auto_runes.pressed.emit()
		await frames(5)
		check(panel.refine_materials().size() == 4 and panel._rune_choices.count("rune_diamond") == 4, "四件材料和四如意真实预选")
		panel._button.pressed.emit()
		await frames(30)
		check(panel._feedback.text.contains(Localization.tr_key("msg.reforge.p015",[17])), "真实交易完成17次取优")
		check(GameState.inventory[150] == null, "四枚钻石如意恰好消耗一次")
		var box: Control = panel._box
		var scroll: ScrollContainer = panel._scroll
		var settled := Vector4(box.size.x,box.size.y,scroll.custom_minimum_size.x,scroll.custom_minimum_size.y)
		for i in range(12):
			await frames(1)
			check(settled.is_equal_approx(Vector4(box.size.x,box.size.y,scroll.custom_minimum_size.x,scroll.custom_minimum_size.y)), "布局连续12帧稳定 高度%d" % height)
		check(box.size.y <= height + 1, "外框不超过窗口")
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await frames(3)
		check(panel._feedback.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1, "结果完整可滚动阅读")
		if DisplayServer.get_name() != "headless":
			RenderingServer.force_draw(false)
			get_viewport().get_texture().get_image().save_png("/tmp/reforge_layout_%d.png" % height)
		panel.set_open(false)
		bag.set_open(false)
		panel.queue_free()
		bag.queue_free()
		await frames(3)
	print("[ReforgeLayoutStabilityTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
