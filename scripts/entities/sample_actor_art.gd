class_name SampleActorArt
extends Sprite2D
## 八向角色的视觉播放入口。已登记的玩家阶段形象使用独立状态图集，其他形象与怪物保留既有关键姿态播放。
## 只更新 Sprite2D，不驱动移动、碰撞、攻击结算或死亡清理。

const HIT_SECONDS := 0.16
const DEATH_SECONDS := 0.6
const WALK_ROWS := [0, 0, 1, 1, 2, 2, 3, 3]
const WALK_BOB := [0.0, -0.5, -1.0, -0.5, 0.0, -0.5, -1.0, -0.5]

var facing := 0
var pose := "idle"
var phase := 0
var display_scale := 1.0
var extra_texture: Texture2D
var walk_texture: Texture2D
var _main_texture: Texture2D
var _clock := 0.0
var _death_clock := 0.0
var _attack_left := 0.0
var _attack_duration := 0.28
var _hit_left := 0.0
var _animations: Dictionary = {}
var _mounts: Dictionary = {}
var _mount_id := ""
var _base_pivot := Vector2.ZERO

static func attach(actor: Node2D, path: String, pivot: Vector2, extra_path := "", walk_path := "") -> SampleActorArt:
	var art := _create(actor)
	var definition := {"main": load(path) as Texture2D, "extra": null, "walk": null, "pivot": pivot}
	if not extra_path.is_empty():
		definition["extra"] = load(extra_path) as Texture2D
	if not walk_path.is_empty():
		definition["walk"] = load(walk_path) as Texture2D
	art.apply_look(definition)
	return art

## 按已登记的角色形象（CharacterLook 表项）装配，直接复用纹理资源。
static func attach_look(actor: Node2D, definition: Dictionary) -> SampleActorArt:
	var art := _create(actor)
	art.apply_look(definition)
	return art

## 建好空精灵并挂到角色下；图集、帧格与锚点随后由 apply_look 统一设置。
static func _create(actor: Node2D) -> SampleActorArt:
	var art := SampleActorArt.new()
	art.name = "SampleArt"
	art.hframes = 8
	art.vframes = 8
	art.centered = false
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	actor.add_child(art)
	return art

## 切换整套形象。阶段形象方案是整体换图，不叠加分层、也不新增渲染层。
## 保持当前朝向、姿势与显示缩放，只替换纹理并修正脚底锚点；主图集缺失时不改动现状。
func apply_look(definition: Dictionary) -> void:
	var main: Texture2D = definition.get("main")
	if main == null:
		return
	_main_texture = main
	extra_texture = definition.get("extra")
	walk_texture = definition.get("walk")
	var pivot: Vector2 = definition.get("pivot", Vector2.ZERO)
	_base_pivot = pivot
	_animations = definition.get("animations", {})
	_mounts = definition.get("mounts", {})
	offset = -pivot
	# 换装时立即更新当前帧；没有对应坐骑素材的形象按普通角色显示。
	if not _animations.is_empty():
		_show_frame(pose if _animations.has(pose) else "idle", phase)
	else:
		texture = _main_texture
		vframes = 8
		hframes = 8
		frame_coords = Vector2i(facing, 0)
	_mount_id = _mount_id if _mounts.has(_mount_id) else ""

## 骑乘状态变化时选择已登记图集；缺失坐骑美术只回退画面，不修改游戏骑乘规则。
func set_mount(mount_id: String) -> void:
	_mount_id = mount_id if _mounts.has(mount_id) else ""
	if not _animations.is_empty():
		_show_frame(pose if _animations.has(pose) else "idle", phase)

## 显示阶段形象的一帧；帧行由动作状态决定，列由八向朝向决定，脚底锚点随图集切换。
func _show_frame(next_pose: String, next_phase: int) -> void:
	pose = next_pose
	var animation: Dictionary = _animations[next_pose]
	var wanted: Texture2D = animation.texture
	var frames: int = animation.frames
	var pivot := _base_pivot
	if not _mount_id.is_empty() and next_pose in ["idle", "walk"]:
		var mount: Dictionary = _mounts[_mount_id]
		wanted = mount[next_pose]
		frames = 4
		pivot = mount.pivot
	phase = clampi(next_phase, 0, frames - 1)
	if texture != wanted:
		texture = wanted
		hframes = 8
		vframes = frames
	offset = -pivot
	frame_coords = Vector2i(facing, phase)

func face(vector: Vector2) -> void:
	if vector.length_squared() > 0.01:
		facing = posmod(roundi((vector.angle() - PI / 2.0) / (PI / 4.0)), 8)

func attack(vector: Vector2, interval: float) -> void:
	face(vector)
	_attack_duration = clampf(interval * 0.65, 0.12, 0.36)
	_attack_left = _attack_duration
	_hit_left = 0.0
	# Damage is resolved by the owner on this same call. Start at contact,
	# followed by follow-through and recovery.
	if _animations.is_empty():
		_show("attack", 0, 5)
	else:
		_show_frame("attack", 0)

func hit() -> void:
	_hit_left = HIT_SECONDS
	_attack_left = 0.0

func _show(next_pose: String, next_phase: int, row: int, supplemental := false, walking := false) -> void:
	pose = next_pose
	phase = next_phase
	var wanted := walk_texture if walking and walk_texture != null else extra_texture if supplemental and extra_texture != null else _main_texture
	if texture != wanted:
		texture = wanted
		vframes = 4 if wanted == walk_texture else 2 if wanted == extra_texture else 8
	frame_coords = Vector2i(facing, row)

func _process(delta: float) -> void:
	_clock += delta
	_attack_left = maxf(0.0, _attack_left - delta)
	_hit_left = maxf(0.0, _hit_left - delta)
	var actor := get_parent() as CharacterBody2D
	if actor == null:
		return
	actor.z_index = clampi(roundi(actor.global_position.y), -3500, 3500)
	if not _animations.is_empty():
		_process_frames(actor, delta)
		return
	var motion := Vector2.ONE
	position = Vector2.ZERO
	rotation = 0.0
	if actor.get("is_dead") == true:
		_death_clock = minf(_death_clock + delta, DEATH_SECONDS)
		var step := mini(5, int(_death_clock / DEATH_SECONDS * 6.0))
		# Brief recoil before the prone pose makes the fall readable. The owner
		# still controls death, fade and revival timing.
		if step == 0:
			_show("death", step, 0 if extra_texture != null else 6, extra_texture != null)
		else:
			_show("death", step, 7)
		motion = Vector2(1.0 + step * 0.004, 1.0 - step * 0.004)
	else:
		_death_clock = 0.0
		if _hit_left > 0.0:
			var step := mini(1, int((1.0 - _hit_left / HIT_SECONDS) * 2.0))
			_show("hit", step, 0 if extra_texture != null else 6, extra_texture != null)
			rotation = (0.045 if step == 0 else 0.015) * (-1.0 if facing in [1, 2, 3] else 1.0)
			motion = Vector2(1.0 + 0.015 * (1 - step), 1.0 - 0.025 * (1 - step))
		elif actor.get("is_sitting") == true and extra_texture != null:
			var step := posmod(int(_clock * 6.0), 4)
			_show("sit", step, 1, true)
			motion.y = [1.0, 0.99, 0.985, 0.99][step]
		elif _attack_left > 0.0:
			var step := mini(5, int((1.0 - _attack_left / _attack_duration) * 6.0))
			_show("attack", step, 5 if step < 3 else 4)
			rotation = [-0.045, -0.07, -0.03, 0.025, 0.015, 0.0][step] * (-1.0 if facing in [1, 2, 3] else 1.0)
			motion = Vector2(1.0 + [0.0, 0.02, 0.01, -0.01, 0.0, 0.0][step], 1.0)
		elif actor.velocity.length_squared() > 1.0:
			face(actor.velocity)
			var step := posmod(int(_clock * 10.0), 8)
			_show("walk", step, WALK_ROWS[step] if walk_texture != null else 2 + posmod(int(step / 2), 2), false, walk_texture != null)
			position.y = WALK_BOB[step]
			motion.x = [1.0, 0.99, 1.0, 1.01, 1.0, 0.99, 1.0, 1.01][step]
		else:
			var step := posmod(int(_clock * 6.0), 4)
			_show("idle", step, 0 if step in [0, 3] else 1)
			motion.y = [1.0, 1.005, 1.01, 1.005][step]
	scale = motion * display_scale

## 按现有角色状态播放六状态逐帧动画；只读速度和动作计时，保持结算时间不变。
func _process_frames(actor: CharacterBody2D, delta: float) -> void:
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE * display_scale
	if actor.get("is_dead") == true:
		_death_clock = minf(_death_clock + delta, DEATH_SECONDS)
		_show_frame("death", mini(5, int(_death_clock / DEATH_SECONDS * 6.0)))
		return
	_death_clock = 0.0
	if _hit_left > 0.0:
		_show_frame("hit", mini(1, int((1.0 - _hit_left / HIT_SECONDS) * 2.0)))
	elif actor.get("is_sitting") == true:
		_show_frame("sit", posmod(int(_clock * 6.0), 4))
	elif _attack_left > 0.0:
		_show_frame("attack", mini(5, int((1.0 - _attack_left / _attack_duration) * 6.0)))
	elif actor.velocity.length_squared() > 1.0:
		face(actor.velocity)
		_show_frame("walk", posmod(int(_clock * 10.0), 8 if _mount_id.is_empty() else 4))
	else:
		_show_frame("idle", posmod(int(_clock * 6.0), 4))
