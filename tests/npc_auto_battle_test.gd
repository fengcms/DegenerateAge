extends Node

var failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var game: Node = main.get_node("Game")
	var hud: Control = main.get_node("UI/Hud")
	var shop: Control = main.get_node("UI/ShopPanel")
	var player: PlayerCharacter = main.get_node("Game/Entities/Player")
	var pilot: AutoBattle = player.get_node("AutoPilot")
	GameState.set_auto_battle(true)
	EventBus.shop_open_requested.emit("peddler_camp")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(shop.visible and GameState.npc_dialog_open(), "货郎对话标记为 NPC 会话")
	check(GameState.auto_battle_on and pilot.current_phase() == Localization.tr_key("ui.auto.npc_dialog")
		and player.auto_move == Vector2.ZERO, "对话中保留 F 开关并停止自动移动")
	var f := InputEventAction.new()
	f.action = "auto_battle"
	f.pressed = true
	game._unhandled_input(f)
	check(not GameState.auto_battle_on, "NPC 面板打开时 F 可关闭自动战斗")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	hud._on_battle_icon_input(click)
	check(GameState.auto_battle_on, "NPC 面板打开时点击头像旁图标可开启自动战斗")
	shop.set_open(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not GameState.npc_dialog_open() and GameState.auto_battle_on
		and pilot.current_phase() != Localization.tr_key("ui.auto.npc_dialog"),
		"关闭 NPC 对话后保留自动战斗开关并恢复决策")
	check(GameState.panel_open, "关闭货郎后背包保留打开")
	main.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[NpcAutoBattleTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
