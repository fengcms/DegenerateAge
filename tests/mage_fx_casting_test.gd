extends Node
## 工程 106 守门：施法特效分派表 + 每个 fx 自报职责 + 无 fx 的技能逐位不变。
##
## 背景：改前 `player._spawn_cast_fx()` 只有 `thunder` 一个分支，其余所有技能共用一颗
## 6px 小球（工程 106 §1.4）。重做成表驱动之后，新增的风险从「画得好不好看」变成了
## **「数据与代码对不上」**，而这一类全都不报错：
##   · 数据写了 `fx` 但分派表没这个 key ⇒ 静默回落成一颗球（观感问题，没人查得出来）
##   · 标了 `fx` 但脚本忘了画范围 ⇒ 玩家**静默失去范围提示**（R2）
##   · fx 挂错锚点 ⇒ 特效出现在 A、伤害打在 B
##   · `LIFETIME` 超过 CD ⇒ 连按时节点堆积
## 这四条都是「配置看着对、跑起来也没报错」的形态，所以必须由测试守住。
##
## 分组：
##   A 数据层：skills.json 里每个 `fx` 都能在分派表找到，脚本可实例化、有 `setup`
##   B 分派层：每个 fx 技能产生**恰好 1 个**对应节点、**0 投射物**、**0 通用范围提示**
##   C 位置层：节点实际位置 == 它自己声明的 `ANCHOR`
##   D 范围声明：`DRAWS_AREA` 与 `shape` 语义一致（circle/cone ⇒ true，single ⇒ false）
##   E 寿命：`LIFETIME < 该技能 cooldown` 且 `<= 1.0s`
##   F 无 fx 的照旧：武士仍产生通用范围提示、仍不产生投射物
##   G 不碰结算：fx 脚本代码里没有 `GameState.` / `Combat.`（105 立的契约）
##   H 未知 fx：报警并**回落投射物**（不静默什么都不画）
##   I 朝向：`cone` 的 fx 必须使用调用点传入的 facing —— **左右各打一次**
##   J 半径：`DRAWS_AREA` 为 true 的 fx 必须自报 `area_radius == range × TILE_W`

const RangeFxScript := preload("res://scripts/systems/skill_range_fx.gd")
const ProjScript := preload("res://scripts/systems/player_projectile.gd")
const TILE := 64.0
## 施法夹具的等级：取「解锁等级 + 5，但不低于 60」，保证每个技能都真的解锁了。
const FIXTURE_LEVEL_FLOOR := 60

class TestEnemy extends Node2D:
	var is_dead := false
	var hits := 0
	func _ready() -> void:
		add_to_group("enemies")
	func get_defense() -> float:
		return 0.0
	func get_dodge() -> float:
		return 0.0
	func take_hit(_result: Dictionary, _from: Node = null) -> void:
		hits += 1

var failures: Array[String] = []

## 🔴 不能直接写 `ProjScript.resource_path`：`const X := preload(...)` 的静态类型是**那个脚本本身**，
## 它没有 `resource_path` 成员（编译期就报 "Cannot find member"）。必须显式当 `Script` 用。
static func _res_path(script: Script) -> String:
	return script.resource_path if script != null else ""

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[MageFxCastingTest] " + label)

func _ready() -> void:
	_test_table_covers_data()
	_test_draws_area_and_anchor_declarations()
	_test_fx_radius_honours_context()
	_test_lifetime_under_cooldown()
	_test_fx_scripts_do_not_touch_combat()
	await _test_dispatch_each_fx_skill()
	await _test_cone_fx_follows_facing()
	await _test_no_fx_unchanged()
	await _test_unknown_fx_falls_back()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[MageFxCastingTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[MageFxCastingTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 取数：遍历 skills.json 里所有声明了 fx 的技能 ----

## 返回 `[{id, class, level, shape, cooldown, range, fx}]`。
## 🔴 用 `DataLoader.get_table("skills")` 读**原始数据**，不经过 `SkillProgression.current()`
##    —— 后者按玩家状态过滤（未解锁返回空字典），会让断言依赖夹具等级而不是数据本身。
func _fx_skills() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table: Variant = DataLoader.get_table("skills")
	if not (table is Array):
		return out
	for raw in (table as Array):
		if not (raw is Dictionary):
			continue
		var skill: Dictionary = raw
		var key := String(skill.get("fx", ""))
		if key == "":
			continue
		out.append({
			"id": String(skill.get("id", "")),
			"class": String(skill.get("class", "mage")),
			"level": maxi(int(skill.get("unlockLevel", 1)) + 5, FIXTURE_LEVEL_FLOOR),
			"shape": String(skill.get("shape", "")),
			"cooldown": float(skill.get("cooldown", 0.0)),
			"range": float(skill.get("range", 1.0)),
			"fx": key,
		})
	return out

func _script_for(key: String) -> Script:
	if not PlayerCharacter.CAST_FX.has(key):
		return null
	var raw: Variant = PlayerCharacter.CAST_FX[key]
	return raw as Script if raw is Script else null

# ---- A：数据层 ----

func _test_table_covers_data() -> void:
	var list := _fx_skills()
	# 🔴 这一条是其余所有断言的前提：一个 fx 都没声明时，下面全部是空循环 ⇒ 静默假绿。
	check(not list.is_empty(), "前提：skills.json 里至少应有一个技能声明 fx（否则本测试形同虚设）")
	for spec in list:
		var key := String(spec["fx"])
		var id := String(spec["id"])
		check(PlayerCharacter.CAST_FX.has(key),
			"数据层：技能 %s 声明了 fx=%s，但 CAST_FX 分派表里没有这个 key（会静默回落成一颗球）" % [id, key])
		var script := _script_for(key)
		if script == null:
			check(false, "数据层：分派表 %s 必须指向一个有效的 GDScript" % key)
			continue
		check(script.can_instantiate(), "数据层：fx 脚本 %s 必须可实例化" % key)
		# 缺 `setup` 会让 `_spawn_cast_node` 报错后丢弃节点 —— 技能彻底没有特效。
		var probe: Variant = script.new()
		check(probe is Object and (probe as Object).has_method("setup"),
			"数据层：fx 脚本 %s 必须实现 setup(ctx)（106 分派契约）" % key)
		if probe is Node:
			(probe as Node).free()

# ---- D：范围声明 ----

func _test_draws_area_and_anchor_declarations() -> void:
	for spec in _fx_skills():
		var key := String(spec["fx"])
		var script := _script_for(key)
		if script == null:
			continue
		var consts := script.get_script_constant_map()
		var id := String(spec["id"])
		var shape := String(spec["shape"])
		check(consts.has("DRAWS_AREA"),
			"范围声明：fx 脚本 %s 必须声明 DRAWS_AREA（没有它就无法核对「谁负责画范围」）" % key)
		check(consts.has("ANCHOR"),
			"锚点声明：fx 脚本 %s 必须声明 ANCHOR = target / origin" % key)
		if consts.has("DRAWS_AREA"):
			var expect_area := shape == "circle" or shape == "cone"
			check(bool(consts["DRAWS_AREA"]) == expect_area,
				"范围声明：%s（shape=%s）的 DRAWS_AREA 应为 %s，实际 %s —— 标错任意一侧都会让玩家%s" % [
					id, shape, str(expect_area), str(bool(consts["DRAWS_AREA"])),
					"失去范围提示" if expect_area else "看到一个不该存在的范围"])
		if consts.has("ANCHOR"):
			var anchor := String(consts["ANCHOR"])
			check(anchor == "target" or anchor == "origin",
				"锚点声明：%s 的 ANCHOR 只能是 target / origin，实际「%s」" % [key, anchor])
		# 扇形 fx 的张角必须与命中判据同源。`player.skill_targets()` 的过滤条件是
		# `facing.dot(offset.normalized()) < cos(PI / 4)` ⇒ 半角 45°、全角 PI/2。
		# 🔴 期望值**手写**在这里：命中判据在 player.gd、张角在 fx 脚本，两者无法互相推导，
		#    所以文案必须点明来源。改命中判据的人要同步这一条。
		if shape == "cone":
			check(consts.has("ARC"),
				"范围形状：%s 是 cone，fx 必须声明 ARC（与命中判据 ±45° 同一来源，否则冰扫过的怪不掉血）" % id)
			if consts.has("ARC"):
				check(absf(float(consts["ARC"]) - PI * 0.5) < 0.001,
					"范围形状：%s 的 ARC 应为 PI/2（±45°，与 skill_targets 的 cos(PI/4) 同源），实际 %.4f" % [
						id, float(consts["ARC"])])

# ---- J：半径必须来自上下文，不能写死 ----

## 🔴 为什么不能只断「`area_radius` 等于 `range × TILE_W`」：数据里的 3.5 格恰好等于
##    脚本里可能写死的 224 —— 那种情况下断言永远绿，写死也查不出来。
##    这里绕开数据，直接喂一个**不可能出现在 skills.json 里**的值（777），
##    看 `setup()` 会不会如实体现在 `area_radius` 上。没有 `area_radius` 的 fx 无法观测，跳过。
func _test_fx_radius_honours_context() -> void:
	var covered := 0
	for spec in _fx_skills():
		var script := _script_for(String(spec["fx"]))
		if script == null:
			continue
		var consts := script.get_script_constant_map()
		if not bool(consts.get("DRAWS_AREA", false)):
			continue
		covered += 1
		var key := String(spec["fx"])
		var probe := script.new() as Node2D
		add_child(probe)
		probe.call("setup", {
			"origin": Vector2(100.0, 100.0),
			"target": Vector2(300.0, 200.0),
			"facing": Vector2.RIGHT,
			"radius": 777.0,
		})
		var got: Variant = probe.get("area_radius")
		check(got is float and absf(float(got) - 777.0) < 0.5,
			"半径来源：%s 的 setup 必须采纳 ctx.radius=777，实际 %s —— 写死半径会让「以后改 range」静默失效" % [
				key, str(got)])
		probe.queue_free()
	# 前提：一个画范围的 fx 都没有时本组空转 ⇒ 静默假绿。
	check(covered > 0, "半径来源：应至少有一个 DRAWS_AREA 的 fx（否则本组空转）")

# ---- E：寿命 ----

func _test_lifetime_under_cooldown() -> void:
	for spec in _fx_skills():
		var key := String(spec["fx"])
		var script := _script_for(key)
		if script == null:
			continue
		var consts := script.get_script_constant_map()
		if not consts.has("LIFETIME"):
			check(false, "寿命：fx 脚本 %s 必须声明 LIFETIME（否则无法核对「连按不会堆积」）" % key)
			continue
		var life := float(consts["LIFETIME"])
		var cd := float(spec["cooldown"])
		check(life < cd,
			"寿命：%s 的 LIFETIME=%.2fs 必须短于技能 CD %.2fs，否则连按时节点会堆积" % [
				String(spec["id"]), life, cd])
		check(life <= 1.0,
			"寿命：%s 的 LIFETIME=%.2fs 超过 1 秒，观感上会盖住后续动作" % [String(spec["id"]), life])

# ---- G：不碰结算 ----

## 读**源码文本**逐行判断，跳过注释行 —— 注释里写 `GameState` 是允许的（多处契约说明如此），
## 真正要防的是「有人把结算塞进视觉层」，那 105 立的契约就废了。
func _test_fx_scripts_do_not_touch_combat() -> void:
	for spec in _fx_skills():
		var key := String(spec["fx"])
		var script := _script_for(key)
		if script == null:
			continue
		var path := script.resource_path
		if path == "":
			check(false, "不碰结算：fx 脚本 %s 没有 resource_path，无法校验源码" % key)
			continue
		var text := FileAccess.get_file_as_string(path)
		check(text != "", "不碰结算：无法读取 %s 的源码（路径失效？）" % path)
		var bad: Array[String] = []
		for raw_line in text.split("\n"):
			var line := raw_line.strip_edges()
			if line.begins_with("#"):
				continue
			if line.contains("GameState.") or line.contains("Combat."):
				bad.append(line)
		check(bad.is_empty(),
			"不碰结算：%s 的代码里出现 GameState./Combat.（视觉层不得参与伤害结算）：%s" % [
				key, " | ".join(bad)])

# ---- B / C：逐个 fx 技能真跑一次 ----

func _test_dispatch_each_fx_skill() -> void:
	for spec in _fx_skills():
		await _run_one(spec)

func _run_one(spec: Dictionary) -> void:
	var key := String(spec["fx"])
	var script := _script_for(key)
	if script == null:
		return
	var id := String(spec["id"])
	# 每个用例独立一个 host：fx 会被挂到**施法者的父级**，共用根节点会让计数串味。
	var host := Node2D.new()
	add_child(host)
	var player := _make_player(host, String(spec["class"]), int(spec["level"]))
	var enemy := _enemy(host, player.global_position + Vector2(float(spec["range"]) * TILE * 0.45, 0.0))
	await get_tree().process_frame

	check(player.cast_skill(id, enemy),
		"分派层前提：%s 应能在射程内施放成功（施放失败时下面的计数断言会静默假绿）" % id)
	await get_tree().process_frame

	var fx_n := _count_script(host, script.resource_path)
	check(fx_n == 1,
		"分派层：%s 应产生恰好 1 个 %s 节点，实际 %d 个" % [id, script.resource_path.get_file(), fx_n])
	check(_count_script(host, _res_path(ProjScript)) == 0,
		"分派层：%s 有专属 fx，不得再产生飞行投射物（「一颗球飞过去」会丢掉技能身份）" % id)
	check(_count_script(host, _res_path(RangeFxScript)) == 0,
		"分派层：%s 有专属 fx，不得再 spawn 通用范围提示（两份对不上的范围会让玩家不知信哪个）" % id)

	# C：位置必须与自己声明的锚点一致。
	var node := _find_script(host, script.resource_path)
	if node != null:
		var consts := script.get_script_constant_map()
		var anchor := String(consts.get("ANCHOR", "target"))
		var expect_at := enemy.global_position if anchor == "target" else player.global_position
		var actual := (node as Node2D).global_position
		check(actual.distance_to(expect_at) < 1.0,
			"位置层：%s 的 fx 应挂在 %s（期望 %s），实际偏了 %.1fpx" % [
				id, anchor, str(expect_at), actual.distance_to(expect_at)])
		# 单独再断一次「不能挂在**另一个**锚点上」：若夹具里两者恰好重合，上一条会假绿。
		# 🔴 两个方向都要断 —— 批 2 的火焰喷发/冰咆哮是 origin，只断 target 反例的话
		#    它们挂错了也没有任何断言会红。
		var other_at := player.global_position if anchor == "target" else enemy.global_position
		check(actual.distance_to(other_at) > 8.0,
			"位置层：%s 的 fx 声明锚点 %s，不得挂在%s" % [
				id, anchor, "施法者脚下" if anchor == "target" else "目标身上"])
		# J：画范围的 fx 必须自报半径，且与 `range × TILE_W` 一致。
		# 抓的是「脚本里写死 448 / 288」这类错位：数据改了 range，视觉还停在旧半径。
		if bool(consts.get("DRAWS_AREA", false)):
			var raw_r: Variant = node.get("area_radius")
			check(raw_r is float,
				"范围半径：%s 声明了 DRAWS_AREA，必须暴露 area_radius 观测点（否则半径写死也查不出来）" % id)
			if raw_r is float:
				var expect_r := float(spec["range"]) * TILE
				check(absf(float(raw_r) - expect_r) < 1.0,
					"范围半径：%s 的 fx 实际半径 %.1fpx，应等于 range(%.1f 格) × %.0f = %.1fpx" % [
						id, float(raw_r), float(spec["range"]), TILE, expect_r])

	host.queue_free()
	await get_tree().process_frame

# ---- I：cone 的 fx 必须跟随调用点传入的 facing ----

## 🔴 **左右各打一次**是这个用例的全部意义：只把敌人放在右边时，脚本里写死
## `Vector2.RIGHT` 也会通过 —— 而那正是「冰往左喷、右边怪掉血」这个 bug 的形状。
func _test_cone_fx_follows_facing() -> void:
	var covered := 0
	for spec in _fx_skills():
		if String(spec["shape"]) != "cone":
			continue
		var script := _script_for(String(spec["fx"]))
		if script == null:
			continue
		covered += 1
		for sign_x: float in [1.0, -1.0]:
			await _run_cone_side(spec, script, sign_x)
	# 前提：数据里至少有一个「cone 且声明 fx」的技能，否则本组是空循环 ⇒ 静默假绿。
	check(covered > 0, "朝向：skills.json 里应至少有一个 cone 且声明 fx 的技能（否则本组空转）")

func _run_cone_side(spec: Dictionary, script: Script, sign_x: float) -> void:
	var id := String(spec["id"])
	var host := Node2D.new()
	add_child(host)
	var player := _make_player(host, String(spec["class"]), int(spec["level"]))
	var offset := Vector2(float(spec["range"]) * TILE * 0.45 * sign_x, 0.0)
	var enemy := _enemy(host, player.global_position + offset)
	await get_tree().process_frame
	check(player.cast_skill(id, enemy),
		"朝向前提：%s 应能在射程内施放（施放失败时下面的断言会静默假绿）" % id)
	await get_tree().process_frame
	var node := _find_script(host, script.resource_path)
	if node == null:
		check(false, "朝向：%s 没有生成 fx 节点，无法核对朝向" % id)
		host.queue_free()
		await get_tree().process_frame
		return
	var raw: Variant = node.get("facing_used")
	check(raw is Vector2,
		"朝向：%s 的 fx 必须暴露 facing_used 观测点（否则「朝向对不对」根本无从核对）" % id)
	if raw is Vector2:
		var used: Vector2 = raw
		var expect := offset.normalized()
		check(used.dot(expect) > 0.99,
			"朝向：%s 的 fx 朝向应等于「到锁定目标的方向」（期望 %s，实际 %s）" % [
				id, str(expect), str(used)])
	host.queue_free()
	await get_tree().process_frame

# ---- F：没有 fx 的技能必须逐位不变 ----

## 🔴 工程 107 把武士五个技能全部接上了 fx，`earth_cleave` 不再是「无 fx 的技能」。
## 直接删掉这条会让「一刀切把所有范围提示都删掉」失去看守（坑 64：为堵 A 加的防线在
## 前提消失后静默变成新 bug，且零断言）。
## 所以改成**内存里临时摘掉 `fx` 字段**把「无 fx 路径」重新构造出来，跑完立刻还原 ——
## 判据不变，样本改为构造出来的，这样无论以后接多少个 fx，这条都还有牙。
func _test_no_fx_unchanged() -> void:
	var host := Node2D.new()
	add_child(host)
	var player := _make_player(host, "warrior", FIXTURE_LEVEL_FLOOR)
	var enemy := _enemy(host, player.global_position + Vector2(TILE * 1.5, 0.0))
	await get_tree().process_frame
	var saved: Variant = _strip_fx("earth_cleave")
	check(saved is String and not (saved as String).is_empty(),
		"构造前提：裂地斩原本应有 fx 字段（否则「摘掉」这一步什么都没验证）")
	player.skill_cooldowns.clear()
	player._attack_cd = 0.0
	check(player.cast_skill("earth_cleave", enemy),
		"无 fx 前提：武士裂地斩应能施放（否则下面的计数断言没有意义）")
	await get_tree().process_frame
	check(_count_script(host, _res_path(RangeFxScript)) == 1,
		"无 fx 的技能必须照旧 spawn 通用范围提示（否则一刀切把武士的提示也删了）")
	check(_count_script(host, _res_path(ProjScript)) == 0,
		"武士不得产生飞行投射物（近战路径逐位不变）")
	_restore_fx("earth_cleave", saved as String)
	host.queue_free()
	await get_tree().process_frame

## 临时摘掉某条技能的 `fx` 字段，并让 `SkillProgression` 的解析缓存失效（它按
## `DataLoader.revision` 判断）。返回原值供还原。
## 🔴 不能走 `DataLoader.load_all()` —— 那会从磁盘重读，把内存里的摘除又盖回去。
func _strip_fx(skill_id: String) -> Variant:
	var table: Variant = DataLoader.tables.get("skills")
	if not table is Array:
		return null
	for raw in table:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == skill_id:
			var saved: Variant = (raw as Dictionary).get("fx")
			(raw as Dictionary).erase("fx")
			DataLoader.revision += 1
			return saved
	return null

func _restore_fx(skill_id: String, value: String) -> void:
	var table: Variant = DataLoader.tables.get("skills")
	if not table is Array or value.is_empty():
		return
	for raw in table:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == skill_id:
			(raw as Dictionary)["fx"] = value
			DataLoader.revision += 1
			return

# ---- H：未知 fx key 必须回落，而不是静默什么都不画 ----

func _test_unknown_fx_falls_back() -> void:
	var host := Node2D.new()
	add_child(host)
	var player := _make_player(host, "mage", FIXTURE_LEVEL_FLOOR)
	var enemy := _enemy(host, player.global_position + Vector2(TILE * 2.0, 0.0))
	await get_tree().process_frame
	# 直接调分派函数（不经 cast_skill）：这里要验的是分派对未知 key 的反应。
	player._spawn_cast_fx({"fx": "no_such_fx_at_all"}, "basic_fireball", enemy, Vector2.RIGHT, 2.0 * TILE)
	await get_tree().process_frame
	check(_count_script(host, _res_path(ProjScript)) == 1,
		"未知 fx key 必须回落到投射物：静默什么都不画＝技能彻底没有特效，比回落更糟")
	host.queue_free()
	await get_tree().process_frame

# ---- 夹具 ----

func _make_player(host: Node2D, class_id: String, level: int) -> PlayerCharacter:
	GameState.reset_to_defaults(class_id)
	GameState.current_map = "wild_trial"
	GameState.player.level = level
	var player := PlayerCharacter.new()
	host.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(2000, 2000)
	return player

func _enemy(host: Node2D, at: Vector2) -> TestEnemy:
	var enemy := TestEnemy.new()
	host.add_child(enemy)
	enemy.global_position = at
	return enemy

## 🔴 必须**递归**计数：施法特效挂在 `player.get_parent()`（host），而通用范围提示
## `skill_range_fx` 是 `player.add_child()` 挂在玩家身上的 —— 只看 host 的直接子节点会漏掉后者，
## 于是「武士仍产生范围提示」这条断言永远红（或者反过来，永远假绿）。
func _count_script(root: Node, path: String) -> int:
	var n := 0
	for child in root.get_children():
		if _is_script(child, path):
			n += 1
		n += _count_script(child, path)
	return n

func _find_script(host: Node2D, path: String) -> Node:
	for child in host.get_children():
		if _is_script(child, path):
			return child
	return null

func _is_script(node: Node, path: String) -> bool:
	if path == "":
		return false
	var script: Variant = node.get_script()
	return script is Script and String((script as Script).resource_path) == path
