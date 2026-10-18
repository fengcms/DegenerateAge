extends Node2D
## 世界根节点：装配地面、玩家、怪物生成器、安全区 NPC，设置出生点与相机边界。
## 依据产品文档 7.2（相机平滑跟随、防露边界）、7.9（怪物点刷新）、6.3（安全区 NPC）。

const NPC_SCENE := preload("res://scenes/entities/Npc.tscn")
const GROUND_ITEM_SCENE := preload("res://scenes/entities/GroundItem.tscn")

## 世界按「当前地图」数据驱动装配（M3-1）：
##   · 怪物点 → `maps.json` 的 `spawnPoints`（`MonsterSpawner.spawn_from_map`）
##   · Boss 点 → `maps.json` 的 `bossSpawn`（含墓碑刷新，M3-5 启用墓碑实体）
##   · NPC    → `maps.json` 的 `npcs`（货郎 / 任务官 / 车夫 / 铁匠）
## 切图 = 重载场景（`MapService.travel_to`，拍板 D1-A）：旧图实体随场景一并销毁（T15）。
## ⚠ 原 M1/M2 单图期的 `TEST_SPAWNS` / `TEST_ELITES` / `TEST_NPCS` 硬编码已随 M3 恢复清单移除
##   （见工程文档 13 §6 R3 与 04「M5 移除清单」）；营地保留 3 只教学木桩（产品 07 §7.6，`ai:false`）。

## 安全区 / 各图 NPC 由 `maps.json` 的 `npcs` 驱动（M3-1；原 `TEST_NPCS` 已移除）。
## `cell` 为等距网格坐标，JSON 里是 `[x, y]` 数组（见 `_cell_of`）。

@onready var _ground: IsoGround = $Ground
@onready var _player: PlayerCharacter = $Entities/Player
@onready var _camera: Camera2D = $Entities/Player/Camera2D
@onready var _spawner: MonsterSpawner = $Spawner
@onready var _npcs: Node2D = $Npcs
@onready var _exits: Node2D = $Exits
@onready var _damage_numbers: Node2D = $DamageNumbers

var _explored_cell := Vector2i(-1, -1)
var _pending_npc: Npc = null
var _pending_exit: TravelExit = null
var _quest_nav_issued := false
var _quest_nav_serial_seen := -1
var _animation_map_id := ""

func _process(_delta: float) -> void:
	if not Input.is_action_pressed("interact"):
		MapService.walk_key_released = true
	_update_exit_nearness()
	_tick_quest_navigation()
	if _player.is_dead:
		_pending_npc = null
		_pending_exit = null
		return
	if _pending_exit != null:
		if not is_instance_valid(_pending_exit) or not _pending_exit.is_inside_tree():
			_pending_exit = null
		elif Iso.world_to_grid(_player.global_position).distance_to(Iso.world_to_grid(_pending_exit.global_position)) <= MapService.WALK_RANGE_CELLS:
			var arrived_exit := _pending_exit
			_pending_exit = null
			_activate_exit(arrived_exit)
			return
		elif not _player.map_move_active:
			_pending_exit = null
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
	if _ground.is_locked_boss_area(point):
		EventBus.toast_requested.emit("先完成「最后的巡检」，打开主机场地安全锁。", "info")
		return false
	if not _player.request_map_move(_ground.clamp_to_map(point)):
		return false
	EventBus.toast_requested.emit(Localization.tr_key("msg.game.p001"), "info")
	return true

## 推进任务链接的跨图导航；抵达目标图后用稳定 NPC ID 找到真实交互对象。
func _tick_quest_navigation() -> void:
	if MapService.quest_nav_target.is_empty():
		_quest_nav_issued = false
		return
	if _player.is_dead:
		return
	# 同图重试或切换任务目标时，旧移动的“已发出”标记不可阻止新指令。
	if _quest_nav_serial_seen != MapService.quest_nav_serial:
		_quest_nav_serial_seen = MapService.quest_nav_serial
		_quest_nav_issued = false
	if GameState.current_map == MapService.quest_nav_map:
		if MapService.quest_nav_kind == "map":
			MapService.clear_quest_navigation()
			return
		if MapService.quest_nav_kind == "npc":
			var npc_id := MapService.quest_nav_target
			for child in _npcs.get_children():
				var npc := child as Npc
				if npc != null and npc.npc_id == npc_id:
					MapService.clear_quest_navigation()
					_request_npc_interaction(npc)
					return
			MapService.clear_quest_navigation()
			EventBus.toast_requested.emit(Localization.tr_key("msg.game.p002"), "danger")
			return
		var best := Vector2.ZERO
		var best_distance := INF
		for point in _spawner.marker_points():
			if String(point.get("monster_id", "")) != MapService.quest_nav_target:
				continue
			var pos: Vector2 = point.get("position", Vector2.ZERO)
			var distance := _player.global_position.distance_squared_to(pos)
			if distance < best_distance:
				best = pos
				best_distance = distance
		MapService.clear_quest_navigation()
		if best_distance == INF:
			EventBus.toast_requested.emit(Localization.tr_key("msg.game.p002"), "danger")
		else:
			_player.request_map_move(_ground.clamp_to_map(best))
			EventBus.toast_requested.emit(Localization.tr_key("msg.game.p003"), "info")
		return
	var exit_data := MapService.quest_next_exit()
	if exit_data.is_empty():
		MapService.clear_quest_navigation()
		EventBus.toast_requested.emit(Localization.tr_key("msg.game.p004"), "danger")
		return
	var cell: Array = exit_data.get("cell", [])
	if cell.size() != 2:
		MapService.clear_quest_navigation()
		return
	var exit_pos := Iso.grid_to_world(Vector2i(int(cell[0]), int(cell[1])))
	if Iso.world_to_grid(_player.global_position).distance_to(Vector2(float(cell[0]), float(cell[1]))) <= MapService.WALK_RANGE_CELLS:
		if MapService.can_use_walk_exit():
			var result := MapService.request_walk(String(exit_data.get("id", "")), _player.global_position)
			if bool(result.get("ok", false)):
				MapService.reload_world()
			else:
				MapService.clear_quest_navigation()
				EventBus.toast_requested.emit(String(result.get("reason", Localization.tr_key("msg.game.p005"))), "danger")
		return
	if not _quest_nav_issued:
		_quest_nav_issued = _player.request_map_move(_ground.clamp_to_map(exit_pos))
	elif not _player.map_move_active:
		MapService.clear_quest_navigation()
		EventBus.toast_requested.emit(Localization.tr_key("msg.game.p006"), "danger")

## 按当前地图装配世界，并在 NPC 生成后初始化和订阅任务标记刷新。
func _ready() -> void:
	# 出行事务只在目标地图地面与必要节点就绪后提交；失败则恢复源图。
	if not MapService.pending_travel.is_empty() and (not MapService.exists(GameState.current_map)
			or _ground.map_id != GameState.current_map or _ground.grid_size.x <= 0
			or _ground.grid_size.y <= 0 or _player == null or _spawner == null):
		MapService.rollback_travel()
		MapService.reload_world()
		return
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
		pilot.reset_after_travel()

	# 相机限制到地图包围盒，避免露出边界外的空白
	var b: Rect2 = _ground.get_world_bounds()
	_camera.limit_left = int(b.position.x)
	_camera.limit_top = int(b.position.y)
	_camera.limit_right = int(b.end.x)
	_camera.limit_bottom = int(b.end.y)
	# M5-9b（09-A）：切图 reload 会重建 Player/Camera2D，故在装配相机处补应用一次地图倍率。
	SettingsRuntime.apply_map_scale_to(_camera)
	_camera.reset_smoothing()

	# 怪物实例生成前准备本图正式动画；切图释放由 _exit_tree 对应处理。
	_animation_map_id = GameState.current_map
	MonsterAnimationCache.prepare_for_map(_animation_map_id)
	# 怪物点 / Boss 点 / NPC：全部按当前地图数据装配（M3-1）
	_ground.add_child(RestZoneOverlay.new())
	_spawner.setup(_ground, _player)
	_spawner.spawn_from_map(GameState.current_map)
	var bosses := MapService.current_bosses()
	if not bosses.is_empty():
		_spawner.spawn_from_specs(bosses, GameState.current_map)

	# 各图 NPC（M3-1：由 maps.json 的 npcs 驱动）
	_spawn_npcs()
	EventBus.quest_state_changed.connect(_refresh_npc_quest_markers)
	EventBus.data_loaded.connect(_refresh_npc_quest_markers)
	_refresh_npc_quest_markers()
	_spawn_exits()

	# M6-0c（创意 07 §11.2）：重建本图未领取战利品 —— 切图 / 读档后恢复，跨档不丢
	_rebuild_unclaimed_loot()
	if not MapService.commit_arrival():
		MapService.reload_world()
		return

	# 抵达提示（切图 / 读档后给一次系统提示；延后一帧等 HUD 就绪）
	_notify_arrival.call_deferred()
	# M10-5（D-6）：跨图追猎的「落地自动走」。只在 `commit_arrival()` 成功之后消费 ——
	# 上面的提前 return 已保证失败路径到不了这里；读档路径从不 arm，所以是空操作。
	_consume_landing_move.call_deferred()

	add_to_group("map_world")
	Fog.reveal(GameState.current_map, Vector2i(Iso.world_to_grid(_player.global_position).round()))

## 世界退场时释放本图正式动画缓存；若切图事务已改变全局地图 ID，仍按旧图身份释放。
func _exit_tree() -> void:
	if not _animation_map_id.is_empty():
		MonsterAnimationCache.release_for_map(_animation_map_id)

## 按当前地图的 NPC 点生成（6.3）。数据源：`maps.json` 的 `npcs`（M3-1 数据化）。
func _spawn_npcs() -> void:
	for spec in MapService.current_npcs():
		if not (spec is Dictionary):
			continue
		var npc: Npc = NPC_SCENE.instantiate()
		npc.npc_id = String(spec.get("npcId", ""))
		npc.shop_id = String(spec.get("shopId", ""))
		npc.role = String(spec.get("role", "shop"))
		npc.npc_name = String(spec.get("npcName", ""))
		npc.greeting = String(spec.get("greeting", ""))
		npc.position = Iso.grid_to_world(_cell_of(spec))
		_npcs.add_child(npc)

## 只在任务状态或数据变化、世界装配后重算可接标记；不在逐帧热路径扫描任务。
func _refresh_npc_quest_markers() -> void:
	var available := Quest.available_givers_on_map(GameState.current_map)
	for child in _npcs.get_children():
		var npc := child as Npc
		if npc != null:
			npc.set_quest_marker(available.has(npc.npc_id))

func _spawn_exits() -> void:
	for spec in MapService.current_exits():
		if not (spec is Dictionary):
			continue
		var exit_node := TravelExit.new()
		exit_node.exit_id = String(spec.get("id", ""))
		exit_node.to_map = String(spec.get("toMap", ""))
		exit_node.position = Iso.grid_to_world(_cell_of(spec))
		_exits.add_child(exit_node)

func _update_exit_nearness() -> void:
	var nearest := nearest_exit()
	for child in _exits.get_children():
		var exit_node := child as TravelExit
		if exit_node != null:
			exit_node.set_player_near(exit_node == nearest and not GameState.world_controls_blocked() and not _player.is_dead)

func nearest_exit() -> TravelExit:
	var player_cell := Iso.world_to_grid(_player.global_position)
	var best: TravelExit = null
	var best_distance := MapService.WALK_RANGE_CELLS
	for child in _exits.get_children():
		var exit_node := child as TravelExit
		if exit_node == null:
			continue
		var distance := player_cell.distance_to(Iso.world_to_grid(exit_node.global_position))
		if distance <= best_distance:
			best = exit_node
			best_distance = distance
	return best

## M6-0c（创意 07 §11.2）：进入地图时重建本图未领取战利品，跨图 / 跨档不丢。
## 重建物为「已登记」状态：`auto_claim=false`（不重复结算 / 不再飞向玩家）、`persistent=true`
## （不走 60s 淡出），依靠靠近 / 点击拾取；领取成功再注销记录（见 `GroundItem`）。
## 落点夹回图内 —— §11.4 的完整可走网格校验待障碍系统落地后再补（当前至少保证边界内）。
func _rebuild_unclaimed_loot() -> void:
	var records := GameState.unclaimed_loot_for(GameState.current_map)
	if records.is_empty():
		return
	var layer := get_tree().get_first_node_in_group("loot_root")
	if layer == null:
		return
	for record in records:
		if not (record is Dictionary):
			continue
		var item_v: Variant = (record as Dictionary).get("item", {})
		if not (item_v is Dictionary) or (item_v as Dictionary).is_empty():
			continue
		var gi: GroundItem = GROUND_ITEM_SCENE.instantiate()
		gi.item = (item_v as Dictionary).duplicate(true)
		gi.auto_claim = false
		gi.persistent = true
		gi.batch_id = String((record as Dictionary).get("batchId", ""))
		gi.claim_uid = String((record as Dictionary).get("uid", ""))
		layer.add_child(gi)
		var pos_v: Variant = (record as Dictionary).get("pos", Vector2.ZERO)
		var pos: Vector2 = pos_v if pos_v is Vector2 else Vector2.ZERO
		gi.global_position = _ground.clamp_to_map(pos)

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
	EventBus.toast_requested.emit(Localization.tr_key("msg.game.p007") % MapService.display_name(GameState.current_map), "levelup")

## 消费一次落地意图：把玩家直接指挥向目标点（跨图追猎）。
## 一次性语义由 `MapService.consume_landing_move()` 保证；无意图即什么都不做。
func _consume_landing_move() -> void:
	var target: Variant = MapService.consume_landing_move()
	if not target is Vector2:
		return
	if _player == null or _player.is_dead:
		return
	if not request_map_move(target):
		return
	EventBus.toast_requested.emit(Localization.tr_key("ui.boss_token_panel.p010"), "info")

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
		EventBus.toast_requested.emit(Localization.tr_key("msg.game.p008"), "info")
		return
	var index := candidates.find(_player.locked_target)
	_player.select_target(candidates[(index + 1) % candidates.size()])

func enemy_at_screen(point: Vector2) -> Node2D:
	var best: Node2D = null
	var nearest := INF
	for enemy in visible_enemies():
		# M6-0a：命中半径取怪物**自身**档次半径（普通 13 / 精英 19 / Boss 36），
		# 与 `Monster._draw` 同源，避免"大 Boss 画得大却点不中"。
		var mon := enemy as Monster
		var r := Monster.RADIUS
		if mon != null:
			r = mon.radius
		var local: Vector2 = enemy.get_global_transform_with_canvas().affine_inverse() * point
		var distance := local.distance_to(Vector2(0, -r * 0.6))
		var art_hit := mon != null and (mon.sample_art != null or mon.dummy_art != null) and Rect2(-36, -52, 72, 56).has_point(local)
		if mon != null and mon.sample_art is MonsterActorArt:
			art_hit = (mon.sample_art as MonsterActorArt).actor_hit_rect().has_point(local)
		if (distance <= r + 9.0 or art_hit) and distance < nearest:
			nearest = distance
			best = enemy
	return best

## Tab 是世界目标切换键，须在 GUI 焦点处理之前接管；模态面板与文本输入仍优先。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("target_next") and not event.is_echo() \
			and not GameState.world_controls_blocked() and _player != null and not _player.is_dead:
		cycle_target()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# 坐骑切换沿用 GameState 的骑乘/下马规则，不受普通浮窗打开状态影响。
	if event.is_action_pressed("mount_toggle") and not event.is_echo() and not GameState.world_controls_blocked():
		if _player != null and not _player.is_dead:
			GameState.toggle_mount()
			get_viewport().set_input_as_handled()
		return
	if not GameState.world_controls_blocked() and not _player.is_dead:
		if event.is_action_pressed("sit_toggle") and not event.is_echo():
			_player.set_sitting(not _player.is_sitting)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			if event.button_index == MOUSE_BUTTON_LEFT:
				var clicked_exit := exit_at_screen(event.position)
				if clicked_exit != null:
					_request_exit_interaction(clicked_exit)
					get_viewport().set_input_as_handled()
					return
			var npc := npc_at_screen(event.position)
			if npc != null:
				_pending_exit = null
				_request_npc_interaction(npc)
				get_viewport().set_input_as_handled()
				return
			_pending_npc = null
			_pending_exit = null
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
	# F 是全局挂机开关，面板打开时也必须能操作；NPC 会话只暂停决策，不禁用开关。
	if event.is_action_pressed("auto_battle") and not event.is_echo() and not GameState.world_controls_blocked():
		if not GameState.auto_battle_on:
			_player.set_sitting(false)
		GameState.toggle_auto_battle()
		get_viewport().set_input_as_handled()
		return
	# 自动拾取（G）在普通面板打开时仍可切换。
	if not GameState.world_controls_blocked():
		if event.is_action_pressed("auto_pickup"):
			GameState.toggle_auto_pickup()
			get_viewport().set_input_as_handled()
			return

	# 与 NPC 交互（6.3 通用交互）：模态流程接管时才屏蔽；普通面板可边走边交互。
	if event.is_action_pressed("interact") and not event.is_echo() and not GameState.world_controls_blocked() and not _player.is_dead:
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
	var exit_node := nearest_exit()
	if exit_node != null:
		_activate_exit(exit_node)
		return true
	var npc := nearest_npc()
	if npc == null:
		return false
	_pending_npc = null
	_focus_npc(npc)
	return _interact_with(npc)

func _activate_exit(exit_node: TravelExit) -> void:
	var result := MapService.request_walk(exit_node.exit_id, _player.global_position)
	if bool(result.get("ok", false)):
		_pending_npc = null
		_pending_exit = null
		MapService.reload_world()
	else:
		EventBus.toast_requested.emit(String(result.get("reason", Localization.tr_key("msg.game.p009"))), "danger")

func _request_exit_interaction(exit_node: TravelExit) -> void:
	_pending_npc = null
	_pending_exit = null
	if not MapService.is_unlocked(exit_node.to_map):
		EventBus.toast_requested.emit(Localization.tr_key("msg.game.p010") % MapService.display_name(exit_node.to_map), "danger")
		return
	if Iso.world_to_grid(_player.global_position).distance_to(Iso.world_to_grid(exit_node.global_position)) <= MapService.WALK_RANGE_CELLS:
		_activate_exit(exit_node)
	elif _player.request_map_move(_ground.clamp_to_map(exit_node.global_position)):
		_pending_exit = exit_node

func exit_at_screen(point: Vector2) -> TravelExit:
	var best: TravelExit = null
	var nearest := INF
	for child in _exits.get_children():
		var exit_node := child as TravelExit
		if exit_node == null or not exit_node.contains_screen_point(point):
			continue
		var distance := exit_node.get_global_transform_with_canvas().origin.distance_squared_to(point)
		if distance < nearest:
			best = exit_node
			nearest = distance
	return best

## 使用 NPC 的稳定配置 ID 分流任务与服务交互，避免同名 NPC 被误认。
func _interact_with(npc: Npc) -> bool:
	var npc_id := npc.npc_id
	Quest.on_npc_talk(npc_id)
	if not npc_id.is_empty() and Quest.has_actionable_at_npc(npc_id):
		EventBus.quest_panel_requested.emit(npc_id)
		return true
	if npc.role == "quest":
		EventBus.quest_panel_requested.emit(npc_id if not npc_id.is_empty() else npc.npc_name)
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
	_focus_npc(npc)
	if npc.is_player_in_range():
		_interact_with(npc)
	elif _player.request_map_move(_ground.clamp_to_map(npc.global_position)):
		_pending_npc = npc

## NPC 只进入界面观察目标；战斗目标仍由 PlayerCharacter 严格筛选怪物。
func _focus_npc(npc: Npc) -> void:
	_player.clear_travel_intent()
	EventBus.target_changed.emit(npc)

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

