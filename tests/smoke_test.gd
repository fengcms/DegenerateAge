extends Node
## 无头冒烟测试（M1）。断言关键不变量，失败则以非 0 退出码结束。
##
## 运行（两步：先导入扫描，再跑测试）：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   "$GODOT" --headless --path . --import
##   "$GODOT" --headless --path . res://tests/SmokeTest.tscn
##
## 说明：--import 用于注册 class_name 全局类（Iso / IsoGround / PlayerCharacter /
## Combat / Monster / MonsterSpawner / DamageNumber / Fx / ItemUtil / Loot /
## Inventory / GroundItem / Equipment / Shop / ItemSlot / DragGhost / AutoBattle）；
## 换机或新增 class_name 后需先跑一次。

var _failures: Array[String] = []

func _ready() -> void:
	_test_data_validation()
	_test_iso_math()
	_test_stats()
	_test_combat()
	await _test_single_resolution()
	await _test_monster_chase()
	await _test_monster_attacks_player()
	await _test_death_settles_once()
	await _test_spawner()
	_test_loot()
	_test_balance_calibration()
	_test_inventory()
	await _test_pickup()
	await _test_pickup_delay()
	_test_equipment()
	_test_shop()
	await _test_trade_panel()
	_test_debug_seed()
	await _test_drag_layer()
	await _test_auto_battle()
	await _test_save()
	await _test_world()
	_finish()

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _test_data_validation() -> void:
	var report: Array[String] = DataLoader.validate_all()
	_expect(report.is_empty(), "数据校验未通过：%s" % [report])

func _test_iso_math() -> void:
	# 往返转换
	var cell := Vector2i(7, 3)
	var back := Iso.world_to_grid(Iso.grid_to_world(cell))
	_expect(is_equal_approx(back.x, float(cell.x)) and is_equal_approx(back.y, float(cell.y)),
		"等距坐标往返失败：%s -> %s" % [cell, back])
	# 公式抽查（文档 7.1：tileW=64, tileH=32）
	_expect(is_equal_approx(Iso.grid_to_world(Vector2i(1, 0)).x, 32.0), "col+1 应使 screenX +32")
	_expect(is_equal_approx(Iso.grid_to_world(Vector2i(0, 1)).x, -32.0), "row+1 应使 screenX −32")
	_expect(is_equal_approx(Iso.grid_to_world(Vector2i(1, 1)).y, -32.0), "col+row 增大应使 screenY 更小")

# ---- M1-3：属性派生与数值广播 ----
func _test_stats() -> void:
	GameState.reset_to_defaults()
	# 4.3 / 4.4：L1（攻12/防5）→ HP 102、MP 35
	_expect(GameState.max_hp() == 102, "L1 最大生命应为 102，实际 %d" % GameState.max_hp())
	_expect(GameState.max_mp() == 35, "L1 最大法力应为 35，实际 %d" % GameState.max_mp())
	_expect(int(GameState.player.hp) == GameState.max_hp(), "初始当前 HP 应等于上限")
	_expect(GameState.inventory.size() == 40, "背包应为 40 格，实际 %d" % GameState.inventory.size())

	# 数值变更应经 EventBus 广播（HUD 实时刷新链路）
	var hp_sig := [0, 0]
	EventBus.player_hp_changed.connect(func(c, m): hp_sig[0] = c; hp_sig[1] = m)
	GameState.damage_player(15)
	_expect(hp_sig[0] == 87 and hp_sig[1] == 102, "扣血应广播 87/102，实际 %s" % [hp_sig])

	var gold_sig := [0]
	EventBus.gold_changed.connect(func(v): gold_sig[0] = v)
	GameState.add_gold(50)
	_expect(gold_sig[0] == 50, "金币变更应广播，实际 %d" % gold_sig[0])
	GameState.reset_to_defaults()

# ---- M1-4：伤害公式（3.2 / 3.5 / 3.8）----
func _test_combat() -> void:
	# 基础伤害：atk12 / def2 / 系数1.0 → floor(12 − 2×0.5) = 11
	var r := Combat.resolve(12.0, 2.0, 1.0, 0.0, 1.5, 0.0)
	_expect(not r.miss and int(r.damage) == 11 and not r.critical,
		"普攻基础伤害应为 11/非暴击，实际 %s" % [r])
	# 暴击：倍数 floor(11 × 1.5) = 16。注意 3.8 暴击率上限 75%，
	# 故用固定种子跑 100 次，确定性校验「暴击=16 / 非暴击=11」两条路径。
	var crng := RandomNumberGenerator.new()
	crng.seed = 999
	var n_crit := 0
	var n_norm := 0
	for _i in range(100):
		var rc := Combat.resolve(12.0, 2.0, 1.0, 0.75, 1.5, 0.0, crng)
		if rc.critical:
			n_crit += 1
			_expect(int(rc.damage) == 16, "暴击伤害应为 16，实际 %d" % int(rc.damage))
		else:
			n_norm += 1
			_expect(int(rc.damage) == 11, "非暴击伤害应为 11，实际 %d" % int(rc.damage))
	_expect(n_crit > 0 and n_norm > 0, "100 次抽样应同时出现暴击与非暴击（暴击 %d / 普通 %d）" % [n_crit, n_norm])
	# 概率 Miss（3.5）：dodge50 → 50%；封顶 75%
	_expect(is_equal_approx(Combat.miss_chance(50.0), 0.5), "闪避 50 → Miss 应为 50%")
	_expect(is_equal_approx(Combat.miss_chance(1000.0), 0.75), "Miss 应封顶 75%")
	# 伤害下限 ≥1（3.2 约束）
	var rmin := Combat.resolve(1.0, 999.0, 1.0, 0.0, 1.5, 0.0)
	_expect(int(rmin.damage) == 1, "伤害下限应为 1，实际 %d" % int(rmin.damage))
	# 技能系数（3.3）：裂地斩 1.4 → floor(12 × 1.4 − 1) = 15
	var rs := Combat.resolve(12.0, 2.0, 1.4, 0.0, 1.5, 0.0)
	_expect(int(rs.damage) == 15, "裂地斩(1.4) 伤害应为 15，实际 %d" % int(rs.damage))

# ---- T04：单次命中只结算一次 ----
func _test_single_resolution() -> void:
	var monster = load("res://scenes/entities/Monster.tscn").instantiate()
	monster.monster_id = "training_dummy"   # hpBase 50 / defense 0
	add_child(monster)
	await get_tree().process_frame

	var hp0: int = int(monster.get("hp"))
	_expect(hp0 == 50, "木桩初始 HP 应为 50，实际 %d" % hp0)

	var res := Combat.resolve(12.0, monster.get_defense(), 1.0, 0.0, 1.5, 0.0)
	monster.take_hit(res, null)
	_expect(int(monster.get("hp")) == hp0 - int(res.damage),
		"单次命中应只扣一次血：%d -> %d（伤害 %d）" % [hp0, int(monster.get("hp")), int(res.damage)])

	monster.queue_free()
	await get_tree().process_frame

# ---- M1-5：怪物 AI 追击（7.9）----
func _test_monster_chase() -> void:
	GameState.reset_to_defaults()
	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO

	var wolf = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	wolf.ai_enabled = true
	wolf.position = Vector2(160.0, 0.0)     # 在仇恨半径内、攻击范围外
	wolf.spawn_position = Vector2(160.0, 0.0)
	add_child(wolf)
	await get_tree().physics_frame

	var d0: float = wolf.global_position.distance_to(player.global_position)
	for _i in range(20):
		await get_tree().physics_frame
	var d1: float = wolf.global_position.distance_to(player.global_position)
	_expect(d1 < d0, "怪物应朝玩家追击：距离 %0.1f -> %0.1f" % [d0, d1])
	_expect(wolf.state == wolf.State.CHASE or wolf.state == wolf.State.ATTACK,
		"怪物应处于追击/攻击态，实际 %d" % wolf.state)

	player.queue_free()
	wolf.queue_free()
	await get_tree().physics_frame

# ---- M1-5：怪物攻击玩家（3.1 敌我对等）----
func _test_monster_attacks_player() -> void:
	GameState.reset_to_defaults()
	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO

	var wolf = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	wolf.ai_enabled = true
	wolf.position = Vector2(40.0, 0.0)      # 在普攻范围内（1 格 = 64px）
	wolf.spawn_position = Vector2(40.0, 0.0)
	add_child(wolf)

	var hp0: int = int(GameState.player.hp)
	for _i in range(15):
		await get_tree().physics_frame
	_expect(int(GameState.player.hp) < hp0,
		"怪物应攻击玩家并扣血：%d -> %d" % [hp0, int(GameState.player.hp)])
	_expect(GameState.player.hp == hp0 - 5,
		"野狼(攻8) 打玩家(防5) 应为 5 点伤害，实际 %d" % [hp0 - int(GameState.player.hp)])

	# 玩家无敌帧内不应被连续命中（3.4）
	var hp_a: int = int(GameState.player.hp)
	player.apply_damage(5)   # 立即再打一次应被无敌帧挡下
	_expect(int(GameState.player.hp) == hp_a, "无敌帧内不应再次扣血")

	player.queue_free()
	wolf.queue_free()
	await get_tree().physics_frame

# ---- M1-5/M1-6：死亡结算仅一次 + 掉落生成 ----
func _test_death_settles_once() -> void:
	GameState.reset_to_defaults()
	var loot_root := Node2D.new()
	loot_root.add_to_group("loot_root")
	add_child(loot_root)

	var wolf = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	add_child(wolf)
	await get_tree().process_frame

	var xp0: int = int(GameState.player.xp)
	var lethal := Combat.resolve(9999.0, wolf.get_defense(), 1.0, 1.0, 1.0, 0.0)
	wolf.take_hit(lethal, null)
	_expect(bool(wolf.is_dead), "致命伤害后怪物应死亡")
	_expect(int(GameState.player.xp) - xp0 == 25,
		"击杀野狼应结算经验 25，实际 %d" % [int(GameState.player.xp) - xp0])
	await get_tree().process_frame
	var drop_n := loot_root.get_child_count()
	_expect(drop_n >= 1, "击杀后应生成至少 1 件地面掉落（coin 概率 1.0），实际 %d" % drop_n)

	# 二次致命不应重复结算 / 重复掉落
	var xp1: int = int(GameState.player.xp)
	wolf.take_hit(lethal, null)
	await get_tree().process_frame
	_expect(int(GameState.player.xp) == xp1, "死亡结算应仅一次（经验）")
	_expect(loot_root.get_child_count() == drop_n, "死亡后不应重复掉落")

	wolf.queue_free()
	loot_root.queue_free()
	await get_tree().process_frame

# ---- M1-5：怪物点生成与刷新（7.9）----
func _test_spawner() -> void:
	var sp := MonsterSpawner.new()
	add_child(sp)
	sp.setup(null, null)
	sp.spawn_from_specs([
		{"monsterId": "wolf_corrupted", "level": 2, "count": 3, "respawnTime": 1.0, "ai": true},
	])
	await get_tree().process_frame
	_expect(sp.point_count() == 3, "应登记 3 个怪物点，实际 %d" % sp.point_count())
	_expect(sp.alive_count() == 3, "应生成 3 个存活怪物，实际 %d" % sp.alive_count())

	# 击杀一只后应按 respawnTime 重生
	var first: Node = sp.get_child(0)
	first.take_hit(Combat.resolve(9999.0, 0.0, 1.0, 1.0, 1.0, 0.0), null)
	await get_tree().process_frame
	_expect(sp.alive_count() == 2, "击杀后存活数应为 2，实际 %d" % sp.alive_count())

	# 注意：无头模式不锁帧，单帧 delta 极小，故按真实时间等待而非帧数
	await get_tree().create_timer(1.4).timeout
	_expect(sp.alive_count() == 3, "刷新时间到达后应回到 3 只，实际 %d" % sp.alive_count())

	sp.queue_free()
	await get_tree().process_frame

# ---- M1-6 / T07：掉落合法（品类 / 引用 / 品质权重 / 等级范围）----
func _test_loot() -> void:
	# 固定种子 → 可复现
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var drops := Loot.roll("DT_Wild_L1", rng)
	_expect(drops.size() >= 1, "DT_Wild_L1 应至少产出 1 件（coin 概率 1.0）")
	var has_coin := false
	for it in drops:
		var kind := String(it.get("kind", ""))
		_expect(kind in ["coin", "potion", "equip", "rune"], "掉落品类非法：%s" % kind)
		if kind == "coin":
			has_coin = true
			var g := int(it.get("gold", 0))
			_expect(g >= 4 and g <= 8, "野生金币应在 [4,8]，实际 %d" % g)
		elif kind == "potion":
			_expect(DataLoader.get_entry("potions", String(it.get("itemId", ""))) != null,
				"掉落的药水未在 potions.json 定义")
		elif kind == "equip":
			_expect(ItemUtil.is_valid_quality(String(it.get("quality", ""))),
				"装备品质非法：%s" % String(it.get("quality", "")))
			var lv := int(it.get("level", 0))
			_expect(lv >= 1 and lv <= 5, "野生装备等级应在 [1,5]，实际 %d" % lv)
			_expect(DataLoader.get_entry("equipments", String(it.get("itemId", ""))) != null,
				"掉落的装备模板未定义：%s" % String(it.get("itemId", "")))
			_expect(not String(it.get("instanceId", "")).is_empty(), "装备实例需带 instanceId")
	_expect(has_coin, "DT_Wild_L1 coin 概率 1.0，应必出金币")

	# Boss 表品质权重仅 rare/epic/legendary（10.2 权重约束）
	for s in range(40):
		var br := RandomNumberGenerator.new()
		br.seed = s
		for it2 in Loot.roll("DT_Boss_L1", br):
			if String(it2.get("kind", "")) == "equip":
				var q := String(it2.get("quality", ""))
				_expect(q in ["rare", "epic", "legendary"],
					"Boss 装备品质应限于 rare/epic/legendary，实际 %s" % q)

	# 无效掉落表 → 空（不崩溃）
	_expect(Loot.roll("DT_NOT_EXIST").is_empty(), "无效掉落表应返回空数组")

# ---- M1 收尾 / 数值校准（07 方案 §7）：防回归断言 ----
## 校准值一旦被误改回旧值，此用例立即失败。
func _test_balance_calibration() -> void:
	# C1 裂壳虫：hpBase / defense 已校准（原 300 / 20 → 30s 过肉）
	var bug = DataLoader.get_entry("monsters", "shellback_bug")
	if bug == null:
		_expect(false, "缺少裂壳虫模板 shellback_bug")
	else:
		_expect(int(bug.get("hpBase", 0)) == 140,
			"C1 裂壳虫 hpBase 应为 140（校准），实际 %d" % int(bug.get("hpBase", 0)))
		_expect(int(bug.get("defense", 0)) == 12,
			"C1 裂壳虫 defense 应为 12（校准），实际 %d" % int(bug.get("defense", 0)))

	# C2 闪避为「点数」口径：野狼/游魂 6（≈10.7%）、狼王 8（≈13.8%）
	var dodge_cases := {"wolf_corrupted": 6, "ash_wraith": 6, "elite_wolf_king": 8}
	for mid in dodge_cases.keys():
		var mon = DataLoader.get_entry("monsters", mid)
		if mon == null:
			_expect(false, "缺少怪物模板 %s" % mid)
			continue
		var dv := int(mon.get("dodge", -1))
		_expect(dv == int(dodge_cases[mid]),
			"C2 %s dodge 应为 %d（点数口径），实际 %d" % [mid, int(dodge_cases[mid]), dv])
		# 点数口径复核：dodge=6 → Miss≈10.7%、dodge=8 → Miss≈13.8%
		var miss := Combat.miss_chance(float(dv))
		_expect(miss > 0.05 and miss < 0.20,
			"C2 %s dodge=%d 的 Miss 应落在 (5%%,20%%)，实际 %.2f%%" % [mid, dv, miss * 100.0])

	# C3 精英专属掉落表：存在 + 已绑定 + 金币/装备口径正确
	var elite = DataLoader.get_entry("monsters", "elite_wolf_king")
	if elite != null:
		_expect(String(elite.get("dropTableId", "")) == "DT_Elite_L1",
			"C3 精英应绑 DT_Elite_L1，实际 %s" % String(elite.get("dropTableId", "")))
	var dt = DataLoader.get_entry("dropTables", "DT_Elite_L1")
	if dt == null:
		_expect(false, "C3 缺少 DT_Elite_L1 掉落表")
	else:
		var coin_ok := false
		var equip_ok := false
		for e in dt.get("entries", []):
			var kind := String(e.get("kind", ""))
			if kind == "coin":
				var gr = e.get("goldRange", [])
				coin_ok = gr is Array and gr.size() >= 2 and int(gr[0]) == 48 and int(gr[1]) == 72
			elif kind == "equip":
				_expect(is_equal_approx(float(e.get("chance", 0.0)), 1.0),
					"C3 精英装备应必掉（chance 1.0）")
				var qw = e.get("qualityWeight", {})
				equip_ok = qw is Dictionary and int(qw.get("uncommon", 0)) == 50 \
					and int(qw.get("rare", 0)) == 40 and int(qw.get("epic", 0)) == 10
		_expect(coin_ok, "C3 DT_Elite_L1 金币范围应为 [48,72]")
		_expect(equip_ok, "C3 DT_Elite_L1 品质权重应为 优50/稀40/史10")

	# 精英掉落实测：金币落 [48,72] 且必出装备（多轮验证）
	var seen_equip := false
	for s in range(30):
		var r := RandomNumberGenerator.new()
		r.seed = 900 + s
		for it in Loot.roll("DT_Elite_L1", r):
			var k := String(it.get("kind", ""))
			if k == "coin":
				var g := int(it.get("gold", 0))
				_expect(g >= 48 and g <= 72, "C3 精英金币应在 [48,72]，实际 %d" % g)
			elif k == "equip":
				seen_equip = true
				var q := String(it.get("quality", ""))
				_expect(q in ["uncommon", "rare", "epic"], "C3 精英装备品质越界：%s" % q)
	_expect(seen_equip, "C3 精英应必出装备（30 轮抽取全未见 equip，异常）")

# ---- M1-6 / T10：背包存储与满包判定（5.8）----
func _test_inventory() -> void:
	var inv := Inventory.create(40)
	_expect(inv.size() == 40, "背包应为 40 格，实际 %d" % inv.size())
	_expect(Inventory.used_slots(inv) == 0, "新背包应为空")

	# 药水可堆叠
	var potion := {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	_expect(Inventory.add(inv, potion), "药水应可入包")
	_expect(Inventory.add(inv, potion), "药水应可续堆")
	_expect(Inventory.used_slots(inv) == 1, "两瓶药水应占 1 格，实际 %d" % Inventory.used_slots(inv))
	_expect(int(inv[0].get("count", 0)) == 2, "药水应堆叠为 2，实际 %d" % int(inv[0].get("count", 0)))

	# 装备不可堆叠 → 各占一格
	var eq := {"kind": "equip", "itemId": "weapon_starter", "quality": "common", "level": 1, "instanceId": "i1", "count": 1}
	_expect(Inventory.add(inv, eq), "装备应可入包")
	_expect(Inventory.add(inv, eq.duplicate(true)), "第二件装备应入新格")
	_expect(Inventory.used_slots(inv) == 3, "应为 3 格，实际 %d" % Inventory.used_slots(inv))

	# 满包：40 件装备 → is_full
	var full := Inventory.create(40)
	for i in range(40):
		Inventory.add(full, {"kind": "equip", "itemId": "weapon_starter", "quality": "common", "level": 1, "instanceId": "f%d" % i, "count": 1})
	_expect(Inventory.is_full(full), "40 件装备后背包应满")
	_expect(not Inventory.add(full, {"kind": "equip", "itemId": "weapon_starter", "count": 1}), "满包不应再入装备")
	_expect(not Inventory.has_space_for(full, {"kind": "equip", "itemId": "weapon_starter", "count": 1}), "满包对装备应无空间")
	_expect(not Inventory.has_space_for(full, {"kind": "potion", "itemId": "potion_hp_small", "count": 1}), "满包（无药水堆）不应容纳新药水")

# ---- M1-6：靠近自动拾取 / T10 满包留地（9.9）----
func _test_pickup() -> void:
	GameState.reset_to_defaults()
	var loot_root := Node2D.new()
	loot_root.add_to_group("loot_root")
	add_child(loot_root)

	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO
	await get_tree().physics_frame

	# 金币：靠近 → 直接入账（不占背包）
	var gi: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi.pickup_delay = 0.0   # 本用例验即时拾取语义，关闭落地保护期
	gi.item = {"kind": "coin", "itemId": "coin", "gold": 7, "count": 1}
	loot_root.add_child(gi)
	gi.global_position = Vector2(20.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(GameState.gold == 7, "拾取金币应入账 7，实际 %d" % GameState.gold)
	_expect(not is_instance_valid(gi), "拾取后金币掉落物应被移除")

	# 药水：靠近 → 入背包
	var gi2: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi2.pickup_delay = 0.0
	gi2.item = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	loot_root.add_child(gi2)
	gi2.global_position = Vector2(20.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(GameState.inventory_used() == 1, "拾取药水应占 1 格，实际 %d" % GameState.inventory_used())

	# T10：背包满 → 物品留地
	GameState.inventory = Inventory.create(40)
	for i in range(40):
		Inventory.add(GameState.inventory, {"kind": "equip", "itemId": "weapon_starter", "quality": "common", "level": 1, "instanceId": "z%d" % i, "count": 1})
	var gi3: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi3.pickup_delay = 0.0
	gi3.item = {"kind": "equip", "itemId": "weapon_starter", "quality": "common", "level": 1, "instanceId": "ll", "count": 1}
	loot_root.add_child(gi3)
	gi3.global_position = Vector2(20.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(is_instance_valid(gi3), "背包满时地面物品应留地（T10）")
	_expect(GameState.inventory_used() == 40, "背包满时应保持 40 件")

	player.queue_free()
	loot_root.queue_free()
	await get_tree().process_frame

## M1-6 补：落地保护期（掉落可见性）。
## 生成后 PICKUP_DELAY 秒内不自动拾取，保证「击杀 → 看到掉落 → 再入包」；
## 否则近战击杀距离（≤1 格）必然小于自动拾取半径（1.5 格），掉落物 1 物理帧内即被吸走。
func _test_pickup_delay() -> void:
	GameState.reset_to_defaults()
	var loot_root := Node2D.new()
	loot_root.add_to_group("loot_root")
	add_child(loot_root)
	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO
	await get_tree().physics_frame

	var gi: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi.item = {"kind": "coin", "itemId": "coin", "gold": 9, "count": 1}
	loot_root.add_child(gi)
	gi.global_position = Vector2(20.0, 0.0)   # 明显落在自动拾取半径（1.5 格 = 96px）内

	var delay: float = gi.pickup_delay
	_expect(delay > 0.0, "地面掉落物默认应有落地保护期，实际 %.2f" % delay)

	# 保护期内：连续物理帧后仍留在地面，且未入账
	for _i in range(3):
		await get_tree().physics_frame
	_expect(is_instance_valid(gi), "落地保护期内不应被自动拾取（掉落可见性）")
	_expect(GameState.gold == 0, "落地保护期内不应入账，实际 %d" % GameState.gold)

	# 保护期结束后：玩家仍在范围内 → 自动入包
	await get_tree().create_timer(delay + 0.2).timeout
	_expect(not is_instance_valid(gi), "保护期结束后应被自动拾取")
	_expect(GameState.gold == 9, "保护期结束后金币应入账 9，实际 %d" % GameState.gold)

	player.queue_free()
	loot_root.queue_free()
	await get_tree().process_frame

## M1-7：装备栏 14 槽（5.1）、穿戴后属性立即生效（T06）、实例属性不重随（10.1）。
func _test_equipment() -> void:
	GameState.reset_to_defaults()

	# 14 槽定义：数量 / id 唯一 / 单双槽（5.1）
	_expect(Equipment.SLOT_DEFS.size() == 14, "装备槽应为 14 个，实际 %d" % Equipment.SLOT_DEFS.size())
	var seen := {}
	for d in Equipment.SLOT_DEFS:
		seen[String(d.id)] = true
	_expect(seen.size() == 14, "槽位 id 应唯一，实际 %d" % seen.size())
	_expect(Equipment.slots_for_kind("ring").size() == 2, "戒指应为双槽")
	_expect(Equipment.slots_for_kind("weapon").size() == 1, "武器应为单槽")
	_expect(Equipment.create().size() == 14, "Equipment.create 应生成 14 槽")
	# 武器与盾牌可同时装备（5.1）；类型取自模板（5.7）
	_expect(Equipment.item_kind({"itemId": "weapon_starter"}) == "weapon", "守护者短刃应为武器")
	_expect(Equipment.item_kind({"itemId": "shield_basic"}) == "shield", "木盾应为盾牌")

	# 穿戴：属性立即生效（T06），且不改基础值（5.1）
	var base_atk: int = int(GameState.player.attack)
	var hp_before := GameState.max_hp()
	var idx := _put_item(_equip_instance("weapon_starter", "e1", {"atk": 5}))
	var res := GameState.equip_from_inventory(idx)
	_expect(bool(res.get("ok", false)), "穿戴守护者短刃应成功：%s" % res.get("reason", ""))
	_expect(int(GameState.player.attack) == base_atk, "装备不应改基础攻击（5.1）")
	_expect(GameState.total_attack() == base_atk + 5,
		"总攻击应为基础+5，实际 %d" % GameState.total_attack())
	_expect(GameState.max_hp() > hp_before, "穿戴加攻装备后最大生命应提升（4.3 派生）")
	_expect(GameState.equipment.get("weapon") != null, "武器槽应已占用")
	_expect(GameState.inventory_used() == 0, "穿戴后该装备应离开背包（已穿戴不占背包 5.8）")

	# 实例属性不重随（10.1）：记录实例 → 卸下 → 再穿，逐字段一致
	var worn: Dictionary = GameState.equipment["weapon"]
	var atk_worn := GameState.total_attack()
	var un := GameState.unequip_slot("weapon")
	_expect(bool(un.get("ok", false)), "卸下应成功")
	_expect(GameState.total_attack() == base_atk, "卸下后总攻击应还原，实际 %d" % GameState.total_attack())
	_expect(GameState.inventory_used() == 1, "卸下后装备应回到背包")
	var again := GameState.equip_from_inventory(_index_of_instance("e1"))
	_expect(bool(again.get("ok", false)), "再次穿戴应成功")
	_expect(str(GameState.equipment["weapon"]) == str(worn), "穿脱后实例属性不应重随（10.1）")
	_expect(GameState.total_attack() == atk_worn, "再次穿戴后总攻击应一致")

	# 同槽替换：旧装备回背包，新装备生效
	GameState.player.level = 5
	var idx2 := _put_item(_equip_instance("weapon_wolfking", "e2", {"atk": 12}, [{"stat": "atk", "value": 6}]))
	var rep := GameState.equip_from_inventory(idx2)
	_expect(bool(rep.get("ok", false)), "替换武器应成功：%s" % rep.get("reason", ""))
	_expect(String(GameState.equipment["weapon"].get("instanceId", "")) == "e2", "武器槽应换成新武器")
	var rep_old: Dictionary = rep.get("replaced", {})
	_expect(not rep_old.is_empty(), "应返回被替换的旧装备")
	_expect(GameState.total_attack() == base_atk + 12 + 6,
		"攻击应为基础+12+6，实际 %d" % GameState.total_attack())
	_expect(GameState.inventory_used() == 1, "被替换的旧武器应回到背包")

	# 等级门槛（5.2 / 4.5）：不足不可穿戴，且不改变状态
	GameState.reset_to_defaults()
	var idx3 := _put_item(_equip_instance("weapon_wolfking", "e3", {"atk": 12}))
	var low := GameState.equip_from_inventory(idx3)
	_expect(not bool(low.get("ok", false)), "Lv1 不应能穿戴 Lv4 装备")
	_expect(GameState.equipment["weapon"] == null, "穿戴失败不应占用槽位")
	_expect(GameState.inventory_used() == 1, "穿戴失败不应改变背包")
	_expect(Equipment.level_req(_equip_instance("weapon_wolfking", "e3", {})) == 4,
		"狼王之刃门槛应为 4（5.2）")

	# 卸下需背包空位（5.1）
	GameState.player.level = 5
	GameState.equip_from_inventory(idx3)
	_expect(GameState.equipment["weapon"] != null, "Lv5 应能穿戴 Lv4 武器")
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i] == null:
			GameState.inventory[i] = {"kind": "potion", "itemId": "potion_hp_small", "count": 99}
	var full_un := GameState.unequip_slot("weapon")
	_expect(not bool(full_un.get("ok", false)), "背包满时卸下应失败（5.1）")
	_expect(GameState.equipment["weapon"] != null, "卸下失败不应清空槽位")

	# 双槽类：两枚戒指可同时装备（5.1）
	GameState.reset_to_defaults()
	for k in range(2):
		var ri := _put_item(_equip_instance("ring_basic", "r%d" % k, {"atk": 1, "mp": 5}))
		GameState.equip_from_inventory(ri)
	_expect(Equipment.worn_count(GameState.equipment) == 2, "两枚戒指应各占一槽")
	_expect(GameState.equipment["ring_1"] != null and GameState.equipment["ring_2"] != null,
		"双槽应分别占用")
	# 装备 mp 进入 MPFlat（4.3）
	_expect(GameState.max_mp() == 35 + 10, "两枚戒指应使最大法力 +10，实际 %d" % GameState.max_mp())

	# 评分（5.9）：高攻装备评分更高
	_expect(Equipment.score({"baseAttrs": {"atk": 12}, "affixes": [{"stat": "atk", "value": 6}]})
		> Equipment.score({"baseAttrs": {"atk": 5}}), "高攻装备评分应更高")

	GameState.reset_to_defaults()

## M1-8：货郎买卖（6.4 / 6.2）——买扣金币入包；卖加金币出包；
## 金币不足 / 背包满 / 非装备出售 均有明确拦截（不静默）。
func _test_shop() -> void:
	var shop_id := "peddler_camp"
	GameState.reset_to_defaults()

	# 配置读取（数据驱动，10.2）
	_expect(Shop.display_name(shop_id) == "货郎（营地）",
		"货郎名应取自 shops.json，实际 %s" % Shop.display_name(shop_id))
	_expect(Shop.buy_items(shop_id).size() >= 1, "营地货郎应有出售商品")
	_expect(Shop.buy_price(shop_id, "potion_hp_small") == 20, "小红药售价应为 20")
	_expect(Shop.buy_price(shop_id, "potion_hp_large") == -1, "营地货郎不应出售大红药（返回 -1）")

	# 买 · 金币不足 → 明确失败，不扣钱不入包
	GameState.gold = 0
	var poor := GameState.shop_buy(shop_id, "potion_hp_small")
	_expect(not bool(poor.get("ok", false)), "金币不足应购买失败")
	_expect(GameState.gold == 0, "购买失败不应扣金币")
	_expect(GameState.inventory_used() == 0, "购买失败不应入包")

	# 买 · 成功 → 扣金币 + 入包（同一药水堆叠为 1 格 2 瓶）
	GameState.gold = 100
	var ok1 := GameState.shop_buy(shop_id, "potion_hp_small")
	_expect(bool(ok1.get("ok", false)), "金币充足应购买成功：%s" % ok1.get("reason", ""))
	_expect(GameState.gold == 80, "购买应扣 20 金币，实际 %d" % GameState.gold)
	_expect(GameState.inventory_used() == 1, "药水应入包占 1 格，实际 %d" % GameState.inventory_used())
	var ok2 := GameState.shop_buy(shop_id, "potion_hp_small")
	_expect(bool(ok2.get("ok", false)), "第二瓶应可续买")
	_expect(int(GameState.inventory[0].get("count", 0)) == 2,
		"两瓶药水应堆叠为 2，实际 %d" % int(GameState.inventory[0].get("count", 0)))

	# 买 · 杂项品类解析正确（回城卷 → misc）
	GameState.gold = 200
	var scroll := GameState.shop_buy(shop_id, "misc_town_scroll")
	_expect(bool(scroll.get("ok", false)), "回城卷应可购买")
	_expect(String(GameState.inventory[1].get("kind", "")) == "misc", "回城卷品类应为 misc")

	# 买 · 背包满 → 明确失败且不扣钱
	GameState.reset_to_defaults()
	GameState.gold = 999
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = _equip_instance("weapon_starter", "f%d" % i, {"atk": 1})
	var full := GameState.shop_buy(shop_id, "potion_hp_small")
	_expect(not bool(full.get("ok", false)), "背包满应购买失败")
	_expect(GameState.gold == 999, "背包满失败不应扣金币，实际 %d" % GameState.gold)

	# 售价公式（6.2）：round(baseValue × qualityMult × (1 + star×0.08))
	var common_w := _equip_instance("weapon_starter", "s1", {"atk": 5})
	_expect(Shop.sell_price(common_w) == 50,
		"普通武器（基础价 50 × 1.0）售价应为 50，实际 %d" % Shop.sell_price(common_w))
	var rare_w := _equip_instance("weapon_wolfking", "s2", {"atk": 12})
	rare_w["quality"] = "rare"
	_expect(Shop.sell_price(rare_w) == 720,
		"稀有武器（240 × 3）售价应为 720，实际 %d" % Shop.sell_price(rare_w))
	var rare_star := rare_w.duplicate(true)
	rare_star["star"] = 1
	_expect(Shop.sell_price(rare_star) == 778,
		"稀有 +1 星（240 × 3 × 1.08）应为 778，实际 %d" % Shop.sell_price(rare_star))
	_expect(Shop.can_sell(rare_w), "装备可出售")
	_expect(not Shop.can_sell({"kind": "potion", "itemId": "potion_hp_small"}),
		"药水不可出售给货郎（6.4）")

	# 卖 · 非装备拦截
	GameState.reset_to_defaults()
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	var bad_sell := GameState.shop_sell(0)
	_expect(not bool(bad_sell.get("ok", false)), "药水不应可出售给货郎")
	_expect(GameState.inventory[0] != null, "出售失败不应移除物品")

	# 卖 · 装备 → 加金币出包
	GameState.reset_to_defaults()
	GameState.inventory[0] = _equip_instance("weapon_starter", "v1", {"atk": 5})
	var sell := GameState.shop_sell(0)
	_expect(bool(sell.get("ok", false)), "装备应可出售")
	_expect(GameState.gold == 50, "出售普通武器应得 50 金币，实际 %d" % GameState.gold)
	_expect(GameState.inventory[0] == null, "出售后该格应清空")
	_expect(not GameState.is_upgrade_over_worn(_equip_instance("weapon_starter", "v2", {"atk": 5})),
		"无同类型已穿戴装备时不应判为升级件")

	# 暂存 → 退回（关闭面板 / 取回）：不结算、不丢失
	GameState.reset_to_defaults()
	GameState.player.level = 5
	GameState.inventory[0] = _equip_instance("weapon_wolfking", "w_strong", {"atk": 12},
		[{"stat": "atk", "value": 6}])
	GameState.equip_from_inventory(0)      # 穿上强武器（武器槽占用）
	GameState.inventory[0] = _equip_instance("weapon_starter", "w_weak", {"atk": 5})
	GameState.inventory[1] = _equip_instance("helmet_cloth", "h1", {"def": 2})
	GameState.inventory[2] = _equip_instance("weapon_starter", "w_better", {"atk": 30})
	_expect(GameState.is_upgrade_over_worn(GameState.inventory[2]),
		"攻击 30 的武器应高于已穿戴（18）而判为升级件")

	var staged_ret: Array = [GameState.remove_item_at(0)]
	var gold_ret: int = GameState.gold
	var back_n := GameState.shop_unstage(staged_ret)
	_expect(back_n == 1, "退回 1 件应成功，实际 %d" % back_n)
	_expect(staged_ret.is_empty(), "退回后暂存列表应清空")
	_expect(GameState.gold == gold_ret, "退回不予结算（不应加金币）")
	_expect(_index_of_instance("w_weak") >= 0, "退回的装备应回到背包")

	# 暂存 → 确认出售（6.4）：批量结算为金币
	var staged: Array = []
	for i in range(GameState.inventory.size() - 1, -1, -1):
		if GameState.inventory[i] is Dictionary:
			staged.append(GameState.remove_item_at(i))
	var expect_gold := 0
	for it in staged:
		expect_gold += Shop.sell_price(it)
	var gold_before: int = GameState.gold
	var settled := GameState.shop_sell_staged(staged)
	_expect(int(settled.get("count", 0)) == staged.size(),
		"确认出售应结算全部暂存件，实际 %d" % int(settled.get("count", 0)))
	_expect(GameState.gold - gold_before == expect_gold,
		"确认出售应入账 %d 金币，实际 %d" % [expect_gold, GameState.gold - gold_before])
	_expect(GameState.inventory_used() == 0, "结算后背包应为空")
	_expect(GameState.shop_sell_staged([]).get("count", -1) == 0, "空暂存结算应为 0 件")

	GameState.reset_to_defaults()

## 交易界面（双面板 + 拖拽出售，M1-8 改造）：面板级不变量与 6.4 托盘流程。
## 独立实例化两个面板（不加载世界），验证拖入 / 取回 / 确认结算 / 一键移入保留升级件 / 关闭退回。
func _test_trade_panel() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 5

	var inv: Control = load("res://scenes/ui/InventoryPanel.tscn").instantiate()
	var shop: Control = load("res://scenes/ui/ShopPanel.tscn").instantiate()
	add_child(inv)
	add_child(shop)                       # 与 Main.tscn 同序：货郎面板在上层
	await get_tree().process_frame

	# 开战前：两面板都关闭
	_expect(not shop.visible and not inv.visible, "未交易时两面板应都关闭")

	# 走近货郎按 E → 进入交易会话：货郎面板 + 背包面板**并列打开**（工程文档 05 🔴R2）
	EventBus.shop_open_requested.emit("peddler_camp")
	await get_tree().process_frame
	_expect(shop.visible, "开战后货郎面板应可见")
	_expect(inv.visible, "开战后背包面板应同时可见（不再互斥）")
	_expect(shop.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"货郎面板根节点应为 IGNORE，否则会吞掉左侧背包的鼠标事件")
	_expect(not inv._dim.visible and not shop._dim.visible, "交易会话中双方遮罩都应隐藏")

	# 背包准备：2 件普通装备（可售）+ 1 件优于已穿戴的武器（一键移入应跳过）
	GameState.inventory[0] = _equip_instance("weapon_wolfking", "p_worn", {"atk": 12},
		[{"stat": "atk", "value": 6}])
	GameState.equip_from_inventory(0)     # 穿上强武器
	GameState.inventory[0] = _equip_instance("weapon_starter", "p_weak", {"atk": 5})
	GameState.inventory[1] = _equip_instance("helmet_cloth", "p_helm", {"def": 2})
	GameState.inventory[2] = _equip_instance("weapon_starter", "p_better", {"atk": 30})
	EventBus.inventory_changed.emit()
	await get_tree().process_frame

	var bag_slot: ItemSlot = inv._bag_buttons[0]
	var payload: Variant = bag_slot._get_drag_data(Vector2.ZERO)
	_expect(payload is Dictionary, "背包格应可拖出（_get_drag_data 返回载荷）")
	_expect(int((payload as Dictionary).get("index", -1)) == 0, "载荷应携带背包下标")
	var payload_item: Dictionary = (payload as Dictionary).get("item", {})
	_expect(String(payload_item.get("instanceId", "")) == "p_weak", "载荷应携带该格物品实例")

	var tray_slot: ItemSlot = shop._tray_slots[0]
	_expect(tray_slot._can_drop_data(Vector2.ZERO, payload), "托盘格应接受背包格的投放")
	_expect(not tray_slot._can_drop_data(Vector2.ZERO, {"from": 999}), "托盘格不应接受非法来源")

	# 拖入 → 装备从背包移入托盘暂存（未结算）
	shop._on_tray_drop(0, payload)
	await get_tree().process_frame
	_expect(shop._tray.size() == 1, "拖入后托盘应暂存 1 件，实际 %d" % shop._tray.size())
	_expect(_index_of_instance("p_weak") < 0, "拖入后该装备应离开背包")
	_expect(GameState.gold == 0, "暂存阶段不应结算金币")
	_expect(tray_slot.item.get("instanceId", "") == "p_weak", "托盘格应显示该装备")

	# 点托盘格 → 取回背包
	shop._on_tray_slot_pressed(0)
	await get_tree().process_frame
	_expect(shop._tray.is_empty(), "取回后托盘应清空")
	_expect(_index_of_instance("p_weak") >= 0, "取回的装备应回到背包")

	# 一键移入：移入可售装备、跳过优于已穿戴的武器
	shop._on_stage_all_pressed()
	await get_tree().process_frame
	_expect(shop._tray.size() == 2, "一键移入应移入 2 件可售装备，实际 %d" % shop._tray.size())
	_expect(_index_of_instance("p_better") >= 0, "优于已穿戴的武器不应被一键移入（6.4）")
	_expect(_index_of_instance("p_weak") < 0 and _index_of_instance("p_helm") < 0,
		"可售装备应已移入托盘")

	# 确认出售 → 结算为金币
	var gold_before: int = GameState.gold
	shop._on_confirm_pressed()
	await get_tree().process_frame
	_expect(shop._tray.is_empty(), "确认出售后托盘应清空")
	_expect(GameState.gold > gold_before, "确认出售应加金币，实际 %d→%d" % [gold_before, GameState.gold])

	# 关闭货郎面板 → 背包面板随之关闭（交易会话整体退出）
	shop.set_open(false)
	await get_tree().process_frame
	_expect(not shop.visible and not inv.visible, "关闭货郎面板应同时关闭背包面板")
	_expect(not GameState.panel_open, "退出交易后角色操控应解除屏蔽")

	# 关闭时托盘内未确认装备应退回背包（不静默丢失，🔴R3）
	EventBus.shop_open_requested.emit("peddler_camp")
	await get_tree().process_frame
	GameState.inventory[0] = _equip_instance("weapon_starter", "p_lost", {"atk": 5})
	EventBus.inventory_changed.emit()
	await get_tree().process_frame
	shop._on_tray_drop(0, inv._bag_buttons[0]._get_drag_data(Vector2.ZERO))
	_expect(shop._tray.size() == 1, "再次拖入应暂存 1 件")
	shop.set_open(false)
	await get_tree().process_frame
	_expect(shop._tray.is_empty(), "关闭后面板托盘应清空")
	_expect(_index_of_instance("p_lost") >= 0, "关闭面板时未确认的装备应退回背包")

	inv.queue_free()
	shop.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

# ---- M1-8 追加修复：拖拽预览层级（DragGhost 的落点图层）----
## 根因：引擎的 set_drag_preview 把预览插到发起拖拽的面板内部（实测 4.7），与其余面板
## 同 canvas、同 z_index → 被排在后面的面板整块盖住；z_index 只在同 canvas 内比较。
## 故改为自绘 DragGhost，挂到 UI 层内最高层（组 drag_ghost_layer）。本测守住这条契约。
func _test_drag_layer() -> void:
	GameState.reset_to_defaults()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var layer := get_tree().get_first_node_in_group("drag_ghost_layer")
	_expect(layer != null, "缺少拖拽预览图层（组 drag_ghost_layer）")
	var shop: Control = main.get_node("UI/ShopPanel")
	var inv: Control = main.get_node("UI/InventoryPanel")

	# HUD 提示条必须浮在面板之上：Hud 与面板同 canvas、z_index 皆为 0 时，
	# 绘制顺序由树的先后决定（Hud 排在 UI 层最前 → 被后绘制的面板整块盖住），
	# 于是交易中的「货郎只收购装备」「背包已满」等提示玩家根本看不到。
	var toast: Control = main.get_node("UI/Hud/ToastBox")
	_expect(toast != null, "未找到 HUD 提示条容器（Hud/ToastBox）")
	if toast != null:
		_expect(toast.z_index > shop.z_index and toast.z_index > inv.z_index,
			"HUD 提示条 z_index（%d）应高于面板（货郎 %d / 背包 %d）"
			% [toast.z_index, shop.z_index, inv.z_index])

	if layer != null:
		_expect(int(layer.z_index) > int(shop.z_index) and int(layer.z_index) > int(inv.z_index),
			"拖拽图层 z_index（%d）应高于面板（货郎 %d / 背包 %d）"
			% [layer.z_index, shop.z_index, inv.z_index])
		if toast != null:
			_expect(int(toast.z_index) < int(layer.z_index),
				"HUD 提示条 z_index（%d）应低于拖拽幽灵图层（%d）—— 幽灵须始终最上"
				% [toast.z_index, layer.z_index])
		_expect(layer.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"拖拽图层不得拦截鼠标（否则面板点击失效）")
		_expect(layer.get_parent() == main.get_node("UI"),
			"拖拽图层必须与面板同属 UI 层（z_index 只在同 canvas 内有效）")

	# 非拖拽态取载荷：返回载荷但**不创建幽灵**，也不得报错（无头安全）
	GameState.add_item(_equip_instance("helmet_cloth", "dl_probe", {"def": 2}))
	var inv2: Control = load("res://scenes/ui/InventoryPanel.tscn").instantiate()
	add_child(inv2)
	await get_tree().process_frame
	inv2._bag_buttons[0].draggable = true
	var payload: Variant = inv2._bag_buttons[0]._get_drag_data(Vector2.ZERO)
	_expect(payload is Dictionary, "背包格应可拖出（_get_drag_data 返回载荷）")
	if layer != null:
		_expect(layer.get_node_or_null("DragGhost") == null,
			"非拖拽态下不应创建拖拽幽灵（避免控件泄漏）")

	inv2.queue_free()
	main.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

## M1-9：自动战斗 / 自动拾取（3.14 硬性异常规则；T08 不可达改选 / T10 背包满 / T11 MP 与冷却；4.6 手动接管）。
func _test_auto_battle() -> void:
	GameState.reset_to_defaults()

	# ---- T11：MP / 冷却 / 等级不足 → 不施放该技能（choose_skill 纯函数）----
	var skills: Array = DataLoader.get_table("skills")
	var earth := _skill_by_id(skills, "earth_cleave")     # Lv5 / 15MP / 范围(cone)
	var armor := _skill_by_id(skills, "armor_break")      # Lv25 / 40MP / 单体
	_expect(not earth.is_empty() and not armor.is_empty(),
		"skills.json 应含 earth_cleave / armor_break")
	# 3.14：优先可用范围技（命中 ≥2）
	_expect(String(AutoBattle.choose_skill([earth], 5, 35, {}, 3).get("id", "")) == "earth_cleave",
		"命中≥2 时应优先范围技")
	# 单体场景不选范围技（返回空 = 回退普攻）
	_expect(AutoBattle.choose_skill([earth], 5, 35, {}, 1).is_empty(),
		"单体场景不应选范围技（应回退普攻）")
	# MP 不足 → 不施放（T11）
	_expect(AutoBattle.choose_skill([earth], 5, 14, {}, 3).is_empty(),
		"MP 不足不应施放技能（T11）")
	# 冷却中 → 不施放（T11）
	_expect(AutoBattle.choose_skill([armor], 25, 40, {"armor_break": 3.0}, 1).is_empty(),
		"冷却中不应施放技能（T11）")
	# 等级不足 → 不施放
	_expect(AutoBattle.choose_skill([earth], 1, 999, {}, 3).is_empty(),
		"技能未解锁不应施放")
	# 条件齐备 → 可施放单体
	_expect(String(AutoBattle.choose_skill([armor], 25, 40, {}, 1).get("id", "")) == "armor_break",
		"条件齐备应可施放单体技能")

	# ---- 状态机：实例化世界，开 F → 锚点搜怪 → 接近 / 攻击 ----
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var player: PlayerCharacter = game.get_node("Entities/Player")
	var pilot: AutoBattle = player.get_node_or_null("AutoPilot")
	_expect(pilot != null, "Player 下应挂有 AutoPilot 自动战斗决策机")
	if pilot == null:
		game.queue_free()
		await get_tree().process_frame
		GameState.reset_to_defaults()
		return

	# 锚点半径内放一只不动的怪，保证必有目标（避免依赖随机怪物点）
	var mon: Monster = load("res://scenes/entities/Monster.tscn").instantiate()
	mon.monster_id = "training_dummy"
	mon.ai_enabled = false
	game.get_node("Spawner").add_child(mon)
	mon.global_position = player.global_position + Vector2(220.0, 0.0)
	await get_tree().process_frame

	GameState.set_auto_battle(true)
	_expect(GameState.auto_battle_on, "开启自动战斗后 auto_battle_on 应为 true")
	# 压低攻击保证目标不死，便于观察状态机；max_hp 由攻击派生（4.3）→ 同步补满
	GameState.player.attack = 1
	GameState.player.hp = GameState.max_hp()
	var seen_combat := false
	for _i in range(120):                     # ≈2s
		await get_tree().physics_frame
		var st := pilot.current_state()
		if st == AutoBattle.State.PATH_TO_TARGET or st == AutoBattle.State.ATTACK_TARGET:
			seen_combat = true
	_expect(pilot.current_target() != null, "自动战斗应锁定锚点半径内的目标")
	_expect(seen_combat, "开 F 后应进入「接近目标」或「攻击目标」状态")

	# 4.6 手动接管：模拟按住方向键 → 立即转「手动接管」
	Input.action_press("move_left")
	for _i in range(4):
		await get_tree().physics_frame
	_expect(pilot.current_state() == AutoBattle.State.MANUAL_OVERRIDE,
		"检测到手动输入应进入「手动接管」，实际 %s"
		% AutoBattle.state_name(pilot.current_state()))
	Input.action_release("move_left")

	# 3.14 ⑥ 死亡 → 自动转 off（4.7）
	player.is_dead = true
	for _i in range(4):
		await get_tree().physics_frame
	_expect(not GameState.auto_battle_on, "玩家死亡后自动战斗应自动关闭（3.14）")
	player.is_dead = false
	GameState.set_auto_battle(false)

	# ---- T10：背包满 → 不走向需要入包的掉落物（金币不受背包限制）----
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = _equip_instance("helmet_cloth", "full_%d" % i, {"def": 1})
	var loot_root: Node = game.get_node("LootRoot")
	var it_potion: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	it_potion.item = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	loot_root.add_child(it_potion)
	await get_tree().process_frame
	_expect(not pilot._can_pick(it_potion),
		"背包满时应判定该掉落物不可拾取（T10：不得无限拾取满背包）")
	var it_coin: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	it_coin.item = {"kind": "coin", "itemId": "coin", "gold": 5, "count": 1}
	loot_root.add_child(it_coin)
	await get_tree().process_frame
	_expect(pilot._can_pick(it_coin), "金币不受背包容量限制，应仍可拾取")

	game.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

## M1-10：存档落地（10.3 记录清单 / 原子写入 / 备份 / T16 损坏恢复）。
## 契约：① 存→退→进后 等级 / 经验 / 金币 / 地图 / 背包实例 / 已穿戴实例 / 坐标 / 任务状态 全部一致；
##       ② 主档损坏 → 自动回退备份并自愈；③ 主档 + 备份都坏 → 明确失败（不静默）；
##       ④ 删除清干净；⑤ 旧档缺字段按默认值补齐；⑥ 运行态自动战斗开关不落档（10.3）。
## 说明：用 3 号槽做实验，测试前快照、测试后原样写回，不碰玩家 1 / 2 号槽。
func _test_save() -> void:
	const SLOT := 3
	var prev_active: int = SaveManager.active_slot
	var snap := _snapshot_saves(SLOT)
	SaveManager.delete_slot(SLOT)

	# ---- ① 空槽语义：读取失败但给出明确说明（不静默）----
	_expect(not SaveManager.has_slot(SLOT), "删除后该槽应视为空")
	var empty_read := SaveManager.read_slot(SLOT)
	_expect(not bool(empty_read.get("ok", false)), "空槽读取应失败")
	_expect(not String(empty_read.get("message", "")).is_empty(), "空槽读取应给出明确说明")

	# ---- 构造一份有内容的进度（等级 / 经验 / 背包实例 / 已穿戴实例 / 坐标 / 任务状态）----
	GameState.reset_to_defaults()
	GameState.player.level = 7
	GameState.player.xp = 33
	GameState.player.attack = 24
	GameState.player.defense = 11
	GameState.player.hp = 90
	GameState.player.mp = 12
	GameState.gold = 1234
	GameState.current_map = "camp"
	GameState.quest_states = {"Q001": "done"}
	GameState.first_clear = {"boss_corrupt_beast": true}
	GameState.settings["searchRadius"] = 15
	GameState.inventory[0] = _equip_instance("weapon_starter", "sv_1", {"atk": 5})
	GameState.inventory[1] = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	GameState.equipment["weapon"] = _equip_instance("weapon_wolfking", "sv_worn", {"atk": 12},
		[{"stat": "atk", "value": 6}])
	GameState.save_pos = Vector2(123.5, -456.25)
	GameState.has_save_pos = true
	GameState.set_auto_battle(true)          # 运行态开关：不应被存档带过重启（10.3）

	var expected_worn: Dictionary = (GameState.equipment["weapon"] as Dictionary).duplicate(true)
	var expected_bag0: Dictionary = (GameState.inventory[0] as Dictionary).duplicate(true)
	var expected_atk := GameState.total_attack()

	SaveManager.set_active_slot(SLOT)
	_expect(SaveManager.save_slot(SLOT, true), "保存应成功")
	_expect(SaveManager.has_slot(SLOT), "保存后应存在存档文件")
	SaveManager.save_slot(SLOT, true)        # 再存一次 → 产生一份最近有效备份（10.3）

	# ---- 摘要（9.4 存档卡：角色名 / 等级 / 地图 / 存档时间）----
	var sum := SaveManager.slot_summary(SLOT)
	_expect(bool(sum.get("ok", false)), "存档摘要应可用：%s" % String(sum.get("message", "")))
	_expect(int(sum.get("level", 0)) == 7, "摘要等级应为 7，实际 %d" % int(sum.get("level", 0)))
	_expect(int(sum.get("gold", 0)) == 1234, "摘要金币应为 1234，实际 %d" % int(sum.get("gold", 0)))
	_expect(int(sum.get("worn", 0)) == 1, "摘要应记录 1 件已穿戴，实际 %d" % int(sum.get("worn", 0)))
	_expect(int(sum.get("inventoryUsed", 0)) == 2,
		"摘要应记录 2 格背包占用，实际 %d" % int(sum.get("inventoryUsed", 0)))
	_expect(String(sum.get("mapName", "")) == "幸存者营地",
		"摘要地图名应取自 maps.json，实际 %s" % String(sum.get("mapName", "")))
	_expect(not String(sum.get("savedAt", "")).is_empty(), "摘要应含存档时间")
	_expect(String(sum.get("savedAt", "")).find("T") < 0, "存档时间应已格式化为可读形式")

	# ---- ② 退出（重置）→ 重进（读档）后逐字段一致 ----
	GameState.reset_to_defaults()
	_expect(GameState.gold == 0 and int(GameState.player.level) == 1, "重置后应回到初始状态")

	var res := SaveManager.read_slot(SLOT)
	_expect(bool(res.get("ok", false)), "读档应成功")
	_expect(String(res.get("source", "")) == "main", "正常读档来源应为主档")
	SaveManager.apply_to_game_state(res.get("data", {}))

	_expect(int(GameState.player.level) == 7, "读档后等级应为 7，实际 %d" % int(GameState.player.level))
	_expect(int(GameState.player.xp) == 33, "读档后经验应为 33，实际 %d" % int(GameState.player.xp))
	_expect(int(GameState.player.attack) == 24, "读档后基础攻击应为 24")
	_expect(int(GameState.player.defense) == 11, "读档后基础防御应为 11")
	_expect(int(GameState.player.hp) == 90, "读档后当前 HP 应为 90，实际 %d" % int(GameState.player.hp))
	_expect(int(GameState.player.mp) == 12, "读档后当前 MP 应为 12，实际 %d" % int(GameState.player.mp))
	_expect(GameState.gold == 1234, "读档后金币应为 1234，实际 %d" % GameState.gold)
	_expect(GameState.current_map == "camp", "读档后地图应一致")
	_expect(String(GameState.quest_states.get("Q001", "")) == "done", "读档后任务状态应一致")
	_expect(bool(GameState.first_clear.get("boss_corrupt_beast", false)), "读档后首杀标记应一致")
	_expect(int(GameState.settings.get("searchRadius", 0)) == 15, "读档后设置项应一致")

	# 背包：实例（含 int 化的数值字段）逐字段一致 + 堆叠数正确
	var idx := _index_of_instance("sv_1")
	_expect(idx >= 0, "读档后背包装备应还原")
	if idx >= 0:
		_expect(_deep_equal(GameState.inventory[idx], expected_bag0),
			"读档后背包实例应逐字段一致（10.1 不重随）：\n  存档时：%s\n  读档后：%s"
			% [str(expected_bag0), str(GameState.inventory[idx])])
	_expect(String(GameState.inventory[1].get("itemId", "")) == "potion_hp_small",
		"读档后药水应还原")
	_expect(int(GameState.inventory[1].get("count", 0)) == 3,
		"读档后药水堆叠应为 3（JSON 数字需回落为 int），实际 %d"
		% int(GameState.inventory[1].get("count", 0)))

	# 已穿戴实例：逐字段一致，且加成立即生效（T06）
	_expect(_deep_equal(GameState.equipment["weapon"], expected_worn),
		"读档后已穿戴实例应逐字段一致（10.1）：\n  存档时：%s\n  读档后：%s"
		% [str(expected_worn), str(GameState.equipment["weapon"])])
	_expect(GameState.total_attack() == expected_atk,
		"读档后总攻击应为 %d，实际 %d" % [expected_atk, GameState.total_attack()])

	# 坐标（10.3 当前地图与坐标）
	_expect(GameState.has_save_pos, "读档后应带出生坐标")
	_expect(GameState.save_pos.is_equal_approx(Vector2(123.5, -456.25)),
		"读档后坐标应一致，实际 %s" % str(GameState.save_pos))

	# ---- ③ 运行态开关不落档（10.3：重启后自动战斗默认关闭）----
	_expect(not GameState.auto_battle_on, "读档后自动战斗应默认关闭（运行态开关不持久化）")

	# ---- ④ 存 → 退 → 进（续档链路，10.3 继续）----
	GameState.reset_to_defaults()
	_expect(SaveManager.resume_last(), "重启后应能继续上次存档（last_slot）")
	_expect(int(GameState.player.level) == 7 and GameState.gold == 1234, "续档后进度应一致")

	# ---- ⑤ T16：主档损坏 → 回退备份并自愈 ----
	var path := SaveManager.slot_path(SLOT)
	_write_raw(path, "{ 这不是合法 JSON")
	var from_bak := SaveManager.read_slot(SLOT)
	_expect(bool(from_bak.get("ok", false)), "主档损坏时应能回退备份（T16）：%s"
		% String(from_bak.get("message", "")))
	_expect(String(from_bak.get("source", "")) == "backup", "恢复来源应为备份，实际 %s"
		% String(from_bak.get("source", "")))
	_expect(int((from_bak.get("data", {}) as Dictionary).get("gold", 0)) == 1234,
		"从备份恢复的金币应与最近有效存档一致")
	_expect(FileAccess.file_exists(path + ".corrupt"), "损坏的主档应另存为 .corrupt 保留现场")
	var healed := SaveManager.read_slot(SLOT)
	_expect(String(healed.get("source", "")) == "main", "恢复后应回到主档路径（已自愈）")

	# 结构非法（合法 JSON 但不是存档）同样判为损坏
	_write_raw(path, JSON.stringify({"schemaVersion": 1}))
	_write_raw(SaveManager.backup_path(SLOT), JSON.stringify({"schemaVersion": 1}))
	var dead := SaveManager.read_slot(SLOT)
	_expect(not bool(dead.get("ok", false)), "主档与备份都不是合法存档时应明确失败")
	_expect(not String(dead.get("message", "")).is_empty(), "损坏时应给出明确说明（不静默）")

	# ---- ⑥ 旧档导入：缺字段按默认值补齐 ----
	SaveManager.delete_slot(SLOT)            # 先清掉上一轮的 .bak / .corrupt 等旁文件
	_write_raw(path, JSON.stringify({"schemaVersion": 0, "player": {"level": 3}, "gold": 5}))
	var old_res := SaveManager.read_slot(SLOT)
	_expect(bool(old_res.get("ok", false)), "缺字段的旧档应可读取（旧档导入）")
	SaveManager.apply_to_game_state(old_res.get("data", {}))
	_expect(int(GameState.player.level) == 3, "旧档已有字段应保留（等级 3）")
	_expect(int(GameState.player.attack) == int(GameState.default_player()["attack"]),
		"旧档缺失字段应补默认值（攻击 %d）" % int(GameState.default_player()["attack"]))
	_expect(GameState.inventory.size() == GameState.INVENTORY_SIZE, "旧档无背包字段时应补空背包")
	_expect(GameState.equipment.size() == Equipment.SLOT_DEFS.size(), "旧档无装备字段时应补空槽")
	_expect(not GameState.has_save_pos, "旧档无坐标字段时应回退地图中心出生")

	# ---- ⑦ 删除：清干净（主档 / 备份 / 临时 / 损坏现场）----
	SaveManager.delete_slot(SLOT)
	_expect(not FileAccess.file_exists(path), "删除后主档应移除")
	_expect(not FileAccess.file_exists(path + ".bak"), "删除后备份应移除")
	_expect(not FileAccess.file_exists(path + ".corrupt"), "删除后损坏现场应移除")
	_expect(not SaveManager.has_slot(SLOT), "删除后 has_slot 应为 false")

	# 还原现场（不污染玩家真实存档）
	_restore_saves(SLOT, snap)
	SaveManager.active_slot = prev_active
	GameState.reset_to_defaults()

	# ---- ⑧ 读档坐标 → 世界出生点（10.3「当前地图与坐标」）----
	GameState.save_pos = Vector2(400.0, -400.0)
	GameState.has_save_pos = true
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var player: Node2D = game.get_node("Entities/Player")
	var ground: IsoGround = game.get_node("Ground")
	var expected := ground.clamp_to_map(Vector2(400.0, -400.0))
	_expect(player.global_position.is_equal_approx(expected),
		"读档后玩家应出生在存档坐标而非地图中心：pos=%s expected=%s"
		% [str(player.global_position), str(expected)])
	_expect(not player.global_position.is_equal_approx(ground.get_map_center_world()),
		"读档出生点不应等于地图中心（说明坐标未被消费）")
	_expect(not GameState.has_save_pos, "出生坐标应在读档出生后被消费一次清空")

	# 坏档 / 越界坐标容错：应被夹回地图范围内（不把玩家扔到墙外）
	var far := ground.clamp_to_map(Vector2(999999.0, -999999.0))
	var gfar := Iso.world_to_grid(far)
	_expect(gfar.x >= 0.0 and gfar.x <= float(ground.grid_size.x)
		and gfar.y >= 0.0 and gfar.y <= float(ground.grid_size.y),
		"越界坐标应被夹回地图范围，实际网格坐标 %s" % str(gfar))

	game.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

# ---- 存档测试辅助：快照 / 还原 3 号槽与 last_slot（避免污染玩家真实存档）----

func _snapshot_saves(slot: int) -> Dictionary:
	var out := {"__last__": ""}
	if FileAccess.file_exists(SaveManager.LAST_SLOT_FILE):
		var lf := FileAccess.open(SaveManager.LAST_SLOT_FILE, FileAccess.READ)
		if lf != null:
			out["__last__"] = lf.get_as_text()
			lf.close()
	for suffix in ["", ".bak", ".tmp", ".corrupt"]:
		var p: String = SaveManager.slot_path(slot) + suffix
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				out[suffix] = f.get_as_text()
				f.close()
	return out

func _restore_saves(slot: int, snap: Dictionary) -> void:
	SaveManager.delete_slot(slot)
	for key in snap.keys():
		var txt := String(snap[key])
		var path: String = SaveManager.LAST_SLOT_FILE if String(key) == "__last__" \
			else SaveManager.slot_path(slot) + String(key)
		if txt.is_empty():
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			_write_raw(path, txt)

func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SmokeTest] 无法写入测试文件：%s" % path)
		return
	f.store_string(text)
	f.close()

## 存储结构深比较：键集相同 + 逐键相等。
## 注意 JSON 往返会**改变字典的键顺序**（解析后按键排序），故不能用 str() 比较。
func _deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			if da.size() != db.size():
				return false
			for k in da.keys():
				if not db.has(k) or not _deep_equal(da[k], db[k]):
					return false
			return true
		TYPE_ARRAY:
			var aa: Array = a
			var ab: Array = b
			if aa.size() != ab.size():
				return false
			for i in range(aa.size()):
				if not _deep_equal(aa[i], ab[i]):
					return false
			return true
		_:
			return a == b

## 按 id 取 skills.json 中的一条技能定义（不存在返回空字典）。
func _skill_by_id(skills: Array, skill_id: String) -> Dictionary:
	for s in skills:
		if s is Dictionary and String(s.get("id", "")) == skill_id:
			return s
	return {}

## 构造一件装备实例（10.1：实例自带属性，永不重随）。
func _equip_instance(item_id: String, inst_id: String, base_attrs: Dictionary,
		affixes: Array = []) -> Dictionary:
	return {
		"kind": "equip", "itemId": item_id, "instanceId": inst_id,
		"quality": "common", "level": 1,
		"baseAttrs": base_attrs, "affixes": affixes, "pctAttrs": [],
		"star": 0, "count": 1,
	}

## 放入背包首个空位，返回索引（-1 = 无空位）。
func _put_item(item: Dictionary) -> int:
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i] == null:
			GameState.inventory[i] = item
			return i
	return -1

## 背包中指定实例 id 的格位（-1 = 不存在）。
func _index_of_instance(instance_id: String) -> int:
	for i in range(GameState.inventory.size()):
		var it = GameState.inventory[i]
		if it is Dictionary and String(it.get("instanceId", "")) == instance_id:
			return i
	return -1

# ---- 开发期测试便利：测试武器必须与掉落池隔离（防污染回归）----
func _test_debug_seed() -> void:
	var id := "debug_blade_overpower"
	var tpl = DataLoader.get_entry("equipments", id)
	_expect(tpl is Dictionary, "缺少开发期测试武器模板 %s" % id)
	if tpl is Dictionary:
		_expect(bool(tpl.get("debug", false)), "测试武器模板应带 debug 标记（否则会进掉落池）")
		_expect(String(tpl.get("slot", "")) == "weapon", "测试武器应为 weapon 槽")
		_expect(int((tpl.get("baseAttrs", {}) as Dictionary).get("atk", 0)) >= 100,
			"测试武器攻击应显著高于普通装备")

	# 抽取 500 次野生掉落：测试武器一次都不应出现（Loot 跳过 debug 模板）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	var hits := 0
	for _i in range(500):
		for it in Loot.roll("DT_Wild_L1", rng):
			if it is Dictionary and String(it.get("itemId", "")) == id:
				hits += 1
	_expect(hits == 0, "测试武器不应出现在掉落中（命中 %d 次）" % hits)

func _test_world() -> void:
	GameState.reset_to_defaults()   # 保证发放测试武器时背包有空间
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame   # 等 deferred 发放测试武器落地

	var ground: Node = game.get_node_or_null("Ground")
	var player: Node = game.get_node_or_null("Entities/Player")
	_expect(ground != null, "未找到 Ground 节点")
	_expect(player != null, "未找到 Player 节点")
	if ground == null or player == null:
		return

	var center: Vector2 = ground.get_map_center_world()
	_expect(player.global_position.is_equal_approx(center),
		"玩家未出生在地图中心：pos=%s center=%s" % [player.global_position, center])

	var bounds: Rect2 = ground.get_world_bounds()
	_expect(bounds.size.x > 0.0 and bounds.size.y > 0.0, "地图包围盒非法：%s" % [bounds])

	var boundary: Node = ground.get_node_or_null("Boundary")
	_expect(boundary != null, "未生成边界碰撞体")
	if boundary != null:
		_expect(boundary.get_child_count() == 4, "边界墙应为 4 段，实际 %d" % boundary.get_child_count())

	# M1-5：怪物生成器按测试怪物点生成（数量随 game.gd 的 TEST_SPAWNS 配置，至少 3）
	var spawner: Node = game.get_node_or_null("Spawner")
	_expect(spawner != null, "未找到 Spawner 节点")
	if spawner != null:
		_expect(spawner.point_count() >= 3,
			"测试怪物点应至少 3 个，实际 %d" % spawner.point_count())
		_expect(spawner.get_child_count() == spawner.point_count(),
			"每个怪物点都应生成实例：点=%d 实例=%d" % [spawner.point_count(), spawner.get_child_count()])

	# 开发期测试便利：开局应已把测试武器放进背包
	var debug_found := false
	for it in GameState.inventory:
		if it is Dictionary and String(it.get("itemId", "")) == "debug_blade_overpower":
			debug_found = true
	_expect(debug_found, "开发期测试武器未发放到背包")

	# M1-6：世界掉落容器
	var loot_root: Node = game.get_node_or_null("LootRoot")
	_expect(loot_root != null and loot_root.is_in_group("loot_root"), "缺少 LootRoot 掉落容器节点")

	# M1-8：安全区 NPC（货郎）与交互半径
	var npcs: Node = game.get_node_or_null("Npcs")
	_expect(npcs != null, "未找到 Npcs 节点")
	if npcs != null:
		_expect(npcs.get_child_count() == 1, "营地图应有 1 个货郎，实际 %d" % npcs.get_child_count())
		var npc := npcs.get_child(0) as Npc
		_expect(npc != null, "Npcs 子节点应为 Npc 实体")
		if npc != null:
			_expect(npc.shop_id == "peddler_camp", "货郎应绑定 peddler_camp 商店")
			_expect(not npc.npc_name.is_empty(), "货郎应有显示名")
			_expect(not npc.is_player_in_range(), "出生点不应已在货郎交互范围内（避免开局误开面板）")
			(player as Node2D).global_position = npc.global_position + Vector2(40.0, 0.0)
			await get_tree().process_frame
			_expect(game.nearest_npc() == npc, "走进交互半径后应能定位到该 NPC（6.3）")

	# HUD 伤害飘字层分组
	var dn: Node = game.get_node_or_null("DamageNumbers")
	_expect(dn != null and dn.is_in_group("damage_numbers"), "DamageNumbers 节点缺少分组标记")

func _finish() -> void:
	if _failures.is_empty():
		print("[SmokeTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("[SmokeTest] 失败：", f)
		get_tree().quit(1)
