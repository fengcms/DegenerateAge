extends Node
## 阶段形象（look）验收：武器 → look 解析、世界形象与人物面板随 look 刷新、HUD 头像固定不变。
## 依据 docs/素材设计/15-角色形象与素材方案（阶段形象·八向单层）.md §7。
## 运行：python3 tools/run_isolated_tests.py CharacterLookTest

var failures: Array[String] = []

## 记录一条断言结果；失败信息在结束时统一输出，不中断测试流程。
func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _ready() -> void:
	GameState.reset_to_defaults()
	_test_resolution()
	await _test_weapon_switch()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[CharacterLookTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for message in failures:
			push_error(message)
		get_tree().quit(1)

## 校验数据落点与解析入口：空手、未标注 look 的装备一律回退 look_01。
## 形象素材未到时必须回退默认图集，保证换装链路可用且不出现空白形象。
func _test_resolution() -> void:
	var iron: Variant = DataLoader.get_entry("equipments", "weapon_iron")
	var blade: Variant = DataLoader.get_entry("equipments", "c2_road_blade")
	expect(iron is Dictionary and String(iron.get("look", "")) == "look_01", "铁制短刃模板应标注 look_01")
	expect(blade is Dictionary and String(blade.get("look", "")) == "look_02", "守路长刃模板应标注 look_02")
	expect(CharacterLook.is_declared("look_01"), "look_01 必须已在形象表中登记")
	expect(CharacterLook.look_id_for({}) == "look_01", "空手应回退 look_01")
	expect(CharacterLook.look_id_for({"weapon": {"kind": "equip", "itemId": "armor_cloth"}}) == "look_01",
		"未标注 look 的装备应回退 look_01")
	expect(CharacterLook.look_id_for({"weapon": {"kind": "equip", "itemId": "c2_road_blade"}}) == "look_02",
		"第二档武器应解析 look_02")

	var default_entry := CharacterLook.definition("look_01")
	expect(default_entry.main.get_size() == Vector2(512, 640), "默认主图集应为 512×640")
	expect(default_entry.frame == Vector2i(64, 80) and default_entry.pivot == Vector2(32, 64),
		"默认形象帧格与脚底锚点")
	var panel_frame := CharacterLook.panel_texture("look_01")
	expect(panel_frame == default_entry.panel and panel_frame.get_size() == Vector2(256, 400),
		"初始形象应使用独立 256×400 高清面板图")
	# 各 look 共用同一帧格与锚点，面板的 ×4 整数倍放大才成立；素材未到时按回退校验。
	if CharacterLook.is_declared("look_02"):
		var second := CharacterLook.definition("look_02")
		expect(second.frame == default_entry.frame and second.pivot == default_entry.pivot,
			"各 look 必须共用同一帧格与锚点")
	else:
		expect(CharacterLook.definition("look_02").main == default_entry.main, "素材未到的形象应回退默认图集")

## 换武器后世界玩家与人物面板按新 look 刷新；HUD 头像固定一张，不随 look 更换。
func _test_weapon_switch() -> void:
	GameState.player["level"] = 11
	GameState.current_map = "wild_trial"
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var player: PlayerCharacter = main.get_node("Game/Entities/Player")
	var pilot: Node = player.get_node_or_null("AutoPilot")
	if pilot != null:
		pilot.set_physics_process(false)
	var panel: Control = main.get_node("UI/CharacterPanel")
	var avatar: TextureRect = main.get_node("UI/Hud/StatusPanel/Portrait/PortraitImage")
	var fixed_avatar := preload("res://assets/ui/portraits/guardian.png")
	expect(player._look_id == "look_01", "初始武器应使用 look_01")
	expect(player.sample_art.texture == CharacterLook.definition("look_01").animations.idle.texture,
		"世界玩家应使用 look_01 逐帧待机图集")
	expect(player.sample_art.offset == Vector2(-32, -64), "世界玩家应保持脚底锚点")

	panel.set_open(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var frame := panel._portrait.get_parent() as Control
	expect(frame.custom_minimum_size == Vector2(258, 410), "展示框应为 258×410")
	expect(is_equal_approx(panel._portrait.size.x, 256.0), "展示框内宽应为 256 = 64 × 4")
	expect(panel._portrait.texture == CharacterLook.definition("look_01").panel, "面板初始形象应为独立高清图")

	GameState.inventory.append(ItemFactory.make_any("c2_road_blade"))
	var result := GameState.equip_from_inventory(GameState.inventory.size() - 1, "weapon")
	expect(bool(result.get("ok", false)), "第二档武器应能穿上并触发换装刷新")
	await get_tree().process_frame
	expect(player._look_id == "look_02", "换武器后世界形象 id 应刷新为 look_02")
	expect(player.sample_art.texture == CharacterLook.definition("look_02").main,
		"世界玩家图集应随形象切换（素材未到时回退默认图集）")
	expect(player.sample_art.walk_texture == CharacterLook.definition("look_02").walk, "行走图集应与形象同步切换")
	expect(panel._look_id == "look_02", "人物面板形象 id 应随武器刷新")
	expect((panel._portrait.texture as AtlasTexture).atlas == CharacterLook.definition("look_02").main,
		"面板形象应随武器切换（素材未到时回退默认图集）")
	expect(avatar.texture == fixed_avatar, "HUD 头像固定一张，不随 look 更换")

	panel.set_open(false)
	main.queue_free()
