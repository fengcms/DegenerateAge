class_name Monster
extends CharacterBody2D
## 怪物实体：属性读取 / HP 派生（7.5）/ 状态机（7.9）/ 受击与死亡结算（3.1）。
##
## 状态机子集：IDLE/patrol → aggro → chase → attack → (return) → dead → respawn。
## 死亡结算（经验 + 掉落）**仅一次**；掉落按 dropTableId 走掉落表（M1-6），任务推进在 M2。
## AI 参数来自 monsters.json；木桩等静态目标 ai_enabled=false。

const GROUND_ITEM_SCENE := preload("res://scenes/entities/GroundItem.tscn")
const DROP_SCATTER := 18.0     # 掉落物散落半径（px）

const M_HP_PER_LV := 0.12      # 7.5：每高 1 级约 +12% 生命（初始参数）
const AGGRO_RANGE := 200.0     # 仇恨半径（px，≈3 格）
const LEASH_RANGE := 420.0     # 追击边界：离 spawn 点过远则返回（px）
const PATROL_RADIUS := 90.0    # 巡逻半径（px）
const IDLE_TIME := 1.4         # 巡逻间停留（s）
const REACH := 6.0             # 到达判定（px）
const HIT_FLASH := 0.12        # 受击白闪时长（s）

const RADIUS := 13.0
const COLOR_BODY := Color("9c5a4a")
const COLOR_AGGRO := Color("c9553f")
const COLOR_EDGE := Color("3d221c")
const COLOR_HP_BG := Color(0.08, 0.08, 0.10, 0.85)
const COLOR_HP_FG := Color("d2383c")

enum State { IDLE, PATROL, CHASE, ATTACK, RETURN, DEAD }

@export var monster_id: String = "wolf_corrupted"
## 实际刷新等级；0 = 采用模板等级（区域等级梯度 / 等级差在 M3 接入）
@export var spawn_level: int = 0
## 是否启用 AI（木桩教学目标为 false）
@export var ai_enabled: bool = false
## 由生成器设置的锚点（巡逻 / 返回基准）；Zero 时取初始位置
@export var spawn_position: Vector2 = Vector2.ZERO

signal died(id: String)

var template: Dictionary = {}
var display_name: String = "怪物"
var level: int = 1
var max_hp: int = 1
var hp: int = 1
var is_dead: bool = false
var selected := false

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()
var state: int = State.IDLE

# ---- 由模板派生的 AI 参数 ----
var aggro_range: float = AGGRO_RANGE
var leash_range: float = LEASH_RANGE
var attack_range_px: float = 64.0
var attack_interval: float = 1.2
var attack_power: float = 0.0
var move_speed_px: float = 0.0
var is_ranged: bool = false
var defense_power := 0.0
var active_affixes: Array[Dictionary] = []
var _life_steal_credit := 0.0
var boss_phase := 0
var _boss_enraged := false
var _stomp_pending := false
var _stomp_remaining := 0.0
var _stomp_cooldown := 0.0
var _stomp_center := Vector2.ZERO
var _stomp_radius := 0.0

var _rng := RandomNumberGenerator.new()
var _attack_cd: float = 0.0
var _state_t: float = 0.0
var _patrol_target: Vector2 = Vector2.ZERO
var _flash_t: float = 0.0
var _flash_dirty: bool = false

func _ready() -> void:
	add_to_group("enemies")
	_rng.randomize()
	_load_template()
	if spawn_position == Vector2.ZERO:
		spawn_position = position
	_state_t = _rng.randf() * IDLE_TIME   # 错开巡逻相位
	queue_redraw()

func _load_template() -> void:
	template = DataLoader.get_entry("monsters", monster_id)
	if template == null:
		push_warning("[Monster] 未找到怪物模板 '%s'" % monster_id)
		template = {}
	display_name = String(template.get("name", monster_id))
	var tpl_level: int = int(template.get("level", 1))
	level = spawn_level if spawn_level > 0 else tpl_level
	max_hp = _derive_max_hp(tpl_level)
	hp = max_hp
	# AI 参数
	move_speed_px = float(template.get("moveSpeed", 0.0)) * Iso.TILE_W
	attack_interval = float(template.get("attackInterval", 1.2))
	attack_power = float(template.get("attack", 0.0))
	defense_power = float(template.get("defense", 0))
	_roll_affixes()
	var ar = template.get("attackRange", {})
	if ar is Dictionary:
		is_ranged = String(ar.get("kind", "melee")) == "ranged"
		attack_range_px = float(ar.get("range", 1.0)) * Iso.TILE_W

## 每次出生独立抽取，不修改共享模板，不重复抽取同一词缀。
func _roll_affixes() -> void:
	active_affixes.clear()
	_life_steal_credit = 0.0
	if template.get("kind", "normal") != "elite":
		return
	var pool: Array = template.get("affixPool", []).duplicate()
	var counts: Array = template.get("affixCount", [1, 2])
	var count := mini(pool.size(), _rng.randi_range(int(counts[0]), int(counts[1])))
	var prefixes: Array[String] = []
	for _i in range(count):
		var id := String(pool.pop_at(_rng.randi_range(0, pool.size() - 1)))
		var entry: Variant = DataLoader.get_entry("affixes", id)
		if not entry is Dictionary:
			continue
		active_affixes.append(entry.duplicate(true))
		prefixes.append(String(entry.name))
		attack_power *= 1.0 + float(entry.get("attackPct", 0))
		attack_interval /= 1.0 + float(entry.get("attackSpeedPct", 0))
		defense_power *= 1.0 + float(entry.get("defensePct", 0))
		move_speed_px *= 1.0 + float(entry.get("moveSpeedPct", 0))
	if not prefixes.is_empty():
		display_name = "·".join(prefixes) + "的" + display_name

## 仅有效扣血触发附伤；吸血保留不足 1 点的小数，避免低伤害永不回血。
func _apply_hit_effects(player: Node2D, actual_damage: int) -> void:
	if actual_damage <= 0:
		return
	var effects := active_affixes.duplicate()
	if template.get("specialAttack", "") == "slow":
		var frost: Variant = DataLoader.get_entry("affixes", "frost")
		if frost is Dictionary:
			effects.append(frost)
	for effect in effects:
		if effect.has("slowPct") and player.has_method("apply_slow"):
			player.call("apply_slow", float(effect.slowPct), float(effect.slowDuration))
		_life_steal_credit += actual_damage * float(effect.get("lifeStealPct", 0))
	var heal := int(floor(_life_steal_credit))
	_life_steal_credit -= heal
	hp = mini(max_hp, hp + heal)
	queue_redraw()

## 延迟到物理查询结束后生成；普通模板且不登记刷新点，随所属世界释放。
func _spawn_death_summons() -> void:
	for effect in active_affixes:
		if effect.has("summonId"):
			_spawn_summons(String(effect.summonId), int(effect.get("summonCount", 0)), true)

func _spawn_summons(id: String, count: int, after_death: bool = false) -> void:
	if not is_inside_tree() or get_parent() == null or is_queued_for_deletion() or (is_dead and not after_death):
		return
	for i in range(count):
		var child := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
		child.monster_id = id
		child.spawn_level = level
		child.ai_enabled = true
		var point := global_position + Vector2.from_angle(TAU * i / count) * 32.0
		var grid := Iso.world_to_grid(point)
		var dims := MapService.grid_size(GameState.current_map)
		grid = grid.clamp(Vector2.ZERO, Vector2(dims) - Vector2.ONE)
		point = Iso.grid_pt(grid.x, grid.y)
		child.position = get_parent().to_local(point)
		child.spawn_position = point
		get_parent().add_child(child)

## 返回 true 表示本帧由预警/践踏接管，禁止同帧普通攻击。
func _update_boss(delta: float) -> bool:
	if is_dead or template.get("kind", "") != "boss":
		return false
	var skill: Dictionary = template.get("bossSkill", {})
	var phases: Array = skill.get("phases", [])
	for i in range(phases.size()):
		var phase: Dictionary = phases[i]
		if phase.has("hpBelow") and hp_ratio() < float(phase.hpBelow):
			boss_phase = maxi(boss_phase, i)
			if phase.get("behavior", "") == "enrage_summon" and not _boss_enraged:
				_boss_enraged = true
				queue_redraw()
				attack_interval = maxf(Combat.MIN_ATTACK_INTERVAL, attack_interval / (1.0 + float(phase.get("addAttackSpeedPct", 0))))
				_spawn_summons.call_deferred(String(phase.get("summon", "")), int(phase.get("summonCount", 0)))
				EventBus.toast_requested.emit("%s 进入狂暴！" % display_name, "danger")
	_stomp_cooldown = maxf(0.0, _stomp_cooldown - delta)
	if _stomp_pending:
		_stomp_remaining = maxf(0.0, _stomp_remaining - delta)
		queue_redraw()
		if _stomp_remaining <= 0:
			_stomp_pending = false
			var target := _get_player()
			if target != null and target.global_position.distance_to(_stomp_center) <= _stomp_radius:
				_do_attack(target)
		return true
	var player := _get_player()
	if player == null or boss_phase < 1:
		return false
	for phase in phases:
		if phase.get("behavior", "") != "aoe_stomp":
			continue
		_stomp_radius = float(phase.get("radius", attack_range_px / Iso.TILE_W)) * Iso.TILE_W
		if _stomp_cooldown <= 0 and global_position.distance_to(player.global_position) <= _stomp_radius:
			_stomp_center = global_position
			_stomp_remaining = float(phase.get("warnDelay", 0.8))
			_stomp_cooldown = _stomp_remaining + float(phase.get("cooldown", attack_interval))
			_stomp_pending = true
			queue_redraw()
			return true
	return false

func _settle_first_clear() -> void:
	if template.get("kind", "") != "boss" or bool(GameState.first_clear.get(monster_id, false)):
		return
	GameState.first_clear[monster_id] = true
	var reward: Dictionary = template.get("firstClearReward", {})
	var unlock := String(reward.get("unlock", ""))
	if not unlock.is_empty():
		GameState.unlocks[unlock] = true
	EventBus.boss_first_clear.emit(monster_id)
	EventBus.toast_requested.emit("首次击败 %s！" % display_name, "levelup")

## 7.5：monsterMaxHP = max(1, round(hpBase × (1 + M_HP_PER_LV × (spawnLevel − templateLevel))))
func _derive_max_hp(tpl_level: int) -> int:
	var hp_base := float(template.get("hpBase", 1))
	var scaled := hp_base * (1.0 + M_HP_PER_LV * float(level - tpl_level))
	return maxi(1, int(round(scaled)))

func get_attack() -> float:
	return attack_power

func get_defense() -> float:
	return defense_power

func get_dodge() -> float:
	return float(template.get("dodge", 0.0))

func hp_ratio() -> float:
	return float(hp) / float(maxi(1, max_hp))

# ---- 物理 / 状态机 ----

func _physics_process(delta: float) -> void:
	# 白闪计时（受击反馈）
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		_flash_dirty = true
		queue_redraw()
	elif _flash_dirty:
		_flash_dirty = false
		queue_redraw()

	if is_dead:
		velocity = Vector2.ZERO
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	velocity = Vector2.ZERO
	if ai_enabled and not _update_boss(delta):
		_update_ai(delta)
	move_and_slide()

func _enter(s: int) -> void:
	if state == s:
		return
	state = s
	_state_t = 0.0
	queue_redraw()

func _update_ai(delta: float) -> void:
	var player := _get_player()
	var dist := INF
	if player != null:
		dist = global_position.distance_to(player.global_position)

	match state:
		State.IDLE, State.PATROL:
			if _can_aggro(player, dist):
				_enter(State.CHASE)
			else:
				_patrol(delta)
		State.CHASE:
			if player == null or global_position.distance_to(spawn_position) > leash_range:
				_enter(State.RETURN)
			elif dist <= attack_range_px:
				_enter(State.ATTACK)
			elif move_speed_px > 0.0:
				_approach(player.global_position)
		State.ATTACK:
			if player == null:
				_enter(State.RETURN)
			elif dist > attack_range_px * 1.2:
				_enter(State.CHASE)
			elif _attack_cd <= 0.0:
				_do_attack(player)
		State.RETURN:
			if _can_aggro(player, dist):
				_enter(State.CHASE)
			elif global_position.distance_to(spawn_position) <= REACH:
				_enter(State.IDLE)
			elif move_speed_px > 0.0:
				_approach(spawn_position)
		_:
			pass

## 能否进入战斗：无害静止物（木桩：移速 0 且攻击 0）永不仇恨。
func _can_aggro(player: Node2D, dist: float) -> bool:
	if player == null:
		return false
	if move_speed_px <= 0.0 and attack_power <= 0.0:
		return false
	return dist <= aggro_range

func _patrol(delta: float) -> void:
	if move_speed_px <= 0.0:
		return   # 静止型怪物不巡逻
	if state == State.IDLE:
		_state_t += delta
		if _state_t >= IDLE_TIME:
			_patrol_target = _random_patrol_point()
			_enter(State.PATROL)
		return
	# PATROL
	if global_position.distance_to(_patrol_target) <= REACH or _state_t > IDLE_TIME * 4.0:
		_enter(State.IDLE)
		return
	_state_t += delta
	_approach(_patrol_target)

func _random_patrol_point() -> Vector2:
	var ang := _rng.randf() * TAU
	var r := _rng.randf_range(20.0, PATROL_RADIUS)
	return spawn_position + Vector2(cos(ang), sin(ang)) * r

func _approach(target_pos: Vector2) -> void:
	var to := target_pos - global_position
	if to.length() < 0.001:
		return
	velocity = to.normalized() * move_speed_px

func _get_player() -> Node2D:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return null
	if p.get("is_dead") == true:
		return null
	return p as Node2D

# ---- 攻击 ----

func _do_attack(player: Node2D) -> void:
	_attack_cd = maxf(Combat.MIN_ATTACK_INTERVAL, attack_interval)
	if attack_power <= 0.0:
		return
	var res := Combat.resolve(
		attack_power,
		float(GameState.total_defense()),
		1.0, 0.0, 1.5,
		float(GameState.player.get("dodge", 0.0)))
	Fx.damage_number(get_tree(), player, res)
	if not bool(res.get("miss", false)) and player.has_method("apply_damage"):
		var actual := int(player.call("apply_damage", int(res.get("damage", 0))))
		_apply_hit_effects(player, actual)

# ---- 受击 / 死亡 ----

## 承受一次已结算的攻击（由 Combat.resolve 产出）。miss 不扣血；受击转仇恨。
func take_hit(result: Dictionary, from: Node = null) -> void:
	if is_dead or bool(result.get("miss", false)):
		return
	hp = maxi(0, hp - int(result.get("damage", 0)))
	_flash_t = HIT_FLASH
	if hp <= 0:
		_die()
	else:
		if ai_enabled and from is Node2D and state != State.CHASE and state != State.ATTACK:
			_enter(State.CHASE)
		queue_redraw()

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	state = State.DEAD
	velocity = Vector2.ZERO
	_stomp_pending = false
	_settle_first_clear()
	_settle_rewards()
	_spawn_death_summons.call_deferred()
	died.emit(monster_id)
	EventBus.monster_died.emit(monster_id)
	queue_redraw()
	# 淡出后移除；刷新由生成器按 respawnTime 处理（7.9）
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)

## 死亡结算（3.1：经验 / 掉落 / 任务，仅一次）。
## 经验即时结算；掉落按 dropTableId 走掉落表（M1-6，含金币作为地面拾取物）。
## 无掉落表时回退为直接结算模板金币（如教学木桩 goldReward=0）。
## 掉落结果聚合为一条「掉落」提示广播，与地面拾取时的「拾取」提示区分（9.6）。
## 任务推进在 M2 接入（订阅 EventBus.monster_died）。
func _settle_rewards() -> void:
	var xp := int(template.get("xpReward", 0))
	if xp > 0:
		GameState.add_xp(xp)

	var table_id := String(template.get("dropTableId", ""))
	if table_id.is_empty():
		var gold := int(template.get("goldReward", 0))
		if gold > 0:
			GameState.add_gold(gold)
			EventBus.toast_requested.emit("%s 掉落：金币 ×%d" % [display_name, gold], "drop")
		return

	var rolled := Loot.roll(table_id)
	for i in range(rolled.size()):
		_spawn_drop(rolled[i], i)
	_announce_drops(rolled)

## 聚合广播一条掉落提示：如「腐化野狼 掉落：金币 ×6 · 生命药水 · 稀有 布甲头盔 Lv2」。
func _announce_drops(items: Array) -> void:
	var parts: Array[String] = []
	for it in items:
		if it is Dictionary and not (it as Dictionary).is_empty():
			parts.append(ItemUtil.display_name(it))
	if parts.is_empty():
		return
	EventBus.toast_requested.emit("%s 掉落：%s" % [display_name, " · ".join(PackedStringArray(parts))], "drop")

## 在死亡位置附近生成一件地面掉落物（7.6 / 9.9）。
## `index` 为同批序号：用于 `stagger_delay` 起飞错峰，避免多件同时飞行叠成一坨。
func _spawn_drop(item: Dictionary, index: int = 0) -> void:
	if item.is_empty():
		return
	var layer := get_tree().get_first_node_in_group("loot_root")
	if layer == null:
		return
	var gi: GroundItem = GROUND_ITEM_SCENE.instantiate()
	gi.item = item
	gi.auto_claim = true   # 怪物掉落 = 生成即认领（工程文档 10 方案 C）
	gi.stagger_delay = minf(float(index) * GroundItem.STAGGER_PER_ITEM, GroundItem.STAGGER_MAX)
	layer.add_child(gi)
	var ang := _rng.randf() * TAU
	var r := _rng.randf() * DROP_SCATTER
	gi.global_position = global_position + Vector2(cos(ang), sin(ang)) * r
	EventBus.item_dropped.emit(String(item.get("itemId", "")))
	EventBus.loot_spawned.emit(item)

func _draw() -> void:
	if _stomp_pending and not is_dead:
		var center := to_local(_stomp_center)
		draw_circle(center, _stomp_radius, Color(1.0, 0.18, 0.05, 0.18))
		draw_arc(center, _stomp_radius, 0, TAU, 64, Color("ff623a"), 3.0, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(-50, -_stomp_radius - 8), "践踏预警", HORIZONTAL_ALIGNMENT_CENTER, 100, 16, Color("ffb65c"))
	if selected and not is_dead:
		draw_arc(Vector2.ZERO, RADIUS + 7, 0, TAU, 40, Color("6eebe6"), 2.5, true)
	var aggro := state == State.CHASE or state == State.ATTACK
	var body := Color("b0296b") if _boss_enraged else (COLOR_AGGRO if aggro else COLOR_BODY)
	if _flash_t > 0.0:
		body = Color.WHITE
	var body_center := Vector2(0.0, -RADIUS * 0.6)
	draw_circle(body_center, RADIUS, body)
	var elite: bool = template.get("kind", "normal") == "elite"
	draw_arc(body_center, RADIUS, 0.0, TAU, 24, Color("f3c85b") if elite else COLOR_EDGE, 3.0 if elite else 2.0, true)
	if elite:
		draw_string(ThemeDB.fallback_font, Vector2(-100, -RADIUS * 3.1), display_name, HORIZONTAL_ALIGNMENT_CENTER, 200, 13, Color("f3c85b"))
	# 头顶血条（9.5：目标血条）
	var w := 34.0
	var h := 4.0
	var x := -w * 0.5
	var y := -RADIUS * 2.4
	draw_rect(Rect2(x, y, w, h), COLOR_HP_BG)
	draw_rect(Rect2(x, y, w * hp_ratio(), h), COLOR_HP_FG)
