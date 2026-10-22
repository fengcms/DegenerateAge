class_name LootBurst
extends RefCounted
## M6-0d（创意 07 §9）：装备雨展示编排 —— 出场时序 + **一格一件的格铺**。
##
## 纯计算（static、无节点、无副作用）：由 `Monster._settle_rewards` 在死亡帧调用一次，
## 产出每份掉落的展示参数（出场延迟 / 落地时长 / 停驻时长 / 飞行时长 / 目标格 + 落点偏移），
## 再逐件写入 `GroundItem`。时间全部相对死亡帧 t=0（暂停与后台冻结由引擎 delta 天然满足）。
##
## 关键分工（与 0c 认领序**解耦**）：
##   · **认领序（入包）** 由 `Monster._order_rows_by_claim` 决定（高品质优先，§8）；
##   · **展示序（出场 / 起飞）** 由本文 `build` 决定（§9：金币/药水/如意、普通、优秀、稀有、史诗、传说）。
##
## 分组＝按 kind + 品质判定：基础槽（普 / 优）／好装备槽（稀 / 史）／传说槽（传说）。
## 该判定与 `dropTables.json` 的槽位一一对应（§5 / §6），不额外标记得以保持物品实例干净。
##
## ## 工程 93（D-31）：为什么从「分环散布」改成「一格一件」
##
## 旧实现把整批塞进一条窄环带（Boss 半径 1.2—2.5 格 = 77—160px）再靠松弛推开。
## 但环带面积是硬上限：86 件时每件等效直径只有 **30px**，小于图标本身 32px ⇒ 图标必然重叠；
## 名字绘制宽度 **240px**，是格间最小间距（22.4px）的 10.7 倍 ⇒ 名字必然糊成一团。
## **这不是排布算法没调好，是物理上放不下。**
##
## 新实现以击杀格为中心按等距菱形同心圈铺开（Chebyshev 距离 = 圈号），**一格一件**：
##   · 累计格数 `1 + 4r(r+1)`：r=2 → 25 格、r=5 → 121 格（孤王绝域上限 102 件正好吃下）；
##   · 格距 64×32px > 图标 32px ⇒ 不再重叠；
##   · 圈数按件数自动决定，无需配置；圈数上限 `MAX_RING`（12 圈 = 625 格）。
## 名字重叠问题由 `GroundItem.LABEL_CROWD_LIMIT` 处理（同批 ≥20 件时稀有以上只悬停显示）。

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

## 1 格（7.1：tileW=64）；像素换算单一来源见 Iso.TILE_W。
const TILE := Iso.TILE_W
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

## 工程 93：格铺圈数上限（12 圈 = 1 + 4×12×13 = 625 格）。
## 取 12 的理由：现有最大掉落表是孤王绝域 102 件，只需 5 圈（121 格），
## 12 圈留了一倍以上余量，同时防止「地图极小 + 件数极多」时空转。
const MAX_RING := 12

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
##     "cell": Vector2i（目标格，绝对地图格坐标；工程 93）,
##     "offset": Vector2（目标格心相对**击杀格心**的世界像素偏移） }
##
## `ctx`（工程 93，可选）：
##   · `"origin": Vector2i`  —— 击杀点所在格（默认 `Vector2i.ZERO`，此时 `offset` 即绝对格心）；
##   · `"walkable": Callable` —— `(cell) -> bool`，不可走的格被跳过（墙 / 水 / 越界）。
##     ⚠ 回调**自己负责判地图边界**：`IsoGround.is_walkable_cell()` 在 `cave == null`
##     时恒返回 true，单靠它会把掉落铺到图外，再被 `clamp_to_map` 挤回同一堆。
static func build(items: Array, kind: String, ctx: Dictionary = {}) -> Array:
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

	# ③ 格铺（一件一格；内侧优先；确定性，可测）
	_layout(rows, ctx)
	return rows

## 工程 93：格铺落点。就地写入每行的 `cell`（绝对格）与 `offset`（相对击杀格心的像素偏移）。
##
## 分配规则：**内侧优先**（`INNER_RANK` 小的先占内圈）→ 逐圈向外取**可走**格 →
## 圈数不够就扩圈（上限 `MAX_RING`）→ 仍不够则**循环复用已有格位**（宁可叠，绝不丢件）。
static func _layout(rows: Array, ctx: Dictionary) -> void:
	var n := rows.size()
	if n == 0:
		return
	var origin_v: Variant = ctx.get("origin", Vector2i.ZERO)
	var origin: Vector2i = origin_v if origin_v is Vector2i else Vector2i.ZERO
	var walk_v: Variant = ctx.get("walkable", null)
	var walk: Callable = walk_v as Callable if walk_v is Callable else Callable()

	# 内侧优先：好装备 / 传说先占内圈
	var idx: Array = []
	for i in range(n):
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = int(INNER_RANK.get(int(rows[a]["order"]), 9))
		var rb: int = int(INNER_RANK.get(int(rows[b]["order"]), 9))
		if ra == rb:
			return a < b
		return ra < rb)

	# 逐圈向外收集可用格位
	var slots: Array = []
	var ring := 0
	while slots.size() < n and ring <= MAX_RING:
		for delta in _ring_deltas(ring):
			if slots.size() >= n:
				break
			var cell: Vector2i = origin + (delta as Vector2i)
			if walk.is_valid() and not bool(walk.call(cell)):
				continue
			slots.append(cell)
		ring += 1

	# 兜底一：整张图一格都不可走（正常不会发生）⇒ 全部叠在击杀点，至少不丢件。
	if slots.is_empty():
		slots.append(origin)
	# 兜底二：件数超过可用格位（MAX_RING 内全满）⇒ 循环复用，绝不丢件。
	var capacity := slots.size()
	var extra := 0
	while slots.size() < n:
		slots.append(slots[extra % capacity])
		extra += 1

	var origin_world := Iso.grid_to_world(origin)
	for i in range(n):
		var row: Dictionary = rows[idx[i]]
		var cell: Vector2i = slots[i]
		row["cell"] = cell
		row["offset"] = Iso.grid_to_world(cell) - origin_world

## 第 `r` 圈的格位增量（Chebyshev 距离 == r）。r=0 只有中心格，r≥1 有 8r 格。
## 环内按**地面视角**角度升序（`Iso.TILE_H` 加权），保证同一份输入永远得到同一份排布。
static func _ring_deltas(r: int) -> Array:
	if r <= 0:
		return [Vector2i.ZERO]
	var ring: Array = []
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) != r:
				continue
			ring.append(Vector2i(dx, dy))
	ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var aa := atan2(float(a.y) * Iso.TILE_H, float(a.x) * Iso.TILE_W)
		var ba := atan2(float(b.y) * Iso.TILE_H, float(b.x) * Iso.TILE_W)
		if is_equal_approx(aa, ba):
			return a.x < b.x
		return aa < ba)
	return ring

## 容纳 `count` 件所需的圈数（`1 + 4r(r+1) ≥ count` 的最小 r）。供测试与文档对照。
static func rings_for(count: int) -> int:
	if count <= 1:
		return 0
	var r := 0
	while 1 + 4 * r * (r + 1) < count:
		r += 1
	return r
