extends Node
## 工程 82：聚金地脉「超杀保护（伤害封顶）」与「金脉守卫」的数值契约。8 组用例。
##
## 三条最值钱的断言：
## 1. **组 3「技能不再一刀秒」** —— 满配玩家（传说 12★）对均值怪的裂地斩从 1 击变 2 击。
##    这是需求的原始动机；只断「伤害数字被截」是假绿（飘字本来就不变）。
## 2. **组 4「弱装不误伤」** —— `common` 12 击、`rare` 4 击在封顶前后**逐值不变**。
##    任何「给所有怪加血」的替代方案都会让这两档变慢，本条是它唯一的硬证据。
## 3. **组 5/6「Boss 档零影响」** —— Boss 实例的 `damage_cap_pct` 恒 0，且 `PaceTest`
##    三位击杀数字逐值不变（封顶放错层 / 误伤 Boss 时必红）。
##
## 🔴 封顶只能验「扣血量」，不能验「伤害数字」：`Fx.damage_number` 与 `damage_dealt`
##    都在 `take_hit` **之前**用原始 result 发出（工程 82 §4.3 的刻意设计）。

## 装备 kind → 槽位 id（十部位，护腕 / 护膝 / 手镯 / 戒指各两格）。
const SLOT_MAP := {
	"weapon": ["weapon"], "shield": ["shield"], "helmet": ["helmet"],
	"armor": ["armor"], "shoes": ["shoes"], "necklace": ["necklace"],
	"bracer": ["bracer_1", "bracer_2"], "knee": ["knee_1", "knee_2"],
	"bracelet": ["bracelet_1", "bracelet_2"], "ring": ["ring_1", "ring_2"],
}
## 打金图等级门槛，也是本测试的采样等级（玩家与怪同乘 `Balance.scale`，比值与等级无关）。
const SAMPLE_LEVEL := 80
## 产品 13 §2.3 的 Boss 基线（`PaceTest` 同源）。
const BOSS_NORM_HP := 24300.0
const BOSS_NORM_DEF := 141.0

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[GoldFieldCapTest] " + label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _ready() -> void:
	_test_pure_cap()
	_test_monster_hit()
	_test_skill_no_one_shot()
	_test_weak_gear_untouched()
	_test_boss_untouched()
	_test_spawner_passthrough()
	_test_guard_scaling()
	_test_multi_hit_cap()
	_test_migration_once()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[GoldFieldCapTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[GoldFieldCapTest] 失败 %d 项 ❌" % failures.size())
		get_tree().quit(1)

# ---- 装备装配（真实模板与真实聚合，不硬编码推导值）----

func _dynamic_ids() -> Array:
	var out: Array = []
	var rows: Variant = DataLoader.get_table("equipments")
	if rows is Array:
		for row in rows:
			if not row is Dictionary:
				continue
			var bases: Variant = (row as Dictionary).get("tierBases", {})
			if bases is Dictionary and (bases as Dictionary).size() == 1 and (bases as Dictionary).has("51"):
				out.append(String((row as Dictionary).get("id", "")))
	return out

## 穿满 14 槽。`star` 是实例字段，工厂恒出 0★，这里按档位改写（与真实掉落同理）。
func _dress(level: int, quality: String, star: int) -> void:
	GameState.equipment = {}
	var seed := 8200 + level
	for id in _dynamic_ids():
		var tpl: Variant = DataLoader.get_entry("equipments", id)
		if not tpl is Dictionary:
			continue
		var slots: Array = SLOT_MAP.get(String((tpl as Dictionary).get("slot", "")), [])
		if slots.is_empty():
			continue
		var item: Dictionary = ItemFactory.make_equip_dynamic(id, level, quality, _rng(seed))
		if item.is_empty():
			continue
		item["star"] = star
		for slot_id in slots:
			GameState.equipment[slot_id] = item

func _setup(level: int, quality: String, star: int) -> void:
	GameState.reset_to_defaults()
	GameState.player.level = level
	GameState.player.attack = Balance.base_attack(level)
	GameState.player.defense = Balance.base_defense(level)
	_dress(level, quality, star)
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()

## 打金图 8 种普通怪的 norm 均值（血量 / 防御），数据源与 `Endgame.norm` 同源。
## 🔴 怪种集合必须从**地图的 spawnPoints** 取，不能按 `c6_` 前缀过滤：工程 83 换掉两只
## 远程怪后，前缀过滤只剩 6 种，均值从 2,112 悄悄变成 2,269 —— 断言里那些「按均值怪算出的
## 击数」会全部跟着漂移，而且报错指向的是「应有 8 种」，不是「均值变了」。
func _gold_norm_avg() -> Dictionary:
	var hp_sum := 0.0
	var def_sum := 0.0
	var n := 0
	var gold: Variant = DataLoader.get_entry("maps", "c7_gold_field")
	if gold is Dictionary:
		for group in (gold as Dictionary).get("spawnPoints", []):
			if not group is Dictionary:
				continue
			var norm := Endgame.norm(String((group as Dictionary).get("monsterId", "")))
			if not norm.has("hp"):
				continue
			hp_sum += float(norm.get("hp", 0.0))
			def_sum += float(norm.get("def", 0.0))
			n += 1
	return {"hp": hp_sum / float(maxi(1, n)), "def": def_sum / float(maxi(1, n)), "count": n}

## 一次命中打出的原始伤害（`Combat` 公式的确定性部分，不做暴击 / 闪避抽样）。
func _raw_hit(coefficient: float, def_norm: float, scale: float) -> int:
	var defense := def_norm * scale
	return maxi(1, int(round(float(GameState.total_attack()) * coefficient - defense * 0.5)))

## 击杀一只怪需要几次命中（封顶生效时单次不超过 `hp × cap`）。
func _hits_to_kill(hp: int, hit: int, cap_pct: float) -> int:
	var capped := Monster.capped_damage(hit, hp, cap_pct)
	return int(ceil(float(hp) / float(maxi(1, capped))))

# ---- 1) 纯函数边界 ----

func _test_pure_cap() -> void:
	check(Monster.capped_damage(5800, 7478, 0.0) == 5800, "cap 0（缺省）必须原样返回")
	check(Monster.capped_damage(5800, 7478, 0.5) == 3739, "cap 0.5 应截到 3739，实际 %d"
		% Monster.capped_damage(5800, 7478, 0.5))
	check(Monster.capped_damage(1000, 7478, 0.5) == 1000, "伤害低于上限时不得改动")
	check(Monster.capped_damage(5800, 0, 0.5) == 5800, "max_hp 尚未结算（0）时不得截断")
	check(Monster.capped_damage(0, 7478, 0.5) == 0, "0 伤害保持 0")
	check(Monster.capped_damage(999999, 100, 0.001) == 1, "极小比例也要保证至少 1 点（否则永不掉血）")

# ---- 2) 真实 Monster 的扣血（唯一入口）----

func _test_monster_hit() -> void:
	var scene: PackedScene = load("res://scenes/entities/Monster.tscn")
	var m: Monster = scene.instantiate()
	add_child(m)
	m.max_hp = 7478
	m.hp = 7478
	m.damage_cap_pct = 0.5
	var result := {"damage": 5800, "miss": false}
	m.take_hit(result, null)
	check(m.hp == 7478 - 3739, "封顶时扣血应为 3739，实际扣 %d" % (7478 - m.hp))
	check(int(result.get("damage", 0)) == 5800,
		"take_hit 不得改写 result —— 飘字与 damage_dealt 必须仍是真实伤害")
	m.hp = 7478
	m.damage_cap_pct = 0.0
	m.take_hit({"damage": 5800, "miss": false}, null)
	check(m.hp == 7478 - 5800, "cap 0 时应扣满 5800，实际扣 %d" % (7478 - m.hp))
	m.queue_free()

# ---- 3) 满配玩家：技能不再一刀秒（需求的原始动机）----

func _test_skill_no_one_shot() -> void:
	var avg := _gold_norm_avg()
	check(int(avg.get("count", 0)) == 8, "打金图应有 8 种普通怪，实际 %d" % int(avg.get("count", 0)))
	var scale := Balance.scale(SAMPLE_LEVEL - 60)
	var hp := int(round(float(avg.get("hp", 0.0)) * scale))
	_setup(SAMPLE_LEVEL, "legendary", 12)
	var basic := _raw_hit(1.0, float(avg.get("def", 0.0)), scale)
	var cleave := _raw_hit(1.4, float(avg.get("def", 0.0)), scale)
	print("[GoldFieldCapTest] 满配 L%d 总攻 %d，均值怪 %d 血；普攻 %d / 裂地斩 %d"
		% [SAMPLE_LEVEL, GameState.total_attack(), hp, basic, cleave])
	# 未封顶：普攻 2 击、裂地斩 1 击（这就是「技能一刀秒」）。
	check(_hits_to_kill(hp, basic, 0.0) == 2, "未封顶时满配普攻应为 2 击，实际 %d"
		% _hits_to_kill(hp, basic, 0.0))
	check(_hits_to_kill(hp, cleave, 0.0) == 1, "未封顶时裂地斩应为 1 击（一刀秒），实际 %d"
		% _hits_to_kill(hp, cleave, 0.0))
	# 封顶 0.5：两者都变 2 击 —— 技能不再一击结束战斗。
	check(_hits_to_kill(hp, basic, 0.5) == 2, "封顶后满配普攻应仍为 2 击，实际 %d"
		% _hits_to_kill(hp, basic, 0.5))
	check(_hits_to_kill(hp, cleave, 0.5) == 2, "封顶后裂地斩应升到 2 击（不再一刀秒），实际 %d"
		% _hits_to_kill(hp, cleave, 0.5))
	GameState.skill_ranks["earth_cleave"] = 5
	var max_rank_cleave := SkillProgression.current("earth_cleave")
	var max_rank_hit := _raw_hit(float(max_rank_cleave.get("coefficient", 0.0)),
		float(avg.get("def", 0.0)), scale)
	check(_hits_to_kill(hp, max_rank_hit, 0.5) == 2,
		"5 阶裂地斩仍需 2 击（升阶不能越过打金图超杀保护），实际 %d"
		% _hits_to_kill(hp, max_rank_hit, 0.5))
	# 2.0 系数的破甲重击同理（系数越高，未封顶时秒得越彻底）。
	var break_hit := _raw_hit(2.0, float(avg.get("def", 0.0)), scale)
	check(_hits_to_kill(hp, break_hit, 0.5) == 2, "封顶后破甲重击应为 2 击，实际 %d"
		% _hits_to_kill(hp, break_hit, 0.5))

# ---- 4) 弱装不误伤（封顶前后逐值不变）----

func _test_weak_gear_untouched() -> void:
	var avg := _gold_norm_avg()
	var scale := Balance.scale(SAMPLE_LEVEL - 60)
	var hp := int(round(float(avg.get("hp", 0.0)) * scale))
	# 绝对值只做「弱装必须明显慢」的下界（实测 L80 装配：common 14 击 / rare 7 击；
	# 工程 82 §1.3 的 12 / 4 击是不同装配口径的估算）。真正的硬判据是**逐值不变** +
	# 「单次伤害本就低于上限时 cap 必须原样放行」。
	for preset in [["common", 0, 10], ["rare", 6, 4]]:
		_setup(SAMPLE_LEVEL, String(preset[0]), int(preset[1]))
		var hit := _raw_hit(1.0, float(avg.get("def", 0.0)), scale)
		var before := _hits_to_kill(hp, hit, 0.0)
		var after := _hits_to_kill(hp, hit, 0.5)
		print("[GoldFieldCapTest] %s %d★ 单次 %d / 怪 %d 血 ⇒ 封顶前 %d 击、封顶后 %d 击"
			% [preset[0], preset[1], hit, hp, before, after])
		check(before >= int(preset[2]),
			"%s %d★ 未封顶普攻应 ≥ %d 击（弱装本就慢），实际 %d"
			% [preset[0], preset[1], preset[2], before])
		check(after == before,
			"%s %d★ 封顶后击数必须逐值不变（%d → %d）" % [preset[0], preset[1], before, after])
		# 🔴 结构判据（不依赖击数绝对值）：伤害没超上限时 cap 必须一位不改。
		check(Monster.capped_damage(hit, hp, 0.5) == hit,
			"%s %d★ 的单次伤害 %d 低于上限 %d，cap 必须原样放行（截了就误伤弱装）"
			% [preset[0], preset[1], hit, int(round(float(hp) * 0.5))])

# ---- 5) Boss 档零影响 ----

func _test_boss_untouched() -> void:
	var scale := Balance.scale(SAMPLE_LEVEL - 60)
	var hp := int(round(BOSS_NORM_HP * scale))
	for preset in [["common", 0], ["legendary", 12]]:
		_setup(SAMPLE_LEVEL, String(preset[0]), int(preset[1]))
		var hit := _raw_hit(1.0, BOSS_NORM_DEF, scale)
		var before := _hits_to_kill(hp, hit, 0.0)
		var after := _hits_to_kill(hp, hit, 0.5)
		check(after == before,
			"Boss %s %d★ 的击数必须逐值不变（%d → %d）—— cap 只对地图普通怪生效"
			% [preset[0], preset[1], before, after])
	# 满配打 Boss 仍应是「十几刀」，不该被收拢后的普通怪数值绑架。
	_setup(SAMPLE_LEVEL, "legendary", 12)
	check(float(hp) / float(_raw_hit(1.0, BOSS_NORM_DEF, scale)) > 10.0,
		"满配打 Boss 应仍需 10 击以上（普通怪变肉不该传导到 Boss）")

# ---- 6) spawner 透传：地图字段 → 实例字段 ----

func _test_spawner_passthrough() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c7_gold_field"
	GameState.player["level"] = SAMPLE_LEVEL
	var gold := MonsterSpawner.new()
	add_child(gold)
	gold.setup(null, null)
	gold.spawn_from_map("c7_gold_field")
	var capped := 0
	var uncapped := 0
	var guard := 0
	for point in gold._points:
		var cap := float(point.get("damage_cap_pct", -1.0))
		if cap <= 0.0:
			uncapped += 1
		else:
			capped += 1
		# 守卫计数看**点规格**而不是存活实例：`normalCap 32` 只装配 32 只，
		# 按实例统计会把 24 席守卫误算成 12 席（假红）。
		if is_equal_approx(float(point.get("hp_multiplier", 1.0)), 6.0):
			guard += 1
	check(capped + uncapped == 96, "打金图应装配 96 个点，实际 %d" % (capped + uncapped))
	check(uncapped == 0, "打金图全部普通怪都应带 cap，实际有 %d 点未带" % uncapped)
	check(guard == 24, "金脉守卫应 24 席，实际 %d" % guard)
	var sample: Monster = null
	for point in gold._points:
		var m: Monster = point.get("entry", null)
		if m != null:
			sample = m
			break
	check(sample != null and is_equal_approx(sample.damage_cap_pct, 0.5),
		"实例的 damage_cap_pct 应为 0.5")
	gold.queue_free()
	# Boss 图完全不带 cap（两道条件中的第二道：非 normal 档恒 0）。
	GameState.current_map = "c7_boss_field"
	var boss := MonsterSpawner.new()
	add_child(boss)
	boss.setup(null, null)
	var boss_map: Dictionary = DataLoader.get_entry("maps", "c7_boss_field")
	boss.spawn_from_specs(boss_map.get("bossSpawns", []), "c7_boss_field")
	var leaked := 0
	for point in boss._points:
		if float(point.get("damage_cap_pct", 0.0)) > 0.0:
			leaked += 1
	check(leaked == 0, "百首禁域的 Boss 不得带 cap，实际 %d 席带上了" % leaked)
	boss.queue_free()

# ---- 7) 金脉守卫：血 ×6、金币 ×4 ----

func _test_guard_scaling() -> void:
	var norm := Endgame.norm("c6_normal02")
	check(norm.has("hp"), "守卫 c6_normal02 应有归一化数值")
	var scale := Balance.scale(SAMPLE_LEVEL - 60)
	var base_hp := int(round(float(norm.get("hp", 0.0)) * scale))
	var guard_hp := base_hp * 6
	_setup(SAMPLE_LEVEL, "legendary", 12)
	var hit := _raw_hit(1.0, float(norm.get("def", 0.0)), scale)
	var hits := _hits_to_kill(guard_hp, hit, 0.5)
	print("[GoldFieldCapTest] 守卫 %d 血，满配普攻 %d 击" % [guard_hp, hits])
	check(hits >= 8 and hits <= 12, "守卫应需 8—12 击（满配），实际 %d 击" % hits)
	# 金币：守卫单价四倍于普通（440–560 → 1760–2240），且装备必掉。
	var normal: Dictionary = DataLoader.get_entry("dropTables", "DT_C7_Gold_Normal")
	var guard: Dictionary = DataLoader.get_entry("dropTables", "DT_C7_Gold_Guard")
	var n_coin: Array = (normal.get("entries", [])[0] as Dictionary).get("goldRange", [])
	var g_coin: Array = (guard.get("entries", [])[0] as Dictionary).get("goldRange", [])
	check(int(g_coin[0]) == int(n_coin[0]) * 4 and int(g_coin[1]) == int(n_coin[1]) * 4,
		"守卫金币应为普通怪的四倍，实际 %s vs %s" % [str(g_coin), str(n_coin)])
	# 🔴 这个比值是刻意的（R-10）：血 ×6 而金 ×4 ⇒ 单位时间金币 ≈ ×0.67。
	check(6.0 / 4.0 > 1.0, "守卫必须比普通怪更费时（否则「掉落更好」的定位失效）")

# ---- 8) 多段技能：每段各自受 cap（高攻速仍更快）----

func _test_multi_hit_cap() -> void:
	var hp := 7478
	var per_hit := Monster.capped_damage(5800, hp, 0.5)
	var total := 0
	var hits := 0
	while total < hp and hits < 10:
		total += per_hit
		hits += 1
	check(hits == 2, "3 段技能每段受 cap ⇒ 两段即杀（不能因封顶变成 6 段），实际 %d" % hits)
	check(per_hit * 3 >= hp, "三段各扣 3739 应超过 7478 血（多段仍有优势）")

# ---- 9) 老存档迁移：一次性门（重复读档不得继续缩）----

## 🔴 这是「缩图」独有的事故形态：迁移若无门，玩家每次登录坐标都按 64/160 再缩一次，
## 二十次登录后跑到图左上角。判据必须包含「第二次迁移逐值不变」，只看「第一次映射到了图内」是假绿。
func _test_migration_once() -> void:
	# 旧图 160×90 的战场中心格 (80,45) 的世界坐标。
	var legacy := Iso.grid_to_world(Vector2i(80, 45))
	var key := "c7_gold_field#c6_normal01#0"
	var data := {
		"schemaVersion": SaveManager.CURRENT_SCHEMA,
		"currentMap": "c7_gold_field",
		"playerPos": [legacy.x, legacy.y],
		"spawnRespawn": {key: {"remaining": 1.0, "pos": [legacy.x, legacy.y]}},
		"unclaimedLoot": {"c7_gold_field": [{"uid": "u_82", "pos": [legacy.x, legacy.y]}]},
	}
	var once: Dictionary = SaveManager._migrate(data)
	check(String(once.get("c7GoldLayoutVersion", "")) == SaveManager.CURRENT_C7_GOLD_LAYOUT_VERSION,
		"迁移后应写入 c7GoldLayoutVersion，实际「%s」" % once.get("c7GoldLayoutVersion"))
	var size := MapService.grid_size("c7_gold_field")
	check(size.x == 64 and size.y == 48, "新图尺寸应为 64×48，实际 %s" % str(size))
	var cell := Iso.world_to_grid(Vector2(float(once.playerPos[0]), float(once.playerPos[1])))
	check(cell.x >= 0 and cell.x < size.x and cell.y >= 0 and cell.y < size.y,
		"迁移后玩家坐标应落在 64×48 内，实际 %s" % str(cell))
	var twice: Dictionary = SaveManager._migrate(once)
	check(twice.playerPos == once.playerPos,
		"重复迁移不得再缩（一次性门失效即坐标持续漂移）：%s → %s"
		% [str(once.playerPos), str(twice.playerPos)])
	var twice_cell := Iso.world_to_grid(Vector2(float(twice.playerPos[0]), float(twice.playerPos[1])))
	check(twice_cell == cell, "重复迁移后落点应不变，实际 %s vs %s" % [str(twice_cell), str(cell)])
	var once_pos: Variant = (once.get("spawnRespawn", {}) as Dictionary).get(key, {}).get("pos")
	var twice_pos: Variant = (twice.get("spawnRespawn", {}) as Dictionary).get(key, {}).get("pos")
	check(once_pos == twice_pos, "墓碑坐标重复迁移不得再缩：%s → %s" % [str(once_pos), str(twice_pos)])
	var once_loot: Variant = (once.get("unclaimedLoot", {}) as Dictionary).get("c7_gold_field", [])
	var twice_loot: Variant = (twice.get("unclaimedLoot", {}) as Dictionary).get("c7_gold_field", [])
	var once_loot_pos: Variant = (once_loot as Array)[0].get("pos") if once_loot is Array and not (once_loot as Array).is_empty() else null
	var twice_loot_pos: Variant = (twice_loot as Array)[0].get("pos") if twice_loot is Array and not (twice_loot as Array).is_empty() else null
	check(once_loot_pos == twice_loot_pos, "地面掉落坐标重复迁移不得再缩：%s → %s"
		% [str(once_loot_pos), str(twice_loot_pos)])
