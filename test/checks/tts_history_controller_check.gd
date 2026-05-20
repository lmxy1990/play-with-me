extends SceneTree


class FakeRuntime:
	extends RefCounted

	var enqueued: Array = []

	func enqueue(item: Dictionary) -> void:
		enqueued.append(item.duplicate(true))


func _initialize() -> void:
	var controller = load("res://scripts/core/tts/tts_history_controller.gd").new()
	assert(controller.normalize_engine("系统TTS") == "system")
	assert(controller.normalize_engine("kokoro") == "local_kokoro")
	assert(controller.normalize_engine("NekoTTS") == "neko_tts")
	assert(controller.normalize_engine("NekoSpeak") == "neko_tts")
	assert(controller.normalize_engine("VoxSherpa-TTS") == "voxsherpa_tts")
	assert(controller.normalize_engine("MultiTTS") == "multi_tts")
	assert(controller.normalize_engine("tts_server_android") == "multi_tts")
	assert(controller.speaker_index_for_history("2号 阿辰", 6) == 1)
	assert(controller.speaker_index_for_history("主持人", 6) == -1)

	var configs := [
		{"name": "停用", "engine": "system", "voice": "zh-CN::off", "enabled": false, "active": true},
		{"name": "启用", "engine": "kokoro", "voice": "zf_001", "speed": "0.90", "pitch": "1.00", "volume": "0.80", "enabled": true, "active": false},
	]
	var migrated_default: Dictionary = controller.playback_voice_config([
		{"key": "voice_system_default", "name": "系统默认", "engine": "system", "voice": "", "enabled": true, "active": true},
	], "voice_system_default")
	assert(String(migrated_default.get("engine", "")) == "local_kokoro")
	assert(String(migrated_default.get("voice", "")) == "zf_001")
	var disabled_runtime := FakeRuntime.new()
	var disabled_result: Dictionary = controller.queue_history_item(
		{"speaker": "1号 阿明", "text": "1号 阿明：今晚查验2号。"},
		configs,
		disabled_runtime,
		6
	)
	assert(not disabled_result.is_empty())
	assert(String(disabled_result.get("engine", "")) == "local_kokoro")
	assert(disabled_runtime.enqueued.size() == 1)

	configs[0]["active"] = false
	configs[1]["active"] = true
	var runtime := FakeRuntime.new()
	var item: Dictionary = controller.queue_history_item(
		{"speaker": "1号 阿明", "text": "1号 阿明：今晚查验2号。"},
		configs,
		runtime,
		6
	)
	assert(not item.is_empty())
	assert(String(item.get("engine", "")) == "local_kokoro")
	assert(String(item.get("voice", "")) == "zf_001")
	assert(int(item.get("speaker_index", -1)) == 0)
	assert(String(item.get("text", "")).contains("二号"))
	assert(runtime.enqueued.size() == 1)

	var selected_runtime := FakeRuntime.new()
	var selected_item: Dictionary = controller.queue_history_item(
		{"speaker": "3号 阿蓝", "text": "3号 阿蓝：我先听后置位。"},
		[
			{"id": 1, "key": "voice_config_1", "name": "主用", "engine": "system", "voice": "zh-CN::main", "enabled": true, "active": true},
			{"id": 2, "key": "voice_config_2", "name": "播放", "engine": "kokoro", "voice": "zf_009", "enabled": true, "active": false},
		],
		selected_runtime,
		6,
		"voice_config_2"
	)
	assert(String(selected_item.get("engine", "")) == "local_kokoro")
	assert(String(selected_item.get("voice", "")) == "zf_009")
	assert(selected_runtime.enqueued.size() == 1)

	for i in range(40):
		controller.queue_history_item(
			{"speaker": "主持人", "text": "第%d夜开始。" % [i + 1]},
			configs,
			null,
			6
		)
	assert(controller.queue_snapshot().size() == 32)
	quit()
