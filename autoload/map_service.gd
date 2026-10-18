extends Node
## MapService — 地图查询与车夫出行服务（M3-1 / M3-2）。
##
## 依据：产品文档 07 §7.3（地图加载与释放）/ §7.8（地图清单与车夫拓扑）、06 §6.6（车夫）。
##
## 职责：
##   ① 读 DataLoader 聚合的地图表提供地图查询（存在性 / 显示名 / 拓扑 / 费用 / NPC 点 / 目的地列表）；
##   ② 车夫出行校验链：存在 → 非当前图 → 拓扑可达 → 已解锁 → 金币足够 → 扣费；
##   ③ 成功后写 `GameState.current_map` + `save_pos`，并**重载当前场景**（拍板 D1-A）。
##
## 为什么是 Autoload 而非 class_name 静态类：出行最后一步需要 `get_tree()` 重载场景，
## `RefCounted` 静态类拿不到 `SceneTree`。
##
## 出行后场景重载的行为（务必理解）：
##   `Game._ready()` 会读 `GameState.save_pos` 把玩家放到落点（消费一次即清空），
##   `IsoGround._ready()` 会按 `GameState.current_map` 重新加载地面与边界，
##   `MonsterSpawner` 会按新图 `spawnPoints` / `bossSpawn` 重新生成 —— 旧图实体随场景一并销毁（T15）。

## 新游戏的起始地图（与 GameState.reset_to_defaults 口径一致）。
const DEFAULT_MAP := "camp"
const WALK_RANGE_CELLS := 1.5
const WALK_ARRIVAL_LOCK_MSEC := 1000

## 跨场景保留防抖状态；仅步行出口使用，车夫线路不受影响。
var walk_locked_until_msec: int = 0
var walk_key_released: bool = true
## 请求与世界装配之间的运行态事务；绝不写入存档。
var pending_travel: Dictionary = {}
## M10-5（产品 13 §5.4 D-6）：**落地后自动走**的一次性意图（Vector2 或 null）。
## 与 `save_pos` 同口径 —— 消费一次即清空、不写存档、读档路径不 arm 所以不启用。
## 由追猎令牌跨图时 arm；`Game._ready` 提交抵达后消费，指挥玩家走向目标 Boss。
var pending_landing_move: Variant = null
var loading_active := false
var loading_message := ""
var _loading_token := 0
var _entry_cache: Dictionary = {}
## 安全区矩形缓存（静态数据，`data_loaded` 时失效）：避免每次安全区判定重解析配置。
var _safe_area_cache: Dictionary = {}

func _ready() -> void:
	EventBus.data_loaded.connect(func() -> void: _entry_cache.clear())
	EventBus.data_loaded.connect(func() -> void: _safe_area_cache.clear())

## 任务目标导航只在运行中保留；跨图重载继续，普通存档不保存这条临时指令。
var quest_nav_target: String = ""
var quest_nav_map: String = ""
var quest_nav_kind: String = ""
## 每次玩家发起导航都递增；世界节点用它区分新指令与上次已结束的移动。
var quest_nav_serial := 0

func clear_quest_navigation() -> void:
	quest_nav_target = ""
	quest_nav_map = ""
	quest_nav_kind = ""

func start_quest_navigation(monster_id: String, allowed_maps: Array) -> Dictionary:
	return start_quest_link_navigation("monster", monster_id, allowed_maps)

func start_quest_link_navigation(kind: String, target_id: String, allowed_maps: Array) -> Dictionary:
	var route := _find_quest_route(kind, target_id, allowed_maps)
	if bool(route.get("ok", false)):
		quest_nav_kind = kind
		quest_nav_target = target_id
		quest_nav_map = String(route.get("map", ""))
		quest_nav_serial += 1
	return route

## 只计算已解锁道路的下一跳，不修改导航状态；跨图每帧查询可安全复用。
func _find_quest_route(kind: String, target_id: String, allowed_maps: Array) -> Dictionary:
	var queue: Array[String] = [GameState.current_map]
	var visited := {GameState.current_map: true}
	var first_hop := {GameState.current_map: ""}
	while not queue.is_empty():
		var map_id: String = queue.pop_front()
		if allowed_maps.has(map_id) and _map_has_quest_target(map_id, kind, target_id):
			return {"ok": true, "map": map_id, "first_hop": first_hop[map_id]}
		for exit_data in data_for(map_id).get("exits", []):
			var next_id := String(exit_data.get("toMap", ""))
			if next_id.is_empty() or visited.has(next_id) or not is_unlocked(next_id):
				continue
			# 正向锁未开的边不进导航路径：否则会指一条走到跟前打不开的路。
			if not _exit_open(exit_data):
				continue
			visited[next_id] = true
			first_hop[next_id] = next_id if map_id == GameState.current_map else first_hop[map_id]
			queue.append(next_id)
	return {"ok": false, "reason": Localization.tr_key("msg.map_service.p001")}

func quest_next_exit() -> Dictionary:
	if quest_nav_target.is_empty() or quest_nav_map.is_empty():
		return {}
	var route := _find_quest_route(quest_nav_kind, quest_nav_target, [quest_nav_map])
	if not bool(route.get("ok", false)):
		return {}
	var hop := String(route.get("first_hop", ""))
	for exit_data in current_exits():
		if String(exit_data.get("toMap", "")) == hop:
			return exit_data
	return {}

## M10-5（F-1）：Boss 一侧必须走 `current_bosses_of()` —— 只查单点 `bossSpawn` 时，
## `c7_arena` 这类只有 `bossSpawns` 的图恒 false，任务导航指不到、追猎令牌也哑火。
func _map_has_monster(map_id: String, monster_id: String) -> bool:
	var map_data := data_for(map_id)
	for spec in map_data.get("spawnPoints", []):
		if String(spec.get("monsterId", "")) == monster_id and int(spec.get("count", 1)) > 0:
			return true
	for boss in current_bosses_of(map_id):
		if boss is Dictionary and String((boss as Dictionary).get("monsterId", "")) == monster_id:
			return true
	return false

func _map_has_quest_target(map_id: String, kind: String, target_id: String) -> bool:
	match kind:
		"monster":
			return _map_has_monster(map_id, target_id)
		"npc":
			for spec in data_for(map_id).get("npcs", []):
				if String(spec.get("npcId", "")) == target_id:
					return true
		"map":
			return map_id == target_id
	return false

func map_for_npc(npc_id: String) -> String:
	for entry in DataLoader.get_table("maps"):
		if entry is Dictionary:
			var map_id := String(entry.get("id", ""))
			if _map_has_quest_target(map_id, "npc", npc_id):
				return map_id
	return ""

func npc_name(npc_id: String) -> String:
	var map_id := map_for_npc(npc_id)
	for spec in data_for(map_id).get("npcs", []):
		if String(spec.get("npcId", "")) == npc_id:
			return String(spec.get("npcName", npc_id))
	return npc_id

# ---- 查询 ----

func data_for(map_id: String) -> Dictionary:
	var entry: Variant = DataLoader.get_entry("maps", map_id)
	return entry if entry is Dictionary else {}

func grid_size(map_id: String) -> Vector2i:
	var dims: Dictionary = data_for(map_id).get("size", {})
	return Vector2i(int(dims.get("w", 0)), int(dims.get("h", 0)))


## 当前地图数据（未找到 → 空字典）。
func current_data() -> Dictionary:
	var m = DataLoader.get_entry("maps", GameState.current_map)
	return m if m is Dictionary else {}

## 地图是否存在（maps.json 内有定义）。
func exists(map_id: String) -> bool:
	return DataLoader.get_entry("maps", map_id) is Dictionary

## 地图显示名（无则回退 id）。
func display_name(map_id: String) -> String:
	var m = DataLoader.get_entry("maps", map_id)
	if m is Dictionary:
		return String((m as Dictionary).get("name", map_id))
	return map_id

## 当前图的推荐进入等级（HUD / 车夫面板提示用）。
func recommended_level(map_id: String) -> int:
	var m = DataLoader.get_entry("maps", map_id)
	if m is Dictionary:
		return int((m as Dictionary).get("recommendedLevel", 1))
	return 1

## 当前图是否安全区（6.3）。
func is_safe_zone(map_id: String) -> bool:
	var m = DataLoader.get_entry("maps", map_id)
	if m is Dictionary:
		return bool((m as Dictionary).get("safeZone", false))
	return false

## 供回城卷与免费复活共用：返回地图所属集群中已解锁的安全城镇。
## hubId 缺失、城镇配置无效或尚未解锁时返回空串，不擅自送往起始营地。
func safe_town_for(map_id: String) -> String:
	var town_id := String(data_for(map_id).get("hubId", ""))
	if town_id.is_empty() or not exists(town_id) or not is_safe_zone(town_id) or not is_unlocked(town_id):
		return ""
	return town_id

# ---- 车夫拓扑与费用 ----

## 所属集群及枢纽相邻集群；按配置顺序去重。
func links() -> Array:
	var out: Array = []
	var hub_id := String(current_data().get("hubId", ""))
	var hub := data_for(hub_id)
	if hub.is_empty():
		return out
	out.append(hub_id)
	for map_data in DataLoader.get_table("maps"):
		if map_data is Dictionary and String(map_data.get("hubId", "")) == hub_id:
			var id := String(map_data.get("id", ""))
			if not out.has(id):
				out.append(id)
	for linked in hub.get("hubLinks", []):
		if not out.has(linked):
			out.append(linked)
	out.erase(GameState.current_map)
	return out

## 从当前图能否直达目标图（无需中转）。
func is_linked(to_id: String) -> bool:
	return links().has(to_id)

## 目标图的解锁条件键（`maps.json.requiresUnlock`；空 = 无需解锁）。
func unlock_requirement(map_id: String) -> String:
	var m = DataLoader.get_entry("maps", map_id)
	if m is Dictionary:
		return String((m as Dictionary).get("requiresUnlock", ""))
	return ""

## 目标图是否已解锁（无 requiresUnlock → 恒 true；否则查 GameState.unlocks）。
func is_unlocked(map_id: String) -> bool:
	var need := unlock_requirement(map_id)
	if need.is_empty():
		return true
	return bool(GameState.unlocks.get(need, false))

# ---- 门禁（E1；工程文档 30 §4，31 §4）----

## 出口自带的正向锁（`exits[].requiresUnlock`；缺省/空 → 这一边无条件）。
## 返回边一律不配置该字段，因此返回永远不锁；正向只在对应任务 `rewarded` 后解除。
func exit_requirement(exit_data: Dictionary) -> String:
	return String(exit_data.get("requiresUnlock", ""))

## 解锁键的产出任务（`reward.unlock` / `reward.unlocks`）；空 = 无人产出。
## 启动校验会拦下无人产出的键（`DataLoader._validate_gate_flags`），避免内容永久死锁。
func unlock_source(flag: String) -> Dictionary:
	if flag.is_empty():
		return {}
	var quests = DataLoader.get_table("quests")
	if not (quests is Array):
		return {}
	for entry in (quests as Array):
		if not entry is Dictionary:
			continue
		var reward: Variant = (entry as Dictionary).get("reward", null)
		if not reward is Dictionary:
			continue
		var single := String((reward as Dictionary).get("unlock", ""))
		if single == flag:
			return entry
		var list: Variant = (reward as Dictionary).get("unlocks", [])
		if list is Array and (list as Array).has(flag):
			return entry
	return {}

## 目标图未解锁的原因：能定位到产出该键的任务时，指明交付人与任务名（31 §6）。
func locked_reason(map_id: String) -> String:
	return _locked_by(unlock_requirement(map_id), map_id)

## 出口边是否已开放（返回边没有 `requiresUnlock` → 恒开）。
func _exit_open(exit_data: Dictionary) -> bool:
	var need := exit_requirement(exit_data)
	return need.is_empty() or bool(GameState.unlocks.get(need, false))

## 以解锁键为口径给出封锁说明；定位不到产出任务时退回简短文案。
func _locked_by(flag: String, map_id: String) -> String:
	var quest := unlock_source(flag)
	if not quest.is_empty():
		var turn_in := String(quest.get("turnIn", quest.get("giver", "")))
		var npc_label := npc_name(turn_in)
		if not npc_label.is_empty():
			return Localization.tr_key("msg.map_service.p023") % [display_name(map_id), npc_label, String(quest.get("name", flag))]
	return Localization.tr_key("msg.map_service.p008") % display_name(map_id)

## 显式逐对价格优先；其次取目标图对本图的反向显式报价（保证枢纽↔首领图双向同价）；
## 否则使用所属枢纽对目标类型的缺省价。
func fee_to(map_id: String) -> int:
	var fees: Variant = current_data().get("carterFares", {})
	if fees is Dictionary and fees.has(map_id):
		return int(fees[map_id])
	var target_fees: Variant = data_for(map_id).get("carterFares", {})
	var here := String(current_data().get("id", ""))
	if target_fees is Dictionary and target_fees.has(here):
		return int(target_fees[here])
	var hub := data_for(String(current_data().get("hubId", "")))
	var defaults: Variant = hub.get("carterFare", {})
	var kind := String(data_for(map_id).get("kind", ""))
	if defaults is Dictionary and defaults.has(kind):
		return int(defaults[kind])
	return -1

## 当前图 NPC 点原始数据（`maps.json.npcs`；cell 为 `[x, y]` 数组）。
func current_npcs() -> Array:
	var n = current_data().get("npcs", [])
	return n if n is Array else []

## 当前图**全部** Boss 点规格（M10-3b / P-8，工程文档 44 §3.2）：`bossSpawns` 数组优先，
## 回退单点 `bossSpawn`，都没有 → 空数组。只返回配置规格（未实例化、无运行状态）——
## 运行态实例目前**零调用方**（血条走 `EventBus.boss_hp_changed`、小地图走
## `Spawner.marker_points()`），真到需要时再加，避免养一个跟着切图/重生维护生命周期的 API。
## 任意地图的**全部** Boss 点规格（M10-5）：`bossSpawns` 数组优先，回退单点 `bossSpawn`，
## 都没有 → 空数组。`current_bosses()` 只是它的当前图转发 —— **不在两处各写一份同逻辑**，
## 否则将来改一处漏一处（追猎令牌遍历全表时用的是本函数）。
func current_bosses_of(map_id: String) -> Array:
	var rows: Variant = data_for(map_id).get("bossSpawns", null)
	if rows is Array and not (rows as Array).is_empty():
		return rows
	var single: Variant = data_for(map_id).get("bossSpawn", null)
	return [single] if single is Dictionary else []

func current_bosses() -> Array:
	return current_bosses_of(GameState.current_map)

## ⚠ 兼容壳：**只给单点图用**，多 Boss 图请用 `current_bosses()`（本函数只返回第 0 只）。
func current_boss() -> Dictionary:
	var rows := current_bosses()
	return rows[0] if not rows.is_empty() else {}

func current_exits() -> Array:
	var exits = current_data().get("exits", [])
	return exits if exits is Array else []

## 只有配置了 safeArea 的城镇拥有局部免战区；min/max 是包含端点的逻辑格。
func safe_area_cells(map_id: String) -> Rect2:
	if _safe_area_cache.has(map_id):
		return _safe_area_cache[map_id]
	var rect := _compute_safe_area_cells(map_id)
	_safe_area_cache[map_id] = rect
	return rect

func _compute_safe_area_cells(map_id: String) -> Rect2:
	var data := data_for(map_id)
	var area: Variant = data.get("safeArea", null)
	if not bool(data.get("safeZone", false)) or not area is Dictionary:
		return Rect2()
	var lower: Variant = area.get("min", [])
	var upper: Variant = area.get("max", [])
	if not lower is Array or not upper is Array or lower.size() != 2 or upper.size() != 2:
		return Rect2()
	var first := Vector2(float(lower[0]), float(lower[1]))
	var last := Vector2(float(upper[0]), float(upper[1]))
	return Rect2(first, last - first)

func is_in_safe_area(map_id: String, world_position: Vector2) -> bool:
	var area := safe_area_cells(map_id)
	if not area.has_area():
		return false
	var cell := Iso.world_to_grid(world_position)
	return cell.x >= area.position.x - 0.5 and cell.x <= area.end.x + 0.5 \
		and cell.y >= area.position.y - 0.5 and cell.y <= area.end.y + 0.5

## 兼容已有战斗、刷怪调用；判定语义已统一为「城镇矩形安全区」。
func is_in_rest_zone(map_id: String, world_position: Vector2) -> bool:
	return is_in_safe_area(map_id, world_position)

func carter_arrival(map_id: String) -> Vector2:
	var cell: Variant = data_for(map_id).get("carterArrival", null)
	if cell is Array and cell.size() == 2:
		return Iso.grid_to_world(Vector2i(int(cell[0]), int(cell[1])))
	return entry_point(map_id)

func walk_exit(exit_id: String) -> Dictionary:
	for entry in current_exits():
		if entry is Dictionary and String(entry.get("id", "")) == exit_id:
			return entry
	return {}

func can_use_walk_exit() -> bool:
	return walk_key_released and Time.get_ticks_msec() >= walk_locked_until_msec

## 步行只接受本图已配置的出口，且必须在逻辑网格 1.5 格内。
## 不读车夫费用；出口落点由目标图入口 ID 决定。
func request_walk(exit_id: String, player_world: Vector2) -> Dictionary:
	if not pending_travel.is_empty():
		return _fail(Localization.tr_key("msg.map_service.p002"))
	if not can_use_walk_exit():
		return _fail(Localization.tr_key("msg.map_service.p003"))
	var exit_data := walk_exit(exit_id)
	if exit_data.is_empty():
		return _fail(Localization.tr_key("msg.map_service.p004"))
	var to_id := String(exit_data.get("toMap", ""))
	if not exists(to_id) or to_id == GameState.current_map:
		return _fail(Localization.tr_key("msg.map_service.p005"))
	var cell: Variant = exit_data.get("cell", null)
	if not cell is Array or cell.size() != 2:
		return _fail(Localization.tr_key("msg.map_service.p006"))
	var player_cell := Iso.world_to_grid(player_world)
	if player_cell.distance_to(Vector2(float(cell[0]), float(cell[1]))) > WALK_RANGE_CELLS:
		return _fail(Localization.tr_key("msg.map_service.p007"))
	if not _exit_open(exit_data):
		return _fail(_locked_by(exit_requirement(exit_data), to_id))
	if not is_unlocked(to_id):
		return _fail(locked_reason(to_id))
	var entrance_id := String(exit_data.get("toEntrance", ""))
	var entrances: Variant = data_for(to_id).get("entrances", null)
	if not entrances is Dictionary or not entrances.has(entrance_id):
		return _fail(Localization.tr_key("msg.map_service.p009"))
	var arrival: Variant = entrances[entrance_id]
	if not arrival is Array or arrival.size() != 2:
		return _fail(Localization.tr_key("msg.map_service.p010"))
	var result := _prepare_travel(to_id, "walk", 0, Iso.grid_to_world(Vector2i(int(arrival[0]), int(arrival[1]))))
	if not bool(result.ok):
		return result
	walk_key_released = false
	walk_locked_until_msec = Time.get_ticks_msec() + WALK_ARRIVAL_LOCK_MSEC
	return result

## 车夫可达目的地列表（供 CarterPanel 渲染）：
##   [{id, name, recommendedLevel, cost, unlocked, reason}]
func destinations() -> Array:
	var out: Array = []
	for lid in links():
		var id := String(lid)
		if not exists(id):
			continue
		var visited := GameState.is_visited(id)
		var taught := GameState.current_map == DEFAULT_MAP and id == "wild_trial"
		var unlocked := is_unlocked(id) and (visited or taught)
		var reason := ""
		if not is_unlocked(id):
			reason = Localization.tr_key("msg.map_service.p011")
		elif not visited and not taught:
			reason = Localization.tr_key("msg.map_service.p012")
		out.append({
			"id": id,
			"name": display_name(id),
			"recommendedLevel": recommended_level(id),
			"cost": fee_to(id),
			"unlocked": unlocked,
			"visited": visited,
			"reason": reason,
		})
	return out

# ---- 出行 ----

## 车夫出行：校验 → 扣费 → 切换地图 → 写落点（**不改场景**）。
## 返回 `{ok: bool, reason: String}`（失败原因明确，不静默）。
##
## ⚠ 场景重载**不在此处**做：拆到 `reload_world()`，由 UI 侧在成功后调用。
## 这样无头测试可以只验证「状态 + 扣费 + 落点」而不触发 `reload_current_scene`
## （否则在 SmokeTest 里调用会把测试场景本身重载掉）。
func travel_to(map_id: String) -> Dictionary:
	return _travel(map_id, true, fee_to(map_id))

## M10-5（产品 13 §5.4）：随身车夫 —— 去**任何走过的地图**，不要求拓扑相邻。
## 与 `travel_to` 共用 `_travel_checks` / `_travel` 同一段实现（只差一个 require_linked），
## 复制整段会让两条 API 各自演化后静默分叉（工程 46 §6 R-2）。
## 费用口径 `fee_anywhere`（20 × 推荐等级，下限 50），与当地车夫的 `carterFares` 并存：
## 同一目的地可能存在两个价，这是产品定义的「便利溢价」，不是 bug。
func travel_anywhere(map_id: String) -> Dictionary:
	return _travel(map_id, false, fee_anywhere(map_id))

## 任意地图的随身车夫报价：`max(50, 20 × 推荐进入等级)`；图不存在 → -1。
func fee_anywhere(map_id: String) -> int:
	if not exists(map_id):
		return -1
	return maxi(50, 20 * recommended_level(map_id))

## 出行公共段：校验链 → 报价 → 扣费 → 写落点。`require_linked` 是两条 API 的**唯一**差异。
func _travel(map_id: String, require_linked: bool, fee: int) -> Dictionary:
	var verdict := _travel_checks(map_id, require_linked)
	if not bool(verdict.get("ok", false)):
		return verdict
	if fee < 0:
		return _fail(Localization.tr_key("msg.map_service.p018") % display_name(map_id))
	if fee > 0 and GameState.gold < fee:
		return _fail(Localization.tr_key("msg.map_service.p019") % [display_name(map_id), fee, GameState.gold])
	return _prepare_travel(map_id, "carter", fee, carter_arrival(map_id))

## 存在 → 非当前图 →（可选）拓扑可达 → 已解锁 → 已到访 的判定链。
## 顺序与文案与原 `travel_to` 逐条一致（抽取不改语义）。
func _travel_checks(map_id: String, require_linked: bool) -> Dictionary:
	if not pending_travel.is_empty():
		return _fail(Localization.tr_key("msg.map_service.p002"))
	if not exists(map_id):
		return _fail(Localization.tr_key("msg.map_service.p013") % map_id)
	if map_id == GameState.current_map:
		return _fail(Localization.tr_key("msg.map_service.p014") % display_name(map_id))
	if require_linked and not is_linked(map_id):
		return _fail(Localization.tr_key("msg.map_service.p015") % display_name(map_id))
	if not is_unlocked(map_id):
		return _fail(Localization.tr_key("msg.map_service.p016") % display_name(map_id))
	if not GameState.is_visited(map_id) and not (GameState.current_map == DEFAULT_MAP and map_id == "wild_trial"):
		return _fail(Localization.tr_key("msg.map_service.p017") % display_name(map_id))
	return {"ok": true, "reason": ""}

func _prepare_travel(to_id: String, mode: String, fee: int, arrival: Vector2) -> Dictionary:
	if not pending_travel.is_empty():
		return _fail(Localization.tr_key("msg.map_service.p002"))
	pending_travel = {
		"from": GameState.current_map, "to": to_id, "mode": mode, "fee": fee,
		"gold": GameState.gold, "save_pos": GameState.save_pos,
		"has_save_pos": GameState.has_save_pos,
		"scene_path": get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "",
	}
	GameState.gold -= fee
	GameState.current_map = to_id
	GameState.save_pos = arrival
	GameState.has_save_pos = true
	GameState.close_all_panels()
	return {"ok": true, "reason": ""}

## 记录一条「落地后自动走」意图（M10-5）。只应在出行**成功之后**调用，
## 否则会留下一条永不消费、却会作用于下一次抵达的幽灵指令。
func arm_landing_move(world_pos: Vector2) -> void:
	pending_landing_move = world_pos

## 消费一次即清空；无意图 → null。
func consume_landing_move() -> Variant:
	var out: Variant = pending_landing_move
	pending_landing_move = null
	return out

## Game._ready 完成装配后调用；所有事件与到访标记只在此时生效。
func commit_arrival() -> bool:
	if pending_travel.is_empty():
		GameState.mark_visited(GameState.current_map)
		return true
	if String(pending_travel.get("to", "")) != GameState.current_map:
		rollback_travel()
		return false
	var request := pending_travel.duplicate(true)
	pending_travel.clear()
	var first_visit := not GameState.is_visited(GameState.current_map)
	GameState.mark_visited(GameState.current_map)
	if int(request.fee) > 0:
		EventBus.gold_changed.emit(GameState.gold)
	EventBus.map_traveled.emit(String(request.from), String(request.to))
	EventBus.map_changed.emit(String(request.to))
	if first_visit:
		EventBus.toast_requested.emit(Localization.tr_key("msg.map_service.p020") % display_name(GameState.current_map), "info")
	return true

func rollback_travel() -> void:
	if pending_travel.is_empty():
		return
	var request := pending_travel.duplicate(true)
	pending_travel.clear()
	# M10-5（R-3）：切图失败必须把「落地自动走」一起撤掉。不清的话玩家回到源图，
	# 却会被指挥走向另一个图的坐标 —— 这条只在失败路径出现，正常流程永远测不出来。
	pending_landing_move = null
	GameState.gold = int(request.gold)
	GameState.current_map = String(request.from)
	GameState.save_pos = request.save_pos
	GameState.has_save_pos = bool(request.has_save_pos)
	EventBus.gold_changed.emit(GameState.gold)
	EventBus.toast_requested.emit(Localization.tr_key("msg.map_service.p021"), "danger")

## 出行成功后重载世界（拍板 D1-A：整场景重载 + `save_pos` 传位置）。
## 旧图实体随场景一并销毁（T15）；`Game._ready` 会消费 `save_pos` 把玩家放到落点。
func reload_world() -> void:
	# deferred：避免在信号回调栈内销毁发起方节点
	_loading_token += 1
	loading_active = true
	loading_message = Localization.tr_key("msg.map_service.p022") % display_name(GameState.current_map)
	EventBus.loading_changed.emit(true, loading_message)
	call_deferred("_reload_world_now")

func _reload_world_now() -> void:
	# 给遮罩一帧实际绘制机会；进度条为不定进度，不伪造百分比。
	await get_tree().process_frame
	var token := _loading_token
	var err := get_tree().reload_current_scene()
	if err != OK and not pending_travel.is_empty():
		var source_scene := String(pending_travel.get("scene_path", ""))
		rollback_travel()
		# 原场景若已卸载，用请求前的场景路径重建源图。
		if get_tree().current_scene == null and not source_scene.is_empty():
			get_tree().change_scene_to_file(source_scene)
	_finish_loading(token)

func _finish_loading(token: int) -> void:
	await get_tree().create_timer(0.3, true, false, true).timeout
	if token != _loading_token:
		return
	loading_active = false
	loading_message = ""
	EventBus.loading_changed.emit(false, "")

## 目标图的默认落点；中心若是障碍，选择最近的可通行格。
func entry_point(map_id: String) -> Vector2:
	var w := 40
	var h := 40
	var m = DataLoader.get_entry("maps", map_id)
	if m is Dictionary:
		var s = (m as Dictionary).get("size", null)
		if s is Dictionary:
			w = maxi(1, int((s as Dictionary).get("w", w)))
			h = maxi(1, int((s as Dictionary).get("h", h)))
	var dims := Vector2i(w, h)
	var layout_path := String(m.get("layoutPath", "")) if m is Dictionary else ""
	var cached: Dictionary = _entry_cache.get(map_id, {})
	if cached.get("size") == dims and cached.get("path") == layout_path:
		return cached.position
	var cell := Vector2i(w / 2, h / 2)
	if not layout_path.is_empty():
		cell = CaveLayout.nearest_cell_in_layout(layout_path, cell)
	var position := Iso.grid_to_world(cell)
	_entry_cache[map_id] = {"size": dims, "path": layout_path, "position": position}
	return position

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
