class_name PlayerCharacter
extends CharacterBody2D
## 玩家角色：八向归一化移动 + 普攻（产品文档 4.6 操控 / 3.1 战斗流程 / 3.2 伤害公式）。
## M1-3/M1-4：移动 + 普攻结算；技能 / 自动战斗 / 超距走位在后续子步骤接入。
## 普攻设计为「离散事件」——每次成功发动只结算一次，天然满足 T04（不重复结算）。

const RADIUS := 12.0
const COLOR_BODY := Color("e8c07d")
const COLOR_EDGE := Color("6d4c1f")
const DAMAGE_NUMBER_SCENE := preload("res://scenes/ui/DamageNumber.tscn")

## 移动速度（像素/秒）= 属性表 movementSpeed（格/秒）× 瓦片宽
var _speed: float = 256.0
## 普攻冷却计时（s）
var _attack_cd: float = 0.0
## 普攻技能定义（skills.json: basic_slash）
var _basic: Dictionary = {}

func _ready() -> void:
	add_to_group("player")
	_speed = float(GameState.player.get("movementSpeed", 4.0)) * Iso.TILE_W
	_basic = DataLoader.get_entry("skills", "basic_slash")
	if _basic == null:
		_basic = {"coefficient": 1.0, "range": 1.0}

func _physics_process(delta: float) -> void:
	# Input.get_vector 已做归一化：斜向不会比正向更快（八向移动）
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * _speed
	move_and_slide()

	# 普攻：按住攻击键，冷却结束即发动一次（每次发动 = 一次结算）
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if Input.is_action_pressed("attack") and _attack_cd <= 0.0:
		_try_attack()

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
	if target == null or not is_instance_valid(target):
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

	_spawn_damage_number(target, result)
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

func _spawn_damage_number(target: Node, result: Dictionary) -> void:
	var layer := get_tree().get_first_node_in_group("damage_numbers")
	var t2d := target as Node2D
	if layer == null or t2d == null:
		return
	var dn: Node2D = DAMAGE_NUMBER_SCENE.instantiate()
	# 连续命中时错位堆叠，避免飘字互相覆盖（9.5）
	var stagger := 14.0 * float(layer.get_child_count() % 3)
	dn.position = t2d.global_position + Vector2(0, -28 - stagger)
	dn.setup(int(result.get("damage", 0)), bool(result.get("critical", false)), bool(result.get("miss", false)))
	layer.add_child(dn)

func _draw() -> void:
	# 占位角色：圆形身体 + 描边（脚底碰撞体见 CollisionShape2D）
	draw_circle(Vector2.ZERO, RADIUS, COLOR_BODY)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 28, COLOR_EDGE, 2.0, true)
