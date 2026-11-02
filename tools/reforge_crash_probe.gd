extends Node
## 工程 116：重铸闪退复现探针（**只读复现，不写入任何真实存档**）。
##
## 用途：在隔离的 user:// 下加载指定槽位，真实打开重铸面板并连续重铸武器，
## 观察是否复现 SIGSEGV。它是崩溃取证工具，不是平衡探针，不进默认测试集。
##
## 运行（**必须**带隔离 HOME，否则会读写玩家真实存档）：
##   HOME=/tmp/deg_iso Godot --path . res://tools/ReforgeCrashProbe.tscn
##   HOME=/tmp/deg_iso Godot --headless --path . res://tools/ReforgeCrashProbe.tscn
##
## 🔴 为什么必须隔离：`--headless` 启动时 `SaveManager` 仍会读 `last_slot` 并在退出回写
## （工程 114 已踩过一次，直接覆盖了玩家主档）。见 MEMORY 坑 106。
## 🔴 headless 不出渲染，只测数据层；要复现渲染层崩溃必须**窗口模式**。

## 重铸次数。默认 24 次覆盖「首次解锁第五词条」与「已解锁后重掷」两段路径。
const ATTEMPTS := 24

## 四枚钻石如意 ⇒ `tries = 17`（工程 112 封顶），覆盖抽样取优全路径。
const RUNE_ID := "rune_diamond"
const RUNE_SLOTS := 4

func _ready() -> void:
	print("[Probe] === 重铸崩溃复现开始（headless=%s）===" % DisplayServer.get_name())
	# 关掉自动读档，避免 Main 的 deferred 初始化把场景重载掉。
	SaveManager.active_slot = -1
	GameState.menu_mode = "world"

	# 🔑 先读档再建场景 —— 与真实流程同序（读档 → 重载场景 → 场景按新状态构建）。
	# 反过来会让 Game 先按默认地图建世界，制造平台差异。
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
	var instance_id := String(weapon.get("instanceId", ""))
	print("[Probe] 武器 instanceId=%s tier=%s affixes=%d pct=%d" % [
		instance_id, weapon.get("reforgeAffixTier", 0),
		(weapon.get("affixes", []) as Array).size(),
		(weapon.get("pctAttrs", []) as Array).size()])

	# 真实路径：打开面板 → 选中穿戴中的武器 → 投满四枚钻石如意。
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
	var rune_choices: Array = []
	for _i in range(RUNE_SLOTS):
		rune_choices.append(RUNE_ID)
	panel.set("_rune_choices", rune_choices)
	panel.call("_refresh_runes")
	await get_tree().process_frame
	print("[Probe] 面板已打开，候选 %d 条，选中 index=%d" % [choices.size(), picked])

	for i in range(ATTEMPTS):
		var current: Dictionary = GameState.equipment.get("weapon", {})
		var tier_before: Variant = current.get("reforgeAffixTier", 0)
		panel.call("_on_reforge")
		# 两帧：一帧让信号回调与重排落地，一帧让 `_draw` 真正执行。
		await get_tree().process_frame
		await get_tree().process_frame
		var after: Dictionary = GameState.equipment.get("weapon", {})
		var feedback: Label = panel.get("_feedback")
		print("[Probe] #%d tier_before=%s tier_after=%s affixes=%d pct=%d feedback_len=%d" % [
			i, tier_before, after.get("reforgeAffixTier", 0),
			(after.get("affixes", []) as Array).size(),
			(after.get("pctAttrs", []) as Array).size(),
			feedback.text.length() if feedback != null else -1])

	print("[Probe] === 未崩溃，%d 次重铸全部完成 ===" % ATTEMPTS)
	get_tree().quit(0)
