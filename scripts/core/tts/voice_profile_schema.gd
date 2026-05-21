extends RefCounted
class_name TtsVoiceProfileSchema

const ENGINE_SYSTEM := "system"
const ENGINE_LOCAL_KOKORO := "local_kokoro"
const ENGINE_NEKO_TTS := "neko_tts"
const ENGINE_VOXSHERPA_TTS := "voxsherpa_tts"
const ENGINE_MULTI_TTS := "multi_tts"
const EXTERNAL_ANDROID_ENGINES := [ENGINE_NEKO_TTS, ENGINE_VOXSHERPA_TTS, ENGINE_MULTI_TTS]
const DEFAULT_PROFILE_KEY := "voice_system_default"
const DEFAULT_PROFILE_NAME := "系统默认"
const DEFAULT_KOKORO_VOICE := "zf_001"

const DEFAULT_PROFILE := {
	"id": 0,
	"key": DEFAULT_PROFILE_KEY,
	"name": DEFAULT_PROFILE_NAME,
	"engine": ENGINE_LOCAL_KOKORO,
	"gender": "女声",
	"voice": DEFAULT_KOKORO_VOICE,
	"speed": "0.90",
	"pitch": "1.00",
	"volume": "1.00",
	"enabled": true,
	"active": true,
}


func default_profile() -> Dictionary:
	return DEFAULT_PROFILE.duplicate(true)


func engine_options() -> Array:
	return [
		{"id": ENGINE_SYSTEM, "label": "系统TTS"},
		{"id": ENGINE_LOCAL_KOKORO, "label": "Kokoro"},
		{"id": ENGINE_NEKO_TTS, "label": "NekoTTS"},
		{"id": ENGINE_VOXSHERPA_TTS, "label": "VoxSherpa-TTS"},
		{"id": ENGINE_MULTI_TTS, "label": "MultiTTS"},
	]


func known_engine_ids() -> Array:
	var ids: Array = []
	for item in engine_options():
		if item is Dictionary:
			ids.append(String((item as Dictionary).get("id", "")))
	return ids


func external_engine_ids() -> Array:
	return EXTERNAL_ANDROID_ENGINES.duplicate()


func normalize_engine(engine: String) -> String:
	var value := engine.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	match value:
		"system", "系统", "系统tts", "android", "android_tts":
			return ENGINE_SYSTEM
		"kokoro", "local_kokoro", "本地kokoro":
			return ENGINE_LOCAL_KOKORO
		"neko", "neko_tts", "nekotts", "nekospeak", "neko_speak":
			return ENGINE_NEKO_TTS
		"voxsherpa", "voxsherpa_tts", "vox_sherpa", "vox_sherpa_tts":
			return ENGINE_VOXSHERPA_TTS
		"multi", "multi_tts", "multitts", "tts_server", "tts_server_android":
			return ENGINE_MULTI_TTS
		_:
			return value


func engine_label(engine: String) -> String:
	match normalize_engine(engine):
		ENGINE_SYSTEM:
			return "系统TTS"
		ENGINE_LOCAL_KOKORO:
			return "Kokoro"
		ENGINE_NEKO_TTS:
			return "NekoTTS"
		ENGINE_VOXSHERPA_TTS:
			return "VoxSherpa-TTS"
		ENGINE_MULTI_TTS:
			return "MultiTTS"
		_:
			return engine.strip_edges()


func engine_supports_default(engine: String) -> bool:
	var normalized := normalize_engine(engine)
	return normalized == ENGINE_SYSTEM or EXTERNAL_ANDROID_ENGINES.has(normalized)


func normalize_profiles(configs: Array) -> Array:
	var result: Array = []
	for item in configs:
		if not (item is Dictionary):
			continue
		var profile := normalize_profile(item as Dictionary)
		if not profile.is_empty():
			result.append(profile)
	if result.is_empty():
		result.append(default_profile())
	return enforce_active_unique(result)


func normalize_profile(config: Dictionary) -> Dictionary:
	var name := String(config.get("name", "")).strip_edges()
	var engine := normalize_engine(String(config.get("engine", ENGINE_SYSTEM)))
	if name == "" or engine == "":
		return {}
	var voice := String(config.get("voice", "")).strip_edges()
	if _is_default_profile_signature(config, name, engine, voice):
		return _migrated_default_profile(config)
	return {
		"id": _numeric_id(config.get("id", 0)),
		"key": _profile_key(config, name, engine, voice),
		"name": name,
		"engine": engine,
		"gender": String(config.get("gender", "女声")).strip_edges(),
		"voice": voice,
		"speed": String(config.get("speed", "0.90")).strip_edges(),
		"pitch": String(config.get("pitch", "1.00")).strip_edges(),
		"volume": String(config.get("volume", "1.00")).strip_edges(),
		"enabled": bool(config.get("enabled", true)),
		"active": bool(config.get("active", false)),
	}


func build_profile(id: int, name: String, engine: String, gender: String, voice: String, speed: String, pitch: String = "1.00", volume: String = "1.00", enabled: bool = true, active: bool = false) -> Dictionary:
	var clean_name := name.strip_edges()
	if clean_name == "":
		clean_name = "未命名声音"
	if active:
		enabled = true
	return normalize_profile({
		"id": id,
		"name": clean_name,
		"engine": engine,
		"gender": gender,
		"voice": voice,
		"speed": speed,
		"pitch": pitch,
		"volume": volume,
		"enabled": enabled,
		"active": active,
	})


func enforce_active_unique(configs: Array) -> Array:
	var result: Array = []
	for item in configs:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))

	var active_index := -1
	for i in range(result.size()):
		var config: Dictionary = result[i]
		var enabled := bool(config.get("enabled", true))
		var active := bool(config.get("active", false))
		if active and enabled and active_index < 0:
			active_index = i
			config["active"] = true
		else:
			config["active"] = false
	if active_index >= 0:
		return result

	for i in range(result.size()):
		if bool((result[i] as Dictionary).get("enabled", true)):
			(result[i] as Dictionary)["active"] = true
			break
	return result


func active_profile(configs: Array) -> Dictionary:
	var normalized := normalize_profiles(configs)
	for item in normalized:
		if item is Dictionary and bool((item as Dictionary).get("active", false)) and bool((item as Dictionary).get("enabled", true)):
			return (item as Dictionary).duplicate(true)
	for item in normalized:
		if item is Dictionary and bool((item as Dictionary).get("enabled", true)):
			return (item as Dictionary).duplicate(true)
	return {}


func profile_by_key(configs: Array, profile_key: String) -> Dictionary:
	var key := profile_key.strip_edges()
	if key == "":
		return active_profile(configs)
	var normalized := normalize_profiles(configs)
	for item in normalized:
		if item is Dictionary and String((item as Dictionary).get("key", "")) == key and bool((item as Dictionary).get("enabled", true)):
			return (item as Dictionary).duplicate(true)
	return {}


func playback_profile(configs: Array, profile_key: String) -> Dictionary:
	var selected := profile_by_key(configs, profile_key)
	if not selected.is_empty():
		return selected
	return active_profile(configs)


func existing_id(configs: Array, index: int) -> int:
	if index >= 0 and index < configs.size() and configs[index] is Dictionary:
		return _numeric_id((configs[index] as Dictionary).get("id", 0))
	return 0


func next_local_id(configs: Array) -> int:
	var max_id := 0
	for item in configs:
		if item is Dictionary:
			max_id = maxi(max_id, _numeric_id((item as Dictionary).get("id", 0)))
	return max_id + 1


func _profile_key(config: Dictionary, name: String, engine: String, voice: String) -> String:
	var explicit_key := str(config.get("key", config.get("profile_key", ""))).strip_edges()
	if explicit_key != "":
		return explicit_key
	var raw_id := str(config.get("id", "")).strip_edges()
	if raw_id == DEFAULT_PROFILE_KEY:
		return DEFAULT_PROFILE_KEY
	if name == DEFAULT_PROFILE_NAME and _is_default_engine_voice(engine, voice):
		return DEFAULT_PROFILE_KEY
	var id := _numeric_id(config.get("id", 0))
	if id > 0:
		return "voice_config_%d" % id
	return "voice_config_0"


func _is_default_profile_signature(config: Dictionary, name: String, engine: String, voice: String) -> bool:
	var explicit_key := str(config.get("key", config.get("profile_key", ""))).strip_edges()
	var raw_id := str(config.get("id", "")).strip_edges()
	return (explicit_key == DEFAULT_PROFILE_KEY or raw_id == DEFAULT_PROFILE_KEY or name == DEFAULT_PROFILE_NAME) and _is_default_engine_voice(engine, voice)


func _is_default_engine_voice(engine: String, voice: String) -> bool:
	return (engine == ENGINE_SYSTEM and voice == "") or (engine == ENGINE_LOCAL_KOKORO and (voice == "" or voice == DEFAULT_KOKORO_VOICE))


func _migrated_default_profile(config: Dictionary) -> Dictionary:
	var profile := DEFAULT_PROFILE.duplicate(true)
	profile["id"] = _numeric_id(config.get("id", 0))
	profile["key"] = DEFAULT_PROFILE_KEY
	profile["gender"] = String(config.get("gender", profile["gender"])).strip_edges()
	profile["speed"] = String(config.get("speed", profile["speed"])).strip_edges()
	profile["pitch"] = String(config.get("pitch", profile["pitch"])).strip_edges()
	profile["volume"] = String(config.get("volume", profile["volume"])).strip_edges()
	profile["enabled"] = bool(config.get("enabled", profile["enabled"]))
	profile["active"] = bool(config.get("active", profile["active"]))
	return profile


func _numeric_id(value) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	var text := str(value).strip_edges()
	if text.is_valid_int():
		return int(text)
	return 0
