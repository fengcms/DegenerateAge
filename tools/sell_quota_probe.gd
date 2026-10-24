extends Node
## 只读探针（工程 102）：统计真实存档里「背包内高于已穿戴」的装备堆积情况。
##
## 目的：把「背包被绿的/蓝的升级候选塞满」从玩家观感变成一张可复核的表。
## 直接 FileAccess 读存档 JSON，**不走 SaveManager** —— 不触发迁移、不写档、不改 GameState。
## 只调用纯函数：`Equipment.item_kind / score / level_req`、`Shop.item_quality`、`SellGearPolicy.entry`。
##
## 输出四块：
##   ① 每档存档概况（等级 / 背包装备数 / 品质分布）
##   ② 按部位统计：高于已穿戴的件数 vs 该部位槽位数（= 建议保留额度）
##   ③ 今天的「积极」预设实际勾选了多少件、留了多少件
##   ④ 按新规则（同部位只留 N 件最优）会多卖掉多少件、卖多少金币

const SAVE_DIR := "user://saves"
const SLOTS := ["slot_1", "slot_2", "slot_3"]
const PRESET := SellGearPolicy.AGGRESSIVE

func _ready() -> void:
	print("== 工程 102 只读探针：背包升级候选堆积统计 ==")
	for slot_name in SLOTS:
		var path := "%s/%s.json" % [SAVE_DIR, slot_name]
		if not FileAccess.file_exists(path):
			print("\n[%s] 不存在，跳过" % slot_name)
			continue
		_scan(path, slot_name)
	print("\n== 探针结束（未写入任何文件）==")
	get_tree().quit(0)

func _scan(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		print("\n[%s] 解析失败" % label)
		return
	var level := int((data.get("player", {}) as Dictionary).get("level", 1))
	var equipment: Dictionary = data.get("equipment", {})
	var inventory: Array = data.get("inventory", [])
	var preset_saved := String((data.get("settings", {}) as Dictionary).get("sellGearPreset", "?"))
	print("\n========== %s（Lv%d，存档预设=%s）==========" % [label, level, preset_saved])

	# ① 概况
	var equips: Array = []
	for i in range(inventory.size()):
		var item = inventory[i]
		if item is Dictionary and String(item.get("kind", "")) == "equip":
			equips.append([i, item])
	var qualities := {}
	for pair in equips:
		var q := Shop.item_quality(pair[1])
		qualities[q] = int(qualities.get(q, 0)) + 1
	print("背包非空 %d 格，其中装备 %d 件；品质分布 %s"
		% [Inventory.used_slots(inventory), equips.size(), str(qualities)])

	# ②+③ 逐件判「高于已穿戴」并收集今天的勾选结果
	var by_kind := {}
	var today_selected := 0
	var today_kept := 0
	var today_sellable_unselected := 0
	for pair in equips:
		var item: Dictionary = pair[1]
		var kind := Equipment.item_kind(item)
		var row := SellGearPolicy.entry(item, int(pair[0]), level, equipment, PRESET)
		if bool(row.get("default_selected", false)):
			today_selected += 1
		else:
			today_kept += 1
			if bool(row.get("manual_selectable", false)):
				today_sellable_unselected += 1
		var baseline := _worn_baseline(equipment, kind)
		var s := Equipment.score(item)
		var stronger := s > baseline + 0.0001
		if not by_kind.has(kind):
			by_kind[kind] = {"total": 0, "stronger": [], "weak": 0}
		var bucket: Dictionary = by_kind[kind]
		bucket.total = int(bucket.total) + 1
		if stronger:
			bucket.stronger.append({"score": s, "item": item, "index": int(pair[0]),
				"quality": Shop.item_quality(item),
				"starred": int(item.get("star", 0)) > 0,
				"favorite": bool(item.get("favorite", false)),
				"level_req": Equipment.level_req(item)})
		else:
			bucket.weak = int(bucket.weak) + 1

	# ② 按部位列「高于已穿戴」的件数 vs 槽位数
	# 两种额度口径都算，差别只在「金紫/星级/收藏是否占额度」：
	#   A 只数「可卖的候选」（金紫、星级、收藏都不占额度）
	#   B 全部「高于已穿戴」按分数取前 N（金紫也占额度，超出的非金紫才卖）
	print("-- 按部位：高于已穿戴 / 槽位额度 / 两种口径下「新规则多卖」--")
	var total_stronger := 0
	var gold_a := 0
	var gold_b := 0
	var sum_a := 0
	var sum_b := 0
	var locked_count := 0
	for kind in by_kind.keys():
		var bucket: Dictionary = by_kind[kind]
		var quota := Equipment.slots_for_kind(String(kind)).size()
		var ranking: Array = bucket.stronger
		ranking.sort_custom(func(a, b): return float(a.score) > float(b.score))
		total_stronger += ranking.size()
		var blocked_flags := []
		for entry in ranking:
			var blocked := bool(entry.starred) or bool(entry.favorite) \
				or Shop.QUALITY_ORDER.find(String(entry.quality)) > Shop.QUALITY_ORDER.find("rare")
			blocked_flags.append(blocked)
			if blocked:
				locked_count += 1
		# A：只在「可卖候选」里取前 N
		var eligible := 0
		var excess_a := 0
		for r in range(ranking.size()):
			if bool(blocked_flags[r]):
				continue
			eligible += 1
			if eligible > quota:
				excess_a += 1
				gold_a += Shop.sell_price(ranking[r].item)
		# B：全部取前 N，超出部分的「可卖候选」卖掉
		var excess_b := 0
		for r in range(ranking.size()):
			if r < quota or bool(blocked_flags[r]):
				continue
			excess_b += 1
			gold_b += Shop.sell_price(ranking[r].item)
		sum_a += excess_a
		sum_b += excess_b
		var detail := PackedStringArray()
		for r in range(mini(4, ranking.size())):
			detail.append("%s%s" % [String(ranking[r].quality).substr(0, 3), "★" if bool(ranking[r].starred) else ""])
		print("  %-9s 槽位 %d | 共 %2d | 高于已穿戴 %2d | 多卖A %2d / B %2d | 低分 %2d | 前4名 %s"
			% [String(kind), quota, int(bucket.total), ranking.size(), excess_a, excess_b,
				int(bucket.weak), ",".join(detail)])
	print("合计：高于已穿戴 %d 件（其中金紫/星级/收藏被硬保护 %d 件）" % [total_stronger, locked_count])
	print("      口径 A（金紫不占额度）可多卖 %d 件 / 约 %d 金币" % [sum_a, gold_a])
	print("      口径 B（金紫占额度）  可多卖 %d 件 / 约 %d 金币" % [sum_b, gold_b])

	# ③ 今天「积极」的勾选口径
	print("-- 今天「积极」预设：默认勾选 %d 件 / 保留 %d 件（其中可手选未勾 %d 件）--"
		% [today_selected, today_kept, today_sellable_unselected])

## 该部位「已穿戴」的评分基线：单槽取该槽，双槽取两槽中较低者（= 会被替换的那一件）。
## 空槽按 `replacement_preview` 口径记 0，但空槽情况由调用方单独看。
func _worn_baseline(equipment: Dictionary, kind: String) -> float:
	var ids := Equipment.slots_for_kind(kind)
	var best := INF
	var found := false
	for sid in ids:
		var worn = equipment.get(sid)
		if not (worn is Dictionary):
			continue
		var s := Equipment.score(worn)
		best = minf(best, s)
		found = true
	if not found:
		return 0.0
	return best
