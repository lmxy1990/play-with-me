extends RefCounted
class_name TtsVoiceCatalog

const TtsVoiceProfileSchemaScript := preload("res://scripts/core/tts/voice_profile_schema.gd")
const TtsTextSanitizerScript := preload("res://scripts/core/tts/tts_text_sanitizer.gd")

var _runtime = null
var _schema = TtsVoiceProfileSchemaScript.new()
var _tts_sanitizer = TtsTextSanitizerScript.new()


func set_runtime(runtime) -> void:
	_runtime = runtime


func normalize_engine(engine: String) -> String:
	return _schema.normalize_engine(engine)


func engine_label(engine: String) -> String:
	return _schema.engine_label(engine)


func engine_options(available_only: bool = false) -> Array:
	var options := _schema.engine_options()
	if not available_only:
		return options
	var available: Array = []
	for item in options:
		if item is Dictionary and engine_available(String((item as Dictionary).get("id", ""))):
			available.append(item)
	if available.is_empty():
		return [options[0]]
	return available


func known_engine_ids() -> Array:
	return _schema.known_engine_ids()


func external_engine_ids() -> Array:
	return _schema.external_engine_ids()


func supported_engine_or_default(engine: String, available_only: bool = false) -> String:
	var normalized := normalize_engine(engine)
	var options := engine_options(available_only)
	for item in options:
		if item is Dictionary and String((item as Dictionary).get("id", "")) == normalized:
			return normalized
	if not options.is_empty() and options[0] is Dictionary:
		return String((options[0] as Dictionary).get("id", "system"))
	return "system"


func engine_available(engine: String) -> bool:
	var normalized := normalize_engine(engine)
	if normalized == "":
		return false
	if _runtime != null and _runtime.has_method("is_engine_available"):
		return bool(_runtime.call("is_engine_available", normalized))
	return normalized == "system"


func warm_up_engine(engine: String, reason: String = "") -> Dictionary:
	if _runtime == null or not _runtime.has_method("warm_up_engine"):
		_catalog_debug("warm_up skipped reason=%s engine=%s runtime=missing" % [reason, engine])
		return {"ok": false, "error": "TTS 未初始化"}
	var normalized := supported_engine_or_default(engine)
	_catalog_debug("warm_up start reason=%s engine=%s" % [reason, normalized])
	var result: Dictionary = _runtime.call("warm_up_engine", normalized)
	_catalog_debug("warm_up result reason=%s engine=%s result=%s" % [reason, normalized, JSON.stringify(result)])
	return result


func voice_options_for(engine: String, gender: String) -> Array:
	var normalized := normalize_engine(engine)
	match normalized:
		"system":
			return system_tts_voices(gender)
		"local_kokoro":
			return kokoro_tts_voices(gender)
		_:
			if external_engine_ids().has(normalized):
				return external_tts_voices(normalized, gender)
			return []


func engine_supports_default(engine: String) -> bool:
	return _schema.engine_supports_default(engine)


func gender_disabled_options(engine: String) -> Array:
	var disabled: Array = []
	for gender in ["女声", "男声"]:
		if voice_options_for(engine, gender).is_empty():
			disabled.append(gender)
	if disabled.size() == 2 and engine_supports_default(normalize_engine(engine)):
		return []
	return disabled


func first_available_gender(engine: String) -> String:
	for gender in ["女声", "男声"]:
		if not voice_options_for(engine, gender).is_empty():
			return gender
	return "女声"


func voice_dropdown_label(engine: String, voice_id: String, default_label: String) -> String:
	if normalize_engine(engine) == "local_kokoro":
		return kokoro_voice_number_label(voice_id)
	return default_label


func kokoro_voice_number_label(voice_id: String) -> String:
	var clean := voice_id.strip_edges()
	var marker := clean.rfind("::")
	if marker >= 0 and marker + 2 < clean.length():
		return clean.substr(marker + 2)
	return clean


func voice_options_have(voices: Array, voice_id: String) -> bool:
	for item in voices:
		if item is Dictionary and String((item as Dictionary).get("id", "")) == voice_id:
			return true
	return false


func system_tts_voices(gender: String) -> Array:
	if _runtime == null or not _runtime.has_method("available_system_voices"):
		_catalog_debug("system voices unavailable runtime=missing gender=%s" % gender)
		return []
	var result: Array = []
	var voices: Array = _runtime.call("available_system_voices", "")
	for item in voices:
		if not (item is Dictionary):
			continue
		var voice: Dictionary = item
		var id := String(voice.get("id", ""))
		if id == "":
			continue
		var language := String(voice.get("language", ""))
		var inferred_gender := infer_system_voice_gender(voice)
		if gender == "男声" and inferred_gender != "男声":
			continue
		if gender == "女声" and inferred_gender == "男声":
			continue
		var name := String(voice.get("name", id))
		var label := "%s · %s" % [name, language if language != "" else "system"]
		result.append({
			"id": id,
			"name": label,
			"engine": "system",
			"gender": gender if gender != "" else inferred_gender,
		})
	_catalog_debug("system voices gender=%s raw=%d filtered=%d" % [gender, voices.size(), result.size()])
	return result


func external_tts_voices(engine: String, gender: String) -> Array:
	var normalized_engine := normalize_engine(engine)
	if not external_engine_ids().has(normalized_engine):
		return []
	if _runtime == null or not _runtime.has_method("available_external_voices"):
		_catalog_debug("external voices unavailable runtime=missing engine=%s gender=%s" % [normalized_engine, gender])
		return []
	var all_matching_voices: Array = []
	var voices: Array = _runtime.call("available_external_voices", normalized_engine, "")
	for item in voices:
		if not (item is Dictionary):
			continue
		var voice: Dictionary = item
		var id := String(voice.get("id", ""))
		if id == "":
			continue
		var language := String(voice.get("language", voice.get("locale", "")))
		var inferred_gender := String(voice.get("gender", "")).strip_edges()
		if inferred_gender == "":
			inferred_gender = infer_system_voice_gender(voice)
		if gender == "男声" and inferred_gender != "男声":
			continue
		if gender == "女声" and inferred_gender == "男声":
			continue
		var name := String(voice.get("name", id))
		var label := "%s · %s" % [name, language if language != "" else engine_label(normalized_engine)]
		var entry := {
			"id": id,
			"name": label,
			"engine": normalized_engine,
			"gender": gender if gender != "" else inferred_gender,
			"language": language,
		}
		all_matching_voices.append(entry)
	_catalog_debug("external voices engine=%s gender=%s raw=%d filtered=%d" % [normalized_engine, gender, voices.size(), all_matching_voices.size()])
	return all_matching_voices


func kokoro_tts_voices(gender: String) -> Array:
	var raw: Array = []
	if _runtime != null and _runtime.has_method("available_kokoro_voices"):
		raw = _runtime.call("available_kokoro_voices", "")
	if raw.is_empty():
		raw = _tts_sanitizer.kokoro_voices()
	var result: Array = []
	var normalized_gender := gender.strip_edges()
	for item in raw:
		if not (item is Dictionary):
			continue
		var voice: Dictionary = item
		var id := String(voice.get("id", ""))
		if id == "":
			continue
		var voice_gender := String(voice.get("gender", ""))
		if normalized_gender != "" and voice_gender != "" and voice_gender != normalized_gender:
			continue
		result.append({
			"id": id,
			"name": String(voice.get("name", id)),
			"engine": "local_kokoro",
			"gender": voice_gender,
			"language": String(voice.get("language", voice.get("locale", "zh-CN"))),
		})
	_catalog_debug("kokoro voices gender=%s raw=%d filtered=%d" % [gender, raw.size(), result.size()])
	return result


func language_matches_chinese(language: String) -> bool:
	var normalized := language.strip_edges().to_lower()
	return normalized == "" or normalized.begins_with("zh") or normalized.begins_with("cmn") or normalized.begins_with("yue")


func infer_system_voice_gender(voice: Dictionary) -> String:
	var text := "%s %s" % [String(voice.get("id", "")), String(voice.get("name", ""))]
	var lower := text.to_lower()
	if lower.contains("female") or lower.contains("女") or lower.contains("_f") or lower.contains("-f") or lower.contains(" x f"):
		return "女声"
	if lower.contains("male") or lower.contains("男") or lower.contains("_m") or lower.contains("-m") or lower.contains(" x m"):
		return "男声"
	return "女声"


func _catalog_debug(message: String) -> void:
	if OS.is_debug_build():
		print("[TtsVoiceCatalog][debug] %s" % message)
