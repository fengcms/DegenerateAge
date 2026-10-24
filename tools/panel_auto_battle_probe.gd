extends Node
## 只读探针：逐面板打开时，背后的自动战斗是否被暂停。
## 不写存档、不改数据；只打印事实。
##
## 采样三件事：面板是否登记进 `_open_panels` / 是否接管世界输入 / 挂机 phase 与移动意图。
## 目的：把「面板会不会打断挂机」从玩家观感变成一张可复核的表（工程 101）。

## 业务面板：按玩家实际操作顺序排（背包最先，铁匠系最后）。
const BIZ_PANELS := [
	["InventoryPanel", "inventory"],
	["CharacterPanel", "character"],
	["SkillPanel", "skill"],
	["MountPanel", "mount"],
	["QuestPanel", "quest"],
	["MapBigPanel", "map"],
	["BlacksmithPanel", "blacksmith"],
	["WarehousePanel", "warehouse"],
	["UpgradePanel", "upgrade"],
	["ReforgePanel", "reforge"],
	["EquipmentFusionPanel", "equipment_fusion"],
	["BossTokenPanel", "boss_token"],
]

## 真暂停级面板：打开时 `get_tree().paused = true`（不是「面板」，是「暂停」）。
const PAUSED_PANELS := [
	["SettingsPanel", "settings"],
	["SavePanel", "save"],
]

func _ready() -> void:
	GameState.reset_to_defaults()
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	for _i in range(10):
		await get_tree().physics_frame

	var player: PlayerCharacter = main.get_node_or_null("Game/Entities/Player")
	var pilot: Node = player.get_node_or_null("AutoPilot") if player != null else null
	print("玩家=", player != null, " 挂机=", pilot != null, " 地图=", GameState.current_map)

	GameState.set_auto_battle(true)
	await _settle(8)
	print("==== 基线 ====")
	_row("（无面板）", pilot, player)

	print("==== ① 业务面板（12 个） ====")
	for entry in BIZ_PANELS:
		var node_name := String(entry[0])
		var panel_id := String(entry[1])
		var panel: Node = main.get_node_or_null("UI/" + node_name)
		if panel == null:
			print("  ", panel_id, " 节点缺失：", node_name)
			continue
		panel.call("set_open", true)
		await _settle(5)
		_row(panel_id, pilot, player)
		panel.call("set_open", false)
		await _settle(3)

	print("==== ② 货郎两种形态 ====")
	var shop: Node = main.get_node_or_null("UI/ShopPanel")
	EventBus.shop_open_requested.emit("peddler_camp")
	await _settle(5)
	_row("shop（当地货郎）", pilot, player)
	shop.call("set_open", false)
	await _settle(3)

	print("==== ③ 随身三件套 ====")
	for tool_id in ["shop", "carter", "boss_token"]:
		print("  open(", tool_id, ")=", JSON.stringify(PanelRouter.open(tool_id)))
		await _settle(5)
		_row(tool_id + "（随身）", pilot, player)
		var target: Node = main.get_node_or_null(
			"UI/" + ("ShopPanel" if tool_id == "shop" else ("CarterPanel" if tool_id == "carter" else "BossTokenPanel")))
		if target != null:
			target.call("set_open", false)
		await _settle(3)

	print("==== ④ 真暂停级（settings / save / menu） ====")
	for entry in PAUSED_PANELS:
		var panel: Node = main.get_node_or_null("UI/" + String(entry[0]))
		if panel == null:
			continue
		panel.call("set_open", true)
		await _settle(5)
		_row(String(entry[1]), pilot, player)
		panel.call("set_open", false)
		get_tree().paused = false
		await _settle(3)
	# 菜单只在 `menu_mode == "world"` 时可开暂停页；而 settings / save 自身**不**设 paused，
	# 它们能不能冻结世界，取决于是否从菜单进入（上面两行 paused=false 就是证据）。
	var menu: Node = main.get_node_or_null("UI/MenuPanel")
	if menu != null:
		GameState.menu_mode = "world"
		menu.call("open_pause")
		await _settle(5)
		_row("menu（Esc 暂停菜单）", pilot, player)
		menu.call("resume_game")
		await _settle(3)

	print("==== ⑤ 收尾 ====")
	_row("全部关闭", pilot, player)
	print("PROBE_DONE")
	get_tree().quit(0)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().physics_frame

func _row(label: String, pilot: Node, player: PlayerCharacter) -> void:
	var phase := String(pilot.current_phase()) if pilot != null else "<无>"
	var move: Vector2 = player.auto_move if player != null else Vector2.ZERO
	var registered := "?"
	for panel_id in GameState._open_panels.keys():
		if registered == "?":
			registered = String(panel_id)
	print("  %-22s paused=%-5s 接管输入=%-5s phase=%-8s auto_move=(%.2f,%.2f) %s" % [
		label, str(get_tree().paused), str(GameState.world_controls_blocked()), phase,
		move.x, move.y, "" if registered == "?" else "已登记:" + registered])
