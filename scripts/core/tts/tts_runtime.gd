extends Node
class_name TtsRuntime

const AndroidTtsBridgeScript := preload("res://scripts/core/tts/adapters/android_tts_bridge.gd")
const TtsTextSanitizerScript := preload("res://scripts/core/tts/tts_text_sanitizer.gd")

signal speech_started(item: Dictionary)
signal speech_progress(item: Dictionary, ratio: float)
signal speech_finished(item: Dictionary)
signal speech_failed(item: Dictionary, error: String)
signal voices_updated(voices: Array)

const ENGINE_SYSTEM := "system"
const ENGINE_LOCAL_KOKORO := "local_kokoro"
const ENGINE_NEKO_TTS := "neko_tts"
const ENGINE_VOXSHERPA_TTS := "voxsherpa_tts"
const ENGINE_MULTI_TTS := "multi_tts"
const EXTERNAL_ANDROID_ENGINES := [ENGINE_NEKO_TTS, ENGINE_VOXSHERPA_TTS, ENGINE_MULTI_TTS]
const DEFAULT_KOKORO_VOICE := "zf_001"
const NATIVE_TTS_FINISH_GRACE_SECONDS := 2.0
const NATIVE_TTS_NO_CALLBACK_GRACE_SECONDS := 4.0
const NATIVE_TTS_NO_CALLBACK_MIN_TIMEOUT_SECONDS := 10.0
const NATIVE_TTS_NO_PROGRESS_ESTIMATE_SECONDS := 10.0
const ANDROID_TTS_PROGRESS_COMPLETE_RATIO := 0.99
const ANDROID_TTS_PROGRESS_STALL_TIMEOUT_SECONDS := 30.0

var enabled := true
var simulate_in_headless := true
var prefer_android_tts_bridge := true

var _queue: Array = []
var _current: Dictionary = {}
var _current_utterance_id := 0
var _next_utterance_id := 1
var _elapsed := 0.0
var _duration := 0.0
var _native_active := false
var _native_source := ""
var _native_progress_received := false
var _native_last_progress_msec := 0
var _callbacks_bound := false
var _android_callbacks_bound := false
var _android_tts_bridge = AndroidTtsBridgeScript.new()
var _tts_sanitizer = TtsTextSanitizerScript.new()
var _last_progress_ratio := -1.0
var _engine_services := {}
var _configured_engine_signature := ""


func _ready() -> void:
	_bind_tts_callbacks()
	_bind_android_tts_callbacks()


func _exit_tree() -> void:
	stop()


func enqueue(item: Dictionary) -> void:
	if not enabled:
		_tts_debug("enqueue skipped: disabled")
		return
	var text := String(item.get("text", "")).strip_edges()
	if text == "":
		_tts_debug("enqueue skipped: empty text speaker=%s" % String(item.get("speaker", "")))
		return
	var next_item := item.duplicate(true)
	next_item["text"] = text
	var validation := validate_item(next_item)
	if not bool(validation.get("ok", false)):
		_tts_debug("enqueue validation failed engine=%s voice=%s error=%s" % [String(next_item.get("engine", "")), _voice_debug(String(next_item.get("voice", ""))), String(validation.get("error", ""))])
		speech_failed.emit(next_item, String(validation.get("error", "invalid_tts_config")))
		return
	if bool(next_item.get("interrupt", false)):
		stop()
	var engine := String(next_item.get("engine", "")).strip_edges()
	if engine != ENGINE_SYSTEM:
		var warmup := warm_up_engine(engine)
		if not bool(warmup.get("ok", false)):
			_tts_debug("enqueue engine service failed engine=%s error=%s" % [engine, String(warmup.get("error", ""))])
			speech_failed.emit(next_item, String(warmup.get("error", "tts_engine_service_unavailable")))
			return
	_tts_debug("enqueue accepted engine=%s voice=%s text_chars=%d pending=%d" % [String(next_item.get("engine", "")), _voice_debug(String(next_item.get("voice", ""))), text.length(), pending_count()])
	_queue.append(next_item)
	_pump()


func pending_count() -> int:
	return _queue.size() + (0 if _current.is_empty() else 1)


func is_speaking() -> bool:
	return not _current.is_empty()


func current_item() -> Dictionary:
	return _current.duplicate(true)


func skip_current() -> bool:
	if _current.is_empty():
		return false
	if _native_active:
		if _native_source == "android":
			_android_tts_bridge.stop()
		else:
			DisplayServer.tts_stop()
	_cancel_current("skipped")
	return true


func validate_item(item: Dictionary) -> Dictionary:
	var engine := String(item.get("engine", "")).strip_edges()
	var voice := String(item.get("voice", "")).strip_edges()
	var kokoro_available := _can_use_kokoro_tts() if engine == ENGINE_LOCAL_KOKORO else false
	_tts_debug("validate start engine=%s voice=%s display=%s android_bridge=%s kokoro_available=%s" % [engine, _voice_debug(voice), DisplayServer.get_name(), _can_use_android_tts(), kokoro_available])
	if engine == "":
		return _invalid_config("未配置语音引擎")
	if engine != ENGINE_SYSTEM and engine != ENGINE_LOCAL_KOKORO and not _is_external_android_engine(engine):
		return _invalid_config("语音引擎未接入：%s" % engine)
	if engine == ENGINE_LOCAL_KOKORO:
		if voice != "" and not _kokoro_voice_exists(voice):
			return _invalid_config("Kokoro 音色不存在：%s" % voice)
		if DisplayServer.get_name() == "headless":
			return {"ok": true}
		if _can_use_kokoro_tts():
			return {"ok": true}
		return _invalid_config("本地 Kokoro 仅支持已接入插件的 Android 设备")
	if _is_external_android_engine(engine):
		if DisplayServer.get_name() == "headless":
			return {"ok": true}
		if not _can_use_android_tts():
			return _invalid_config("本地非系统 TTS 仅支持已接入插件的 Android 设备")
		if not _can_use_external_tts(engine):
			return _invalid_config("本地 TTS 引擎不可用：%s" % _engine_display_name(engine))
		if voice != "":
			var external_voices := available_external_voices(engine, "")
			if not external_voices.is_empty() and not _voice_array_has(external_voices, voice):
				return _invalid_config("%s 音色不存在：%s" % [_engine_display_name(engine), voice])
		return {"ok": true}
	if voice == "":
		if can_use_system_default_voice():
			_tts_debug("validate system default accepted source=android")
			return {"ok": true}
		if _can_fallback_system_default_to_kokoro():
			_tts_debug("validate system default accepted source=kokoro_fallback voice=%s" % DEFAULT_KOKORO_VOICE)
			return {"ok": true}
		return _invalid_config("未配置系统音色 ID：当前环境不能使用系统默认音色，请等待 Android TTS 音色列表刷新后选择具体音色")
	if DisplayServer.get_name() == "headless":
		return {"ok": true}
	if _can_use_android_tts():
		var android_voices := _android_tts_bridge.available_voices("")
		_tts_debug("validate system android voices count=%d voice=%s" % [android_voices.size(), _voice_debug(voice)])
		if android_voices.is_empty() or _voice_array_has(android_voices, voice):
			return {"ok": true}
		return _invalid_config("系统音色不存在：%s" % voice)
	if not _voice_exists(voice):
		return _invalid_config("系统音色不存在：%s" % voice)
	return {"ok": true}


func stop() -> void:
	_queue.clear()
	if _native_active:
		if _native_source == "android":
			_android_tts_bridge.stop()
		else:
			DisplayServer.tts_stop()
	_native_active = false
	_native_source = ""
	if not _current.is_empty():
		var stopped := _current.duplicate(true)
		_current.clear()
		_native_progress_received = false
		_native_last_progress_msec = 0
		speech_failed.emit(stopped, "stopped")


func tick(delta: float) -> void:
	if _current.is_empty():
		_pump()
		return
	_elapsed += delta
	if _duration > 0.0 and not _native_active:
		var ratio := clampf(_elapsed / _duration, 0.0, 1.0)
		_emit_progress(ratio, "estimated")
	if _native_active:
		if _native_progress_received:
			var idle_seconds := _native_progress_idle_seconds()
			if _last_progress_ratio >= ANDROID_TTS_PROGRESS_COMPLETE_RATIO and idle_seconds >= NATIVE_TTS_FINISH_GRACE_SECONDS:
				_tts_debug("finish fallback utterance=%d source=%s elapsed=%.2f duration=%.2f progress=%.2f idle=%.2f" % [_current_utterance_id, _native_source, _elapsed, _duration, _last_progress_ratio, idle_seconds])
				_finish_current()
			elif idle_seconds >= ANDROID_TTS_PROGRESS_STALL_TIMEOUT_SECONDS:
				_tts_debug("native progress timeout utterance=%d source=%s elapsed=%.2f idle=%.2f progress=%.2f duration=%.2f" % [_current_utterance_id, _native_source, _elapsed, idle_seconds, _last_progress_ratio, _duration])
				if _native_source == "android":
					_android_tts_bridge.stop()
				elif DisplayServer.get_name() != "headless":
					DisplayServer.tts_stop()
				_cancel_current("TTS播放超时，原生进度停滞")
			return
		if _elapsed >= NATIVE_TTS_NO_PROGRESS_ESTIMATE_SECONDS:
			var fallback_duration := _native_no_callback_timeout_seconds(_current)
			var ratio := clampf(_elapsed / maxf(fallback_duration, 0.1), 0.0, 1.0)
			_emit_progress(ratio, "estimated")
			if _elapsed >= fallback_duration:
				_tts_debug("finish estimated fallback utterance=%d source=%s elapsed=%.2f fallback_duration=%.2f duration=%.2f reason=no_progress_after_10s" % [_current_utterance_id, _native_source, _elapsed, fallback_duration, _duration])
				if _native_source == "android":
					_android_tts_bridge.stop()
				elif DisplayServer.get_name() != "headless":
					DisplayServer.tts_stop()
				_finish_current()
		return
	if _elapsed >= _duration:
		_finish_current()


func _process(delta: float) -> void:
	tick(delta)


func available_system_voices(language: String = "zh") -> Array:
	if _can_use_android_tts():
		var android_voices := _android_tts_bridge.available_voices(language)
		_tts_debug("available_system_voices source=android language=%s count=%d" % [language, android_voices.size()])
		return android_voices
	var voices: Array = []
	if DisplayServer.get_name() == "headless":
		_tts_debug("available_system_voices source=headless language=%s count=0" % language)
		return voices
	if _is_android_os():
		_tts_debug("available_system_voices source=android-no-bridge language=%s count=0" % language)
		return voices
	for item in DisplayServer.tts_get_voices():
		if not (item is Dictionary):
			continue
		var voice: Dictionary = item
		var voice_language := String(voice.get("language", ""))
		if language == "" or voice_language.begins_with(language):
			voices.append(voice.duplicate(true))
	_tts_debug("available_system_voices source=display language=%s count=%d" % [language, voices.size()])
	return voices


func available_kokoro_voices(language: String = "zh") -> Array:
	if _android_tts_bridge != null and _android_tts_bridge.has_method("available_kokoro_voices"):
		var native_voices: Array = _android_tts_bridge.call("available_kokoro_voices", language)
		if not native_voices.is_empty():
			_tts_debug("available_kokoro_voices source=android language=%s count=%d" % [language, native_voices.size()])
			return native_voices
	var voices: Array = []
	for item in _tts_sanitizer.kokoro_voices():
		if not (item is Dictionary):
			continue
		var voice: Dictionary = item
		var voice_language := String(voice.get("language", voice.get("locale", "")))
		if language == "" or voice_language == "" or voice_language.begins_with(language):
			voices.append(voice.duplicate(true))
	_tts_debug("available_kokoro_voices source=bundled-list language=%s count=%d" % [language, voices.size()])
	return voices


func available_external_voices(engine: String, language: String = "zh") -> Array:
	var normalized := _normalize_engine_name(engine)
	if not _is_external_android_engine(normalized):
		return []
	if _android_tts_bridge != null and _android_tts_bridge.has_method("available_external_voices"):
		var native_voices: Array = _android_tts_bridge.call("available_external_voices", normalized, language)
		_tts_debug("available_external_voices engine=%s language=%s count=%d" % [normalized, language, native_voices.size()])
		return native_voices
	return []


func is_engine_available(engine: String) -> bool:
	var normalized := _normalize_engine_name(engine)
	match normalized:
		ENGINE_SYSTEM:
			if DisplayServer.get_name() == "headless":
				return true
			if _can_use_android_tts():
				return can_use_system_default_voice()
			if _is_android_os():
				return false
			return not DisplayServer.tts_get_voices().is_empty()
		ENGINE_LOCAL_KOKORO:
			if DisplayServer.get_name() == "headless":
				return true
			return _can_use_kokoro_tts()
		_:
			if _is_external_android_engine(normalized):
				if DisplayServer.get_name() == "headless":
					return true
				return _can_use_android_tts() and _can_use_external_tts(normalized)
			return false


func configure_voice_configs(configs: Array) -> Dictionary:
	var engines: Array = []
	var seen := {}
	for item in configs:
		if not (item is Dictionary):
			continue
		var config: Dictionary = item
		if not bool(config.get("enabled", true)):
			continue
		var engine := _normalize_engine_name(String(config.get("engine", ENGINE_SYSTEM)))
		if engine == "" or seen.has(engine):
			continue
		if engine == ENGINE_SYSTEM:
			_tts_debug("configure_voice_configs skip eager warmup engine=system")
			continue
		seen[engine] = true
		engines.append(engine)
	var signature := "|".join(engines)
	if signature == _configured_engine_signature:
		return {"ok": true, "engines": engines, "reused": true}
	_configured_engine_signature = signature
	var errors: Array = []
	for engine in engines:
		var result := warm_up_engine(String(engine))
		if not bool(result.get("ok", false)):
			errors.append({"engine": engine, "error": String(result.get("error", "引擎预热失败"))})
	_tts_debug("configure_voice_configs engines=%s errors=%s" % [JSON.stringify(engines), JSON.stringify(errors)])
	return {
		"ok": errors.is_empty(),
		"engines": engines,
		"errors": errors,
	}


func warm_up_engine(engine: String) -> Dictionary:
	var normalized := _normalize_engine_name(engine)
	var kokoro_available := _can_use_kokoro_tts() if normalized == ENGINE_LOCAL_KOKORO else false
	_tts_debug("warm_up_engine request engine=%s display=%s android_bridge=%s kokoro_available=%s" % [normalized, DisplayServer.get_name(), _can_use_android_tts(), kokoro_available])
	if normalized != ENGINE_SYSTEM:
		return _warm_up_non_system_engine_service(normalized)
	return _warm_up_system_engine_service(normalized)


func debug_snapshot() -> Dictionary:
	var snapshot := {
		"ok": true,
		"display": DisplayServer.get_name(),
		"os": OS.get_name(),
		"android_bridge": _can_use_android_tts(),
		"engine_services": _engine_services.duplicate(true),
		"configured_engine_signature": _configured_engine_signature,
		"pending_count": pending_count(),
		"queue_count": _queue.size(),
		"current_utterance_id": _current_utterance_id,
		"current": _current.duplicate(true),
		"queue": _debug_queue_snapshot(),
		"elapsed": _elapsed,
		"duration": _duration,
		"native_no_callback_timeout": _native_no_callback_timeout_seconds(_current) if not _current.is_empty() else 0.0,
		"native_active": _native_active,
		"native_source": _native_source,
		"native_progress_received": _native_progress_received,
		"native_last_progress_msec": _native_last_progress_msec,
		"native_progress_idle_seconds": _native_progress_idle_seconds() if _native_progress_received else 0.0,
		"last_progress_ratio": _last_progress_ratio,
	}
	if _android_tts_bridge != null and _android_tts_bridge.has_method("debug_snapshot"):
		snapshot["android"] = _android_tts_bridge.call("debug_snapshot")
	return snapshot


func _warm_up_system_engine_service(engine: String) -> Dictionary:
	var normalized := engine.strip_edges()
	var service := _engine_service_state(normalized)
	if bool(service.get("warm_requested", false)) and String(service.get("state", "")) != "failed":
		_tts_debug("engine_service reuse engine=%s state=%s warm_count=%d" % [normalized, String(service.get("state", "")), int(service.get("warm_count", 0))])
		return {"ok": true, "engine": normalized, "state": String(service.get("state", "warming")), "reused": true}
	service["warm_requested"] = true
	service["state"] = "warming"
	service["warm_count"] = int(service.get("warm_count", 0)) + 1
	service["last_error"] = ""
	service["updated_at_ms"] = Time.get_ticks_msec()
	_engine_services[normalized] = service
	var result := _warm_up_engine_native(normalized)
	if bool(result.get("ok", false)):
		if _can_use_android_tts():
			service["state"] = "warming"
		else:
			service["state"] = "ready"
			service["ready_at_ms"] = Time.get_ticks_msec()
		service["last_ok_at_ms"] = Time.get_ticks_msec()
		_engine_services[normalized] = service
		return result
	service["state"] = "failed"
	service["last_error"] = String(result.get("error", "引擎预热失败"))
	service["warm_requested"] = false
	_engine_services[normalized] = service
	return result


func _warm_up_engine_native(normalized: String) -> Dictionary:
	_tts_debug("warm_up_engine native start engine=%s" % normalized)
	if normalized == ENGINE_LOCAL_KOKORO:
		if DisplayServer.get_name() == "headless":
			return {"ok": true, "source": "headless"}
		if _android_tts_bridge == null or not _android_tts_bridge.has_method("warm_up_kokoro"):
			return _invalid_config("Android Kokoro TTS 桥未接入")
		var kokoro_result: Dictionary = _android_tts_bridge.call("warm_up_kokoro")
		_tts_debug("warm_up_engine kokoro result=%s" % JSON.stringify(kokoro_result))
		return kokoro_result
	if _is_external_android_engine(normalized):
		if DisplayServer.get_name() == "headless":
			return {"ok": true, "source": "headless"}
		if _android_tts_bridge == null or not _android_tts_bridge.has_method("warm_up_external_engine"):
			return _invalid_config("Android 本地 TTS 桥未接入")
		var external_result: Dictionary = _android_tts_bridge.call("warm_up_external_engine", normalized)
		_tts_debug("warm_up_engine external result engine=%s result=%s" % [normalized, JSON.stringify(external_result)])
		return external_result
	if normalized == ENGINE_SYSTEM:
		if _can_use_android_tts() and _android_tts_bridge.has_method("warm_up"):
			var system_result: Dictionary = _android_tts_bridge.call("warm_up")
			_tts_debug("warm_up_engine system result=%s" % JSON.stringify(system_result))
			return system_result
		if _is_android_os():
			return _invalid_config("Android 系统 TTS 插件未就绪")
		if DisplayServer.get_name() != "headless":
			return {"ok": true, "source": "display"}
		return _invalid_config("当前环境没有可用系统 TTS")
	return _invalid_config("语音引擎未接入：%s" % normalized)


func _warm_up_non_system_engine_service(engine: String) -> Dictionary:
	var normalized := engine.strip_edges()
	var service := _engine_service_state(normalized)
	if bool(service.get("warm_requested", false)) and String(service.get("state", "")) != "failed":
		_tts_debug("engine_service reuse engine=%s state=%s warm_count=%d" % [normalized, String(service.get("state", "")), int(service.get("warm_count", 0))])
		return {"ok": true, "engine": normalized, "state": String(service.get("state", "warming")), "reused": true}
	if not _is_non_system_engine_integrated(normalized):
		service["state"] = "failed"
		service["last_error"] = "语音引擎未接入：%s" % normalized
		_engine_services[normalized] = service
		_tts_debug("engine_service unavailable engine=%s" % normalized)
		return _invalid_config(String(service["last_error"]))
	service["warm_requested"] = true
	service["state"] = "warming"
	service["warm_count"] = int(service.get("warm_count", 0)) + 1
	service["last_error"] = ""
	service["updated_at_ms"] = Time.get_ticks_msec()
	_engine_services[normalized] = service
	_tts_debug("engine_service warmup start engine=%s warm_count=%d" % [normalized, int(service["warm_count"])])
	var result := _warm_up_engine_native(normalized)
	if bool(result.get("ok", false)):
		service["state"] = "warming"
		service["last_ok_at_ms"] = Time.get_ticks_msec()
		_engine_services[normalized] = service
		_tts_debug("engine_service warmup accepted engine=%s result=%s" % [normalized, JSON.stringify(result)])
		return result
	service["state"] = "failed"
	service["last_error"] = String(result.get("error", "引擎预热失败"))
	service["warm_requested"] = false
	_engine_services[normalized] = service
	_tts_debug("engine_service warmup failed engine=%s error=%s" % [normalized, String(service["last_error"])])
	return result


func can_use_system_default_voice() -> bool:
	var result := false
	if DisplayServer.get_name() == "headless":
		result = false
	elif _can_use_android_tts():
		result = not _android_tts_bridge.available_voices("").is_empty()
	elif _is_android_os():
		result = false
	else:
		result = not DisplayServer.tts_get_voices().is_empty()
	_tts_debug("can_use_system_default_voice=%s display=%s" % [str(result), DisplayServer.get_name()])
	return result


func _pump() -> void:
	if not _current.is_empty() or _queue.is_empty():
		return
	_current = (_queue.pop_front() as Dictionary).duplicate(true)
	_current_utterance_id = _next_utterance_id
	_next_utterance_id += 1
	_elapsed = 0.0
	_duration = _estimated_duration(String(_current.get("text", "")), _rate_from_item(_current))
	_last_progress_ratio = -1.0
	_native_active = false
	_native_source = ""
	_native_progress_received = false
	_native_last_progress_msec = 0
	_tts_debug("pump start utterance=%d engine=%s voice=%s text_chars=%d" % [_current_utterance_id, String(_current.get("engine", "")), _voice_debug(String(_current.get("voice", ""))), String(_current.get("text", "")).length()])
	speech_started.emit(_current.duplicate(true))
	_emit_progress(0.0, "estimated")
	if _can_use_native_tts():
		_speak_native(_current, _current_utterance_id)


func _can_use_native_tts() -> bool:
	if DisplayServer.get_name() == "headless":
		return not simulate_in_headless
	if _can_use_android_tts():
		return true
	return true


func _speak_native(item: Dictionary, utterance_id: int) -> void:
	var engine := String(item.get("engine", ENGINE_SYSTEM)).strip_edges()
	if engine == ENGINE_LOCAL_KOKORO:
		var warmup := warm_up_engine(engine)
		if not bool(warmup.get("ok", false)):
			_cancel_current(String(warmup.get("error", "本地 Kokoro 预热失败")))
			return
		if _can_use_kokoro_tts():
			_speak_android(item, utterance_id)
			return
		_tts_debug("speak native kokoro unavailable utterance=%d" % utterance_id)
		_cancel_current("本地 Kokoro 仅支持已接入插件的 Android 设备")
		return
	if _is_external_android_engine(engine):
		var warmup := warm_up_engine(engine)
		if not bool(warmup.get("ok", false)):
			_cancel_current(String(warmup.get("error", "%s 预热失败" % _engine_display_name(engine))))
			return
		if _can_use_android_tts():
			_speak_android(item, utterance_id)
			return
		_tts_debug("speak native external unavailable utterance=%d engine=%s" % [utterance_id, engine])
		_cancel_current("本地非系统 TTS 仅支持已接入插件的 Android 设备")
		return
	if engine == ENGINE_SYSTEM and String(item.get("voice", "")).strip_edges() == "" and not can_use_system_default_voice():
		if _try_speak_system_default_with_kokoro_fallback(item, utterance_id, "system_default_unavailable"):
			return
	if _can_use_android_tts():
		_speak_android(item, utterance_id)
		return
	var text := String(item.get("text", ""))
	var voice := _voice_id_for_item(item)
	if voice == "":
		_tts_debug("speak display failed: empty system voice utterance=%d" % utterance_id)
		_cancel_current("未配置系统音色 ID")
		return
	var volume := _volume_from_item(item)
	var pitch := _pitch_from_item(item)
	var rate := _rate_from_item(item)
	var interrupt := bool(item.get("interrupt", false))
	_native_active = true
	_native_source = "display"
	_tts_debug("speak display utterance=%d voice=%s rate=%.2f pitch=%.2f volume=%d" % [utterance_id, _voice_debug(voice), rate, pitch, volume])
	DisplayServer.tts_speak(text, voice, volume, pitch, rate, utterance_id, interrupt)


func _speak_android(item: Dictionary, utterance_id: int) -> void:
	_native_active = true
	_native_source = "android"
	_tts_debug("speak android utterance=%d engine=%s voice=%s" % [utterance_id, String(item.get("engine", "")), _voice_debug(String(item.get("voice", "")))])
	var result: Dictionary = _android_tts_bridge.speak(item, utterance_id)
	if not bool(result.get("ok", false)):
		_tts_debug("speak android failed utterance=%d error=%s" % [utterance_id, String(result.get("error", ""))])
		_cancel_current(String(result.get("error", "Android TTS 播放启动失败")))
		return


func _finish_current() -> void:
	if _current.is_empty():
		return
	var finished := _current.duplicate(true)
	_tts_debug("finish utterance=%d engine=%s voice=%s" % [_current_utterance_id, String(finished.get("engine", "")), _voice_debug(String(finished.get("voice", "")))])
	_emit_progress(1.0, "native" if _native_progress_received else "estimated")
	_current.clear()
	_native_active = false
	_native_source = ""
	_native_progress_received = false
	_native_last_progress_msec = 0
	speech_finished.emit(finished)
	_pump()


func _cancel_current(error: String) -> void:
	if _current.is_empty():
		return
	var canceled := _current.duplicate(true)
	_tts_debug("cancel utterance=%d engine=%s voice=%s error=%s" % [_current_utterance_id, String(canceled.get("engine", "")), _voice_debug(String(canceled.get("voice", ""))), error])
	_current.clear()
	_native_active = false
	_native_source = ""
	_native_progress_received = false
	_native_last_progress_msec = 0
	speech_failed.emit(canceled, error)
	_pump()


func _emit_progress(ratio: float, source: String = "estimated") -> void:
	var rounded := floorf(clampf(ratio, 0.0, 1.0) * 100.0) / 100.0
	if rounded < _last_progress_ratio and _last_progress_ratio < 1.0:
		return
	if absf(rounded - _last_progress_ratio) < 0.01 and rounded < 1.0:
		return
	_last_progress_ratio = rounded
	var item := _current.duplicate(true)
	item["progress_source"] = source
	speech_progress.emit(item, rounded)


func _bind_tts_callbacks() -> void:
	if _callbacks_bound or DisplayServer.get_name() == "headless":
		return
	_callbacks_bound = true
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, Callable(self, "_on_native_tts_started"))
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, Callable(self, "_on_native_tts_ended"))
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, Callable(self, "_on_native_tts_canceled"))
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_BOUNDARY, Callable(self, "_on_native_tts_boundary"))


func _bind_android_tts_callbacks() -> void:
	if _android_callbacks_bound:
		return
	_android_callbacks_bound = true
	_android_tts_bridge.speech_started.connect(_on_android_tts_started)
	if _android_tts_bridge.has_signal("speech_progress"):
		_android_tts_bridge.speech_progress.connect(_on_android_tts_progress)
	_android_tts_bridge.speech_finished.connect(_on_android_tts_ended)
	_android_tts_bridge.speech_failed.connect(_on_android_tts_failed)
	_android_tts_bridge.voices_updated.connect(_on_android_voices_updated)
	if _android_tts_bridge.has_signal("engine_ready"):
		_android_tts_bridge.engine_ready.connect(_on_android_engine_ready)


func _on_native_tts_started(utterance_id: int) -> void:
	if utterance_id != _current_utterance_id or _current.is_empty():
		return
	_elapsed = 0.0
	_native_last_progress_msec = Time.get_ticks_msec()
	_emit_progress(0.0, "estimated")


func _on_native_tts_ended(utterance_id: int) -> void:
	if utterance_id != _current_utterance_id:
		return
	_finish_current()


func _on_native_tts_canceled(utterance_id: int) -> void:
	if utterance_id != _current_utterance_id:
		return
	_cancel_current("canceled")


func _on_native_tts_boundary(char_index: int, utterance_id: int) -> void:
	if utterance_id != _current_utterance_id or _current.is_empty():
		return
	var text := String(_current.get("text", ""))
	if text == "":
		return
	var ratio := clampf(float(char_index) / float(text.length()), 0.0, 1.0)
	_native_progress_received = true
	_native_last_progress_msec = Time.get_ticks_msec()
	_emit_progress(ratio, "native")


func _on_android_tts_started(utterance_id: int) -> void:
	if utterance_id != _current_utterance_id or _current.is_empty():
		return
	_elapsed = 0.0
	_native_last_progress_msec = Time.get_ticks_msec()
	_emit_progress(0.0, "estimated")


func _on_android_tts_progress(utterance_id: int, ratio: float) -> void:
	if utterance_id != _current_utterance_id or _current.is_empty():
		return
	_native_progress_received = true
	_native_last_progress_msec = Time.get_ticks_msec()
	_emit_progress(ratio, "native")


func _on_android_tts_ended(utterance_id: int) -> void:
	if utterance_id != _current_utterance_id:
		return
	_finish_current()


func _on_android_tts_failed(utterance_id: int, error: String = "") -> void:
	if utterance_id != _current_utterance_id or _current.is_empty():
		return
	var message := "Android TTS 播放失败" if error == "" else error
	if _try_speak_system_default_with_kokoro_fallback(_current, utterance_id, message):
		return
	_cancel_current(message)


func _on_android_voices_updated(voices: Array) -> void:
	_tts_debug("android voices_updated count=%d" % voices.size())
	voices_updated.emit(voices)


func _on_android_engine_ready(engine: String) -> void:
	var normalized := engine.strip_edges()
	var service := _engine_service_state(normalized)
	service["state"] = "ready"
	service["ready_at_ms"] = Time.get_ticks_msec()
	service["last_error"] = ""
	_engine_services[normalized] = service
	_tts_debug("engine_service ready engine=%s state=%s" % [normalized, JSON.stringify(service)])


func _voice_id_for_item(item: Dictionary) -> String:
	return String(item.get("voice", "")).strip_edges()


func _voice_exists(voice_id: String) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if _is_android_os() and not _can_use_android_tts():
		_tts_debug("voice_exists skipped source=android-no-bridge voice=%s" % _voice_debug(voice_id))
		return false
	for item in DisplayServer.tts_get_voices():
		if item is Dictionary and String((item as Dictionary).get("id", "")) == voice_id:
			return true
	return false


func _is_android_os() -> bool:
	return OS.get_name() == "Android"


func _normalize_engine_name(engine: String) -> String:
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


func _can_use_android_tts() -> bool:
	return prefer_android_tts_bridge and _android_tts_bridge != null and _android_tts_bridge.is_available()


func _can_use_kokoro_tts() -> bool:
	var result := _android_tts_bridge != null and _android_tts_bridge.has_method("is_kokoro_available") and bool(_android_tts_bridge.call("is_kokoro_available"))
	_tts_debug("can_use_kokoro_tts=%s" % str(result))
	return result


func _can_fallback_system_default_to_kokoro() -> bool:
	if DisplayServer.get_name() == "headless" and not _can_use_android_tts():
		return false
	return _can_use_kokoro_tts() and _kokoro_voice_exists(DEFAULT_KOKORO_VOICE)


func _try_speak_system_default_with_kokoro_fallback(item: Dictionary, utterance_id: int, reason: String) -> bool:
	if item.is_empty():
		return false
	if String(item.get("engine", ENGINE_SYSTEM)).strip_edges() != ENGINE_SYSTEM:
		return false
	if String(item.get("voice", "")).strip_edges() != "":
		return false
	if not _can_fallback_system_default_to_kokoro():
		_tts_debug("system default kokoro fallback unavailable utterance=%d reason=%s" % [utterance_id, reason])
		return false
	var warmup := warm_up_engine(ENGINE_LOCAL_KOKORO)
	if not bool(warmup.get("ok", false)):
		_tts_debug("system default kokoro fallback warmup failed utterance=%d error=%s" % [utterance_id, String(warmup.get("error", ""))])
		return false
	var fallback := item.duplicate(true)
	fallback["engine"] = ENGINE_LOCAL_KOKORO
	fallback["voice"] = DEFAULT_KOKORO_VOICE
	fallback["fallback_from_engine"] = ENGINE_SYSTEM
	fallback["fallback_reason"] = reason
	if utterance_id == _current_utterance_id and not _current.is_empty():
		_current = fallback.duplicate(true)
	_native_active = false
	_native_source = ""
	_native_progress_received = false
	_tts_debug("system default kokoro fallback start utterance=%d voice=%s reason=%s" % [utterance_id, DEFAULT_KOKORO_VOICE, reason])
	_speak_android(fallback, utterance_id)
	return true


func _can_use_external_tts(engine: String) -> bool:
	var normalized := _normalize_engine_name(engine)
	var result := _android_tts_bridge != null and _android_tts_bridge.has_method("is_external_engine_available") and bool(_android_tts_bridge.call("is_external_engine_available", normalized))
	_tts_debug("can_use_external_tts engine=%s result=%s" % [normalized, str(result)])
	return result


func _is_external_android_engine(engine: String) -> bool:
	return EXTERNAL_ANDROID_ENGINES.has(_normalize_engine_name(engine))


func _is_non_system_engine_integrated(engine: String) -> bool:
	match engine:
		ENGINE_LOCAL_KOKORO:
			if DisplayServer.get_name() == "headless":
				return true
			return _android_tts_bridge != null and _android_tts_bridge.has_method("warm_up_kokoro") and _can_use_kokoro_tts()
		_:
			if _is_external_android_engine(engine):
				if DisplayServer.get_name() == "headless":
					return true
				return _android_tts_bridge != null and _android_tts_bridge.has_method("warm_up_external_engine") and _can_use_external_tts(engine)
			return false


func _engine_service_state(engine: String) -> Dictionary:
	var normalized := engine.strip_edges()
	if _engine_services.has(normalized) and _engine_services[normalized] is Dictionary:
		return (_engine_services[normalized] as Dictionary).duplicate(true)
	return {
		"engine": normalized,
		"state": "cold",
		"warm_requested": false,
		"warm_count": 0,
		"last_error": "",
		"created_at_ms": Time.get_ticks_msec(),
	}


func _debug_queue_snapshot() -> Array:
	var result := []
	for item in _queue:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _android_voice_exists(voice_id: String) -> bool:
	for item in _android_tts_bridge.available_voices(""):
		if item is Dictionary and String((item as Dictionary).get("id", "")) == voice_id:
			return true
	return false


func _voice_array_has(voices: Array, voice_id: String) -> bool:
	for item in voices:
		if item is Dictionary and String((item as Dictionary).get("id", "")) == voice_id:
			return true
	return false


func _kokoro_voice_exists(voice_id: String) -> bool:
	var normalized := voice_id.strip_edges()
	for item in available_kokoro_voices(""):
		if item is Dictionary and String((item as Dictionary).get("id", "")) == normalized:
			return true
	return false


func _volume_from_item(item: Dictionary) -> int:
	return int(roundi(clampf(float(String(item.get("volume", "1.00"))), 0.0, 1.0) * 100.0))


func _pitch_from_item(item: Dictionary) -> float:
	return clampf(float(String(item.get("pitch", "1.00"))), 0.0, 2.0)


func _rate_from_item(item: Dictionary) -> float:
	var speed := clampf(float(String(item.get("speed", "0.85"))), 0.1, 2.0)
	return clampf(speed, 0.1, 10.0)


func _estimated_duration(text: String, rate: float) -> float:
	var chinese_chars := 0
	for i in range(text.length()):
		var code := text.unicode_at(i)
		if code >= 0x3400 and code <= 0x9fff:
			chinese_chars += 1
	var units := maxi(chinese_chars, text.length() / 2)
	var chars_per_second := 4.4 * maxf(rate, 0.1)
	return clampf(float(units) / chars_per_second + 0.35, 0.7, 12.0)


func _native_no_callback_timeout_seconds(item: Dictionary) -> float:
	if item.is_empty():
		return 0.0
	var text := String(item.get("text", "")).strip_edges()
	var by_text := float(maxi(1, text.length())) * 0.5 + NATIVE_TTS_NO_CALLBACK_GRACE_SECONDS
	return maxf(NATIVE_TTS_NO_CALLBACK_MIN_TIMEOUT_SECONDS, maxf(_duration + NATIVE_TTS_FINISH_GRACE_SECONDS, by_text))


func _native_progress_idle_seconds() -> float:
	if _native_last_progress_msec <= 0:
		return _elapsed
	return maxf(0.0, float(Time.get_ticks_msec() - _native_last_progress_msec) / 1000.0)


func _engine_display_name(engine: String) -> String:
	match _normalize_engine_name(engine):
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


func _invalid_config(error: String) -> Dictionary:
	_tts_debug("invalid_config error=%s" % error)
	return {
		"ok": false,
		"error": error,
	}


func _voice_debug(voice: String) -> String:
	return "<default>" if voice.strip_edges() == "" else voice.strip_edges()


func _tts_debug(message: String) -> void:
	if OS.is_debug_build():
		if OS.is_debug_build():
			print("[TtsRuntime][debug] %s" % message)
