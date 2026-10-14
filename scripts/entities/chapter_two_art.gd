class_name ChapterTwoArt
extends RefCounted
## Optional formal art packs. Incomplete packs leave the gameplay placeholder intact.

const MANIFEST := "res://data/chapter2_art_manifest.json"
const REQUIRED_STATES := ["idle", "walk", "attack", "hit", "death"]
static var _manifest: Dictionary = {}
static var _loaded := false
static var _warned: Dictionary = {}

static func attach(actor: Node2D, actor_id: String) -> MonsterActorArt:
	var spec := _actor_spec(actor_id)
	if spec.is_empty():
		_warn_once(actor_id, "缺少正式美术包，使用玩法占位图")
		return null
	var states: Variant = spec.get("states", {})
	var frame_size: Variant = spec.get("frame_size", [])
	var foot: Variant = spec.get("foot_anchor", [])
	if not states is Dictionary or not frame_size is Array or frame_size.size() != 2 \
			or not foot is Array or foot.size() != 2 or int(spec.get("directions", 0)) != 8:
		_warn_once(actor_id, "正式美术包元数据不完整，使用玩法占位图")
		return null
	var definitions := {}
	for state in REQUIRED_STATES:
		var row: Variant = states.get(state, null)
		if not row is Dictionary or not row.get("path") is String \
				or not ResourceLoader.exists(String(row.path)) or int(row.get("frames", 0)) <= 0 \
				or float(row.get("fps", 0.0)) <= 0.0:
			_warn_once(actor_id, "缺少 %s 动画或帧元数据，使用玩法占位图" % state)
			return null
		var texture := load(String(row.path)) as Texture2D
		if texture == null or texture.get_width() != int(frame_size[0]) * int(row.frames) \
				or texture.get_height() != int(frame_size[1]) * 8:
			_warn_once(actor_id, "%s 动画尺寸与 manifest 不符，使用玩法占位图" % state)
			return null
		definitions[state] = {"texture": texture, "frames": int(row.frames),
			"fps": float(row.fps), "contact": int(row.get("contact", 0))}
	var art := MonsterActorArt.new()
	art.name = "ChapterTwoArt"
	art.definitions = definitions
	art.frame_size = Vector2(float(frame_size[0]), float(frame_size[1]))
	art.pivot = Vector2(float(foot[0]), float(foot[1]))
	art.centered = false
	art.offset = -art.pivot
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state in definitions:
		art._textures[state] = definitions[state].texture
	actor.add_child(art)
	art._show_pose("idle", 0)
	return art

static func _actor_spec(actor_id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var file := FileAccess.open(MANIFEST, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_manifest = parsed
	var actors: Variant = _manifest.get("actors", {})
	if actors is Dictionary and actors.get(actor_id) is Dictionary:
		return actors[actor_id]
	return {}

static func _warn_once(actor_id: String, detail: String) -> void:
	if _warned.has(actor_id):
		return
	_warned[actor_id] = true
	push_warning("[ChapterTwoArt] %s：%s" % [actor_id, detail])
