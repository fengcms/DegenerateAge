extends Node
## Check the actual equipment, skill panel and hotbar texture paths used by players.

var failures: Array[String] = []

func _ready() -> void:
	for template in DataLoader.get_table("equipments"):
		var id := String(template.id)
		var item := ItemFactory.make_equip(id)
		var icon := SampleArt.icon_for(item)
		check(icon != null and icon.get_size() == Vector2(48, 48), "%s equipment icon" % id)
		check(icon != null and icon.resource_path == String(template.icon), "%s uses configured icon" % id)
	# 全套药水、如意与已制作的杂项图标必须通过物品实例入口进入背包和地面。
	var designed_items := [
		"potion_hp_small", "potion_mp_small", "potion_hp_mid", "potion_mp_mid",
		"potion_hp_large", "potion_mp_large", "rune_iron", "rune_jade",
		"rune_gold", "rune_diamond", "misc_firework", "misc_random_ticket",
		"misc_town_scroll", "misc_revive_scroll", "spirit_shard",
		# 工程 109：仓库兑换台的储值物必须能画出图标（漏登记 = 空白格，不报错）
		"gold_ingot", "gold_brick",
	]
	for id in designed_items:
		var item := ItemFactory.make_any(id)
		var icon := SampleArt.icon_for(item)
		check(icon != null and icon.get_size() == Vector2(48, 48)
			and icon.resource_path == "res://assets/sprites/items/%s.png" % id,
			"%s uses delivered item icon" % id)
		check(SampleArt.ground_for(item) == icon, "%s ground drop uses delivered icon" % id)
	var coin := {"kind": "coin", "itemId": "coin", "gold": 1, "count": 1}
	check(SampleArt.ground_for(coin) != null
		and SampleArt.ground_for(coin).resource_path == "res://assets/sprites/items/coin.png",
		"ground coin uses delivered icon")
	check(HotbarVisual.binding_icon({"kind": "auto_potion", "id": "red"}) == SampleArt.icon_for(ItemFactory.make_any("potion_hp_small"))
		and HotbarVisual.binding_icon({"kind": "auto_potion", "id": "blue"}) == SampleArt.icon_for(ItemFactory.make_any("potion_mp_small")),
		"hotbar automatic potions use delivered red and blue icons")
	var panel: Variant = preload("res://scripts/ui/skill_panel.gd").new()
	add_child(panel)
	var rows: VBoxContainer = panel._list
	# 工程 98 R5：技能面板按**当前职业**过滤，所以「图标 / 数据路径」对全表 12 条都要查，
	# 而「面板行 + 快捷栏槽位」只能按本职业那 6 条查 —— 拿全表去索引行会越界
	# （`--all` 抓到的原形：`Index p_index = 6 is out of bounds (… = 6)`，随后 `get_child` 空引用）。
	for raw_skill in DataLoader.get_table("skills"):
		var sid := String(raw_skill.id)
		var tex := SampleArt.skill_icon(sid)
		check(tex != null and tex.get_size() == Vector2(48, 48), sid + " loaded texture")
		check(ResourceLoader.exists(String(raw_skill.icon), "Texture2D"), sid + " data path")
	for class_id in PlayerClass.ids():
		GameState.player.classId = String(class_id)
		panel._refresh()
		var ids: Array = HotbarConfig.active_skills(String(class_id))
		check(rows.get_child_count() == ids.size(),
			"%s 技能面板应只列本职业 %d 条，实际 %d" % [String(class_id), ids.size(), rows.get_child_count()])
		for index in range(mini(ids.size(), rows.get_child_count())):
			var id := String(ids[index])
			var skill: Dictionary = DataLoader.get_entry("skills", id)
			var texture := SampleArt.skill_icon(id)
			var button := rows.get_child(index).get_child(0) as SkillDragButton
			check(button.icon == texture and button.text.is_empty(), id + " skill panel icon")
			check(button.drag_label == String(skill.name), id + " drag preview label")
			var slot := HotbarSlot.new()
			add_child(slot)
			slot.entry = {"kind": "skill", "id": id}
			SampleArt.decorate(slot, null)
			check(slot.icon == texture, id + " hotbar icon")
			slot.queue_free()
	for index in range(2):
		var kind := "red" if index == 0 else "blue"
		var button := panel._potion_buttons[kind] as SkillDragButton
		check(button.icon == SampleArt.binding_icon({"kind": "auto_potion", "id": kind})
			and button.text.is_empty(), "%s automatic potion picker icon" % kind)
	if failures.is_empty():
		print("[IconIntegrationTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
