extends Node
## 第一章事件音效。音频为原创占位 WAV，可直接替换同名资源。

const AUDIO_PATH := "res://assets/audio/"
const CUES := ["hit", "hurt", "death", "pickup", "level", "equip", "boss"]
const MIN_GAP_MS := {"hit": 90, "hurt": 180, "pickup": 110, "boss": 900}

var _players: Dictionary = {}
var _last_played: Dictionary = {}
var cue_counts: Dictionary = {}
var _music: AudioStreamPlayer
var _last_hp := -1
## M10-3b（P-7）：按「Boss 实例」记状态 —— 单游标在多目标下会让不同 Boss 互相顶掉，
## 每次心跳都判成「换 Boss / 升阶段」⇒ 每秒反复播 boss 音。
var _boss_seen: Dictionary = {}
var _ready_for_events := false

func _ready() -> void:
	SettingsRuntime.apply_audio()
	_music = AudioStreamPlayer.new()
	_music.name = "AmbientMusic"
	_music.bus = "Music"
	_music.volume_db = -8.0
	add_child(_music)
	var music_stream := load(AUDIO_PATH + "ambient_loop.wav") as AudioStreamWAV
	if music_stream != null:
		music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_music.stream = music_stream
		if not SettingsRuntime.is_headless():
			_music.play()
	for cue in CUES:
		var player := AudioStreamPlayer.new()
		player.name = cue.capitalize() + "Cue"
		player.bus = "SFX"
		player.stream = load(AUDIO_PATH + cue + ".wav") as AudioStream
		add_child(player)
		_players[cue] = player
	_last_hp = int(GameState.player.get("hp", 0))
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.player_hp_changed.connect(_on_player_hp_changed)
	EventBus.player_died.connect(func() -> void: play_cue("death"))
	EventBus.item_picked.connect(func(_id: String) -> void: play_cue("pickup"))
	EventBus.player_leveled.connect(func(_level: int) -> void: play_cue("level"))
	EventBus.equipment_changed.connect(func() -> void: play_cue("equip"))
	EventBus.boss_hp_changed.connect(_on_boss_hp_changed)
	_ready_for_events = true

func _exit_tree() -> void:
	_music.stop()
	_music.stream = null
	for cue in CUES:
		var player := _players.get(cue) as AudioStreamPlayer
		if player != null:
			player.stop()
			player.stream = null
	_players.clear()

func play_cue(cue: String) -> void:
	if not _ready_for_events or not _players.has(cue):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(cue, -10_000)) < int(MIN_GAP_MS.get(cue, 0)):
		return
	_last_played[cue] = now
	cue_counts[cue] = int(cue_counts.get(cue, 0)) + 1
	var player := _players[cue] as AudioStreamPlayer
	if player.stream != null and not SettingsRuntime.is_headless():
		player.play()

func _on_damage_dealt(_target: Node, amount: int, _critical: bool) -> void:
	if amount > 0:
		play_cue("hit")

func _on_player_hp_changed(current: int, _maximum: int) -> void:
	if _last_hp >= 0 and current > 0 and current < _last_hp:
		play_cue("hurt")
	_last_hp = current

func _on_boss_hp_changed(boss_id: int, name: String, hp: int, _maximum: int, phase: int) -> void:
	if hp <= 0:
		_boss_seen.erase(boss_id)
		return
	var prev: Dictionary = _boss_seen.get(boss_id, {})
	if String(prev.get("name", "")) != name or phase > int(prev.get("phase", -1)):
		play_cue("boss")
	_boss_seen[boss_id] = {"name": name, "phase": phase}
