extends Node2D
## 世界根节点：装配地面、玩家、怪物生成器、安全区 NPC，设置出生点与相机边界。
## 依据产品文档 7.2（相机平滑跟随、防露边界）、7.9（怪物点刷新）、6.3（安全区 NPC）。

const NPC_SCENE := preload("res://scenes/entities/Npc.tscn")

## M1 测试怪物点（在营地图上验证 AI；M3 改为读 maps.json 的 spawnPoints）。
## 木桩 ai=false（静态教学目标）；野狼 / 裂壳虫 ai=true（会巡逻 / 追击 / 攻击）。
## 【开发期测试便利】为加快测试循环，数量已上调、刷新时间已缩短；正式数值见 maps.json（M3）。
const TEST_SPAWNS := [
	{"monsterId": "wolf_corrupted", "level": 2, "count": 6, "respawnTime": 6.0, "ai": true},
	{"monsterId": "shellback_bug", "level": 3, "count": 2, "respawnTime": 12.0, "ai": true},
	{"monsterId": "training_dummy", "level": 1, "count": 3, "respawnTime": 20.0, "ai": false},
]

## ---- 开发期测试便利（【M5 打包前移除】）----
## 开局往背包补一把高攻测试武器，省去刷装备环节，便于快速验证战斗 / 掉落 / 交易。
## 模板在 equipments.json 中标 "debug": true → Loot 抽取时跳过（见 loot.gd），不污染正式掉落池。
const DEBUG_WEAPON_ID := "debug_blade_overpower"

## M1 安全区 NPC（6.3：每个地图的安全区聚集功能性 NPC；M3 改为读 maps.json 的 NPC 点）。
## cell 为等距网格坐标；货郎放在出生点附近（营地中心偏西 4 格），开局即可走到。
const TEST_NPCS := [
	{"shopId": "peddler_camp", "cell": Vector2i(16, 20)},
]

@onready var _ground: IsoGround = $Ground
@onready var _player: PlayerCharacter = $Entities/Player
@onready var _camera: Camera2D = $Entities/Player/Camera2D
@onready var _spawner: MonsterSpawner = $Spawner
@onready var _npcs: Node2D = $Npcs
@onready var _damage_numbers: Node2D = $DamageNumbers

func _ready() -> void:
	_damage_numbers.add_to_group("damage_numbers")

	# 出生点：地图中心
	_player.global_position = _ground.get_map_center_world()

	# 相机限制到地图包围盒，避免露出边界外的空白
	var b: Rect2 = _ground.get_world_bounds()
	_camera.limit_left = int(b.position.x)
	_camera.limit_top = int(b.position.y)
	_camera.limit_right = int(b.end.x)
	_camera.limit_bottom = int(b.end.y)
	_camera.reset_smoothing()

	# 怪物点（M1-5）
	_spawner.setup(_ground, _player)
	_spawner.spawn_from_specs(TEST_SPAWNS)

	# 安全区 NPC（M1-8）
	_spawn_npcs()

	# 开发期：延迟一帧发放测试武器（此时 UI 已就绪，提示能正常显示）
	_grant_debug_loadout.call_deferred()

## 开发期：向背包补一把测试武器（已有则不重复给，避免堆积）。
## 仅 debug 构建生效（导出 release 包时不应带测试武器）。
func _grant_debug_loadout() -> void:
	if not OS.is_debug_build():
		return
	if _has_item_anywhere(DEBUG_WEAPON_ID):
		return
	var item := _make_debug_equip(DEBUG_WEAPON_ID)
	if item.is_empty():
		return
	GameState.add_item(item)
	EventBus.toast_requested.emit("【测试】已放入背包：%s" % ItemUtil.display_name(item), "drop")
	print("[Debug] 已发放测试武器：%s（攻击 +%d）" % [
		ItemUtil.display_name(item), int(item.get("baseAttrs", {}).get("atk", 0))])

## 背包或已穿戴中是否已存在该装备。
func _has_item_anywhere(item_id: String) -> bool:
	for it in GameState.inventory:
		if it is Dictionary and String(it.get("itemId", "")) == item_id:
			return true
	for sid in GameState.equipment.keys():
		var w = GameState.equipment[sid]
		if w is Dictionary and String(w.get("itemId", "")) == item_id:
			return true
	return false

## 依模板构造一件装备实例（结构与 Loot 一致：属性随实例保存，10.1 / 5.7）。
func _make_debug_equip(item_id: String) -> Dictionary:
	var tpl = DataLoader.get_entry("equipments", item_id)
	if not (tpl is Dictionary):
		push_warning("[Debug] 未找到测试装备模板：%s" % item_id)
		return {}
	var base := {}
	if tpl.get("baseAttrs", {}) is Dictionary:
		base = (tpl.get("baseAttrs") as Dictionary).duplicate(true)
	var affixes := []
	if tpl.get("affixes", []) is Array:
		affixes = (tpl.get("affixes") as Array).duplicate(true)
	var pct := []
	if tpl.get("pctAttrs", []) is Array:
		pct = (tpl.get("pctAttrs") as Array).duplicate(true)
	return {
		"kind": "equip",
		"itemId": item_id,
		"instanceId": "debug_%d" % Time.get_ticks_msec(),
		"quality": String(tpl.get("quality", "common")),
		"level": 1,
		"baseAttrs": base,
		"affixes": affixes,
		"pctAttrs": pct,
		"star": 0,
		"count": 1,
	}

## 按测试规格生成 NPC（6.3）。M3 起改为读 maps.json 的 NPC 点。
func _spawn_npcs() -> void:
	for spec in TEST_NPCS:
		if not (spec is Dictionary):
			continue
		var npc: Npc = NPC_SCENE.instantiate()
		npc.shop_id = String(spec.get("shopId", ""))
		var cell: Vector2i = spec.get("cell", Vector2i.ZERO)
		npc.position = Iso.grid_to_world(cell)
		_npcs.add_child(npc)

func _unhandled_input(event: InputEvent) -> void:
	# 开发期验证键（M5 移除）：H = 自伤 15，用于验证 HUD 血条实时刷新。
	if OS.is_debug_build() and event.is_action_pressed("debug_hurt"):
		GameState.damage_player(15)
		get_viewport().set_input_as_handled()
		return

	# 自动战斗 / 自动拾取（F / G，3.14 / 9.9）；面板打开时不响应
	if not GameState.panel_open:
		if event.is_action_pressed("auto_battle"):
			GameState.toggle_auto_battle()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("auto_pickup"):
			GameState.toggle_auto_pickup()
			get_viewport().set_input_as_handled()
			return

	# 与 NPC 交互（6.3 通用交互）：靠近后按 E；面板打开时不响应
	if event.is_action_pressed("interact") and not GameState.panel_open:
		if _try_interact():
			get_viewport().set_input_as_handled()

## 玩家身上的自动战斗决策机（M1-9；测试场景中可能不存在 → 返回 null）。
func auto_pilot() -> AutoBattle:
	if _player == null or not is_instance_valid(_player):
		return null
	return _player.get_node_or_null("AutoPilot") as AutoBattle

## 就近与 NPC 交互：成功派发返回 true（6.3 通用交互入口，后续对话系统 9.8 在此扩展）。
func _try_interact() -> bool:
	var npc := nearest_npc()
	if npc == null:
		return false
	if not npc.shop_id.is_empty():
		EventBus.shop_open_requested.emit(npc.shop_id)
		return true
	return false

## 交互半径内的最近 NPC（无则 null）。
func nearest_npc() -> Npc:
	var best: Npc = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("npcs"):
		if not (n is Npc):
			continue
		var npc := n as Npc
		if not npc.is_player_in_range():
			continue
		var d := npc.global_position.distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = npc
	return best

