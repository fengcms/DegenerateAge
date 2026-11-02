extends Node
## 必须通过tools/run_isolated_probe.py启动；隔离由项目身份强制检查，不能只依赖HOME约定。
## 工程 116：重铸闪退复现探针（**只读复现，不写入任何真实存档**）。
##
## 用途：在隔离的 user:// 下加载指定槽位，真实打开重铸面板，**按玩家操作顺序**
## 投满 4 件紫装 + 4 枚钻石如意，再点重铸，观察是否复现 SIGSEGV。
##
## 运行（**必须**带隔离 HOME，否则会读写玩家真实存档）：
##   HOME=/tmp/deg_iso Godot --path . res://tools/ReforgeCrashProbe.tscn
##
## 窗口模式用于复核真实绘制路径；无头只能验证逻辑与调度，不能替代视觉验收。
## 🔴 为什么必须隔离：`--headless` 启动时 `SaveManager` 仍会读 `last_slot` 并在退出回写
## （工程 114 已踩过一次，直接覆盖了玩家主档）。见 MEMORY 坑 106。

## 重铸次数。玩家实测是**每一段会话第一次重铸就崩**，所以默认只打 2 次足够判定。
const ATTEMPTS := 2

## 每次重铸后继续渲染的时长（秒）。崩溃发生在按钮回调返回**之后**，必须留足观察窗口。
const WATCH_SECONDS := 4.0

## 覆盖内嵌子窗口路径；第三轮已确认独立窗口也可触发布局自激，内嵌并非必要条件。
const EMBED_SUBWINDOWS := true

## 四枚钻石如意 ⇒ `tries = 17`（工程 112 封顶），覆盖抽样取优全路径。
const RUNE_ID := "rune_diamond"
const RUNE_SLOTS := 4

## 精炼材料：本作「紫」= `legendary`（门槛写 `epic` 会错降一档且零报错）。
const REFINE_SLOTS := 4
const REFINE_QUALITY := "legendary"

func _ready() -> void:
	if not DiagnosticProbeGuard.require_isolated(self):
		return
	print("[Probe] === 重铸崩溃复现开始（headless=%s）===" % DisplayServer.get_name())
	# 必须在建任何窗口之前切换：运行期若已有子窗口在显示，引擎会拒绝修改并报
	# 「Can't change "gui_embed_subwindows" while a child window is displayed」。
	get_tree().root.gui_embed_subwindows = EMBED_SUBWINDOWS
	print("[Probe] gui_embed_subwindows=%s" % str(get_tree().root.gui_embed_subwindows))
	# 关掉自动读档，避免 Main 的 deferred 初始化把场景重载掉。
	SaveManager.active_slot = -1
	GameState.menu_mode = "world"

	# 🔑 先读档再建场景 —— 与真实流程同序（读档 → 重载场景 → 场景按新状态构建）。
	var res: Dictionary = SaveManager.load_into_game(1)
	print("[Probe] load_into_game ok=%s reason=%s" % [res.get("ok", false), String(res.get("reason", ""))])

	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	# `_ready` 期间根节点正在装配子节点，直接 add_child 会被引擎拒绝（"parent node is busy"），
	# 必须 deferred 等到本轮装配结束。
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = main
	await get_tree().process_frame
	await get_tree().process_frame

	var weapon: Dictionary = GameState.equipment.get("weapon", {})
	if weapon.is_empty():
		print("[Probe] ❌ 没有穿戴武器，终止")
		get_tree().quit(1)
		return
	print("[Probe] 武器 instanceId=%s affixes=%d pct=%d" % [
		String(weapon.get("instanceId", "")),
		(weapon.get("affixes", []) as Array).size(),
		(weapon.get("pctAttrs", []) as Array).size()])

	var panel: Node = main.get_node_or_null("UI/ReforgePanel")
	if panel == null:
		print("[Probe] ❌ 找不到重铸面板")
		get_tree().quit(1)
		return
	panel.set_open(true)
	await get_tree().process_frame

	var picked := -1
	var choices: Array = panel.get("_choices")
	for i in range(choices.size()):
		var row: Dictionary = choices[i]
		if String(row.get("source", "")) == "worn" and String(row.get("key", "")) == "weapon":
			picked = i
			break
	if picked < 0:
		print("[Probe] ❌ 候选里没有穿戴中的武器（候选 %d 条）" % choices.size())
		get_tree().quit(1)
		return
	panel.select_choice(picked)
	await get_tree().process_frame

	# --- 玩家操作第一步：投 4 件紫装（本作「紫」= legendary）---
	var filled := 0
	for bag_index in range(GameState.inventory.size()):
		if filled >= REFINE_SLOTS:
			break
		var candidate: Variant = GameState.inventory[bag_index]
		if not candidate is Dictionary:
			continue
		var item: Dictionary = candidate
		if String(item.get("quality", "")) != REFINE_QUALITY:
			continue
		if bool(item.get("favorite", false)):
			continue
		var guard: Dictionary = Reforge.can_refine(item, _current_target(panel))
		if not bool(guard.get("ok", false)):
			continue
		panel.call("drop_refine_material", filled, bag_index)
		filled += 1
	print("[Probe] 已投入精炼材料 %d 件（要求 %d 件）" % [filled, REFINE_SLOTS])

	# --- 玩家操作第二步：按「如意」按钮（不是直接塞值）---
	# 🔴 必须走真实按钮：`_on_auto_runes()` 里是 `RuneCharge.best_available()`，
	# 直接塞 `_rune_choices` 会绕过它，等于换了一条代码路径（且不产生按钮的焦点/悬停态）。
	var auto_runes: Button = panel.get("_auto_runes")
	if auto_runes != null and not auto_runes.disabled:
		Input.warp_mouse(auto_runes.get_global_rect().get_center())
		await get_tree().create_timer(0.8).timeout
		auto_runes.grab_focus()
		auto_runes.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
	print("[Probe] 点如意后 rune_choices=%s（如意按钮 disabled=%s）" % [
		str(panel.get("_rune_choices")), str(auto_runes.disabled) if auto_runes != null else "?"])

	print("[Probe] 候选 %d 条，选中 index=%d，材料 %d 件，如意 %s" % [
		choices.size(), picked, (panel.call("refine_materials") as Array).size(),
		str(panel.get("_rune_choices"))])

	# --- 玩家操作细节：鼠标停在按钮上，会弹出 tooltip ---
	# 真实玩家点完「如意」再点「重铸」，全程鼠标都压在控件上，于是引擎会挂一个
	# tooltip 弹窗。而重铸成功会 `_refresh_choices()`（clear + 重建 147 项）并把
	# `_button.tooltip_text` 清空 —— 正在显示的 tooltip 若指向被清掉/换掉的控件，
	# 就是最典型的「渲染时访问已释放对象」。
	#
	# 🔴 `Input.warp_mouse()` 靠不住：后台窗口没有焦点时 macOS 根本不派发 mouse move，
	# 于是 hover 从未建立、tooltip 从未弹出 —— 前几次「同样操作不崩」很可能是这个假阴性。
	# 改为直接 `Input.parse_input_event()` 注入 mouse motion，走完整的 Viewport GUI 分发。
	var trigger: Button = panel.get("_button")
	if trigger != null:
		for _k in range(3):
			_hover(trigger)
			await get_tree().create_timer(0.6).timeout
		print("[Probe] 悬停 1.8s 后：可见子窗口 %s | 按钮 tooltip=%s" % [
			str(_visible_windows()), str(trigger.tooltip_text).left(30)])

	# --- 玩家操作第三步：点重铸（真实按钮信号 + 焦点）---
	for i in range(ATTEMPTS):
		print("[Probe] >>> 第 %d 次点重铸（材料 %d 件）" % [
			i, (panel.call("refine_materials") as Array).size()])
		if trigger != null:
			trigger.grab_focus()
			trigger.pressed.emit()
		else:
			panel.call("_on_reforge")
		# 🔑 玩家是「点完按钮停在那里」，崩溃发生在之后 0.5 秒内（下一帧重绘 / 布局重算 /
		# 自动存档去抖到期），不是同一个函数栈里。所以这里必须**继续渲染若干秒**，
		# 只等两帧等于刚好在崩溃之前退出，会得出「不复现」的假结论。
		var elapsed := 0.0
		while elapsed < WATCH_SECONDS:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		var after: Dictionary = GameState.equipment.get("weapon", {})
		var feedback: Label = panel.get("_feedback")
		print("[Probe] #%d 存活 %.1fs frame=%d affixes=%d feedback_len=%d 可见窗=%s" % [
			i, elapsed, Engine.get_process_frames(),
			(after.get("affixes", []) as Array).size(),
			feedback.text.length() if feedback != null else -1,
			str(_visible_windows())])

	print("[Probe] === 未崩溃，%d 次重铸全部完成 ===" % ATTEMPTS)
	get_tree().quit(0)

## 注入一次真实的鼠标移动，让引擎走完整的 hover / tooltip 判定。
## 🔴 不要用 `Input.warp_mouse()`：后台窗口无焦点时 macOS 不派发 mouse move（已踩）。
func _hover(control: Control) -> void:
	var at: Vector2 = control.get_screen_position() + control.size * 0.5
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)

## 收集当前可见的、非主窗口的 Window（tooltip 是 PopupPanel，内嵌模式下也挂在这里）。
## 用来确认「tooltip 到底有没有弹出来」—— 没弹出来的话，悬停实验等于没做。
func _visible_windows() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if child is Window and child != get_tree().root and (child as Window).visible:
				out.append(String(child.name))
			stack.append(child)
	return out

## 面板当前选中的目标件（`_selected_item()` 是私有的读法，走同一个口径）。
func _current_target(panel: Node) -> Dictionary:
	var picked := int(panel.get("_picker").selected)
	var choices: Array = panel.get("_choices")
	if picked < 0 or picked >= choices.size():
		return {}
	var choice: Dictionary = choices[picked]
	var candidate: Variant = GameState.inventory[choice.key] if choice.source == "bag" \
		else GameState.equipment.get(choice.key)
	return candidate if candidate is Dictionary else {}
