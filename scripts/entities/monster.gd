class_name Monster
extends Node2D
## 怪物实体（M1-4 最小版：属性读取 / 受击结算 / 死亡消失）。
##
## 属性来源 monsters.json；HP 按《07 地图关卡与怪物》17.1 派生公式随刷新等级缩放。
## M1-4 关闭 AI（不移动 / 不攻击）——仅作为普攻与伤害结算的可验证目标；
## M1-5 接入状态机（巡逻 / 追击 / 攻击）后打开 ai_enabled。

const M_HP_PER_LV := 0.12   # 17.1：每高 1 级约 +12% 生命（初始参数）

@export var monster_id: String = "wolf_corrupted"
## 实际刷新等级；0 = 采用模板等级（地图等级梯度 / 等级差在 M3 接入）
@export var spawn_level: int = 0
## M1-4 为 false（静态目标）；M1-5 打开
@export var ai_enabled: bool = false

signal died(id: String)

var template: Dictionary = {}
var display_name: String = "怪物"
var level: int = 1
var max_hp: int = 1
var hp: int = 1
var is_dead: bool = false

const RADIUS := 13.0
const COLOR_BODY := Color("9c5a4a")
const COLOR_EDGE := Color("3d221c")
const COLOR_HP_BG := Color(0.08, 0.08, 0.10, 0.85)
const COLOR_HP_FG := Color("d2383c")

func _ready() -> void:
	add_to_group("enemies")
	_load_template()
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

## 17.1：monsterMaxHP = max(1, round(hpBase × (1 + M_HP_PER_LV × (spawnLevel − templateLevel))))
func _derive_max_hp(tpl_level: int) -> int:
	var hp_base := float(template.get("hpBase", 1))
	var scaled := hp_base * (1.0 + M_HP_PER_LV * float(level - tpl_level))
	return maxi(1, int(round(scaled)))

func get_attack() -> float:
	return float(template.get("attack", 0))

func get_defense() -> float:
	return float(template.get("defense", 0))

func get_dodge() -> float:
	return float(template.get("dodge", 0.0))

func hp_ratio() -> float:
	return float(hp) / float(maxi(1, max_hp))

## 承受一次已结算的攻击（由 Combat.resolve 产出）。miss 不扣血。
func take_hit(result: Dictionary, _from: Node = null) -> void:
	if is_dead or bool(result.get("miss", false)):
		return
	hp = maxi(0, hp - int(result.get("damage", 0)))
	if hp <= 0:
		_die()
	else:
		queue_redraw()

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	died.emit(monster_id)
	EventBus.monster_died.emit(monster_id)
	# 占位：淡出后移除（经验 / 金币 / 掉落结算在 M1-5 / M1-6 接入）
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)

func _draw() -> void:
	# 占位身体
	var body_center := Vector2(0.0, -RADIUS * 0.6)
	draw_circle(body_center, RADIUS, COLOR_BODY)
	draw_arc(body_center, RADIUS, 0.0, TAU, 24, COLOR_EDGE, 2.0, true)
	# 头顶血条（9.5：目标血条）
	var w := 34.0
	var h := 4.0
	var x := -w * 0.5
	var y := -RADIUS * 2.4
	draw_rect(Rect2(x, y, w, h), COLOR_HP_BG)
	draw_rect(Rect2(x, y, w * hp_ratio(), h), COLOR_HP_FG)
