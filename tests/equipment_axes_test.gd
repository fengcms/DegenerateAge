extends Node
## 三轴装备模型的真实配置、生成、结算、掉落和新旧存档边界。

var failures: Array[String] = []

func _ready() -> void:
	check(DataLoader.validate_all().is_empty(), "装备与掉落配置应通过启动校验")
	var rng := RandomNumberGenerator.new()
	rng.seed = 190026
	var qualities := ["common", "uncommon", "rare", "epic", "legendary"]
	var expected_count := [0, 1, 2, 3, 4]
	for tier in [1, 10, 20]:
		var kinds := {}
		for tpl in DataLoader.get_table("equipments"):
			if not tpl is Dictionary or not bool(tpl.get("lootable", true)):
				continue
			kinds[String(tpl.slot)] = true
			for i in range(qualities.size()):
				var item := ItemFactory.make_equip_roll(String(tpl.id), tier, qualities[i], rng)
				check(not item.is_empty(), "%s Lv%d %s 可生成" % [tpl.id, tier, qualities[i]])
				if item.is_empty():
					continue
				check(int(item.requiredLevel) == tier and Equipment.level_req(item) == tier and int(item.level) == tier,
					"显示等级与穿戴门槛一致")
				check(item.affixes.size() + item.pctAttrs.size() == expected_count[i], "品质词条数量准确")
				check(item.pctAttrs.size() <= 1 and int(item.star) == 0, "百分比上限与掉落初始星级")
				check(SaveManager._valid_item(item), "生成实例符合新存档格式")
		check(kinds.size() == 10, "每档有十类可掉落部位")
	var sample := ItemFactory.make_equip_roll("shoes_cloth", 10, "legendary", rng)
	var white := ItemFactory.make_equip_roll("shoes_cloth", 10, "common", rng)
	check(is_equal_approx(float(EquipmentMath.base_attrs(sample).def),
		float(EquipmentMath.base_attrs(white).def) * 2.4), "同型号品质只放大基础")
	var base := EquipmentMath.effective_attrs(sample)
	sample.star = 12
	var boosted := EquipmentMath.effective_attrs(sample)
	for stat in base:
		check(is_equal_approx(float(boosted[stat]), float(base[stat]) * 2.2), "12 星整件贡献放大：%s" % stat)
	check(Equipment.score(sample) > Equipment.score(ItemFactory.make_equip_roll("shoes_cloth", 10, "common", rng)),
		"评分使用有效属性")
	check(not Equipment.meets_level(sample, 9) and Equipment.meets_level(sample, 10), "Lv10 穿戴门槛")
	check(Shop.base_value(sample) > Shop.base_value(ItemFactory.make_equip_roll("shoes_cloth", 1, "legendary", rng)),
		"高档位装备的基础售价随档位增长")
	var old := {"kind": "equip", "itemId": "shoes_cloth", "instanceId": "old", "level": 10,
		"quality": "common", "star": 0, "baseAttrs": {"def": 1}, "affixes": [], "pctAttrs": []}
	check(not SaveManager._valid_item(old), "旧结构不得混入新存档")
	var save := SaveManager._collect()
	check(SaveManager._is_valid_save(save), "新档可校验")
	save.schemaVersion = 10
	check(not SaveManager._is_valid_save(save), "旧 schema 明确拒绝")
	var legendary_slots := {}
	for _i in range(1500):
		for item in Loot.roll("DT_Boss_L1", rng, "boss_corrupted_beast"):
			if item is Dictionary and String(item.get("quality", "")) == "legendary":
				legendary_slots[Equipment.item_kind(item)] = true
	check(legendary_slots.size() > 1 and legendary_slots.has("shoes"), "Boss 传说追加可覆盖非武器部位")
	if failures.is_empty():
		print("[EquipmentAxesTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
