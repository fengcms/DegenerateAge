extends Node
## 工程 104 探针（只读，不写档）：地面掉落物积压时的性能定位。
##
## 触发场景：百首禁域 `unclaimedLootCap = 2400` + `preserveUnclaimedLoot = true`
## ⇒ 背包满后，未领取战利品**永不淡出**，可长期积压到上千件 GroundItem 同屏。
##
## 本探针把开销拆成四份分别实测，避免"感觉卡"式的猜测：
##   A. `get_first_node_in_group("player")` 单次成本 —— GroundItem 每帧每件都要调一次
##   B. `_physics_process` 单件成本（未认领 + 背包满路径），随件数线性增长
##   C. `AutoBattle._find_loot` 等价扫描（背包满时 `_loot` 恒为 null ⇒ **每帧全表重扫**）
##   D. 每帧无条件 `queue_redraw()` 的重绘成本（用同复杂度替身节点实测）
##
## 不写存档：全程关闭 autosave，且不触碰任何真实档位。

const SCENE: PackedScene = preload("res://scenes/entities/GroundItem.tscn")
const COUNTS := [0, 200, 600, 1200, 2400]
const BAG_FULL := 137
const FRAMES := 40

var _loot_root: Node2D
var _player: Node2D
var _rng := RandomNumberGenerator.new()
var _items: Array[GroundItem] = []


func _ready() -> void:
	SaveManager.autosave_enabled = false
	Engine.max_fps = 0
	GameState.reset_to_defaults()
	GameState.player.level = 140
	GameState.settings["dropFlyAnim"] = true
	GameState.auto_pickup_on = true
	# 🔴 必须指定地图：未领取战利品上限是**按图取**的（`unclaimed_loot_cap(current_map)`），
	# 空地图名会落到缺省 20 —— 2400 件会被 FIFO 立即淘汰成 20 件，探针静默测不到积压态。
	GameState.current_map = "c7_boss_field"
	_rng.seed = 104
	_loot_root = Node2D.new()
	_loot_root.name = "LootRoot"
	_loot_root.add_to_group("loot_root")
	add_child(_loot_root)
	_player = Node2D.new()
	_player.name = "Player"
	_player.add_to_group("player")
	add_child(_player)
	_player.global_position = Vector2(8000, 8000)   # 远离掉落物：不走靠近自动拾取分支

	print("=== 工程 104 地面掉落积压性能探针 ===")
	print("PROBE 结构｜current_map=%s 未领取上限=%d 总数=%d" % [
		GameState.current_map, GameState.unclaimed_loot_cap(GameState.current_map),
		GameState.unclaimed_count(GameState.current_map)])
	_report_structural()
	_report_player_lookup()
	await _report_scale()
	await _report_loot_scan()
	await _report_redraw()
	GameState.unclaimed_loot.clear()
	print("=== PROBE DONE ===")
	get_tree().quit(0)


# ---- 结构计数 ----

## 一件 GroundItem = Node2D + Area2D(input_pickable) + CollisionShape2D。
## Area2D 默认 `monitoring = true` ⇒ 每件都要进物理广相并参与重叠查询。
func _report_structural() -> void:
	var sample: GroundItem = SCENE.instantiate()
	var area := sample.get_node_or_null("ClickArea") as Area2D
	var monitoring := area.monitoring if area != null else false
	var monitorable := area.monitorable if area != null else false
	var pickable := area.input_pickable if area != null else false
	print("PROBE 结构｜单件节点数=%d｜Area2D monitoring=%s monitorable=%s input_pickable=%s" % [
		_count_nodes(sample), str(monitoring), str(monitorable), str(pickable)])
	sample.free()
	print("PROBE 结构｜百首禁域上限 2400 件 ⇒ Area2D %d 个 + 碰撞形状 %d 个 + CanvasItem %d 个" % [
		2400, 2400, 2400])


func _count_nodes(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count_nodes(c)
	return total


# ---- A. 组查询成本 ----

## GroundItem 每帧每件都会调 `_get_player()` → `get_tree().get_first_node_in_group("player")`。
## 分别在小场景树（当前）与大场景树（挂 2400 个惰性节点）下量。
func _report_player_lookup() -> void:
	var small := _time_player_lookup(20000)
	var filler: Array[Node] = []
	for i in range(2400):
		var n := Node2D.new()
		n.set_physics_process(false)
		_loot_root.add_child(n)
		filler.append(n)
	var big := _time_player_lookup(20000)
	for n in filler:
		n.free()
	print("PROBE A｜get_first_node_in_group(\"player\") 单次：小树 %.3f µs ｜ 树内 +2400 节点 %.3f µs" % [
		small, big])
	print("PROBE A｜2400 件 × 每帧 1 次 ⇒ 小树 %.3f ms/帧 ｜ 大树 %.3f ms/帧" % [
		small * 2400.0 / 1000.0, big * 2400.0 / 1000.0])


func _time_player_lookup(times: int) -> float:
	var t0 := Time.get_ticks_usec()
	var hits := 0
	for i in range(times):
		if get_tree().get_first_node_in_group("player") != null:
			hits += 1
	var us := float(Time.get_ticks_usec() - t0) / float(times)
	if hits != times:
		print("PROBE A｜⚠ 组查询命中数异常 %d/%d" % [hits, times])
	return us


# ---- B. _physics_process 单件成本 ----

## 手动调用 `_physics_process`（先把节点的自动处理关掉），排除引擎调度噪声。
## 未认领 + persistent + 背包满 = 最坏路径：每帧 `_get_player()` + 距离判定 + `queue_redraw()`。
func _report_scale() -> void:
	print("PROBE B｜未认领 persistent 物的 _physics_process 单件成本（背包满口径）")
	var baseline := 0.0
	for n in COUNTS:
		while _items.size() < n:
			var gi := _make_item(_items.size())
			_items.append(gi)
		# 预热一帧，避免首次 redraw 的抖动算进均值
		for gi in _items:
			gi._physics_process(1.0 / 60.0)
		var t0 := Time.get_ticks_usec()
		for _f in range(FRAMES):
			for gi in _items:
				gi._physics_process(1.0 / 60.0)
		var us := float(Time.get_ticks_usec() - t0) / float(FRAMES)
		var per_item := us / float(maxi(1, n)) if n > 0 else 0.0
		if n == 0:
			baseline = us
		print("PROBE B｜N=%4d ⇒ 每帧 %7.3f ms ｜ 单件 %6.3f µs ｜ 相对基线 +%.3f ms" % [
			n, us / 1000.0, per_item, (us - baseline) / 1000.0])
		await get_tree().process_frame
	_clear_items()


func _make_item(index: int) -> GroundItem:
	var gi: GroundItem = SCENE.instantiate()
	gi.item = _roll_equip(index)
	gi.auto_claim = false            # 背包满：认领失败，保持未认领
	gi.persistent = true             # 精英 / Boss 战利品：不参与 60s 淡出
	gi.batch_size = 20               # 单批 20 件（Boss 单次掉落量级）
	gi.appear_delay = 0.0
	gi.hold_time = 0.0
	gi.set_physics_process(false)    # 手动计时，排除引擎调度
	_loot_root.add_child(gi)
	gi.global_position = Vector2(10000 + (index % 60) * 64, 10000 + (index / 60) * 32)
	return gi


func _roll_equip(index: int) -> Dictionary:
	var pool := ["c6_equip_weapon", "c6_equip_ring", "c6_equip_helmet", "c6_equip_armor"]
	var item_id := String(pool[index % pool.size()])
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	if not tpl is Dictionary:
		return {"kind": "misc", "itemId": "missing_%d" % index}
	var bases: Variant = (tpl as Dictionary).get("tierBases", {})
	var tier := 1
	if bases is Dictionary and not (bases as Dictionary).is_empty():
		tier = int(String((bases as Dictionary).keys()[0]))
	var quality := "rare" if index % 7 == 0 else ("epic" if index % 11 == 0 else "uncommon")
	return ItemFactory.make_equip_roll(item_id, tier, quality, _rng)


func _clear_items() -> void:
	for gi in _items:
		if is_instance_valid(gi):
			gi.free()
	_items.clear()
	GameState.unclaimed_loot.clear()


# ---- C. 顺路拾取扫描 ----

## `AutoBattle._tick_loot()` 在 `_loot == null` 时**每物理帧**调 `_find_loot()`；
## 背包满 ⇒ `_can_pick` 全部为 false ⇒ `_loot` 恒 null ⇒ 每帧全表重扫 + 每件一次
## `Inventory.has_space_for()`（不可堆叠 = 扫 137 格找空位）。
func _report_loot_scan() -> void:
	while _items.size() < 2400:
		var gi := _make_item(_items.size())
		_items.append(gi)
	# 背包满：137 格全塞满
	GameState.inventory.resize(BAG_FULL)
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = _roll_equip(i * 3 + 1)
	var full := _time_scan(10)
	# 拆解：只遍历组 vs 只做背包空位判定（背包仍满）
	var t0 := Time.get_ticks_usec()
	for _i in range(10):
		for g in get_tree().get_nodes_in_group("ground_items"):
			if not g is GroundItem:
				continue
	var walk_only := float(Time.get_ticks_usec() - t0) / 10.0 / 1000.0
	var probe_item: Dictionary = (_items[0] as GroundItem).item
	var t1 := Time.get_ticks_usec()
	for _i in range(2400 * 10):
		Inventory.has_space_for(GameState.inventory, probe_item)
	var space_only := float(Time.get_ticks_usec() - t1) / 10.0 / 1000.0
	print("PROBE C｜拆解：只遍历组 %.3f ms ｜ 2400 次 has_space_for %.3f ms（背包满 ⇒ 每次扫 137 格）" % [
		walk_only, space_only])
	# 背包空：早期场景，`_first_empty` 首格即命中
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null
	var empty := _time_scan(10)
	# 新口径：先判一次 `is_full`，背包满时装备根本不进 `has_space_for`
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = _roll_equip(i * 3 + 1)
	var full_fast := _time_scan(10, true)
	print("PROBE C｜改后口径（背包满早退）：%.3f ms/次 ⇒ 相对旧口径 %.1f%%" % [
		full_fast, full_fast / maxf(0.001, full) * 100.0])
	print("PROBE C｜_find_loot 等价全表扫描（2400 件）单次：背包满 %.3f ms ｜ 背包空 %.3f ms" % [
		full, empty])
	print("PROBE C｜背包满时每物理帧 1 次 ⇒ %.3f ms/帧" % full)
	_clear_items()
	GameState.inventory.resize(40)
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null


func _time_scan(times: int, bag_full_flag: bool = false) -> float:
	var t0 := Time.get_ticks_usec()
	var hits := 0
	for _i in range(times):
		hits += _scan_once(bag_full_flag)
	return float(Time.get_ticks_usec() - t0) / float(times) / 1000.0


## AutoBattle._find_loot 的判据复刻（除 `_route_reachable`：背包满时走不到那一步）。
## `bag_full_flag = true` 走工程 104 的新口径（背包满 ⇒ 装备直接跳过，不扫格子）。
func _scan_once(bag_full_flag: bool = false) -> int:
	var best: GroundItem = null
	var best_d := INF
	var bag_full := bag_full_flag and Inventory.is_full(GameState.inventory)
	for g in get_tree().get_nodes_in_group("ground_items"):
		if not (g is GroundItem):
			continue
		var gi := g as GroundItem
		if gi.item.is_empty():
			continue
		if not gi.visible or gi.is_queued_for_deletion() or gi.manual_only:
			continue
		if String(gi.item.get("kind", "")) == "coin":
			if GameState.gold_is_capped():
				continue
		elif bag_full:
			continue
		elif not Inventory.has_space_for(GameState.inventory, gi.item):
			continue
		var d := _player.global_position.distance_to(gi.global_position)
		if d <= GroundItem.PICKUP_RANGE_PX or d > 10.0 * Iso.TILE_W:
			continue
		if d < best_d:
			best_d = d
			best = gi
	return 1 if best != null else 0


# ---- D. 每帧重绘成本 ----

## GroundItem 每帧无条件 `queue_redraw()`（`_physics_process` 里那句）。
## 用同 draw 调用序列的替身节点实测「重绘 vs 不重绘」的帧耗时差。
func _report_redraw() -> void:
	if RedrawProbe.ring_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		RedrawProbe.ring_tex = ImageTexture.create_from_image(img)
	var stand_in: Array[RedrawProbe] = []
	for i in range(1200):
		var p := RedrawProbe.new()
		_loot_root.add_child(p)
		stand_in.append(p)
	await get_tree().process_frame
	await get_tree().process_frame
	var idle := await _time_frames(stand_in, false)
	for p in stand_in:
		p.with_label = false
	var no_label := await _time_frames(stand_in, true)
	for p in stand_in:
		p.with_label = true
	var busy := await _time_frames(stand_in, true)
	var draws := 0
	for p in stand_in:
		draws += p.draws
	print("PROBE D｜1200 个同复杂度节点：不重绘 %.3f ms/帧 ｜ 重绘（无名字）%.3f ms/帧 ｜ 重绘（含名字）%.3f ms/帧" % [
		idle, no_label, busy])
	print("PROBE D｜⇒ 重绘净增 %.3f ms/帧，其中 draw_string 名字 %.3f ms（占 %.0f%%）" % [
		busy - idle, busy - no_label, (busy - no_label) / maxf(0.001, busy - idle) * 100.0])
	print("PROBE D｜_draw 实际执行次数=%d（0 表示 headless 不触发绘制回调，只能看真机）" % draws)
	# E：把 _draw 压到最小（一个圆），判断「每帧重绘一件」是固定成本（canvas item 重建）
	# 还是随 draw 命令数增长 —— 前者只能靠减少重绘件数，后者可以合并绘制。
	for p in stand_in:
		p.mode = 1
	var minimal := await _time_frames(stand_in, true)
	print("PROBE E｜1200 节点最小绘制（1 个圆）：%.3f ms/帧（不重绘 %.3f）⇒ 每件 %.2f µs" % [
		minimal, idle, (minimal - idle) * 1000.0 / 1200.0])
	# F：只保留 4 条 GroundFx.outline（抗锯齿折线），不带圆 / 光柱 / 名字
	for p in stand_in:
		p.mode = 2
	var outlines := await _time_frames(stand_in, true)
	print("PROBE F｜1200 节点只画 4 条 outline（抗锯齿）：%.3f ms/帧 ⇒ 每件 %.2f µs" % [
		outlines, (outlines - idle) * 1000.0 / 1200.0])
	# G：同上但关抗锯齿
	for p in stand_in:
		p.mode = 3
	var no_aa := await _time_frames(stand_in, true)
	print("PROBE G｜1200 节点只画 4 条 outline（无抗锯齿）：%.3f ms/帧 ⇒ 每件 %.2f µs" % [
		no_aa, (no_aa - idle) * 1000.0 / 1200.0])
	# H：同样 4 个装饰换成 2 次预渲染纹理 blit（= 方案「椭圆环预渲染」的等效成本）
	for p in stand_in:
		p.mode = 4
	var textured := await _time_frames(stand_in, true)
	print("PROBE H｜1200 节点画 2 张预渲染环纹理：%.3f ms/帧 ⇒ 每件 %.2f µs" % [
		textured, (textured - idle) * 1000.0 / 1200.0])
	# I：**照抄改后的 `GroundItem._draw`**（4 条 ring + 光柱 + 阴影 + 图标 + 名字）
	for p in stand_in:
		p.mode = 5
	var after := await _time_frames(stand_in, true)
	print("PROBE I｜1200 节点 = 改后 GroundItem._draw 全套：%.3f ms/帧 ⇒ 每件 %.2f µs" % [
		after, (after - idle) * 1000.0 / 1200.0])
	# J：只留光柱（draw_rect + 抗锯齿 draw_line），去掉所有环
	for p in stand_in:
		p.mode = 6
	var beam := await _time_frames(stand_in, true)
	print("PROBE J｜1200 节点只画光柱（rect + AA line）：%.3f ms/帧 ⇒ 每件 %.2f µs" % [
		beam, (beam - idle) * 1000.0 / 1200.0])
	for p in stand_in:
		p.mode = 0
	for p in stand_in:
		p.free()

func _time_frames(nodes: Array[RedrawProbe], redraw: bool) -> float:
	var t0 := Time.get_ticks_usec()
	for _f in range(FRAMES):
		for p in nodes:
			if redraw:
				p.queue_redraw()
		await get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / float(FRAMES) / 1000.0


## 与 GroundItem._draw 同复杂度的替身。
## `mode = 0` 是**工程 104 之前**的 `_draw` 复刻（`GroundFx.outline` 折线），留作对照基线；
## `mode = 5` 是**改后**的全套（`GroundFx.ring` 纹理环）。两者跑同一批节点，差值即本次收益。
class RedrawProbe:
	extends Node2D
	const FONT: Font = preload("res://assets/themes/mono_font.tres")
	var draws := 0
	var with_label := true
	## 0 = 与 GroundItem._draw 同复杂度；1 = 仅一个圆；2 = 仅 4 条抗锯齿 outline；3 = 同上但无抗锯齿；
	## 4 = 2 次预渲染纹理 blit（替代 4 条 outline）
	var mode := 0
	static var ring_tex: Texture2D = null

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 与 GroundItem 一致

	func _draw() -> void:
		draws += 1
		if mode == 1:
			draw_circle(Vector2.ZERO, 9.0, Color(0.62, 0.29, 0.95))
			return
		if mode == 4:
			if ring_tex != null:
				draw_texture_rect(ring_tex, Rect2(-32, -24, 64, 64), false)
				draw_texture_rect(ring_tex, Rect2(-40, -32, 80, 80), false)
			return
		if mode == 5:
			# 照抄改后的 GroundItem._draw（稀有 + 史诗混合件的最坏组合）
			draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, Iso.GROUND_SQUASH))
			draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.28))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_rect(Rect2(-3.5, -54.0, 7.0, 60.0), Color(0.62, 0.29, 0.95, 0.30))
			draw_line(Vector2(0, 6), Vector2(0, -54), Color(0.62, 0.29, 0.95, 0.85), 1.5, true)
			GroundFx.ring(self, Vector2(0, 8), 16.0, Color(0.62, 0.29, 0.95), 0.60)
			GroundFx.ring(self, Vector2(0, 8), 23.0, Color(0.62, 0.29, 0.95), 0.35)
			GroundFx.ring(self, Vector2(0, 8), 26.0, Color(1.0, 0.62, 0.30), 0.85)
			GroundFx.ring(self, Vector2(0, 8), 30.0, Color(1.0, 0.62, 0.30), 0.45)
			draw_circle(Vector2(0, -16), 9.0, Color(0.62, 0.29, 0.95))
			if with_label:
				draw_string(FONT, Vector2(-120.0, -36.0), "残破的测试装备名",
					HORIZONTAL_ALIGNMENT_CENTER, 240.0, 13.0, Color.WHITE)
			return
		if mode == 6:
			draw_rect(Rect2(-3.5, -54.0, 7.0, 60.0), Color(0.62, 0.29, 0.95, 0.30))
			draw_line(Vector2(0, 6), Vector2(0, -54), Color(0.62, 0.29, 0.95, 0.85), 1.5, true)
			return
		if mode == 2 or mode == 3:
			var aa := mode == 2
			for r in [16.0, 23.0, 26.0, 30.0]:
				var pts := Iso.ground_ellipse(Vector2(0, 8), r, 28)
				pts.append(pts[0])
				draw_polyline(pts, Color(0.62, 0.29, 0.95, 0.6), 1.8, aa)
			return
		var c := Vector2(0, -16)
		draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, Iso.GROUND_SQUASH))
		draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(-3.5, -54.0, 7.0, 60.0), Color(0.62, 0.29, 0.95, 0.30))
		draw_line(Vector2(0, 6), Vector2(0, -54), Color(0.62, 0.29, 0.95, 0.85), 1.5, true)
		GroundFx.outline(self, Vector2(0, 8), 16.0, Color(0.62, 0.29, 0.95, 0.60), 1.8, 28)
		GroundFx.outline(self, Vector2(0, 8), 23.0, Color(0.62, 0.29, 0.95, 0.35), 1.3, 28)
		GroundFx.outline(self, Vector2(0, 8), 26.0, Color(1.0, 0.62, 0.30, 0.85), 2.0, 32)
		GroundFx.outline(self, Vector2(0, 8), 30.0, Color(1.0, 0.62, 0.30, 0.45), 1.2, 32)
		draw_circle(c, 9.0, Color(0.62, 0.29, 0.95))
		if with_label:
			draw_string(FONT, Vector2(c.x - 120.0, c.y - 20.0), "残破的测试装备名",
				HORIZONTAL_ALIGNMENT_CENTER, 240.0, 13.0, Color.WHITE)
