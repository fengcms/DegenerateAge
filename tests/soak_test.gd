extends Node
## 长时稳定性压测（M1 出口「连续游玩 ≥ 10 分钟不崩不卡」乙方案；开发期工具，M5 移除）。
##
## 运行：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   # 无头长跑（默认 600s / 10 分钟，静默压测）
##   "$GODOT" --headless --path . res://tests/SoakTest.tscn
##   # 开窗短跑（额外采真实帧率；勿与长跑同时进行）
##   "$GODOT" --path . res://tests/SoakTest.tscn -- --soak=120
##   # 快速自检（30 秒，用于验证脚本本身）
##   "$GODOT" --headless --path . res://tests/SoakTest.tscn -- --soak=30 --interval=3
##
## 参数（`--` 之后）：--soak=秒数（默认 600）｜--interval=秒数（默认 5）｜--no-ui-stress
##
## 压测内容（真实主场景 Main.tscn，不是 Game.tscn——后者没有 UI 层）：
##   · 自动战斗 + 自动拾取**常开**，持续刷怪 / 掉落 / 认领 / 飞行 / 升级 / 结算
##   · 每 interval 秒采样：帧率 / 节点数 / 对象数 / **孤儿节点** / 静态内存 / 场上怪物与
##     **留地掉落物**（工程文档 10 起：怪物掉落生成即认领并脱离 ground_items 组，
##     故该采样通常为 0；>0 表示「背包满留地」等**未认领**物）/ 累计击杀 / 等级 / 金币 /
##     背包占用 / 自动战斗状态
##   · 每 60s 一次交互脉冲：开关背包面板、开关存档面板、0.6s 手动移动接管（压 UI 与 4.6 分支）、
##     清空场上怪物 4s（观察兜底的「搜索掉落 → 顺路拾取」路径——仅在存在未认领留地物时触发）、
##     把留地掉落物扫进背包（兜底：背包满时掉落物会留地待清，否则会单调堆积掩盖泄漏信号）、
##     背包接近满时模拟回城卖装备；M3 增加营地↔试炼野外往返切图脉冲
##   · 低血注水：HP < 50% 时补满（压测角色**不带药水**，故 M2.5 的自动喝药不会触发；
##     且 Q5 已取消「低血停战」，若不注水角色会一直战斗到死，破坏持续负载）——
##     属压测注水，只为保证持续负载，报告中单独计数说明
##
## 判定：孤儿节点恒为 0 ／ 有真实负载（击杀 > 0）／ 节点数与对象数无单调漂移 ／
##       背包无重复实例 ／ 背包占用不越界 ／ 采样间隔正常（主线程未卡住）
##
## ⚠ 会写 3 号槽（顺带压测自动存路径）：开始前快照整个 saves 目录，结束后**原样还原**。

const SOAK_SLOT := 3
const STRESS_EVERY := 60.0        # 交互脉冲间隔（秒）
const BAG_CLEAN_THRESHOLD := 30   # 背包占用达到此值 → 模拟回城卖装备
const DEBUG_WEAPON_ID := "debug_blade_overpower"   # 不卖开发期测试武器
const START_LEVEL := 5            # 起步等级（与 4.4 成长公式一致：攻 +2 / 防 +1 每级）

const REPORT_MD := "/tmp/degenerateage_soak_report.md"
const REPORT_JSON := "/tmp/degenerateage_soak_samples.json"
const BACKUP_DIR := "/tmp/ea_soak_save_backup/"

var _seconds := 600.0
var _interval := 5.0
var _ui_stress := true
var _headless := true

var _main: Node = null
var _game: Node = null
var _player: PlayerCharacter = null
var _pilot: AutoBattle = null

var _samples: Array = []
var _kills := 0
var _levels := 0
var _xp_gained := 0
var _heals := 0
var _deaths := 0
var _sold := 0
var _gold_sold := 0
var _swept_items := 0
var _swept_gold := 0
var _loot_paths := 0
var _duplicate_ids := 0
var _bg_samples := 0
var _max_gap := 0.0
var _gap_overruns := 0
var _last_frames := 0
var _stress_count := 0
var _travel_count := 0
var _travel_subsidy := 0

var _failures: Array[String] = []
var _save_snapshot: Dictionary = {}
var _prev_active := -1

func _ready() -> void:
	_parse_args()
	_headless = DisplayServer.get_name() == "headless"
	print("=".repeat(64))
	print("[Soak] 长时稳定性压测：%s 模式 · 时长 %.0fs · 采样间隔 %.0fs · 交互脉冲 %s" % [
		"无头" if _headless else "开窗", _seconds, _interval,
		"开" if _ui_stress else "关"])
	print("[Soak] 报告将写入：%s" % REPORT_MD)
	print("=".repeat(64))

	# 0) 现场保护：快照整个 saves 目录（含 last_slot.json 与各槽的 .bak/.tmp/.corrupt）
	_save_snapshot = _snapshot_saves()
	_prev_active = SaveManager.active_slot
	# 本工具**主动压测自动存路径**（写 3 号槽），且已快照 / 还原整个存档目录 → 显式放开。
	# 其余 tests/ 工具默认被 SaveManager 自动存的「测试场景闸门」挡住，不会写坏玩家存档。
	SaveManager.autosave_in_tests = true

	# 1) 起步角色：L5（与 4.4 成长一致），保证长跑期间持续作战
	GameState.reset_to_defaults()
	GameState.player.level = START_LEVEL
	GameState.player.attack = 12 + 2 * (START_LEVEL - 1)
	GameState.player.defense = 5 + 1 * (START_LEVEL - 1)
	GameState.player.xp = 0
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()

	# 2) 真实主场景（含 UI 层）
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	for _i in range(20):
		await get_tree().process_frame

	# 开窗模式：主动抢前台 —— 3.14⑥「应用失去焦点 → 停决策」会让自动战斗一直显示
	# 「暂停中」，窗口留在后台时压测根本跑不出负载（无头模式没有窗口，不受影响）。
	if not _headless:
		get_window().move_to_foreground()
		await get_tree().process_frame

	_game = _main.get_node_or_null("Game")
	if _game == null:
		_fail("主场景缺少 Game 节点")
		_finish()
		return
	_player = _game.get_node_or_null("Entities/Player") as PlayerCharacter
	if _player == null:
		_fail("主场景缺少 Player 节点")
		_finish()
		return
	_pilot = _game.call("auto_pilot") as AutoBattle
	if _pilot == null:
		_fail("Player 下未挂 AutoPilot（M1-9）")
		_finish()
		return

	# 3) 顺带压测存档路径：活动槽 = 3（结束后整体还原）
	SaveManager.set_active_slot(SOAK_SLOT)
	SaveManager.save_slot(SOAK_SLOT, true)

	# 4) 常开自动战斗 / 自动拾取（3.14 / 9.9）
	GameState.set_auto_battle(true)
	GameState.set_auto_pickup(true)

	# 5) 事件计数
	EventBus.monster_died.connect(_on_monster_died)
	EventBus.player_leveled.connect(_on_player_leveled)
	EventBus.xp_gained.connect(func(n: int) -> void: _xp_gained += n)

	await _run()

	_evaluate()
	_write_reports()
	_restore_saves()
	SaveManager.active_slot = _prev_active
	GameState.reset_to_defaults()
	_finish()

# ---- 主循环 ----

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var last_ms := t0
	var next_stress_at := STRESS_EVERY
	_last_frames = Engine.get_process_frames()

	while true:
		await get_tree().create_timer(_interval).timeout
		var now_ms := Time.get_ticks_msec()
		var gap := float(now_ms - last_ms) / 1000.0
		last_ms = now_ms
		var elapsed := float(now_ms - t0) / 1000.0

		# 卡顿检测：采样等待明显超出设定间隔 → 主线程被阻塞过
		if gap > _max_gap:
			_max_gap = gap
		if gap > _interval * 1.5:
			_gap_overruns += 1
			print("[Soak] ⚠ t=%.1fs 采样间隔 %.2fs（> %.2fs，疑似卡顿）" % [
				elapsed, gap, _interval * 1.5])

		_guard_hp()
		_sample(elapsed, gap)

		if elapsed >= _seconds:
			break
		if _ui_stress and elapsed >= next_stress_at:
			await _stress_pulse()
			next_stress_at = elapsed + STRESS_EVERY
			# 脉冲耗时不计入卡顿判定
			last_ms = Time.get_ticks_msec()

# ---- 采样 ----

func _sample(elapsed: float, gap: float) -> void:
	var frames := Engine.get_process_frames()
	var fps := float(frames - _last_frames) / maxf(0.001, gap)
	_last_frames = frames

	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var orphan := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var mem_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	var drops := get_tree().get_nodes_in_group("ground_items").size()
	var state := AutoBattle.state_name(_pilot.current_state()) if _pilot != null else "-"
	# 3.14 ⑥：应用失去焦点 → 自动战斗停决策（状态显示「暂停中」）。
	# 观测这个标志，避免把「窗口没在前台」误读成「状态机卡死 / 卡顿」。
	var bg := false
	if _pilot != null:
		bg = bool(_pilot.get("_background"))
	if bg:
		_bg_samples += 1

	var s := {
		"t": elapsed, "fps": fps, "gap": gap, "nodes": nodes, "objects": objects,
		"orphan": orphan, "memMB": mem_mb, "enemies": enemies, "drops": drops,
		"kills": _kills, "level": int(GameState.player.level), "gold": GameState.gold,
		"bag": GameState.inventory_used(), "state": state, "bg": bg,
	}
	_samples.append(s)
	_check_inventory()
	print("[Soak] t=%6.1fs fps=%6.0f gap=%.2fs 节点=%5d 对象=%6d 孤儿=%d 内存=%4.0fMB 怪=%2d 留地=%3d 击杀=%3d Lv%2d 金=%7d 包=%2d %s%s" % [
		elapsed, fps, gap, nodes, objects, orphan, mem_mb, enemies, drops,
		_kills, int(GameState.player.level), GameState.gold,
		GameState.inventory_used(), state,
		"（窗口失焦，按 3.14⑥ 停决策）" if bg else ""])

## HP 守卫：压测角色不带药水 → M2.5 自动喝药不触发；Q5 已取消「低血停战」，
## 不注水会一直战斗到死 → 仍需低血注水保证持续负载。死亡则记一次并满血复活。
func _guard_hp() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var mx := GameState.max_hp()
	var hp := int(GameState.player.hp)
	if hp <= 0:
		_deaths += 1
		GameState.player.hp = mx
		EventBus.player_hp_changed.emit(mx, mx)
		print("[Soak] ⚠ 玩家 HP 归零（第 %d 次）→ 满血复活（M1 无死亡处理）" % _deaths)
		return
	if float(hp) / float(maxi(1, mx)) < 0.5:
		GameState.heal_player(mx)
		_heals += 1

## 背包实例查重（复制 bug 探测）+ 占用越界检查。
func _check_inventory() -> void:
	var seen := {}
	for it in GameState.inventory:
		if not (it is Dictionary) or (it as Dictionary).is_empty():
			continue
		var iid := String((it as Dictionary).get("instanceId", ""))
		if iid.is_empty():
			continue
		if seen.has(iid):
			_duplicate_ids += 1
			if _duplicate_ids <= 3:
				print("[Soak] ⚠ 背包出现重复实例 ID：%s" % iid)
		seen[iid] = true

# ---- 交互脉冲（UI / 手动接管 / 后勤）----

func _stress_pulse() -> void:
	_stress_count += 1
	var tag := "脉冲#%d" % _stress_count
	var inv_panel := _main.get_node_or_null("UI/InventoryPanel")
	var save_panel := _main.get_node_or_null("UI/SavePanel")
	var opened := 0

	# ① 面板开合（压 UI 构建 / 销毁与面板互斥，9.2）
	if inv_panel != null and inv_panel.has_method("set_open"):
		inv_panel.set_open(true)
		await get_tree().process_frame
		await get_tree().process_frame
		inv_panel.set_open(false)
		await get_tree().process_frame
		opened += 1

	if save_panel != null and save_panel.has_method("set_open"):
		save_panel.set_open(true)
		for _i in range(4):
			await get_tree().process_frame
		save_panel.set_open(false)
		await get_tree().process_frame
		opened += 1

	# ② 手动接管（4.6）：按下方向键 → 应转「手动接管」→ 松开后恢复
	if _player != null:
		Input.action_press("move_down")
		await get_tree().create_timer(0.6).timeout
		Input.action_release("move_down")
		await get_tree().process_frame

	# ③ 清场：模拟玩家打空一片区域 → 观察自动战斗是否进入「顺路拾取」路径（3.14 / 9.9）
	#    怪物点会在 respawnTime 后自动重生，压测负载不受影响（7.9）。
	var cleared := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Monster:
			n.queue_free()
			cleared += 1
	var loot_seen := false
	for _i in range(240):                      # ≈4s
		await get_tree().physics_frame
		if _pilot != null and _pilot.current_state() == AutoBattle.State.PATH_TO_LOOT:
			loot_seen = true
	if loot_seen:
		_loot_paths += 1

	# ④ 后勤：先把背包里的装备卖掉（模拟回城清包）→ 再把剩余掉落物扫进背包
	#    （自动拾取只覆盖「顺路」范围，长期压测需模拟玩家主动拾取，否则掉落物会
	#      因持续刷怪而单调堆积——那是设计行为，会掩盖真正的节点泄漏信号）
	var cleaned := 0
	if GameState.inventory_used() >= BAG_CLEAN_THRESHOLD:
		cleaned = _clean_bag()
	var swept := _sweep_drops()
	# ⑤ M3 切图生命周期脉冲：往返后仍回原地图，便于稳定性样本横向比较。
	await _travel_round_trip()

	print("[Soak] %s：面板开合 %d · 清场 %d 怪 · 顺路拾取 %s · 扫入 %d 件(+%d 金) · 卖 %d 件 · 切图累计 %d 次 · 背包 %d 格" % [
		tag, opened, cleared, "√" if loot_seen else "×",
		int(swept.get("took", 0)), int(swept.get("gold", 0)), cleaned, _travel_count,
		GameState.inventory_used()])

func _travel_round_trip() -> void:
	if GameState.current_map != "camp":
		_fail("切图脉冲起点应为营地，实际 %s" % GameState.current_map)
		return
	if not await _travel_once("wild_trial"):
		return
	var fare := MapService.fee_to("camp")
	if GameState.gold < fare:
		var subsidy := fare - GameState.gold
		GameState.add_gold(subsidy)
		_travel_subsidy += subsidy
	await _travel_once("camp")

func _travel_once(map_id: String) -> bool:
	var result := MapService.travel_to(map_id)
	if not bool(result.get("ok", false)):
		_fail("切图脉冲前往 %s 失败：%s" % [map_id, result.get("reason", "")])
		return false
	var old_main: WeakRef = weakref(_main)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if old_main.get_ref() != null:
		_fail("切图脉冲旧世界未释放")
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	_game = _main.get_node_or_null("Game")
	_player = _game.get_node_or_null("Entities/Player") as PlayerCharacter if _game != null else null
	_pilot = _player.get_node_or_null("AutoPilot") as AutoBattle if _player != null else null
	if _game == null or _player == null or _pilot == null:
		_fail("切图脉冲新世界缺少 Game / Player / AutoPilot")
		return false
	if GameState.current_map != map_id or _game.get_node("Ground").map_id != map_id:
		_fail("切图脉冲未装载目标地图 %s" % map_id)
		return false
	_travel_count += 1
	return true

## 把**未认领**的留地掉落物扫进背包 / 金币入账（兜底；9.9）。
## 工程文档 10 起怪物掉落生成即认领，本路径主要服务「背包满留地」遗留物；
## 背包满的件留在地上（不静默丢失），地面物品另有 60s 生命周期兜底。
func _sweep_drops() -> Dictionary:
	var took := 0
	var coins := 0
	var gold := 0
	var left := 0
	for n in get_tree().get_nodes_in_group("ground_items"):
		if not (n is GroundItem):
			continue
		var g := n as GroundItem
		var it: Dictionary = g.item
		if it.is_empty():
			g.queue_free()
			continue
		if String(it.get("kind", "")) == "coin":
			gold += GameState.add_gold(int(it.get("gold", 0)))
			coins += 1
			g.queue_free()
			continue
		if GameState.add_item(it):
			took += 1
			g.queue_free()
		else:
			left += 1
	_swept_items += took
	_swept_gold += gold
	return {"took": took, "coins": coins, "gold": gold, "left": left}

## 卖掉落（不含开发期测试武器），模拟玩家回城清包。
func _clean_bag() -> int:
	var sold := 0
	var gold0 := GameState.gold
	for i in range(GameState.inventory.size() - 1, -1, -1):
		var it = GameState.inventory[i]
		if not (it is Dictionary):
			continue
		if String(it.get("kind", "")) != "equip":
			continue
		if String(it.get("itemId", "")) == DEBUG_WEAPON_ID:
			continue
		var res := GameState.shop_sell(i, true)
		if bool(res.get("ok", false)):
			sold += 1
	_sold += sold
	_gold_sold += GameState.gold - gold0
	return sold

# ---- 事件 ----

func _on_monster_died(_id: String) -> void:
	_kills += 1

func _on_player_leveled(_lv: int) -> void:
	_levels += 1

# ---- 判定 ----

func _evaluate() -> void:
	var n := _samples.size()
	if n == 0:
		_fail("没有任何采样点")
		return

	var max_orphan := 0
	var max_bag := 0
	for sv in _samples:
		var s: Dictionary = sv
		max_orphan = maxi(max_orphan, int(s["orphan"]))
		max_bag = maxi(max_bag, int(s["bag"]))

	_expect(max_orphan == 0,
		"孤儿节点应恒为 0（对象未正确释放），实际峰值 %d" % max_orphan)
	_expect(_kills > 0, "压测期间应有真实负载（击杀 > 0），实际 %d" % _kills)
	_expect(_travel_count == _stress_count * 2,
		"每次交互脉冲应完成营地↔野外两次切图：%d 次脉冲 / %d 次切图" % [_stress_count, _travel_count])
	_expect(_duplicate_ids == 0,
		"背包不应出现重复实例 ID（复制 bug），实际 %d 次" % _duplicate_ids)
	_expect(max_bag <= GameState.INVENTORY_SIZE,
		"背包占用不应越界（≤ %d），实际峰值 %d" % [GameState.INVENTORY_SIZE, max_bag])
	_expect(_deaths == 0,
		"持续刷怪不应把玩家打死（M1 无死亡处理），实际 %d 次" % _deaths)

	# 漂移：跳过前 10% 采样点（场景初始化），比较「前 1/4」与「后 1/4」均值
	var skip := maxi(2, int(float(n) / 10.0))
	var rest: Array = _samples.slice(skip)
	var m := rest.size()
	if m >= 4:
		var k := maxi(1, int(float(m) / 4.0))
		var head_nodes := 0.0
		var tail_nodes := 0.0
		var head_obj := 0.0
		var tail_obj := 0.0
		var head_mem := 0.0
		var tail_mem := 0.0
		for i in range(k):
			head_nodes += float(rest[i]["nodes"])
			head_obj += float(rest[i]["objects"])
			head_mem += float(rest[i]["memMB"])
		for i in range(m - k, m):
			tail_nodes += float(rest[i]["nodes"])
			tail_obj += float(rest[i]["objects"])
			tail_mem += float(rest[i]["memMB"])
		head_nodes /= float(k)
		tail_nodes /= float(k)
		head_obj /= float(k)
		tail_obj /= float(k)
		head_mem /= float(k)
		tail_mem /= float(k)
		_expect(tail_nodes <= head_nodes * 1.3 + 30.0,
			"节点数应稳定（无泄漏）：前段均值 %.0f → 后段均值 %.0f" % [head_nodes, tail_nodes])
		_expect(tail_obj <= head_obj * 1.3 + 30.0,
			"对象数应稳定（无泄漏）：前段均值 %.0f → 后段均值 %.0f" % [head_obj, tail_obj])
		_expect(tail_mem <= head_mem * 1.6,
			"静态内存不应显著增长：前段均值 %.0fMB → 后段均值 %.0fMB" % [head_mem, tail_mem])

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)

func _fail(msg: String) -> void:
	_failures.append(msg)

# ---- 报告 ----

func _write_reports() -> void:
	var n := _samples.size()
	var first: Dictionary = {}
	var last: Dictionary = {}
	if n > 0:
		first = _samples[0]
		last = _samples[n - 1]

	var lines: Array[String] = []
	lines.append("# 长时稳定性压测报告（SoakTest）")
	lines.append("")
	lines.append("- 运行模式：**%s**" % ("无头（headless）" if _headless else "开窗"))
	lines.append("- 压测时长：%.1fs（采样 %d 次，间隔 %.0fs）" % [
		float(last.get("t", 0.0)), n, _interval])
	lines.append("- 交互脉冲：%d 次（每 %.0fs 一次）" % [_stress_count, STRESS_EVERY])
	lines.append("- M3 切图脉冲：%d 次实际切图（营地↔试炼野外；测试补足返程车费 %d 金）" % [_travel_count, _travel_subsidy])
	lines.append("- 引擎：Godot %s · %s" % [
		Engine.get_version_info().get("string", "?"), OS.get_name()])
	lines.append("")
	lines.append("## 负载与结果")
	lines.append("")
	lines.append("| 指标 | 值 |")
	lines.append("|---|---|")
	lines.append("| 累计击杀 | %d |" % _kills)
	lines.append("| 累计升级 | %d 次（Lv%d → Lv%d）|" % [
		_levels, START_LEVEL, int(last.get("level", START_LEVEL))])
	lines.append("| 累计经验 | %d |" % _xp_gained)
	lines.append("| 卖出装备 | %d 件（+%d 金币）|" % [_sold, _gold_sold])
	lines.append("| 模拟拾取 | %d 件 + %d 金币（未认领留地物兜底清理）|" % [
		_swept_items, _swept_gold])
	lines.append("| 往返切图 | %d 次（测试返程车费补足 %d 金）|" % [_travel_count, _travel_subsidy])
	lines.append("| 顺路拾取触发 | %d 次（清场后观察到 PATH_TO_LOOT；仅命中未认领留地物，属兜底）|" % _loot_paths)
	lines.append("| 低血注水 | %d 次（M1 无自动喝药，压测注水）|" % _heals)
	lines.append("| 玩家死亡 | %d 次 |" % _deaths)
	lines.append("| 最大采样间隔 | %.2fs（超阈值 %d 次）|" % [_max_gap, _gap_overruns])
	lines.append("| 窗口失焦采样 | %d / %d 次（失焦期间 3.14⑥ 会停决策，负载会暂停）|" % [
		_bg_samples, n])
	lines.append("| 孤儿节点峰值 | %d |" % _max_metric("orphan"))
	lines.append("| 节点数 | %d → %d |" % [
		int(first.get("nodes", 0)), int(last.get("nodes", 0))])
	lines.append("| 对象数 | %d → %d |" % [
		int(first.get("objects", 0)), int(last.get("objects", 0))])
	lines.append("| 静态内存 | %.0fMB → %.0fMB |" % [
		float(first.get("memMB", 0.0)), float(last.get("memMB", 0.0))])
	lines.append("| 场上怪物 | %d → %d |" % [
		int(first.get("enemies", 0)), int(last.get("enemies", 0))])
	lines.append("| 留地掉落物（未认领） | %d → %d |" % [
		int(first.get("drops", 0)), int(last.get("drops", 0))])
	lines.append("| 金币 | %d → %d |" % [
		int(first.get("gold", 0)), int(last.get("gold", 0))])
	lines.append("")
	lines.append("## 采样曲线（降采样）")
	lines.append("")
	lines.append("| t(s) | 帧率 | 节点 | 对象 | 孤儿 | 内存MB | 怪 | 留地 | 击杀 | Lv | 金币 | 包 | 自动状态 |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	var step := maxi(1, int(float(n) / 12.0))
	var i := 0
	while i < n:
		var s: Dictionary = _samples[i]
		lines.append("| %.0f | %.0f | %d | %d | %d | %.0f | %d | %d | %d | %d | %d | %d | %s |" % [
			float(s["t"]), float(s["fps"]), int(s["nodes"]), int(s["objects"]),
			int(s["orphan"]), float(s["memMB"]), int(s["enemies"]), int(s["drops"]),
			int(s["kills"]), int(s["level"]), int(s["gold"]), int(s["bag"]),
			String(s["state"])])
		i += step
	if n > 0 and (n - 1) % step != 0:
		var sl: Dictionary = _samples[n - 1]
		lines.append("| %.0f | %.0f | %d | %d | %d | %.0f | %d | %d | %d | %d | %d | %d | %s |" % [
			float(sl["t"]), float(sl["fps"]), int(sl["nodes"]), int(sl["objects"]),
			int(sl["orphan"]), float(sl["memMB"]), int(sl["enemies"]), int(sl["drops"]),
			int(sl["kills"]), int(sl["level"]), int(sl["gold"]), int(sl["bag"]),
			String(sl["state"])])
	lines.append("")
	lines.append("## 判定")
	lines.append("")
	if _failures.is_empty():
		lines.append("**✅ 全部通过**：%d 分钟内无崩溃、无卡死、无节点/对象泄漏、无孤儿节点。" % int(_seconds / 60.0))
	else:
		lines.append("**❌ 失败 %d 项**：" % _failures.size())
		lines.append("")
		for f in _failures:
			lines.append("- %s" % f)
	lines.append("")
	lines.append("> 判据：孤儿节点恒 0 ／ 击杀 > 0（真实负载）／ 背包无重复实例、占用不越界 ／")
	lines.append("> 节点数与对象数后段均值 ≤ 前段均值 × 1.3 + 30 ／ 静态内存后段 ≤ 前段 × 1.6。")

	var md := "\n".join(PackedStringArray(lines))
	var f := FileAccess.open(REPORT_MD, FileAccess.WRITE)
	if f != null:
		f.store_string(md)
		f.close()
	var jf := FileAccess.open(REPORT_JSON, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(_samples, "\t"))
		jf.close()
	print("[Soak] 报告已写入：%s" % REPORT_MD)

func _max_metric(key: String) -> int:
	var v := 0
	for sv in _samples:
		var s: Dictionary = sv
		v = maxi(v, int(s.get(key, 0)))
	return v

# ---- 参数与现场保护 ----

func _parse_args() -> void:
	var args: Array = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for a in args:
		var s := String(a)
		if s.begins_with("--soak="):
			_seconds = maxf(5.0, float(s.split("=")[1]))
		elif s.begins_with("--interval="):
			_interval = maxf(1.0, float(s.split("=")[1]))
		elif s == "--no-ui-stress":
			_ui_stress = false

## 快照整个 saves 目录（文件名 → 内容），结束后原样还原。
func _snapshot_saves() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(SaveManager.SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var path := SaveManager.SAVE_DIR + name
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				out[name] = f.get_as_text()
				f.close()
		name = dir.get_next()
	dir.list_dir_end()
	print("[Soak] 已快照 %d 个存档文件（结束后还原）" % out.size())
	# 额外落一份到 /tmp：万一压测被强制中断（Ctrl+C），仍可手工恢复玩家存档
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	for key in out.keys():
		var bf := FileAccess.open(BACKUP_DIR + String(key), FileAccess.WRITE)
		if bf != null:
			bf.store_string(String(out[key]))
			bf.close()
	return out

func _restore_saves() -> void:
	var dir := DirAccess.open(SaveManager.SAVE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if not dir.current_is_dir():
				DirAccess.remove_absolute(SaveManager.SAVE_DIR + name)
			name = dir.get_next()
		dir.list_dir_end()
	for key in _save_snapshot.keys():
		var f := FileAccess.open(SaveManager.SAVE_DIR + String(key), FileAccess.WRITE)
		if f != null:
			f.store_string(String(_save_snapshot[key]))
			f.close()
	print("[Soak] 已还原存档现场（%d 个文件）" % _save_snapshot.size())

# ---- 收尾 ----

func _finish() -> void:
	print("=".repeat(64))
	if _failures.is_empty():
		print("[Soak] ✅ 全部通过：%.0fs 压测无崩溃 / 无卡死 / 无泄漏（击杀 %d · 升级 %d）" % [
			_seconds, _kills, _levels])
	else:
		for f in _failures:
			print("[Soak] ❌ %s" % f)
		print("[Soak] 失败 %d 项" % _failures.size())
	print("=".repeat(64))
	get_tree().quit(0 if _failures.is_empty() else 1)
