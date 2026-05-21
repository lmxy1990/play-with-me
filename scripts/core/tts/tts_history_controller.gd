extends RefCounted
class_name TtsHistoryController

const TtsTextSanitizerScript := preload("res://scripts/core/tts/tts_text_sanitizer.gd")
const TtsVoiceProfileSchemaScript := preload("res://scripts/core/tts/voice_profile_schema.gd")
const MAX_QUEUE_SIZE := 32

var _queue: Array = []
var _tts_sanitizer = TtsTextSanitizerScript.new()
var _voice_schema = TtsVoiceProfileSchemaScript.new()


func clear() -> void:
	_queue.clear()


func queue_history_item(history_item: Dictionary, voice_configs: Array, runtime, player_count: int, playback_voice_config_id: String = "") -> Dictionary:
	var voice := playback_voice_config(voice_configs, playback_voice_config_id)
	if voice.is_empty() or not bool(voice.get("enabled", true)):
		return {}
	var tts_item := build_item(history_item, voice, player_count)
	if tts_item.is_empty():
		return {}
	_queue.append(tts_item)
	if _queue.size() > MAX_QUEUE_SIZE:
		_queue.pop_front()
	if runtime != null and runtime.has_method("enqueue"):
		runtime.enqueue(tts_item)
	return tts_item.duplicate(true)


func build_item(history_item: Dictionary, voice_config: Dictionary, player_count: int) -> Dictionary:
	if voice_config.is_empty() or not bool(voice_config.get("enabled", true)):
		return {}
	var speaker := String(history_item.get("speaker", ""))
	var display_text := String(history_item.get("text", ""))
	var text := _tts_sanitizer.sanitize(display_text, speaker)
	if text == "":
		return {}
	return {
		"speaker": speaker,
		"speaker_index": int(history_item.get("speaker_index", speaker_index_for_history(speaker, player_count))),
		"text": text,
		"display_text": display_text,
		"presentation_id": String(history_item.get("presentation_id", history_item.get("presentationId", ""))),
		"presentationId": String(history_item.get("presentationId", history_item.get("presentation_id", ""))),
		"voice": String(voice_config.get("voice", "")),
		"engine": normalize_engine(String(voice_config.get("engine", "system"))),
		"speed": String(voice_config.get("speed", "0.85")),
		"pitch": String(voice_config.get("pitch", "1.00")),
		"volume": String(voice_config.get("volume", "1.00")),
		"at": history_item.get("at", Time.get_unix_time_from_system()),
	}


func active_voice_config(voice_configs: Array) -> Dictionary:
	return _voice_schema.active_profile(voice_configs)


func playback_voice_config(voice_configs: Array, playback_voice_config_id: String) -> Dictionary:
	return _voice_schema.playback_profile(voice_configs, playback_voice_config_id)


func speaker_index_for_history(speaker: String, player_count: int) -> int:
	var marker := speaker.find("号")
	if marker <= 0:
		return -1
	var seat_text := speaker.substr(0, marker).strip_edges()
	if not seat_text.is_valid_int():
		return -1
	var index := int(seat_text.to_int()) - 1
	if index < 0 or index >= player_count:
		return -1
	return index


func normalize_engine(engine: String) -> String:
	return _voice_schema.normalize_engine(engine)


func kokoro_voices() -> Array:
	return _tts_sanitizer.kokoro_voices()


func queue_snapshot() -> Array:
	var result := []
	for item in _queue:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result
