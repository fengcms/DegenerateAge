extends Node

func _ready() -> void:
	var ok := true
	for cue in AudioCues.CUES:
		var player := AudioCues._players.get(cue) as AudioStreamPlayer
		ok = _check(player != null and player.stream != null and player.bus == "SFX", "%s 音效资源" % cue) and ok
	ok = _check(AudioCues._music.stream is AudioStreamWAV
		and (AudioCues._music.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
		and AudioCues._music.bus == "Music", "循环环境音乐") and ok
	GameState.settings["musicVolume"] = 0.0
	GameState.settings["sfxVolume"] = 0.35
	SettingsRuntime.apply_audio()
	ok = _check(is_zero_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")))
		and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("SFX")), 0.35), "音乐与音效分别受控") and ok
	EventBus.item_picked.emit("test_item")
	ok = _check(int(AudioCues.cue_counts.get("pickup", 0)) == 1, "拾取事件触发音效") and ok
	EventBus.player_died.emit()
	ok = _check(int(AudioCues.cue_counts.get("death", 0)) == 1, "死亡事件触发音效") and ok
	AudioCues._music.stop()
	AudioCues._music.stream = null
	for cue in AudioCues.CUES:
		var player := AudioCues._players[cue] as AudioStreamPlayer
		player.stop()
		player.stream = null
	await get_tree().process_frame
	await get_tree().process_frame
	print("AudioCuesTest: ", "PASS" if ok else "FAIL")
	get_tree().quit.call_deferred(0 if ok else 1)

func _check(condition: bool, label: String) -> bool:
	if not condition:
		push_error("AudioCuesTest: " + label)
	return condition
