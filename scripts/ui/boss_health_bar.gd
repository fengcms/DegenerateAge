extends Control
## M6-0a（创意 07 §4）：Boss 顶部血条。
##
## 挂 `Main.tscn` 的 `UI` 下（随 UI 轴缩放，见 `SettingsRuntime.apply_ui_scale_to`）。
## 数据源＝`EventBus.boss_hp_changed`（由 `Monster` 在受击 / 阶段变更 / 进入仇恨 / 死亡时广播）。
## 显隐：任一更新 → 显示；脱战 3s 无更新 → 隐藏；死亡（hp≤0）停留 0.6s 后淡出。
##
## M10-3b（P-7）：**多目标**。信号首参 `boss_id` 区分实例，本控件按 id 维护一张表
## （`_bars`，顺序即显示顺序，index 0 在最上）：
##   · 新 id → 插到最上（最新接战优先）；已有 id → **原地更新，不重排**。
##     产品原建议是「最近受击置顶」，但两只同时挨打时会互相顶掉 ⇒ 仍然跳位；
##     改成「首见置顶 + 原位更新」后跳位从根上消失。
##   · 逐条 `HIDE_AFTER` 过期（= 产品说的「最近 3s 内受击才更新」），一条过期不带走另一条。
##   · 死亡逐条处理：保留条目 0.6s + 0.3s 淡出，旁边那只的血条不受影响。
##   · `MAX_BARS` 上限：超限淘汰 `since` 最大的非死亡条目（同区 2 只 + 打死一只的过渡够用）。

const MONO_FONT := preload("res://assets/themes/mono_font.tres")

const HIDE_AFTER := 3.0           # 脱战隐藏延迟（s）
const FADE_AFTER_DEATH := 0.6     # 死亡后停留（s），随后淡出
const FADE_TIME := 0.3            # 淡出时长（s）
const BAR_W := 480.0
const BAR_H := 18.0
const TOP_Y := 22.0
## 条间距：一条血条 = 18px 条体 + 名称行，40px 足够不叠字。
const PITCH := 40.0
## 同时最多几条（同区 2 只 + 「刚打死一只、旁边又来一只」的过渡）。
const MAX_BARS := 3
## 三阶段名（对应 monsters.json 的 bossSkill.phases 0/1/2，创意 07 §4）。
const PHASE_KEYS := ["ui.boss.phase_sealed", "ui.boss.phase_cracked", "ui.boss.phase_corrupted"]

const COL_BG := Color(0.06, 0.02, 0.03, 0.88)
const COL_EDGE := Color(0.58, 0.18, 0.18, 0.95)
const COL_FILL := Color(0.78, 0.16, 0.18, 1.0)
const COL_TICK := Color(1.0, 0.85, 0.4, 0.8)
const COL_NAME := Color(0.96, 0.89, 0.87, 1.0)
const COL_PHASE := Color(0.96, 0.74, 0.64, 1.0)
const COL_HP_TEXT := Color(1.0, 1.0, 1.0, 0.85)

## 每条：`{id, name, hp, max_hp, phase, since, dying_left, alpha}`。
var _bars: Array[Dictionary] = []
## 全部条目都在死亡淡出中（既有断言语义：非空且全 dying）。
var _dying := false

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.boss_hp_changed.connect(_on_boss_hp)

func _process(delta: float) -> void:
	if _bars.is_empty():
		return
	var dirty := false
	for i in range(_bars.size() - 1, -1, -1):
		var entry: Dictionary = _bars[i]
		if float(entry["dying_left"]) > 0.0:
			entry["dying_left"] = float(entry["dying_left"]) - delta
			# 前 0.6s 保持不透明，最后 FADE_TIME 内线性淡出。
			entry["alpha"] = clampf(float(entry["dying_left"]) / FADE_TIME, 0.0, 1.0)
			if float(entry["dying_left"]) <= 0.0:
				_bars.remove_at(i)
			dirty = true
		else:
			entry["since"] = float(entry["since"]) + delta
			if float(entry["since"]) >= HIDE_AFTER:
				_bars.remove_at(i)
				dirty = true
	if dirty:
		_sync_visibility()
		queue_redraw()

func _on_boss_hp(boss_id: int, boss_name: String, hp: int, max_hp: int, phase: int) -> void:
	var index := _index_of(boss_id)
	if hp <= 0:
		if index < 0:
			return
		var dying: Dictionary = _bars[index]
		dying["hp"] = 0
		dying["max_hp"] = maxi(1, max_hp)
		dying["phase"] = phase
		if float(dying["dying_left"]) <= 0.0:
			dying["dying_left"] = FADE_AFTER_DEATH + FADE_TIME
			dying["alpha"] = 1.0
		_sync_visibility()
		queue_redraw()
		return
	if index >= 0:
		var live: Dictionary = _bars[index]
		live["name"] = boss_name
		live["hp"] = hp
		live["max_hp"] = maxi(1, max_hp)
		live["phase"] = phase
		live["since"] = 0.0
		# 回血 / 归位 / 实例复用时撤销死亡淡出。
		live["dying_left"] = 0.0
		live["alpha"] = 1.0
	else:
		_bars.insert(0, {
			"id": boss_id,
			"name": boss_name,
			"hp": hp,
			"max_hp": maxi(1, max_hp),
			"phase": phase,
			"since": 0.0,
			"dying_left": 0.0,
			"alpha": 1.0,
		})
		_evict_overflow()
	_sync_visibility()
	queue_redraw()

## 超上限时淘汰「最久没更新」的存活条目；若全部在死亡淡出，淘汰最旧的（数组尾）。
func _evict_overflow() -> void:
	while _bars.size() > MAX_BARS:
		var worst := -1
		var worst_since := -1.0
		for i in range(_bars.size()):
			var entry: Dictionary = _bars[i]
			if float(entry["dying_left"]) > 0.0:
				continue
			if float(entry["since"]) >= worst_since:
				worst_since = float(entry["since"])
				worst = i
		if worst < 0:
			worst = _bars.size() - 1
		_bars.remove_at(worst)

func _sync_visibility() -> void:
	visible = not _bars.is_empty()
	var all_dying := true
	for entry in _bars:
		if float(entry["dying_left"]) <= 0.0:
			all_dying = false
			break
	_dying = visible and all_dying

func _index_of(boss_id: int) -> int:
	for i in range(_bars.size()):
		if int(_bars[i]["id"]) == boss_id:
			return i
	return -1

## 当前显示条数（测试 / 调试用）。
func bar_count() -> int:
	return _bars.size()

## 显示顺序的实例 id（index 0 在最上）—— 测试 / 调试用。
func bar_ids() -> Array[int]:
	var ids: Array[int] = []
	for entry in _bars:
		ids.append(int(entry["id"]))
	return ids

## 指定实例的血条快照（无 → 空字典）。返回副本，调用方改不动内部状态。
func bar_state(boss_id: int) -> Dictionary:
	var index := _index_of(boss_id)
	if index < 0:
		return {}
	return (_bars[index] as Dictionary).duplicate()

func _draw() -> void:
	var left := size.x * 0.5 - BAR_W * 0.5
	for i in range(_bars.size()):
		_draw_one(left, TOP_Y + PITCH * float(i), _bars[i])

func _draw_one(left: float, top: float, entry: Dictionary) -> void:
	var alpha := float(entry["alpha"])
	# 名称（血条上方居中）
	var name_color := COL_NAME
	name_color.a *= alpha
	draw_string(MONO_FONT, Vector2(left, top - 7.0), String(entry["name"]),
		HORIZONTAL_ALIGNMENT_CENTER, BAR_W, 17, name_color)
	# 底板 + 血量
	var bg := COL_BG
	bg.a *= alpha
	draw_rect(Rect2(left, top, BAR_W, BAR_H), bg)
	var ratio := clampf(float(int(entry["hp"])) / float(int(entry["max_hp"])), 0.0, 1.0)
	if ratio > 0.0:
		var fill := COL_FILL
		fill.a *= alpha
		draw_rect(Rect2(left, top, BAR_W * ratio, BAR_H), fill)
	# 阶段刻度（60% / 30%）
	for t in [0.6, 0.3]:
		var tick := COL_TICK
		tick.a *= alpha
		var tx := left + BAR_W * float(t)
		draw_line(Vector2(tx, top), Vector2(tx, top + BAR_H), tick, 2.0, true)
	var edge := COL_EDGE
	edge.a *= alpha
	draw_rect(Rect2(left, top, BAR_W, BAR_H), edge, false, 2.0)
	# 血量数值（左）+ 阶段名（中）
	var hp_color := COL_HP_TEXT
	hp_color.a *= alpha
	draw_string(MONO_FONT, Vector2(left + 8.0, top + BAR_H - 4.0),
		"%d / %d" % [int(entry["hp"]), int(entry["max_hp"])],
		HORIZONTAL_ALIGNMENT_LEFT, BAR_W - 16.0, 11, hp_color)
	var phase_color := COL_PHASE
	phase_color.a *= alpha
	var phase_name := Localization.tr_key(PHASE_KEYS[clampi(int(entry["phase"]), 0, PHASE_KEYS.size() - 1)])
	draw_string(MONO_FONT, Vector2(left, top + BAR_H - 4.0), phase_name,
		HORIZONTAL_ALIGNMENT_CENTER, BAR_W, 11, phase_color)
