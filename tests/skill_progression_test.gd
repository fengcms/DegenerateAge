extends Node
## 技能阶数配置与解析回归：验证五项技能、效果上限及热重载缓存失效。
## 隔离测试场景不写玩家存档，后续购买和存档往返另行覆盖。

var _failures: Array[String] = []

## 检查静态技能表能完整解析 1—5 阶，且不改变原始 1 阶定义。
func _ready() -> void:
	var config: Variant = DataLoader.get_table("skillProgression")
	# 工程 98：两个职业各 5 条可升阶技能（普攻不升阶）⇒ 10 组。
	# 🔴 不能只把 5 改成 10 就完事 —— 那样「法师那 5 组到底在不在、是不是真的 5 阶」无人看守（第 46 条）。
	_check(config is Array and config.size() == 10, "两个职业各 5 个非普攻技能都有阶数配置（共 10 组）")
	_check(DataLoader._validate_skill_progression().is_empty(), "阶数配置通过完整校验")
	_check(SkillProgression.max_rank("basic_slash") == 1, "普攻保持单阶")
	_check(SkillProgression.max_rank("basic_fireball") == 1, "法师普攻同样保持单阶")
	for class_id in PlayerClass.ids():
		var covered := 0
		for sid in HotbarConfig.active_skills(String(class_id)):
			var tpl: Variant = DataLoader.get_entry("skills", String(sid))
			if not (tpl is Dictionary) or bool((tpl as Dictionary).get("basic", false)):
				continue
			covered += 1
			_check(SkillProgression.max_rank(String(sid)) == 5,
				"%s 的 %s 应有 5 阶" % [String(class_id), String(sid)])
		_check(covered == 5, "%s 应有 5 个可升阶技能，实际 %d" % [String(class_id), covered])
	_check(SkillProgression.default_rank("spirit_storm", 39) == 0 and SkillProgression.default_rank("spirit_storm", 40) == 1,
		"技能解锁前为 0 阶，解锁后默认 1 阶")
	for raw in config:
		var sid := String(raw.skillId)
		var base: Dictionary = DataLoader.get_entry("skills", sid)
		_check(SkillProgression.max_rank(sid) == 5, "%s 最多 5 阶" % sid)
		_check(SkillProgression.resolve(sid, 1).get("coefficient") == base.get("coefficient"), "%s 的 1 阶保持基准" % sid)
		_check(SkillProgression.resolve(sid, 6).is_empty(), "%s 拒绝越界阶数" % sid)
		var top := SkillProgression.resolve(sid, 5)
		# 工程 98：buff 升阶升的是**效果键**，没有伤害系数。两个职业的 buff 各断言自己的键 ——
		# 只写 `if sid == "battle_focus"` 会让魔法盾落进 else 分支去读不存在的 `coefficient`。
		if String(base.get("kind", "")) == "buff":
			var effects: Dictionary = top.effects
			if sid == "battle_focus":
				# 工程 107：战意觉醒不再给攻击，改成「减伤 + 攻速」。用 `.get()` 而不是 `.attackPct`：
				# 点语法访问缺失键会 SCRIPT ERROR 并返回 null，整条用例链静默报废。
				_check(is_equal_approx(float(effects.get("damageReducePct", 0.0)), 0.28)
					and is_equal_approx(float(effects.attackSpeedPct), 0.19), "战意觉醒 5 阶效果（减伤 28% / 攻速 19%）")
				_check(not effects.has("attackPct"),
					"战意觉醒不应再有 attackPct：减伤已经占满这个槽位，两套输出口径并存会让定位重新模糊")
			elif sid == "magic_shield":
				_check(is_equal_approx(float(effects.get("damageToManaPct", 0.0)), 0.47), "魔法盾 5 阶转嫁")
			else:
				_check(false, "%s 是 buff 但本用例没有为它写 5 阶判据（新增 buff 时必须补）" % sid)
		else:
			_check(is_equal_approx(float(top.coefficient), float(base.coefficient) * 1.12), "%s 的 5 阶伤害增幅受限" % sid)
			# `get()` 而不是 `.range`：没有射程字段的技能（自施法）两侧同为空，仍算「没暗改」。
			_check(int(top.get("hits", 1)) == int(base.get("hits", 1)) and top.get("range") == base.get("range")
				and top.cooldown == base.cooldown and top.manaCost == base.manaCost, "%s 不暗改段数/射程/冷却/耗蓝" % sid)
			# 工程 107（B2-d）：debuff 也随阶成长。三件事各断一次 ——
			# ① 类型不变；② 幅度**变强**（保留系数更小）；③ 是独立副本（`_resolved` 是共享缓存，
			# 裸引用会被下游改脏，且下一次解析拿到的就是脏数据）。
			if base.has("debuff"):
				var base_db: Dictionary = base.debuff
				var top_db: Variant = top.get("debuff")
				_check(top_db is Dictionary
					and String((top_db as Dictionary).get("type", "")) == String(base_db.get("type", "")),
					"%s 的 5 阶 debuff 类型应与基础表一致" % sid)
				_check(not is_same(top_db, base_db), "%s 的 5 阶 debuff 必须是独立副本" % sid)
				# 只有破甲有「幅度」概念（防御保留系数）；减速的 value 是控制强度，本工程不动。
				# 不加这一条分支会让冰咆哮被判成「破甲变弱」，而它根本没有 defenseScale 字段。
				if String(base_db.get("type", "")) == "armorBreak":
					var base_keep := float(base_db.get("defenseScale", 1.0))
					var top_keep := 1.0
					if top_db is Dictionary:
						top_keep = float((top_db as Dictionary).get("defenseScale", 1.0))
					_check(top_keep < base_keep,
						"%s 的 5 阶破甲应更强（保留系数 %.2f 应 < 基础 %.2f）" % [sid, top_keep, base_keep])
					_check(is_equal_approx(top_keep, 0.58),
						"%s 的 5 阶破甲保留系数应为 0.58（−42%%），实际 %.2f" % [sid, top_keep])
				else:
					_check(top_db is Dictionary
						and is_equal_approx(float((top_db as Dictionary).get("value", 0.0)), float(base_db.get("value", 0.0))),
						"%s 的 5 阶控制强度应保持不变（本工程只改破甲幅度）" % sid)
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
