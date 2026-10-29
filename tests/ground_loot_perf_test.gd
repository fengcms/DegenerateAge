extends Node
## 工程 104：地面掉落积压（背包满）性能 —— 四条改动的守门测试。
##
## 守四件事：
## A. 掉落物的**装饰环**走预渲染纹理（`GroundFx.ring`），而技能预警圈仍走折线（`GroundFx.outline`）
##    —— 前者是每帧重画几千次的「装饰」，后者是半径算出来的「玩法」。
## B. 背包满时装备**直接判不可拾取**，金币不受限（不占背包）。
##    关键负向：`_bag_full` 为真而背包**实际有空**时也必须返回 false，
##    否则「早退」被删掉后测试会因为「本来也满了」而假绿。
## C. 拾取扫描节流**只在背包满时**生效；背包未满时掉落一出现就能被立刻走向。
## D. 距离门控：远处静止件不重绘，玩家走近后恢复，悬停中始终重绘。
## E. `ClickArea` 不参与 area 重叠检测，但点击/悬停仍可用。
##
## ⚠ 不写死「多少 ms」这类时间断言（会随机器抖动），只断「行为方向」；
##   具体耗时数字由 `tools/ground_loot_perf_probe` 负责，本测试只防止代码被改回去。

var failures: Array[String] = []
var _root: Node2D
var _player: Node2D


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[GroundLootPerfTest] " + label)


func _ready() -> void:
	_root = Node2D.new()
	_root.name = "LootRoot"
	_root.add_to_group("loot_root")
	add_child(_root)
	_player = Node2D.new()
	_player.name = "Player"
	_player.add_to_group("player")
	add_child(_player)

	_test_ring_texture()
	_test_draw_contract()
	_test_bag_full_gate()
	_test_scan_throttle()
	_check_redraw_gating()
	_test_click_area()

	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[GroundLootPerfTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[GroundLootPerfTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)


# ---- A 预渲染环纹理 ----

## 纹理必须**真的画出东西**：生成器算错（全透明）会让「看得见的圈」变成隐形，
## 而性能看起来完美 —— 这类假绿必须被挡住。
func _test_ring_texture() -> void:
	var tex := GroundFx.ring_texture()
	check(tex != null, "装饰环纹理应能生成")
	if tex == null:
		return
	check(tex.get_width() == GroundFx.RING_TEX_SIZE, "环纹理宽度应为 %d" % GroundFx.RING_TEX_SIZE)
	check(tex.get_height() == GroundFx.RING_TEX_SIZE, "环纹理高度应为 %d" % GroundFx.RING_TEX_SIZE)
	var img := tex.get_image()
	var opaque := 0
	var center := GroundFx.RING_TEX_SIZE / 2
	if img != null:
		for y in range(GroundFx.RING_TEX_SIZE):
			for x in range(GroundFx.RING_TEX_SIZE):
				if img.get_pixel(x, y).a > 0.05:
					opaque += 1
	check(opaque > 200, "环纹理应有可见像素（实际 %d 个），否则等于圈变成隐形" % opaque)
	check(img != null and img.get_pixel(center, center).a < 0.05,
		"环心必须是空的（否则画出来是一个实心椭球，不是环）")


# ---- A 契约：装饰走 ring、玩法走 outline ----

func _test_draw_contract() -> void:
	var item_src := _read("res://scripts/entities/ground_item.gd")
	check(not item_src.contains("GroundFx.outline("),
		"掉落物装饰圈不应再用折线 outline（每帧数千次 = 积压场景的主要瓶颈）")
	check(item_src.contains("GroundFx.ring("), "掉落物装饰圈应走 GroundFx.ring()（预渲染纹理）")
	# 🔴 反向：技能预警 / 玩家脚下圈是**玩法性**描边，半径与张角都是算出来的，不能被一起改成纹理。
	var skill_src := _read("res://scripts/systems/skill_range_fx.gd")
	check(skill_src.contains("GroundFx.outline("),
		"技能预警圈必须保留折线 outline（纹理做不了动态半径 / 张角）")


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


# ---- B 背包满早退 ----

func _test_bag_full_gate() -> void:
	var pilot := _make_pilot()
	var equip := {"kind": "equip", "itemId": "weapon_iron", "quality": "common"}
	var coin := {"kind": "coin", "itemId": "coin", "gold": 10}
	var gi_equip := _spawn(equip)
	var gi_coin := _spawn(coin)

	# 背包有空：装备可拾取
	_fill_bag(false)
	pilot._bag_full = false
	check(pilot._can_pick(gi_equip), "背包有空时装备应可拾取")

	# 背包真空：装备不可拾取、金币仍可
	_fill_bag(true)
	pilot._bag_full = Inventory.is_full(GameState.inventory)
	check(not pilot._can_pick(gi_equip), "背包满时装备应判不可拾取")
	check(pilot._can_pick(gi_coin), "背包满时金币仍应可拾取（不占背包）")

	# 🔴 关键负向：背包**有空**但缓存说满 ⇒ 必须仍然拒绝。
	# 这条专门证明「早退真的生效」，而不是「背包本来就满所以碰巧返回 false」。
	_fill_bag(false)
	pilot._bag_full = true
	check(not pilot._can_pick(gi_equip),
		"背包满缓存应短路 has_space_for —— 否则 2400 次 × 137 格的扫描会回来")

	gi_equip.free()
	gi_coin.free()
	pilot.free()
	_fill_bag(false)


# ---- C 节流只在背包满时生效 ----

func _test_scan_throttle() -> void:
	var pilot := _make_pilot()
	# 背包满 + 节流冷却中 ⇒ 不扫描（`_loot_scan_t` 保持原值）
	_fill_bag(true)
	pilot._bag_full = true
	pilot._loot_scan_t = 1.0
	var throttled: bool = pilot._tick_loot()
	check(not throttled and pilot._loot == null, "背包满且节流冷却中时不应重扫")
	check(pilot._loot_scan_t >= 0.9, "被节流跳过时不应重置扫描计时")

	# 背包空 + 节流冷却中 ⇒ 仍要扫描（掉落刚出现就得能走向它）
	_fill_bag(false)
	pilot._bag_full = false
	pilot._loot_scan_t = 1.0
	pilot._tick_loot()
	check(absf(pilot._loot_scan_t - AutoBattle.LOOT_SCAN_INTERVAL) < 0.001,
		"背包未满时不应被节流挡住（否则新掉落最多晚 %.2fs 才被捡）" % AutoBattle.LOOT_SCAN_INTERVAL)

	pilot.free()
	_fill_bag(false)


# ---- D 距离门控 ----

func _check_redraw_gating() -> void:
	GameState.auto_pickup_on = false   # 只测重绘调度，不让靠近拾取插手
	var gi := _spawn({"kind": "equip", "itemId": "weapon_iron", "quality": "rare"})
	gi.hold_time = 0.0
	gi.persistent = false
	gi.set_physics_process(false)

	# 先跑过「出场 / 落下」高亮期（`land_time` 默认 0.32s），之后才是「静止件」
	for _i in range(24):
		gi._physics_process(1.0 / 60.0)

	# 远处：不重绘
	_player.global_position = gi.global_position + Vector2(0, 4000)
	gi._range_t = 0.0                  # 强制立刻复查距离
	gi._physics_process(1.0 / 60.0)
	var far_base := gi.redraw_count
	for _i in range(40):
		gi._physics_process(1.0 / 60.0)
	check(gi.redraw_count == far_base,
		"远处静止件不应重绘（实际多了 %d 次）" % (gi.redraw_count - far_base))

	# 走近：恢复动画（10 Hz 低频，跑 0.3s 以上给复查留时间）
	_player.global_position = gi.global_position + Vector2(0, 64)
	gi._range_t = 0.0
	for _i in range(30):
		gi._physics_process(1.0 / 60.0)
	check(gi.redraw_count > far_base, "玩家走近后应恢复重绘")

	# 悬停：即使远处也每帧重绘
	_player.global_position = gi.global_position + Vector2(0, 4000)
	gi._range_t = 0.0
	gi._physics_process(1.0 / 60.0)
	var hover_base := gi.redraw_count
	gi._hovered = true
	gi._physics_process(1.0 / 60.0)
	check(gi.redraw_count == hover_base + 1, "悬停中的掉落物必须每帧重绘（名字要跟着高亮变）")
	gi._hovered = false

	gi.free()
	GameState.auto_pickup_on = true


# ---- E ClickArea 不再参与物理重叠检测 ----

func _test_click_area() -> void:
	var gi := _spawn({"kind": "equip", "itemId": "weapon_iron", "quality": "common"})
	var area := gi.get_node_or_null("ClickArea") as Area2D
	check(area != null, "GroundItem 应有 ClickArea 子节点")
	if area != null:
		check(not area.monitoring, "ClickArea 不应开启 monitoring（2400 个 Area2D 互相查询纯浪费）")
		check(not area.monitorable, "ClickArea 不应开启 monitorable")
		check(area.input_pickable, "input_pickable 必须为真，否则点击拾取与悬停名字全部失效")
	gi.free()


# ---- 夹具 ----

## `AutoBattle` 的 `_ready` 要求父节点是 `PlayerCharacter`，否则会 push_warning。
## 这里要的只是 `_can_pick` / `_tick_loot` 的判据，所以用一个**空转**子类绕开 `_ready`，
## 但仍然 `add_child`（`_find_loot` 要用 `get_tree()`）。
class FakePilot:
	extends AutoBattle

	func _ready() -> void:
		set_physics_process(false)


func _make_pilot() -> FakePilot:
	var pilot := FakePilot.new()
	add_child(pilot)
	return pilot


func _spawn(item: Dictionary) -> GroundItem:
	var gi: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi.item = item
	gi.auto_claim = false
	gi.persistent = false
	gi.hold_time = 0.0
	_root.add_child(gi)
	gi.set_physics_process(false)
	return gi


## `full = true` 塞满背包；`false` 清空。装备件用真实模板实例，避免影响堆叠判定。
func _fill_bag(full: bool) -> void:
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null
	if not full:
		return
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = {
			"kind": "equip", "itemId": "weapon_iron", "uid": "bag_%d" % i,
			"quality": "common", "level": 1,
		}
