class_name Quest
extends RefCounted
## 任务系统逻辑层（M2；产品文档 08，工程文档 11 §4.1/§4.2/§4.3）。
##
## 职责：任务状态推导（6 态）、接取 / 推进 / 交付 / 放弃。与 Loot / Shop / Equipment
## 同构 —— **纯静态逻辑层**，不依赖 UI；状态落在 `GameState.quest_states`（存档链已现成）。
##
## 关键设计（11 §4.1）：
##   - `locked` / `available` **不落档**，由 `prev` 链推导 —— 存档只记"玩家做过什么"。
##   - 存储结构：`quest_states = { "Q002": {"state": "active", "progress": 2} }`。
##   - 推进复用现成信号（`EventBus.monster_died` / `item_picked`），不新增采集点。
##
## 6 态流转（08 §8.1）：
##   locked → available → active → completed → rewarded
##                          ↘ abandoned（可立即重接，计数清零重做）

## 6 态常量。
const STATE_LOCKED := "locked"
const STATE_AVAILABLE := "available"
const STATE_ACTIVE := "active"
const STATE_COMPLETED := "completed"
const STATE_REWARDED := "rewarded"
const STATE_ABANDONED := "abandoned"

## 08 §8.4：同时接取上限。
const MAX_ACTIVE := 5

## 目标类型 → 中文动词（UI 文案）。
const KIND_VERB := {
	"kill": "msg.quest.verb_kill",
	"collect": "msg.quest.verb_collect",
	"talk": "msg.quest.verb_talk",
}

## 事件类型 → 任务目标类型（推进映射）。两处 kind 目前同名，独立列出便于将来分叉。
const EVENT_TO_OBJECTIVE := {
	"monster_died": "kill",
	"item_picked": "collect",
}

# ---- 读配置 ----

## 全部任务模板（quests.json 数组）。
static func all() -> Array:
	var t = DataLoader.get_table("quests")
	return t if t is Array else []

## 取任务模板（不存在返回空字典）。
static func template(quest_id: String) -> Dictionary:
	var e = DataLoader.get_entry("quests", quest_id)
	return e if e is Dictionary else {}

# ---- 状态推导（11 §4.1）----

## 任务当前状态（6 态）。`locked` / `available` 由 `prev` 链推导，不落档。
static func state_of(quest_id: String) -> String:
	var rec = _record(quest_id)
	if rec is Dictionary:
		return String((rec as Dictionary).get("state", STATE_AVAILABLE))
	if rec is String:                                  # 结构迁移前的老档（防御）
		return rec
	var tpl := template(quest_id)
	if tpl.is_empty():
		return STATE_LOCKED
	var prev := String(tpl.get("prev", ""))
	if prev.is_empty():
		return STATE_AVAILABLE
	return STATE_AVAILABLE if state_of(prev) == STATE_REWARDED else STATE_LOCKED

## 任务进度 {cur, need}。need 取自 objective.count。
static func progress_of(quest_id: String) -> Dictionary:
	var need := 0
	var tpl := template(quest_id)
	if not tpl.is_empty():
		var obj = tpl.get("objective", {})
		if obj is Dictionary:
			need = maxi(0, int((obj as Dictionary).get("count", 1)))
	var cur := 0
	var rec = _record(quest_id)
	if rec is Dictionary:
		cur = int((rec as Dictionary).get("progress", 0))
	return {"cur": cur, "need": need}

## 当前进行中的任务数（08 §8.4 上限判据）。
static func active_count() -> int:
	var n := 0
	for qid in GameState.quest_states.keys():
		if state_of(String(qid)) == STATE_ACTIVE:
			n += 1
	return n

## 是否有任意任务处于该状态。
static func has_state(state: String) -> bool:
	for qid in GameState.quest_states.keys():
		if state_of(String(qid)) == state:
			return true
	return false

# ---- 接取 / 放弃（08 §8.2 / §8.4）----

## 接取任务。返回 {ok, reason, state}。
## `talk` 类目标（D4-A）：接取即达标 → 直接置 completed（"与长老交谈"在接取那刻已发生）。
static func accept(quest_id: String) -> Dictionary:
	var tpl := template(quest_id)
	if tpl.is_empty():
		return _fail(Localization.tr_key("msg.quest.p001"))
	var st := state_of(quest_id)
	match st:
		STATE_LOCKED:
			return _fail(Localization.tr_key("msg.quest.p002"))
		STATE_ACTIVE:
			return _fail(Localization.tr_key("msg.quest.p003"))
		STATE_COMPLETED:
			return _fail(Localization.tr_key("msg.quest.p004"))
		STATE_REWARDED:
			return _fail(Localization.tr_key("msg.quest.p005"))
	if active_count() >= MAX_ACTIVE:
		return _fail(Localization.tr_key("msg.quest.p006") % MAX_ACTIVE)

	var obj = tpl.get("objective", {})
	var kind := ""
	var need := 1
	if obj is Dictionary:
		kind = String((obj as Dictionary).get("kind", ""))
		need = maxi(1, int((obj as Dictionary).get("count", 1)))

	_write(quest_id, STATE_ACTIVE, 0)
	EventBus.quest_accepted.emit(quest_id)

	if kind == "talk":
		_complete(quest_id, need)          # 接取即达标
	return {"ok": true, "reason": "", "state": state_of(quest_id)}

## 放弃任务（08 §8.2：主线不可放弃）。计数清零，状态置 abandoned（可立即重接）。
static func abandon(quest_id: String) -> Dictionary:
	var tpl := template(quest_id)
	if tpl.is_empty():
		return _fail(Localization.tr_key("msg.quest.p001"))
	if not bool(tpl.get("abandonable", false)):
		return _fail(Localization.tr_key("msg.quest.p007"))
	if state_of(quest_id) != STATE_ACTIVE:
		return _fail(Localization.tr_key("msg.quest.p008"))
	_write(quest_id, STATE_ABANDONED, 0)
	EventBus.toast_requested.emit(Localization.tr_key("msg.quest.p009") % String(tpl.get("name", quest_id)), "info")
	return {"ok": true, "reason": ""}

# ---- 推进（11 §4.2）----

## 由 EventBus 事件驱动推进（接线见 autoload/quest_service.gd）。
## `event_kind` 用 EventBus 的信号名（monster_died / item_picked），
## 内部映射为主目标类型（kill / collect）。**只用 active 状态的任务计数**。
static func on_event(event_kind: String, target_id: String) -> void:
	var objective_kind := String(EVENT_TO_OBJECTIVE.get(event_kind, event_kind))
	for tpl in all():
		if not (tpl is Dictionary):
			continue
		var qid := String((tpl as Dictionary).get("id", ""))
		if qid.is_empty() or state_of(qid) != STATE_ACTIVE:
			continue
		var obj = (tpl as Dictionary).get("objective", {})
		if not (obj is Dictionary):
			continue
		if String((obj as Dictionary).get("kind", "")) != objective_kind:
			continue
		if String((obj as Dictionary).get("targetId", "")) != target_id:
			continue
		if not _in_scope(tpl as Dictionary):          # D3：地图范围校验
			continue
		var need := maxi(1, int((obj as Dictionary).get("count", 1)))
		var cur := int(progress_of(qid).get("cur", 0))
		if cur >= need:                                # 达标后不再计数（08 §8.1）
			continue
		cur += 1
		if cur >= need:
			_complete(qid, cur)
		else:
			_write(qid, STATE_ACTIVE, cur)
			EventBus.quest_progressed.emit(qid, cur, need)

## 当前地图是否在任务允许范围（11 §4.3 D3：代码按最终设计做，数据 M2 用临时值）。
static func _in_scope(tpl: Dictionary) -> bool:
	var scope = tpl.get("mapScope", [])
	if not (scope is Array) or (scope as Array).is_empty():
		return true
	return (scope as Array).has(GameState.current_map)

# ---- 交付与奖励结算（11 §4.3 M2-5）----

## 交付已完成的任务：结算金币 / 经验 / 物品 / 解锁，状态置 rewarded。
## 返回 {ok, reason, reward, item}。**背包满时明确拒绝且不置 rewarded**（R-e，不静默丢奖）。
static func deliver(quest_id: String) -> Dictionary:
	var tpl := template(quest_id)
	if tpl.is_empty():
		return _fail(Localization.tr_key("msg.quest.p001"))
	if state_of(quest_id) != STATE_COMPLETED:
		return _fail(Localization.tr_key("msg.quest.p010"))

	var reward = tpl.get("reward", {})
	if not (reward is Dictionary):
		reward = {}
	reward = reward as Dictionary

	# 先校验奖励物品可入包（避免"发了金币却丢了装备"的半完成态）
	var item_id := String(reward.get("item", ""))
	var item := {}
	if not item_id.is_empty():
		item = ItemFactory.make_any(item_id, 1)
		if item.is_empty():
			return _fail(Localization.tr_key("msg.quest.p011") % item_id)
		if not Inventory.has_space_for(GameState.inventory, item):
			return _fail(Localization.tr_key("msg.quest.p012"))

	var gold := int(reward.get("gold", 0))
	var xp := int(reward.get("xp", 0))
	if gold > 0:
		GameState.add_gold(gold)
	if xp > 0:
		GameState.add_xp(xp)
	if not item.is_empty():
		GameState.add_item(item)

	var unlock := String(reward.get("unlock", ""))
	if not unlock.is_empty():
		GameState.unlocks[unlock] = true

	_write(quest_id, STATE_REWARDED, int(progress_of(quest_id).get("cur", 0)))
	EventBus.quest_rewarded.emit(quest_id)

	var parts: Array[String] = []
	if gold > 0:
		parts.append(Localization.tr_key("msg.quest.p013") % gold)
	if xp > 0:
		parts.append(Localization.tr_key("msg.quest.p014") % xp)
	if not item.is_empty():
		parts.append(ItemUtil.display_name(item))
	if not unlock.is_empty():
		parts.append(Localization.tr_key("msg.quest.p015") % unlock)
	EventBus.toast_requested.emit(Localization.tr_key("msg.quest.p016") % [
		String(tpl.get("name", quest_id)),
		"（%s）" % "，".join(PackedStringArray(parts)) if not parts.is_empty() else "",
	], "levelup")

	return {"ok": true, "reason": "", "reward": reward, "item": item}

# ---- 读档归一化（R8；11 §4.1）----

## 把存档里的 questStates 归一化为 {id: {state, progress}}。
## 老档 String 值 → 包成 {"state": 值, "progress": 0}；非法项丢弃（不静默写坏）。
## 另做一次防御：active 且进度已满的记录补置 completed（避免"永远无法完成"的悬挂态）。
static func normalize_states(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for k in (raw as Dictionary).keys():
		var qid := String(k)
		if qid.is_empty():
			continue
		var v = raw[k]
		var st := ""
		var prog := 0
		if v is String:
			st = String(v)
		elif v is Dictionary:
			st = String((v as Dictionary).get("state", STATE_ACTIVE))
			prog = int((v as Dictionary).get("progress", 0))
		else:
			continue
		if not _is_known_state(st):
			continue
		if st == STATE_ACTIVE:
			var need := int(progress_of(qid).get("need", 0))
			if need > 0 and prog >= need:
				st = STATE_COMPLETED
		out[qid] = {"state": st, "progress": prog}
	return out

static func _is_known_state(st: String) -> bool:
	return st in [STATE_LOCKED, STATE_AVAILABLE, STATE_ACTIVE, STATE_COMPLETED, STATE_REWARDED, STATE_ABANDONED]

# ---- UI 视图数据（任务面板 / HUD 列表）----

## 全部任务的状态视图（按 quests.json 定义顺序）。
## 每项：{id, name, desc, type, state, cur, need, objective, objectiveText}
static func list_states() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tpl in all():
		if not (tpl is Dictionary):
			continue
		var qid := String((tpl as Dictionary).get("id", ""))
		if qid.is_empty():
			continue
		var p := progress_of(qid)
		var entry := {
			"id": qid,
			"name": String((tpl as Dictionary).get("name", qid)),
			"desc": String((tpl as Dictionary).get("desc", "")),
			"type": String((tpl as Dictionary).get("type", "main")),
			"state": state_of(qid),
			"cur": int(p.get("cur", 0)),
			"need": int(p.get("need", 0)),
			"objective": (tpl as Dictionary).get("objective", {}),
		}
		entry["objectiveText"] = objective_text(entry)
		out.append(entry)
	return out

## 进行中 / 可交付的任务（HUD 列表用；08 §8.1 与 9.1 第 6 条）。
static func ongoing_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in list_states():
		var st := String(e.get("state", ""))
		if st == STATE_ACTIVE or st == STATE_COMPLETED:
			out.append(e)
	return out

## 目标进度文本，如「击败 腐化野狼 3/5」；count ≤ 1 时省略进度。
static func objective_text(entry: Dictionary) -> String:
	var obj = entry.get("objective", {})
	if not (obj is Dictionary):
		return ""
	var kind := String((obj as Dictionary).get("kind", ""))
	var tid := String((obj as Dictionary).get("targetId", ""))
	var verb := Localization.tr_key(String(KIND_VERB[kind])) if KIND_VERB.has(kind) else ""
	var tname := _target_name(kind, tid)
	var need := int(entry.get("need", 0))
	if need <= 1:
		return "%s%s" % [verb, tname]
	return "%s%s %d/%d" % [verb, tname, int(entry.get("cur", 0)), need]

## 任务面板点击击杀目标：只导航至实际刷新点，不选择目标或发动攻击。
static func start_target_navigation(quest_id: String) -> Dictionary:
	if state_of(quest_id) != STATE_ACTIVE:
		return {"ok": false, "reason": Localization.tr_key("msg.quest.p017")}
	var tpl := template(quest_id)
	var objective: Dictionary = tpl.get("objective", {})
	if String(objective.get("kind", "")) != "kill":
		return {"ok": false, "reason": Localization.tr_key("msg.quest.p018")}
	return MapService.start_quest_navigation(String(objective.get("targetId", "")), tpl.get("mapScope", []))

## 目标对象显示名（怪物 / 收集物 / NPC）。
static func _target_name(kind: String, target_id: String) -> String:
	var table := ""
	match kind:
		"kill":
			table = "monsters"
		"collect":
			table = "miscItems"
		"talk":
			return "长老"        # M2 仅任务官一位
		_:
			return target_id
	var e = DataLoader.get_entry(table, target_id)
	if e is Dictionary:
		return String((e as Dictionary).get("name", target_id))
	return target_id

# ---- 内部 ----

static func _record(quest_id: String) -> Variant:
	return GameState.quest_states.get(quest_id)

static func _write(quest_id: String, state: String, progress: int) -> void:
	GameState.quest_states[quest_id] = {"state": state, "progress": progress}

static func _complete(quest_id: String, cur: int) -> void:
	_write(quest_id, STATE_COMPLETED, cur)
	EventBus.quest_completed.emit(quest_id)

static func _fail(reason: String) -> Dictionary:
	EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "reason": reason}
