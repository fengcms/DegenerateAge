extends Node
## 工程 101：**任何面板打开都不打断背后挂机**（取消「NPC 会话停战」）。
##
## 五组判据：A 文本层不停战 / B 行为层真的在移动 / C 真暂停仍然停 /
## D 面板打开时自动拾取仍生效 / E 死亡仍会关挂机。
## 全部从公开入口驱动（`set_open` / `GameState` / 真实地面物），不读面板私有布局。
## 不写正式存档。

## 12 类业务面板：面板节点名 + 登记 id。玩家日常能开到的功能面板全在这里。
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

var failures: Array[String] = []
var _main: Node = null
var _player: PlayerCharacter = null
var _pilot: AutoBattle = null
var _loot_root: Node2D = null

func _ready() -> void:
	# 真暂停用例里本节点也要能继续推进协程，否则 C 组会卡死。
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.reset_to_defaults()
	_main = preload("res://scenes/Main.tscn").instantiate()
	# ⚠ 本节点是 ALWAYS（C 组要在暂停中继续推进协程），而 process_mode 会向下继承 ——
	# 不显式压回 PAUSABLE，整棵 Main 都会跟着 ALWAYS，`paused = true` 变成空操作。
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_main)
	for _i in range(6):
		await get_tree().process_frame
	_player = _main.get_node_or_null("Game/Entities/Player") as PlayerCharacter
	if _player != null:
		_pilot = _player.get_node_or_null("AutoPilot") as AutoBattle
	check(_player != null and _pilot != null, "主场景里玩家与 AutoPilot 都存在（前置）")
	if _player == null or _pilot == null:
		await _finish()
		return
	_loot_root = Node2D.new()
	_loot_root.name = "LootRoot"
	_loot_root.add_to_group("loot_root")
	_main.get_node("Game").add_child(_loot_root)
	GameState.set_auto_battle(true)
	await _settle(10)
	await _test_panels_do_not_enter_pause_phase()
	await _test_panels_keep_moving()
	await _test_real_pause_still_stops()
	await _test_auto_pickup_with_panel_open()
	await _test_death_still_turns_off()
	await _finish()

# ---- A 文本层：不再切进「对话中暂停」 ----

func _test_panels_do_not_enter_pause_phase() -> void:
	var pause_key := Localization.tr_key("ui.auto.npc_dialog")
	var hit := 0
	for entry in BIZ_PANELS:
		var panel: Node = _main.get_node_or_null("UI/" + String(entry[0]))
		if panel == null:
			continue
		panel.call("set_open", true)
		await _settle(4)
		# 前置防空跑：面板真的要打开，否则「没进暂停态」是废话。
		check(bool(panel.get("visible")), "%s 真的打开（前置）" % String(entry[1]))
		check(_pilot.current_phase() != pause_key,
			"打开 %s 不切进「对话中暂停」" % String(entry[1]))
		hit += 1
		panel.call("set_open", false)
		await _settle(2)
	check(hit >= BIZ_PANELS.size(),
		"12 类业务面板都被实际打开过，实际 %d" % hit)

# ---- B 行为层：挂机真的在推进（防「只是文案没变」） ----
#
# 判据是「掉血 **或** 位移」而不是单看 auto_move：玩家贴身站桩输出时 auto_move
# 恒为零（攻击不移动），单看它会把「本来就在打」误判成「没在跑」。两者任一发生
# 都说明决策链在推进 —— 反过来，若整段决策被跳过，两者都不会发生。

func _test_panels_keep_moving() -> void:
	# 环境前置：场上有敌人，「掉血」这条判据才成立；否则只剩位移一条腿，
	# 玩家贴身站桩时会把「本来就在打」误报成「没推进」。
	check(_enemy_hp_total() >= 0, "B 组前置：场上有敌人（掉血判据可用）")
	var progressed_panels := 0
	for entry in BIZ_PANELS:
		var panel: Node = _main.get_node_or_null("UI/" + String(entry[0]))
		if panel == null:
			continue
		panel.call("set_open", true)
		var pos_before := _player.global_position
		var hp_before := _enemy_hp_total()
		if await _wait_progress(pos_before, hp_before, 90):
			progressed_panels += 1
		else:
			check(false, "打开 %s 后 60 帧内挂机无任何推进（phase=「%s」）"
				% [String(entry[1]), _pilot.current_phase()])
		panel.call("set_open", false)
		await _settle(2)
	check(progressed_panels > 0, "至少一个面板下观察到真实推进")

# ---- C 真暂停仍然停（守边界，别把暂停一起放开） ----

func _test_real_pause_still_stops() -> void:
	# 先等挂机真的走起来，否则「暂停后位置不变」会因为本来就没动而假绿。
	var moving := await _wait_auto_move(60)
	check(moving, "真暂停用例前置：挂机正在移动")
	var before := _player.global_position
	var phase_before := _pilot.current_phase()
	get_tree().paused = true
	await _settle(10)
	var frozen := _player.global_position.distance_to(before) < 0.01
	check(frozen, "真暂停时角色位置冻结（世界真的停了）")
	check(_pilot.current_phase() == phase_before, "真暂停时挂机状态机不推进")
	get_tree().paused = false
	await _settle(4)

# ---- D 面板打开时自动拾取仍生效 ----

func _test_auto_pickup_with_panel_open() -> void:
	GameState.set_auto_pickup(true)
	var bag: Node = _main.get_node("UI/InventoryPanel")
	bag.call("set_open", true)
	await _settle(2)
	var gold_before := GameState.gold
	var ground := preload("res://scenes/entities/GroundItem.tscn").instantiate()
	ground.item = {"kind": "coin", "gold": 137, "name": "铜币"}
	ground.auto_claim = true
	ground.persistent = false
	ground.manual_only = false
	ground.appear_delay = 0.0
	ground.position = _player.global_position
	_loot_root.add_child(ground)
	await _settle(4)
	check(GameState.gold == gold_before + 137,
		"面板打开时脚边掉落仍被自动拾取（金币 %d → %d）" % [gold_before, GameState.gold])
	bag.call("set_open", false)
	GameState.set_auto_pickup(false)
	await _settle(2)

# ---- E 死亡仍会关挂机（既有语义不能被波及） ----

func _test_death_still_turns_off() -> void:
	GameState.set_auto_battle(true)
	await _settle(3)
	_player.is_dead = true
	await _settle(2)
	check(not GameState.auto_battle_on, "死亡仍会自动关闭挂机")
	_player.is_dead = false
	await _settle(2)

# ---- 工具 ----

## 最多等 `frames` 个物理帧，期间出现过非零移动意图即返回 true。
func _wait_auto_move(frames: int) -> bool:
	for _i in range(frames):
		await get_tree().physics_frame
		if _player.auto_move != Vector2.ZERO:
			return true
	return false

## 最多等 `frames` 帧，期间出现「玩家位移 > 1px」或「全场敌人总血量下降」即返回 true。
## 用总血量而不是「第一个敌人」：玩家打的是被锁定的那一只，未必是组里的第一个
## （第一版取第一个，结果盯着没挨打的怪，误报成「没推进」）。
func _wait_progress(pos_before: Vector2, hp_before: int, frames: int) -> bool:
	for _i in range(frames):
		await get_tree().physics_frame
		if _player.global_position.distance_to(pos_before) > 1.0:
			return true
		if hp_before >= 0 and _enemy_hp_total() < hp_before:
			return true
	return false

## 场上所有敌人的当前血量之和；没有敌人返回 -1（= 本帧无法用「掉血」判据）。
func _enemy_hp_total() -> int:
	var foes := get_tree().get_nodes_in_group("enemies")
	if foes.is_empty():
		return -1
	var total := 0
	for enemy in foes:
		total += int(enemy.get("hp"))
	return total

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().physics_frame

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _finish() -> void:
	get_tree().paused = false
	GameState.set_auto_battle(false)
	if _main != null:
		_main.queue_free()
		await get_tree().process_frame
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[PanelAutoBattleTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
