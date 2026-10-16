extends Node
## E1 门禁/交通：正向锁只在对应任务领奖后开、返回边不锁、封锁说明指名交付人；
## 无人产出的解锁键会在启动校验被拦下（工程文档 30 §4，31 §4/§6）。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[MapGateTest] " + message)

## 上一次步行的防抖只为真人连续按键服务，这里在断言之间复位。
func _walk(exit_id: String, cell: Variant) -> Dictionary:
	MapService.walk_key_released = true
	MapService.walk_locked_until_msec = 0
	var target: Array = cell if cell is Array else [0, 0]
	var result := MapService.request_walk(exit_id, Iso.grid_to_world(Vector2i(int(target[0]), int(target[1]))))
	if bool(result.get("ok", false)):
		MapService.commit_arrival()
	return result

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "所有数据表通过引用校验：%s" % str(issues))

	# 第三章入口由 C2Q12 领奖解除；这里直接给键，本轮只验证门禁本身。
	GameState.unlocks["chapter3"] = true
	GameState.current_map = "c3_map00"
	check(MapService.is_unlocked("c3_map01"), "枢纽到断流渠岸本地开放")
	check(not MapService.is_unlocked("c3_map02"), "悬渠闸站在 C3Q03 领奖前锁定")

	var hub_exit := MapService.walk_exit("c3_map00_exit02")
	check(bool(_walk("c3_map00_exit02", hub_exit.get("cell")).get("ok", false)), "枢纽正向边本地开放")
	check(GameState.current_map == "c3_map01", "已进入断流渠岸")

	var forward := MapService.walk_exit("c3_map01_exit02")
	check(MapService.exit_requirement(forward) == "c3_access_02", "正向边自带解锁键")
	var blocked := _walk("c3_map01_exit02", forward.get("cell"))
	check(not bool(blocked.get("ok", false)), "未领奖时正向边锁住")
	check(GameState.current_map == "c3_map01" and MapService.pending_travel.is_empty(), "被拦下时不切图也不留事务")
	var reason := String(blocked.get("reason", ""))
	check(reason.contains("陶汀") and reason.contains("被改道的水"), "封锁说明指名交付人与任务：%s" % reason)

	check(bool(_walk("c3_map01_exit01", MapService.walk_exit("c3_map01_exit01").get("cell")).get("ok", false)), "返回边不锁")
	check(GameState.current_map == "c3_map00", "已退回枢纽")

	GameState.unlocks["c3_access_02"] = true
	check(bool(_walk("c3_map00_exit02", MapService.walk_exit("c3_map00_exit02").get("cell")).get("ok", false)), "再次进入断流渠岸")
	check(bool(_walk("c3_map01_exit02", forward.get("cell")).get("ok", false)), "C3Q03 领奖后正向边打开")
	check(GameState.current_map == "c3_map02", "已进入悬渠闸站")

	# 门未开时不导航到走不到的目标（免费步行永远能完成主线的前提）。
	var spawns: Array = MapService.data_for("c3_map03").get("spawnPoints", [])
	var far_target := "" if spawns.is_empty() else String((spawns[0] as Dictionary).get("monsterId", ""))
	GameState.current_map = "c3_map00"
	GameState.unlocks.erase("c3_access_02")
	GameState.unlocks.erase("c3_access_03")
	check(not bool(MapService.start_quest_navigation(far_target, ["c3_map03"]).get("ok", false)), "门未开时不指一条打不开的路")
	GameState.unlocks["c3_access_02"] = true
	GameState.unlocks["c3_access_03"] = true
	var route := MapService.start_quest_navigation(far_target, ["c3_map03"])
	check(bool(route.get("ok", false)) and String(route.get("map", "")) == "c3_map03", "两门均领奖后可达旱井旧坊")
	check(String(route.get("first_hop", "")) == "c3_map01", "第一跳落在相邻已开图")
	MapService.clear_quest_navigation()

	# 车夫只列本集群附属图与相邻**已发布**枢纽；未发布章不出现可进入目的地。
	var destinations := MapService.destinations()
	check(not destinations.is_empty(), "枢纽有车夫目的地")
	for entry in destinations:
		var id := String(entry.get("id", ""))
		check(id != "ash_land" and (id == "c4_map00" or not id.begins_with("c4_")), "不跨集群、不列未发布章：%s" % id)
		check(bool(entry.get("unlocked", false)) or not String(entry.get("reason", "")).is_empty(), "%s 未开放时说明原因" % id)

	# 无人产出的解锁键（或写错类型）必须在启动校验被拦下，避免内容永久锁死。
	var probe: Dictionary = DataLoader.get_entry("maps", "c3_map04")
	var original: Variant = probe.get("requiresUnlock")
	probe["requiresUnlock"] = "c3_orphan_gate"
	var orphan_hit := false
	for line in DataLoader.validate_all():
		if line.contains("c3_orphan_gate"):
			orphan_hit = true
	check(orphan_hit, "无人产出的解锁键被启动校验点名")
	check(DataLoader.validate_all().size() == 1, "只报这一处问题")
	probe["requiresUnlock"] = 21
	check(DataLoader.validate_all().size() == 1, "非字符串解锁键被拦下")
	probe["requiresUnlock"] = original
	check(DataLoader.validate_all().is_empty(), "还原后校验重新通过")

	print("[MapGateTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
