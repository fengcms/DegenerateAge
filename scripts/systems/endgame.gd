class_name Endgame
extends RefCounted
## M10-3（工程文档 43 §5.1）：满级后循环玩法的静态数据门面。
##
## 与 `Balance` 同规格：**只做纯查表，不引用 `GameState`** —— `--check-only` 下
## autoload 不可见，一旦引用会得到假阳性而不是真问题。
##
## `norm` 口径 = 「投影到 60 级的等效数值」：实例真实值 = `norm × Balance.scale(等级 − 60)`。
## 存在的意义是把各章 Boss 模板 3,000 → 24,300 的 8.1 倍基底差距压进窄带（产品 13 §4.2）。

## 全部循环 Boss 登记（`data/endgame.json` 的 arenaBosses；未配置 → 空数组）。
static func arena_bosses() -> Array:
	var cfg: Variant = DataLoader.get_table("endgame")
	if not cfg is Dictionary:
		return []
	var rows: Variant = (cfg as Dictionary).get("arenaBosses", [])
	return rows if rows is Array else []

## 归一化基底 `{hp, atk, def}`；未登记 → 空字典 ⇒ 调用方回退模板数值。
static func norm(monster_id: String) -> Dictionary:
	if monster_id.is_empty():
		return {}
	for entry in arena_bosses():
		if not entry is Dictionary:
			continue
		if String((entry as Dictionary).get("monsterId", "")) != monster_id:
			continue
		var n: Variant = (entry as Dictionary).get("norm", {})
		return n if n is Dictionary else {}
	return {}

## 该怪物是否有归一化基底（`scaleStats` 的落地判据）。
static func has_norm(monster_id: String) -> bool:
	return not norm(monster_id).is_empty()
