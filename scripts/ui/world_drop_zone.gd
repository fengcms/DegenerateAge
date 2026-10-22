class_name WorldDropZone
extends Control
## 世界投放区（工程 89 / 产品 05 §5.8「拖到地面丢弃」）。
##
## **为什么需要它**：Godot 的拖放（`_can_drop_data` / `_drop_data`）只由**鼠标正下方的 Control**
## 接收。鼠标移出面板后下面是世界（Node2D），没有任何 Control ⇒ 引擎直接判「取消拖拽」，
## 调用方连一次回调都收不到 —— 「扔在空地上」这件事根本无从发生。故补一块全屏接收层。
##
## 三条硬约束：
##   ① **常态不拦点击**：平时 `mouse_filter = IGNORE`，否则点地走路 / 点怪会被整块吃掉；
##   ② **仅拖拽期接管**：`gui_is_dragging()` 为真且载荷来自背包时切 `STOP`，松手当帧切回；
##   ③ **树序在所有面板之前**：面板格（背包格 / 出售托盘 / 合成材料格）`STOP` 优先命中，
##      拖到面板上仍然交给面板，只有面板外的空地才落到这里（`Main.tscn` 里它是最前面的 UI 子节点）。
##
## 🔴 `_can_drop_data` **不判「能不能丢」**：判 false 时引擎连 `_drop_data` 都不调，
## 玩家就永远听不到「任务物品不能丢弃」这类原因。这里一律放行，落地时再拒、用 toast 说清楚。
##
## 落点口径与 `game.gd` 的 `request_map_move` 同源：视口鼠标坐标 → 地面节点的 canvas 变换反算。

const GROUND_ITEM := preload("res://scenes/entities/GroundItem.tscn")

## 提示条在屏幕底部抬起的高度（px，逻辑坐标）—— 压在快捷栏之上，不挡血条。
const HINT_BOTTOM_OFFSET := 150.0
const HINT_HEIGHT := 22.0

var _hint: Label

func _ready() -> void:
	add_to_group("world_drop_zone")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hint()
	resized.connect(_layout_hint)
	_layout_hint()

## 每帧对齐一次投放开关。**不能只在拖拽开始/结束时切换**：一次漏切就会让整块全屏
## Control 变成常驻鼠标拦截器（点地走路、点怪、点 NPC 全部失灵），而这个 bug 只在
## 「拖过一次」之后出现，很难从现象反推。故按帧对齐、值相同不赋值。
func _process(_delta: float) -> void:
	var payload := current_payload()
	_sync_filter(not payload.is_empty())
	_sync_hint(not payload.is_empty())

## 当前拖拽载荷（仅背包格发起时非空）。
func current_payload() -> Dictionary:
	var vp := get_viewport()
	if vp == null or not vp.gui_is_dragging():
		return {}
	var data: Variant = vp.gui_get_drag_data()
	if not (data is Dictionary):
		return {}
	var payload := data as Dictionary
	if int(payload.get("from", -1)) != ItemSlot.ROLE_BAG:
		return {}
	if not (payload.get("item") is Dictionary):
		return {}
	return payload

func _sync_filter(dragging: bool) -> void:
	var want: int = Control.MOUSE_FILTER_STOP if dragging else Control.MOUSE_FILTER_IGNORE
	if int(mouse_filter) != want:
		mouse_filter = want

func _sync_hint(show_hint: bool) -> void:
	if _hint == null or _hint.visible == show_hint:
		return
	_hint.visible = show_hint

# ---- 拖放接收 ----

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	return int((data as Dictionary).get("from", -1)) == ItemSlot.ROLE_BAG

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	drop_payload(data as Dictionary, world_point_at_mouse())

## 执行一次丢弃。**拆成公开方法**是为了让测试能传入确定的落点 ——
## 无头下鼠标坐标与 canvas 变换都不可信，硬走 `world_point_at_mouse()` 只能测出 0,0。
func drop_payload(data: Dictionary, world_point: Vector2) -> Dictionary:
	var payload_item: Dictionary = data.get("item", {}) if data.get("item") is Dictionary else {}
	# 🔴 **先建节点、再动背包**：场景缺失这类失败必须发生在取出物品之前，
	# 否则就是「背包空了、地上也没有」（R1）。
	var node := GROUND_ITEM.instantiate() as GroundItem
	if node == null:
		return _fail("no_ground", ItemUtil.display_name(payload_item))
	var res := GameState.drop_item_to_ground(
		int(data.get("index", -1)), String(data.get("token", "")), world_point)
	if not bool(res.get("ok", false)):
		node.free()
		# 失败时 `drop_item_to_ground` 不回 item（一件都没动），名称用载荷里的那份。
		return _fail(String(res.get("reason", "")), ItemUtil.display_name(payload_item))
	var item: Dictionary = res.get("item", {}) as Dictionary
	# 🔴 落点必须用 `GameState` 解析后的那一份（`_resolve_drop_point`：夹进地图 + 不可走退脚边 +
	# 超 6 格退脚边）。这里若图省事直接用传入的 `world_point`，上面三条兜底等于没写。
	var point: Vector2 = res.get("point", world_point)
	node.item = item
	node.auto_claim = false      # 玩家丢弃物：不「生成即认领」
	node.persistent = false      # Q3=A：60 秒淡出，不登记未领取战利品、不落档
	node.manual_only = true      # Q1=A：只能点击拾取，不被靠近自动拾取 / 顺路拾取捡回
	node.appear_delay = 0.0      # 松手即出现，不走掉落错峰
	var layer := get_tree().get_first_node_in_group("loot_root") as Node2D
	if layer == null:
		# GameState 进门时确认过容器存在；走到这里说明期间切图了。
		# 宁可放回背包，也不能让物品凭空消失。
		node.free()
		GameState.add_item(item)
		return _fail("no_ground", ItemUtil.display_name(item))
	node.position = layer.to_local(point)
	layer.add_child(node)
	EventBus.toast_requested.emit(
		Localization.tr_key("msg.drop_to_ground.p001") % [
			ItemUtil.display_name(item), int(GroundItem.LIFETIME)], "pickup")
	return {"ok": true, "reason": "", "item": item, "point": point, "node": node}

# ---- 坐标换算 ----

## 视口鼠标坐标 → 世界坐标（与 `game.gd` L415 同源：地面节点的 canvas 变换反算）。
func world_point_at_mouse() -> Vector2:
	return world_point_from_screen(get_viewport().get_mouse_position())

func world_point_from_screen(screen: Vector2) -> Vector2:
	var ground := get_tree().get_first_node_in_group("map_ground") as Node2D
	if ground == null:
		return Vector2.ZERO
	var in_ground: Vector2 = ground.get_global_transform_with_canvas().affine_inverse() * screen
	return ground.to_global(in_ground)

# ---- 文案 ----

func _fail(reason: String, item_name: String) -> Dictionary:
	var text := ""
	match reason:
		"quest_item":
			text = Localization.tr_key("msg.drop_to_ground.p002") % item_name
		"favorite":
			text = Localization.tr_key("msg.drop_to_ground.p003") % item_name
		"tool":
			text = Localization.tr_key("msg.drop_to_ground.p004") % item_name
		"stale":
			text = Localization.tr_key("msg.drop_to_ground.p005")
		"no_ground":
			text = Localization.tr_key("msg.drop_to_ground.p006")
		_:
			text = Localization.tr_key("msg.drop_to_ground.p007")
	EventBus.toast_requested.emit(text, "danger")
	return {"ok": false, "reason": reason}

# ---- 提示条 ----

func _build_hint() -> void:
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = Localization.tr_key("ui.drop_zone.hint")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.93, 0.89, 0.78, 0.95))
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.07, 0.9))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.visible = false
	add_child(_hint)

func _layout_hint() -> void:
	if _hint == null:
		return
	_hint.size = Vector2(size.x, HINT_HEIGHT)
	_hint.position = Vector2(0.0, size.y - HINT_BOTTOM_OFFSET)

## 供测试断言：投放区当前是否处于「接管鼠标」状态。
func is_armed() -> bool:
	return int(mouse_filter) == Control.MOUSE_FILTER_STOP
