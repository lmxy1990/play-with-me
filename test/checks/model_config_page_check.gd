extends SceneTree

const CHECK_NAME := "model_config_page_check"
const WATCHDOG_SECONDS := 8.0

var _current_stage := "boot"
var _watchdog_version := 0


class FakeModelChatClient:
	extends RefCounted

	signal completed(request_id: int, ok: bool, content: String, error: String)
	signal diagnostic_ready(request_id: int, diagnostic: Dictionary)
	signal protocol_event(request_id: int, event: Dictionary)

	var next_request_id := 100
	var last_profile := {}
	var last_messages := []
	var last_temperature := -1.0
	var last_max_output_tokens := -1
	var last_timeout_sec := -1.0
	var last_options := {}
	var last_request := {}
	var requests := []
	var diagnostics := {}
	var completed_results := {}

	func complete_request(request: Dictionary) -> int:
		next_request_id += 1
		last_request = request.duplicate(true)
		requests.append(last_request)
		last_profile = {
			"provider": String(request.get("provider", "")),
			"endpoint": String(request.get("endpoint", "")),
			"api_key": String(request.get("api_key", "")),
			"model": String(request.get("model", "")),
			"output_adapter": String(request.get("output_adapter", "")),
			"reason_adapter": String(request.get("reason_adapter", "")),
			"reasoning_mode": String(request.get("reasoning_mode", "")),
			"connection_test": bool(request.get("connection_test", false)),
		}
		last_messages = (request.get("messages", []) as Array).duplicate(true)
		last_temperature = float(request.get("temperature", -1.0))
		last_max_output_tokens = int(request.get("max_output_tokens", -1))
		last_timeout_sec = float(request.get("timeout_sec", -1.0))
		last_options = (request.get("options", {}) as Dictionary).duplicate(true)
		if request.has("response_schema"):
			last_options["response_schema"] = (request.get("response_schema", {}) as Dictionary).duplicate(true)
		return next_request_id

	func complete(profile: Dictionary, messages: Array, temperature: float = 0.7, max_output_tokens: int = 0, timeout_sec: float = 30.0, options: Dictionary = {}) -> int:
		next_request_id += 1
		last_profile = profile.duplicate(true)
		last_messages = messages.duplicate(true)
		last_temperature = temperature
		last_max_output_tokens = max_output_tokens
		last_timeout_sec = timeout_sec
		last_options = options.duplicate(true)
		return next_request_id

	func take_completed_diagnostic(request_id: int) -> Dictionary:
		if not diagnostics.has(request_id):
			return {}
		var item: Dictionary = diagnostics[request_id]
		diagnostics.erase(request_id)
		return item.duplicate(true)

	func take_completed_result(request_id: int) -> Dictionary:
		if not completed_results.has(request_id):
			return {}
		var item: Dictionary = completed_results[request_id]
		completed_results.erase(request_id)
		return item.duplicate(true)


class FakeUnavailableModelConfigStore:
	extends RefCounted

	func backend_attached() -> bool:
		return true

	func is_available() -> bool:
		return false

	func save_config(_config: Dictionary) -> Dictionary:
		return {"ok": false, "error": "should not save"}

	func list_configs() -> Array:
		return []


func _initialize() -> void:
	_setup_watchdog()
	_checkpoint("state_setup")
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.model_configs = []
	state.bot_profiles = []

	_checkpoint("page_setup")
	var packed := load("res://scenes/model_config.tscn") as PackedScene
	var page := packed.instantiate() as Control
	page.set_app_state(state)
	root.add_child(page)
	await process_frame

	_checkpoint("schema_fallback")
	var fake_client := FakeModelChatClient.new()
	page._model_chat_client = fake_client
	page._test_model_config("openai_api", "http://localhost/v1", "sk-test", "qwen:test", false, null)
	assert(String(fake_client.last_request.get("purpose", "")) == "model_config.connection_test")
	assert(String(fake_client.last_request.get("provider", "")) == "openai_api")
	assert(String(fake_client.last_request.get("endpoint", "")) == "http://localhost/v1")
	assert(String(fake_client.last_request.get("model", "")) == "qwen:test")
	assert(String(fake_client.last_request.get("output_type", "")) == "json")
	assert(String(fake_client.last_request.get("output_adapter", "")) == "openai_json_schema")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "auto")
	assert(fake_client.last_options.has("response_schema"))
	assert(String(fake_client.last_options.get("output_adapter", "")) == "openai_json_schema")
	assert(int(fake_client.last_max_output_tokens) == 512)
	assert(String((fake_client.last_messages[0] as Dictionary).get("content", "")).contains("schema_check"))
	var response_schema: Dictionary = fake_client.last_options["response_schema"] as Dictionary
	assert(String(response_schema.get("name", "")) == "model_action_schema_test_v1")
	var schema_body: Dictionary = response_schema["schema"] as Dictionary
	assert(((schema_body["properties"] as Dictionary).get("action", {}) as Dictionary).get("enum", []) == ["schema_check"])
	assert(((schema_body["properties"] as Dictionary).get("targetSeatNumber", {}) as Dictionary).get("enum", []) == [1])

	var client = load("res://scripts/core/model/model_chat_client.gd").new()
	var payload: Dictionary = client._payload("openai", "qwen:test", fake_client.last_messages, 0.0, false, 512, fake_client.last_options)
	assert(String((payload["response_format"] as Dictionary).get("type", "")) == "json_schema")

	fake_client.completed.emit(fake_client.next_request_id, true, "not-json", "")
	assert(String(fake_client.last_request.get("output_adapter", "")) == "openai_json_object")
	var test_item: Dictionary = page._model_config_item(0, "qwen:test", "openai_api", "http://localhost/v1", "sk-test", 8192, 262144, 4096, 0.6, false, "openai_json_object", "native")
	assert(not page._model_schema_test_passed_for_item(test_item))
	assert(not page._model_schema_test_response_valid("OK"))
	assert(not page._model_schema_test_response_valid("{\"target\":1}"))
	assert(page._model_schema_test_error("{\"target\":1}") == "schema 校验失败：缺少 action")
	assert(page._model_schema_test_response_valid("{\"action\":\"schema_check\",\"targetSeatNumber\":1}"))
	assert(not page._model_schema_test_response_valid("{\"action\":\"schema_check\",\"targetSeatNumber\":\"1\"}"))
	assert(not page._model_schema_test_response_valid("{\"action\":\"schema_check\",\"targetSeatNumber\":1.5}"))
	assert(not page._model_schema_test_response_valid("{\"action\":\"schema_check\",\"targetSeatNumber\":1,\"extra\":\"ignored\"}"))
	assert(page._model_schema_test_error("{\"action\":\"schema_check\",\"targetSeatNumber\":1,\"extra\":\"ignored\"}") == "schema 校验失败：包含多余字段")

	_checkpoint("schema_text_reasoning_base")
	var success_request_id := fake_client.next_request_id
	fake_client.completed_results[success_request_id] = {
		"ok": true,
		"text": "{\"action\":\"schema_check\",\"targetSeatNumber\":1}",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(success_request_id, true, "{\"action\":\"schema_check\",\"targetSeatNumber\":1}", "")
	assert(String(fake_client.last_request.get("purpose", "")) == "model_config.text_test")
	var text_request_id := fake_client.next_request_id
	fake_client.completed_results[text_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(text_request_id, true, "ok", "")
	var no_reasoning_request_id := fake_client.next_request_id
	fake_client.completed_results[no_reasoning_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(no_reasoning_request_id, true, "ok", "")
	assert(page._model_schema_test_passed_for_item(test_item))

	_checkpoint("save_guards")
	page._model_schema_test_passes.clear()
	page._save_model_config(-1, "qwen:new", "openai_api", "http://localhost/v1", "", "sk-test", 8192, 262144, 4096, 0.6, false)
	assert(_find_model_index(page, "qwen:new") < 0)

	var new_item: Dictionary = page._model_config_item(0, "qwen:new", "openai_api", "http://localhost/v1", "sk-test", 8192, 262144, 4096, 0.6, false, "openai_json_schema", "native")
	page._model_test_capabilities[page._model_test_capability_key("openai_api", "http://localhost/v1", "sk-test", "qwen:new", false, "openai_json_schema", "native")] = {"compatible": true}
	page._save_model_config(-1, "qwen:new", "openai_api", "http://localhost/v1", "", "sk-test", 8192, 262144, 4096, 0.6, false, "openai_json_schema", "native")
	assert(page._model_schema_test_passed_for_item(new_item))
	var delete_index := _find_model_index(page, "qwen:new")
	assert(delete_index >= 0)

	_checkpoint("reasoning_openai")
	page._test_model_config("openai_api", "http://localhost/v1", "sk-test", "qwen:reasoning", true, null, "auto", null, "openai_reasoning_effort", null)
	var schema_reasoning_request_id := fake_client.next_request_id
	fake_client.completed_results[schema_reasoning_request_id] = {
		"ok": true,
		"text": "{\"action\":\"schema_check\",\"targetSeatNumber\":1}",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(schema_reasoning_request_id, true, "{\"action\":\"schema_check\",\"targetSeatNumber\":1}", "")
	var text_reasoning_request_id := fake_client.next_request_id
	fake_client.completed_results[text_reasoning_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(text_reasoning_request_id, true, "ok", "")
	var reasoning_request_id := fake_client.next_request_id
	fake_client.completed_results[reasoning_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.protocol_event.emit(reasoning_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "thinking",
	})
	fake_client.completed.emit(reasoning_request_id, true, "ok", "")
	var reasoning_item: Dictionary = page._model_config_item(0, "qwen:reasoning", "openai_api", "http://localhost/v1", "sk-test", 8192, 262144, 4096, 0.6, true, "openai_json_schema", "openai_reasoning_effort")
	assert(page._model_schema_test_passed_for_item(reasoning_item))
	assert(String(page._model_detected_reason_adapter("openai_api", "http://localhost/v1", "sk-test", "qwen:reasoning", true)) == "openai_reasoning_effort")

	_checkpoint("reasoning_kimi")
	page._test_model_config("openai_api", "http://localhost/v1", "sk-test", "kimi-k2.6", true, null, "auto", null, "auto", null)
	var kimi_schema_request_id := fake_client.next_request_id
	fake_client.completed_results[kimi_schema_request_id] = {
		"ok": true,
		"text": "{\"action\":\"schema_check\",\"targetSeatNumber\":1}",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(kimi_schema_request_id, true, "{\"action\":\"schema_check\",\"targetSeatNumber\":1}", "")
	var kimi_text_request_id := fake_client.next_request_id
	fake_client.completed_results[kimi_text_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(kimi_text_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "kimi_thinking_control")
	var kimi_reasoning_request_id := fake_client.next_request_id
	fake_client.completed_results[kimi_reasoning_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.protocol_event.emit(kimi_reasoning_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "kimi-thinking",
	})
	fake_client.completed.emit(kimi_reasoning_request_id, true, "ok", "")
	assert(String(page._model_detected_reason_adapter("openai_api", "http://localhost/v1", "sk-test", "kimi-k2.6", true)) == "kimi_thinking_control")

	_checkpoint("reasoning_glm")
	page._test_model_config("openai_api", "http://localhost/v1", "sk-test", "glm-5.1", false, null, "auto", null, "auto", null)
	var glm_schema_request_id := fake_client.next_request_id
	fake_client.completed_results[glm_schema_request_id] = {
		"ok": true,
		"text": "{\"action\":\"schema_check\",\"targetSeatNumber\":1}",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(glm_schema_request_id, true, "{\"action\":\"schema_check\",\"targetSeatNumber\":1}", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "glm_thinking")
	var glm_text_request_id := fake_client.next_request_id
	fake_client.completed_results[glm_text_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(glm_text_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "native")
	var glm_reason_native_fail_request_id := fake_client.next_request_id
	fake_client.completed_results[glm_reason_native_fail_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": true,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.protocol_event.emit(glm_reason_native_fail_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "glm-thinking",
	})
	fake_client.completed.emit(glm_reason_native_fail_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "glm_thinking")
	var glm_reason_success_request_id := fake_client.next_request_id
	fake_client.completed_results[glm_reason_success_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(glm_reason_success_request_id, true, "ok", "")
	await process_frame
	assert(String(page._model_detected_reason_adapter("openai_api", "http://localhost/v1", "sk-test", "glm-5.1", false)) == "glm_thinking")

	_checkpoint("reasoning_doubao")
	page._test_model_config("openai_api", "http://localhost/v1", "sk-test", "doubao-seed-2.0-pro", false, null, "auto", null, "auto", null)
	var doubao_schema_request_id := fake_client.next_request_id
	fake_client.completed_results[doubao_schema_request_id] = {
		"ok": true,
		"text": "{\"action\":\"schema_check\",\"targetSeatNumber\":1}",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(doubao_schema_request_id, true, "{\"action\":\"schema_check\",\"targetSeatNumber\":1}", "")
	var doubao_text_request_id := fake_client.next_request_id
	fake_client.completed_results[doubao_text_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(doubao_text_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "native")
	var doubao_reason_native_fail_request_id := fake_client.next_request_id
	fake_client.completed_results[doubao_reason_native_fail_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": true,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.protocol_event.emit(doubao_reason_native_fail_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "doubao-thinking",
	})
	fake_client.completed.emit(doubao_reason_native_fail_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "ark_thinking")
	var doubao_reason_success_request_id := fake_client.next_request_id
	fake_client.completed_results[doubao_reason_success_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(doubao_reason_success_request_id, true, "ok", "")
	assert(String(page._model_detected_reason_adapter("openai_api", "http://localhost/v1", "sk-test", "doubao-seed-2.0-pro", false)) == "ark_thinking")

	_checkpoint("reasoning_generic_off")
	page._test_model_config("openai_api", "http://localhost/v1", "sk-test", "qwen:no-reasoning", false, null, "auto", null, "auto", null)
	var no_reason_schema_request_id := fake_client.next_request_id
	fake_client.completed_results[no_reason_schema_request_id] = {
		"ok": true,
		"text": "{\"action\":\"schema_check\",\"targetSeatNumber\":1}",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(no_reason_schema_request_id, true, "{\"action\":\"schema_check\",\"targetSeatNumber\":1}", "")
	var no_reason_text_request_id := fake_client.next_request_id
	fake_client.completed_results[no_reason_text_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(no_reason_text_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "native")
	var no_reason_fail_request_id := fake_client.next_request_id
	fake_client.completed_results[no_reason_fail_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": true,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.protocol_event.emit(no_reason_fail_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "should-not-exist",
	})
	fake_client.completed.emit(no_reason_fail_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "deepseek_thinking")
	var no_reason_second_fail_request_id := fake_client.next_request_id
	fake_client.completed_results[no_reason_second_fail_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": true,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.protocol_event.emit(no_reason_second_fail_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "still-wrong",
	})
	fake_client.completed.emit(no_reason_second_fail_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "ark_thinking")
	var no_reason_third_fail_request_id := fake_client.next_request_id
	fake_client.completed_results[no_reason_third_fail_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": true,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.protocol_event.emit(no_reason_third_fail_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "wrong-again",
	})
	fake_client.completed.emit(no_reason_third_fail_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "minimax_reasoning_split")
	var no_reason_minimax_request_id := fake_client.next_request_id
	fake_client.completed_results[no_reason_minimax_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": true,
			"has_stream_output": false,
			"parse_ok": true,
			"reasoning_output": "split thinking",
		},
	}
	fake_client.protocol_event.emit(no_reason_minimax_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "split thinking",
	})
	fake_client.completed.emit(no_reason_minimax_request_id, true, "ok", "")
	await process_frame
	print("[model_config_page_check] qwen:no-reasoning detected=%s" % String(page._model_detected_reason_adapter("openai_api", "http://localhost/v1", "sk-test", "qwen:no-reasoning", false)))
	assert(String(page._model_detected_reason_adapter("openai_api", "http://localhost/v1", "sk-test", "qwen:no-reasoning", false)) == "minimax_reasoning_split")

	_checkpoint("reasoning_minimax")
	page._test_model_config("openai_api", "http://localhost/v1", "sk-test", "minimax-m2.7", false, null, "auto", null, "auto", null)
	var minimax_schema_request_id := fake_client.next_request_id
	fake_client.completed_results[minimax_schema_request_id] = {
		"ok": true,
		"text": "{\"action\":\"schema_check\",\"targetSeatNumber\":1}",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(minimax_schema_request_id, true, "{\"action\":\"schema_check\",\"targetSeatNumber\":1}", "")
	var minimax_text_request_id := fake_client.next_request_id
	fake_client.completed_results[minimax_text_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": false,
			"has_stream_output": false,
			"parse_ok": true,
		},
	}
	fake_client.completed.emit(minimax_text_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "native")
	var minimax_native_reason_request_id := fake_client.next_request_id
	fake_client.completed_results[minimax_native_reason_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": true,
			"has_stream_output": false,
			"parse_ok": true,
			"reasoning_output": "unsplit thinking",
		},
	}
	fake_client.protocol_event.emit(minimax_native_reason_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "unsplit thinking",
	})
	fake_client.completed.emit(minimax_native_reason_request_id, true, "ok", "")
	assert(String(fake_client.last_request.get("reason_adapter", "")) == "minimax_reasoning_split")
	var minimax_split_reason_request_id := fake_client.next_request_id
	fake_client.completed_results[minimax_split_reason_request_id] = {
		"ok": true,
		"text": "ok",
		"error": "",
		"diagnostic": {
			"has_text_output": true,
			"has_reasoning_output": true,
			"has_stream_output": false,
			"parse_ok": true,
			"reasoning_output": "split thinking",
		},
	}
	fake_client.protocol_event.emit(minimax_split_reason_request_id, {
		"type": "chunk",
		"kind": "reasoning",
		"text": "split thinking",
	})
	fake_client.completed.emit(minimax_split_reason_request_id, true, "ok", "")
	await process_frame
	assert(String(page._model_detected_reason_adapter("openai_api", "http://localhost/v1", "sk-test", "minimax-m2.7", false)) == "minimax_reasoning_split")

	_checkpoint("delete_guard_and_options")
	page._bot_profiles = [
		{"id": "bot_model_user", "name": "模型用户", "model": "qwen:new", "voice": "系统默认", "enabled": true},
	]
	page._delete_model_config(delete_index)
	assert(_find_model_index(page, "qwen:new") >= 0)

	page._bot_profiles = []
	page._delete_model_config(delete_index)
	assert(_find_model_index(page, "qwen:new") < 0)

	var model_line := LineEdit.new()
	model_line.text = "qwen:auto-refresh"
	var endpoint_line := LineEdit.new()
	endpoint_line.text = "http://localhost/v1"
	var api_key_line := LineEdit.new()
	api_key_line.text = "sk-test"
	var provider_option: OptionButton = page._book_provider_dropdown("openai_api") as OptionButton
	var reasoning_checkbox := CheckBox.new()
	reasoning_checkbox.button_pressed = false
	var adapter_option: OptionButton = page._book_formt_adapter_dropdown("openai_api", "auto") as OptionButton
	var reason_adapter_option: OptionButton = page._book_reason_adapter_dropdown("openai_api", "auto", "qwen:auto-refresh", false) as OptionButton
	var openai_native_reason_option: OptionButton = page._book_reason_adapter_dropdown("openai_api", "native", "qwen:auto-refresh", false) as OptionButton
	var gemini_native_reason_option: OptionButton = page._book_reason_adapter_dropdown("gemini", "native", "gemini-1.5-flash", false) as OptionButton
	assert(_option_has_metadata(adapter_option, "openai_json_schema"))
	assert(_option_has_metadata(adapter_option, "openai_json_object"))
	assert(_option_has_metadata(adapter_option, "openai_tool_forced"))
	assert(_option_has_metadata(adapter_option, "openai_tool_optional"))
	assert(_option_has_metadata(adapter_option, "openai_mimo_tool"))
	assert(_option_has_metadata(reason_adapter_option, "openai_reasoning_effort"))
	assert(_option_has_metadata(reason_adapter_option, "glm_thinking"))
	assert(_option_has_metadata(reason_adapter_option, "ark_thinking"))
	assert(_option_has_metadata(reason_adapter_option, "minimax_reasoning_split"))
	assert(_option_has_metadata(reason_adapter_option, "mimo_chat_template"))
	assert(_option_has_metadata(reason_adapter_option, "kimi_thinking_control"))
	assert(_option_has_metadata(reason_adapter_option, "native"))
	assert(openai_native_reason_option.get_item_text(openai_native_reason_option.selected) == "openai")
	assert(gemini_native_reason_option.get_item_text(gemini_native_reason_option.selected) == "gemini")
	var test_button := Button.new()
	var save_button := Button.new()
	test_button.set_meta("save_button", save_button)
	test_button.set_meta("provider_option", provider_option)
	test_button.set_meta("endpoint_line", endpoint_line)
	test_button.set_meta("api_key_line", api_key_line)
	test_button.set_meta("model_line", model_line)
	test_button.set_meta("reasoning_checkbox", reasoning_checkbox)
	test_button.set_meta("formt_adapter_option", adapter_option)
	test_button.set_meta("reason_adapter_option", reason_adapter_option)
	test_button.set_meta("edit_index", -1)
	model_line.text = "qwen:auto-refresh"
	endpoint_line.text = "http://localhost/v1"
	api_key_line.text = "sk-test"
	page._update_model_editor_save_state(save_button, -1, model_line.text, "openai_api", endpoint_line.text, api_key_line.text, false, "auto", "auto")
	assert(save_button.disabled)
	var auto_refresh_base_key: String = String(page._model_schema_test_base_key("openai_api", endpoint_line.text, api_key_line.text, model_line.text, false))
	page._model_detected_formt_adapters[auto_refresh_base_key] = "openai_json_schema"
	page._model_detected_reason_adapters[auto_refresh_base_key] = "native"
	page._model_test_capabilities[page._model_test_capability_key("openai_api", endpoint_line.text, api_key_line.text, model_line.text, false, "openai_json_schema", "native")] = {"compatible": true}
	page._refresh_model_editor_save_state_from_test_button(test_button)
	assert(not save_button.disabled)
	page._apply_detected_model_adapters_to_test_button(test_button)
	assert(String(page._formt_adapter_selected(adapter_option)) == "openai_json_schema")
	assert(String(page._reason_adapter_selected(reason_adapter_option)) == "native")
	page._select_formt_adapter(adapter_option, "auto")
	page._select_reason_adapter(reason_adapter_option, "auto")
	page._update_model_editor_save_state(save_button, -1, model_line.text, "openai_api", endpoint_line.text, api_key_line.text, false, page._formt_adapter_selected(adapter_option), page._reason_adapter_selected(reason_adapter_option))
	assert(String(page._formt_adapter_selected(adapter_option)) == "auto")
	assert(String(page._reason_adapter_selected(reason_adapter_option)) == "auto")
	assert(not save_button.disabled)
	var unavailable_store := FakeUnavailableModelConfigStore.new()
	page._model_config_store = unavailable_store
	page._app_state.persistence_enabled = true
	var persisted_count_before: int = page._model_configs.size()
	var blocked_item: Dictionary = page._model_config_item(999, "persist-blocked", "openai_api", "https://api.example/v1", "sk-test", 183501, 262144, 4096, 0.6, false, "openai_json_schema", "native")
	assert(not page._save_model_config_item(-1, blocked_item, false))
	assert(page._model_configs.size() == persisted_count_before)

	_checkpoint("cleanup")
	model_line.free()
	endpoint_line.free()
	api_key_line.free()
	provider_option.free()
	reasoning_checkbox.free()
	adapter_option.free()
	reason_adapter_option.free()
	openai_native_reason_option.free()
	gemini_native_reason_option.free()
	test_button.free()
	save_button.free()

	page.call("_clear_scene")
	root.remove_child(page)
	page.free()
	await process_frame
	await process_frame
	_checkpoint("done")
	quit()


func _find_model_index(page: Control, model_name: String) -> int:
	for i in range(page._model_configs.size()):
		if page._model_configs[i] is Dictionary and String((page._model_configs[i] as Dictionary).get("model", "")) == model_name:
			return i
	return -1


func _option_has_metadata(option: OptionButton, expected: String) -> bool:
	for i in range(option.get_item_count()):
		if String(option.get_item_metadata(i)) == expected:
			return true
	return false


func _setup_watchdog() -> void:
	print("[%s] watchdog armed %.1fs" % [CHECK_NAME, WATCHDOG_SECONDS])
	_rearm_watchdog()


func _checkpoint(stage: String) -> void:
	_current_stage = stage
	print("[%s] stage=%s" % [CHECK_NAME, stage])
	_rearm_watchdog()


func _rearm_watchdog() -> void:
	_watchdog_version += 1
	var expected_version := _watchdog_version
	var timer := create_timer(WATCHDOG_SECONDS)
	timer.timeout.connect(func():
		if expected_version != _watchdog_version:
			return
		_on_watchdog_timeout()
	)


func _on_watchdog_timeout() -> void:
	push_error("[%s] timeout at stage=%s after %.1fs" % [CHECK_NAME, _current_stage, WATCHDOG_SECONDS])
	quit(1)
