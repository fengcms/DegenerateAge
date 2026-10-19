extends Node
## 把指定存档槽补成「任务全通」状态：任务全 rewarded + 解锁键全开 + 全图已到访 + Boss 全首通。
##
## 用途：Lv60 测试档要进 61+ 高级图，而入口由主线 `reward.unlocks` / Boss `firstClearReward.unlock` 把关。
## 边界：只改任务与解锁相关字段，**不动等级 / 装备 / 金币 / 背包**；写入走 `SaveManager.import_to_slot`
## （同一套 `_is_valid_save` → 备份 → 原子写），非法字段会当场被拒、不落盘。
##
## 🔴 解锁键**只能**取 `reward.unlocks` 数组 + Boss `firstClearReward.unlock` 单数 ——
## 这正是 `SaveManager._ensure_legal_keys()` 的白名单口径。任务单数 `reward.unlock`（如 Q005 的
## `chapter2`）**不能**由这里直接搬：它虽被 `chapter2` 的 Boss 首通键覆盖，但换个键就会整档判毁。
##
## 运行：Godot --headless --path . --scene res://tools/complete_all_quests.tscn --quit-after 900

const SLOT := 3

var problems: Array[String] = []

func _ready() -> void:
	SaveManager.autosave_enabled = false
	var read := SaveManager.read_slot(SLOT)
	if not bool(read.get("ok", false)):
		_fail("读档失败：%s" % String(read.get("message", "")))
		return
	var data: Dictionary = read.get("data", {})

	var needs := _quest_needs()
	if needs.is_empty():
		_fail("quests 表不可用，拒绝盲写")
		return
	var states := {}
	for quest_id in needs.keys():
		states[quest_id] = {"state": "rewarded", "progress": int(needs[quest_id])}

	var unlocks := _legal_unlocks()
	var boss_ids := _boss_ids()
	var map_ids := _map_ids()
	if unlocks.is_empty() or boss_ids.is_empty() or map_ids.is_empty():
		_fail("数据表不完整（unlocks %d / boss %d / maps %d）" % [unlocks.size(), boss_ids.size(), map_ids.size()])
		return

	var first_clear := {}
	for boss_id in boss_ids.keys():
		first_clear[boss_id] = true

	data["questStates"] = states
	data["unlocks"] = unlocks
	data["firstClear"] = first_clear
	data["visitedMaps"] = map_ids.keys()

	var written := SaveManager.import_to_slot(SLOT, _ints(data) as Dictionary)
	if not bool(written.get("ok", false)):
		_fail("import_to_slot 拒绝写入：%s" % String(written.get("message", "")))
		return
	_verify(states, unlocks, first_clear, map_ids)

# ---- 数据侧 ----

## 每个任务的 needs → 直接把 progress 置满，面板不会出现 `9999/5` 那种脏数字。
func _quest_needs() -> Dictionary:
	var out := {}
	var rows: Variant = DataLoader.get_table("quests")
	if not rows is Array:
		return out
	for row in (rows as Array):
		if not row is Dictionary:
			continue
		var entry: Dictionary = row
		var quest_id := String(entry.get("id", ""))
		if quest_id.is_empty():
			continue
		var need := 0
		var objective: Variant = entry.get("objective", {})
		if objective is Dictionary:
			need = maxi(0, int((objective as Dictionary).get("count", 1)))
		out[quest_id] = need
	return out

## 与 `SaveManager._ensure_legal_keys()` 同口径：只收 quests 的 `reward.unlocks` 数组
## 与 Boss 的 `firstClearReward.unlock` 单数。多收一个键，读档就会整档判毁。
## 🔴 注意 Boss 首通键（如 `chapter2`）只能进 unlocks，**绝不能**混进 firstClear ——
## 那里只认 Boss id，混一个解锁键进去就是「firstClear 含未登记键」⇒ 整档判毁。
func _legal_unlocks() -> Dictionary:
	var out := {}
	var quests: Variant = DataLoader.get_table("quests")
	if quests is Array:
		for row in (quests as Array):
			if not row is Dictionary:
				continue
			var reward: Variant = (row as Dictionary).get("reward", {})
			if not reward is Dictionary:
				continue
			var list: Variant = (reward as Dictionary).get("unlocks", [])
			if not list is Array:
				continue
			for key in (list as Array):
				out[String(key)] = true
	for row in _monster_rows():
		if String(row.get("kind", "")) != "boss":
			continue
		var first_clear: Variant = row.get("firstClearReward", {})
		if first_clear is Dictionary:
			var single := String((first_clear as Dictionary).get("unlock", ""))
			if not single.is_empty():
				out[single] = true
	return out

## 纯 Boss id 集合（firstClear 的合法键域，不含任何解锁键）。
func _boss_ids() -> Dictionary:
	var out := {}
	for row in _monster_rows():
		if String(row.get("kind", "")) != "boss":
			continue
		var boss_id := String(row.get("id", ""))
		if not boss_id.is_empty():
			out[boss_id] = true
	return out

func _monster_rows() -> Array:
	var rows: Variant = DataLoader.get_table("monsters")
	return rows if rows is Array else []

func _map_ids() -> Dictionary:
	var out := {}
	var maps: Variant = DataLoader.get_table("maps")
	if not maps is Array:
		return out
	for row in (maps as Array):
		if not row is Dictionary:
			continue
		var map_id := String((row as Dictionary).get("id", ""))
		if not map_id.is_empty():
			out[map_id] = true
	return out

# ---- 回读自检 ----

## JSON 解析把每个数字都变成 float（存档往返的既有口径）。写回前统一收成 int，
## 让夹具与游戏自己写出的档在「数值形态」上也一致 —— 读档时 `_migrate_player` 本来也会 `_deep_int`，
## 这里只是提前对齐，避免落盘出现 `"level": 60.0` 这种与生产写入不同的形态。
func _ints(value: Variant) -> Variant:
	if value is float:
		var number := float(value)
		return int(round(number)) if is_equal_approx(number, round(number)) else number
	if value is Array:
		var list: Array = []
		for item in (value as Array):
			list.append(_ints(item))
		return list
	if value is Dictionary:
		var dict := {}
		for key in (value as Dictionary).keys():
			dict[key] = _ints((value as Dictionary)[key])
		return dict
	return value

## 三重校验：落盘内容、运行态视图（`state_of`）、以及真实传送门槛（`MapService.is_unlocked`）。
func _verify(states: Dictionary, unlocks: Dictionary, first_clear: Dictionary, map_ids: Dictionary) -> void:
	var read := SaveManager.read_slot(SLOT)
	if not bool(read.get("ok", false)):
		_fail("写后回读失败：%s" % String(read.get("message", "")))
		return
	var data: Dictionary = read.get("data", {})
	var saved_states: Dictionary = data.get("questStates", {})
	var saved_unlocks: Dictionary = data.get("unlocks", {})
	var saved_visited: Array = data.get("visitedMaps", [])
	if saved_states.size() != states.size():
		problems.append("回读任务数 %d ≠ %d" % [saved_states.size(), states.size()])
	if saved_unlocks.size() != unlocks.size():
		problems.append("回读解锁键 %d ≠ %d" % [saved_unlocks.size(), unlocks.size()])
	if saved_visited.size() != map_ids.size():
		problems.append("回读到访图 %d ≠ %d" % [saved_visited.size(), map_ids.size()])

	# 运行态：把刚写入的内容装进 GameState，按游戏内真实口径再过一遍。
	GameState.quest_states = saved_states.duplicate(true)
	GameState.unlocks = saved_unlocks.duplicate(true)
	GameState.first_clear = first_clear.duplicate(true)
	var visited: Array[String] = []
	for map_id in saved_visited:
		visited.append(String(map_id))
	GameState.visited_maps = visited

	var not_rewarded := 0
	for quest_id in states.keys():
		if Quest.state_of(String(quest_id)) != Quest.STATE_REWARDED:
			not_rewarded += 1
	if not_rewarded > 0:
		problems.append("运行态仍有 %d 个任务不是 rewarded" % not_rewarded)

	var locked: Array[String] = []
	var unvisited: Array[String] = []
	for map_id in map_ids.keys():
		var id := String(map_id)
		if not MapService.is_unlocked(id):
			locked.append(id)
		if not GameState.is_visited(id):
			unvisited.append(id)
	if not locked.is_empty():
		problems.append("仍被门槛挡住的地图：%s" % str(locked))
	if not unvisited.is_empty():
		problems.append("仍未到访的地图：%s" % str(unvisited))

	print("[CompleteAll] 任务 %d 个 → rewarded；解锁键 %d 个；Boss 首通 %d 个；到访地图 %d 张" % [
		saved_states.size(), saved_unlocks.size(), first_clear.size(), saved_visited.size()])
	print("[CompleteAll] 传送门槛：%d 张图全部 is_unlocked=true，locked_reason 全空" % map_ids.size())
	if not problems.is_empty():
		_fail("回读校验未通过")
		return
	print("[CompleteAll] 槽 %d 已补成「任务全通」，可以进高级图 ✅" % SLOT)
	get_tree().quit(0)

func _fail(message: String) -> void:
	for problem in problems:
		push_error("[CompleteAll] " + problem)
	print("[CompleteAll] 失败：%s" % message)
	get_tree().quit(1)
