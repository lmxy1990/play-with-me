extends "res://scripts/pages/base/page_room_host_peer_ui_base.gd"

enum SeatMotion { IDLE, THINKING, SPEAKING, DEAD }

const PlayerSpeechOutputScript := preload("res://scripts/player/player_speech_output.gd")

var _player_speech_output = PlayerSpeechOutputScript.new()
var _tts_speaking_index := -1


func _add_history(speaker: String, text: String) -> void:
	if text.strip_edges() == "":
		return
	_append_history_item({
		"speaker": speaker,
		"text": text,
		"at": Time.get_unix_time_from_system(),
	})


func _append_history_item(item: Dictionary) -> void:
	if has_method("_ensure_history_presentation_id"):
		call("_ensure_history_presentation_id", item)
	if has_method("_register_presentation_ack_gate_for_history_item"):
		call("_register_presentation_ack_gate_for_history_item", item)
	var history := _state_array("_history")
	history.append(item)
	set("_history", history)
	_present_history_item(item)


func _present_history_item(item: Dictionary) -> void:
	if has_method("_history_item_visible_to_current") and not bool(call("_history_item_visible_to_current", item)):
		return
	if has_method("_defer_history_item_for_center_speech") and bool(call("_defer_history_item_for_center_speech", item)):
		return
	if has_method("_show_history_toast_item"):
		call("_show_history_toast_item", item)
	if has_method("_begin_local_presentation_ack"):
		call("_begin_local_presentation_ack", item)
	var tts_item := _queue_tts_for_history(item)
	var wait_for_tts := not tts_item.is_empty()
	if tts_item.is_empty() and has_method("_schedule_local_presentation_ack_after_text_delay"):
		call("_schedule_local_presentation_ack_after_text_delay", item)
	elif not tts_item.is_empty() and has_method("_history_presentation_id") and has_method("_schedule_local_presentation_ack_after_text_delay"):
		var presentation_id := String(call("_history_presentation_id", item))
		if not _tts_runtime_has_presentation_id(presentation_id):
			wait_for_tts = false
			if has_method("_local_presentation_ack_pending") and bool(call("_local_presentation_ack_pending", presentation_id)):
				call("_schedule_local_presentation_ack_after_text_delay", item)
	if has_method("_show_center_speech_item_from_history"):
		call("_show_center_speech_item_from_history", item, wait_for_tts)


func _present_history_delta(previous_history: Array, next_history: Array) -> void:
	var seen := {}
	for item in previous_history:
		if item is Dictionary:
			seen[_history_item_signature(item as Dictionary)] = true
	for item in next_history:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var signature := _history_item_signature(entry)
		if seen.has(signature):
			continue
		seen[signature] = true
		_present_history_item(entry)


func _history_item_signature(item: Dictionary) -> String:
	return _player_speech_output.history_item_signature(item)


func _queue_tts_for_history(item: Dictionary) -> Dictionary:
	if has_method("_history_item_tts_enabled") and not bool(call("_history_item_tts_enabled", item)):
		return {}
	if _tts_runtime == null and has_method("_setup_tts_runtime"):
		call("_setup_tts_runtime")
	return _player_speech_output.queue_history_item(item, _tts_voice_repository.list_profiles(), _tts_runtime, _state_array("_players").size(), _playback_voice_config_id())


func _tts_runtime_has_presentation_id(presentation_id: String) -> bool:
	return _player_speech_output.runtime_has_presentation_id(_tts_runtime, presentation_id)


func _playback_voice_config_id() -> String:
	var repository = _ensure_preference_repository()
	if repository == null:
		return "voice_system_default"
	var result: Dictionary = repository.get_preferences()
	if not bool(result.get("ok", false)):
		return "voice_system_default"
	var state: Dictionary = result.get("state", {})
	var config_id := str(state.get("playback_voice_config_id", "")).strip_edges()
	return config_id if config_id != "" else "voice_system_default"


func _speaker_index_for_history(speaker: String) -> int:
	return _player_speech_output.speaker_index_for_history(speaker, _state_array("_players").size())


func _on_tts_speech_started(item: Dictionary) -> void:
	var index := int(item.get("speaker_index", -1))
	_tts_speaking_index = index
	if has_method("_show_center_speech_item"):
		call("_show_center_speech_item", item, false, false, true)
	var players := _state_array("_players")
	if index < 0 or index >= players.size() or not bool(players[index].get("alive", true)):
		return
	players[index]["motion"] = SeatMotion.SPEAKING
	players[index]["speech_progress"] = 0.0
	set("_players", players)
	_call_if_present("_refresh_seat", [index])


func _on_tts_speech_progress(item: Dictionary, ratio: float) -> void:
	if String(item.get("speaker", "")) == "试听":
		if String(item.get("progress_source", "")) == "native":
			if ratio > 0.0 and ratio < 1.0:
				_voice_preview_progress_supported = true
			if not _voice_preview_progress_supported:
				return
			_voice_preview_progress_supported = true
			_update_voice_preview_text(String(item.get("text", _voice_preview_sample_text())), ratio, true)
			_book_status(_voice_preview_status_label, "正在试听 %d%%" % int(round(clampf(ratio, 0.0, 1.0) * 100.0)), BOOK_GREEN)
		return
	var index := int(item.get("speaker_index", -1))
	if has_method("_update_center_speech_progress"):
		call("_update_center_speech_progress", item, ratio)
	var players := _state_array("_players")
	if index < 0 or index >= players.size() or not bool(players[index].get("alive", true)):
		return
	players[index]["speech_progress"] = clampf(ratio, 0.0, 1.0)
	set("_players", players)
	_call_if_present("_refresh_seat", [index])


func _on_tts_speech_finished(item: Dictionary) -> void:
	if String(item.get("speaker", "")) == "试听":
		if _voice_preview_progress_supported:
			_update_voice_preview_text(String(item.get("text", _voice_preview_sample_text())), 1.0, true)
		_book_status(_voice_preview_status_label, "试听完成", BOOK_GREEN)
		_stop_voice_preview_animation()
	elif has_method("_finish_center_speech_item"):
		call("_finish_center_speech_item", item)
		if has_method("_complete_local_presentation_ack"):
			var ack_item := item.duplicate(true)
			get_tree().create_timer(2.0).timeout.connect(func():
				if has_method("_complete_local_presentation_ack"):
					call("_complete_local_presentation_ack", ack_item, "tts_finished")
			)
	_restore_tts_speaker_motion(int(item.get("speaker_index", -1)))


func _on_tts_speech_failed(item: Dictionary, error: String) -> void:
	if String(item.get("speaker", "")) == "试听":
		_book_status(_voice_preview_status_label, error if error != "" else "试听失败", BOOK_RED)
		_stop_voice_preview_animation()
	elif has_method("_fail_center_speech_item"):
		call("_fail_center_speech_item", item, error)
		var reason := error.strip_edges()
		if reason != "" and reason != "stopped" and has_method("_show_system_progress_toast"):
			call("_show_system_progress_toast", "语音播放失败：%s" % reason, 5.0)
		if has_method("_complete_local_presentation_ack"):
			call("_complete_local_presentation_ack", item, "tts_failed")
	_restore_tts_speaker_motion(int(item.get("speaker_index", -1)))


func _restore_tts_speaker_motion(index: int) -> void:
	if _tts_speaking_index == index:
		_tts_speaking_index = -1
	var players := _state_array("_players")
	if index < 0 or index >= players.size() or not bool(players[index].get("alive", true)):
		return
	if int(get("_speech_prompt_index")) == index:
		return
	if int(get("_pending_actor_index")) == index:
		return
	players[index]["motion"] = SeatMotion.IDLE
	players[index]["speech_progress"] = 0.0
	set("_players", players)
	_call_if_present("_refresh_seat", [index])
