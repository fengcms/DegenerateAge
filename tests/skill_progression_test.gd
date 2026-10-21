extends Node
## 技能阶数配置与解析回归：验证五项技能、效果上限及热重载缓存失效。
## 隔离测试场景不写玩家存档，后续购买和存档往返另行覆盖。

var _failures: Array[String] = []

## 检查静态技能表能完整解析 1—5 阶，且不改变原始 1 阶定义。
func _ready() -> void:
	var config: Variant = DataLoader.get_table("skillProgression")
	_check(config is Array and config.size() == 5, "五个非普攻技能都有阶数配置")
	_check(DataLoader._validate_skill_progression().is_empty(), "阶数配置通过完整校验")
	_check(SkillProgression.max_rank("basic_slash") == 1, "普攻保持单阶")
	_check(SkillProgression.default_rank("spirit_storm", 39) == 0 and SkillProgression.default_rank("spirit_storm", 40) == 1,
		"技能解锁前为 0 阶，解锁后默认 1 阶")
	for raw in config:
		var sid := String(raw.skillId)
		var base: Dictionary = DataLoader.get_entry("skills", sid)
		_check(SkillProgression.max_rank(sid) == 5, "%s 最多 5 阶" % sid)
		_check(SkillProgression.resolve(sid, 1).get("coefficient") == base.get("coefficient"), "%s 的 1 阶保持基准" % sid)
		_check(SkillProgression.resolve(sid, 6).is_empty(), "%s 拒绝越界阶数" % sid)
		var top := SkillProgression.resolve(sid, 5)
		if sid == "battle_focus":
			_check(is_equal_approx(float((top.effects as Dictionary).attackPct), 0.26)
				and is_equal_approx(float((top.effects as Dictionary).attackSpeedPct), 0.19), "战意觉醒 5 阶效果")
		else:
			_check(is_equal_approx(float(top.coefficient), float(base.coefficient) * 1.12), "%s 的 5 阶伤害增幅受限" % sid)
			_check(int(top.get("hits", 1)) == int(base.get("hits", 1)) and top.range == base.range
				and top.cooldown == base.cooldown and top.manaCost == base.manaCost, "%s 不暗改段数/射程/冷却/耗蓝" % sid)
	var original := SkillProgression.resolve("earth_cleave", 2)
	var valid_config: Array = (config as Array).duplicate(true)
	var broken_config: Array = valid_config.duplicate(true)
	broken_config[0].ranks[0].rank = 4
	broken_config[0].ranks[0].coefficientMultiplier = 3.0
	DataLoader.tables["skillProgression"] = broken_config
	_check(not DataLoader._validate_skill_progression().is_empty(), "错阶与越界伤害配置会被拦截")
	broken_config = valid_config.duplicate(true)
	broken_config[0].ranks[1].coefficientMultiplier = 1.01
	DataLoader.tables["skillProgression"] = broken_config
	_check(not DataLoader._validate_skill_progression().is_empty(), "高阶倍率倒退会被拦截")
	DataLoader.tables["skillProgression"] = valid_config
	DataLoader.load_all()
	var reloaded := SkillProgression.resolve("earth_cleave", 2)
	_check(not is_same(original, reloaded), "重载配置后丢弃旧解析缓存")
	if _failures.is_empty():
		print("SkillProgressionTest: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)

## 收集所有失败，避免第一处失败掩盖其他配置问题。
func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
