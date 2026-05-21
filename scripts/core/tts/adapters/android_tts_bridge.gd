extends RefCounted
class_name AndroidTtsBridge

signal speech_started(utterance_id: int)
signal speech_progress(utterance_id: int, ratio: float)
signal speech_finished(utterance_id: int)
signal speech_failed(utterance_id: int, error: String)
signal voices_updated(voices: Array)
signal engine_ready(engine: String)

const DEFAULT_SINGLETON := "PlayWithMeAndroid"
const WARM_UP_METHODS := ["tts_warm_up", "warmUpTts"]
const LIST_METHODS := ["tts_list_voices", "listSystemTtsVoices"]
const SPEAK_METHODS := ["tts_speak", "speakTts"]
const STOP_METHODS := ["tts_stop", "stopTts"]
const KOKORO_AVAILABLE_METHODS := ["tts_kokoro_available"]
const KOKORO_WARM_UP_METHODS := ["tts_kokoro_warm_up", "kokoro_tts_warm_up", "warmUpKokoroTts"]
const KOKORO_LIST_METHODS := ["tts_list_kokoro_voices", "listKokoroTtsVoices"]
const KOKORO_SPEAK_METHODS := ["tts_speak_kokoro", "speakKokoroTts"]
const EXTERNAL_AVAILABLE_METHODS := ["tts_external_available"]
const EXTERNAL_WARM_UP_METHODS := ["tts_external_warm_up"]
const EXTERNAL_LIST_METHODS := ["tts_list_external_voices"]
const EXTERNAL_SPEAK_METHODS := ["tts_speak_external"]
const DEBUG_AVAILABLE_METHODS := ["tts_debug_available"]
const DEBUG_SNAPSHOT_METHODS := ["tts_debug_snapshot"]

var singleton_name := DEFAULT_SINGLETON
var _bound_plugin = null


func is_available() -> bool:
	var plugin = _plugin()
	var available := plugin != null and _method(plugin, SPEAK_METHODS) != ""
	_bridge_debug("is_available=%s plugin=%s" % [str(available), "present" if plugin != null else "missing"])
	return available


func is_kokoro_available() -> bool:
	var plugin = _plugin()
	if plugin == null:
		_bridge_debug("is_kokoro_available=false plugin=missing")
		return false
	var available_method := _method(plugin, KOKORO_AVAILABLE_METHODS)
	if available_method != "":
		var result = plugin.call(available_method)
		var available := _plugin_bool(result, false)
		_bridge_debug("is_kokoro_available=%s method=%s raw_type=%s" % [str(available), available_method, type_string(typeof(result))])
		return available
	var speak_method_available := _method(plugin, KOKORO_SPEAK_METHODS) != ""
	_bridge_debug("is_kokoro_available=%s source=speak_method" % str(speak_method_available))
	return speak_method_available


func is_external_engine_available(engine: String) -> bool:
	var normalized_engine := _normalize_engine_id(engine)
	var plugin = _plugin()
	if plugin == null:
		_bridge_debug("is_external_engine_available=false plugin=missing engine=%s" % normalized_engine)
		return false
	var method := _method(plugin, EXTERNAL_AVAILABLE_METHODS)
	if method == "":
		_bridge_debug("is_external_engine_available=false method=missing engine=%s" % normalized_engine)
		return false
	var result = plugin.call(method, normalized_engine)
	var available := _plugin_bool(result, false)
	_bridge_debug("is_external_engine_available=%s engine=%s raw_type=%s" % [str(available), normalized_engine, type_string(typeof(result))])
	return available


func warm_up() -> Dictionary:
	var plugin = _plugin()
	if plugin == null:
		return _error("Android TTS 插件未接入：缺少 singleton %s" % singleton_name)
	var method := _method(plugin, WARM_UP_METHODS)
	if method == "":
		return _error("Android TTS 插件缺少 warm_up 方法")
	_bridge_debug("warm_up method=%s" % method)
	var result = plugin.call(method)
	if _plugin_returned_false(result):
		return _error("Android TTS 初始化失败")
	return {"ok": true}


func warm_up_kokoro() -> Dictionary:
	var plugin = _plugin()
	if plugin == null:
		return _error("Android TTS 插件未接入：缺少 singleton %s" % singleton_name)
	var method := _method(plugin, KOKORO_WARM_UP_METHODS)
	if method == "":
		return _error("Android TTS 插件缺少 Kokoro warm_up 方法")
	_bridge_debug("warm_up_kokoro method=%s" % method)
	var result = plugin.call(method)
	if _plugin_returned_false(result):
		return _error("Android Kokoro TTS 初始化失败")
	return {"ok": true}


func warm_up_external_engine(engine: String) -> Dictionary:
	var normalized_engine := _normalize_engine_id(engine)
	var plugin = _plugin()
	if plugin == null:
		return _error("Android TTS 插件未接入：缺少 singleton %s" % singleton_name)
	var method := _method(plugin, EXTERNAL_WARM_UP_METHODS)
	if method == "":
		return _error("Android TTS 插件缺少本地引擎 warm_up 方法")
	_bridge_debug("warm_up_external_engine method=%s engine=%s" % [method, normalized_engine])
	var result = plugin.call(method, normalized_engine)
	if _plugin_returned_false(result):
		return _error("本地 TTS 引擎初始化失败：%s" % normalized_engine)
	return {"ok": true}


func debug_available() -> bool:
	var plugin = _plugin()
	if plugin == null:
		return false
	var method := _method(plugin, DEBUG_AVAILABLE_METHODS)
	if method == "":
		return false
	var result = plugin.call(method)
	return _plugin_bool(result, false)


func debug_snapshot() -> Dictionary:
	var plugin = _plugin()
	if plugin == null:
		return _error("Android TTS 插件未接入：缺少 singleton %s" % singleton_name)
	var method := _method(plugin, DEBUG_SNAPSHOT_METHODS)
	if method == "":
		return _error("Android TTS 插件缺少 debug snapshot 方法")
	var payload = plugin.call(method)
	if payload is Dictionary:
		return (payload as Dictionary).duplicate(true)
	if not (payload is String):
		return _error("Android TTS debug snapshot 返回格式错误")
	var raw := String(payload).strip_edges()
	if raw == "":
		return _error("Android TTS debug snapshot 为空")
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		return _error("Android TTS debug snapshot JSON 解析失败")
	return (json.data as Dictionary).duplicate(true)


func available_voices(language: String = "") -> Array:
	var plugin = _plugin()
	if plugin == null:
		return []
	_bind_plugin_signals(plugin)
	var warm_method := _method(plugin, WARM_UP_METHODS)
	if warm_method != "":
		plugin.call(warm_method)
	var list_method := _method(plugin, LIST_METHODS)
	if list_method == "":
		_bridge_debug("available_voices list_method=missing language=%s" % language)
		return []
	var parsed := _parse_voice_payload(plugin.call(list_method))
	_bridge_debug("available_voices language=%s count=%d" % [language, parsed.size()])
	if language.strip_edges() == "":
		return parsed
	var filtered: Array = []
	for item in parsed:
		if not (item is Dictionary):
			continue
		var voice: Dictionary = item
		var voice_language := String(voice.get("language", voice.get("locale", "")))
		if voice_language == "" or voice_language.begins_with(language):
			filtered.append(voice.duplicate(true))
	return filtered


func available_kokoro_voices(language: String = "") -> Array:
	var plugin = _plugin()
	if plugin == null:
		return []
	_bind_plugin_signals(plugin)
	var list_method := _method(plugin, KOKORO_LIST_METHODS)
	if list_method == "":
		_bridge_debug("available_kokoro_voices list_method=missing language=%s" % language)
		return []
	var parsed := _parse_voice_payload(plugin.call(list_method))
	_bridge_debug("available_kokoro_voices language=%s count=%d" % [language, parsed.size()])
	if language.strip_edges() == "":
		return parsed
	var filtered: Array = []
	for item in parsed:
		if not (item is Dictionary):
			continue
		var voice: Dictionary = item
		var voice_language := String(voice.get("language", voice.get("locale", "")))
		if voice_language == "" or voice_language.begins_with(language):
			filtered.append(voice.duplicate(true))
	return filtered


func available_external_voices(engine: String, language: String = "") -> Array:
	var normalized_engine := _normalize_engine_id(engine)
	var plugin = _plugin()
	if plugin == null:
		return []
	_bind_plugin_signals(plugin)
	var list_method := _method(plugin, EXTERNAL_LIST_METHODS)
	if list_method == "":
		_bridge_debug("available_external_voices list_method=missing engine=%s language=%s" % [normalized_engine, language])
		return []
	var parsed := _parse_voice_payload(plugin.call(list_method, normalized_engine))
	_bridge_debug("available_external_voices engine=%s language=%s count=%d" % [normalized_engine, language, parsed.size()])
	if language.strip_edges() == "":
		return parsed
	var filtered: Array = []
	for item in parsed:
		if not (item is Dictionary):
			continue
		var voice: Dictionary = item
		var voice_language := String(voice.get("language", voice.get("locale", "")))
		if voice_language == "" or voice_language.begins_with(language):
			filtered.append(voice.duplicate(true))
	return filtered


func speak(item: Dictionary, utterance_id: int) -> Dictionary:
	var plugin = _plugin()
	if plugin == null:
		return _error("Android TTS 插件未接入：缺少 singleton %s" % singleton_name)
	var engine := String(item.get("engine", "system")).strip_edges()
	var normalized_engine := _normalize_engine_id(engine)
	var external := _is_external_engine(engine)
	var methods := EXTERNAL_SPEAK_METHODS if external else (KOKORO_SPEAK_METHODS if engine == "local_kokoro" else SPEAK_METHODS)
	var method := _method(plugin, methods)
	if method == "":
		return _error("Android TTS 插件缺少 %s speak 方法" % ("本地引擎" if external else ("Kokoro" if engine == "local_kokoro" else "system")))
	_bind_plugin_signals(plugin)
	var text := String(item.get("text", "")).strip_edges()
	var voice := String(item.get("voice", "")).strip_edges()
	var speed := _float_from_item(item, "speed", 1.0)
	var pitch := _float_from_item(item, "pitch", 1.0)
	var volume := _float_from_item(item, "volume", 1.0)
	var interrupt := bool(item.get("interrupt", false))
	_bridge_debug("speak method=%s engine=%s voice=%s text_chars=%d speed=%.2f pitch=%.2f volume=%.2f interrupt=%s utterance=%d" % [method, normalized_engine if external else engine, _voice_debug(voice), text.length(), speed, pitch, volume, str(interrupt), utterance_id])
	var result = plugin.call(method, normalized_engine, text, voice, speed, pitch, volume, utterance_id, interrupt) if external else plugin.call(method, text, voice, speed, pitch, volume, utterance_id, interrupt)
	if _plugin_returned_false(result):
		return _error("Android TTS 播放启动失败")
	if result is Dictionary:
		var data: Dictionary = result
		if not bool(data.get("ok", true)):
			return _error(String(data.get("error", "Android TTS 播放启动失败")))
	return {"ok": true}


func stop() -> void:
	var plugin = _plugin()
	if plugin == null:
		return
	var method := _method(plugin, STOP_METHODS)
	if method != "":
		plugin.call(method)


func _is_external_engine(engine: String) -> bool:
	return ["neko_tts", "voxsherpa_tts", "multi_tts"].has(_normalize_engine_id(engine))


func _normalize_engine_id(engine: String) -> String:
	var value := engine.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	match value:
		"neko", "neko_tts", "nekotts", "nekospeak", "neko_speak":
			return "neko_tts"
		"voxsherpa", "voxsherpa_tts", "vox_sherpa", "vox_sherpa_tts":
			return "voxsherpa_tts"
		"multi", "multi_tts", "multitts", "tts_server", "tts_server_android":
			return "multi_tts"
		_:
			return value


func _plugin():
	if Engine.has_singleton(singleton_name):
		return Engine.get_singleton(singleton_name)
	return null


func _method(plugin, methods: Array) -> String:
	for method in methods:
		if plugin.has_method(method):
			return method
	if plugin != null and not methods.is_empty():
		return String(methods[0])
	return ""


func _bind_plugin_signals(plugin) -> void:
	if _bound_plugin == plugin:
		return
	_bound_plugin = plugin
	_connect_if_present(plugin, "tts_speech_started", Callable(self, "_on_plugin_speech_started"))
	_connect_if_present(plugin, "tts_speech_progress", Callable(self, "_on_plugin_speech_progress"))
	_connect_if_present(plugin, "tts_speech_done", Callable(self, "_on_plugin_speech_done"))
	_connect_if_present(plugin, "tts_speech_failed", Callable(self, "_on_plugin_speech_failed"))
	_connect_if_present(plugin, "tts_voices_updated", Callable(self, "_on_plugin_voices_updated"))
	_connect_if_present(plugin, "tts_ready", Callable(self, "_on_plugin_system_ready"))
	_connect_if_present(plugin, "kokoro_tts_ready", Callable(self, "_on_plugin_kokoro_ready"))
	_connect_if_present(plugin, "external_tts_ready", Callable(self, "_on_plugin_external_ready"))


func _connect_if_present(plugin, signal_name: String, callback: Callable) -> void:
	if plugin.has_signal(signal_name) and not plugin.is_connected(signal_name, callback):
		plugin.connect(signal_name, callback)


func _parse_voice_payload(payload) -> Array:
	if payload is Array:
		return _normalize_voices(payload)
	if payload is Dictionary:
		var data: Dictionary = payload
		return _normalize_voices(data.get("voices", []))
	if payload is String:
		var raw := String(payload).strip_edges()
		if raw == "":
			return []
		var json := JSON.new()
		if json.parse(raw) != OK:
			return []
		if json.data is Array:
			return _normalize_voices(json.data)
		if json.data is Dictionary:
			var parsed: Dictionary = json.data
			return _normalize_voices(parsed.get("voices", []))
	return []


func _normalize_voices(raw_voices) -> Array:
	var voices: Array = []
	if not (raw_voices is Array):
		return voices
	var seen := {}
	for item in raw_voices:
		if not (item is Dictionary):
			continue
		var voice: Dictionary = item
		var id := String(voice.get("id", "")).strip_edges()
		var name := String(voice.get("name", id)).strip_edges()
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		voices.append({
			"id": id,
			"name": name if name != "" else id,
			"engine": String(voice.get("engine", "system")),
			"language": String(voice.get("language", voice.get("locale", ""))),
			"locale": String(voice.get("locale", voice.get("language", ""))),
			"gender": String(voice.get("gender", "")),
			"quality": int(voice.get("quality", 0)),
			"latency": int(voice.get("latency", 0)),
			"networkRequired": bool(voice.get("networkRequired", false)),
		})
	return voices


func _float_from_item(item: Dictionary, key: String, default_value: float) -> float:
	var raw = item.get(key, default_value)
	if raw is float or raw is int:
		return float(raw)
	var text := String(raw).strip_edges()
	if text == "":
		return default_value
	return float(text)


func _plugin_bool(value, default_value: bool) -> bool:
	if value is bool:
		return bool(value)
	if value is int:
		return int(value) != 0
	if value is float:
		return absf(float(value)) > 0.0001
	if value is String:
		var normalized := String(value).strip_edges().to_lower()
		if ["true", "1", "yes", "ok"].has(normalized):
			return true
		if ["false", "0", "no", ""].has(normalized):
			return false
	return default_value


func _plugin_returned_false(value) -> bool:
	if value is bool or value is int or value is float or value is String:
		return not _plugin_bool(value, true)
	return false


func _on_plugin_speech_started(utterance_id: int) -> void:
	_bridge_debug("signal speech_started utterance=%d" % utterance_id)
	speech_started.emit(utterance_id)


func _on_plugin_speech_progress(utterance_id: int, ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	_bridge_debug("signal speech_progress utterance=%d ratio=%.2f" % [utterance_id, clamped])
	speech_progress.emit(utterance_id, clamped)


func _on_plugin_speech_done(utterance_id: int) -> void:
	_bridge_debug("signal speech_done utterance=%d" % utterance_id)
	speech_finished.emit(utterance_id)


func _on_plugin_speech_failed(utterance_id: int, error: String = "") -> void:
	_bridge_debug("signal speech_failed utterance=%d error=%s" % [utterance_id, error])
	speech_failed.emit(utterance_id, error)


func _on_plugin_voices_updated(payload: String) -> void:
	var voices := _parse_voice_payload(payload)
	_bridge_debug("signal voices_updated count=%d" % voices.size())
	voices_updated.emit(voices)


func _on_plugin_system_ready() -> void:
	_bridge_debug("signal engine_ready system")
	engine_ready.emit("system")


func _on_plugin_kokoro_ready() -> void:
	_bridge_debug("signal engine_ready local_kokoro")
	engine_ready.emit("local_kokoro")


func _on_plugin_external_ready(engine: String) -> void:
	_bridge_debug("signal engine_ready %s" % engine)
	engine_ready.emit(engine)


func _error(message: String) -> Dictionary:
	_bridge_debug("error=%s" % message)
	return {
		"ok": false,
		"error": message,
	}


func _voice_debug(voice: String) -> String:
	var clean := voice.strip_edges()
	return "<default>" if clean == "" else clean


func _bridge_debug(message: String) -> void:
	if OS.is_debug_build():
		if OS.is_debug_build():
			print("[AndroidTtsBridge][debug] %s" % message)
