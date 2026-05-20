extends SceneTree


class FakeTtsPlugin:
	extends Node

	signal tts_speech_started(utterance_id: int)
	signal tts_speech_progress(utterance_id: int, ratio: float)
	signal tts_speech_done(utterance_id: int)
	signal tts_speech_failed(utterance_id: int, error: String)
	signal tts_voices_updated(payload: String)
	signal external_tts_ready(engine: String)

	var warmed := false
	var external_warmed: Array = []
	var stopped := false
	var speak_calls: Array = []
	var system_voices := [
		{"id": "zh-CN::voice_a", "name": "voice_a", "engine": "system", "language": "zh-CN"},
		{"id": "en-US::voice_b", "name": "voice_b", "engine": "system", "language": "en-US"},
	]

	func tts_warm_up() -> bool:
		warmed = true
		return true

	func tts_list_voices() -> String:
		return JSON.stringify(system_voices)

	func tts_kokoro_available():
		return 1

	func tts_list_kokoro_voices() -> String:
		return JSON.stringify([
			{"id": "zf_001", "name": "Kokoro 女声 zf_001", "engine": "local_kokoro", "language": "zh-CN"},
		])

	func tts_external_available(engine: String):
		return 1 if ["neko_tts", "voxsherpa_tts", "multi_tts"].has(engine) else 0

	func tts_external_warm_up(engine: String):
		external_warmed.append(engine)
		external_tts_ready.emit(engine)
		return 1

	func tts_debug_available():
		return "true"

	func tts_debug_snapshot() -> String:
		return JSON.stringify({
			"ok": true,
			"debuggable": true,
			"mode": "in_app_inference",
			"systemTtsServiceDiscovery": false,
			"localEngines": [
				{"id": "neko_tts", "available": true, "backend": "kokoro_sherpa"},
				{"id": "voxsherpa_tts", "available": true, "backend": "kokoro_sherpa"},
				{"id": "multi_tts", "available": true, "backend": "kokoro_sherpa"},
			],
		})

	func tts_list_external_voices(engine: String) -> String:
		return JSON.stringify([
			{"id": "zh-CN::%s_female" % engine, "name": "%s female" % engine, "engine": engine, "language": "zh-CN"},
			{"id": "en-US::%s_male" % engine, "name": "%s male" % engine, "engine": engine, "language": "en-US"},
		])

	func tts_speak(text: String, voice_id: String, speed: float, pitch: float, volume: float, utterance_id: int, interrupt: bool) -> bool:
		speak_calls.append({
			"text": text,
			"voice": voice_id,
			"engine": "system",
			"speed": speed,
			"pitch": pitch,
			"volume": volume,
			"utterance_id": utterance_id,
			"interrupt": interrupt,
		})
		tts_speech_started.emit(utterance_id)
		tts_speech_progress.emit(utterance_id, 0.5)
		tts_speech_done.emit(utterance_id)
		return true

	func tts_speak_kokoro(text: String, voice_id: String, speed: float, pitch: float, volume: float, utterance_id: int, interrupt: bool) -> bool:
		speak_calls.append({
			"text": text,
			"voice": voice_id,
			"engine": "local_kokoro",
			"speed": speed,
			"pitch": pitch,
			"volume": volume,
			"utterance_id": utterance_id,
			"interrupt": interrupt,
		})
		tts_speech_started.emit(utterance_id)
		tts_speech_progress.emit(utterance_id, 0.5)
		tts_speech_done.emit(utterance_id)
		return true

	func tts_speak_external(engine: String, text: String, voice_id: String, speed: float, pitch: float, volume: float, utterance_id: int, interrupt: bool):
		speak_calls.append({
			"text": text,
			"voice": voice_id,
			"engine": engine,
			"speed": speed,
			"pitch": pitch,
			"volume": volume,
			"utterance_id": utterance_id,
			"interrupt": interrupt,
		})
		tts_speech_started.emit(utterance_id)
		tts_speech_progress.emit(utterance_id, 0.5)
		tts_speech_done.emit(utterance_id)
		return 1

	func tts_stop() -> bool:
		stopped = true
		return true


class TestTtsBridge:
	extends AndroidTtsBridge

	var plugin

	func _init(plugin_ref) -> void:
		plugin = plugin_ref

	func _plugin():
		return plugin


func _initialize() -> void:
	var plugin := FakeTtsPlugin.new()
	root.add_child(plugin)

	var bridge := TestTtsBridge.new(plugin)
	assert(bridge.is_available())
	assert(bridge._normalize_engine_id("NekoTTS") == "neko_tts")
	assert(bridge._normalize_engine_id("NekoSpeak") == "neko_tts")
	assert(bridge._normalize_engine_id("VoxSherpa-TTS") == "voxsherpa_tts")
	assert(bridge._normalize_engine_id("MultiTTS") == "multi_tts")
	var voices: Array = bridge.available_voices("zh")
	assert(plugin.warmed)
	assert(voices.size() == 1)
	assert(String((voices[0] as Dictionary).get("id", "")) == "zh-CN::voice_a")
	var kokoro_voices: Array = bridge.available_kokoro_voices("zh")
	assert(bridge.is_kokoro_available())
	assert(kokoro_voices.size() == 1)
	assert(String((kokoro_voices[0] as Dictionary).get("id", "")) == "zf_001")
	assert(bridge.is_external_engine_available("VoxSherpa-TTS"))
	assert(bool(bridge.warm_up_external_engine("VoxSherpa-TTS").get("ok", false)))
	assert(plugin.external_warmed.size() == 1 and String(plugin.external_warmed[0]) == "voxsherpa_tts")
	assert(bridge.is_external_engine_available("NekoTTS"))
	assert(bool(bridge.warm_up_external_engine("NekoTTS").get("ok", false)))
	assert(plugin.external_warmed.size() == 2 and String(plugin.external_warmed[1]) == "neko_tts")
	var external_voices: Array = bridge.available_external_voices("VoxSherpa-TTS", "zh")
	assert(external_voices.size() == 1)
	assert(String((external_voices[0] as Dictionary).get("engine", "")) == "voxsherpa_tts")
	assert(bridge.debug_available())
	var debug_snapshot: Dictionary = bridge.debug_snapshot()
	assert(bool(debug_snapshot.get("ok", false)))
	var debug_engines := debug_snapshot.get("localEngines", []) as Array
	assert(debug_engines.size() == 3)
	var first_debug_engine := debug_engines[0] as Dictionary
	assert(String(first_debug_engine.get("id", "")) == "neko_tts")
	assert(not bool(debug_snapshot.get("systemTtsServiceDiscovery", true)))

	var started: Array = []
	var progress: Array = []
	var finished: Array = []
	bridge.speech_started.connect(func(utterance_id: int): started.append(utterance_id))
	bridge.speech_progress.connect(func(utterance_id: int, ratio: float): progress.append({"id": utterance_id, "ratio": ratio}))
	bridge.speech_finished.connect(func(utterance_id: int): finished.append(utterance_id))
	var speak_result: Dictionary = bridge.speak({
		"text": "第一夜开始。",
		"voice": "zh-CN::voice_a",
		"speed": "0.90",
		"pitch": "1.00",
		"volume": "0.80",
		"interrupt": true,
	}, 12)
	assert(bool(speak_result.get("ok", false)))
	assert(plugin.speak_calls.size() == 1)
	assert(started.size() == 1 and int(started[0]) == 12)
	assert(progress.size() == 1 and int((progress[0] as Dictionary).get("id", 0)) == 12)
	assert(absf(float((progress[0] as Dictionary).get("ratio", 0.0)) - 0.5) < 0.01)
	assert(finished.size() == 1 and int(finished[0]) == 12)
	var external_speak_result: Dictionary = bridge.speak({
		"text": "外部播报测试。",
		"engine": "VoxSherpa-TTS",
		"voice": "zh-CN::voxsherpa_tts_female",
		"speed": "0.90",
		"pitch": "1.00",
		"volume": "1.00",
		"interrupt": true,
	}, 13)
	assert(bool(external_speak_result.get("ok", false)))
	assert(plugin.speak_calls.size() == 2)
	assert(String((plugin.speak_calls[1] as Dictionary).get("engine", "")) == "voxsherpa_tts")

	var runtime = load("res://scripts/core/tts/tts_runtime.gd").new()
	runtime.simulate_in_headless = false
	runtime.prefer_android_tts_bridge = true
	runtime._android_tts_bridge = bridge
	runtime._android_callbacks_bound = false
	runtime._bind_android_tts_callbacks()
	root.add_child(runtime)
	var runtime_finished: Array = []
	runtime.speech_finished.connect(func(item: Dictionary): runtime_finished.append(item))
	runtime.enqueue({
		"text": "系统播报测试。",
		"engine": "system",
		"voice": "zh-CN::voice_a",
		"speed": "0.90",
		"pitch": "1.00",
		"volume": "1.00",
		"interrupt": true,
	})
	assert(runtime_finished.size() == 1)
	assert(plugin.speak_calls.size() == 3)
	runtime.enqueue({
		"text": "本地播报测试。",
		"engine": "local_kokoro",
		"voice": "zf_001",
		"speed": "0.90",
		"pitch": "1.00",
		"volume": "1.00",
		"interrupt": true,
	})
	assert(runtime_finished.size() == 2)
	assert(plugin.speak_calls.size() == 4)
	assert(String((plugin.speak_calls[3] as Dictionary).get("engine", "")) == "local_kokoro")
	runtime.enqueue({
		"text": "外部播报测试。",
		"engine": "multi_tts",
		"voice": "",
		"speed": "0.90",
		"pitch": "1.00",
		"volume": "1.00",
		"interrupt": true,
	})
	assert(runtime_finished.size() == 3)
	assert(plugin.speak_calls.size() == 5)
	assert(String((plugin.speak_calls[4] as Dictionary).get("engine", "")) == "multi_tts")
	var runtime_debug: Dictionary = runtime.debug_snapshot()
	assert(bool(runtime_debug.get("ok", false)))
	assert(runtime_debug.has("android"))
	runtime.queue_free()

	var fallback_plugin := FakeTtsPlugin.new()
	fallback_plugin.system_voices = []
	root.add_child(fallback_plugin)
	var fallback_bridge := TestTtsBridge.new(fallback_plugin)
	var fallback_runtime = load("res://scripts/core/tts/tts_runtime.gd").new()
	fallback_runtime.simulate_in_headless = false
	fallback_runtime.prefer_android_tts_bridge = true
	fallback_runtime._android_tts_bridge = fallback_bridge
	fallback_runtime._android_callbacks_bound = false
	fallback_runtime._bind_android_tts_callbacks()
	root.add_child(fallback_runtime)
	var fallback_finished: Array = []
	fallback_runtime.speech_finished.connect(func(item: Dictionary): fallback_finished.append(item))
	fallback_runtime.enqueue({
		"text": "系统默认兜底播报。",
		"engine": "system",
		"voice": "",
		"speed": "0.90",
		"pitch": "1.00",
		"volume": "1.00",
		"interrupt": true,
	})
	assert(fallback_finished.size() == 1)
	assert(fallback_plugin.speak_calls.size() == 1)
	assert(String((fallback_plugin.speak_calls[0] as Dictionary).get("engine", "")) == "local_kokoro")
	assert(String((fallback_plugin.speak_calls[0] as Dictionary).get("voice", "")) == "zf_001")
	fallback_runtime.queue_free()
	quit()
