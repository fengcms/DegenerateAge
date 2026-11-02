extends Node
## 必须通过tools/run_isolated_probe.py启动；隔离由项目身份强制检查，不能只依赖HOME约定。
## 工程 116：重铸闪退的**分步拆分**探针。
##
## 目的：把「重铸」这一个动作拆成互不重叠的几段，分别单独执行，
## 定位崩溃究竟落在哪一段 —— 而不是继续整段重铸去猜。
##
## 用法（每段单独起进程，必须隔离 HOME）：
##   HOME=/tmp/deg_iso Godot --path . --resolution 1280x1000 \
##       res://tools/SplitProbe.tscn -- <step>
##   step ∈ none | feedback | equip | choices | picker | full
##
## 🔑 为什么必须 `--resolution 1280x1000`：崩溃只在窗口高度 ≥1000 时出现，
##    而玩家是在编辑器 Game 面板里玩的，面板高度超过 1000。默认 1280x800 永远不崩，
##    这正是前几轮「同样操作连打几十次不崩」的原因（假阴性）。

## 隔离身份通过后执行指定步骤的拆分对照。
func _ready() -> void:
	if not DiagnosticProbeGuard.require_isolated(self):
		return
	var argv := OS.get_cmdline_user_args()
	# 🔑 关键变量：不带材料时只点重铸（tries=1）**不崩**；带上 4 件紫装 + 4 枚钻石
	# 如意（tries=17）才崩。所以「是否投料」必须单独可控，否则会把两件事混为一谈。
	var use_materials := "--materials" in argv
	var step := "none"
	for a in argv:
		if not String(a).begins_with("--"):
			step = String(a)
			break
	print("[Split] step=%s materials=%s win=%s" % [step, str(use_materials),
		str(DisplayServer.window_get_size())])
	# 🔴 必须**实测**这个值：改 project.godot 后如果写错段名/键名，Godot 会静默忽略，
	# 于是「调大上限还是不崩不了」会被误读成「容量不是原因」。
	print("[Split] message_queue/max_size_mb=%s" % str(
		ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb", "UNSET")))
	SaveManager.active_slot = -1
	GameState.menu_mode = "world"
	var res: Dictionary = SaveManager.load_into_game(1)
	print("[Split] load ok=%s" % str(res.get("ok", false)))

	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = main
	await get_tree().process_frame
	await get_tree().process_frame

	var panel: Node = main.get_node_or_null("UI/ReforgePanel")
	if panel == null:
		print("[Split] ❌ 无面板")
		get_tree().quit(1)
		return
	panel.set_open(true)
	await get_tree().process_frame

	var choices: Array = panel.get("_choices")
	var picked := -1
	for i in range(choices.size()):
		var row: Dictionary = choices[i]
		if String(row.get("source", "")) == "worn" and String(row.get("key", "")) == "weapon":
			picked = i
			break
	if picked < 0:
		picked = 0
	panel.select_choice(picked)
	await get_tree().process_frame
	await get_tree().process_frame

	if use_materials:
		var filled := 0
		for bag_index in range(GameState.inventory.size()):
			if filled >= 4:
				break
			var candidate: Variant = GameState.inventory[bag_index]
			if not candidate is Dictionary:
				continue
			var it: Dictionary = candidate
			if String(it.get("quality", "")) != "legendary" or bool(it.get("favorite", false)):
				continue
			var target: Dictionary = GameState.equipment.get("weapon", {})
			if not bool(Reforge.can_refine(it, target).get("ok", false)):
				continue
			panel.call("drop_refine_material", filled, bag_index)
			filled += 1
		var auto_runes: Button = panel.get("_auto_runes")
		if auto_runes != null and not auto_runes.disabled:
			auto_runes.pressed.emit()
			await get_tree().process_frame
			await get_tree().process_frame
		print("[Split] 已投材料 %d 件，如意=%s" % [filled, str(panel.get("_rune_choices"))])

	var picker: OptionButton = panel.get("_picker")
	var feedback: Label = panel.get("_feedback")
	var content: Control = panel.get("_content")
	var box: Control = panel.get("_box")
	print("[Split] 命中：候选 %d 条（picker item_count=%d），内容高=%.1f 盒子高=%.1f 视口高=%.1f" % [
		choices.size(), picker.item_count, content.size.y, box.size.y,
		get_viewport().get_visible_rect().size.y])

	match step:
		"none":
			pass
		"feedback":
			# 只复刻「重铸成功后反馈文本由 1 行变 2 行」这一个变化。
			feedback.text = "词条已重铸：攻击 12582 → 防御 24941\n本次是最好的 1 次结果"
			feedback.add_theme_color_override("font_color", PanelChrome.GOLD_LIGHT)
			print("[Split] 已设两行反馈文本 len=%d" % feedback.text.length())
		"equip":
			# 只跑数据层结算，不碰任何 UI 刷新。
			var before: Dictionary = GameState.equipment.get("weapon", {})
			var result: Dictionary = GameState.reforge_equipment("worn", "weapon",
				String(before.get("instanceId", "")), null, [] as Array[String],
				[] as Array[String], ServiceFee.rate_for(panel.get("_portable")),
				["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"] as Array[String])
			print("[Split] reforge_equipment ok=%s tries=%s affixes=%d" % [
				str(result.get("ok", false)), str(result.get("tries", 1)),
				(result.get("affixes", []) as Array).size()])
		"choices":
			panel.call("_refresh_choices")
			print("[Split] _refresh_choices 完成，item_count=%d" % picker.item_count)
		"picker":
			# 只复刻「清空并重建下拉」这一件事，不碰词条行与材料格。
			picker.clear()
			for i in range(choices.size()):
				picker.add_item("项 %d" % i)
			picker.select(0)
			print("[Split] 下拉重建完成 item_count=%d" % picker.item_count)
		"full":
			var trigger: Button = panel.get("_button")
			if trigger != null:
				trigger.pressed.emit()
			else:
				panel.call("_on_reforge")
			print("[Split] 已触发完整重铸")
		"mimic":
			# 🔑 只复刻 `_on_reforge` 成功分支里**与材料相关**的那两件事：
			# 清空 4 个材料格 + 重建候选。不碰 `_feedback` 文本、不碰数据层结算。
			# 用来把「材料清空」与「多一行反馈」这两个变量彻底分开。
			# 🔴 `_refine_selected` 是 `Array[Dictionary]`，用无类型 Array 经 set()
			# 赋值会被**静默拒绝**（值不变，实验等于没做）。
			var emptied: Array[Dictionary] = [{}, {}, {}, {}]
			panel.set("_refine_selected", emptied)
			panel.call("_refresh_choices")
			print("[Split] 已清空材料 + 重建候选，item_count=%d" % picker.item_count)
		"feedback2":
			# 只把反馈文本改成「带材料时」的三行版本，不动材料、不重建候选。
			feedback.text = "已重铸：攻击 1 词条 → 防御 2 词条\n锁定保留\n本次是最好的 17 次结果"
			feedback.add_theme_color_override("font_color", PanelChrome.GOLD_LIGHT)
			print("[Split] 已设三行反馈 len=%d" % feedback.text.length())
		_:
			print("[Split] ❌ 未知 step")

	print("[Split] >>> 进入观察窗口（12s），崩溃会在这里发生")
	for i in range(30):
		await get_tree().create_timer(0.4).timeout
		if i % 8 == 0:
			print("[Split] 存活 %.1fs frame=%d 内容高=%.1f 反馈=%d" % [
				i * 0.4, Engine.get_process_frames(), content.size.y,
				feedback.text.length()])
	print("[Split] === 未崩溃 step=%s ===" % step)
	get_tree().quit(0)
