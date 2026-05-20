extends SceneTree


func _initialize() -> void:
	var sanitizer = load("res://scripts/core/tts/tts_text_sanitizer.gd").new()
	assert(sanitizer.sanitize("系统旁白：第12夜开始。") == "第十二夜开始。")
	assert(sanitizer.sanitize("机器人1: vote 2号，OK。", "机器人1") == "vote 二号，OK。")
	assert(sanitizer.sanitize("Hello AI.") == "Hello AI。")
	var voices: Array = sanitizer.kokoro_voices()
	assert(voices.size() > 80)
	assert(String(voices[0]["id"]) == "zf_001")
	assert(String(voices[0]["gender"]) == "女声")
	quit()
