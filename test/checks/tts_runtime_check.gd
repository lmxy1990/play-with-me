extends SceneTree


func _initialize() -> void:
	var runtime = load("res://scripts/core/tts/tts_runtime.gd").new()
	runtime.simulate_in_headless = true
	root.add_child(runtime)
	var flags := {
		"started": false,
		"finished": false,
		"progress_seen": false,
	}
	runtime.speech_started.connect(func(_item: Dictionary) -> void:
		flags["started"] = true
	)
	runtime.speech_progress.connect(func(_item: Dictionary, ratio: float) -> void:
		if ratio > 0.0:
			flags["progress_seen"] = true
	)
	runtime.speech_finished.connect(func(_item: Dictionary) -> void:
		flags["finished"] = true
	)
	var invalid: Dictionary = runtime.validate_item({
		"text": "第一夜开始。",
		"engine": "system",
		"voice": "",
	})
	assert(not bool(invalid.get("ok", false)))
	var local_valid: Dictionary = runtime.validate_item({
		"text": "第一夜开始。",
		"engine": "local_kokoro",
		"voice": "zf_001",
	})
	assert(bool(local_valid.get("ok", false)))
	var removed_local_id: Dictionary = runtime.validate_item({
		"text": "第一夜开始。",
		"engine": "local_kokoro",
		"voice": "kokoro::0",
	})
	assert(not bool(removed_local_id.get("ok", false)))
	var local_invalid: Dictionary = runtime.validate_item({
		"text": "第一夜开始。",
		"engine": "local_kokoro",
		"voice": "missing",
	})
	assert(not bool(local_invalid.get("ok", false)))
	var external_valid: Dictionary = runtime.validate_item({
		"text": "第一夜开始。",
		"engine": "VoxSherpa-TTS",
		"voice": "",
	})
	assert(bool(external_valid.get("ok", false)))
	var configured: Dictionary = runtime.configure_voice_configs([
		{"engine": "kokoro", "enabled": true},
		{"engine": "local_kokoro", "enabled": true},
		{"engine": "system", "enabled": false},
	])
	assert(bool(configured.get("ok", false)))
	assert((configured.get("engines", []) as Array).size() == 1)
	assert(String(((configured.get("engines", []) as Array)[0])) == "local_kokoro")
	var configured_external: Dictionary = runtime.configure_voice_configs([
		{"engine": "NekoTTS", "enabled": true},
		{"engine": "NekoSpeak", "enabled": true},
		{"engine": "MultiTTS", "enabled": true},
		{"engine": "tts_server_android", "enabled": true},
		{"engine": "system", "enabled": false},
	])
	assert(bool(configured_external.get("ok", false)))
	assert((configured_external.get("engines", []) as Array).size() == 2)
	assert(String(((configured_external.get("engines", []) as Array)[0])) == "neko_tts")
	assert(String(((configured_external.get("engines", []) as Array)[1])) == "multi_tts")
	runtime.enqueue({
		"speaker": "主持人",
		"text": "第一夜开始。",
		"engine": "system",
		"voice": "manual_voice",
		"speed": "1.00",
		"pitch": "1.00",
		"volume": "1.00",
	})
	for _i in range(40):
		runtime.tick(0.1)
	assert(bool(flags["started"]))
	assert(bool(flags["progress_seen"]))
	assert(bool(flags["finished"]))

	var android_runtime = load("res://scripts/core/tts/tts_runtime.gd").new()
	android_runtime.simulate_in_headless = true
	root.add_child(android_runtime)
	var android_flags := {
		"finished": false,
		"failed": false,
	}
	android_runtime.speech_finished.connect(func(_item: Dictionary) -> void:
		android_flags["finished"] = true
	)
	android_runtime.speech_failed.connect(func(_item: Dictionary, _error: String) -> void:
		android_flags["failed"] = true
	)
	android_runtime._current = {
		"speaker": "主持人",
		"text": "Android 已经返回播放进度时，不能再按估算时长提前完成。",
		"engine": "neko_tts",
		"voice": "zm_034",
	}
	android_runtime._current_utterance_id = 77
	android_runtime._duration = 1.0
	android_runtime._native_active = true
	android_runtime._native_source = "android"
	android_runtime._on_android_tts_progress(77, 0.3)
	android_runtime.tick(20.0)
	assert(android_runtime.is_speaking())
	assert(not bool(android_flags["finished"]))
	assert(not bool(android_flags["failed"]))
	android_runtime.queue_free()
	runtime.queue_free()
	quit()
