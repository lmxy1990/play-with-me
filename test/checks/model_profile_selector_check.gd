extends SceneTree

const SelectorScript := preload("res://scripts/core/model/model_profile_selector.gd")


func _initialize() -> void:
	var selector = SelectorScript.new()
	var configs := [
		{"model": "", "endpoint": "http://localhost"},
		{"model": "qwen", "endpoint": "http://localhost:11434", "temperature": 3.0, "max_context": 0, "max_output": 0, "context_window_tokens": 0},
		{"model": "deepseek", "endpoint": "https://api.example/v1", "temperature": -1.0, "max_context": 262144, "max_output": 4096, "context_window_tokens": 183501, "reasoning": true, "formt_adapter": "openai_json_object", "reason_adapter": "openai_reasoning_effort"},
	]
	var selected: Dictionary = selector.profile_for_player({"model": "deepseek"}, configs)
	assert(String(selected.get("model", "")) == "deepseek")
	assert(not selected.has("name"))
	assert(float(selected.get("temperature", 0.5)) == 0.0)
	assert(int(selected.get("max_context", 0)) == 262144)
	assert(int(selected.get("max_output", 0)) == 4096)
	assert(int(selected.get("context_window_tokens", 0)) == 183501)
	assert(bool(selected.get("reasoning", false)))
	assert(String(selected.get("formt_adapter", "")) == "openai_json_object")
	assert(String(selected.get("reason_adapter", "")) == "openai_reasoning_effort")
	var selected_by_name: Dictionary = selector.profile_for_model_name("deepseek", configs)
	assert(String(selected_by_name.get("model", "")) == "deepseek")
	var missing_model: Dictionary = selector.profile_for_player({"model": "不存在"}, configs)
	assert(missing_model.is_empty())
	assert(selector.profile_for_model_name("", configs).is_empty())
	assert(selector.usable_profile({"model": "", "endpoint": "x"}).is_empty())
	assert(selector.usable_profile({"model": "x", "endpoint": ""}).is_empty())
	assert(float(selector.temperature({}, 0.7)) == 0.7)
	assert(int(selector.max_token({}, 128)) == 128)
	assert(int(selector.max_output({}, 4096)) == 4096)
	quit()
