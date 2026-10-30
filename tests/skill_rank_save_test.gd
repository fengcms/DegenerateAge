extends Node
## 技能升阶交易与存档回归：验证金币/阶数原子结算、旧档迁入和非法升阶拒读。
## 在隔离项目中运行，只调用存档采集与校验，不写正式玩家槽位。

var _failures: Array[String] = []
var _rank_events := 0

## 在 L15 购买裂地斩 2 阶，并用 schema 14 快照验证现有角色无损迁移。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 15
	GameState.gold = 1499
	EventBus.skill_rank_changed.connect(_on_rank_changed)
	_check(GameState.skill_rank("earth_cleave") == 1 and GameState.skill_rank("spirit_storm") == 0,
		"按角色等级提供 0/1 阶默认值")
	_check(not bool(GameState.buy_skill_rank("earth_cleave").get("ok", false)) and GameState.gold == 1499
		and _rank_events == 0, "金币不足不扣费也不广播")
	GameState.gold = 1500
	GameState.skill_cooldowns["earth_cleave"] = 2.5
	var bought := GameState.buy_skill_rank("earth_cleave")
	_check(bool(bought.get("ok", false)) and GameState.skill_rank("earth_cleave") == 2 and GameState.gold == 0,
		"购买成功一次提交金币与阶数")
	_check(_rank_events == 1 and is_equal_approx(float(GameState.skill_cooldowns.earth_cleave), 2.5),
		"购买只广播一次且不重置冷却")
	_check(String(GameState.buy_skill_rank("earth_cleave").get("reason", "")) == "level"
		and GameState.skill_rank("earth_cleave") == 2 and GameState.gold == 0 and _rank_events == 1,
		"重复购买不能越过下一阶等级门槛")
	var current := SaveManager._collect()
	_check(SaveManager._is_valid_save(current) and int(current.skillRanks.earth_cleave) == 2,
		"当前版本完整保存已购买阶数")
	var old := current.duplicate(true)
	old.schemaVersion = 14
	old.erase("skillRanks")
	_check(SaveManager._is_valid_save(old), "schema 14 存量角色可读")
	var migrated := SaveManager._migrate(old)
	_check(migrated.skillRanks.is_empty() and int(migrated.schemaVersion) == 16
		and SaveManager._migrate(migrated) == migrated, "旧档幂等补空升阶记录")
	SaveManager.apply_to_game_state(old)
	_check(GameState.skill_ranks.is_empty() and GameState.skill_rank("earth_cleave") == 1,
		"旧档读入后保留原有技能解锁且不赠送购买阶数")
	for invalid_rank in [1, 6, 2.5, "2"]:
		var bad := current.duplicate(true)
		bad.skillRanks.earth_cleave = invalid_rank
		_check(not SaveManager._is_valid_save(bad), "拒绝非法阶数 %s" % str(invalid_rank))
	var unknown := current.duplicate(true)
	unknown.skillRanks["unknown_skill"] = 2
	_check(not SaveManager._is_valid_save(unknown), "拒绝未知技能 ID")
	var too_early := current.duplicate(true)
	too_early.skillRanks["earth_cleave"] = 5
	_check(not SaveManager._is_valid_save(too_early), "拒绝未达到购买等级的高阶技能")
	if _failures.is_empty():
		print("SkillRankSaveTest: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)

## 只统计真实购买成功事件，检测失败分支是否提前通知界面或自动存档。
func _on_rank_changed(_skill_id: String, _rank: int) -> void:
	_rank_events += 1

## 累积断言失败，便于同轮找出校验遗漏。
func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
