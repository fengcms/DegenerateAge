class_name LootBurst
extends RefCounted
## M6-0d（创意 07 §9）：装备雨展示编排 —— 出场时序 + 分环散布。
##
## 纯计算（static、无节点、无副作用）：由 `Monster._settle_rewards` 在死亡帧调用一次，
## 产出每份掉落的展示参数（出场延迟 / 落地时长 / 停驻时长 / 飞行时长 / 落点偏移），
## 再逐件写入 `GroundItem`。时间全部相对死亡帧 t=0（暂停与后台冻结由引擎 delta 天然满足）。
##
## 关键分工（与 0c 认领序**解耦**）：
##   · **认领序（入包）** 由 `Monster._order_rows_by_claim` 决定（高品质优先，§8）；
##   · **展示序（出场 / 起飞）** 由本文 `build` 决定（§9：金币/药水/如意、普通、优秀、稀有、史诗、传说）。
##
## 分组＝按 kind + 品质判定：基础槽（普 / 优）／好装备槽（稀 / 史）／传说槽（传说）。
## 该判定与 `dropTables.json` 的槽位一一对应（§5 / §6），不额外标记得以保持物品实例干净。

## 展示 / 起飞次序（§9 原文顺序，值越小越先出场 / 越先离场）。
const ORDER_COIN := 0
const ORDER_POTION := 1
const ORDER_RUNE := 2
const ORDER_MISC := 3
const ORDER_COMMON := 4
const ORDER_UNCOMMON := 5
const ORDER_RARE := 6
const ORDER_EPIC := 7
const ORDER_LEGENDARY := 8
## 基础组上界（含）：金币 / 药水 / 如意 / 杂项 / 普通 / 优秀。
const BASE_MAX_ORDER := ORDER_UNCOMMON

## 内侧优先序（§9「好装备和传说优先选择玩家容易看到的内侧位置」）：值越小越靠内。
const INNER_RANK := {
	ORDER_LEGENDARY: 0,
	ORDER_EPIC: 1,
	ORDER_RARE: 2,
	ORDER_UNCOMMON: 3,
	ORDER_COMMON: 4,
	ORDER_RUNE: 5,
	ORDER_POTION: 6,
	ORDER_COIN: 7,
	ORDER_MISC: 8,
}

## 1 格（7.1：tileW=64）。
const TILE := 64.0
## 时序（§9 表，单位 s；键＝敌人档次；normal 为普通怪取的温和值，§9 只规定精英 / Boss）。
const BASE_START := {"normal": 0.0, "elite": 0.15, "boss": 0.45}
const BASE_STEP := 0.05
const GOOD_GAP := {"normal": 0.10, "elite": 0.15, "boss": 0.20}
const GOOD_STEP := {"normal": 0.10, "elite": 0.15, "boss": 0.15}
const LEGEND_GAP := {"normal": 0.10, "elite": 0.0, "boss": 0.25}
## 每份出场落地动画时长。
const LAND_TIME := {"normal": 0.25, "elite": 0.25, "boss": 0.30}
## 全部落地后的展示停留。
const BURST_HOLD := {"normal": 0.20, "elite": 0.80, "boss": 1.50}
## 停留结束后每份起飞错峰。
const FLY_STAGGER := {"normal": 0.07, "elite": 0.08, "boss": 0.10}
## 每份飞行持续。
const FLY_TIME := {"normal": 0.70, "elite": 0.70, "boss": 0.90}
## 散布环带（格；§9：精英 0.7–1.5 / Boss 1.2–2.5；普通怪取小环）。
const RING_TILES := {"normal": [0.5, 1.2], "elite": [0.7, 1.5], "boss": [1.2, 2.5]}
## 装备中心最小间距（格；§9：≥0.35 格）。
const MIN_SPACING_TILES := 0.35
## 黄金角（≈137.5°）：确定性螺旋排布，天然近似最优散布（无需随机数 → 可测）。
const GOLDEN_ANGLE := 2.399963229728653

## 取时序表值（缺档位回退 normal）。
static func _t(table: Dictionary, kind: String) -> float:
	var v: Variant = table.get(kind, null)
	if v == null:
		v = table.get("normal", 0.0)
	return float(v)

## 出场 / 起飞次序（§9；kind + 品质 → order）。未知 kind 归入杂项组（基础组末尾）。
static func order_of(item: Dictionary) -> int:
	match String(item.get("kind", "misc")):
		"coin":
			return ORDER_COIN
		"potion":
			return ORDER_POTION
		"rune":
			return ORDER_RUNE
		"equip":
			match String(item.get("quality", "common")):
				"legendary":
					return ORDER_LEGENDARY
				"epic":
					return ORDER_EPIC
				"rare":
					return ORDER_RARE
				"uncommon":
					return ORDER_UNCOMMON
				_:
					return ORDER_COMMON
		_:
			return ORDER_MISC

## 计算整批展示编排。返回数组（**顺序＝出场 / 起飞顺序**），每项：
##   { "item": Dictionary, "order": int, "appear": float（出场延迟）,
##     "land_time": float, "hold": float（停驻时长）, "fly_time": float,
##     "offset": Vector2（相对死亡点的落点偏移） }
static func build(items: Array, kind: String) -> Array:
	var k := kind if kind in ["elite", "boss"] else "normal"
	var rows: Array = []
	for it in items:
		if it is Dictionary and not (it as Dictionary).is_empty():
			rows.append({"item": it, "order": order_of(it as Dictionary)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["order"]) < int(b["order"]))

	# ① 出场时刻（§9 表）：基础组 → 好装备组 → 传说
	var base_start := _t(BASE_START, k)
	var base_last := base_start
	var base_n := 0
	for row in rows:
		if int(row["order"]) <= BASE_MAX_ORDER:
			row["appear"] = base_start + BASE_STEP * float(base_n)
			base_last = float(row["appear"])
			base_n += 1
	var good_last := maxf(base_last, base_start)
	var good_n := 0
	for row in rows:
		var o := int(row["order"])
		if o > BASE_MAX_ORDER and o <= ORDER_EPIC:
			row["appear"] = base_last + _t(GOOD_GAP, k) + float(good_n) * _t(GOOD_STEP, k)
			good_last = float(row["appear"])
			good_n += 1
	for row in rows:
		if int(row["order"]) == ORDER_LEGENDARY:
			row["appear"] = good_last + _t(LEGEND_GAP, k)

	# ② 全部落地 → 统一停留 → 错峰起飞（§9）
	var land_time := _t(LAND_TIME, k)
	var last_land := 0.0
	for row in rows:
		last_land = maxf(last_land, float(row["appear"]) + land_time)
	var hold_end := last_land + _t(BURST_HOLD, k)
	var stagger := _t(FLY_STAGGER, k)
	var fly_time := _t(FLY_TIME, k)
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var takeoff := hold_end + stagger * float(i)      # 起飞次序＝出场次序（§9）
		row["land_time"] = land_time
		row["fly_time"] = fly_time
		row["hold"] = maxf(0.0, takeoff - (float(row["appear"]) + land_time))

	# ③ 分环散布（内侧优先；确定性，可测）
	var offsets := _scatter(rows, k)
	for i in range(rows.size()):
		rows[i]["offset"] = offsets[i]
	return rows

## 分环散布：好装备 / 传说优先内侧，确定性螺旋 + 松弛保证中心间距 ≥0.35 格。
## 返回与 `rows` 同序的偏移数组。
static func _scatter(rows: Array, kind: String) -> Array:
	var n := rows.size()
	var out: Array = []
	out.resize(n)
	if n == 0:
		return out
	var ring_v: Variant = RING_TILES.get(kind, RING_TILES["normal"])
	var ring: Array = ring_v as Array
	var r_min: float = float(ring[0]) * TILE
	var r_max: float = float(ring[1]) * TILE
	# 内侧优先排序：好装备 / 传说先占内环
	var idx: Array = []
	for i in range(n):
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = int(INNER_RANK.get(int(rows[a]["order"]), 9))
		var rb: int = int(INNER_RANK.get(int(rows[b]["order"]), 9))
		if ra == rb:
			return a < b
		return ra < rb)
	# 螺旋初值（sqrt 半径 → 面积均布；黄金角 → 角度错开）
	var pts: Array = []
	var denom := float(maxi(1, n - 1))
	for i in range(n):
		var radius := lerpf(r_min, r_max, sqrt(float(i) / denom))
		var ang := GOLDEN_ANGLE * float(i)
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	_relax(pts, r_min, r_max)
	for i in range(n):
		out[idx[i]] = pts[i]
	return out

## 松弛迭代：两两推开至最小间距，并把半径夹回环带（n ≤ ~14，代价可忽略）。
static func _relax(pts: Array, r_min: float, r_max: float) -> void:
	var n := pts.size()
	var min_d := MIN_SPACING_TILES * TILE
	for _iteration in range(48):
		var moved := false
		for i in range(n):
			for j in range(i + 1, n):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[j]
				var d := b - a
				var dist := d.length()
				if dist < min_d:
					var dir := d / maxf(dist, 0.0001)
					var push := dir * ((min_d - dist) * 0.5)
					pts[i] = a - push
					pts[j] = b + push
					moved = true
		for i in range(n):
			var p: Vector2 = pts[i]
			var r := p.length()
			if r < 0.0001:
				pts[i] = Vector2(r_min, 0.0)
			elif r < r_min:
				pts[i] = p * (r_min / r)
			elif r > r_max:
				pts[i] = p * (r_max / r)
		if not moved:
			break
