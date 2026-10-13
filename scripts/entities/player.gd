class_name PlayerCharacter
extends CharacterBody2D
## 玩家角色：八向归一化移动 + 普攻 + 受击保护 + 死亡占位。
## 依据：产品文档 4.6 操控 / 3.1 战斗流程 / 3.2 伤害公式 / 3.4 受击保护 / 4.7 死亡。
## M1-3/M1-4：移动 + 普攻结算；M1-5：受击硬直 + 无敌帧 + 死亡复活占位；
## M1-9：暴露自动移动 / 自动攻击接口（供 AutoBattle 决策机驱动，3.14）。
## 普攻设计为「离散事件」——每次成功发动只结算一次，天然满足 T04（不重复结算）。
## 锁定目标超距接近与点击普攻已接入；技能格随后续技能系统接线。

const RADIUS := 12.0
const ART_SCALE := 1.25  # 玩家外观放大；碰撞和战斗距离仍使用原逻辑尺寸。
const COLOR_BODY := Color("e8c07d")
const COLOR_EDGE := Color("6d4c1f")
const COLOR_DEAD := Color("8a8a8a")
const COLOR_HEAD_HP_BG := Color(0.08, 0.08, 0.10, 0.85)
const COLOR_HEAD_HP_FG := Color("61c985")
const MONO_FONT := preload("res://assets/themes/mono_font.tres")

const IFRAME := 0.5            # 3.4：受击后无敌帧时长（s）
const HITSTUN := 0.25          # 3.4：受击硬直时长（s，期间无法主动行动）
const DEATH_REVIVE_DELAY := 3.0  # 4.7 死亡流程占位（正式复活对话框见 M3）
const MANUAL_EPS := 0.05       # 手动输入判定阈值（摇杆量）
const REGEN_COMBAT_DELAY := 5.0
const IDLE_HP_RATE := 0.01      # 每秒按最大值恢复；小数余量逐帧累积
const IDLE_MP_RATE := 0.02
const SIT_HP_RATE := 0.03
const SIT_MP_RATE := 0.05

## 减速是实体运行态，死亡清除，不写存档。
var _slow_pct := 0.0
var _slow_remaining := 0.0

## 同强度刷新时间，较弱减速不会覆盖较强效果；不乘算叠加。
func apply_slow(percent: float, duration: float) -> void:
	if is_dead or percent <= 0 or duration <= 0:
		return
	if percent >= _slow_pct or _slow_remaining <= 0:
		_slow_pct = clampf(percent, 0.0, 0.95)
		_slow_remaining = duration

func movement_multiplier() -> float:
	return 1.0 - _slow_pct if _slow_remaining > 0 else 1.0

## 移动速度（像素/秒）= 属性表 movementSpeed（格/秒）× 瓦片宽
var _speed: float = 256.0
## 普攻冷却计时（s）
var _attack_cd: float = 0.0
## 主动技能冷却为角色运行态；切图保留、暂停冻结、读档重新创建。
var skill_cooldowns: Dictionary = {}
var _pending_skill_id := ""
## 普攻技能定义（skills.json: basic_slash）
var _basic: Dictionary = {}
## 受击保护计时
var _invuln: float = 0.0
var _stun: float = 0.0
## 死亡占位计时
var _death_t: float = 0.0
var is_dead: bool = false
var is_sitting: bool = false
var sample_art: SampleActorArt

## 自动战斗的移动意图（3.14）：由 AutoBattle 写入。
## **手动输入优先**——玩家一按方向键即完全接管（4.6），无需 AutoBattle 额外干预。
var auto_move: Vector2 = Vector2.ZERO
## 上一帧是否检测到手动输入（供 auto_battle 判定「手动接管」）。
var manual_input_active: bool = false
## 锁定目标与手动指令归玩家持有；地面/大地图/追击共用移动与普攻，不保存运行态路线。
var locked_target: Node2D = null
var target_is_manual := false
var manual_attack_active := false
var map_move_active := false
var _map_destination := Vector2.ZERO
var _map_check_t := 0.0
var _map_last_distance := INF
var _map_stuck_count := 0
var _cave_path: Array[Vector2] = []
var _cave_path_index := 0
var _cave_target_cell := Vector2i(-1, -1)
var _map_background := false
var _combat_cooldown := 0.0
var _hp_regen_rest := 0.0
var _mp_regen_rest := 0.0

func valid_target(target: Variant) -> bool:
	return is_instance_valid(target) and target is Node2D and not target.is_queued_for_deletion() and target.get("is_dead") != true and target.has_method("take_hit") and not MapService.is_in_rest_zone(GameState.current_map, target.global_position)

func clear_travel_intent() -> void:
	map_move_active = false
	manual_attack_active = false
	_pending_skill_id = ""
	auto_move = Vector2.ZERO
	velocity = Vector2.ZERO
	_map_destination = global_position
	select_target(null)

func select_target(target: Node2D, manual: bool = true) -> void:
	if target != null and not valid_target(target):
		target = null
	if is_instance_valid(locked_target) and locked_target.has_method("set_selected"):
		locked_target.set_selected(false)
	locked_target = target
	target_is_manual = manual and target != null
	if locked_target != null and locked_target.has_method("set_selected"):
		locked_target.set_selected(true)
	EventBus.target_changed.emit(locked_target)

func begin_manual_command() -> void:
	set_sitting(false)
	auto_move = Vector2.ZERO
	var pilot := get_node_or_null("AutoPilot") as AutoBattle
	if pilot != null:
		pilot.begin_manual_override()

func request_target_attack(target: Node2D) -> bool:
	if is_dead or not valid_target(target):
		return false
	select_target(target)
	_pending_skill_id = ""
	map_move_active = false
	manual_attack_active = true
	reset_move_progress(target.global_position)
	begin_manual_command()
	return true

func reset_move_progress(point: Vector2) -> void:
	_map_destination = point
	_map_last_distance = global_position.distance_to(point)
	_map_check_t = 0.0
	_map_stuck_count = 0
	_cave_path.clear()
	_cave_path_index = 0
	_cave_target_cell = Vector2i(-1, -1)

func _manual_attack_direction(delta: float) -> Vector2:
	if not valid_target(locked_target):
		manual_attack_active = false
		select_target(null)
		return Vector2.ZERO
	var reach := melee_range_px()
	if not _pending_skill_id.is_empty():
		var pending = DataLoader.get_entry("skills", _pending_skill_id)
		if pending is Dictionary:
			reach = float(pending.get("range", 1.0)) * Iso.TILE_W
	if not MapService.is_in_safe_area(GameState.current_map, global_position) \
		and global_position.distance_to(locked_target.global_position) <= reach - AutoBattle.STOP_GAP:
		_map_stuck_count = 0
		_map_check_t = 0.0
		_map_last_distance = INF
		if not _pending_skill_id.is_empty():
			if cast_skill(_pending_skill_id, locked_target):
				_pending_skill_id = ""
				manual_attack_active = false
		else:
			try_auto_attack(locked_target)
		return Vector2.ZERO
	_map_destination = locked_target.global_position
	return _map_direction(delta)

func request_map_move(point: Vector2) -> bool:
	if is_dead or not point.is_finite():
		return false
	manual_attack_active = false
	_pending_skill_id = ""
	map_move_active = true
	reset_move_progress(point)
	begin_manual_command()
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_map_background = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_map_background = false

func _map_direction(delta: float) -> Vector2:
	var distance := global_position.distance_to(_map_destination)
	if distance <= AutoBattle.LOOT_ARRIVE_EPS:
		map_move_active = false
		return Vector2.ZERO
	var waypoint := _map_destination
	var world := get_tree().get_first_node_in_group("map_world")
	if world != null:
		var ground := world.get_node_or_null("Ground") as IsoGround
		if ground != null and ground.cave != null:
			var target_cell := Vector2i(Iso.world_to_grid(_map_destination).round())
			if _cave_path.is_empty() or target_cell != _cave_target_cell:
				_cave_path = ground.route(global_position, _map_destination)
				_cave_target_cell = target_cell
				_cave_path_index = 0
			if _cave_path.is_empty():
				map_move_active = false
				manual_attack_active = false
				EventBus.toast_requested.emit("目标不可达，请换一个位置", "danger")
				return Vector2.ZERO
			var old_index := _cave_path_index
			while _cave_path_index < _cave_path.size() and global_position.distance_to(_cave_path[_cave_path_index]) < 9.0:
				_cave_path_index += 1
			if _cave_path_index != old_index:
				_map_last_distance = INF
				_map_stuck_count = 0
				_map_check_t = 0.0
			if _cave_path_index < _cave_path.size():
				waypoint = _cave_path[_cave_path_index]
			elif target_cell != Vector2i(Iso.world_to_grid(global_position).round()):
				_cave_path.clear()
				return Vector2.ZERO
			distance = global_position.distance_to(waypoint)
	_map_check_t += delta
	if _map_check_t >= AutoBattle.STUCK_INTERVAL:
		_map_check_t = 0.0
		_map_stuck_count = _map_stuck_count + 1 if _map_last_distance - distance < AutoBattle.STUCK_PROGRESS_EPS else 0
		_map_last_distance = distance
		if _map_stuck_count >= AutoBattle.STUCK_LIMIT:
			map_move_active = false
			manual_attack_active = false
			EventBus.toast_requested.emit("前往目标受阻，请换一个位置或目标", "danger")
			return Vector2.ZERO
	return global_position.direction_to(waypoint)

func _ready() -> void:
	sample_art = SampleActorArt.attach(self, "res://assets/sprites/player/guardian/guardian_atlas.png", Vector2(32, 64), "res://assets/sprites/player/guardian/guardian_hit_sit_atlas.png", "res://assets/sprites/player/guardian/guardian_walk_atlas.png")
	sample_art.display_scale = ART_SCALE
	add_to_group("player")
	_speed = float(GameState.player.get("movementSpeed", 4.0)) * Iso.TILE_W
	var b = DataLoader.get_entry("skills", "basic_slash")
	_basic = b if b is Dictionary else {"coefficient": 1.0, "range": 1.0}
	skill_cooldowns = GameState.skill_cooldowns
	EventBus.player_hp_changed.connect(func(_current: int, _maximum: int) -> void: queue_redraw())

func _physics_process(delta: float) -> void:
	if locked_target != null and not valid_target(locked_target):
		manual_attack_active = false
		select_target(null)
	_slow_remaining = maxf(0.0, _slow_remaining - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)

	if is_dead:
		auto_move = Vector2.ZERO
		manual_input_active = false
		velocity = Vector2.ZERO
		move_and_slide()
		_death_t += delta
		if _death_t >= DEATH_REVIVE_DELAY:
			_revive()
		_update_blink()
		return
	_tick_regen(delta)

	_stun = maxf(0.0, _stun - delta)
	if is_sitting:
		var wants_move := Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > MANUAL_EPS
		if wants_move or Input.is_action_pressed("attack"):
			set_sitting(false)
		else:
			auto_move = Vector2.ZERO
			manual_input_active = false
			velocity = Vector2.ZERO
			move_and_slide()
			_update_blink()
			return

	# 面板接管手动输入；F 挂机已开启时仍执行自动战斗的移动意图。
	if GameState.panel_open and not GameState.auto_battle_on:
		auto_move = Vector2.ZERO
		manual_input_active = false
		velocity = Vector2.ZERO
		move_and_slide()
		_update_blink()
		return

	# Input.get_vector 已做归一化：斜向不会比正向更快（八向移动）
	var dir := Vector2.ZERO if GameState.panel_open else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	manual_input_active = dir.length() > MANUAL_EPS
	if GameState.panel_open:
		manual_attack_active = false
		_pending_skill_id = ""
		map_move_active = false
	if manual_input_active:
		map_move_active = false
		manual_attack_active = false
		_pending_skill_id = ""
	if not GameState.panel_open and Input.is_action_pressed("attack") and not manual_input_active and not manual_attack_active:
		if valid_target(locked_target):
			request_target_attack(locked_target)
		else:
			map_move_active = false
	if manual_attack_active or map_move_active:
		if _map_background:
			dir = Vector2.ZERO
		elif _stun <= 0.0:
			dir = _manual_attack_direction(delta) if manual_attack_active else _map_direction(delta)
		manual_input_active = true
	# 手动输入优先；无手动输入时由自动战斗的移动意图接管（3.14：自动与手动共用同一移动路径）
	if not manual_input_active and auto_move != Vector2.ZERO:
		dir = auto_move
	if _stun > 0.0:
		dir = Vector2.ZERO   # 硬直期间无法主动移动（3.4）
	velocity = dir * _speed * movement_multiplier() * GameState.mount_speed_multiplier()
	move_and_slide()

	# 普攻：按住攻击键，冷却结束即发动一次（每次发动 = 一次结算）
	if not GameState.panel_open and not manual_attack_active and _stun <= 0.0 and Input.is_action_pressed("attack") and _attack_cd <= 0.0:
		_try_attack()

	_update_blink()

# ---- 受击保护 / 死亡（3.4 / 4.7）----

## 承受怪物攻击，返回实际扣血量；无敌帧内返回 0，供吸血与附伤判定。
func apply_damage(amount: int) -> int:
	if is_dead or _invuln > 0.0 or amount <= 0 or MapService.is_in_rest_zone(GameState.current_map, global_position):
		return 0
	set_sitting(false)
	if sample_art != null:
		sample_art.hit()
	_invuln = IFRAME
	_stun = HITSTUN
	_mark_combat()
	var actual := mini(amount, int(GameState.player.hp))
	if GameState.damage_player(amount):
		_begin_death()
	return actual

func _begin_death() -> void:
	if is_dead:
		return
	set_sitting(false)
	map_move_active = false
	manual_attack_active = false
	_pending_skill_id = ""
	select_target(null)
	_slow_remaining = 0.0
	_slow_pct = 0.0
	is_dead = true
	_hp_regen_rest = 0.0
	_mp_regen_rest = 0.0
	_death_t = 0.0
	velocity = Vector2.ZERO
	queue_redraw()
	EventBus.toast_requested.emit("你倒下了……%.0f 秒后恢复（占位流程，正式死亡/复活见后续阶段）" % DEATH_REVIVE_DELAY, "danger")

## 占位复活：满 HP / MP 原地恢复（4.7「不掉等级 / 装备 / 金币」）。
func _revive() -> void:
	is_dead = false
	_death_t = 0.0
	_invuln = 1.0
	_stun = 0.0
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()
	GameState.emit_all()
	queue_redraw()
	EventBus.toast_requested.emit("已恢复（占位复活）", "info")

## 受击闪烁：无敌帧内高频闪烁，死亡保留半透明。
func _update_blink() -> void:
	if is_dead:
		modulate.a = 0.35
	elif _invuln > 0.0:
		modulate.a = 0.45 + 0.55 * absf(sin(_invuln * 14.0))
	else:
		modulate.a = 1.0

# ---- 自动战斗接口（M1-9，3.14：自动与手动共用同一移动 / 攻击路径）----

## 设置自动移动意图（由 AutoBattle 调用）。手动输入优先，见 _physics_process。
func set_auto_move(dir: Vector2) -> void:
	auto_move = dir

## 攻击是否就绪：未死亡、不在受击硬直、攻击冷却已结束（3.9：自动不绕过攻速）。
func is_attack_ready() -> bool:
	return not is_dead and _stun <= 0.0 and _attack_cd <= 0.0

## 自动战斗对指定目标发动一次普攻。返回是否真正发动。
## 冷却中 / 硬直中 / 目标已失效 → 返回 false（不结算、不推进冷却）。
func try_auto_attack(target: Node) -> bool:
	if not is_attack_ready() or MapService.is_in_safe_area(GameState.current_map, global_position):
		return false
	if not valid_target(target):
		return false
	if not target is Node2D or global_position.distance_to(target.global_position) > melee_range_px():
		return false
	_attack_cd = maxf(Combat.MIN_ATTACK_INTERVAL, float(GameState.player.get("attackInterval", 0.8)))
	perform_attack(target)
	return true

# ---- 攻击 ----

## 普攻的攻击距离上限（格 → 像素）。超距自动走位（3.15）与自动战斗（3.14）共用。
func melee_range_px() -> float:
	return float(_basic.get("range", 1.0)) * Iso.TILE_W

func skill_cooldown(skill_id: String) -> float:
	return float(skill_cooldowns.get(skill_id, 0.0))

## 快捷栏手动指令：选中目标后接近至技能射程，再由同一施放入口结算。
func request_skill(skill_id: String) -> bool:
	var skill = DataLoader.get_entry("skills", skill_id)
	if not HotbarConfig.ACTIVE_SKILLS.has(skill_id) or not skill is Dictionary:
		return false
	if skill_id == "basic_slash":
		if valid_target(locked_target):
			return request_target_attack(locked_target)
		EventBus.toast_requested.emit("请先选中怪物", "danger")
		return false
	if is_dead or int(GameState.player.level) < int(skill.get("unlockLevel", 1)):
		EventBus.toast_requested.emit("技能尚未解锁", "danger")
		return false
	if int(GameState.player.mp) < int(skill.get("manaCost", 0)):
		EventBus.toast_requested.emit("法力不足", "danger")
		return false
	if skill_cooldown(skill_id) > 0.0:
		EventBus.toast_requested.emit("技能冷却中", "danger")
		return false
	if String(skill.get("shape", "")) == "circle":
		if skill_targets(skill).is_empty():
			EventBus.toast_requested.emit("范围内没有可攻击的怪物", "danger")
			return false
		begin_manual_command()
		if not cast_skill(skill_id):
			EventBus.toast_requested.emit("当前无法施放技能", "danger")
			return false
		return true
	if not valid_target(locked_target):
		EventBus.toast_requested.emit("请先选中怪物", "danger")
		return false
	map_move_active = false
	manual_attack_active = true
	_pending_skill_id = skill_id
	reset_move_progress(locked_target.global_position)
	begin_manual_command()
	return true

## 所有入口共用的实际施放；失败时不耗蓝、不进入冷却。
func cast_skill(skill_id: String, target: Node = null) -> bool:
	var skill = DataLoader.get_entry("skills", skill_id)
	if not HotbarConfig.ACTIVE_SKILLS.has(skill_id) or skill_id == "basic_slash" or not skill is Dictionary:
		return false
	if is_dead or _stun > 0.0 or _attack_cd > 0.0 or MapService.is_in_safe_area(GameState.current_map, global_position):
		return false
	if int(GameState.player.level) < int(skill.get("unlockLevel", 1)) or skill_cooldown(skill_id) > 0.0:
		return false
	var mana_cost := int(skill.get("manaCost", 0))
	if int(GameState.player.mp) < mana_cost:
		return false
	var targets := skill_targets(skill, target)
	if targets.is_empty() or not GameState.spend_mp(mana_cost):
		return false
	skill_cooldowns[skill_id] = float(skill.get("cooldown", 0.0))
	_attack_cd = maxf(Combat.MIN_ATTACK_INTERVAL, float(GameState.player.get("attackInterval", 0.8)))
	_mark_combat()
	if sample_art != null:
		sample_art.attack((targets[0] as Node2D).global_position - global_position, _attack_cd)
	var range_fx := preload("res://scripts/systems/skill_range_fx.gd").new() as Node2D
	range_fx.shape = String(skill.get("shape", "circle"))
	range_fx.radius = float(skill.get("range", 1.0)) * Iso.TILE_W
	range_fx.facing = global_position.direction_to((target as Node2D).global_position) if String(skill.get("shape", "")) == "cone" else Vector2.RIGHT
	add_child(range_fx)
	for enemy in targets:
		var result := Combat.resolve(float(GameState.total_attack()), _target_defense(enemy),
			float(skill.get("coefficient", 1.0)), float(GameState.player.get("criticalChance", 0.0)),
			float(GameState.player.get("criticalMultiplier", 1.5)), _target_dodge(enemy))
		Fx.damage_number(get_tree(), enemy, result)
		EventBus.damage_dealt.emit(enemy, int(result.get("damage", 0)), bool(result.get("critical", false)))
		enemy.take_hit(result, self)
	return true

## 按真实位置求命中集合；圆形以自身为中心，扇形面向锁定目标。
func skill_targets(skill: Dictionary, target: Node = null) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var shape := String(skill.get("shape", "single"))
	var reach := float(skill.get("range", 1.0)) * Iso.TILE_W
	var facing := Vector2.RIGHT
	if shape == "cone":
		if not valid_target(target):
			return result
		facing = global_position.direction_to((target as Node2D).global_position)
		if facing == Vector2.ZERO:
			facing = Vector2.RIGHT
	for raw in get_tree().get_nodes_in_group("enemies"):
		if not valid_target(raw):
			continue
		var enemy := raw as Node2D
		var offset := enemy.global_position - global_position
		if offset.length() > reach:
			continue
		if shape == "cone" and offset.length() > 0.01 and facing.dot(offset.normalized()) < cos(PI / 4.0):
			continue
		result.append(enemy)
	result.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	if shape == "cone" and result.size() > int(skill.get("maxTargets", 3)):
		result.resize(int(skill.get("maxTargets", 3)))
	return result

## 尝试普攻：优先锁定目标；无锁定时使用范围内最近敌人。
func _try_attack() -> void:
	if MapService.is_in_safe_area(GameState.current_map, global_position):
		return
	var target: Node = locked_target if valid_target(locked_target) else find_nearest_enemy_in_range()
	if target == null or global_position.distance_to(target.global_position) > melee_range_px():
		return
	_attack_cd = maxf(Combat.MIN_ATTACK_INTERVAL, float(GameState.player.get("attackInterval", 0.8)))
	perform_attack(target)

## 对指定目标结算一次普攻（供手动 / 自动化测试调用）。返回结算结果。
func perform_attack(target: Node) -> Dictionary:
	if is_dead or MapService.is_in_safe_area(GameState.current_map, global_position) or not valid_target(target):
		return {}
	_mark_combat()
	if sample_art != null:
		sample_art.attack((target as Node2D).global_position - global_position, float(GameState.player.get("attackInterval", 0.8)))
		var slash := preload("res://scripts/systems/sample_slash.gd").new() as Node2D
		slash.direction = ((target as Node2D).global_position - global_position).angle()
		slash.position = Vector2(0, -16 * ART_SCALE)
		add_child(slash)

	var result := Combat.resolve(
		float(GameState.total_attack()),
		_target_defense(target),
		float(_basic.get("coefficient", 1.0)),
		float(GameState.player.get("criticalChance", 0.0)),
		float(GameState.player.get("criticalMultiplier", 1.5)),
		_target_dodge(target))

	Fx.damage_number(get_tree(), target as Node2D, result)
	EventBus.damage_dealt.emit(target, int(result.get("damage", 0)), bool(result.get("critical", false)))
	if locked_target != target:
		select_target(target as Node2D, false)
	target.take_hit(result, self)
	return result

func _mark_combat() -> void:
	_combat_cooldown = REGEN_COMBAT_DELAY
	_hp_regen_rest = 0.0
	_mp_regen_rest = 0.0

func _tick_regen(delta: float) -> void:
	if _map_background or get_tree().paused:
		return
	var recovery_delta := maxf(0.0, delta - _combat_cooldown)
	_combat_cooldown = maxf(0.0, _combat_cooldown - delta)
	var pilot := get_node_or_null("AutoPilot") as AutoBattle
	if recovery_delta <= 0.0 or manual_attack_active or (pilot != null and pilot.current_target() != null):
		return
	var hp_max := GameState.max_hp()
	var mp_max := GameState.max_mp()
	if int(GameState.player.hp) < hp_max:
		_hp_regen_rest += float(hp_max) * (SIT_HP_RATE if is_sitting else IDLE_HP_RATE) * recovery_delta
		var hp_points := int(floorf(_hp_regen_rest))
		if hp_points > 0:
			_hp_regen_rest -= hp_points
			GameState.heal_player(hp_points)
	else:
		_hp_regen_rest = 0.0
	if int(GameState.player.mp) < mp_max:
		_mp_regen_rest += float(mp_max) * (SIT_MP_RATE if is_sitting else IDLE_MP_RATE) * recovery_delta
		var mp_points := int(floorf(_mp_regen_rest))
		if mp_points > 0:
			_mp_regen_rest -= mp_points
			GameState.restore_mp(mp_points)
	else:
		_mp_regen_rest = 0.0

## 攻击范围内的最近敌人（手动普攻的目标搜索；自动战斗为 3.14 的锚点搜索）。
func find_nearest_enemy_in_range() -> Node:
	var rng_px := melee_range_px()
	var best: Node = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not valid_target(e):
			continue
		var d := global_position.distance_to((e as Node2D).global_position)
		if d <= rng_px and d < best_d:
			best_d = d
			best = e
	return best

func _target_defense(t: Node) -> float:
	return t.get_defense() if t.has_method("get_defense") else 0.0

func _target_dodge(t: Node) -> float:
	return t.get_dodge() if t.has_method("get_dodge") else 0.0

func _draw() -> void:
	if sample_art != null:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.45))
		draw_circle(Vector2.ZERO, 14 * ART_SCALE, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO)
		if is_sitting:
			draw_arc(Vector2.ZERO, 19, 0, TAU, 24, Color("78d8d0"), 1.0)
		_draw_overhead_name(-99.0)
		_draw_overhead_hp(-92.0)
		return
	# 占位角色：圆形身体 + 描边；死亡态转灰（脚底碰撞体见 CollisionShape2D）
	var body := COLOR_DEAD if is_dead else COLOR_BODY
	if is_sitting:
		draw_circle(Vector2(0, 5), RADIUS, body)
		draw_arc(Vector2(0, 5), RADIUS, 0.0, TAU, 28, COLOR_EDGE, 2.0, true)
		draw_line(Vector2(-15, 17), Vector2(15, 17), COLOR_EDGE, 3.0)
	else:
		draw_circle(Vector2.ZERO, RADIUS, body)
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 28, COLOR_EDGE, 2.0, true)
	_draw_overhead_name(-37.0)
	_draw_overhead_hp(-30.0)

func _draw_overhead_name(baseline_y: float) -> void:
	var name := String(GameState.player.get("name", "守护者"))
	var origin := Vector2(-90.0, baseline_y)
	draw_string(MONO_FONT, origin + Vector2(1.0, 1.0), name,
		HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(MONO_FONT, origin, name,
		HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, Color("a7efed"))

func _draw_overhead_hp(y: float) -> void:
	var width := 60.0
	var height := 5.0
	var ratio := clampf(float(GameState.player.hp) / float(maxi(1, GameState.max_hp())), 0.0, 1.0)
	var rect := Rect2(-width * 0.5, y, width, height)
	draw_rect(rect, COLOR_HEAD_HP_BG)
	draw_rect(Rect2(rect.position, Vector2(width * ratio, height)), COLOR_HEAD_HP_FG)
	draw_rect(rect, Color(0, 0, 0, 0.65), false, 1.0)

func set_sitting(value: bool) -> void:
	if is_dead and value or is_sitting == value:
		return
	is_sitting = value
	if value:
		map_move_active = false
		manual_attack_active = false
		auto_move = Vector2.ZERO
		velocity = Vector2.ZERO
		var pilot := get_node_or_null("AutoPilot") as AutoBattle
		if pilot != null:
			pilot.begin_manual_override()
	EventBus.player_sitting_changed.emit(is_sitting)
	queue_redraw()
