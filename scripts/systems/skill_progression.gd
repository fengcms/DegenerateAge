class_name SkillProgression
extends RefCounted
## 玩家技能阶数配置与生效数值解析。基础技能来自 skills.json，升级只叠加有限阶的攻击系数或 Buff 效果。
## 只供玩家技能使用，不修改共享配置；缓存按 DataLoader 修订号失效，战斗热路径不反复复制字典。

static var _resolved: Dictionary = {}
static var _data_revision := -1

## 已解锁技能默认为 1 阶；未解锁为 0 阶。旧档迁移与新建角色共用这一规则。
static func default_rank(skill_id: String, player_level: int) -> int:
	var base: Variant = DataLoader.get_entry("skills", skill_id)
	return 1 if base is Dictionary and player_level >= int((base as Dictionary).get("unlockLevel", 1)) else 0

## 返回技能最高阶。基础斩击没有升级表，始终只有 1 阶。
static func max_rank(skill_id: String) -> int:
	var base: Variant = DataLoader.get_entry("skills", skill_id)
	if not base is Dictionary:
		return 0
	var config: Variant = DataLoader.get_entry("skillProgression", skill_id)
	return 1 + (config.get("ranks", []) as Array).size() if config is Dictionary else 1

## 查询指定目标阶的购买条件；无下一阶或非法 id 时返回空字典。
static func step(skill_id: String, target_rank: int) -> Dictionary:
	if target_rank < 2:
		return {}
	var config: Variant = DataLoader.get_entry("skillProgression", skill_id)
	if not config is Dictionary:
		return {}
	var ranks: Array = config.get("ranks", [])
	var index := target_rank - 2
	return ranks[index] if index >= 0 and index < ranks.size() and ranks[index] is Dictionary else {}

## 解析指定阶的只读技能定义。缓存最多六技能×五阶；调用方不得修改返回字典。
static func resolve(skill_id: String, rank: int) -> Dictionary:
	if _data_revision != DataLoader.revision:
		_resolved.clear()
		_data_revision = DataLoader.revision
	if rank < 1 or rank > max_rank(skill_id):
		return {}
	var key := "%s#%d" % [skill_id, rank]
	if _resolved.has(key):
		return _resolved[key]
	var base: Variant = DataLoader.get_entry("skills", skill_id)
	if not base is Dictionary:
		return {}
	var effective: Dictionary = (base as Dictionary).duplicate(true)
	if rank > 1:
		var upgrade := step(skill_id, rank)
		if upgrade.is_empty():
			return {}
		if upgrade.has("coefficientMultiplier"):
			effective.coefficient = float(base.get("coefficient", 0.0)) * float(upgrade.coefficientMultiplier)
		if upgrade.has("effects"):
			effective.effects = (upgrade.effects as Dictionary).duplicate(true)
	_resolved[key] = effective
	return effective

## 读取玩家当前阶生效定义；未解锁时返回空字典，供施放和自动战斗共用。
static func current(skill_id: String) -> Dictionary:
	return resolve(skill_id, GameState.skill_rank(skill_id))
