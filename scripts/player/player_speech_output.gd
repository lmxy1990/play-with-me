extends RefCounted

const TtsHistoryControllerScript := preload("res://scripts/core/tts/tts_history_controller.gd")

var _tts_history_controller = TtsHistoryControllerScript.new()
var _muted_speaker_keys := {}


func queue_history_item(item: Dictionary, voice_profiles: Array, tts_runtime, player_count: int, voice_config_id: String) -> Dictionary:
	return _tts_history_controller.queue_history_item(item, voice_profiles, tts_runtime, player_count, voice_config_id)


func build_item(history_item: Dictionary, voice_config: Dictionary, player_count: int) -> Dictionary:
	return _tts_history_controller.build_item(history_item, voice_config, player_count)


func queue_snapshot() -> Array:
	return _tts_history_controller.queue_snapshot()


func clear() -> void:
	_tts_history_controller.clear()


func clear_muted_speaker_keys() -> void:
	_muted_speaker_keys.clear()


func muted_speaker_keys_snapshot() -> Dictionary:
	return _muted_speaker_keys.duplicate(true)


func restore_muted_speaker_keys(keys: Dictionary) -> void:
	_muted_speaker_keys = keys.duplicate(true)


func speaker_tts_enabled(index: int, players: Array, local_ai_profile_id_resolver: Callable = Callable()) -> bool:
	if index < 0 or index >= players.size():
		return true
	return not bool(_muted_speaker_keys.get(speaker_tts_key(index, players, local_ai_profile_id_resolver), false))


func set_speaker_tts_enabled(index: int, enabled: bool, players: Array, local_ai_profile_id_resolver: Callable = Callable()) -> void:
	if index < 0 or index >= players.size():
		return
	var key := speaker_tts_key(index, players, local_ai_profile_id_resolver)
	if enabled:
		_muted_speaker_keys.erase(key)
	else:
		_muted_speaker_keys[key] = true


func speaker_tts_key(index: int, players: Array, local_ai_profile_id_resolver: Callable = Callable()) -> String:
	if index >= 0 and index < players.size() and players[index] is Dictionary:
		var player: Dictionary = players[index]
		var local_ai_profile_id := ""
		if local_ai_profile_id_resolver.is_valid():
			local_ai_profile_id = String(local_ai_profile_id_resolver.call(index)).strip_edges()
		if local_ai_profile_id != "":
			return local_ai_profile_id
		for field in ["id", "participant_id"]:
			var value := String(player.get(field, "")).strip_edges()
			if value != "":
				return value
	return "seat_%d" % [index + 1]


func speaker_index_for_history(speaker: String, player_count: int) -> int:
	return _tts_history_controller.speaker_index_for_history(speaker, player_count)


func history_item_signature(item: Dictionary) -> String:
	var presentation_id := String(item.get("presentation_id", item.get("presentationId", ""))).strip_edges()
	if presentation_id != "":
		return "presentation:%s" % presentation_id
	return "%s|%s|%s|%s" % [
		String(item.get("speaker", "")),
		String(item.get("text", "")),
		str(item.get("at", "")),
		str(item.get("speaker_index", item.get("actor_index", ""))),
	]


func runtime_has_presentation_id(tts_runtime, presentation_id: String) -> bool:
	var clean := presentation_id.strip_edges()
	if clean == "" or tts_runtime == null or not is_instance_valid(tts_runtime):
		return false
	if tts_runtime.has_method("current_item"):
		var current_value = tts_runtime.call("current_item")
		if current_value is Dictionary:
			var current: Dictionary = current_value
			if String(current.get("presentation_id", current.get("presentationId", ""))).strip_edges() == clean:
				return true
	if tts_runtime.has_method("debug_snapshot"):
		var snapshot_value = tts_runtime.call("debug_snapshot")
		if snapshot_value is Dictionary:
			var snapshot: Dictionary = snapshot_value
			var queue_value = snapshot.get("queue", [])
			if queue_value is Array:
				for item_value in queue_value as Array:
					if item_value is Dictionary:
						var item: Dictionary = item_value
						if String(item.get("presentation_id", item.get("presentationId", ""))).strip_edges() == clean:
							return true
	return false
