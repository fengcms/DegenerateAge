class_name PlayerCharacter
extends CharacterBody2D
## 玩家角色：八向归一化移动 + 普攻 + 受击保护 + 死亡占位。
## 依据：产品文档 4.6 操控 / 3.1 战斗流程 / 3.2 伤害公式 / 3.4 受击保护 / 4.7 死亡。
## M1-3/M1-4：移动 + 普攻结算；M1-5：受击硬直 + 无敌帧 + 死亡复活占位。
## 普攻设计为「离散事件」——每次成功发动只结算一次，天然满足 T04（不重复结算）。
## 技能 / 自动战斗 / 超距走位在后续子步骤接入。

const RADIUS := 12.0
const COLOR_BODY := Color("e8c07d")
const COLOR_EDGE := Color("6d4c1f")
const COLOR_DEAD := Color("8a8a8a")

const IFRAME := 0.5            # 3.4：受击后无敌帧时长（s）
const HITSTUN := 0.25          # 3.4：受击硬直时长（s，期间无法主动行动）
const DEATH_REVIVE_DELAY := 3.0  # 4.7 死亡流程占位（正式复活对话框见 M3）

## 移动速度（像素/秒）= 属性表 movementSpeed（格/秒）× 瓦片宽
var _speed: float = 256.0
## 普攻冷却计时（s）
var _attack_cd: float = 0.0
## 普攻技能定义（skills.json: basic_slash）
var _basic: Dictionary = {}
## 受击保护计时
var _invuln: float = 0.0
var _stun: float = 0.0
## 死亡占位计时
var _death_t: float = 0.0
var is_dead: bool = false

func _ready() -> void:
	add_to_group("player")
	_speed = float(GameState.player.get("movementSpeed", 4.0)) * Iso.TILE_W
	var b = DataLoader.get_entry("skills", "basic_slash")
	_basic = b if b is Dictionary else {"coefficient": 1.0, "range": 1.0}

func _physics_process(delta: float) -> void:
	_invuln = maxf(0.0, _invuln - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)

	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		_death_t += delta
		if _death_t >= DEATH_REVIVE_DELAY:
			_revive()
		_update_blink()
		return

	_stun = maxf(0.0, _stun - delta)

	# Input.get_vector 已做归一化：斜向不会比正向更快（八向移动）
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _stun > 0.0:
		dir = Vector2.ZERO   # 硬直期间无法主动移动（3.4）
	velocity = dir * _speed
	move_and_slide()

	# 普攻：按住攻击键，冷却结束即发动一次（每次发动 = 一次结算）
	if _stun <= 0.0 and Input.is_action_pressed("attack") and _attack_cd <= 0.0:
		_try_attack()

	_update_blink()

# ---- 受击保护 / 死亡（3.4 / 4.7）----

## 承受怪物攻击（Combat.resolve 已结算）。无敌帧内忽略；否则进入硬直 + 触发闪烁。
func apply_damage(amount: int) -> void:
	if is_dead or _invuln > 0.0 or amount <= 0:
		return
	_invuln = IFRAME
	_stun = HITSTUN
	if GameState.damage_player(amount):
		_begin_death()

func _begin_death() -> void:
	if is_dead:
		return
	is_dead = true
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

# ---- 攻击 ----

## 普攻附加的最近目标距离上限（格 → 像素）。M3-7 接入「超距自动走位」后改为自动接近。
func _melee_range_px() -> float:
	return float(_basic.get("range", 1.0)) * Iso.TILE_W

## 尝试普攻：找到攻击范围内最近的敌人则发动（无目标则不动作）。
func _try_attack() -> void:
	var target := find_nearest_enemy_in_range()
	if target == null:
		return
	_attack_cd = maxf(Combat.MIN_ATTACK_INTERVAL, float(GameState.player.get("attackInterval", 0.8)))
	perform_attack(target)

## 对指定目标结算一次普攻（供手动 / 自动化测试调用）。返回结算结果。
func perform_attack(target: Node) -> Dictionary:
	if is_dead or target == null or not is_instance_valid(target):
		return {}
	if target.get("is_dead") == true or not target.has_method("take_hit"):
		return {}

	var result := Combat.resolve(
		float(GameState.player.get("attack", 0)),
		_target_defense(target),
		float(_basic.get("coefficient", 1.0)),
		float(GameState.player.get("criticalChance", 0.0)),
		float(GameState.player.get("criticalMultiplier", 1.5)),
		_target_dodge(target))

	Fx.damage_number(get_tree(), target as Node2D, result)
	EventBus.damage_dealt.emit(target, int(result.get("damage", 0)), bool(result.get("critical", false)))
	EventBus.target_changed.emit(target)
	target.take_hit(result, self)
	return result

## 攻击范围内的最近敌人（attacking 目标搜索，M1-4 仅手动）。
func find_nearest_enemy_in_range() -> Node:
	var rng_px := _melee_range_px()
	var best: Node = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.get("is_dead") == true:
			continue
		if not (e is Node2D):
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
	# 占位角色：圆形身体 + 描边；死亡态转灰（脚底碰撞体见 CollisionShape2D）
	var body := COLOR_DEAD if is_dead else COLOR_BODY
	draw_circle(Vector2.ZERO, RADIUS, body)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 28, COLOR_EDGE, 2.0, true)
