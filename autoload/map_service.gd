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
	GameState.save_pos = entry_point(map_id)
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
