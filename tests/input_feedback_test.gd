extends Node
## 使用真实 Main 和 Viewport 输入路由验证试玩反馈；独立 tests 存档闸门。
var failures: Array[String] = []

## 累积输入验收失败，供测试结束时一次性报告。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("[InputFeedback] 失败：", message)

## 向真实 Viewport 送一组按下与松开事件，覆盖面板与世界的输入路由。
func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)

## 模拟左键点击屏幕位置，验证 GUI 命中与世界点击是否正确分流。
## 需同时填 position 与 global_position，并带上左键 mask —— 只填 position 时 GUI 命中拿不到
## 全局坐标，控件（如快捷格按钮）收不到按下/松开，点击会静默落空。
func click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		get_viewport().push_input(event, true)

## 构造真实主场景并执行鼠标、键盘、面板和自动战斗的综合输入回归。
func _ready() -> void:
	GameState.reset_to_defaults()
	# 交互回归需要可攻击的近距离怪；营地出生点位于免战区内。
	GameState.current_map = "wild_trial"
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("Game")
	var player: PlayerCharacter = main.get_node("Game/Entities/Player")
	var pilot: AutoBattle = player.get_node("AutoPilot")
	var hud: Control = main.get_node("UI/Hud")
	world.get_node("Spawner").set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var npc := (load("res://scenes/entities/Npc.tscn") as PackedScene).instantiate() as Npc
	npc.role = "quest"
	npc.npc_name = "测试长老"
	world.get_node("Npcs").add_child(npc)
	npc.global_position = player.global_position + Vector2(250.0, 0.0)
	click(npc.get_global_transform_with_canvas().origin + Vector2(0.0, -45.0))
	check(hud.get_node("TargetPanel").visible and hud._target_name.text == npc.npc_name,
		"点击 NPC 显示目标名称")
	check(hud._target_hint.visible and not hud._target_hp.visible, "NPC 目标显示友方交互信息而非血条")
	check(hud._target_hint.position.y >= hud._target_name.position.y + hud._target_name.size.y,
		"NPC 交互提示不遮挡目标名称")
	check(player.locked_target == null and not player.valid_target(npc), "NPC 不进入战斗锁定")
	player.clear_travel_intent()
	npc.queue_free()
	await get_tree().process_frame
	var enemies: Array[Monster] = []
	for offset in [Vector2(130, 0), Vector2(260, 0), Vector2(2000, 0)]:
		var enemy := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
		enemy.monster_id = "training_dummy"
		world.add_child(enemy)
		enemy.global_position = player.global_position + offset
		enemy.max_hp = 1000
		enemy.hp = 1000
		enemy.set_physics_process(false)
		enemies.append(enemy)
	await get_tree().create_timer(0.1).timeout
	check(not hud.get_node("TargetPanel").visible, "无目标时整体隐藏")
	key(KEY_TAB)
	check(player.locked_target == enemies[0] and enemies[0].selected, "Tab 首选最近可见目标")
	check(hud.get_node("TargetPanel").visible, "选中显示目标区")
	key(KEY_TAB)
	check(player.locked_target == enemies[1] and not enemies[0].selected, "Tab 切换并清除旧高亮")
	key(KEY_TAB)
	check(player.locked_target == enemies[0], "Tab 循环不选屏外怪")
	check(not player.try_auto_attack(enemies[1]), "超距离不能直接扣血")
	# 无锁定目标时按「可见范围」选最近者（屏外 2000px 不参选）；显式锁定优先，
	# 但锁定目标进黑名单后回退最近可见。
	# （M4-9 起搜怪以 visible_enemies 为准，旧锚点 _anchor 已移除 ——
	#  2026-10-13 M5-7 回归时重写本节，原锚点范围断言随 API 废止。）
	player.select_target(enemies[0], false)
	check(pilot._find_target() == enemies[0], "无锁定应选最近可见目标")
	player.select_target(enemies[1])
	check(pilot._find_target() == enemies[1], "用户锁定目标优先")
	pilot._blacklist[enemies[1].get_instance_id()] = 8.0
	check(pilot._find_target() == enemies[0], "锁定目标被拉黑后回退最近可见目标")
	pilot._blacklist.clear()
	player.select_target(null)
	# P2 目标粘性（工程 69 §5）：被误判拉黑丢掉的原目标，出了黑名单后应被优先选回，
	# 而不是被「更近的那只」抢走（enemies[1] 比 enemies[0] 远，选回它才说明粘性真的生效）。
	pilot._blacklist_target(enemies[1])
	pilot._blacklist.clear()                          # 模拟 3s 黑名单到点
	check(pilot._find_target() == enemies[1],
		"被误判丢掉的原目标应在黑名单到点后优先被选回（目标粘性）")
	pilot._sticky_left = 0.0                          # 记忆过期 → 回到「最近可见优先」
	check(pilot._find_target() == enemies[0], "粘性记忆过期后应恢复最近可见优先")
	# 空地移动使用世界投影，与相机位置无关。
	var start := player.global_position
	var point := start + Vector2(0, 130)
	click(world.get_canvas_transform() * point)
	await get_tree().create_timer(0.3).timeout
	check(player.global_position.distance_to(point) < start.distance_to(point), "主地图左击实际行走")
	Input.action_press("move_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_left")
	check(not player.map_move_active, "WASD 取消点击行走")
	# 点击指定的远目标，不应攻击更近的其他怪。
	click(enemies[1].get_global_transform_with_canvas().origin + Vector2(0, -8))
	check(player.manual_attack_active and player.locked_target == enemies[1], "点击怪物锁定并下达攻击")
	await get_tree().create_timer(2.2).timeout
	check(enemies[1].hp < 1000 and enemies[0].hp == 1000, "接近后持续普攻仅命中指定目标")
	check(player.global_position.distance_to(enemies[1].global_position) <= player.melee_range_px(), "攻击时实际抵达范围")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_input_selected.png")
	# 普通面板打开时，键盘仍能接管角色与快捷栏；鼠标命中面板控件仍归 GUI。
	key(KEY_M)
	var stopped := player.global_position
	check(GameState.panel_open and not GameState.world_controls_blocked(), "普通地图面板不接管世界键盘")
	Input.action_press("move_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_left")
	check(player.global_position.distance_to(stopped) > 1.0 and not player.manual_attack_active,
		"面板打开时 WASD 仍能移动并取消连续攻击")
	key(KEY_TAB)
	check(player.locked_target == enemies[0], "面板打开时 Tab 仍能切换目标")
	Input.action_press("attack")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("attack")
	check(player.manual_attack_active or enemies[0].hp < 1000,
		"面板打开时 Space 仍能向选中怪物发起普攻")
	Input.action_press("move_left")
	await get_tree().physics_frame
	Input.action_release("move_left")
	key(KEY_G)
	check(GameState.auto_pickup_on, "面板打开时 G 仍能切换自动拾取")
	key(KEY_G)
	# 2026-10-22：F 开自动战斗时联动打开自动拾取（挂机最常漏的一步），G 仍可单独关。
	# 四条断言覆盖完整交互链，避免「联动写了但提示在骗人」或「G 关掉后又被抢回去」。
	var toasts: Array[String] = []
	var on_toast := func(text: String, _kind: String) -> void:
		toasts.append(text)
	EventBus.toast_requested.connect(on_toast)
	toasts.clear()
	key(KEY_F)
	check(GameState.auto_battle_on and GameState.auto_pickup_on,
		"按 F 开启自动战斗时一并打开自动拾取")
	check(toasts.size() == 1 and toasts[0] == Localization.tr_key("msg.game_state.p042")
		+ Localization.tr_key("msg.game_state.p057"),
		"提示写明本次是顺带开启了拾取（实际 %s）" % [toasts])
	key(KEY_G)
	check(not GameState.auto_pickup_on and GameState.auto_battle_on,
		"G 可单独关闭自动拾取，自动战斗不受影响")
	key(KEY_F)
	check(not GameState.auto_battle_on and not GameState.auto_pickup_on,
		"关自动战斗不会顺手改动自动拾取")
	key(KEY_G)
	toasts.clear()
	key(KEY_F)
	check(GameState.auto_pickup_on and toasts.size() == 1
		and toasts[0] == Localization.tr_key("msg.game_state.p042")
			+ Localization.tr_key("msg.game_state.p044"),
		"拾取本来就开着时提示不再说「已同时开启」（实际 %s）" % [toasts])
	key(KEY_F)
	key(KEY_G)
	EventBus.toast_requested.disconnect(on_toast)
	# P1（工程 71 §4/§5）：面板打开时鼠标点快捷格必须与键盘等效。这里直接调用 `_activate_hotbar`
	# 断言**守卫**这一层；旧口径（panel_open and not from_keyboard）下这一条必红。
	# 药水冷却按 item_id 独立且不落档（Consumable._cd），会跨断言残留 —— 每条断言前先 reset，
	# 否则后一条会被前一条的冷却拦下，把「守卫放行」伪证成「守卫拦下」。
	Consumable.reset()
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	GameState.player.hp = maxi(1, int(GameState.player.hp) - 30)
	hud._activate_hotbar(0)
	check(GameState.inventory[0] is Dictionary and int(GameState.inventory[0].count) == 2,
		"普通面板内点快捷格应真正触发该格操作（旧防误触守卫必红）")
	Consumable.reset()
	GameState.player.hp = maxi(1, int(GameState.player.hp) - 30)  # 上一口药已把血补满，须再扣血才能验证键位路径
	key(KEY_1)
	check(GameState.inventory[0] is Dictionary and int(GameState.inventory[0].count) == 1,
		"面板打开时快捷栏数字键仍能使用药品")
	key(KEY_ESCAPE)
	var inventory_panel: Control = main.get_node("UI/InventoryPanel")
	inventory_panel.set_open(true)
	var bag_position := player.global_position
	Input.action_press("move_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_left")
	check(player.global_position.distance_to(bag_position) > 1.0,
		"背包浮窗打开时 WASD 仍能操作角色")
	inventory_panel._organize_button.grab_focus()
	var before_focused_tab := player.locked_target
	key(KEY_TAB)
	check(player.locked_target != before_focused_tab, "背包按钮持有焦点时 Tab 仍切换世界目标")
	# P1 端到端（工程 71 §5）：背包打开会把快捷栏抬到 z_index 100（hud.gd:509），
	# 鼠标事件确实落在格子上（HotbarUiTest 的真实拖放已验证该坐标可达）——真实点击必须真的生效。
	Consumable.reset()  # 同上：清掉前两条断言留下的红药冷却
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 2}
	GameState.player.hp = maxi(1, int(GameState.player.hp) - 30)
	var bag_stock := int(GameState.inventory[0].count)
	click(hud._hotbar_buttons[0].get_global_rect().get_center())
	check(GameState.inventory[0] is Dictionary and int(GameState.inventory[0].count) == bag_stock - 1,
		"背包打开时真实鼠标点快捷格应消耗药品")
	inventory_panel.set_open(false)
	var settings_panel: Control = main.get_node("UI/SettingsPanel")
	settings_panel.set_open(true)
	var modal_position := player.global_position
	Input.action_press("move_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_left")
	check(GameState.world_controls_blocked() and player.global_position.is_equal_approx(modal_position),
		"设置模态面板仍阻止角色移动")
	# P1 边界（工程 71 §5）：模态面板仍必须拦住快捷格，不许把模态保护一起放开。
	# 用直接调用断言守卫本身——真实点击会被窗口遮挡混淆，分不清「守卫拦下」与「根本没点到」。
	Consumable.reset()
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 2}
	GameState.player.hp = maxi(1, int(GameState.player.hp) - 30)
	var modal_stock := int(GameState.inventory[0].count)
	hud._activate_hotbar(0)
	check(GameState.world_controls_blocked() and int(GameState.inventory[0].count) == modal_stock,
		"设置模态面板内点快捷格仍应被拦下")
	settings_panel.set_open(false)
	Input.action_press("move_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_left")
	check(not player.manual_attack_active, "WASD 取消连续攻击")
	click(Vector2(100, 50))
	check(not player.map_move_active and not player.manual_attack_active, "点击 HUD 不穿透到世界")
	# Space 对 Tab 锁定目标同样可以超距接近。
	player.global_position = start
	player.select_target(enemies[1])
	Input.action_press("attack")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("attack")
	check(player.manual_attack_active, "Space 接近锁定目标")
	player.manual_attack_active = false
	# 目标直接释放也必须清除引用和 HUD。
	enemies[1].queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	check(not is_instance_valid(player.locked_target) and not hud.get_node("TargetPanel").visible, "目标释放清理选中和 HUD")
	# 持续按键不会恢复，松开后才开始 1.5 秒倒计时。
	GameState.set_auto_battle(true)
	pilot.set_physics_process(false)
	player.set_physics_process(false)
	inventory_panel.set_open(true)
	Input.action_press("move_left")
	for i in range(5):
		pilot._physics_process(1.0)
	check(pilot._manual_t == 1.5 and pilot.current_state() == AutoBattle.State.MANUAL_OVERRIDE,
		"普通面板打开期间持续手动操作仍刷新 1.5 秒接管")
	Input.action_release("move_left")
	inventory_panel.set_open(false)
	pilot._physics_process(1.0)
	check(pilot.current_phase().contains("0.5 秒") and String(hud.get_node("%AutoLabel").text).contains("0.5 秒"), "HUD 显示真实倒计时")
	pilot.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	pilot._physics_process(1.0)
	check(pilot._manual_t == 0.0, "窗口失焦后自动战斗的接管倒计时仍推进")
	pilot._manual_t = 0.0
	pilot._target = enemies[0]
	pilot._physics_process(0.35)
	check(pilot.current_state() in [AutoBattle.State.PATH_TO_TARGET, AutoBattle.State.ATTACK_TARGET],
		"窗口失焦后自动战斗仍追怪或攻击")
	pilot.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	GameState.set_auto_battle(false)
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	await get_tree().process_frame
	key(KEY_TAB)
	check(player.locked_target == null and not hud.get_node("TargetPanel").visible, "空场景 Tab 无目标")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_input_empty.png")
	main.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()
	print("[InputFeedback] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
