extends SceneTree

const StoreScript := preload("res://scripts/android/android_model_config_store.gd")


class FakeModelConfigPlugin:
	extends Node

	var models := []
	var next_id := 1

	func model_config_available() -> bool:
		return true

	func model_config_list() -> String:
		return JSON.stringify(models)

	func model_config_save(config_json: String) -> String:
		var config: Dictionary = JSON.parse_string(config_json)
		var id := int(config.get("id", 0))
		if id <= 0:
			id = next_id
			next_id += 1
		var model := String(config.get("model", "")).strip_edges()
		if model == "":
			model = String(config.get("name", "")).strip_edges()
		var item := {
			"id": id,
			"model": model,
			"provider": String(config.get("provider", "")),
			"endpoint": String(config.get("endpoint", "")),
			"api_key": String(config.get("api_key", "")),
			"context_window_tokens": int(config.get("context_window_tokens", 1)),
			"max_context": int(config.get("max_context", config.get("max_token", 262144))),
			"max_output": int(config.get("max_output", config.get("max_output_tokens", 4096))),
			"temperature": float(config.get("temperature", 0.6)),
			"reasoning": bool(config.get("reasoning", false)),
			"formt_adapter": String(config.get("formt_adapter", "auto")),
			"reason_adapter": String(config.get("reason_adapter", "auto")),
		}
		for i in range(models.size()):
			if int((models[i] as Dictionary).get("id", 0)) == id:
				models[i] = item
				return JSON.stringify({"ok": true, "model": item})
		models.append(item)
		return JSON.stringify({"ok": true, "model": item})

	func model_config_delete(id: int) -> String:
		for i in range(models.size() - 1, -1, -1):
			if int((models[i] as Dictionary).get("id", 0)) == id:
				models.remove_at(i)
		return JSON.stringify({"ok": true})


class TestModelConfigStore:
	extends StoreScript

	var plugin

	func _init(plugin_ref) -> void:
		plugin = plugin_ref

	func _plugin():
		return plugin


func _initialize() -> void:
	var plugin := FakeModelConfigPlugin.new()
	root.add_child(plugin)
	var store := TestModelConfigStore.new(plugin)
	assert(store.is_available())
	var saved := store.save_config({
		"model": "qwen2.5:7b",
		"provider": "ollama",
		"endpoint": "http://127.0.0.1:11434/api",
		"api_key": "",
		"context_window_tokens": 183501,
		"max_context": 262144,
		"max_output": 4096,
		"temperature": 0.7,
		"reasoning": true,
		"formt_adapter": "ollama_format_schema",
		"reason_adapter": "openai_reasoning_effort",
		"active": true,
	})
	assert(bool(saved.get("ok", false)))
	assert(int(saved.get("id", 0)) == 1)
	assert(String(saved.get("model", "")) == "qwen2.5:7b")
	assert(not saved.has("name"))
	assert(not saved.has("active"))
	var configs := store.list_configs()
	assert(configs.size() == 1)
	assert(int((configs[0] as Dictionary).get("context_window_tokens", 0)) == 183501)
	assert(int((configs[0] as Dictionary).get("max_context", 0)) == 262144)
	assert(int((configs[0] as Dictionary).get("max_output", 0)) == 4096)
	assert(bool((configs[0] as Dictionary).get("reasoning", false)))
	assert(String((configs[0] as Dictionary).get("formt_adapter", "")) == "ollama_format_schema")
	assert(String((configs[0] as Dictionary).get("reason_adapter", "")) == "openai_reasoning_effort")
	assert(bool(store.delete_config(1).get("ok", false)))
	assert(store.list_configs().is_empty())

	var blocked_auto := store.save_config({
		"model": "auto-blocked",
		"provider": "openai_api",
		"endpoint": "https://api.example/v1",
		"formt_adapter": "auto",
	})
	assert(not bool(blocked_auto.get("ok", false)))
	assert(String(blocked_auto.get("error", "")).contains("适配器"))

	var blocked_none := store.save_config({
		"model": "none-blocked",
		"provider": "openai_api",
		"endpoint": "https://api.example/v1",
		"formt_adapter": "none",
	})
	assert(not bool(blocked_none.get("ok", false)))
	var blocked_auto_reason := store.save_config({
		"model": "reason-auto-blocked",
		"provider": "openai_api",
		"endpoint": "https://api.example/v1",
		"formt_adapter": "openai_json_schema",
		"reasoning": true,
		"reason_adapter": "auto",
	})
	assert(not bool(blocked_auto_reason.get("ok", false)))
	var native_saved := store.save_config({
		"model": "native-ok",
		"provider": "openai_api",
		"endpoint": "https://api.example/v1",
		"formt_adapter": "openai_json_schema",
		"reasoning": false,
		"reason_adapter": "native",
	})
	assert(bool(native_saved.get("ok", false)))
	assert(String(native_saved.get("reason_adapter", "")) == "native")
	var deepseek_saved := store.save_config({
		"model": "deepseek-ok",
		"provider": "openai_api",
		"endpoint": "https://api.deepseek.com",
		"formt_adapter": "openai_json_object",
		"reasoning": false,
		"reason_adapter": "deepseek_thinking",
	})
	assert(bool(deepseek_saved.get("ok", false)))
	assert(String(deepseek_saved.get("reason_adapter", "")) == "deepseek_thinking")
	var ark_saved := store.save_config({
		"model": "doubao-ok",
		"provider": "openai_api",
		"endpoint": "https://ark.cn-beijing.volces.com/api/plan/v3",
		"formt_adapter": "openai_json_schema",
		"reasoning": false,
		"reason_adapter": "ark_thinking",
	})
	assert(bool(ark_saved.get("ok", false)))
	assert(String(ark_saved.get("reason_adapter", "")) == "ark_thinking")
	var minimax_saved := store.save_config({
		"model": "minimax-ok",
		"provider": "openai_api",
		"endpoint": "https://api.minimax.chat/v1",
		"formt_adapter": "openai_tool_optional",
		"reasoning": false,
		"reason_adapter": "minimax_reasoning_split",
	})
	assert(bool(minimax_saved.get("ok", false)))
	assert(String(minimax_saved.get("reason_adapter", "")) == "minimax_reasoning_split")
	assert(store.list_configs().size() == 4)
	quit()
