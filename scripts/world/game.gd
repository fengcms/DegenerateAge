extends Node2D
## 世界根节点：装配地面、玩家、怪物生成器、安全区 NPC，设置出生点与相机边界。
## 依据产品文档 7.2（相机平滑跟随、防露边界）、7.9（怪物点刷新）、6.3（安全区 NPC）。

const NPC_SCENE := preload("res://scenes/entities/Npc.tscn")

## 世界按「当前地图」数据驱动装配（M3-1）：
##   · 怪物点 → `maps.json` 的 `spawnPoints`（`MonsterSpawner.spawn_from_map`）
##   · Boss 点 → `maps.json` 的 `bossSpawn`（含墓碑刷新，M3-5 启用墓碑实体）
##   · NPC    → `maps.json` 的 `npcs`（货郎 / 任务官 / 车夫 / 铁匠）
## 切图 = 重载场景（`MapService.travel_to`，拍板 D1-A）：旧图实体随场景一并销毁（T15）。
## ⚠ 原 M1/M2 单图期的 `TEST_SPAWNS` / `TEST_ELITES` / `TEST_NPCS` 硬编码已随 M3 恢复清单移除
##   （见工程文档 13 §6 R3 与 04「M5 移除清单」）；营地保留 3 只教学木桩（产品 07 §7.6，`ai:false`）。

## ---- 开发期测试便利（【M5 打包前移除】）----
## 开局往背包补一把高攻测试武器，省去刷装备环节，便于快速验证战斗 / 掉落 / 交易。
## 模板在 equipments.json 中标 "debug": true → Loot 抽取时跳过（见 loot.gd），不污染正式掉落池。
const DEBUG_WEAPON_ID := "debug_blade_overpower"

## 安全区 / 各图 NPC 由 `maps.json` 的 `npcs` 驱动（M3-1；原 `TEST_NPCS` 已移除）。
## `cell` 为等距网格坐标，JSON 里是 `[x, y]` 数组（见 `_cell_of`）。

@onready var _ground: IsoGround = $Ground
@onready var _player: PlayerCharacter = $Entities/Player
@onready var _camera: Camera2D = $Entities/Player/Camera2D
@onready var _spawner: MonsterSpawner = $Spawner
@onready var _npcs: Node2D = $Npcs
@onready var _damage_numbers: Node2D = $DamageNumbers

var _explored_cell := Vector2i(-1, -1)
var _pending_npc: Npc = null

func _process(_delta: float) -> void:
	if GameState.panel_open or _player.is_dead:
		_pending_npc = null
		return
	if _pending_npc != null:
		if not is_instance_valid(_pending_npc) or not _pending_npc.is_inside_tree():
			_pending_npc = null
		elif _pending_npc.is_player_in_range():
			var arrived := _pending_npc
			_pending_npc = null
			_interact_with(arrived)
		elif not _player.map_move_active:
			_pending_npc = null
	var cell := Vector2i(Iso.world_to_grid(_player.global_position).round())
	if cell != _explored_cell:
		_explored_cell = cell
		Fog.reveal(GameState.current_map, cell)

func request_map_move(point: Vector2) -> bool:
	if not _player.request_map_move(_ground.clamp_to_map(point)):
		return false
	EventBus.toast_requested.emit("步行前往地图目标", "info")
	return true

func _ready() -> void:
	_damage_numbers.add_to_group("damage_numbers")

	# 出生点：读档 / 切图坐标优先（M1-10 + M3-1），否则地图中心。
	# SaveManager.apply_to_game_state（读档）与 MapService.travel_to（切图）都会把坐标写进
	# GameState.save_pos；此处**消费一次**即清空，因此后续重载场景若无新坐标就按地图中心出生。
	if GameState.has_save_pos:
		_player.global_position = _ground.clamp_to_map(GameState.save_pos)
		print("[Game] 读档/切图出生点：%s" % str(_player.global_position))
		GameState.clear_save_pos()
	else:
		_player.global_position = _ground.get_map_center_world()

	var pilot := _player.get_node_or_null("AutoPilot") as AutoBattle
	if pilot != null:
		pilot._on_auto_state_changed(GameState.auto_battle_on, GameState.auto_pickup_on)

	# 相机限制到地图包围盒，避免露出边界外的空白
	var b: Rect2 = _ground.get_world_bounds()
	_camera.limit_left = int(b.position.x)
	_camera.limit_top = int(b.position.y)
	_camera.limit_right = int(b.end.x)
	_camera.limit_bottom = int(b.end.y)
	# M5-9b（09-A）：切图 reload 会重建 Player/Camera2D，故在装配相机处补应用一次地图倍率。
	SettingsRuntime.apply_map_scale_to(_camera)
	_camera.reset_smoothing()

	# 怪物点 / Boss 点 / NPC：全部按当前地图数据装配（M3-1）
	_spawner.setup(_ground, _player)
	_spawner.spawn_from_map(GameState.current_map)
	var boss := MapService.current_boss()
	if not boss.is_empty():
		_spawner.spawn_from_specs([boss], GameState.current_map)

	# 各图 NPC（M3-1：由 maps.json 的 npcs 驱动）
	_spawn_npcs()

	# 抵达提示（切图 / 读档后给一次系统提示；延后一帧等 HUD 就绪）
	_notify_arrival.call_deferred()

	add_to_group("map_world")
	Fog.reveal(GameState.current_map, Vector2i(Iso.world_to_grid(_player.global_position).round()))

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

## 依模板构造一件装备实例（结构由公共工厂产出，见 scripts/systems/item_factory.gd）。
## 开发期测试装备用 "debug" 前缀便于辨识（M2 起统一由 ItemFactory 构造，消除 4 处重复）。
func _make_debug_equip(item_id: String) -> Dictionary:
	var item := ItemFactory.make_equip(item_id, 1, "debug")
	if item.is_empty():
		push_warning("[Debug] 未找到测试装备模板：%s" % item_id)
	return item

## 按当前地图的 NPC 点生成（6.3）。数据源：`maps.json` 的 `npcs`（M3-1 数据化）。
func _spawn_npcs() -> void:
	for spec in MapService.current_npcs():
		if not (spec is Dictionary):
			continue
		var npc: Npc = NPC_SCENE.instantiate()
		npc.shop_id = String(spec.get("shopId", ""))
		npc.role = String(spec.get("role", "shop"))
		npc.npc_name = String(spec.get("npcName", ""))
		npc.greeting = String(spec.get("greeting", ""))
		npc.position = Iso.grid_to_world(_cell_of(spec))
		_npcs.add_child(npc)

## `maps.json` 的 `cell` 是 `[x, y]` 数组（JSON 无 Vector2i）。
func _cell_of(spec: Dictionary) -> Vector2i:
	var c = spec.get("cell", null)
	if c is Array:
		var arr: Array = c as Array
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO

## 抵达提示（切图 / 读档 / 新游戏开局各一次）：延后一帧调用，确保 HUD 已就绪。
func _notify_arrival() -> void:
	EventBus.toast_requested.emit("抵达　%s" % MapService.display_name(GameState.current_map), "levelup")

## 使用画布投影后的视口范围，随相机、缩放与窗口尺寸变化。
func visible_enemies() -> Array[Node2D]:
	var candidates: Array[Node2D] = []
	var rect := get_viewport_rect()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _player.valid_target(enemy) or not enemy.is_visible_in_tree():
			continue
		if rect.has_point(enemy.get_global_transform_with_canvas().origin):
			candidates.append(enemy)
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var da := _player.global_position.distance_squared_to(a.global_position)
		var db := _player.global_position.distance_squared_to(b.global_position)
		return a.get_instance_id() < b.get_instance_id() if is_equal_approx(da, db) else da < db)
	return candidates

func cycle_target() -> void:
	var candidates := visible_enemies()
	_player.manual_attack_active = false
	_player.map_move_active = false
	_player.begin_manual_command()
	if candidates.is_empty():
		_player.select_target(null)
		EventBus.toast_requested.emit("可视范围内没有目标", "info")
		return
	var index := candidates.find(_player.locked_target)
	_player.select_target(candidates[(index + 1) % candidates.size()])

func enemy_at_screen(point: Vector2) -> Node2D:
	var best: Node2D = null
	var nearest := INF
	for enemy in visible_enemies():
		var local: Vector2 = enemy.get_global_transform_with_canvas().affine_inverse() * point
		var distance := local.distance_to(Vector2(0, -Monster.RADIUS * 0.6))
		if distance <= Monster.RADIUS + 9 and distance < nearest:
			nearest = distance
			best = enemy
	return best

func _unhandled_input(event: InputEvent) -> void:
	if not GameState.panel_open and not _player.is_dead:
		if event.is_action_pressed("sit_toggle") and not event.is_echo():
			_player.set_sitting(not _player.is_sitting)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("target_next") and not event.is_echo():
			cycle_target()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			var npc := npc_at_screen(event.position)
			if npc != null:
				_request_npc_interaction(npc)
				get_viewport().set_input_as_handled()
				return
			_pending_npc = null
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_player.map_move_active = false
				_player.manual_attack_active = false
				_player.begin_manual_command()
				get_viewport().set_input_as_handled()
				return
			var enemy := enemy_at_screen(event.position)
			if enemy != null:
				_player.request_target_attack(enemy)
			else:
				var world_point: Vector2 = get_canvas_transform().affine_inverse() * event.position
				_player.request_map_move(_ground.clamp_to_map(world_point))
			get_viewport().set_input_as_handled()
			return
	# 开发期验证键（M5 移除）：H = 自伤 15，用于验证 HUD 血条实时刷新。
	if OS.is_debug_build() and event.is_action_pressed("debug_hurt"):
		GameState.damage_player(15)
		get_viewport().set_input_as_handled()
		return

	# 自动战斗 / 自动拾取（F / G，3.14 / 9.9）；面板打开时不响应
	if not GameState.panel_open:
		if event.is_action_pressed("auto_battle"):
			if not GameState.auto_battle_on:
				_player.set_sitting(false)
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
## M2：按 NPC role 派发 —— quest = 任务面板，shop = 货郎面板；
## M3-2：carter = 车夫面板（跨图出行）；M4-2：blacksmith = 铁匠对话。
func _try_interact() -> bool:
	var npc := nearest_npc()
	if npc == null:
		return false
	_pending_npc = null
	return _interact_with(npc)

func _interact_with(npc: Npc) -> bool:
	if npc.role == "quest":
		EventBus.quest_panel_requested.emit(npc.npc_name)
		return true
	if npc.role == "carter":
		EventBus.carter_panel_requested.emit(npc.npc_name)
		return true
	if npc.role == "blacksmith":
		EventBus.blacksmith_panel_requested.emit(npc.npc_name, npc.greeting)
		return true
	if npc.role == "warehouse":
		EventBus.warehouse_panel_requested.emit(npc.npc_name)
		return true
	if not npc.shop_id.is_empty():
		EventBus.shop_open_requested.emit(npc.shop_id)
		return true
	return false

## 鼠标点击 NPC：近距离直接对话，远距离先步行到 NPC，进入 2 格范围后自动打开。
func _request_npc_interaction(npc: Npc) -> void:
	_pending_npc = null
	if npc.is_player_in_range():
		_interact_with(npc)
	elif _player.request_map_move(_ground.clamp_to_map(npc.global_position)):
		_pending_npc = npc

func npc_at_screen(point: Vector2) -> Npc:
	var best: Npc = null
	var best_distance := INF
	for child in _npcs.get_children():
		var npc := child as Npc
		if npc == null or not npc.contains_screen_point(point):
			continue
		var distance := npc.get_global_transform_with_canvas().origin.distance_squared_to(point)
		if distance < best_distance:
			best = npc
			best_distance = distance
	return best

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

