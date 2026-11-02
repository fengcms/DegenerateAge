class_name MonsterActorArt
extends SampleActorArt
## 怪物八方向动画表现：图集横轴为时间、纵轴为方向，生命周期由宿主驱动。
## 仅负责姿势与动画；伤害、召唤和奖励仍由Monster统一结算。

const IDS := ["elite_wolf_king", "elite_ash_wraith", "elite_shellback_bug", "boss_corrupted_beast"]

var definitions: Dictionary = {}
var frame_size := Vector2.ZERO
var pivot := Vector2.ZERO
var _textures: Dictionary = {}
var _cycle_elapsed := 0.0
var _action := ""
var _elapsed := 0.0
var _duration := 0.0
var _start_frame := 0
var _death_started := false
var _death_elapsed := 0.0
var _warning_duration := 0.0
var _warning_pose := false
var _queued_enrage := false

## 从共享缓存挂接怪物动画图集，缺失素材时返回空。
static func attach_monster(actor: Node2D, id: String) -> MonsterActorArt:
	var raw: Variant = MonsterAnimationCache.get_pack(id)
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		push_error("Missing monster animation pack: " + id)
		return null
	var art := MonsterActorArt.new()
	art.name = "MonsterArt"
	art.definitions = raw.states
	art.frame_size = Vector2(raw.frameSize[0], raw.frameSize[1])
	art.pivot = Vector2(raw.pivot[0], raw.pivot[1])
	art.centered = false
	art.offset = -art.pivot
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for key: String in art.definitions:
		art._textures[key] = art.definitions[key].texture as Texture2D
	actor.add_child(art)
	art._show_pose("idle", 0)
	return art

## 按动作、帧和朝向更新显示，不执行战斗结算。
func _show_pose(key: String, step: int) -> void:
	if not definitions.has(key):
		return
	pose = key
	phase = clampi(step, 0, int(definitions[key].frames) - 1)
	frame = 0
	texture = _textures[key]
	hframes = int(definitions[key].frames)
	vframes = 8
	frame_coords = Vector2i(phase, facing)

## 开始一次有时长的表现动作，记录起始帧。
func _begin(key: String, duration: float, first_frame: int = 0) -> void:
	_action = key
	_elapsed = 0.0
	_duration = maxf(0.01, duration)
	_start_frame = first_frame
	_show_pose(key, first_frame)

## 展示既有普攻接触帧和后摇，不覆盖践踏与死亡。
func attack(vector: Vector2, interval: float) -> void:
	if _action in ["stomp", "enrage_summon"] or _death_started:
		return
	face(vector)
	# Existing combat resolves immediately: show contact now, then recovery.
	_begin("attack", clampf(interval * 0.45, 0.12, 0.4), int(definitions.attack.contact))

## 播放短受击反馈，保留正在进行的预警动作。
func hit() -> void:
	if _action in ["stomp", "enrage_summon"] or _death_started:
		return
	_begin("hit", HIT_SECONDS)

## 进入践踏抬臂预警，时钟沿用宿主物理预警。
func begin_stomp(vector: Vector2, warning_seconds: float) -> void:
	if _action == "enrage_summon":
		_queued_enrage = true
	face(vector)
	_warning_duration = maxf(0.01, warning_seconds)
	_warning_pose = true
	_begin("stomp", _warning_duration)

## 预警结算后展示践踏接触帧。
func finish_stomp() -> void:
	_warning_pose = false
	_begin("stomp", 0.25, int(definitions.stomp.contact))

## 播放狂暴表现，践踏期间排队等待。
func play_enrage() -> void:
	if _action == "stomp":
		_queued_enrage = true
	else:
		_begin("enrage_summon", 0.55)

## 返回死亡动画的秒数，供宿主安排释放。
func death_duration() -> float:
	return float(definitions.death.frames) / float(definitions.death.fps)

## 清理待播放动作并开始死亡动画。
func begin_death() -> void:
	_death_started = true
	_death_elapsed = 0.0
	_action = ""
	_queued_enrage = false
	_show_pose("death", 0)

## 返回本地显示边界，供现有选中检测使用。
func actor_hit_rect() -> Rect2:
	return Rect2(-pivot * display_scale, frame_size * display_scale)

## 按宿主状态推进表现，不独立推进技能预警时钟。
func _process(delta: float) -> void:
	var actor := get_parent() as Monster
	if actor == null:
		return
	actor.z_index = clampi(roundi(actor.global_position.y), -3500, 3500)
	scale = Vector2.ONE * display_scale
	if actor.is_dead:
		if not _death_started:
			begin_death()
		_death_elapsed += delta
		_show_pose("death", int(_death_elapsed * float(definitions.death.fps)))
		return
	if _action == "stomp" and _warning_pose:
		# Use the actual physics warning clock, not a second animation timer.
		var contact := int(definitions.stomp.contact)
		var progress := clampf(1.0 - actor._stomp_remaining / _warning_duration, 0.0, 1.0)
		_show_pose("stomp", mini(contact - 1, int(progress * contact)))
		return
	if not _action.is_empty():
		_elapsed += delta
		if _elapsed < _duration:
			var count := int(definitions[_action].frames)
			_show_pose(_action, _start_frame + int(_elapsed / _duration * (count - _start_frame)))
			return
		_action = ""
		if _queued_enrage:
			_queued_enrage = false
			play_enrage()
			return
	var wanted := "walk" if actor.velocity.length_squared() > 1.0 and definitions.has("walk") else "idle"
	if wanted != pose:
		_cycle_elapsed = 0.0
	_cycle_elapsed += delta
	if wanted == "walk":
		face(actor.velocity)
	var def: Dictionary = definitions[wanted]
	_show_pose(wanted, posmod(int(_cycle_elapsed * float(def.fps)), int(def.frames)))

## 脱战取消未落地践踏，回到正常待机/行走，不播放命中帧或追加狂暴动作。
func cancel_stomp() -> void:
	if _action != "stomp":
		return
	_warning_pose = false
	_action = ""
	_queued_enrage = false
