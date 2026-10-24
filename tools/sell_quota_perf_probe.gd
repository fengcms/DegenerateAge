extends Node
## 工程 102 R5 性能探针（只读，不写档）：额度上下文让「清单构建」与「拾取判定」
## 各多扫一遍背包，先量再说，避免凭感觉优化。
##
## 口径：满背包（137 件）时单次耗时。判定标准取自方案 R5：
## 单次超过 0.2ms 才考虑按 `inventory` 变更版本做缓存。

const BAG := 137
const KINDS := ["weapon", "ring", "shield", "helmet", "armor", "shoes", "necklace",
	"bracer", "knee", "bracelet"]
const QUALITIES := ["common", "uncommon", "rare"]
## 每个部位取一件低阶模板当「已穿戴」，其余同部位的高阶件才是升级候选。
const LOW := {
	"weapon": "weapon_iron", "ring": "ring_basic", "shield": "shield_basic",
	"helmet": "helmet_cloth", "armor": "armor_cloth", "shoes": "shoes_cloth",
	"necklace": "necklace_basic", "bracer": "bracer_basic", "knee": "knee_basic",
	"bracelet": "bracelet_basic",
}
const HIGH := {
	"weapon": ["c2_road_blade", "c3_equip_weapon", "c4_equip_weapon", "c5_equip_weapon"],
	"ring": ["c2_road_ring", "c3_equip_ring", "c4_equip_ring", "c5_equip_ring"],
}

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 102
	GameState.reset_to_defaults()
	GameState.player.level = 90
	GameState.set_sell_gear_preset(SellGearPolicy.AGGRESSIVE)
	GameState.equipment = Equipment.create()
	# 已穿戴：每个部位都放低阶普通件（双槽放两件），这样「评分更高」才判得出来
	var worn := 0
	for kind in KINDS:
		var low_id := String(LOW.get(kind, ""))
		if low_id.is_empty() or not DataLoader.get_entry("equipments", low_id) is Dictionary:
			continue
		for slot_id in Equipment.slots_for_kind(kind):
			GameState.equipment[slot_id] = _roll(low_id, "common", rng)
			worn += 1
	var placed := 0
	# 默认背包只有 40 格，先扩到最坏情形（137）再量
	GameState.inventory.resize(BAG)
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null
	# 背包：武器/戒指塞高阶件（会一路走到额度闸），其余部位塞普通件填满 137 格
	var index := 0
	while placed < BAG:
		var kind := String(KINDS[index % KINDS.size()])
		var pool: Array = HIGH.get(kind, [])
		var item_id := ""
		if pool.is_empty():
			item_id = String(LOW.get(kind, ""))
		else:
			item_id = String(pool[index % pool.size()])
		if not item_id.is_empty() and DataLoader.get_entry("equipments", item_id) is Dictionary:
			var rolled := _roll(item_id, String(QUALITIES[index % QUALITIES.size()]), rng)
			if not rolled.is_empty():
				GameState.inventory[placed] = rolled
				placed += 1
		index += 1
	print("已穿戴 %d 槽 / 背包 %d 件" % [worn, _used()])
	var t0 := Time.get_ticks_usec()
	var rows := 0
	for _i in range(10):
		rows = SellGearPolicy.build_preview(GameState.inventory,
			int(GameState.player.level), GameState.equipment, SellGearPolicy.AGGRESSIVE).size()
	var build_ms := float(Time.get_ticks_usec() - t0) / 10.0 / 1000.0
	print("build_preview（新口径）: %.3f ms/次（%d 行）" % [build_ms, rows])
	# 旧口径基线：逐件 entry、不算额度（= 工程 102 之前的耗时），用来量这次的增量
	var t_old := Time.get_ticks_usec()
	var rows_old := 0
	for _i in range(10):
		rows_old = 0
		for i in range(GameState.inventory.size()):
			if GameState.inventory[i] is Dictionary and not SellGearPolicy.entry(
					GameState.inventory[i], i, int(GameState.player.level),
					GameState.equipment, SellGearPolicy.AGGRESSIVE).is_empty():
				rows_old += 1
	var old_ms := float(Time.get_ticks_usec() - t_old) / 10.0 / 1000.0
	print("build_preview（旧口径基线）: %.3f ms/次（%d 行）" % [old_ms, rows_old])
	# 拾取判定：取一件同部位的高阶稀有件（会走到额度闸），量 100 次
	var probe := _roll("c6_equip_weapon", "rare", rng)
	var t1 := Time.get_ticks_usec()
	var sells := 0
	for _i in range(100):
		var decision := SellGearPolicy.auto_sell(probe, int(GameState.player.level),
			GameState.equipment, SellGearPolicy.AGGRESSIVE, false, GameState.inventory)
		if bool(decision.get("sell", false)):
			sells += 1
	var pick_ms := float(Time.get_ticks_usec() - t1) / 100.0 / 1000.0
	print("auto_sell: %.3f ms/次（100 次里卖出 %d 次）" % [pick_ms, sells])
	print("判定：单次 ≤ 0.2ms 即可接受（方案 R5）")
	get_tree().quit(0)

func _used() -> int:
	var n := 0
	for it in GameState.inventory:
		if it is Dictionary:
			n += 1
	return n

## 套位读模板自己的 `tierBases` 键 —— 不能从 requiredLevel 反推（`necklace_basic` 是 19 级、
## 但基底只有第 1 套，反推会去找不存在的第 11 套并直接 push_error）。
func _roll(item_id: String, quality: String, rng: RandomNumberGenerator) -> Dictionary:
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	if not tpl is Dictionary:
		return {}
	var bases: Variant = (tpl as Dictionary).get("tierBases", {})
	if not bases is Dictionary or (bases as Dictionary).is_empty():
		return {}
	return ItemFactory.make_equip_roll(item_id, int(String((bases as Dictionary).keys()[0])),
		quality, rng)
