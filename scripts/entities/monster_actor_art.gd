class_name MonsterActorArt
extends SampleActorArt
## Real directional animation atlases: time on X, screen direction on Y.
## Presentation only; damage, spawning and rewards remain owned by Monster.

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

func _begin(key: String, duration: float, first_frame: int = 0) -> void:
	_action = key
	_elapsed = 0.0
	_duration = maxf(0.01, duration)
	_start_frame = first_frame
	_show_pose(key, first_frame)

func attack(vector: Vector2, interval: float) -> void:
	if _action in ["stomp", "enrage_summon"] or _death_started:
		return
	face(vector)
	# Existing combat resolves immediately: show contact now, then recovery.
	_begin("attack", clampf(interval * 0.45, 0.12, 0.4), int(definitions.attack.contact))

func hit() -> void:
	if _action in ["stomp", "enrage_summon"] or _death_started:
		return
	_begin("hit", HIT_SECONDS)

func begin_stomp(vector: Vector2, warning_seconds: float) -> void:
	if _action == "enrage_summon":
		_queued_enrage = true
	face(vector)
	_warning_duration = maxf(0.01, warning_seconds)
	_warning_pose = true
	_begin("stomp", _warning_duration)

func finish_stomp() -> void:
	_warning_pose = false
	_begin("stomp", 0.25, int(definitions.stomp.contact))

func play_enrage() -> void:
	if _action == "stomp":
		_queued_enrage = true
	else:
		_begin("enrage_summon", 0.55)

func death_duration() -> float:
	return float(definitions.death.frames) / float(definitions.death.fps)

func begin_death() -> void:
	_death_started = true
	_death_elapsed = 0.0
	_action = ""
	_queued_enrage = false
	_show_pose("death", 0)

func actor_hit_rect() -> Rect2:
	return Rect2(-pivot * display_scale, frame_size * display_scale)

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
