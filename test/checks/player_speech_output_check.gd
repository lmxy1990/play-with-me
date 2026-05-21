extends SceneTree


func _initialize() -> void:
	var output = load("res://scripts/player/player_speech_output.gd").new()
	var players := [
		{"id": "self_player", "name": "一号"},
		{"participant_id": "peer_two", "name": "二号"},
		{"id": "bot_seat", "name": "机器人"},
	]
	if not _expect(output.speaker_tts_enabled(0, players), "speakers are enabled by default"):
		return
	output.set_speaker_tts_enabled(0, false, players)
	if not _expect(not output.speaker_tts_enabled(0, players), "speaker mute is tracked by player id"):
		return
	if not _expect(bool(output.muted_speaker_keys_snapshot().get("self_player", false)), "mute snapshot stores player key"):
		return
	output.set_speaker_tts_enabled(0, true, players)
	if not _expect(output.speaker_tts_enabled(0, players), "speaker can be unmuted"):
		return
	output.set_speaker_tts_enabled(2, false, players, Callable(self, "_local_ai_profile_id"))
	if not _expect(not output.speaker_tts_enabled(2, players, Callable(self, "_local_ai_profile_id")), "local AI profile id is used as stable mute key"):
		return
	if not _expect(String(output.speaker_tts_key(2, players, Callable(self, "_local_ai_profile_id"))) == "profile_bot_3", "AI profile key is preferred"):
		return
	output.restore_muted_speaker_keys({"peer_two": true})
	if not _expect(not output.speaker_tts_enabled(1, players), "restored muted keys are applied"):
		return
	output.clear_muted_speaker_keys()
	if not _expect(output.speaker_tts_enabled(1, players), "clear muted keys restores speech"):
		return
	quit(0)


func _local_ai_profile_id(index: int) -> String:
	return "profile_bot_%d" % [index + 1] if index == 2 else ""


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("player_speech_output_check failed: %s" % message)
	quit(1)
	return false
