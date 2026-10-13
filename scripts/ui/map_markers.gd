class_name MapMarkers
extends RefCounted
## UI 标记来自当前世界的实际刷新点；收集目标查投放表，不编造地图坐标。
static func for_world(world: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	for npc: Node2D in world.get_node("Npcs").get_children():
		var carter := String(npc.get("role")) == "carter"
		out.append({"position": npc.global_position, "kind": "carter" if carter else "npc",
			"name": Localization.tr_key("ui.map.carter_marker") % String(npc.get("npc_name")) if carter else String(npc.get("npc_name")),
			"revealed": false, "always_big": carter})
	for exit_node: Node2D in world.get_node("Exits").get_children():
		var destination := String(exit_node.get("to_map"))
		var label := Localization.tr_key("ui.map.exit_marker") % [MapService.display_name(destination), MapService.recommended_level(destination)]
		if not MapService.is_unlocked(destination):
			label += Localization.tr_key("ui.map.locked_suffix")
		out.append({"position": exit_node.global_position, "kind": "exit", "name": label,
			"to_map": destination, "unlocked": MapService.is_unlocked(destination),
			"revealed": false, "always_big": true})
	var points: Array[Dictionary] = world.get_node("Spawner").marker_points()
	for point in points:
		var monster: Variant = DataLoader.get_entry("monsters", point.monster_id)
		if monster is Dictionary and String(monster.get("kind", "")) == "boss":
			out.append({"position": point.position, "kind": "boss", "name": String(monster.get("name", "Boss")), "revealed": false})
	for quest in Quest.ongoing_list():
		if String(quest.state) != Quest.STATE_ACTIVE:
			continue
		var tpl := Quest.template(String(quest.id))
		if not (tpl.get("mapScope", []) as Array).has(GameState.current_map):
			continue
		var objective: Dictionary = quest.objective
		var target := String(objective.get("targetId", ""))
		for point in points:
			var matched: bool = String(objective.get("kind", "")) == "kill" and point.monster_id == target
			if String(objective.get("kind", "")) == "collect":
				matched = drops_item(String(point.monster_id), target)
			if matched:
				var template: Variant = DataLoader.get_entry("monsters", String(point.monster_id))
				var boss: bool = template is Dictionary and String(template.get("kind", "")) == "boss"
				out.append({"position": point.position, "kind": "quest", "name": String(quest.name), "revealed": true, "boss": boss})
	return out

static func drops_item(monster_id: String, item_id: String) -> bool:
	var monster: Variant = DataLoader.get_entry("monsters", monster_id)
	if not monster is Dictionary:
		return false
	var table: Variant = DataLoader.get_entry("dropTables", String(monster.get("dropTableId", "")))
	if not table is Dictionary:
		return false
	for entry: Dictionary in table.get("entries", []):
		if String(entry.get("itemId", "")) == item_id and float(entry.get("chance", 0)) > 0:
			return true
	return false
