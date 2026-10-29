extends Node
## 工程 98 §5.1：职业平衡契约（五条判据，断的是**结果**不是系数）。
##
## 为什么单独一个文件：`class_frame_test` 守的是**系数有没有乘上去**（0.64 / 2.0 / 1.08），
## 它守不住「法师是不是强到没人想玩武士」。两者会在这些情况下分叉：
##   · 有人把 `atkMult` 从 1.08 调到 1.30 —— 系数测试跟着改一行就绿，平衡直接崩；
##   · 有人调了 Boss 数值表 / 装备防御公式 —— 系数一个都没动，两职业实际体验全变。
## 所以这里只断：击杀耗时比、掉血比（开盾 / 断盾）、蓝药消耗、金币收益比。
##
## 🔴 **玩家侧用实测快照常数，绝不在测试里造装备**：工程 94 踩过 —— `ItemFactory`
##    造的 140 级紫 12 星跑出 103 万血（真实 40.8 万）、防御多 11%。而承伤是**差值**
##    公式，防御多 11% 就能让每击腰斩 ⇒ 造出来的玩家不是玩家。真实属性取决于玩家
##    实际词条骰子，造不出来。玩家升级 / 换装后请重跑 `tools/class_balance_probe`
##    并更新下方 `SNAPSHOT_*`。
##
## 🔴 **Boss 侧相反，必须走完整生产链路**（真实例化 → `Endgame.norm` → `Balance.scale`
##    → `atk_multiplier`）。漏了 `stat_norm` 会静默走 `elif scale_stats` 分支，
##    同一只怪攻击从 26,174 变 1,371，结论完全相反（`spawner.gd` 第 100 行同源）。
##
## 注：下面五条判据**全是比值**，所以 `max_hp` 的绝对值不参与任何断言。装备只通过
##     两个口子影响结果：`max_mp`（决定蓝药瓶数）与 `attack`/`defense`（决定破防），
##     这两处用快照钉死即可复现真实体感。

## 玩家侧快照：160 级真实存档（`slot_3`）的派生值，与 `tools/class_balance_probe` 同源。
const LEVEL := 160
const SNAPSHOT_ATTACK := 55661.0
const SNAPSHOT_DEFENSE := 62629.0
## 装备提供的法力固定加成（真实存档 `equip_bonus().mp` 折算值）。
## 🔴 这条不能省：裸装 160 级蓝池只有 830 点，武士放一轮技能就要 1.5 瓶蓝 ⇒
##    「武士蓝药消耗 = 0」会假红，而假红会诱使人去把判据放宽（第 46 条）。
const SNAPSHOT_MP_FLAT := 75836.0

## §5.1 判据（改这些数字 = 改产品定位，必须走产品文档评审）。
const TTK_RATIO_MIN := 0.90        ## 法师快 0—10%：烧蓝换速度，「值得玩」但不至于武士没人玩
const TTK_RATIO_MAX := 1.00        ## 超过 1.0 = 法师又慢又费蓝，这个职业没有存在理由
const SHIELD_DROP_MIN := 0.85      ## 开盾掉血比 0.85—1.15 = 「用蓝买回来的血，约等于持平」
const SHIELD_DROP_MAX := 1.15
const BARE_DROP_MIN := 1.50        ## 断盾掉血比：无盾必须明显更脆，否则盾没有存在意义
const GOLD_RATIO_MIN := 0.95       ## 职业不能变成收益倍率
const GOLD_RATIO_MAX := 1.05

## Boss 出手率（技能动作 / 走位期间不出普攻）。工程 92 实测 14.7 秒挨 4.5 击。
const HIT_RATE := 0.55
## 蓝药按**最大瓶**折算瓶数：这是对「法师要喝药」最宽松的口径 ——
## 连最大的瓶子都撑不住，小瓶子更撑不住。武士则相反，用最宽松口径仍然是 0 瓶才算过。
const MANA_POTION := "potion_mp_large"
## 金币用固定种子：两职业必须抽出**逐件相同**的战利品（职业不得参与收益计算）。
const GOLD_SEED := 20261022

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ClassBalanceTest] " + label)

func _ready() -> void:
	var boss := _measure_boss()
	if boss.is_empty():
		check(false, "读不到 c7_boss_field 的 bossSpawns，无法做平衡判据")
	else:
		var rows := {}
		for class_id in PlayerClass.ids():
			rows[String(class_id)] = _measure(String(class_id), boss)
		_test_kill_time(rows)
		_test_shielded_drop(rows)
		_test_bare_drop(rows)
		_test_mana_bottles(rows)
		_test_gold(boss)
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[ClassBalanceTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[ClassBalanceTest] 失败 %d 项" % failures.size())
		for f in failures:
			print("  - " + f)
		get_tree().quit(1)

# ---- 夹具 ----

## 代表 Boss：**真实例化**一只，然后把它的生产数值拿出来。
##
## 选哪一只：取 `c7_boss_field` 席位里**出现次数最多**的怪 + 全部席位里**最低**的攻击 /
## 血量倍率。不写死 id 与倍率 —— 调了配置本测试要跟着走；取最低倍率是不让「某席配错
## 高倍率」把整体抬过去（那会让判据看起来更宽松，实际是拿错了分母 —— 第 36 条同形）。
func _measure_boss() -> Dictionary:
	var map_data: Variant = DataLoader.get_entry("maps", "c7_boss_field")
	if not (map_data is Dictionary):
		return {}
	var seats: Array = (map_data as Dictionary).get("bossSpawns", [])
	if seats.is_empty():
		return {}
	var counts := {}
	var lowest_atk := INF
	var lowest_hp := INF
	for raw in seats:
		if not (raw is Dictionary):
			continue
		var seat: Dictionary = raw
		var mid := String(seat.get("monsterId", ""))
		counts[mid] = int(counts.get(mid, 0)) + 1
		lowest_atk = minf(lowest_atk, float(seat.get("atkMultiplier", 1.0)))
		lowest_hp = minf(lowest_hp, float(seat.get("hpMultiplier", 1.0)))
	var rep := ""
	var rep_count := 0
	for raw_key in counts.keys():
		if int(counts[String(raw_key)]) > rep_count:
			rep = String(raw_key)
			rep_count = int(counts[String(raw_key)])
	if rep.is_empty():
		return {}
	var from_player: Variant = (map_data as Dictionary).get("levelFromPlayer", {})
	var min_level := Balance.SOFTCAP_LEVEL
	if from_player is Dictionary:
		min_level = int((from_player as Dictionary).get("minLevel", Balance.SOFTCAP_LEVEL))

	var m := Monster.new()
	m.monster_id = rep
	m.spawn_level = maxi(min_level, LEVEL)
	m.stat_norm = Endgame.norm(rep)
	m.atk_multiplier = lowest_atk
	m.hp_multiplier = lowest_hp
	m.scale_stats = true
	add_child(m)
	var info := {
		"id": rep, "level": m.level,
		"atk": float(m.attack_power), "hp": float(m.max_hp),
		"def": float(m.defense_power),
		"interval": float(m.attack_interval),
		"drop_table": String(DataLoader.get_entry("monsters", rep).get("dropTableId", "")),
	}
	m.free()
	return info

## 把玩家摆成「快照里的那个 160 级角色」：只设基础攻防与法力固定加成，装备栏清空
## （套装加成 1+pct 恒等，派生结果与带装一致）。
## 这样 `total_attack()` / `max_mp()` / `max_hp()` 仍然**走真实派生门面**，职业系数由
## 生产代码乘上去，而不是在这里手工乘一遍 —— 手工乘会漏掉「系数该乘在哪一层」，
## 那正是 R1 要守的东西。
func _setup(class_id: String) -> void:
	GameState.reset_to_defaults(class_id)
	GameState.current_map = "wild_trial"
	GameState.player.level = LEVEL
	GameState.player.attack = SNAPSHOT_ATTACK
	GameState.player.defense = SNAPSHOT_DEFENSE
	GameState.player.mpFlat = SNAPSHOT_MP_FLAT
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()

func _make_player() -> PlayerCharacter:
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(4000, 4000)
	return player

# ---- 单职业测量 ----

func _measure(class_id: String, boss: Dictionary) -> Dictionary:
	_setup(class_id)
	var player := _make_player()
	var max_hp := float(GameState.max_hp())
	var max_mp := float(GameState.max_mp())
	var attack := float(GameState.total_attack())
	var interval := maxf(0.01, GameState.total_attack_interval())
	var per_hit_in := _per_hit_in(boss, max_hp)
	# 有盾的职业才开盾 —— `start_buff` 不做职业校验（低层 API），在这里替生产路径把关：
	# 生产上武士根本拿不到这个技能格（`HotbarConfig.usable_skill` + 快捷栏清理）。
	var has_shield := HotbarConfig.usable_skill("magic_shield", class_id)

	# 玩家 → Boss：破防是差值，所以「攻击 +8%」在高防目标上不止 8% 伤害，必须实算。
	var per_hit_out := maxf(1.0, attack - float(boss.get("def", 0.0)) * 0.5)
	var ttk := float(boss.get("hp", 1.0)) / maxf(1.0, per_hit_out / interval)

	# ① 断盾：蓝清零（盾即使是开着的也转嫁不出任何伤害），看一次受击掉多少血。
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = 0
	if has_shield:
		GameState.start_buff("magic_shield")
	var bare := player.apply_damage(per_hit_in)
	player._invuln = 0.0                        # 真实战斗里两次受击间隔远大于无敌帧
	var leaked := int(GameState.player.mp)      # 断蓝时盾不得透支 / 不得变负

	# ② 开盾：满蓝受同一击，同时量「掉多少血」与「扣多少蓝」。
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()
	player._invuln = 0.0
	var mp_before := int(GameState.player.mp)
	var shielded := player.apply_damage(per_hit_in)
	var mana_transferred := mp_before - int(GameState.player.mp)
	player.queue_free()

	# 蓝药：按「所有主动技能一到 CD 就放」的上界估算每秒支出（实际打法只会更省）。
	# 工程 103：逐项走生产费用入口；用 pct×max_mp 会在法师攻击法术上算错。
	var skill_per_sec := 0.0
	for sid in PlayerClass.active_skills(class_id):
		var tpl: Variant = DataLoader.get_entry("skills", String(sid))
		if not (tpl is Dictionary):
			continue
		var skill: Dictionary = tpl
		if bool(skill.get("basic", false)):
			continue
		var cd := maxf(1.0, float(skill.get("cooldown", 1.0)))
		skill_per_sec += float(GameState.skill_mana_cost(skill)) / cd
	# 护盾转嫁：每次受击**实测**扣蓝 × 每秒受击次数。
	var shield_per_sec := float(mana_transferred) / maxf(0.1, float(boss.get("interval", 1.2))) * HIT_RATE
	var spend := (skill_per_sec + shield_per_sec) * ttk

	var restore := max_mp * 0.2
	var potion: Variant = DataLoader.get_entry("potions", MANA_POTION)
	if potion is Dictionary:
		restore = max_mp * float((potion as Dictionary).get("restorePercent", 0.2))
	return {
		"max_hp": max_hp, "max_mp": max_mp, "attack": attack, "ttk": ttk,
		"per_hit_in": per_hit_in, "bare": bare, "shielded": shielded,
		"mana_transferred": mana_transferred, "mana_leaked": leaked,
		"mana_spend": spend, "bottles": int(floor(spend / maxf(1.0, restore))),
		"drop_per_hit": float(bare) / maxf(1.0, max_hp),
		"shield_drop_per_hit": float(shielded) / maxf(1.0, max_hp),
	}

## Boss 实攻 → 玩家实扣。走 `Combat.resolve`（与 `monster.gd` 同一条结算），
## 保底值按玩家真实血池算 —— 写死 60 会在血池变化后静默失真。
func _per_hit_in(boss: Dictionary, max_hp: float) -> int:
	var min_hit := clampi(int(round(max_hp * 0.0025)), 10, 60)
	var res := Combat.resolve(float(boss.get("atk", 0.0)), float(GameState.total_defense()),
		1.0, 0.0, 1.5, 0.0, null, min_hit)
	return int(res.get("damage", 0))

# ---- 用例 ----

## §5.1 之 1：法师击杀耗时 / 武士 ∈ [0.90, 1.00]。
func _test_kill_time(rows: Dictionary) -> void:
	var base: Dictionary = rows.get("warrior", {})
	if base.is_empty():
		check(false, "必须测出 warrior 才能算比值")
		return
	for class_id in rows.keys():
		if String(class_id) == "warrior":
			continue
		var ratio := float(rows[class_id].ttk) / maxf(0.001, float(base.ttk))
		check(ratio >= TTK_RATIO_MIN and ratio <= TTK_RATIO_MAX,
			"%s 击杀耗时比 %.3f 应 ∈ [%.2f, %.2f]（武士 %.1fs / %s %.1fs）；超出即「烧蓝换速度」不成立"
			% [String(class_id), ratio, TTK_RATIO_MIN, TTK_RATIO_MAX,
			   float(base.ttk), String(class_id), float(rows[class_id].ttk)])

## §5.1 之 2：开盾掉血比 ∈ [0.85, 1.15] —— 用蓝买回来的血，约等于持平。
## 🔴 断言方向是**掉血比**（越脆越大）。写成「存活时间比」方向就反了，
##    会变成一条永远绿的假断言（探针实测 0.985 的存活比 = 1.015 的掉血比）。
func _test_shielded_drop(rows: Dictionary) -> void:
	var base: Dictionary = rows.get("warrior", {})
	if base.is_empty():
		check(false, "必须测出 warrior 才能算比值")
		return
	for class_id in rows.keys():
		if String(class_id) == "warrior":
			continue
		var ratio := float(rows[class_id].shield_drop_per_hit) / maxf(0.0000001, float(base.drop_per_hit))
		check(ratio >= SHIELD_DROP_MIN and ratio <= SHIELD_DROP_MAX,
			"%s 开盾掉血比 %.3f 应 ∈ [%.2f, %.2f]（每击掉血 %.4f%% vs 武士 %.4f%%）；偏低=盾太强，偏高=蓝不划算"
			% [String(class_id), ratio, SHIELD_DROP_MIN, SHIELD_DROP_MAX,
			   float(rows[class_id].shield_drop_per_hit) * 100.0, float(base.drop_per_hit) * 100.0])
		# 盾必须真的在扣蓝，否则「高蓝低血」变成纯增益（R6）。
		check(float(rows[class_id].mana_transferred) > 0.0,
			"%s 开盾受击必须扣蓝（转嫁 %.0f 点）；只减伤不扣蓝 = 白送" % [
				String(class_id), float(rows[class_id].mana_transferred)])

## §5.1 之 3：断盾掉血比 ≥ 1.50 —— 无盾必须明显更脆。
## 这条同时是 `hpMult` 的守门员：`hpMult` 抬到 0.67 以上就会红（0.64 ⇒ 1.5625）。
func _test_bare_drop(rows: Dictionary) -> void:
	var base: Dictionary = rows.get("warrior", {})
	if base.is_empty():
		check(false, "必须测出 warrior 才能算比值")
		return
	for class_id in rows.keys():
		if String(class_id) == "warrior":
			continue
		var ratio := float(rows[class_id].drop_per_hit) / maxf(0.0000001, float(base.drop_per_hit))
		check(ratio >= BARE_DROP_MIN,
			"%s 断盾掉血比 %.3f 应 ≥ %.2f（每击掉血 %.4f%% vs 武士 %.4f%%）；盾没有存在意义的职业不必有盾"
			% [String(class_id), ratio, BARE_DROP_MIN,
			   float(rows[class_id].drop_per_hit) * 100.0, float(base.drop_per_hit) * 100.0])
		# 断蓝时盾必须完全失效（不是「扣一点血再转一点」）。
		check(int(rows[class_id].mana_leaked) == 0,
			"%s 蓝为 0 时盾必须一点蓝都拿不到，实际蓝条变成 %d" % [
				String(class_id), int(rows[class_id].mana_leaked)])

## §5.1 之 4：每只 Boss 蓝药消耗 —— 两职业都 > 0，且武士更省。
## 口径：击杀期间的**法力净支出** ÷ 最大瓶蓝药回蓝量，向下取整成瓶数（上界估算）。
##
## 🔴 工程 107 **反转**：武士从「固定点耗 ⇒ 0 瓶」改成百分比耗蓝。旧判据「武士 = 0 瓶」
## 不是被放宽，而是它守的那个属性本身被判定为缺陷 —— 160 级蓝池 7.6 万点，15—60 点蓝耗
## 摊薄到 0.1%，等于「法力」这个系统对武士完全不存在。
## 新判据守两件事：① 武士重新有蓝压力（> 0）；② 武士仍比法师省（< 法师），
## 否则「武士靠普攻、法师靠技能」的定位消失，两个职业只差贴图。
func _test_mana_bottles(rows: Dictionary) -> void:
	var warrior: Dictionary = rows.get("warrior", {})
	var mage: Dictionary = rows.get("mage", {})
	if warrior.is_empty() or mage.is_empty():
		check(false, "必须同时测出 warrior 与 mage")
		return
	print("[ClassBalanceTest] 蓝药瓶数｜warrior %d 瓶（支出 %.0f / 池 %.0f）｜mage %d 瓶（支出 %.0f / 池 %.0f）"
		% [int(warrior.bottles), float(warrior.mana_spend), float(warrior.max_mp),
		   int(mage.bottles), float(mage.mana_spend), float(mage.max_mp)])
	check(int(warrior.bottles) > 0,
		"武士每只 Boss 应有蓝药消耗（支出 %.0f / 蓝池 %.0f = %.1f%%）：107 之前是 0 瓶，固定点耗被大蓝池摊平了"
		% [float(warrior.mana_spend), float(warrior.max_mp),
		   float(warrior.mana_spend) / maxf(1.0, float(warrior.max_mp)) * 100.0])
	check(int(warrior.bottles) < int(mage.bottles),
		"武士应比法师省蓝（武士 %d 瓶 / 法师 %d 瓶）：否则两职业的定位差只剩贴图"
		% [int(warrior.bottles), int(mage.bottles)])
	check(int(mage.bottles) > 0,
		"法师每只 Boss 的蓝药消耗应 > 0 瓶（支出 %.0f / 蓝池 %.0f = %.1f%%）；百分比蓝耗必须真的贵，否则「高蓝」是免费属性"
		% [float(mage.mana_spend), float(mage.max_mp),
		   float(mage.mana_spend) / maxf(1.0, float(mage.max_mp)) * 100.0])

## §5.1 之 5：单只 Boss 金币收益比 ∈ [0.95, 1.05] —— 职业不能变成收益倍率。
## 用固定种子各抽一次完整掉落表：如果哪天有人把职业塞进掉落 / 售价路径，两边会分出差异。
func _test_gold(boss: Dictionary) -> void:
	var table := String(boss.get("drop_table", ""))
	var mid := String(boss.get("id", ""))
	if table.is_empty() or mid.is_empty():
		check(false, "代表 Boss 必须带 dropTableId（实际 '%s' / '%s'）" % [table, mid])
		return
	var totals := {}
	for class_id in PlayerClass.ids():
		GameState.player.classId = String(class_id)
		totals[String(class_id)] = _roll_gold(table, mid)
	var base := float(totals.get("warrior", 0))
	if base <= 0.0:
		check(false, "代表 Boss 的金币掉落必须 > 0（实际 %.0f），否则这条判据没有分母" % base)
		return
	for class_id in totals.keys():
		if String(class_id) == "warrior":
			continue
		var ratio := float(totals[class_id]) / base
		check(ratio >= GOLD_RATIO_MIN and ratio <= GOLD_RATIO_MAX,
			"%s 单只 Boss 金币 %.0f 相对武士 %.0f 的比值 %.3f 应 ∈ [%.2f, %.2f]"
			% [String(class_id), float(totals[class_id]), base, ratio, GOLD_RATIO_MIN, GOLD_RATIO_MAX])

## 固定种子抽一次掉落表，累加金币。种子每次重置 ⇒ 两职业的随机数序列逐位相同。
func _roll_gold(table: String, monster_id: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = GOLD_SEED
	var items: Array = Loot.roll(table, rng, monster_id, LEVEL)
	var total := 0.0
	for raw in items:
		if not (raw is Dictionary):
			continue
		var item: Dictionary = raw
		if String(item.get("kind", "")) == Loot.KIND_COIN:
			total += float(item.get("gold", 0))
	return total
