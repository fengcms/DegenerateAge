extends Node
## 工程 93（D-31）「一格一件」掉落铺格契约。
##
## 核心底线：这套算法一旦退化，游戏**能跑、能掉、能捡、不报错** ——
## 只是又回到「86 件叠成一个圆环糊成一团」，而这**不会被任何其他测试发现**。
## 所以断言全部压在「格位唯一 / 格心对齐 / 圈内可走 / 内侧优先 / 兜底不丢件」上。
##
## 数值背景（见 docs/工程文档/93）：旧环带在 86 件时每件等效直径仅 30px（< 图标 32px），
## 名字宽 240px 是格距 64px 的 3.75 倍 —— 重叠是**物理必然**，不是排布算法没调好。

const SOLO_SIZE := Vector2i(40, 30)      # 孤王绝域尺寸：格铺最容易撞边界的一张图
const MAX_TABLE_COUNT := 102             # DT_C7_Solo_Boss 上限件数（最坏情况）

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[LootGridTest] " + label)

func _ready() -> void:
	_test_one_per_cell()
	_test_ring_growth()
	_test_inner_first()
	_test_walkable()
	_test_bounds()
	_test_overflow()
	_test_label_crowd()
	_test_deterministic()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[LootGridTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[LootGridTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

## 造一批 n 件（1 金币 + n-2 普通装备 + 1 传说），保证内容贴近真实掉落。
func _batch(n: int) -> Array:
	var out: Array = [{"kind": "coin", "itemId": "coin", "gold": 100, "count": 1}]
	for i in range(maxi(0, n - 2)):
		out.append({"kind": "equip", "quality": "common", "instanceId": "c%d" % i})
	if n >= 2:
		out.append({"kind": "equip", "quality": "legendary", "instanceId": "leg"})
	return out

func _cells_of(plan: Array) -> Array:
	var out: Array = []
	for row in plan:
		var cell_v: Variant = row.get("cell", null)
		check(cell_v is Vector2i, "每份掉落都必须带格位（一件一格），实际 %s" % str(cell_v))
		if cell_v is Vector2i:
			out.append(cell_v as Vector2i)
	return out

static func _ring_of(cell: Vector2i) -> int:
	return maxi(absi(cell.x), absi(cell.y))

# ---- 1) 一件一格：格位唯一 + 落点等于格心偏移 ----

func _test_one_per_cell() -> void:
	var ctx := {"origin": Vector2i.ZERO}
	var plan := LootBurst.build(_batch(MAX_TABLE_COUNT), "boss", ctx)
	check(plan.size() == MAX_TABLE_COUNT, "102 件应产出 102 行，实际 %d" % plan.size())
	var cells := _cells_of(plan)
	check(cells.size() == MAX_TABLE_COUNT, "102 件都应有格位，实际 %d" % cells.size())

	# 🔴 这是本条的核心：**任意两件不得同格**。旧环带算法在这里必然失败。
	var seen := {}
	for i in range(cells.size()):
		var c: Vector2i = cells[i]
		check(not seen.has(c), "两件掉落落在同一格 %s（第 %d 件与第 %d 件）"
			% [str(c), int(seen.get(c, -1)), i])
		seen[c] = i

	# 落点偏移必须**精确等于**目标格心相对击杀格心的差（否则实机落点是「死亡点 + 偏移」，格子会歪）
	for row in plan:
		var cell_v: Variant = row.get("cell", null)
		if not (cell_v is Vector2i):
			continue
		var expect_off := Iso.grid_to_world(cell_v as Vector2i) - Iso.grid_to_world(Vector2i.ZERO)
		check((row["offset"] as Vector2).is_equal_approx(expect_off),
			"格 %s 的 offset 应为 %s，实际 %s" % [str(cell_v), str(expect_off), str(row["offset"])])
		# 格心反解必须回到同一格（防止将来有人改 Iso 公式而不同步）
		check(Vector2i(Iso.world_to_grid(Iso.grid_to_world(cell_v as Vector2i)).round()) == cell_v,
			"格 %s 的格心反解不一致（Iso 公式被改？）" % str(cell_v))

# ---- 2) 圈数按件数自动扩展 ----

func _test_ring_growth() -> void:
	# 累计格数 1 + 4r(r+1)：r=0 → 1、r=1 → 9、r=2 → 25、r=3 → 49、r=5 → 121
	var expect := {1: 0, 9: 1, 10: 2, 25: 2, 26: 3, 49: 3, 50: 4, 102: 5, 121: 5, 122: 6}
	for count in expect.keys():
		var got := LootBurst.rings_for(int(count))
		check(got == int(expect[count]),
			"%d 件应需 %d 圈，实际 %d 圈" % [int(count), int(expect[count]), got])

	# 实际排布用到的最大圈号必须与 rings_for 一致（不是「多铺一圈也无所谓」）
	for count in [1, 7, 25, 26, 102]:
		var plan := LootBurst.build(_batch(int(count)), "boss", {"origin": Vector2i.ZERO})
		var max_ring := 0
		for c in _cells_of(plan):
			max_ring = maxi(max_ring, _ring_of(c as Vector2i))
		check(max_ring == LootBurst.rings_for(int(count)),
			"%d 件实际用到 %d 圈，应恰好 %d 圈" % [int(count), max_ring, LootBurst.rings_for(int(count))])

# ---- 3) 内侧优先（传说最内、金币最外） ----

func _test_inner_first() -> void:
	var plan := LootBurst.build(_batch(120), "boss", {"origin": Vector2i.ZERO})
	var n := plan.size()
	check(String(plan[0]["item"].get("kind", "")) == "coin", "展示序首份应是金币")
	check(String(plan[n - 1]["item"].get("quality", "")) == "legendary", "展示序末份应是传说")
	var coin_cell: Vector2i = plan[0]["cell"]
	var legend_cell: Vector2i = plan[n - 1]["cell"]
	check(_ring_of(legend_cell) == 0, "传说应占中心格（r=0），实际 r=%d" % _ring_of(legend_cell))
	check(_ring_of(coin_cell) > 0, "金币不应占中心格（内侧优先给好装备），实际 r=%d" % _ring_of(coin_cell))
	# 中心格必须真的在**击杀格**上，不是地图原点（origin 非零时最容易搞错）
	var moved := LootBurst.build(_batch(120), "boss", {"origin": Vector2i(7, 9)})
	check(Vector2i(moved[moved.size() - 1]["cell"]) == Vector2i(7, 9),
		"origin=(7,9) 时传说的目标格应为 (7,9)，实际 %s" % str(moved[moved.size() - 1]["cell"]))
	check((moved[moved.size() - 1]["offset"] as Vector2) == Vector2.ZERO,
		"中心格的 offset 必须为 0（落点＝击杀格心）")

# ---- 4) 可走性：不可走的格必须被跳过 ----

func _test_walkable() -> void:
	var origin := Vector2i(20, 15)
	# 东侧一堵竖墙：x >= 23 一律不可走
	var wall := func(cell: Vector2i) -> bool:
		return cell.x < 23
	var plan := LootBurst.build(_batch(102), "boss", {"origin": origin, "walkable": wall})
	var cells := _cells_of(plan)
	check(cells.size() == 102, "跳过不可走格不得丢件：应 102 格，实际 %d" % cells.size())
	for c in cells:
		check((c as Vector2i).x < 23, "格 %s 落进了不可走区（x≥23）" % str(c))

	# 中心格不可走（怪物死在墙边）⇒ 传说必须让位到内圈第一个可走格
	var block_center := func(cell: Vector2i) -> bool:
		return cell != origin
	var plan2 := LootBurst.build(_batch(20), "boss", {"origin": origin, "walkable": block_center})
	var legend_cell: Vector2i = plan2[plan2.size() - 1]["cell"]
	check(legend_cell != origin, "中心格不可走时传说不得落在中心格")
	check(_ring_of(legend_cell - origin) == 1,
		"中心格不可走时传说应退到 r=1 圈，实际 r=%d" % _ring_of(legend_cell - origin))

# ---- 5) 地图边界：越界格必须被拒（否则会被 clamp 挤回同一堆） ----

func _test_bounds() -> void:
	var origin := Vector2i(SOLO_SIZE.x / 2, SOLO_SIZE.y / 2)
	# 与 Monster._loot_layout_context() 同口径：clamp_to_map 的合法范围是 [2, size-3]
	var in_bounds := func(cell: Vector2i) -> bool:
		return cell.x >= 2 and cell.y >= 2 and cell.x < SOLO_SIZE.x - 2 and cell.y < SOLO_SIZE.y - 2
	var plan := LootBurst.build(_batch(MAX_TABLE_COUNT), "boss", {"origin": origin, "walkable": in_bounds})
	var cells := _cells_of(plan)
	check(cells.size() == MAX_TABLE_COUNT, "位于图心时 102 件不该触发兜底：实际 %d 格" % cells.size())
	for c in cells:
		var cell: Vector2i = c
		check(cell.x >= 2 and cell.y >= 2 and cell.x < SOLO_SIZE.x - 2 and cell.y < SOLO_SIZE.y - 2,
			"格 %s 越界（合法范围 x∈[2,%d] y∈[2,%d]）" % [str(cell), SOLO_SIZE.x - 3, SOLO_SIZE.y - 3])

	# 贴角落：可用格骤减，算法必须扩圈而不是铺到图外
	var corner := LootBurst.build(_batch(40), "boss", {"origin": Vector2i(3, 3), "walkable": in_bounds})
	for c in _cells_of(corner):
		var cell: Vector2i = c
		check(cell.x >= 2 and cell.y >= 2 and cell.x < SOLO_SIZE.x - 2 and cell.y < SOLO_SIZE.y - 2,
			"贴角落时格 %s 越界" % str(cell))

# ---- 6) 件数超过可用格位：循环复用，绝不丢件 ----

func _test_overflow() -> void:
	# 只留一列可走 ⇒ 容量远小于件数，必然走到「循环复用」兜底
	var one_column := func(cell: Vector2i) -> bool:
		return cell.x == 20
	var plan := LootBurst.build(_batch(700), "boss", {"origin": Vector2i(20, 15), "walkable": one_column})
	check(plan.size() == 700, "兜底路径不得丢件：应 700 行，实际 %d" % plan.size())
	var cells := _cells_of(plan)
	check(cells.size() == 700, "兜底路径每份仍须有格位：实际 %d" % cells.size())
	var distinct := {}
	for c in cells:
		distinct[c] = true
		check((c as Vector2i).x == 20, "兜底时格 %s 仍须在可走列上" % str(c))
	check(distinct.size() < 700, "可用格只有一列（最多 %d 格），必然复用 —— 说明兜底分支真的被走到了" % (2 * LootBurst.MAX_RING + 1))
	check(distinct.size() >= 2, "兜底不该把 700 件全叠在同一格（应循环复用，实际 %d 格）" % distinct.size())

# ---- 7) 名字降噪：同批 ≥ 阈值时稀有以上只悬停显示 ----

func _test_label_crowd() -> void:
	check(GroundItem.LABEL_CROWD_LIMIT == 20,
		"名字降噪阈值应为 20 件（工程 93 Q1=A 拍板），实际 %d" % GroundItem.LABEL_CROWD_LIMIT)
	var limit := GroundItem.LABEL_CROWD_LIMIT
	# 少件：稀有以上常显（保留「掉了件紫的」这种一眼可见的爽感）
	for q in ["rare", "epic", "legendary"]:
		check(GroundItem.should_always_show_label(String(q), limit - 1),
			"同批 %d 件（< 阈值）时 %s 应常显名字" % [limit - 1, String(q)])
	# 多件：不再常显，避免 100 个名字（各宽 240px）叠成糊字
	for q in ["rare", "epic", "legendary"]:
		check(not GroundItem.should_always_show_label(String(q), limit),
			"同批 %d 件（≥ 阈值）时 %s 不应常显名字（名字宽 240px ≫ 格距 64px）" % [limit, String(q)])
	# 普通 / 优秀本来就不常显，与件数无关
	for q in ["common", "uncommon"]:
		for bs in [1, limit, 500]:
			check(not GroundItem.should_always_show_label(String(q), int(bs)),
				"%s 在任何件数下都不常显名字（%d 件）" % [String(q), int(bs)])
	# 孤王绝域的真实批次必须落入降噪分支
	var solo := LootBurst.build(_batch(MAX_TABLE_COUNT), "boss", {"origin": Vector2i(20, 15)})
	check(solo.size() >= limit, "孤王绝域批次 %d 件应触发名字降噪" % solo.size())

# ---- 8) 确定性：同一输入必须给出同一排布 ----

func _test_deterministic() -> void:
	var ctx := {"origin": Vector2i(20, 15)}
	var a := LootBurst.build(_batch(102), "boss", ctx)
	var b := LootBurst.build(_batch(102), "boss", ctx)
	check(a.size() == b.size(), "两次 build 行数应一致")
	for i in range(mini(a.size(), b.size())):
		check(Vector2i(a[i]["cell"]) == Vector2i(b[i]["cell"]),
			"第 %d 件的格位不确定：%s vs %s" % [i, str(a[i]["cell"]), str(b[i]["cell"])])
