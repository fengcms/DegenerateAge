extends Node
## 第四章 31—40 地图数据契约（32 §5 批次 4.5 准出）：
##   · 六图登记、枢纽/野外分工与等级区间符合 32 §1/§3；
##   · 根驿营地为安全枢纽：无可刷怪、八个服务点集中在安全区；
##   · 野外图刷新预算 10/2/1，刷新怪均为本章模板；
##   · 三首领位落在各自图内，复刷计时 600 秒、墓碑、容量 1；
##   · 出口去向都在正式地图表内，无悬空出口，含第三章↔第四章双向边。

var failures: Array[String] = []

const HUB := "c4_map00"
const FIELD_MAPS := ["c4_map01", "c4_map02", "c4_map03", "c4_map04", "c4_map05"]
## 首领图 → 首领怪（c4_map01 / c4_map03 为过路图，无首领位）。
const BOSS_OF := {"c4_map02": "c4_boss01", "c4_map04": "c4_boss02", "c4_map05": "c4_boss03"}

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterFourMapTest] " + message)

func _data(map_id: String) -> Dictionary:
	return MapService.data_for(map_id)

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "所有数据表通过引用校验：%s" % str(issues))
	_test_registration()
	_test_hub_safety()
	_test_field_budget()
	_test_boss_contract()
	_test_no_dangling_exit()
	_test_chapter_bridge()
	print("[ChapterFourMapTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- ① 登记与分工 ----

func _test_registration() -> void:
	check(_data(HUB).get("kind", "") == "hub", "根驿营地登记为枢纽")
	var lo := int(_data(HUB).get("tierRange", [0, 0])[0])
	check(lo >= 31 and lo <= 40, "枢纽等级区间落在 31—40")
	for map_id in FIELD_MAPS:
		var data := _data(map_id)
		check(not data.is_empty(), "%s 已登记" % map_id)
		check(String(data.get("kind", "")) == "spoke", "%s 登记为野外附属图" % map_id)
		check(String(data.get("hubId", "")) == HUB, "%s 归属根驿营地" % map_id)
		var range: Array = data.get("tierRange", [])
		check(range.size() == 2 and int(range[0]) >= 31 and int(range[1]) <= 40 and int(range[0]) <= int(range[1]),
			"%s 等级区间合法且落在 31—40" % map_id)
		check(not bool(data.get("safeZone", true)), "%s 非安全区" % map_id)

# ---- ② 枢纽安全 ----

func _test_hub_safety() -> void:
	var hub := _data(HUB)
	check(bool(hub.get("safeZone", false)), "枢纽标记安全区")
	for cap in ["normalCap", "eliteCap", "bossCap"]:
		check(int(hub.get(cap, -1)) == 0, "枢纽 %s 为 0" % cap)
	check((hub.get("spawnPoints", []) as Array).is_empty(), "枢纽无常态刷新点")
	check(hub.get("bossSpawn", null) == null, "枢纽无首领位")
	check(hub.get("hubLinks", []).has("c3_map00"), "枢纽与下街水市互连")
	var npcs: Array = hub.get("npcs", [])
	check(npcs.size() == 8, "枢纽集中八个服务点")
	var area: Dictionary = hub.get("safeArea", {})
	var min_c: Array = area.get("min", [0, 0])
	var max_c: Array = area.get("max", [0, 0])
	for npc in npcs:
		var cell: Array = (npc as Dictionary).get("cell", [0, 0])
		check(int(cell[0]) >= int(min_c[0]) and int(cell[0]) <= int(max_c[0])
			and int(cell[1]) >= int(min_c[1]) and int(cell[1]) <= int(max_c[1]),
			"枢纽 NPC %s 落在安全区内" % (npc as Dictionary).get("npcId", "?"))

# ---- ③ 野外刷新预算 ----

func _test_field_budget() -> void:
	for map_id in FIELD_MAPS:
		var data := _data(map_id)
		check(int(data.get("normalCap", 0)) == 10, "%s 普通怪预算封顶 10" % map_id)
		check(int(data.get("eliteCap", 0)) == 2, "%s 精英预算封顶 2" % map_id)
		check(int(data.get("bossCap", 0)) == 1, "%s 首领容量为 1" % map_id)
		var spawns: Array = data.get("spawnPoints", [])
		check(not spawns.is_empty(), "%s 配置常态刷新点" % map_id)
		for spec in spawns:
			check(String((spec as Dictionary).get("monsterId", "")).begins_with("c4_"), "%s 只刷本章怪" % map_id)

# ---- ④ 首领位契约 ----

func _test_boss_contract() -> void:
	for map_id in FIELD_MAPS:
		var boss: Variant = _data(map_id).get("bossSpawn", null)
		if BOSS_OF.has(map_id):
			check(boss is Dictionary, "%s 登记首领位" % map_id)
			if boss is Dictionary:
				var spec := boss as Dictionary
				check(String(spec.get("monsterId", "")) == String(BOSS_OF[map_id]), "%s 首领怪与规划一致" % map_id)
				check(int(spec.get("respawnTime", 0)) == 600, "%s 首领复刷 600 秒" % map_id)
				check(bool(spec.get("tombstone", false)), "%s 首领留下墓碑" % map_id)
				check(int(spec.get("count", 0)) == 1, "%s 首领单只生成" % map_id)
				check(not (spec.get("cells", []) as Array).is_empty(), "%s 首领位有落点" % map_id)
		else:
			check(boss == null, "%s 为过路图，不设首领位" % map_id)

# ---- ⑤ 出口去向 ----

func _test_no_dangling_exit() -> void:
	for map_id in ([HUB] + FIELD_MAPS):
		for exit_data in _data(map_id).get("exits", []):
			var to_map := String((exit_data as Dictionary).get("toMap", ""))
			check(DataLoader.get_entry("maps", to_map) is Dictionary, "%s 出口去向 %s 已登记" % [map_id, to_map])

# ---- ⑥ 第三↔第四章双向边 ----

func _test_chapter_bridge() -> void:
	var prev := _data("c3_map00")
	var field := _data("c4_map01")
	var hub := _data(HUB)
	for edge in prev.get("exits", []):
		check(String(edge.get("toMap", "")) != HUB, "前城没有直达本城的步行边")
	var outbound: Dictionary = {}
	for edge in prev.get("exits", []):
		if String(edge.get("id", "")) == "c3_map00_exit03":
			outbound = edge
	check(String(outbound.get("toMap", "")) == "c4_map01", "前城先通往过渡野外")
	check(String(outbound.get("requiresUnlock", "")) == "chapter4", "去程仍由 chapter4 把关")
	check(field.get("entrances", {}).has("from_c3_map00"), "野外有前城落点")
	var to_hub: Dictionary = {}
	var to_prev: Dictionary = {}
	for edge in field.get("exits", []):
		if String(edge.get("id", "")) == "c4_map01_exit01":
			to_hub = edge
		if String(edge.get("id", "")) == "c4_map01_to_previous":
			to_prev = edge
	check(String(to_hub.get("toMap", "")) == HUB, "野外可进入本城")
	check(String(to_prev.get("toMap", "")) == "c3_map00" and not to_prev.has("requiresUnlock"), "野外回前城不锁")
	check(prev.get("entrances", {}).has("from_c4_map00"), "前城保留回程落点")
	var hub_return: Dictionary = {}
	for edge in hub.get("exits", []):
		if String(edge.get("id", "")) == "c4_map00_exit02":
			hub_return = edge
	check(String(hub_return.get("toMap", "")) == "c4_map01", "本城回野外有步行出口")
