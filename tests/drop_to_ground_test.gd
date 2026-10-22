extends Node
## 工程 89：背包拖拽丢弃地面（产品 05 §5.8 / 09 §9.9）。
##
## 覆盖分析文档 §8 的八条正向 + 三条「开关/判据」断言。全部走**公开入口**
## （`GameState.can_drop_item` / `GameState.drop_item_to_ground` / `WorldDropZone.drop_payload`），
## 不直接读 UI 私有状态 —— 否则改实现就能让断言跟着变形。

const ZONE_SCENE := preload("res://scenes/ui/WorldDropZone.tscn")
const GROUND_ITEM := preload("res://scenes/entities/GroundItem.tscn")

var failures: Array[String] = []
var _toast_text := ""
var _toast_count := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

## 落点契约的桩：只实现「不可走 → 退到最近可走格」这一条。
## 不搬真 `Ground`（它要整张地图数据），因为丢弃逻辑对地面的要求仅此一条，
## 而「夹到地图内」本身已有 `Ground.clamp_to_map` 的独立测试。
class StubGround:
	extends Node2D
	var walkable := Rect2(0.0, 0.0, 800.0, 800.0)
	var fallback := Vector2.ZERO

	func clamp_to_map(point: Vector2) -> Vector2:
		return point if walkable.has_point(point) else fallback

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	GameState.auto_pickup_on = false
	EventBus.toast_requested.connect(_on_toast)

	var loot_root := Node2D.new()
	loot_root.name = "LootRoot"
	loot_root.add_to_group("loot_root")
	add_child(loot_root)
	var ground := StubGround.new()
	ground.add_to_group("map_ground")
	add_child(ground)
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(400, 400)
	ground.fallback = player.global_position

	var zone := ZONE_SCENE.instantiate() as WorldDropZone
	add_child(zone)

	_check_gate(zone)
	_check_blocked(zone, loot_root)
	_check_equip_drop(zone, loot_root)
	_check_stale_token(zone, loot_root)
	_check_far_point(zone, loot_root, ground)
	_check_impassable_point(zone, loot_root, ground)
	_check_stack_drop(zone, loot_root)
	_check_manual_only(loot_root, player)
	_check_click_pickup(zone, loot_root)
	_check_no_loot_root(zone, loot_root)

	if failures.is_empty():
		print("DropToGroundTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

func _on_toast(text: String, _kind: String) -> void:
	_toast_text = text
	_toast_count += 1

# ---- 开关：常态不拦点击、仅拖拽期接管 ----

func _check_gate(zone: WorldDropZone) -> void:
	check(not zone.is_armed() and zone.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"投放区常态必须 mouse_filter=IGNORE（否则点地走路/点怪全失灵）")
	zone._sync_filter(true)
	check(zone.is_armed(), "拖拽期投放区应接管鼠标")
	# 🔴 反向：进入拖拽态后，一帧 _process 必须把它拉回 IGNORE（无头下 gui_is_dragging 恒假）。
	zone._process(0.016)
	check(not zone.is_armed(), "松手后首帧必须恢复 IGNORE（漏切会让全屏控件常驻拦截）")
	# 只认背包载荷：仓库 / 出售托盘 / 身上装备都不该落到地面。
	check(zone._can_drop_data(Vector2.ZERO, {"from": ItemSlot.ROLE_BAG, "index": 0, "item": {}, "token": ""}),
		"背包格载荷应可投放到地面")
	check(not zone._can_drop_data(Vector2.ZERO, {"from": ItemSlot.ROLE_WAREHOUSE, "index": 0, "item": {}, "token": ""}),
		"仓库存取不该被投放到地面")
	check(not zone._can_drop_data(Vector2.ZERO, {"from": ItemSlot.ROLE_EQUIP, "index": 0, "item": {}, "token": ""}),
		"身上装备不该被投放到地面")
	check(not zone._can_drop_data(Vector2.ZERO, "不是字典"), "非字典载荷应拒绝")

# ---- 三类不可丢弃（Q2=A）----

func _check_blocked(zone: WorldDropZone, loot_root: Node2D) -> void:
	# 判据本身（不依赖 UI）
	check(bool(GameState.can_drop_item(ItemFactory.make_equip("weapon_iron")).get("ok", false)),
		"普通装备应可丢弃")
	# 🔑 灵能碎片 `useType=quest` 但 `questItem` 未置 ⇒ 设计上可售可丢。
	#    若按「useType==quest 一刀切」，这条会变 false（把可售道具判成任务物品）。
	check(bool(GameState.can_drop_item({"kind": "misc", "itemId": "spirit_shard", "count": 1}).get("ok", false)),
		"灵能碎片（useType=quest 但非 questItem）应可丢弃")
	check(String(GameState.can_drop_item({"kind": "misc", "itemId": "c2_pressure_plate", "count": 1}).get("reason", "")) == "quest_item",
		"任务物品应判 quest_item")
	# 🔑 三件随身工具同时带 `questItem: true` ⇒ 工具判定必须排在 quest 之前，
	#    否则玩家会看到「任务物品不能丢弃：随身车夫」，误以为任务链要断。
	check(String(GameState.can_drop_item({"kind": "misc", "itemId": "tool_portable_carter", "count": 1}).get("reason", "")) == "tool",
		"随身工具应判 tool（先于 quest_item）")
	var favourite := ItemFactory.make_equip("weapon_iron")
	favourite["favorite"] = true
	check(String(GameState.can_drop_item(favourite).get("reason", "")) == "favorite", "收藏装备应判 favorite")

	# 真丢：三类都必须是「背包一件不少 + 地面零件 + 文案对得上真实原因」
	_clear(loot_root)
	var cases := [
		{"item": {"kind": "misc", "itemId": "c2_pressure_plate", "count": 1}, "expect": "任务物品不能丢弃"},
		{"item": {"kind": "misc", "itemId": "tool_portable_carter", "count": 1}, "expect": "随身工具不能丢弃"},
		{"item": favourite.duplicate(true), "expect": "已收藏的装备不能丢弃"},
	]
	for entry in cases:
		var item: Dictionary = entry.item
		GameState.inventory[0] = item.duplicate(true)
		_toast_text = ""
		var toasts_before := _toast_count
		var res := zone.drop_payload(_payload(0, GameState.inventory[0]), Vector2(500, 500))
		check(not bool(res.get("ok", false)), "「%s」不应被丢弃" % String(entry.expect))
		check(GameState.inventory[0] != null, "「%s」被拒后背包必须保持原样" % String(entry.expect))
		check(loot_root.get_child_count() == 0, "「%s」被拒后地面不得生成任何东西" % String(entry.expect))
		check(_toast_count == toasts_before + 1, "「%s」被拒应恰好给一条提示（不刷屏）" % String(entry.expect))
		# 用**字面文案**当判据：key 撞号（后者静默胜出）时这里才会红。
		check(_toast_text.contains(String(entry.expect)), "「%s」应 toast 真实原因，实际「%s」" % [
			String(entry.expect), _toast_text])
		check(_toast_text.contains(ItemUtil.display_name(item)),
			"提示里应带物品名，实际「%s」" % _toast_text)
		GameState.inventory[0] = null
	_clear(loot_root)

# ---- 普通装备丢弃 ----

func _check_equip_drop(zone: WorldDropZone, loot_root: Node2D) -> void:
	_clear(loot_root)
	var equip := ItemFactory.make_equip("weapon_iron")
	GameState.inventory[0] = equip.duplicate(true)
	_toast_text = ""
	var res := zone.drop_payload(_payload(0, GameState.inventory[0]), Vector2(520, 480))
	check(bool(res.get("ok", false)), "普通装备应能丢到地面")
	check(GameState.inventory[0] == null, "丢弃后背包该格必须清空")
	check(loot_root.get_child_count() == 1, "丢弃后地面应生成 1 件")
	var node := loot_root.get_child(0) as GroundItem
	check(node != null, "地面物应为 GroundItem")
	if node == null:
		return
	check(node.item == equip, "地面物应保留原装备实例（不回炉重随机）")
	check(not node.auto_claim and not node.persistent, "丢弃物不得生成即认领、不得登记未领取战利品")
	check(node.manual_only, "丢弃物必须 manual_only（否则脚边 96px 内会被立刻捡回）")
	check(node.global_position.is_equal_approx(Vector2(520, 480)), "落点应取鼠标所指世界坐标")
	# R8：文案必须写明「多久消失」，否则玩家重进游戏会以为是丢档。
	check(_toast_text == "已丢弃：%s（60 秒后消失）" % ItemUtil.display_name(equip),
		"成功 toast 应写明 60 秒后消失，实际「%s」" % _toast_text)

# ---- token 失效（拖拽期间背包被整理）----

func _check_stale_token(zone: WorldDropZone, loot_root: Node2D) -> void:
	_clear(loot_root)
	var equip := ItemFactory.make_equip("weapon_iron")
	GameState.inventory[0] = equip.duplicate(true)
	var payload := _payload(0, GameState.inventory[0])
	# 拖起之后背包被整理：同一格换成了另一件
	GameState.inventory[0] = ItemFactory.make_equip("weapon_iron").duplicate(true)
	_toast_text = ""
	var res := zone.drop_payload(payload, Vector2(500, 500))
	check(String(res.get("reason", "")) == "stale", "token 不符应判 stale")
	check(GameState.inventory[0] != null, "stale 时背包一件都不能少")
	check(loot_root.get_child_count() == 0, "stale 时地面不得生成任何东西")
	check(_toast_text == "物品位置已变化，请重新拖动", "stale 应提示重新拖动，实际「%s」" % _toast_text)
	GameState.inventory[0] = null

# ---- 落点解析（Q5=A）----

func _check_far_point(zone: WorldDropZone, loot_root: Node2D, ground: StubGround) -> void:
	_clear(loot_root)
	GameState.inventory[0] = ItemFactory.make_equip("weapon_iron").duplicate(true)
	# 让桩把 (5000,5000) 原样放行 —— 此时「离玩家 6 格外」才是唯一的拦截理由，
	# 否则这条断言测的就变成桩的可用区域而不是 `DROP_MAX_DISTANCE`。
	var saved := ground.walkable
	ground.walkable = Rect2(0.0, 0.0, 10000.0, 10000.0)
	var res := zone.drop_payload(_payload(0, GameState.inventory[0]), Vector2(5000, 5000))
	ground.walkable = saved
	check(bool(res.get("ok", false)), "远点丢弃应仍成功（落点被纠正，不是拒绝）")
	var node := loot_root.get_child(0) as GroundItem
	check(node != null and node.global_position.is_equal_approx(Vector2(400, 400)),
		"超出 6 格的落点应退回玩家脚边，实际 %s" % (str(node.global_position) if node != null else "无"))
	_clear(loot_root)

func _check_impassable_point(zone: WorldDropZone, loot_root: Node2D, ground: StubGround) -> void:
	_clear(loot_root)
	GameState.inventory[0] = ItemFactory.make_equip("weapon_iron").duplicate(true)
	# (900, 900) 落在可行走矩形外 ⇒ 桩把它换成脚边；这里验的是「我们确实采用了 clamp_to_map 的结果」
	var res := zone.drop_payload(_payload(0, GameState.inventory[0]), Vector2(900, 900))
	check(bool(res.get("ok", false)), "不可走落点应仍成功（退到脚边）")
	var node := loot_root.get_child(0) as GroundItem
	check(node != null and ground.walkable.has_point(node.global_position),
		"不可走落点必须被纠正到可行走区域，实际 %s" % (str(node.global_position) if node != null else "无"))
	_clear(loot_root)

# ---- 堆叠整堆落地（Q4=A）----

func _check_stack_drop(zone: WorldDropZone, loot_root: Node2D) -> void:
	_clear(loot_root)
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 5}
	var res := zone.drop_payload(_payload(0, GameState.inventory[0]), Vector2(500, 500))
	check(bool(res.get("ok", false)), "堆叠药水应可丢弃")
	check(GameState.inventory[0] == null, "整堆丢弃后背包该格应清空")
	var node := loot_root.get_child(0) as GroundItem
	check(node != null and int(node.item.get("count", 0)) == 5, "应整堆落地（count 保持 5）")
	_clear(loot_root)

# ---- Q1=A：丢弃物不被靠近自动拾取 ----

func _check_manual_only(loot_root: Node2D, player: PlayerCharacter) -> void:
	_clear(loot_root)
	GameState.auto_pickup_on = true
	var dropped := _make_ground(loot_root, ItemFactory.make_equip("weapon_iron"), true)
	dropped.global_position = player.global_position + Vector2(10, 0)   # 远小于 96px 拾取半径
	# 1 秒 = 保护期 0.2s 早已过去，足够触发任何自动拾取分支
	for _i in range(60):
		dropped._physics_process(1.0 / 60.0)
	check(not dropped.is_queued_for_deletion() and dropped.is_inside_tree(),
		"manual_only 丢弃物站在 96px 内 1 秒也不能被自动拾回")
	dropped.queue_free()

	# 🔑 反向对照：同一套 tick 下，普通未认领物**必须**被捡走 ——
	# 否则上面那条断言在「自动拾取整体失效」时也会绿。
	var control := _make_ground(loot_root, ItemFactory.make_equip("weapon_iron"), false)
	control.global_position = player.global_position + Vector2(10, 0)
	for _i in range(60):
		control._physics_process(1.0 / 60.0)
	check(control.is_queued_for_deletion() or not control.is_inside_tree(),
		"对照组：普通未认领物在 G 开启时应被靠近拾取（否则本条测试失去判别力）")
	if control.is_inside_tree():
		control.queue_free()
	GameState.auto_pickup_on = false
	_clear(loot_root)

# ---- 点击仍可拾取 ----

func _check_click_pickup(zone: WorldDropZone, loot_root: Node2D) -> void:
	_clear(loot_root)
	var equip := ItemFactory.make_equip("weapon_iron")
	GameState.inventory[0] = equip.duplicate(true)
	zone.drop_payload(_payload(0, GameState.inventory[0]), Vector2(500, 500))
	check(GameState.inventory[0] == null, "前置：丢弃后格子应为空")
	var node := loot_root.get_child(0) as GroundItem
	if node == null:
		check(false, "点击拾取前置：地面应有一件")
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	node._on_click_area_input_event(null, click, 0)
	check(GameState.inventory[0] != null and GameState.inventory[0] == equip,
		"manual_only 只挡自动拾取，点击仍应把原实例收回背包")
	GameState.inventory[0] = null
	_clear(loot_root)

# ---- 极端：loot_root 缺失 ----

func _check_no_loot_root(zone: WorldDropZone, loot_root: Node2D) -> void:
	loot_root.remove_from_group("loot_root")
	var equip := ItemFactory.make_equip("weapon_iron")
	GameState.inventory[0] = equip.duplicate(true)
	_toast_text = ""
	var res := zone.drop_payload(_payload(0, GameState.inventory[0]), Vector2(500, 500))
	check(not bool(res.get("ok", false)) and String(res.get("reason", "")) == "no_ground",
		"地面容器缺失应拒绝丢弃")
	check(GameState.inventory[0] != null, "地面容器缺失时背包必须回滚（不得静默丢件）")
	check(_toast_text == "这里放不下，换个位置再丢", "no_ground 应提示换位置，实际「%s」" % _toast_text)
	GameState.inventory[0] = null
	loot_root.add_to_group("loot_root")

# ---- 工具 ----

## 复刻 `ItemSlot._get_drag_data` 的载荷形状（含 token）。
func _payload(index: int, item: Dictionary) -> Dictionary:
	return {"from": ItemSlot.ROLE_BAG, "index": index, "item": item, "token": Warehouse.item_token(item)}

## 造一件地面物；`manual_only` 与生产入口（`WorldDropZone.drop_payload`）同款取值。
func _make_ground(loot_root: Node2D, item: Dictionary, manual_only: bool) -> GroundItem:
	var node := GROUND_ITEM.instantiate() as GroundItem
	node.item = item
	node.auto_claim = false
	node.persistent = false
	node.manual_only = manual_only
	node.appear_delay = 0.0
	loot_root.add_child(node)
	node.set_physics_process(false)
	return node

## 清空背包与地面（各用例互不污染）。
func _clear(loot_root: Node2D) -> void:
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null
	for child in loot_root.get_children():
		loot_root.remove_child(child)
		child.queue_free()
