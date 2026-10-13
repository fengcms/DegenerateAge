extends Node
## MapService — 地图查询与车夫出行服务（M3-1 / M3-2）。
##
## 依据：产品文档 07 §7.3（地图加载与释放）/ §7.8（地图清单与车夫拓扑）、06 §6.6（车夫）。
##
## 职责：
##   ① 读 `maps.json` 提供地图查询（存在性 / 显示名 / 拓扑 / 费用 / NPC 点 / 目的地列表）；
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
const REST_RADIUS_CELLS := 3.0

## 跨场景保留防抖状态；仅步行出口使用，车夫线路不受影响。
var walk_locked_until_msec: int = 0
var walk_key_released: bool = true
var _rest_zones_cache: Dictionary = {}

func _ready() -> void:
	EventBus.data_loaded.connect(func() -> void: _rest_zones_cache.clear())

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

# ---- 车夫拓扑与费用 ----

## 当前图的车夫可达拓扑（`maps.json.carterLinks`）。
func links() -> Array:
	var l = current_data().get("carterLinks", [])
	return l if l is Array else []

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

## 从当前图前往目标图的费用（`maps.json.carterFees`；缺省 0）。
func fee_to(map_id: String) -> int:
	var fees = current_data().get("carterFees", {})
	if fees is Dictionary:
		return maxi(0, int((fees as Dictionary).get(map_id, 0)))
	return 0

## 当前图 NPC 点原始数据（`maps.json.npcs`；cell 为 `[x, y]` 数组）。
func current_npcs() -> Array:
	var n = current_data().get("npcs", [])
	return n if n is Array else []

## 当前图 Boss 点原始数据（`maps.json.bossSpawn`；无 → 空字典）。
func current_boss() -> Dictionary:
	var b = current_data().get("bossSpawn", null)
	return b if b is Dictionary else {}

func current_exits() -> Array:
	var exits = current_data().get("exits", [])
	return exits if exits is Array else []

## 从地图数据推导休整区，不增存档字段；所有距离都在逻辑网格中计算。
func rest_zones(map_id: String) -> Array[Dictionary]:
	if _rest_zones_cache.has(map_id):
		return _rest_zones_cache[map_id]
	var out: Array[Dictionary] = []
	var data := data_for(map_id)
	if data.is_empty():
		return out
	for exit_data in data.get("exits", []):
		if exit_data is Dictionary:
			_add_rest_zone(out, "exit", exit_data.get("cell", null))
	var entrances: Variant = data.get("entrances", {})
	if entrances is Dictionary:
		for entrance_id in entrances.keys():
			_add_rest_zone(out, "entrance", entrances[entrance_id])
	_add_rest_zone(out, "carter", data.get("carterArrival", null))
	_rest_zones_cache[map_id] = out
	return out

func _add_rest_zone(out: Array[Dictionary], kind: String, value: Variant) -> void:
	if not value is Array or value.size() != 2:
		return
	out.append({"kind": kind, "cell": Vector2(float(value[0]), float(value[1]))})

func is_in_rest_zone(map_id: String, world_position: Vector2) -> bool:
	var cell := Iso.world_to_grid(world_position)
	for zone in rest_zones(map_id):
		if cell.distance_to(zone.cell) <= REST_RADIUS_CELLS:
			return true
	return false

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
	if not can_use_walk_exit():
		return _fail("请松开交互键，稍后再走")
	var exit_data := walk_exit(exit_id)
	if exit_data.is_empty():
		return _fail("此处没有道路出口")
	var to_id := String(exit_data.get("toMap", ""))
	if not exists(to_id) or to_id == GameState.current_map:
		return _fail("道路目的地无效")
	var cell: Variant = exit_data.get("cell", null)
	if not cell is Array or cell.size() != 2:
		return _fail("道路出口配置无效")
	var player_cell := Iso.world_to_grid(player_world)
	if player_cell.distance_to(Vector2(float(cell[0]), float(cell[1]))) > WALK_RANGE_CELLS:
		return _fail("请走近路牌")
	if not is_unlocked(to_id):
		return _fail("道路封锁：%s尚未解锁" % display_name(to_id))
	var entrance_id := String(exit_data.get("toEntrance", ""))
	var entrances: Variant = data_for(to_id).get("entrances", null)
	if not entrances is Dictionary or not entrances.has(entrance_id):
		return _fail("道路入口配置缺失")
	var arrival: Variant = entrances[entrance_id]
	if not arrival is Array or arrival.size() != 2:
		return _fail("道路入口配置无效")
	var from_id := GameState.current_map
	GameState.current_map = to_id
	GameState.save_pos = Iso.grid_to_world(Vector2i(int(arrival[0]), int(arrival[1])))
	GameState.has_save_pos = true
	GameState.close_all_panels()
	walk_key_released = false
	walk_locked_until_msec = Time.get_ticks_msec() + WALK_ARRIVAL_LOCK_MSEC
	EventBus.map_traveled.emit(from_id, to_id)
	EventBus.map_changed.emit(to_id)
	return {"ok": true, "reason": ""}

## 车夫可达目的地列表（供 CarterPanel 渲染）：
##   [{id, name, recommendedLevel, cost, unlocked, reason}]
func destinations() -> Array:
	var out: Array = []
	for lid in links():
		var id := String(lid)
		if not exists(id):
			continue
		var unlocked := is_unlocked(id)
		out.append({
			"id": id,
			"name": display_name(id),
			"recommendedLevel": recommended_level(id),
			"cost": fee_to(id),
			"unlocked": unlocked,
			"reason": "" if unlocked else "尚未解锁",
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
	if not exists(map_id):
		return _fail("未知地图：%s" % map_id)
	if map_id == GameState.current_map:
		return _fail("已在%s" % display_name(map_id))
	if not is_linked(map_id):
		return _fail("车夫不到%s，需经其他地图中转" % display_name(map_id))
	if not is_unlocked(map_id):
		return _fail("%s尚未解锁" % display_name(map_id))
	var fee := fee_to(map_id)
	if fee > 0 and GameState.gold < fee:
		return _fail("金币不足：前往%s需 %d（现有 %d）" % [display_name(map_id), fee, GameState.gold])

	if fee > 0:
		GameState.add_gold(-fee)

	var from_id := GameState.current_map
	GameState.current_map = map_id
	GameState.save_pos = carter_arrival(map_id)
	GameState.has_save_pos = true
	GameState.close_all_panels()
	EventBus.map_traveled.emit(from_id, map_id)
	EventBus.map_changed.emit(map_id)
	return {"ok": true, "reason": ""}

## 出行成功后重载世界（拍板 D1-A：整场景重载 + `save_pos` 传位置）。
## 旧图实体随场景一并销毁（T15）；`Game._ready` 会消费 `save_pos` 把玩家放到落点。
func reload_world() -> void:
	# deferred：避免在信号回调栈内销毁发起方节点
	get_tree().call_deferred("reload_current_scene")

## 目标图的落点世界坐标（地图中心；`IsoGround.clamp_to_map` 会再夹一次兜底）。
func entry_point(map_id: String) -> Vector2:
	var w := 40
	var h := 40
	var m = DataLoader.get_entry("maps", map_id)
	if m is Dictionary:
		var s = (m as Dictionary).get("size", null)
		if s is Dictionary:
			w = maxi(1, int((s as Dictionary).get("w", w)))
			h = maxi(1, int((s as Dictionary).get("h", h)))
	return Iso.grid_to_world(Vector2i(w / 2, h / 2))

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
