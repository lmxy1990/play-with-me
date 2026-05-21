extends RefCounted
class_name TtsVoicePreviewController

const TtsVoiceProfileSchemaScript := preload("res://scripts/core/tts/voice_profile_schema.gd")

const PREVIEW_TEXT := "试听开始。你好，今天是 2026 年，座位 3 号。数值 3.14，21 个苹果。字母 A B C，单词 wolf village game。"

var _schema = TtsVoiceProfileSchemaScript.new()


func preview_text() -> String:
	return PREVIEW_TEXT


func build_preview_item(engine: String, voice_id: String, speed: String, pitch: String, volume: String) -> Dictionary:
	return {
		"speaker": "试听",
		"speaker_index": -1,
		"text": PREVIEW_TEXT,
		"voice": voice_id.strip_edges(),
		"engine": _schema.normalize_engine(engine),
		"speed": speed,
		"pitch": pitch,
		"volume": volume,
		"interrupt": true,
		"at": Time.get_unix_time_from_system(),
	}


func start_preview(runtime, engine: String, voice_id: String, speed: String, pitch: String, volume: String) -> Dictionary:
	var prepared := prepare_preview(runtime, engine, voice_id, speed, pitch, volume)
	if not bool(prepared.get("ok", false)):
		return prepared
	return enqueue_preview(runtime, prepared.get("item", {}) as Dictionary)


func prepare_preview(runtime, engine: String, voice_id: String, speed: String, pitch: String, volume: String) -> Dictionary:
	if runtime == null:
		return _error("TTS 未初始化", {})
	var item := build_preview_item(engine, voice_id, speed, pitch, volume)
	if runtime.has_method("validate_item"):
		var validation: Dictionary = runtime.call("validate_item", item)
		if not bool(validation.get("ok", false)):
			validation["item"] = item
			return validation
	return {
		"ok": true,
		"item": item,
		"error": "",
	}


func enqueue_preview(runtime, item: Dictionary) -> Dictionary:
	if runtime == null:
		return _error("TTS 未初始化", item)
	if not runtime.has_method("enqueue"):
		return _error("TTS 运行时缺少播放入口", item)
	runtime.call("enqueue", item)
	return {
		"ok": true,
		"item": item.duplicate(true),
		"error": "",
	}


func _error(message: String, item: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"item": item.duplicate(true),
	}
