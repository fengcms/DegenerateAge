class_name Monster
extends CharacterBody2D
## 怪物实体：属性读取 / HP 派生（7.5）/ 状态机（7.9）/ 受击与死亡结算（3.1）。
##
## 状态机子集：IDLE/patrol → aggro → chase → attack → (return) → dead → respawn。
## 死亡结算（经验 + 掉落）**仅一次**；掉落按 dropTableId 走掉落表（M1-6），任务推进在 M2。
## AI 参数来自 monsters.json；木桩等静态目标 ai_enabled=false。

const GROUND_ITEM_SCENE := preload("res://scenes/entities/GroundItem.tscn")

const M_HP_PER_LV := 0.12      # 7.5：每高 1 级约 +12% 生命（初始参数）
const AGGRO_RANGE := 200.0     # 仇恨半径（px，≈3 格）
const LEASH_RANGE := 420.0     # 追击边界：离 spawn 点过远则返回（px）
const PATROL_RADIUS := 90.0    # 巡逻半径（px）
const IDLE_TIME := 1.4         # 巡逻间停留（s）
const REACH := 6.0             # 到达判定（px）
const HIT_FLASH := 0.12        # 受击白闪时长（s）

## M6-0a（创意 07 §4）：三档敌人外观。普通沿用既有半径；精英 / Boss 放大并加轮廓与地面标识。
const RADIUS := 13.0          # 普通（兼容既有引用）
const RADIUS_ELITE := 19.0
const RADIUS_BOSS := 36.0
const COLOR_BODY := Color("9c5a4a")
const COLOR_AGGRO := Color("c9553f")
const COLOR_EDGE := Color("3d221c")
const COLOR_ELITE_BODY := Color("8a5f2c")
const COLOR_ELITE_EDGE := Color("f3c85b")
const COLOR_BOSS_BODY := Color("6b2a2a")
const COLOR_BOSS_BODY_ENRAGED := Color("b0296b")
const COLOR_BOSS_EDGE := Color("8f2020")
const COLOR_BOSS_RING := Color("5a1414")
const COLOR_HP_BG := Color(0.08, 0.08, 0.10, 0.85)
const COLOR_HP_FG := Color("d2383c")

## 等宽字体（M4-10）：自绘文字不经过主题，显式引用与 default_theme 相同的字体资源，
## 保证怪物名 / 倒计时里的数字与 UI 其余部分同样等宽对齐。
const MONO_FONT := preload("res://assets/themes/mono_font.tres")

enum State { IDLE, PATROL, CHASE, ATTACK, RETURN, DEAD }

@export var monster_id: String = "wolf_corrupted"
var drop_table_override := ""
## 实际刷新等级；0 = 采用模板等级（地图生成器会按 tierRange 约束）
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
var sample_art: SampleActorArt
var dummy_art: Sprite2D

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
## M6-0a：当前外观半径（按 kind 决定），绘制与点击命中同源（见 game.gd::enemy_at_screen）。
var radius: float = RADIUS
var boss_phase := 0
var _boss_enraged := false
var _boss_beat := 0.0
## M6-0c：本实例掉落批次序号（与 ticks 拼成批次 ID，见 _settle_rewards）。
var _batch_seq: int = 0
var _stomp_pending := false
var _stomp_remaining := 0.0
var _stomp_cooldown := 0.0
var _stomp_center := Vector2.ZERO
var _stomp_radius := 0.0
var suppress_rewards := false
var _chapter_boss_warn := ""
var _chapter_boss_warn_left := 0.0
var _chapter_boss_origin := Vector2.ZERO
var _chapter_boss_target := Vector2.ZERO
var _chapter_boss_centers: Array[Vector2] = []
var _chapter_boss_skill_cd := 3.0
var _chapter_boss_casts := 0
var _chapter_boss_summons: Array[Monster] = []
var _special_warn := ""
var _special_warn_left := 0.0
var _special_target := Vector2.ZERO
var _special_cd := 3.0
var _charge_left := 0.0
var _charge_direction := Vector2.ZERO
var _charge_hit := false

var _rng := RandomNumberGenerator.new()
var _attack_cd: float = 0.0
var _ranged_windup := 0.0
var _ranged_target := Vector2.ZERO
var _support_heal_cd := 4.0
var _state_t: float = 0.0
var _patrol_target: Vector2 = Vector2.ZERO
var _flash_t: float = 0.0
var _flash_dirty: bool = false
var _cave_nav := CaveNavigator.new()

func _ready() -> void:
	add_to_group("enemies")
	_rng.randomize()
	_load_template()
	if monster_id in MonsterActorArt.IDS:
		sample_art = MonsterActorArt.attach_monster(self, monster_id)
	elif monster_id.begins_with("c2_"):
		sample_art = ChapterTwoArt.attach(self, monster_id)
	elif monster_id == "wolf_corrupted":
		sample_art = SampleActorArt.attach(self, "res://assets/sprites/monsters/wolf_corrupted/wolf_atlas.png", Vector2(40, 64), "", "res://assets/sprites/monsters/wolf_corrupted/wolf_walk_atlas.png")
	elif monster_id == "shellback_bug":
		sample_art = SampleActorArt.attach(self, "res://assets/sprites/monsters/shellback_bug/actor_atlas.png", Vector2(40, 64))
	elif monster_id == "ash_wraith":
		sample_art = SampleActorArt.attach(self, "res://assets/sprites/monsters/ash_wraith/actor_atlas.png", Vector2(32, 64))
	elif monster_id == "training_dummy":
		dummy_art = Sprite2D.new()
		dummy_art.name = "DummyArt"
		dummy_art.texture = load("res://assets/sprites/monsters/training_dummy/dummy_atlas.png") as Texture2D
		dummy_art.hframes = 3
		dummy_art.centered = false
		dummy_art.offset = Vector2(-32, -64)
		dummy_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(dummy_art)
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
	radius = radius_for_kind(_kind())
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

func _spawn_summons(id: String, count: int, after_death: bool = false, no_rewards: bool = false) -> void:
	if not is_inside_tree() or get_parent() == null or is_queued_for_deletion() or (is_dead and not after_death):
		return
	for i in range(count):
		var child := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
		child.monster_id = id
		child.spawn_level = level
		child.ai_enabled = true
		child.suppress_rewards = no_rewards
		var point := global_position + Vector2.from_angle(TAU * i / count) * 32.0
		var grid := Iso.world_to_grid(point)
		var dims := MapService.grid_size(GameState.current_map)
		grid = grid.clamp(Vector2.ZERO, Vector2(dims) - Vector2.ONE)
		point = _clamp_to_map(Iso.grid_pt(grid.x, grid.y))
		if MapService.is_in_rest_zone(GameState.current_map, point):
			point = global_position
		if MapService.is_in_rest_zone(GameState.current_map, point):
			continue
		child.position = get_parent().to_local(point)
		child.spawn_position = point
		get_parent().add_child(child)
		if no_rewards:
			_chapter_boss_summons.append(child)

## 返回 true 表示本帧由预警/践踏接管，禁止同帧普通攻击。
func _update_boss(delta: float) -> bool:
	if is_dead or template.get("kind", "") != "boss":
		return false
	if monster_id.begins_with("c2_boss_"):
		return _update_chapter_boss(delta)
	var skill: Dictionary = template.get("bossSkill", {})
	var phases: Array = skill.get("phases", [])
	var prev_phase := boss_phase
	for i in range(phases.size()):
		var phase: Dictionary = phases[i]
		if phase.has("hpBelow") and hp_ratio() < float(phase.hpBelow):
			boss_phase = maxi(boss_phase, i)
			if phase.get("behavior", "") == "enrage_summon" and not _boss_enraged:
				_boss_enraged = true
				queue_redraw()
				attack_interval = maxf(Combat.MIN_ATTACK_INTERVAL, attack_interval / (1.0 + float(phase.get("addAttackSpeedPct", 0))))
				_spawn_summons.call_deferred(String(phase.get("summon", "")), int(phase.get("summonCount", 0)))
				if sample_art is MonsterActorArt:
					(sample_art as MonsterActorArt).play_enrage()
				EventBus.toast_requested.emit(Localization.tr_key("msg.monster.p001") % display_name, "danger")
	if boss_phase != prev_phase:
		_announce_boss_hp()
	_stomp_cooldown = maxf(0.0, _stomp_cooldown - delta)
	if _stomp_pending:
		_stomp_remaining = maxf(0.0, _stomp_remaining - delta)
		queue_redraw()
		if _stomp_remaining <= 0:
			_stomp_pending = false
			if sample_art is MonsterActorArt:
				(sample_art as MonsterActorArt).finish_stomp()
			var target := _get_player()
			if target != null and target.global_position.distance_to(_stomp_center) <= _stomp_radius:
				_do_attack(target, false)
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
			if sample_art is MonsterActorArt:
				(sample_art as MonsterActorArt).begin_stomp(player.global_position - global_position, _stomp_remaining)
			queue_redraw()
			return true
	return false

## 第二章三种 Boss 使用固定预警时序；警示形状在命中前不会追踪玩家。
func _update_chapter_boss(delta: float) -> bool:
	var next_phase := 2 if hp_ratio() < 0.3 else 1 if hp_ratio() < 0.6 else 0
	if next_phase > boss_phase:
		boss_phase = next_phase
		_announce_boss_hp()
		if boss_phase == 2 and not _boss_enraged:
			_boss_enraged = true
			attack_interval /= 1.15 if monster_id != "c2_boss_slag_devourer" else 1.10
			if monster_id == "c2_boss_iron_foreman":
				_spawn_summons.call_deferred("c2_broken_guard", 2, false, true)
			elif monster_id == "c2_boss_hundred_arm_extractor":
				_spawn_summons.call_deferred("c2_spirit_larva", 3, false, true)
	_chapter_boss_skill_cd = maxf(0.0, _chapter_boss_skill_cd - delta)
	if not _chapter_boss_warn.is_empty():
		_chapter_boss_warn_left -= delta
		queue_redraw()
		if _chapter_boss_warn_left <= 0.0:
			_resolve_chapter_boss_warn()
		return true
	var player := _get_player()
	if player == null or global_position.distance_to(spawn_position) > leash_range:
		return false
	if state != State.CHASE and state != State.ATTACK:
		return false
	if _chapter_boss_skill_cd > 0.0 or global_position.distance_to(player.global_position) > 300.0:
		return false
	_chapter_boss_casts += 1
	_chapter_boss_origin = global_position
	_chapter_boss_target = player.global_position
	_chapter_boss_centers.clear()
	match monster_id:
		"c2_boss_iron_foreman":
			_chapter_boss_warn = "sweep" if boss_phase == 0 or _chapter_boss_casts % 2 == 0 else "line"
			_chapter_boss_warn_left = 1.0 if _chapter_boss_warn == "sweep" else 1.2
		"c2_boss_slag_devourer":
			_chapter_boss_warn = "line" if boss_phase == 0 else "blasts"
			_chapter_boss_warn_left = 1.0 if boss_phase == 0 else 1.4
			if _chapter_boss_warn == "blasts":
				var side := (_chapter_boss_target - _chapter_boss_origin).normalized().orthogonal() * 145.0
				_chapter_boss_centers = [_chapter_boss_target - side, _chapter_boss_target, _chapter_boss_target + side]
		_:
			_chapter_boss_warn = "circle" if boss_phase == 0 or _chapter_boss_casts % 2 == 0 else "line"
			_chapter_boss_warn_left = 1.2 if _chapter_boss_warn == "circle" else 1.5
	_chapter_boss_skill_cd = _chapter_boss_warn_left + 2.2
	queue_redraw()
	return true

func _resolve_chapter_boss_warn() -> void:
	var shape := _chapter_boss_warn
	_chapter_boss_warn = ""
	queue_redraw()
	if is_dead or not is_inside_tree():
		return
	var player := _get_player()
	if player == null:
		return
	var player_pos := player.global_position
	var hit := false
	match shape:
		"sweep":
			var direction := (_chapter_boss_target - _chapter_boss_origin).normalized()
			var toward := player_pos - _chapter_boss_origin
			hit = toward.length() <= 170.0 and direction.dot(toward.normalized()) >= 0.35
		"line":
			var end := _chapter_boss_origin + (_chapter_boss_target - _chapter_boss_origin).normalized() * 340.0
			hit = Geometry2D.get_closest_point_to_segment(player_pos, _chapter_boss_origin, end).distance_to(player_pos) <= 48.0
		"circle":
			hit = player_pos.distance_to(_chapter_boss_target) <= 88.0
		"blasts":
			for center in _chapter_boss_centers:
				if player_pos.distance_to(center) <= 66.0:
					hit = true
					break
	if hit:
		_do_attack(player, false)

func _settle_first_clear() -> void:
	if template.get("kind", "") != "boss" or bool(GameState.first_clear.get(monster_id, false)):
		return
	GameState.first_clear[monster_id] = true
	var reward: Dictionary = template.get("firstClearReward", {})
	var unlock := String(reward.get("unlock", ""))
	if not unlock.is_empty():
		GameState.unlocks[unlock] = true
	EventBus.boss_first_clear.emit(monster_id)
	EventBus.toast_requested.emit(Localization.tr_key("msg.monster.p002") % display_name, "levelup")

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

## M6-0a：敌人档次（normal / elite / boss）。
func _kind() -> String:
	return String(template.get("kind", "normal"))

## M6-0a（创意 07 §4）：按 kind 取外观半径（普通 13 / 精英 19 / Boss 36）。
## 绘制与点击命中同源，避免「大 Boss 点不中」。
static func radius_for_kind(kind: String) -> float:
	match kind:
		"elite":
			return RADIUS_ELITE
		"boss":
			return RADIUS_BOSS
		_:
			return RADIUS

## M6-0a（创意 07 §4）：向 HUD 广播 Boss 血量，供顶部血条刷新。
func _announce_boss_hp() -> void:
	if _kind() != "boss":
		return
	EventBus.boss_hp_changed.emit(display_name, hp, max_hp, boss_phase)

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
	if dummy_art != null:
		dummy_art.frame = 2 if is_dead else 1 if _flash_t > 0.0 else 0

	if is_dead:
		velocity = Vector2.ZERO
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	if _ranged_windup > 0.0:
		_ranged_windup -= delta
		if _ranged_windup <= 0.0 and state == State.ATTACK:
			_fire_chapter_projectile()
	if monster_id == "c2_spirit_attendant":
		_update_support_heal(delta)
	velocity = Vector2.ZERO
	if ai_enabled and not _update_boss(delta) and not _update_chapter_special(delta):
		_update_ai(delta)
	# M6-0a：交战期间每秒续期顶部血条（脱战即停 ⇒ HUD 3s 后隐藏）。
	if _kind() == "boss":
		_boss_beat -= delta
		if _boss_beat <= 0.0:
			_boss_beat = 1.0
			if state == State.CHASE or state == State.ATTACK:
				_announce_boss_hp()
	move_and_slide()

func _enter(s: int) -> void:
	if state == s:
		return
	state = s
	if s == State.RETURN or s == State.IDLE:
		_ranged_windup = 0.0
		_chapter_boss_warn = ""
	_state_t = 0.0
	# M6-0a：Boss 进入仇恨即点亮顶部血条（脱战停止心跳后由 HUD 自行隐藏）。
	if s == State.CHASE:
		_announce_boss_hp()
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
				if is_ranged and monster_id.begins_with("c2_"):
					_begin_chapter_projectile(player)
				else:
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
	for _i in range(8):
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(20.0, PATROL_RADIUS)
		var candidate := spawn_position + Vector2(cos(ang), sin(ang)) * r
		if not MapService.is_in_rest_zone(GameState.current_map, candidate):
			return candidate
	return spawn_position

func _approach(target_pos: Vector2) -> void:
	var world := get_tree().get_first_node_in_group("map_world")
	var ground := world.get_node_or_null("Ground") as IsoGround if world != null else null
	var to := _cave_nav.direction(ground, global_position, target_pos)
	if to.length() < 0.001:
		return
	var step := to * move_speed_px * get_physics_process_delta_time()
	if MapService.is_in_rest_zone(GameState.current_map, global_position + step):
		velocity = Vector2.ZERO
		return
	velocity = to * move_speed_px

func _get_player() -> Node2D:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return null
	if p.get("is_dead") == true:
		return null
	if MapService.is_in_rest_zone(GameState.current_map, (p as Node2D).global_position):
		return null
	return p as Node2D

func _update_chapter_special(delta: float) -> bool:
	if not monster_id in ["c2_ash_beast", "c2_elite_ash_leader", "c2_elite_broken_inspector"]:
		return false
	_special_cd = maxf(0.0, _special_cd - delta)
	var player := _get_player()
	if player == null or global_position.distance_to(spawn_position) > leash_range:
		_special_warn = ""
		_charge_left = 0.0
		return false
	if _charge_left > 0.0:
		_charge_left -= delta
		velocity = _charge_direction * move_speed_px * 2.5
		if not _charge_hit and player.global_position.distance_to(global_position) <= 32.0:
			_do_attack(player)
			_charge_hit = true
		return true
	if not _special_warn.is_empty():
		_special_warn_left -= delta
		queue_redraw()
		if _special_warn_left <= 0.0:
			var kind := _special_warn
			_special_warn = ""
			if kind == "charge":
				_charge_direction = (_special_target - global_position).normalized()
				_charge_left = 0.34
				_charge_hit = false
			elif player.global_position.distance_to(global_position) <= 135.0:
				_do_attack(player, false)
		return true
	if _special_cd > 0.0 or state not in [State.CHASE, State.ATTACK]:
		return false
	if player.global_position.distance_to(global_position) > (220.0 if monster_id != "c2_elite_broken_inspector" else 135.0):
		return false
	_special_warn = "sweep" if monster_id == "c2_elite_broken_inspector" else "charge"
	_special_target = player.global_position
	_special_warn_left = 0.8 if _special_warn == "sweep" else 0.7
	_special_cd = 4.5
	queue_redraw()
	return true

# ---- 攻击 ----

func _do_attack(player: Node2D, play_attack_art: bool = true) -> void:
	if MapService.is_in_rest_zone(GameState.current_map, player.global_position) or MapService.is_in_rest_zone(GameState.current_map, global_position):
		return
	_attack_cd = maxf(Combat.MIN_ATTACK_INTERVAL, attack_interval)
	if sample_art != null and play_attack_art:
		sample_art.attack(player.global_position - global_position, attack_interval)
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

func _begin_chapter_projectile(player: Node2D) -> void:
	_attack_cd = maxf(Combat.MIN_ATTACK_INTERVAL, attack_interval)
	_ranged_windup = 0.28
	_ranged_target = player.global_position
	if sample_art != null:
		sample_art.attack(_ranged_target - global_position, attack_interval)

func _fire_chapter_projectile() -> void:
	if is_dead or not is_inside_tree() or get_parent() == null:
		return
	var facing := (_ranged_target - global_position).normalized()
	if facing == Vector2.ZERO:
		return
	var count := 2 if monster_id == "c2_elite_gray_scribe" else 1
	for i in range(count):
		var bolt := MonsterProjectile.new()
		bolt.source = self
		bolt.direction = facing.rotated(-0.10 if i == 0 and count == 2 else 0.10 if count == 2 else 0.0)
		get_parent().add_child(bolt)
		bolt.global_position = global_position + bolt.direction * 22.0

func _update_support_heal(delta: float) -> void:
	_support_heal_cd -= delta
	if _support_heal_cd > 0.0:
		return
	_support_heal_cd = 4.0
	var best: Monster = null
	var nearest := 180.0 * 180.0
	for candidate in get_tree().get_nodes_in_group("enemies"):
		var ally := candidate as Monster
		if ally == null or ally == self or ally.is_dead or ally._kind() != "normal" \
				or ally.hp >= ally.max_hp or not ally.monster_id.begins_with("c2_"):
			continue
		var distance := global_position.distance_squared_to(ally.global_position)
		if distance < nearest:
			nearest = distance
			best = ally
	if best != null:
		best.hp = mini(best.max_hp, best.hp + maxi(1, roundi(best.max_hp * 0.10)))
		best.queue_redraw()

# ---- 受击 / 死亡 ----

## 承受一次已结算的攻击（由 Combat.resolve 产出）。miss 不扣血；受击转仇恨。
func take_hit(result: Dictionary, from: Node = null) -> void:
	if is_dead or bool(result.get("miss", false)):
		return
	if from is PlayerCharacter and (MapService.is_in_rest_zone(GameState.current_map, (from as Node2D).global_position) or MapService.is_in_rest_zone(GameState.current_map, global_position)):
		return
	hp = maxi(0, hp - int(result.get("damage", 0)))
	_flash_t = HIT_FLASH
	if sample_art != null:
		sample_art.hit()
	if hp <= 0:
		_die()
	else:
		if ai_enabled and from is Node2D and state != State.CHASE and state != State.ATTACK:
			_enter(State.CHASE)
		_announce_boss_hp()
		queue_redraw()

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	state = State.DEAD
	velocity = Vector2.ZERO
	if sample_art is MonsterActorArt:
		(sample_art as MonsterActorArt).begin_death()
		var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision != null:
			collision.set_deferred("disabled", true)
	_stomp_pending = false
	_chapter_boss_warn = ""
	_special_warn = ""
	_charge_left = 0.0
	for summon in _chapter_boss_summons:
		if is_instance_valid(summon):
			summon.queue_free()
	_chapter_boss_summons.clear()
	_announce_boss_hp()   # M6-0a：hp 已归零 ⇒ 触发顶部血条淡出
	_settle_first_clear()
	_settle_rewards()
	_spawn_death_summons.call_deferred()
	died.emit(monster_id)
	if not suppress_rewards:
		EventBus.monster_died.emit(monster_id)
	queue_redraw()
	# 淡出后移除；刷新由生成器按 respawnTime 处理（7.9）
	var tw := create_tween()
	if sample_art is MonsterActorArt:
		tw.tween_interval((sample_art as MonsterActorArt).death_duration())
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)

## 死亡结算（3.1：经验 / 掉落 / 任务，仅一次）。
## 经验即时结算；掉落按 dropTableId 走掉落表（M1-6，含金币作为地面拾取物）。
## 无掉落表时回退为直接结算模板金币（如教学木桩 goldReward=0）。
## 掉落结果聚合为一条「掉落」提示广播，与地面拾取时的「拾取」提示区分（9.6）。
## 任务推进在 M2 接入（订阅 EventBus.monster_died）。
func _settle_rewards() -> void:
	if suppress_rewards:
		return
	var xp := LevelGap.kill_xp(int(template.get("xpReward", 0)), int(GameState.player.get("level", 1)), level)
	if xp > 0:
		GameState.add_xp(xp)

	var table_id := drop_table_override if not drop_table_override.is_empty() else String(template.get("dropTableId", ""))
	if table_id.is_empty():
		var gold := int(template.get("goldReward", 0))
		if gold > 0:
			GameState.add_gold(gold)
			EventBus.toast_requested.emit(Localization.tr_key("msg.monster.p003") % [display_name, gold], "drop")
		return

	var rolled := Loot.roll(table_id, null, monster_id)
	# M6-0c（创意 07 §8）：整批掉落一次抽取（随机结果只生成一次），批次带唯一 ID。
	_batch_seq += 1
	var batch_id := "b_%d_%d" % [Time.get_ticks_msec(), _batch_seq]
	var kind := _kind()
	var persistent := kind in ["elite", "boss"]   # 精英 / Boss 未领取 ⇒ 跨图 / 跨档保留（§11）
	var anim := bool(GameState.settings.get("dropFlyAnim", true))   # 关闭 ⇒ 不散落 / 不飞行（§10）
	# M6-0d（创意 07 §9）：装备雨展示编排（出场时序 + 落地 + 停留 + 错峰起飞 + 分环散布）
	var plan := LootBurst.build(rolled, kind)
	# 认领序（§8，仅决定背包空间分配）与展示序（§9）解耦：高品质优先入包，展示按 plan 自带时序。
	# 认领在 `add_child` 时同步判定，故循环结束时「未领取装备数」已可确定（§11.1）。
	var unclaimed_equip := 0
	for row in _order_rows_by_claim(plan):
		var gi := _spawn_drop(row, batch_id, persistent, anim)
		if gi == null or gi.is_claimed():
			continue
		var it_v: Variant = row.get("item", {})
		if it_v is Dictionary and String((it_v as Dictionary).get("kind", "")) == "equip":
			unclaimed_equip += 1
	# M6-0e（创意 07 §10）：精英 / Boss 批次摘要（延迟到装备雨结束）+ 传说单独提示
	_announce_batch_summary(rolled, kind, plan, unclaimed_equip, anim)

## 入包认领序（创意 07 §8）：传说→史诗→稀有→优秀→普通；同品质按生成序号。
## 药水 / 如意 / 杂项排在装备之后，金币最后（独立入账）。分桶实现以保持**稳定次序**。
const _QUALITY_RANK := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}

static func _priority_order(items: Array) -> Array:
	var buckets := {6: [], 5: [], 4: [], 3: [], 2: [], 1: [], 0: []}
	for it in items:
		if not (it is Dictionary):
			continue
		var rank := _claim_rank(it as Dictionary)
		if not buckets.has(rank):
			buckets[rank] = []
		buckets[rank].append(it)
	var out: Array = []
	for rank in [6, 5, 4, 3, 2, 1, 0]:
		for it in buckets.get(rank, []):
			out.append(it)
	return out

## 认领优先级：金币 0 ＜ 药水 / 如意 / 杂项 1 ＜ 装备 2+品质序（普通 2 … 传说 6）。
static func _claim_rank(item: Dictionary) -> int:
	var kind := String(item.get("kind", ""))
	if kind == "coin":
		return 0
	if kind == "equip":
		return 2 + int(_QUALITY_RANK.get(String(item.get("quality", "common")), 0))
	return 1

## M6-0d（创意 07 §8 / §9）：把「展示编排行」按**入包认领序**重排（高品质优先占背包空间）。
## 与展示序解耦 —— 每行的出场 / 停驻 / 落点由 `LootBurst.build` 自带，不随本排序改变。
static func _order_rows_by_claim(rows: Array) -> Array:
	var buckets := {}
	for row in rows:
		if not (row is Dictionary):
			continue
		var rank := _claim_rank((row as Dictionary).get("item", {}))
		if not buckets.has(rank):
			buckets[rank] = []
		(buckets[rank] as Array).append(row)
	var ranks: Array = buckets.keys()
	ranks.sort()
	ranks.reverse()
	var out: Array = []
	for rank in ranks:
		for row in buckets[rank]:
			out.append(row)
	return out

## 聚合广播一条掉落提示：如「腐化野狼 掉落：金币 ×6 · 生命药水 · 稀有 布甲头盔 Lv2」。
func _announce_drops(items: Array) -> void:
	var parts: Array[String] = []
	for it in items:
		if it is Dictionary and not (it as Dictionary).is_empty():
			parts.append(ItemUtil.display_name(it))
	if parts.is_empty():
		return
	EventBus.toast_requested.emit(Localization.tr_key("msg.monster.p004") % [display_name, " · ".join(PackedStringArray(parts))], "drop")

## M6-0e（创意 07 §10）：批次摘要 + 传说提示。
## 精英 / Boss 用**批次摘要**替代旧逐件聚合提示（延迟到装备雨全部落地，§10「最后一份出场完成时」）；
## 普通怪沿用旧即时聚合提示（§1 普通怪沿用现有规则）。
func _announce_batch_summary(rolled: Array, kind: String, plan: Array, unclaimed_equip: int, anim: bool) -> void:
	if not (kind in ["elite", "boss"]):
		_announce_drops(rolled)
		return
	var delay := LootNotify.summary_delay(plan, anim)
	_emit_toast_delayed(LootNotify.summary_text(display_name, rolled, unclaimed_equip, not GameState.auto_pickup_on), "drop", delay)
	var legend := LootNotify.legendary_text(rolled)
	if not legend.is_empty():
		_emit_toast_delayed(legend, "legendary", delay)

## 延迟广播 toast（相对死亡帧 t=0）。`delay <= 0` 立即发；否则用 `SceneTreeTimer`，
## `process_always=false` ⇒ 暂停 / 后台冻结（与装备雨同一时钟，§9 / §10）。
## 回调只捕获文本，不引用本节点 —— 死亡后 Monster 被释放也不影响。
func _emit_toast_delayed(text: String, kind: String, delay: float) -> void:
	if delay <= 0.0:
		EventBus.toast_requested.emit(text, kind)
		return
	var tree := get_tree()
	if tree == null:
		EventBus.toast_requested.emit(text, kind)
		return
	tree.create_timer(delay, false).timeout.connect(func() -> void:
		EventBus.toast_requested.emit(text, kind))

## 生成一件地面掉落物（7.6 / 9.9）。
## M6-0c：`persistent`（精英 / Boss）⇒ 入包失败登记为「未领取战利品」，跨图 / 跨档保留（创意 07 §11）。
## M6-0d（创意 07 §9）：`row` 为 `LootBurst.build` 产出的展示编排行（出场延迟 / 落地时长 /
##   停驻 / 飞行时长 / 落点偏移）；`anim=false`（关闭 dropFlyAnim）⇒ 立即出场、不散落、不飞行（§10）。
## M6-0e（创意 07 §10）：精英 / Boss **装备**不逐件弹「拾取」提示（由批次摘要统一说明）。
## 返回生成的 `GroundItem`（供结算统计未领取件数）；无掉落层 / 非法物品时返回 `null`。
func _spawn_drop(row: Dictionary, batch_id: String = "", persistent: bool = false, anim: bool = true) -> GroundItem:
	var item_v: Variant = row.get("item", {})
	if not (item_v is Dictionary) or (item_v as Dictionary).is_empty():
		return null
	var item: Dictionary = item_v
	var layer := get_tree().get_first_node_in_group("loot_root")
	if layer == null:
		return null
	var gi: GroundItem = GROUND_ITEM_SCENE.instantiate()
	gi.item = item
	gi.auto_claim = GameState.auto_pickup_on
	gi.batch_id = batch_id
	gi.persistent = persistent
	gi.silent_pickup = persistent and String(item.get("kind", "")) == "equip"
	var offset := Vector2.ZERO
	var off_v: Variant = row.get("offset", Vector2.ZERO)
	if off_v is Vector2:
		offset = off_v
	if anim:
		gi.appear_delay = maxf(0.0, float(row.get("appear", 0.0)))
		gi.land_time = maxf(0.01, float(row.get("land_time", GroundItem.DROP_ARC_TIME)))
		gi.hold_time = maxf(0.0, float(row.get("hold", GroundItem.HOLD_TIME)))
		gi.fly_time = maxf(0.05, float(row.get("fly_time", GroundItem.FLY_TIME)))
	else:
		gi.appear_delay = 0.0
		gi.hold_time = 0.0
	layer.add_child(gi)
	# 落点：死亡位置 + 分环偏移。关闭动画时**认领物**不散落（立即飞走 / 消失），
	# 但**未领取物**仍需错开，避免多件叠在同一点而看不见（§10「未领取物仍须有可见地面标记」）。
	var apply_offset := anim or not gi.is_claimed()
	gi.global_position = _clamp_to_map(global_position + (offset if apply_offset else Vector2.ZERO))
	EventBus.item_dropped.emit(String(item.get("itemId", "")))
	EventBus.loot_spawned.emit(item)
	return gi

## M6-0d（创意 07 §9）：落点至少满足地图边界内；完整可走网格校验待障碍系统落地后复用。
## 找不到地面节点（测试 / 无世界上下文）时原样返回。
func _clamp_to_map(pos: Vector2) -> Vector2:
	var layer := get_tree().get_first_node_in_group("loot_root")
	if layer == null:
		return pos
	var world := layer.get_parent()
	if world == null:
		return pos
	var ground := world.get_node_or_null("Ground")
	if ground is IsoGround:
		return (ground as IsoGround).clamp_to_map(pos)
	return pos

func _draw() -> void:
	if not _chapter_boss_warn.is_empty() and not is_dead:
		_draw_chapter_boss_warn()
	if not _special_warn.is_empty() and not is_dead:
		if _special_warn == "sweep":
			draw_circle(Vector2.ZERO, 135.0, Color(1.0, 0.35, 0.08, 0.15))
			draw_arc(Vector2.ZERO, 135.0, 0.0, TAU, 48, Color("ff9c53"), 2.0, true)
		else:
			var end := to_local(global_position + (_special_target - global_position).normalized() * 230.0)
			draw_line(Vector2.ZERO, end, Color("ff9c53"), 22.0, true)
	if _stomp_pending and not is_dead:
		var center := to_local(_stomp_center)
		draw_circle(center, _stomp_radius, Color(1.0, 0.18, 0.05, 0.18))
		draw_arc(center, _stomp_radius, 0, TAU, 64, Color("ff623a"), 3.0, true)
		draw_string(MONO_FONT, center + Vector2(-50, -_stomp_radius - 8), Localization.tr_key("msg.monster.p005"), HORIZONTAL_ALIGNMENT_CENTER, 100, 16, Color("ffb65c"))
	if selected and not is_dead:
		draw_arc(Vector2.ZERO, radius + 7.0, 0, TAU, 40, Color("6eebe6"), 2.5, true)
	if sample_art != null or dummy_art != null:
		if sample_art is MonsterActorArt:
			_draw_sprite_identity()
		draw_set_transform(Vector2.ZERO, 0, Vector2(1, 0.45))
		draw_circle(Vector2.ZERO, radius if sample_art is MonsterActorArt else 17.0, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO)
		_draw_head_hp_bar()
		return
	match _kind():
		"elite":
			_draw_elite()
		"boss":
			_draw_boss()
		_:
			_draw_normal()
	_draw_head_hp_bar()

func _draw_chapter_boss_warn() -> void:
	var red := Color(1.0, 0.18, 0.08, 0.24)
	var edge := Color("ff7744")
	match _chapter_boss_warn:
		"sweep":
			var direction := (_chapter_boss_target - _chapter_boss_origin).normalized()
			var points := PackedVector2Array([to_local(_chapter_boss_origin)])
			for i in range(17):
				points.append(to_local(_chapter_boss_origin + direction.rotated(deg_to_rad(-68.0 + 8.5 * i)) * 170.0))
			draw_colored_polygon(points, red)
		"line":
			var direction := (_chapter_boss_target - _chapter_boss_origin).normalized()
			var side := direction.orthogonal() * 48.0
			var finish := _chapter_boss_origin + direction * 340.0
			draw_colored_polygon(PackedVector2Array([
				to_local(_chapter_boss_origin + side), to_local(finish + side),
				to_local(finish - side), to_local(_chapter_boss_origin - side)]), red)
			draw_line(to_local(_chapter_boss_origin), to_local(finish), edge, 2.0, true)
		"circle":
			draw_circle(to_local(_chapter_boss_target), 88.0, red)
			draw_arc(to_local(_chapter_boss_target), 88.0, 0.0, TAU, 48, edge, 2.0, true)
		"blasts":
			for center in _chapter_boss_centers:
				draw_circle(to_local(center), 66.0, red)
				draw_arc(to_local(center), 66.0, 0.0, TAU, 40, edge, 2.0, true)

## 受击白闪 / 仇恨变色的统一体色。
func _current_body(base: Color) -> Color:
	if _flash_t > 0.0:
		return Color.WHITE
	return COLOR_AGGRO if (state == State.CHASE or state == State.ATTACK) else base

## 普通怪（创意 07 §4）：既有圆身 + 深描边，无名，血条 34×4。
func _draw_normal() -> void:
	var c := Vector2(0.0, -radius * 0.6)
	draw_circle(c, radius, _current_body(COLOR_BODY))
	draw_arc(c, radius, 0.0, TAU, 24, COLOR_EDGE, 2.0, true)

## 精英（创意 07 §4）：双肩尖耳 + 单爪 + 金色双描边 + 金色菱形地面标识 + 常显名，血条 64×6。
func _draw_elite() -> void:
	var c := Vector2(0.0, -radius * 0.6)
	var body := _current_body(COLOR_ELITE_BODY)
	_draw_ground_mark(Color(0.95, 0.78, 0.36, 0.30), radius * 0.75)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-radius * 0.90, -radius * 0.40),
		c + Vector2(-radius * 0.38, -radius * 1.30),
		c + Vector2(-radius * 0.10, -radius * 0.55)]), body)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(radius * 0.90, -radius * 0.40),
		c + Vector2(radius * 0.38, -radius * 1.30),
		c + Vector2(radius * 0.10, -radius * 0.55)]), body)
	draw_circle(c, radius, body)
	draw_arc(c, radius, 0.0, TAU, 28, COLOR_ELITE_EDGE, 3.0, true)
	draw_arc(c, radius - 3.5, 0.0, TAU, 28, Color(0.99, 0.87, 0.47, 0.6), 1.3, true)
	draw_line(c + Vector2(radius * 0.70, radius * 0.30), c + Vector2(radius * 1.35, radius * 0.92), COLOR_ELITE_EDGE, 2.6, true)
	draw_string(MONO_FONT, Vector2(c.x - 110.0, -radius * 2.4 - 6.0), display_name,
		HORIZONTAL_ALIGNMENT_CENTER, 220.0, 13, COLOR_ELITE_EDGE)

## Boss（创意 07 §4）：双角双爪 + 暗红封印环（四刻度）+ 常显名，血条 100×8。
func _draw_boss() -> void:
	var c := Vector2(0.0, -radius * 0.6)
	var body := _current_body(COLOR_BOSS_BODY_ENRAGED if _boss_enraged else COLOR_BOSS_BODY)
	draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 48, COLOR_BOSS_RING, 2.2, true)
	for i in range(4):
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var dir := Vector2(cos(a), sin(a))
		draw_line(dir * (radius + 1.0), dir * (radius + 12.0), COLOR_BOSS_EDGE, 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-radius * 0.72, -radius * 0.55),
		c + Vector2(-radius * 0.46, -radius * 1.38),
		c + Vector2(-radius * 0.04, -radius * 0.64)]), COLOR_BOSS_EDGE)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(radius * 0.72, -radius * 0.55),
		c + Vector2(radius * 0.46, -radius * 1.38),
		c + Vector2(radius * 0.04, -radius * 0.64)]), COLOR_BOSS_EDGE)
	draw_circle(c, radius, body)
	draw_arc(c, radius, 0.0, TAU, 40, COLOR_BOSS_EDGE, 3.2, true)
	draw_line(c + Vector2(-radius * 0.68, radius * 0.42), c + Vector2(-radius * 1.24, radius * 1.00), COLOR_BOSS_EDGE, 3.0, true)
	draw_line(c + Vector2(radius * 0.68, radius * 0.42), c + Vector2(radius * 1.24, radius * 1.00), COLOR_BOSS_EDGE, 3.0, true)
	draw_string(MONO_FONT, Vector2(c.x - 150.0, -radius * 2.4 - 6.0), display_name,
		HORIZONTAL_ALIGNMENT_CENTER, 300.0, 15, Color("f4c9c9"))

## 金色菱形地面标识（精英；创意 07 §4「地面标识」）。
func _draw_ground_mark(color: Color, r: float) -> void:
	var g := Vector2(0.0, 6.0)
	draw_colored_polygon(PackedVector2Array([
		g + Vector2(0.0, -r), g + Vector2(r, 0.0), g + Vector2(0.0, r), g + Vector2(-r, 0.0)]), color)

## 头顶血条（9.5）：尺寸随档次 34×4 / 64×6 / 100×8（创意 07 §4）。
func _draw_head_hp_bar() -> void:
	var s := _head_hp_size()
	var x := -s.x * 0.5
	var y := _head_hp_y()
	draw_rect(Rect2(x, y, s.x, s.y), COLOR_HP_BG)
	draw_rect(Rect2(x, y, s.x * hp_ratio(), s.y), COLOR_HP_FG)
	draw_rect(Rect2(x, y, s.x, s.y), Color(0, 0, 0, 0.5), false, 1.0)

## 贴图怪默认沿用已验收的位置；特殊身高可在怪物模板中单独覆写。
func _head_hp_y() -> float:
	if sample_art is MonsterActorArt:
		return float(template.get("headHpY", -(sample_art as MonsterActorArt).pivot.y - 6.0))
	if sample_art != null or dummy_art != null:
		return float(template.get("headHpY", -46.0))
	return -radius * 2.4

func _draw_sprite_identity() -> void:
	if is_dead:
		return
	var boss := _kind() == "boss"
	if boss:
		draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 48, COLOR_BOSS_RING, 2.2, true)
	else:
		_draw_ground_mark(Color(0.95, 0.78, 0.36, 0.30), radius * 0.75)
	var width := 300.0 if boss else 220.0
	draw_string(MONO_FONT, Vector2(-width * 0.5, _head_hp_y() - 8.0), display_name,
		HORIZONTAL_ALIGNMENT_CENTER, width, 15 if boss else 13, Color("f4c9c9") if boss else COLOR_ELITE_EDGE)

func _head_hp_size() -> Vector2:
	match _kind():
		"elite":
			return Vector2(64.0, 6.0)
		"boss":
			return Vector2(100.0, 8.0)
		_:
			return Vector2(34.0, 4.0)
