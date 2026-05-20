extends SceneTree

const CHECK_NAME := "model_chat_client_check"
const WATCHDOG_SECONDS := 8.0

var _current_stage := "boot"
var _watchdog_version := 0


func _initialize() -> void:
	_setup_watchdog()
	_checkpoint("basic_payloads")
	var client = load("res://scripts/core/model/model_chat_client.gd").new()
	assert(client._chat_url("ollama", "http://127.0.0.1:11434") == "http://127.0.0.1:11434/api/chat")
	assert(client._chat_url("ollama", "http://127.0.0.1:11434/api") == "http://127.0.0.1:11434/api/chat")
	assert(client._chat_url("openai", "https://api.example.local/v1") == "https://api.example.local/v1/chat/completions")
	assert(client._chat_url("openai", "https://api.example.local/v1/models") == "https://api.example.local/v1/chat/completions")
	assert(client._endpoint_hint("openai", "https://api.example.local/chat/completions", "<!doctype html><title>Gateway</title>") == "BaseUrl 可能缺少 /v1；")
	assert(client._endpoint_hint("openai", "https://api.example.local/v1/chat/completions", "<!doctype html>") == "")
	assert(client._request_result_label(HTTPRequest.RESULT_TIMEOUT) == "RESULT_TIMEOUT")
	assert(client._request_result_error(HTTPRequest.RESULT_TIMEOUT, "https://api.example.local/v1/chat/completions") == "模型请求失败：请求超时(RESULT_TIMEOUT/13) url=https://api.example.local/v1/chat/completions")
	assert(client._model_family_matches("deepseek-v4-flash", "deepseek"))
	assert(client._model_family_matches("vendor/glm-5.1", "glm"))
	assert(client._model_family_matches("glm5.1", "glm"))
	assert(client._model_family_matches("minimax-m2.7", "minimax"))
	assert(client._model_family_matches("mimo-v2", "mimo"))
	assert(client._model_family_matches("kimi-k2.6", "kimi"))
	assert(client._model_family_matches("moonshot-v1-8k", "moonshot"))
	assert(client._model_family_matches("doubao-seed-2.0-pro", "doubao"))
	assert(client._model_family_matches("notdeepseek-v4", "deepseek"))
	assert(client._chat_url("anthropic", "https://api.anthropic.com/v1") == "https://api.anthropic.com/v1/messages")
	assert(client._chat_url("gemini", "https://generativelanguage.googleapis.com/v1beta", "gemini-1.5-flash") == "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent")
	assert(client._parse_content("ollama", {"message": {"content": "白天先听发言。"}}) == "白天先听发言。")
	assert(client._parse_content("openai", {"choices": [{"message": {"content": "{\"action\":\"vote\",\"targetSeatNumber\":2}"}}]}) == "{\"action\":\"vote\",\"targetSeatNumber\":2}")
	assert(client._parse_content("openai", {"choices": [{"message": {"content": "", "tool_calls": [{"type": "function", "function": {"name": "werewolf_vote_v1", "arguments": "{\"action\":\"vote\",\"targetSeatNumber\":2}"}}]}}]}) == "{\"action\":\"vote\",\"targetSeatNumber\":2}")
	assert(client._parse_content("anthropic", {"content": [{"type": "text", "text": "先验一号"}]}) == "先验一号")
	var anthropic_tool_content = JSON.parse_string(client._parse_content("anthropic", {"content": [{"type": "tool_use", "name": "werewolf_vote_v1", "input": {"action": "vote", "targetSeatNumber": 2}}]}))
	assert(anthropic_tool_content is Dictionary)
	assert(String((anthropic_tool_content as Dictionary).get("action", "")) == "vote")
	assert(int((anthropic_tool_content as Dictionary).get("targetSeatNumber", -1)) == 2)
	assert(client._parse_content("gemini", {"candidates": [{"content": {"parts": [{"text": "我先发言"}]}}]}) == "我先发言")
	assert(client._headers_debug(["Content-Type: application/json", "Authorization: Bearer secret"]) == "Content-Type: application/json, Authorization=set")
	_checkpoint("provider_payloads")
	var anthropic_payload: Dictionary = client._payload("anthropic", "claude-3-5-sonnet", [{"role": "system", "content": "主持"}, {"role": "user", "content": "行动"}], 0.6, false, 4096)
	assert(String(anthropic_payload["system"]) == "主持")
	assert((anthropic_payload["messages"] as Array).size() == 1)
	assert(int(anthropic_payload.get("max_tokens", 0)) == 4096)
	var gemini_payload: Dictionary = client._payload("gemini", "gemini-1.5-flash", [{"role": "assistant", "content": "上一轮"}, {"role": "user", "content": "继续"}], 0.6, false, 4096)
	assert(String(((gemini_payload["contents"] as Array)[0] as Dictionary)["role"]) == "model")
	assert(int((gemini_payload["generationConfig"] as Dictionary).get("maxOutputTokens", 0)) == 4096)
	var openai_payload: Dictionary = client._payload("openai", "deepseek-r1", [{"role": "user", "content": "hello"}], 0.6, false, 4096)
	assert(int(openai_payload.get("max_tokens", 0)) == 4096)
	assert(not openai_payload.has("reasoning_effort"))
	assert(client._request_url("openai", "https://api.example.local/v1", "qwen:test", {"stream": true}) == "https://api.example.local/v1/chat/completions")
	assert(client._request_url("gemini", "https://generativelanguage.googleapis.com/v1beta", "gemini-1.5-flash", {"stream": true}) == "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:streamGenerateContent")
	var openai_stream_payload: Dictionary = client._payload("openai", "qwen:test", [{"role": "user", "content": "hello"}], 0.6, false, 64, {"stream": true})
	assert(bool(openai_stream_payload.get("stream", false)))
	var anthropic_stream_payload: Dictionary = client._payload("anthropic", "claude-3-5-sonnet", [{"role": "user", "content": "hello"}], 0.6, false, 64, {"stream": true})
	assert(bool(anthropic_stream_payload.get("stream", false)))
	var ollama_stream_payload: Dictionary = client._payload("ollama", "qwen", [{"role": "user", "content": "hello"}], 0.6, false, 64, {"stream": true})
	assert(bool(ollama_stream_payload.get("stream", false)))
	var stream_events := []
	var protocol_events := []
	client.stream_output.connect(func(request_id: int, kind: String, text: String):
		stream_events.append({"request_id": request_id, "kind": kind, "text": text})
	)
	client.protocol_event.connect(func(request_id: int, event: Dictionary):
		protocol_events.append({"request_id": request_id, "event": event.duplicate(true)})
	)
	_checkpoint("stream_parsing")
	var openai_stream_result: Dictionary = client._parse_stream_response(201, "openai", "data: {\"choices\":[{\"delta\":{\"content\":\"投\",\"reasoning_content\":\"想\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"票\"}}]}\n\ndata: [DONE]\n\n")
	assert(bool(openai_stream_result.get("ok", false)))
	assert(String(openai_stream_result.get("content", "")) == "投票")
	assert(String(openai_stream_result.get("reasoning_content", "")) == "想")
	var anthropic_stream_result: Dictionary = client._parse_stream_response(202, "anthropic", "data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"查验\",\"thinking\":\"先看发言\"}}\n\ndata: {\"type\":\"message_delta\",\"delta\":{\"thinking\":\"再下结论\"}}\n\n")
	assert(bool(anthropic_stream_result.get("ok", false)))
	assert(String(anthropic_stream_result.get("content", "")) == "查验")
	assert(String(anthropic_stream_result.get("reasoning_content", "")) == "先看发言再下结论")
	var gemini_stream_result: Dictionary = client._parse_stream_response(203, "gemini", "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"分析中\",\"thought\":true},{\"text\":\"我投2号\"}]}}]}\n\n")
	assert(bool(gemini_stream_result.get("ok", false)))
	assert(String(gemini_stream_result.get("content", "")) == "我投2号")
	assert(String(gemini_stream_result.get("reasoning_content", "")) == "分析中")
	var ollama_stream_result: Dictionary = client._parse_stream_response(204, "ollama", "{\"message\":{\"content\":\"守卫\",\"thinking\":\"先保自己\"}}\n{\"message\":{\"content\":\"保1号\"}}\n")
	assert(bool(ollama_stream_result.get("ok", false)))
	assert(String(ollama_stream_result.get("content", "")) == "守卫保1号")
	assert(String(ollama_stream_result.get("reasoning_content", "")) == "先保自己")
	assert(stream_events.size() == 8)
	assert(int((stream_events[0] as Dictionary).get("request_id", 0)) == 201)
	assert(String((stream_events[0] as Dictionary).get("kind", "")) == "text")
	assert(String((stream_events[0] as Dictionary).get("text", "")) == "投票")
	assert(String((stream_events[1] as Dictionary).get("kind", "")) == "reasoning")
	assert(String((stream_events[1] as Dictionary).get("text", "")) == "想")
	assert(int((stream_events[2] as Dictionary).get("request_id", 0)) == 202)
	assert(String((stream_events[2] as Dictionary).get("kind", "")) == "text")
	assert(String((stream_events[2] as Dictionary).get("text", "")) == "查验")
	assert(String((stream_events[3] as Dictionary).get("kind", "")) == "reasoning")
	assert(String((stream_events[3] as Dictionary).get("text", "")) == "先看发言再下结论")
	assert(int((stream_events[4] as Dictionary).get("request_id", 0)) == 203)
	assert(String((stream_events[4] as Dictionary).get("kind", "")) == "text")
	assert(String((stream_events[4] as Dictionary).get("text", "")) == "我投2号")
	assert(String((stream_events[5] as Dictionary).get("kind", "")) == "reasoning")
	assert(String((stream_events[5] as Dictionary).get("text", "")) == "分析中")
	assert(int((stream_events[6] as Dictionary).get("request_id", 0)) == 204)
	assert(String((stream_events[6] as Dictionary).get("kind", "")) == "text")
	assert(String((stream_events[6] as Dictionary).get("text", "")) == "守卫保1号")
	assert(String((stream_events[7] as Dictionary).get("kind", "")) == "reasoning")
	assert(String((stream_events[7] as Dictionary).get("text", "")) == "先保自己")
	assert(protocol_events.size() == 8)
	assert(String((((protocol_events[0] as Dictionary).get("event", {}) as Dictionary).get("type", ""))) == "chunk")
	assert(String((((protocol_events[0] as Dictionary).get("event", {}) as Dictionary).get("kind", ""))) == "text")
	_checkpoint("final_result_and_validation")
	client._emit_final_result(999, true, "ok", "", {
		"has_text_output": true,
		"has_reasoning_output": true,
		"has_stream_output": true,
		"reasoning_output": "thinking",
		"response_code": 200,
	}, {
		"provider": "openai",
		"model": "qwen:test",
		"purpose": "check",
		"output_type": "json",
		"transport_mode": "stream",
		"reasoning_mode": "on",
		"output_adapter": "openai_json_schema",
		"reason_adapter": "openai_reasoning_effort",
	}, "{\"ok\":true}")
	var final_result: Dictionary = client.take_completed_result(999)
	assert(bool(final_result.get("ok", false)))
	assert(String(final_result.get("text", "")) == "ok")
	assert(String(final_result.get("provider", "")) == "openai")
	assert(String(final_result.get("model", "")) == "qwen:test")
	assert(String(final_result.get("output_type", "")) == "json")
	assert(String(final_result.get("transport_mode", "")) == "stream")
	assert(String(final_result.get("reasoning_mode", "")) == "on")
	assert(bool(final_result.get("has_reasoning_output", false)))
	assert(bool(final_result.get("has_stream_output", false)))
	assert(String(final_result.get("reasoning_text", "")) == "thinking")
	assert(int(final_result.get("response_code", 0)) == 200)
	assert(client.take_completed_result(999).is_empty())
	var normalized_json_text: String = client._normalize_json_output_content("```json\n{\"action\":\"vote\",\"targetSeatNumber\":2}\n```", {
		"output_type": "json",
	})
	assert(normalized_json_text == "{\"action\":\"vote\",\"targetSeatNumber\":2}")
	var untouched_text: String = client._normalize_json_output_content("```json\n{\"action\":\"vote\"}\n```", {
		"output_type": "text",
	})
	assert(untouched_text.begins_with("```json"))
	var mixed_json_text: String = client._normalize_json_output_content("说明\n```json\n{\"action\":\"vote\"}\n```", {
		"output_type": "json",
	})
	assert(mixed_json_text.begins_with("说明"))
	var invalid_request_id: int = client.complete_request({
		"provider": "openai_api",
		"endpoint": "https://api.example.local/v1",
		"model": "qwen:test",
		"messages": [{"role": "user", "content": "vote"}],
		"output_type": "json",
	})
	await process_frame
	var invalid_result: Dictionary = client.take_completed_result(invalid_request_id)
	assert(not bool(invalid_result.get("ok", true)))
	assert(String(invalid_result.get("error", "")) == "JSON 输出必须提供 response_schema")
	assert(String(invalid_result.get("output_type", "")) == "json")
	assert(client._sse_data_events("event: message\ndata: {\"a\":1}\ndata: {\"b\":2}\n\n") == ["{\"a\":1}\n{\"b\":2}"])
	_checkpoint("reason_and_schema_adapters")
	var openai_reasoning_payload: Dictionary = client._payload("openai", "gpt-5.4", [{"role": "user", "content": "hello"}], 0.6, true)
	assert(String(openai_reasoning_payload.get("reasoning_effort", "")) == "medium")
	var explicit_reason_payload: Dictionary = client._payload("openai", "gpt-5.4", [{"role": "user", "content": "hello"}], 0.6, true, 64, {"reason_adapter": "openai_reasoning_effort"})
	assert(String(explicit_reason_payload.get("reasoning_effort", "")) == "medium")
	assert(not explicit_reason_payload.has("max_tokens"))
	var glm_reason_off_payload: Dictionary = client._payload("openai", "glm-5.1", [{"role": "user", "content": "hello"}], 0.6, false, 64, {"reason_adapter": "glm_thinking"})
	assert(String((glm_reason_off_payload.get("thinking", {}) as Dictionary).get("type", "")) == "disabled")
	var glm_reason_on_payload: Dictionary = client._payload("openai", "glm-5.1", [{"role": "user", "content": "hello"}], 0.6, true, 64, {"reason_adapter": "glm_thinking"})
	assert(String((glm_reason_on_payload.get("thinking", {}) as Dictionary).get("type", "")) == "enabled")
	assert(not glm_reason_on_payload.has("max_tokens"))
	var minimax_reason_off_payload: Dictionary = client._payload("openai", "minimax-m2.7", [{"role": "user", "content": "hello"}], 0.6, false, 64, {"reason_adapter": "minimax_reasoning_split"})
	assert(bool(minimax_reason_off_payload.get("reasoning_split", false)))
	var minimax_reason_payload: Dictionary = client._payload("openai", "minimax-m2.7", [{"role": "user", "content": "hello"}], 0.6, true, 64, {"reason_adapter": "minimax_reasoning_split"})
	assert(bool(minimax_reason_payload.get("reasoning_split", false)))
	var kimi_reason_payload: Dictionary = client._payload("openai", "kimi-k2.6", [{"role": "user", "content": "hello"}], 0.6, true, 64, {"reason_adapter": "kimi_thinking_control"})
	assert(String((kimi_reason_payload.get("thinking", {}) as Dictionary).get("type", "")) == "enabled")
	assert(not kimi_reason_payload.has("max_tokens"))
	var ark_reason_payload: Dictionary = client._payload("openai", "doubao-seed-2.0-pro", [{"role": "user", "content": "hello"}], 0.6, true, 64, {"reason_adapter": "ark_thinking"})
	assert(String((ark_reason_payload.get("thinking", {}) as Dictionary).get("type", "")) == "enabled")
	assert(not ark_reason_payload.has("max_tokens"))
	assert(not ark_reason_payload.has("reasoning_effort"))
	var ark_reason_off_payload: Dictionary = client._payload("openai", "doubao-seed-2.0-pro", [{"role": "user", "content": "hello"}], 0.6, false, 64, {"reason_adapter": "ark_thinking"})
	assert(String((ark_reason_off_payload.get("thinking", {}) as Dictionary).get("type", "")) == "disabled")
	var mimo_reason_payload: Dictionary = client._payload("openai", "mimo-v2", [{"role": "user", "content": "hello"}], 0.6, true, 64, {"reason_adapter": "mimo_chat_template"})
	assert(bool((mimo_reason_payload.get("chat_template_kwargs", {}) as Dictionary).get("enable_thinking", false)))
	assert(not mimo_reason_payload.has("max_tokens"))
	var response_schema := {
		"name": "werewolf_vote_v1",
		"strict": true,
		"schema": {
			"type": "object",
			"additionalProperties": false,
			"properties": {
				"action": {"type": "string", "enum": ["vote"]},
				"targetSeatNumber": {"type": "integer", "enum": [2]},
			},
			"required": ["action", "targetSeatNumber"],
		},
	}
	var openai_schema_payload: Dictionary = client._payload("openai", "gpt-5.4", [{"role": "user", "content": "vote"}], 0.2, false, 0, {"response_schema": response_schema})
	var openai_response_format: Dictionary = openai_schema_payload["response_format"] as Dictionary
	assert(String(openai_response_format.get("type", "")) == "json_schema")
	var openai_json_schema: Dictionary = openai_response_format["json_schema"] as Dictionary
	assert(String(openai_json_schema.get("name", "")) == "werewolf_vote_v1")
	assert(bool(openai_json_schema.get("strict", false)))
	assert(((openai_json_schema["schema"] as Dictionary)["properties"] as Dictionary).has("targetSeatNumber"))
	var gemini_schema_payload: Dictionary = client._payload("gemini", "gemini-1.5-flash", [{"role": "user", "content": "vote"}], 0.2, false, 0, {"response_schema": response_schema})
	var gemini_generation_config: Dictionary = gemini_schema_payload["generationConfig"] as Dictionary
	assert(String(gemini_generation_config.get("responseMimeType", "")) == "application/json")
	assert(((gemini_generation_config["responseJsonSchema"] as Dictionary)["properties"] as Dictionary).has("targetSeatNumber"))
	assert((gemini_generation_config["responseJsonSchema"] as Dictionary).get("propertyOrdering", []) == ["action", "targetSeatNumber"])
	assert(client._payload_schema_state(gemini_schema_payload) == "generationConfig.responseJsonSchema")
	var anthropic_schema_payload: Dictionary = client._payload("anthropic", "claude-3-5-sonnet", [{"role": "system", "content": "主持"}, {"role": "user", "content": "vote"}], 0.2, false, 64, {"response_schema": response_schema})
	assert((anthropic_schema_payload["tools"] as Array).size() == 1)
	assert(String((anthropic_schema_payload["tool_choice"] as Dictionary).get("name", "")) == "werewolf_vote_v1")
	assert((((anthropic_schema_payload["tools"] as Array)[0] as Dictionary)["input_schema"] as Dictionary).has("required"))
	assert(client._payload_schema_state(anthropic_schema_payload) == "tools.tool_choice")
	var ollama_schema_payload: Dictionary = client._payload("ollama", "qwen", [{"role": "user", "content": "vote"}], 0.2, false, 64, {"response_schema": response_schema})
	assert(((ollama_schema_payload["format"] as Dictionary)["properties"] as Dictionary).has("targetSeatNumber"))
	assert(client._payload_schema_state(ollama_schema_payload) == "format")
	var request_options: Dictionary = client._request_options_from_request({
		"response_schema": response_schema,
		"top_p": 0.4,
		"reason_adapter": "minimax_reasoning_split",
		"output_adapter": "openai_json_schema",
		"model_params": {"presence_penalty": 0.2},
		"extra_payload": {"metadata": {"purpose": "check"}},
	})
	assert(request_options.has("response_schema"))
	assert(String(request_options.get("reason_adapter", "")) == "minimax_reasoning_split")
	assert(String(request_options.get("output_adapter", "")) == "openai_json_schema")
	assert(absf(float(request_options.get("top_p", 0.0)) - 0.4) < 0.001)
	var request_messages: Array = client._messages_from_request({"prompt": "直接文本"})
	assert(request_messages.size() == 1)
	assert(String((request_messages[0] as Dictionary).get("content", "")) == "直接文本")
	var request_payload: Dictionary = client._payload("openai", "qwen:test", request_messages, 0.3, false, 128, request_options)
	assert(int(request_payload.get("max_tokens", 0)) == 128)
	assert(absf(float(request_payload.get("top_p", 0.0)) - 0.4) < 0.001)
	assert(absf(float(request_payload.get("presence_penalty", 0.0)) - 0.2) < 0.001)
	assert(((request_payload.get("metadata", {}) as Dictionary).get("purpose", "")) == "check")
	assert(String(((request_payload["messages"] as Array)[0] as Dictionary).get("content", "")) == "直接文本")
	assert((request_payload["response_format"] as Dictionary).has("json_schema"))
	var debug_context: Dictionary = client._model_call_debug_context(1, {
		"api_key": "sk-test",
		"options": request_options,
		"purpose": "check",
	}, "openai", "https://api.example.local/v1", "https://api.example.local/v1/chat/completions", "qwen:test", [], request_messages, response_schema, request_payload, 128, 0.3, 30.0, false, false)
	assert(String(debug_context.get("api_key_raw", "")) == "sk-test")
	assert(String(debug_context.get("api_key", "")) == "set")
	assert((debug_context.get("request_options", {}) as Dictionary).has("response_schema"))
	assert(String(debug_context.get("reason_adapter", "")) == "minimax_reasoning_split")
	assert(String(debug_context.get("output_adapter", "")) == "openai_json_schema")
	var explicit_json_object_payload: Dictionary = client._payload("openai", "qwen:test", request_messages, 0.3, false, 128, {"response_schema": response_schema, "formt_adapter": "openai_json_object"})
	assert(not explicit_json_object_payload.has("response_format"))
	client._apply_openai_compat_payload_adjustments(explicit_json_object_payload, "openai", "https://api.example.local/v1", response_schema, false, "openai_json_object")
	assert(String((explicit_json_object_payload["response_format"] as Dictionary).get("type", "")) == "json_object")
	assert(String(((explicit_json_object_payload["messages"] as Array)[0] as Dictionary).get("content", "")).contains("[OpenAI JSON Object Mode]"))
	var explicit_tool_payload: Dictionary = client._payload("openai", "qwen:test", request_messages, 0.3, false, 128, {"response_schema": response_schema, "formt_adapter": "openai_tool_optional"})
	client._apply_openai_compat_payload_adjustments(explicit_tool_payload, "openai", "https://api.example.local/v1", response_schema, false, "openai_tool_optional")
	assert((explicit_tool_payload["tools"] as Array).size() == 1)
	assert(not explicit_tool_payload.has("tool_choice"))
	var explicit_deepseek_object_payload: Dictionary = client._payload("openai", "deepseek-v4-flash", request_messages, 0.3, false, 128, {"response_schema": response_schema, "formt_adapter": "openai_json_object"})
	client._apply_openai_compat_payload_adjustments(explicit_deepseek_object_payload, "openai", "https://api.deepseek.com", response_schema, false, "openai_json_object")
	assert(String((explicit_deepseek_object_payload["response_format"] as Dictionary).get("type", "")) == "json_object")
	assert(String(((explicit_deepseek_object_payload["messages"] as Array)[0] as Dictionary).get("content", "")).contains("[DeepSeek JSON Mode]"))
	var explicit_kimi_object_payload: Dictionary = client._payload("openai", "kimi-k2.6", request_messages, 0.3, false, 128, {"response_schema": response_schema, "formt_adapter": "openai_json_object"})
	client._apply_openai_compat_payload_adjustments(explicit_kimi_object_payload, "openai", "https://api.moonshot.ai/v1", response_schema, false, "openai_json_object")
	assert(String((explicit_kimi_object_payload["response_format"] as Dictionary).get("type", "")) == "json_object")
	assert(String(((explicit_kimi_object_payload["messages"] as Array)[0] as Dictionary).get("content", "")).contains("[Kimi JSON Mode]"))
	var explicit_glm_tool_payload: Dictionary = client._payload("openai", "glm-5.1", request_messages, 0.3, false, 128, {"response_schema": response_schema, "formt_adapter": "openai_tool_forced"})
	client._apply_openai_compat_payload_adjustments(explicit_glm_tool_payload, "openai", "https://ark.cn-beijing.volces.com/api/plan/v3", response_schema, false, "openai_tool_forced")
	assert((explicit_glm_tool_payload["tools"] as Array).size() == 1)
	assert(String((explicit_glm_tool_payload["tool_choice"] as Dictionary).get("type", "")) == "function")
	var explicit_minimax_tool_v2_payload: Dictionary = client._payload("openai", "minimax-m2.7", request_messages, 0.3, false, 128, {"response_schema": response_schema, "formt_adapter": "openai_tool_optional"})
	client._apply_openai_compat_payload_adjustments(explicit_minimax_tool_v2_payload, "openai", "https://ark.cn-beijing.volces.com/api/plan/v3", response_schema, false, "openai_tool_optional")
	assert((explicit_minimax_tool_v2_payload["tools"] as Array).size() == 1)
	assert(not explicit_minimax_tool_v2_payload.has("tool_choice"))
	assert(String(((explicit_minimax_tool_v2_payload["messages"] as Array)[0] as Dictionary).get("content", "")).contains("[MiniMax Tool Mode]"))
	var explicit_general_reason_off_payload: Dictionary = client._payload("openai", "qwen:test", request_messages, 0.3, false, 128, {"reason_adapter": "native"})
	assert(not explicit_general_reason_off_payload.has("thinking"))
	var explicit_glm_reason_off_payload: Dictionary = client._payload("openai", "glm-5.1", request_messages, 0.3, false, 128, {"reason_adapter": "glm_thinking"})
	assert(String((explicit_glm_reason_off_payload.get("thinking", {}) as Dictionary).get("type", "")) == "disabled")
	var explicit_none_payload: Dictionary = client._payload("openai", "qwen:test", request_messages, 0.3, false, 128, {"response_schema": response_schema, "formt_adapter": "none"})
	client._apply_openai_compat_payload_adjustments(explicit_none_payload, "openai", "https://api.example.local/v1", response_schema, false, "none")
	assert(client._payload_schema_state(explicit_none_payload) == "empty")
	var xiaomi_endpoint_only_payload: Dictionary = request_payload.duplicate(true)
	client._apply_openai_compat_payload_adjustments(xiaomi_endpoint_only_payload, "openai", "https://token-plan-cn.xiaomimimo.com/v1", response_schema, false)
	assert(String((xiaomi_endpoint_only_payload["response_format"] as Dictionary).get("type", "")) == "json_schema")
	assert(not xiaomi_endpoint_only_payload.has("chat_template_kwargs"))
	assert(client._payload_schema_state(xiaomi_endpoint_only_payload) == "response_format")
	var xiaomi_reasoning_payload: Dictionary = client._payload("openai", "mimo-v2", request_messages, 0.3, true, 128, request_options)
	client._apply_openai_compat_payload_adjustments(xiaomi_reasoning_payload, "openai", "https://token-plan-cn.xiaomimimo.com/v1", response_schema, true)
	assert(not xiaomi_reasoning_payload.has("reasoning_effort"))
	assert(not xiaomi_reasoning_payload.has("max_tokens"))
	assert(not xiaomi_reasoning_payload.has("response_format"))
	assert((xiaomi_reasoning_payload["tools"] as Array).size() == 1)
	assert(String((xiaomi_reasoning_payload["tool_choice"] as Dictionary).get("type", "")) == "function")
	assert(bool(xiaomi_reasoning_payload.get("parallel_tool_calls", true)) == false)
	assert(bool((xiaomi_reasoning_payload["chat_template_kwargs"] as Dictionary).get("enable_thinking", false)) == true)
	assert(client._payload_schema_state(xiaomi_reasoning_payload) == "tools.tool_choice")
	var mimo_model_payload: Dictionary = client._payload("openai", "mimo-v2", request_messages, 0.3, true, 128, request_options)
	client._apply_openai_compat_payload_adjustments(mimo_model_payload, "openai", "https://ark.cn-beijing.volces.com/api/plan/v3", response_schema, true)
	assert(not mimo_model_payload.has("reasoning_effort"))
	assert(not mimo_model_payload.has("max_tokens"))
	assert(bool((mimo_model_payload["chat_template_kwargs"] as Dictionary).get("enable_thinking", false)) == true)
	assert(client._payload_schema_state(mimo_model_payload) == "tools.tool_choice")
	var deepseek_over_mimo_payload: Dictionary = client._payload("openai", "deepseek-v4-flash", request_messages, 0.3, true, 128, request_options)
	client._apply_openai_compat_payload_adjustments(deepseek_over_mimo_payload, "openai", "https://token-plan-cn.xiaomimimo.com/v1", response_schema, true)
	assert(not deepseek_over_mimo_payload.has("max_tokens"))
	assert(client._payload_schema_state(deepseek_over_mimo_payload) == "response_format")
	assert(String((deepseek_over_mimo_payload["response_format"] as Dictionary).get("type", "")) == "json_object")
	var deepseek_endpoint_only_payload: Dictionary = request_payload.duplicate(true)
	client._apply_openai_compat_payload_adjustments(deepseek_endpoint_only_payload, "openai", "https://api.deepseek.com", response_schema, false)
	assert(String((deepseek_endpoint_only_payload["response_format"] as Dictionary).get("type", "")) == "json_schema")
	var deepseek_payload: Dictionary = client._payload("openai", "deepseek-chat", request_messages, 0.3, false, 128, request_options)
	client._apply_openai_compat_payload_adjustments(deepseek_payload, "openai", "https://api.deepseek.com", response_schema, false)
	var deepseek_response_format: Dictionary = deepseek_payload["response_format"] as Dictionary
	assert(String(deepseek_response_format.get("type", "")) == "json_object")
	assert(not deepseek_response_format.has("json_schema"))
	var deepseek_system := String(((deepseek_payload["messages"] as Array)[0] as Dictionary).get("content", ""))
	assert(deepseek_system.contains("[DeepSeek JSON Mode]"))
	assert(deepseek_system.contains("targetSeatNumber"))
	var deepseek_reasoning_payload: Dictionary = client._payload("openai", "deepseek-v4-flash", request_messages, 0.3, true, 128, request_options)
	client._apply_openai_compat_payload_adjustments(deepseek_reasoning_payload, "openai", "https://api.deepseek.com", response_schema, true)
	assert(not deepseek_reasoning_payload.has("reasoning_effort"))
	assert(not deepseek_reasoning_payload.has("max_tokens"))
	assert(String((deepseek_reasoning_payload["response_format"] as Dictionary).get("type", "")) == "json_object")
	var ark_deepseek_payload: Dictionary = client._payload("openai", "deepseek-v4-flash", request_messages, 0.3, true, 128, request_options)
	client._apply_openai_compat_payload_adjustments(ark_deepseek_payload, "openai", "https://ark.cn-beijing.volces.com/api/plan/v3", response_schema, true)
	assert(not ark_deepseek_payload.has("reasoning_effort"))
	assert(not ark_deepseek_payload.has("max_tokens"))
	assert(String((ark_deepseek_payload["response_format"] as Dictionary).get("type", "")) == "json_object")
	var deepseek_beta_payload: Dictionary = client._payload("openai", "deepseek-v4-flash", request_messages, 0.3, true, 128, request_options)
	client._apply_openai_compat_payload_adjustments(deepseek_beta_payload, "openai", "https://api.deepseek.com/beta", response_schema, true)
	assert(not deepseek_beta_payload.has("reasoning_effort"))
	assert(String((deepseek_beta_payload["response_format"] as Dictionary).get("type", "")) == "json_object")
	assert(not deepseek_beta_payload.has("tools"))
	assert(client._payload_schema_state(deepseek_beta_payload) == "response_format")
	var glm_request_options: Dictionary = request_options.duplicate(true)
	glm_request_options["reason_adapter"] = "glm_thinking"
	var glm_payload: Dictionary = client._payload("openai", "glm-5.1", request_messages, 0.3, true, 128, glm_request_options)
	glm_payload["model"] = "glm-5.1"
	client._apply_openai_compat_payload_adjustments(glm_payload, "openai", "https://ark.cn-beijing.volces.com/api/plan/v3", response_schema, true)
	assert(not glm_payload.has("reasoning_effort"))
	assert(not glm_payload.has("max_tokens"))
	assert(String((glm_payload.get("thinking", {}) as Dictionary).get("type", "")) == "enabled")
	assert(not glm_payload.has("response_format"))
	assert((glm_payload["tools"] as Array).size() == 1)
	assert(String((glm_payload["tool_choice"] as Dictionary).get("type", "")) == "function")
	assert(bool(glm_payload.get("parallel_tool_calls", true)) == false)
	var glm_system := String(((glm_payload["messages"] as Array)[0] as Dictionary).get("content", ""))
	assert(not glm_system.contains("[GLM JSON Mode]"))
	assert(client._payload_schema_state(glm_payload) == "tools.tool_choice")
	var kimi_payload: Dictionary = client._payload("openai", "kimi-k2.6", request_messages, 0.3, true, 128, request_options)
	client._apply_openai_compat_payload_adjustments(kimi_payload, "openai", "https://ark.cn-beijing.volces.com/api/plan/v3", response_schema, true)
	assert(not kimi_payload.has("reasoning_effort"))
	assert(not kimi_payload.has("max_tokens"))
	var kimi_response_format: Dictionary = kimi_payload["response_format"] as Dictionary
	assert(String(kimi_response_format.get("type", "")) == "json_object")
	assert(not kimi_response_format.has("json_schema"))
	var kimi_system := String(((kimi_payload["messages"] as Array)[0] as Dictionary).get("content", ""))
	assert(kimi_system.contains("[Kimi JSON Mode]"))
	assert(kimi_system.contains("targetSeatNumber"))
	var kimi_text_payload: Dictionary = client._payload("openai", "kimi-k2.6", request_messages, 0.3, false, 128, {"formt_adapter": "none"})
	client._apply_openai_compat_payload_adjustments(kimi_text_payload, "openai", "https://ark.cn-beijing.volces.com/api/plan/v3", {}, false, "none")
	assert(String((kimi_text_payload.get("thinking", {}) as Dictionary).get("type", "")) == "disabled")
	assert(not kimi_text_payload.has("response_format"))
	var moonshot_payload: Dictionary = client._payload("openai", "moonshot-v1-8k", request_messages, 0.3, false, 128, request_options)
	client._apply_openai_compat_payload_adjustments(moonshot_payload, "openai", "https://api.moonshot.ai/v1", response_schema, false)
	assert(String((moonshot_payload["response_format"] as Dictionary).get("type", "")) == "json_object")
	var minimax_payload: Dictionary = client._payload("openai", "minimax-m2.7", request_messages, 0.3, true, 128, {"response_schema": response_schema, "reason_adapter": "minimax_reasoning_split"})
	client._apply_openai_compat_payload_adjustments(minimax_payload, "openai", "https://ark.cn-beijing.volces.com/api/plan/v3", response_schema, true)
	assert(not minimax_payload.has("reasoning_effort"))
	assert(not minimax_payload.has("max_tokens"))
	assert(not minimax_payload.has("response_format"))
	assert((minimax_payload["tools"] as Array).size() == 1)
	assert(not minimax_payload.has("tool_choice"))
	var minimax_system := String(((minimax_payload["messages"] as Array)[0] as Dictionary).get("content", ""))
	assert(minimax_system.contains("[MiniMax Tool Mode]"))
	assert(minimax_system.contains("werewolf_vote_v1"))
	assert(minimax_system.contains("targetSeatNumber"))
	assert(client._payload_schema_state(minimax_payload) == "tools")
	assert(bool(minimax_payload.get("reasoning_split", false)))
	assert(client._parse_reasoning_content("openai", {"choices": [{"message": {"reasoning_details": [{"text": "step1"}, {"content": [{"text": "step2"}]}]}}]}) == "step1\nstep2")
	var ark_doubao_payload: Dictionary = client._payload("openai", "doubao-seed-2.0-lite", request_messages, 0.3, true, 128, {"response_schema": response_schema, "reason_adapter": "ark_thinking"})
	ark_doubao_payload["model"] = "doubao-seed-2.0-lite"
	client._apply_openai_compat_payload_adjustments(ark_doubao_payload, "openai", "https://ark.cn-beijing.volces.com/api/plan/v3", response_schema, true)
	assert(not ark_doubao_payload.has("reasoning_effort"))
	assert(not ark_doubao_payload.has("max_tokens"))
	assert(String((ark_doubao_payload.get("thinking", {}) as Dictionary).get("type", "")) == "enabled")
	assert(String((ark_doubao_payload["response_format"] as Dictionary).get("type", "")) == "json_schema")
	var standard_payload: Dictionary = client._payload("openai", "gpt-5.4", request_messages, 0.3, true, 128, {"response_schema": response_schema, "reason_adapter": "openai_reasoning_effort"})
	client._apply_openai_compat_payload_adjustments(standard_payload, "openai", "https://api.openai.com/v1", response_schema, true)
	assert(String(standard_payload.get("reasoning_effort", "")) == "medium")
	assert(not standard_payload.has("max_tokens"))
	assert(not standard_payload.has("include_reasoning"))
	_checkpoint("done")
	var ollama_payload: Dictionary = client._payload("ollama", "qwen", [{"role": "user", "content": "hello"}], 0.6, false, 4096)
	assert(int((ollama_payload["options"] as Dictionary).get("num_predict", 0)) == 4096)
	var ollama_reasoning_payload: Dictionary = client._payload("ollama", "qwen", [{"role": "user", "content": "hello"}], 0.6, true, 4096)
	assert(not (ollama_reasoning_payload["options"] as Dictionary).has("num_predict"))
	var gemini_reasoning_payload: Dictionary = client._payload("gemini", "gemini-1.5-flash", [{"role": "user", "content": "hello"}], 0.6, true, 4096)
	assert(not (gemini_reasoning_payload["generationConfig"] as Dictionary).has("maxOutputTokens"))
	var anthropic_reasoning_payload: Dictionary = client._payload("anthropic", "claude-3-5-sonnet", [{"role": "user", "content": "hello"}], 0.6, true, 4096)
	assert(not anthropic_reasoning_payload.has("max_tokens"))
	quit()


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
