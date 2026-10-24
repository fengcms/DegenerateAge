extends Node
## NPC 面对面会话回归（工程 101 反转）：面板打开**不再**打断挂机。
## 保留的边界是「F / 图标在面板打开时仍可开关」与「手动输入仍能接管挂机」。
## 不写正式存档。

var failures: Array[String] = []

## 构造真实货郎会话，检查自动决策照常运行、手动输入仍可接管。
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
	# 前置防空跑：面板本身要真的开着，否则下面每条「不停战」都是空转通过。
	check(shop.visible, "货郎面板真的打开（前置）")
	# 判据一（文本层）：不再切进「对话中暂停」这个 phase。
	check(GameState.auto_battle_on and pilot.current_phase() != Localization.tr_key("ui.auto.npc_dialog"),
		"打开货郎不把挂机切成暂停态")
	# 判据二（行为层）：30 帧内出现过非零移动意图 —— 光看文案不变会被
	# 「守卫把整段决策跳过」骗过去。
	var moved := false
	for _i in range(30):
		await get_tree().physics_frame
		if player.auto_move != Vector2.ZERO:
			moved = true
			break
	check(moved, "货郎打开时挂机仍产生移动意图（行为层）")
	var before_manual := player.global_position
	Input.action_press("move_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_left")
	check(player.global_position.distance_to(before_manual) > 1.0, "货郎打开时仍能手动移动")
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
	check(GameState.auto_battle_on and pilot.current_phase() != Localization.tr_key("ui.auto.npc_dialog"),
		"关闭货郎后保留自动战斗开关且仍非暂停态")
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

## 累积失败信息并由测试退出码统一报告。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
