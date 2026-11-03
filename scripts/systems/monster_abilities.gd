class_name MonsterAbilities
extends RefCounted
## 怪物可复用能力的边界校验；仅检查模板参数与引用，不执行战斗或持有实例。

## 启动/配置重载时检查全部怪物能力；未知能力键拒绝，数值须有限且在执行器支持范围。
static func validate(rows: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not rows is Array:
		return errors
	var ids := {}
	for row in rows:
		if row is Dictionary:
			ids[String(row.get("id", ""))] = true
	for row in rows:
		if not row is Dictionary or not row.has("abilities"):
			continue
		if not _valid(row.abilities, ids):
			errors.append("[abilities] 非法怪物能力：%s" % row.get("id", ""))
	return errors

## 校验单个能力组合，缺省能力保持普通攻击；弹数当前仅支持单发/双发。
static func _valid(raw: Variant, ids: Dictionary) -> bool:
	if not raw is Dictionary:
		return false
	for key in raw:
		if key not in ["bossPattern", "enrageSpeed", "summon", "summonCount", "special", "projectiles", "heal"]:
			return false
	if raw.has("bossPattern") and raw.bossPattern not in ["foreman", "devourer", "extractor"]:
		return false
	if raw.has("special") and raw.special not in ["charge", "sweep"]:
		return false
	if not _number(raw.get("enrageSpeed", 1.0), 1.0, 10.0):
		return false
	var projectiles: Variant = raw.get("projectiles", 1)
	if not _number(projectiles, 1, 2) or float(projectiles) != floor(float(projectiles)):
		return false
	var count: Variant = raw.get("summonCount", 0)
	if not _number(count, 0, 32) or float(count) != floor(float(count)):
		return false
	if count > 0 and not ids.has(raw.get("summon", "")):
		return false
	if raw.has("heal"):
		var heal: Variant = raw.heal
		if not heal is Dictionary or not heal.get("group") is String or heal.group.is_empty():
			return false
		if not _number(heal.get("interval"), 0.01, 3600) or not _number(heal.get("range"), 1, 4096) \
				or not _number(heal.get("fraction"), 0.001, 1):
			return false
	return true

## 数值边界不接收字符串、无穷或 NaN。
static func _number(value: Variant, lower: float, upper: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper
