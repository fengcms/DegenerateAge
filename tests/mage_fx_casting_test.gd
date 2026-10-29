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
	_test_lifetime_under_cooldown()
	_test_fx_scripts_do_not_touch_combat()
	await _test_dispatch_each_fx_skill()
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
		if anchor == "target":
			# 单独再断一次「不能挂在施法者脚下」：若夹具里两者恰好重合，上一条会假绿。
			check(actual.distance_to(player.global_position) > 8.0,
				"位置层：%s 的 fx 不得挂在施法者脚下" % id)

	host.queue_free()
	await get_tree().process_frame

# ---- F：没有 fx 的技能必须逐位不变 ----

func _test_no_fx_unchanged() -> void:
	var host := Node2D.new()
	add_child(host)
	var player := _make_player(host, "warrior", FIXTURE_LEVEL_FLOOR)
	var enemy := _enemy(host, player.global_position + Vector2(TILE * 1.5, 0.0))
	await get_tree().process_frame
	check(player.cast_skill("earth_cleave", enemy),
		"无 fx 前提：武士裂地斩应能施放（否则下面的计数断言没有意义）")
	await get_tree().process_frame
	check(_count_script(host, _res_path(RangeFxScript)) == 1,
		"无 fx 的技能必须照旧 spawn 通用范围提示（否则一刀切把武士的提示也删了）")
	check(_count_script(host, _res_path(ProjScript)) == 0,
		"武士不得产生飞行投射物（近战路径逐位不变）")
	host.queue_free()
	await get_tree().process_frame

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
