class_name PlayerClass
extends RefCounted
## 职业定义解析（工程 98 第一层）。
##
## 唯一数据源是 `data/classes.json`：系数与射程都写在表里，不散落成代码常量 ——
## 这样「武士全 1.0」变成可断言的配置事实（`tests/class_frame_test.gd`），而不是靠记性。
##
## 🔴 三条红线（改这里之前先读工程文档 98 §3.2 / §6）：
##   ① `atkMult` **只能**在 `GameState.total_attack()` 最外层乘，绝不能进 `_base_attack()`。
##      `max_hp()` 内部用 `_base_attack()` 算血，进去就是二次放大（套装 1.4→1.96 的同一个坑）。
##   ② `defMult` 恒为 1.0，**不要"顺手"降到 0.9**：本作承伤是 `攻 − 防×0.5` 的差值，
##      防御打九折 = 承伤 +39%，法师会变成三击死。脆皮压力由 `hpMult` 承担，那是线性的。
##   ③ 非法 / 缺失的 `classId` 一律回退 `warrior`，**不拒档**（被改过的存档也要能读）。

const DEFAULT_ID := "warrior"

## 全部职业 id（按表顺序）。
static func ids() -> Array:
	var out: Array = []
	var rows: Variant = DataLoader.get_table("classes")
	if not rows is Array:
		return out
	for row in (rows as Array):
		if row is Dictionary:
			var id := String((row as Dictionary).get("id", ""))
			if not id.is_empty():
				out.append(id)
	return out

static func is_valid(id: String) -> bool:
	var rows: Variant = DataLoader.get_table("classes")
	if not rows is Array:
		return false
	for row in (rows as Array):
		if row is Dictionary and String((row as Dictionary).get("id", "")) == id:
			return true
	return false

## 非法 / 空 id → 默认职业。读档、存档面板、旧快捷栏都走这里归一。
static func normalize(id: String) -> String:
	return id if is_valid(id) else DEFAULT_ID

## 取职业定义；id 为空时取**当前存档职业**；仍然取不到时回退默认职业的条目。
static func definition(id: String = "") -> Dictionary:
	var wanted := id if not id.is_empty() else current_id()
	var rows: Variant = DataLoader.get_table("classes")
	if rows is Array:
		for row in (rows as Array):
			if row is Dictionary and String((row as Dictionary).get("id", "")) == wanted:
				return row
		for row in (rows as Array):
			if row is Dictionary and String((row as Dictionary).get("id", "")) == DEFAULT_ID:
				return row
	return {}

## 当前存档的职业 id（永远返回合法值）。旧档无该字段 ⇒ 武士。
static func current_id() -> String:
	return normalize(String(GameState.player.get("classId", DEFAULT_ID)))

## 系数读取。缺键返回 1.0 —— 缺键不等于「削弱」，绝不能返回 0（那会让属性直接归零）。
static func mult(key: String, id: String = "") -> float:
	var value: Variant = definition(id).get(key, 1.0)
	if not (value is int or value is float):
		return 1.0
	return float(value)

## 普攻射程（格）。武士 1.0 / 法师 4.0。
static func attack_range(id: String = "") -> float:
	var value: Variant = definition(id).get("attackRange", 1.0)
	return maxf(1.0, float(value)) if value is int or value is float else 1.0

## 远程职业判定：普攻射程超过 1.5 格即视作远程（1.5 是「近身」与「跨格」的分界，
## 不用 `> 1.0` 是因为将来可能有 1.5 格的长兵，那仍该走近战手感）。
static func is_ranged(id: String = "") -> bool:
	return attack_range(id) > 1.5

## 普攻技能 id（快捷栏默认格与 `player._basic` 都取这里）。
static func basic_skill(id: String = "") -> String:
	var value := String(definition(id).get("basicSkill", "basic_slash"))
	return value if not value.is_empty() else "basic_slash"

## 本职业可拖上快捷栏的技能（含普攻）。顺序与表一致。
static func active_skills(id: String = "") -> Array:
	var out: Array = []
	var rows: Variant = definition(id).get("skills", [])
	if rows is Array:
		for sid in (rows as Array):
			var skill := String(sid)
			if not skill.is_empty():
				out.append(skill)
	return out

static func display_name(id: String = "") -> String:
	var value := String(definition(id).get("name", ""))
	return value if not value.is_empty() else DEFAULT_ID

static func describe(id: String = "") -> String:
	return String(definition(id).get("desc", ""))

## 形象冷色偏移（法师暂无专属素材时的最小区分手段，见方案 §3.6）。
## 空串 ⇒ 返回白色（`modulate` 的恒等值），武士路径因此逐位不变。
static func tint(id: String = "") -> Color:
	var raw := String(definition(id).get("tint", ""))
	return Color.WHITE if raw.is_empty() else Color(raw)
