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

const HIDE_AFTER := 3.0           # 脱战隐藏延迟（s）
const FADE_AFTER_DEATH := 0.6     # 死亡后停留（s），随后淡出
const FADE_TIME := 0.3            # 淡出时长（s）
## 同时最多几条（同区 2 只 + 「刚打死一只、旁边又来一只」的过渡）。
const MAX_BARS := 3
## 三阶段名（对应 monsters.json 的 bossSkill.phases 0/1/2，创意 07 §4）。
const PHASE_KEYS := ["ui.boss.phase_sealed", "ui.boss.phase_cracked", "ui.boss.phase_corrupted"]

## 每条：`{id, name, hp, max_hp, phase, since, dying_left, alpha}`。
var _bars: Array[Dictionary] = []
## 全部条目都在死亡淡出中（既有断言语义：非空且全 dying）。
var _dying := false
var _rows: Dictionary = {}
var _row_pool: Array[BossStatusRow] = []
var _portraits := MonsterPortraitCache.new()
var _selected_id := 0

## 绑定数据事件，保持原有逐实例状态模型。
func _ready() -> void:
	EventBus.equipment_changed.connect(_refresh_gap_rows)
	EventBus.data_loaded.connect(_on_data_loaded)
	EventBus.map_changed.connect(_on_map_changed)
	EventBus.target_changed.connect(_on_target_changed)
	resized.connect(_sync_rows)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.boss_hp_changed.connect(_on_boss_hp)

## 逐条推进过期与死亡淡出，不重排仍存活的实例。
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

## 接收真实实例事件，首次登记时缓存头像及技能阶段信息。
func _on_boss_hp(boss_id: int, boss_name: String, hp: int, max_hp: int, phase: int) -> void:
	var index := _index_of(boss_id)
	var monster := instance_from_id(boss_id) if is_instance_id_valid(boss_id) else null
	var level := EquipmentGap.target_level(monster) if monster is Node else 0
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
	if level > 0:
		var updated := _index_of(boss_id)
		if updated >= 0:
			_bars[updated]["level"] = level
	var updated_index := _index_of(boss_id)
	if updated_index >= 0 and monster is Monster:
		var entry: Dictionary = _bars[updated_index]
		if entry.get("portrait") == null:
			entry["portrait"] = _portraits.get_portrait(monster)
		entry["thresholds"] = _thresholds(monster)
		entry["phase_text"] = _phase_text(monster, phase)
	_refresh_gap_rows(false)
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

## 更新可见性与行节点，所有死亡时保持原有_dying语义。
func _sync_visibility() -> void:
	visible = not _bars.is_empty()
	var all_dying := true
	for entry in _bars:
		if float(entry["dying_left"]) <= 0.0:
			all_dying = false
			break
	_dying = visible and all_dying
	_sync_rows()

## 按运行实例id查找条目，不按怪物模板或同名匹配。
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

## 通过行节点呈现数据，布局使用固定槽位；更新既有实例不改变顺序。
func _sync_rows() -> void:
	for id in _rows.keys():
		if _index_of(id) < 0:
			var row: BossStatusRow = _rows[id]
			row.clear_presentation()
			_row_pool.append(row)
			_rows.erase(id)
	var compact := size.x < 1000.0 or size.y < 650.0
	var compact_height := 52.0 if size.y < 460.0 else 60.0
	var width := minf(560.0, maxf(280.0, size.x - 275.0))
	var left := clampf((size.x - width) * 0.5, 16, maxf(16, size.x - 259 - width))
	var total := (compact_height * _bars.size() if compact else 88.0 + 60.0 * maxi(0,_bars.size()-1)) + 8.0 * maxi(0,_bars.size()-1)
	var y := minf(140.0, maxf(132.0, size.y - 92.0 - total))
	for i in range(_bars.size()):
		var entry: Dictionary = _bars[i]
		var id := int(entry.id)
		if not _rows.has(id):
			var row: BossStatusRow = _row_pool.pop_back() if not _row_pool.is_empty() else BossStatusRow.new()
			if row.get_parent() == null:
				add_child(row)
			row.show()
			_rows[id] = row
		var row: BossStatusRow = _rows[id]
		row.position = Vector2(left, y)
		row.size = Vector2(width, 88 if i == 0 and not compact else compact_height)
		row.present(entry, i == 0 and not compact, id == _selected_id)
		y += row.size.y + 8

## 每次血量/装备/规则事件刷新最多三条提示，不在绘制或逐帧扫描装备属性。
func _refresh_gap_rows(sync: bool = true) -> void:
	var ctx := EquipmentGap.current_context()
	for entry in _bars:
		entry["gap_text"] = EquipmentGap.hint(ctx,int(entry.get("level",0)))
	if sync:
		_sync_rows()

## 从实际技能定义读取血量阈值，不把首章的60%/30%强加给其他首领。
func _thresholds(monster: Monster) -> Array:
	var result: Array = []
	var raw: Variant = monster.template.get("bossSkill")
	var skill: Dictionary = raw if raw is Dictionary else {}
	for phase in skill.get("phases", []):
		if phase.has("hpBelow"):
			result.append(float(phase.hpBelow))
	if skill.has("phaseB"):
		result.append(float(skill.phaseB.get("triggerHp", 0.5)))
	if skill.has("phaseC"):
		result.append(float(skill.phaseC.get("hpBelow", 0.25)))
	return result

## 首章使用既有阶段命名，其他模板只展示真实已触发阶段，避免虚构同名机制。
func _phase_text(monster: Monster, phase: int) -> String:
	var raw: Variant = monster.template.get("bossSkill")
	var skill: Dictionary = raw if raw is Dictionary else {}
	if skill.has("phases") or monster.template.get("abilities", {}).has("bossPattern"):
		return Localization.tr_key(PHASE_KEYS[clampi(phase, 0, PHASE_KEYS.size()-1)])
	if skill.has("phaseC") and monster.hp_ratio() <= float(skill.phaseC.get("hpBelow",0.25)):
		return "III"
	return "II" if monster._boss_visual_phase == 1 else "I" if skill.has("phaseB") else ""

## 配置重载后重新取仍存在实例的外观，缓存资源不跨数据修订存活。
func _on_data_loaded() -> void:
	_portraits.clear()
	for entry in _bars:
		var monster := instance_from_id(int(entry.id)) if is_instance_id_valid(int(entry.id)) else null
		entry["portrait"] = _portraits.get_portrait(monster) if monster is Monster else null
	_refresh_gap_rows()

## 切图时清空旧Boss与头像，避免旧实例在新地图上继续展示。
func _on_map_changed(_map_id: String) -> void:
	_bars.clear()
	_portraits.clear()
	_sync_visibility()

## UI销毁时主动放开裁切缓存，行节点纹理随子树释放。
func _exit_tree() -> void:
	_portraits.clear()

## 选中高亮只改变外框，不改变显示槽、顺序或行高。
func _on_target_changed(target: Node) -> void:
	_selected_id = target.get_instance_id() if is_instance_valid(target) else 0
	_sync_rows()
