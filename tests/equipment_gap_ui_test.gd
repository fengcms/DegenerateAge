extends Node
## 新规则UI与出售保护：真实Boss显示、换装提示恢复，低分高等级过渡装按原有限额度保留。
var failures: Array[String] = []

## 收集失败，测试不读写真实存档。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

## 从真实模板构造等级/品质夹具，词条随机固定。
func item(kind: String, level: int, quality: String, star: int = 0) -> Dictionary:
	var rng:=RandomNumberGenerator.new()
	rng.seed=3101+level
	var id:=EquipmentFusion.template_for(511,kind)
	var result:=ItemFactory.make_equip_exact(id,level,quality,rng)
	result.star=star
	return result

## 先在真实Main复核事件与提示，再以纯规则验证不会无限保留替代品。
func _ready() -> void:
	get_window().content_scale_size = Vector2i.ZERO
	get_window().size = Vector2i(1280,1200)
	GameState.reset_to_defaults("mage")
	GameState.player.level=517
	GameState.current_map="c7_boss_field"
	GameState.menu_mode="world"
	for slot in Equipment.SLOT_DEFS:
		GameState.equipment[slot.id]=item(slot.kind,450,"legendary",12)
	GameState.player.hp=GameState.max_hp()
	GameState.player.mp=GameState.max_mp()
	var main:=preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	var world:=main.get_node("Game")
	world.get_node("Spawner").set_process(false)
	for existing in get_tree().get_nodes_in_group("enemies"):
		existing.set_physics_process(false)
		existing.hide()
	var player:=world.get_node("Entities/Player") as PlayerCharacter
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	var boss:=preload("res://scenes/entities/Monster.tscn").instantiate() as Monster
	boss.monster_id="c6_boss03"
	boss.spawn_level=517
	boss.ai_enabled=false
	world.get_node("Entities").add_child(boss)
	boss.position=player.position+Vector2(80,0)
	boss.set_physics_process(false)
	boss._announce_boss_hp()
	var bar:=main.get_node("UI/BossHealthBar")
	check(bar.bar_state(boss.get_instance_id()).get("level")==517,"Boss条用真实目标等级")
	check(String(bar.bar_state(boss.get_instance_id()).get("gap_text","")).contains("19.6"),"Boss持续显示实际装备影响")
	await check_character_layout(main, player, boss)
	var fresh:=item("weapon",510,"common")
	check(Equipment.score(fresh)<Equipment.score(GameState.equipment.weapon),"夹具确实是低分高等级过渡装")
	var inv:=main.get_node("UI/InventoryPanel")
	GameState.inventory[0] = fresh
	inv.set_open(true)
	var source: ItemSlot = inv._bag_buttons[0]
	var card:=source._make_custom_tooltip("fallback") as Control
	check(text_of(card).contains("跨级预览"),"实际结构化对比卡也显示预览")
	main.get_node("UI").add_child(card)
	boss.level=450
	player.select_target(boss,false)
	check(not text_of(card).contains("跨级预览"),"悬停时切到低级目标即时清除旧预览")
	boss.level=517
	player.select_target(boss,false)
	check(text_of(card).contains("跨级预览"),"切回高级目标重新显示实际影响")
	if DisplayServer.get_name()!="headless":
		source.hide()
		card.position=Vector2(440,150)
		for frame in range(3):
			await get_tree().process_frame
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png("/tmp/equipment_gap_hint.png")
	main.get_node("UI").remove_child(card)
	card.free()
	source.queue_free()
	for slot in Equipment.SLOT_DEFS:
		GameState.equipment[slot.id]=item(slot.kind,510,"legendary",12)
	EventBus.equipment_changed.emit()
	check(bar.bar_state(boss.get_instance_id()).get("gap_text")=="","换装事件即时清除压制提示")
	GameState.equipment.weapon=item("weapon",450,"legendary",12)
	var keep:=SellGearPolicy.auto_sell(fresh,517,GameState.equipment,SellGearPolicy.AGGRESSIVE,false,[])
	check(not keep.sell,"低分高等级候选不被自动出售")
	var duplicate:=item("weapon",510,"common")
	var next:=SellGearPolicy.auto_sell(duplicate,517,GameState.equipment,SellGearPolicy.AGGRESSIVE,false,[fresh])
	check(next.sell,"超出原武器一件额度的同级候选仍可出售")
	var worn: Dictionary=GameState.equipment.weapon.duplicate(true)
	var before:=EquipmentGap.current_context()
	EquipmentGap.preview(GameState.equipment,fresh,"weapon",517)
	check(GameState.equipment.weapon==worn and is_same(before,EquipmentGap.current_context()),"预览不修改真实穿戴或上下文")
	main.queue_free()
	await get_tree().process_frame
	print("[EquipmentGapUiTest] ","全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 收集实际结构化弹窗中的Label文本，避免只断言不会显示的原生fallback。
func text_of(node: Node) -> String:
	var text:=String(node.text) if node is Label else ""
	for child in node.get_children():
		text += "\n"+text_of(child)
	return text

## 真实人物面板布局完成后检查矩形，不以父子节点结构替代防遮挡验收。
func check_character_layout(main: Node, player: PlayerCharacter, boss: Monster) -> void:
	var panel: Control = main.get_node("UI/CharacterPanel")
	var window := get_window()
	var original_size := window.size
	var original_scale := window.content_scale_size
	window.content_scale_size = Vector2i.ZERO
	player.select_target(boss, false)
	panel.set_open(true)
	var card: Control = panel.get("_gap_card")
	var stats: Label = panel.get("_stats")
	for dimensions in [Vector2i(1280,1200), Vector2i(1280,800), Vector2i(960,640)]:
		window.size = dimensions
		for frame in range(12):
			await get_tree().process_frame
		if dimensions.y == 1200:
			var stretched: FloatingWindow = panel.get("_center")
			stretched.size.y = 1100
			stretched.panel_box.size.y = 1100
			EventBus.equipment_changed.emit()
			for frame in range(3):
				await get_tree().process_frame
			print("[PERF] height allocated=",stretched.size.y," frame=",stretched.panel_box.size.y," natural=",stretched.panel_box.get_combined_minimum_size().y)
			check(stretched.panel_box.size.y <= stretched.panel_box.get_combined_minimum_size().y + 1.0, "大窗口旧分配高度不能拉长面板外框")
		var figure: Control = card.get_parent().get_child(1)
		check(card.visible, "落后装备显示独立卡片")
		check(not card.get_global_rect().intersects(stats.get_global_rect()), "提示与属性实际矩形不相交")
		check(card.global_position.y >= figure.get_global_rect().end.y, "提示位于人物展示与装备槽下方")
		check(card.size.y >= card.get_combined_minimum_size().y, "卡片高度容纳完整文字")
		var floating: FloatingWindow = panel.get("_center")
		check(floating.header.get_global_rect().end.y <= panel.get_viewport_rect().end.y, "小窗口标题与关闭入口可见")
		if dimensions.x == 960:
			var scroll: ScrollContainer = floating.content_scroll
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			for frame in range(3):
				await get_tree().process_frame
			check(card.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1.0, "小窗口滚动可读完整提示卡")
		if DisplayServer.get_name() != "headless":
			RenderingServer.force_draw(false)
			get_viewport().get_texture().get_image().save_png("/tmp/character_gap_%d_%d.png" % [dimensions.x, dimensions.y])
	boss.level = 450
	player.select_target(boss, false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not card.visible, "低等级目标无衰减时隐藏整卡")
	player.select_target(null, false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(card.visible and String(panel.get("_gap_reference").text).contains("人物等级"), "无目标明确按人物等级参考")
	boss.level = 517
	player.select_target(boss, false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(String(panel.get("_gap_reference").text).contains("参考目标"), "切回目标更新来源说明")
	panel.set_open(false)
	window.content_scale_size = original_scale
	window.size = original_size
