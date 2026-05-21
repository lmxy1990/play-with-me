extends RefCounted
class_name ModelChatClient

const ModelAdapterRegistryScript := preload("res://scripts/core/model/model_adapter_registry.gd")

signal completed(request_id: int, ok: bool, content: String, error: String)
signal stream_output(request_id: int, kind: String, text: String)
signal diagnostic_ready(request_id: int, diagnostic: Dictionary)
signal protocol_event(request_id: int, event: Dictionary)

const TRANSPORT_MODE_SYNC := "sync"
const TRANSPORT_MODE_STREAM := "stream"
const OUTPUT_TYPE_TEXT := "text"
const OUTPUT_TYPE_JSON := "json"
const REASONING_MODE_OFF := "off"
const REASONING_MODE_ON := "on"
const FORMT_ADAPTER_AUTO := "auto"
const FORMT_ADAPTER_NONE := "none"
const FORMT_ADAPTER_OPENAI_JSON_SCHEMA := "openai_json_schema"
const FORMT_ADAPTER_OPENAI_JSON_OBJECT := "openai_json_object"
const FORMT_ADAPTER_OPENAI_TOOL_FORCED := "openai_tool_forced"
const FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL := "openai_tool_optional"
const FORMT_ADAPTER_OPENAI_MIMO_TOOL := "openai_mimo_tool"
const FORMT_ADAPTER_GEMINI_JSON_SCHEMA := "gemini_json_schema"
const FORMT_ADAPTER_ANTHROPIC_TOOL := "anthropic_tool"
const FORMT_ADAPTER_OLLAMA_FORMAT_SCHEMA := "ollama_format_schema"
const REASON_ADAPTER_AUTO := "auto"
const REASON_ADAPTER_NATIVE := "native"
const REASON_ADAPTER_OPENAI_REASONING_EFFORT := "openai_reasoning_effort"
const REASON_ADAPTER_DEEPSEEK_THINKING := "deepseek_thinking"
const REASON_ADAPTER_GLM_THINKING := "glm_thinking"
const REASON_ADAPTER_ARK_THINKING := "ark_thinking"
const REASON_ADAPTER_MINIMAX_REASONING_SPLIT := "minimax_reasoning_split"
const REASON_ADAPTER_MIMO_CHAT_TEMPLATE := "mimo_chat_template"
const REASON_ADAPTER_KIMI_THINKING_CONTROL := "kimi_thinking_control"
const DEFAULT_MAX_RETRIES := 3
const DEFAULT_RETRY_DELAY_SEC := 0.75
const DEFAULT_RETRY_MAX_DELAY_SEC := 6.0
const RETRY_BACKOFF_MULTIPLIER := 2.0

var _next_request_id := 1
var _pending := {}
var _completed_diagnostics := {}
var _completed_results := {}
var _adapter_registry = ModelAdapterRegistryScript.new()


func complete(profile: Dictionary, messages: Array, temperature: float = 0.7, max_output_tokens: int = 0, timeout_sec: float = 30.0, options: Dictionary = {}) -> int:
	var request := profile.duplicate(true)
	request["messages"] = messages.duplicate(true)
	request["temperature"] = temperature
	request["max_output_tokens"] = max_output_tokens
	request["timeout_sec"] = timeout_sec
	request["options"] = options.duplicate(true)
	var request_options := _request_options_from_request(request)
	var response_schema := _response_schema_from_request(request, request_options)
	request["transport_mode"] = _transport_mode_from_request(request, request_options)
	request["output_type"] = _output_type_from_request(request, request_options, response_schema)
	request["reasoning_mode"] = _reasoning_mode_from_request(request)
	request["output_adapter"] = _output_adapter_from_request(request, request_options)
	request["reason_adapter"] = _reason_adapter_from_request(request, request_options)
	if not response_schema.is_empty():
		request["response_schema"] = response_schema.duplicate(true)
	return complete_request(request)


func take_completed_diagnostic(request_id: int) -> Dictionary:
	if not _completed_diagnostics.has(request_id):
		return {}
	var diagnostic = _completed_diagnostics.get(request_id, {})
	_completed_diagnostics.erase(request_id)
	return diagnostic.duplicate(true) if diagnostic is Dictionary else {}


func take_completed_result(request_id: int) -> Dictionary:
	if not _completed_results.has(request_id):
		return {}
	var result = _completed_results.get(request_id, {})
	_completed_results.erase(request_id)
	return result.duplicate(true) if result is Dictionary else {}


func build_request_debug_payload(request: Dictionary) -> Dictionary:
	var endpoint := String(request.get("endpoint", "")).strip_edges()
	var model := String(request.get("model", "")).strip_edges()
	var provider := _normalize_provider(String(request.get("provider", "")))
	var messages := _messages_from_request(request)
	var request_options := _request_options_from_request(request)
	var response_schema := _response_schema_from_request(request, request_options)
	var output_adapter := _output_adapter_from_request(request, request_options)
	var reason_adapter := _reason_adapter_from_request(request, request_options)
	var transport_mode := _transport_mode_from_request(request, request_options)
	var output_type := _output_type_from_request(request, request_options, response_schema)
	var reasoning_mode := _reasoning_mode_from_request(request)
	var temperature := clampf(float(request.get("temperature", 0.7)), 0.0, 2.0)
	var reasoning := reasoning_mode == REASONING_MODE_ON
	var connection_test := bool(request.get("connection_test", false))
	var stream_requested := transport_mode == TRANSPORT_MODE_STREAM
	var requested_output_tokens := int(request.get("max_output_tokens", request.get("max_tokens", 0)))
	var output_tokens := _effective_max_output_tokens(request, requested_output_tokens, reasoning)
	var url := _request_url(provider, endpoint, model, request_options) if endpoint != "" and model != "" else ""
	var payload := _payload(provider, model, messages, temperature, reasoning, output_tokens, request_options)
	_apply_openai_compat_payload_adjustments(payload, provider, endpoint, response_schema, reasoning, output_adapter, reason_adapter)
	return {
		"purpose": String(request.get("purpose", request.get("module", request.get("debug_label", "")))).strip_edges(),
		"provider": provider,
		"endpoint": endpoint,
		"url": url,
		"model": model,
		"transport_mode": transport_mode,
		"output_type": output_type,
		"reasoning_mode": reasoning_mode,
		"output_adapter": output_adapter,
		"reason_adapter": reason_adapter,
		"temperature": temperature,
		"output_tokens": output_tokens,
		"reasoning": reasoning,
		"connection_test": connection_test,
		"stream_requested": stream_requested,
		"payload_schema": _payload_schema_state(payload),
		"schema_payload": _payload_schema_payload_text(payload),
		"response_schema": response_schema.duplicate(true),
		"messages": messages.duplicate(true),
		"payload": payload.duplicate(true),
	}


func complete_request(request: Dictionary) -> int:
	var request_id := _next_request_id
	_next_request_id += 1
	var endpoint := String(request.get("endpoint", "")).strip_edges()
	var model := String(request.get("model", "")).strip_edges()
	var provider := _normalize_provider(String(request.get("provider", "")))
	var messages := _messages_from_request(request)
	var request_options := _request_options_from_request(request)
	var response_schema := _response_schema_from_request(request, request_options)
	var output_adapter := _output_adapter_from_request(request, request_options)
	var reason_adapter := _reason_adapter_from_request(request, request_options)
	var transport_mode := _transport_mode_from_request(request, request_options)
	var output_type := _output_type_from_request(request, request_options, response_schema)
	var reasoning_mode := _reasoning_mode_from_request(request)
	var temperature := clampf(float(request.get("temperature", 0.7)), 0.0, 2.0)
	var timeout_sec := maxf(0.1, float(request.get("timeout_sec", request.get("timeout", 30.0))))
	var max_retries := _max_retries_from_request(request, request_options)
	var retry_delay_sec := _retry_delay_from_request(request, request_options)
	var retry_max_delay_sec := _retry_max_delay_from_request(request, request_options)
	var reasoning := reasoning_mode == REASONING_MODE_ON
	var connection_test := bool(request.get("connection_test", false))
	var requested_output_tokens := int(request.get("max_output_tokens", request.get("max_tokens", 0)))
	var output_tokens := _effective_max_output_tokens(request, requested_output_tokens, reasoning)
	var stream_requested := transport_mode == TRANSPORT_MODE_STREAM
	if output_type == OUTPUT_TYPE_JSON and response_schema.is_empty():
		var validation_context := _model_call_debug_context(request_id, request, provider, endpoint, "", model, [], messages, response_schema, {}, output_tokens, temperature, timeout_sec, reasoning, connection_test)
		_log_model_call_error_io("validation_failed", request_id, validation_context, "")
		call_deferred("_emit_final_result_deferred", request_id, false, "", "JSON 输出必须提供 response_schema", {}, validation_context, "")
		return request_id
	var debug_context := _model_call_debug_context(request_id, request, provider, endpoint, "", model, [], messages, response_schema, {}, output_tokens, temperature, timeout_sec, reasoning, connection_test)
	if endpoint == "" or model == "":
		push_warning("[ModelChatClient] complete skipped: endpoint_or_model_empty endpoint=%s model=%s" % [endpoint, model])
		_log_model_call_error_io("validation_failed", request_id, debug_context, "")
		call_deferred("_emit_final_result_deferred", request_id, false, "", "模型 endpoint 或 model 为空", {}, debug_context, "")
		return request_id

	var url := _request_url(provider, endpoint, model, request_options)
	var headers := ["Content-Type: application/json"]
	if stream_requested and provider != "ollama":
		headers.append("Accept: text/event-stream")
	var api_key := String(request.get("api_key", "")).strip_edges()
	if provider == "anthropic":
		headers.append("anthropic-version: 2023-06-01")
		if api_key != "":
			headers.append("x-api-key: %s" % api_key)
	elif provider == "gemini":
		if api_key != "":
			headers.append("x-goog-api-key: %s" % api_key)
	elif api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)
	var payload := _payload(provider, model, messages, temperature, reasoning, output_tokens, request_options)
	_apply_openai_compat_payload_adjustments(payload, provider, endpoint, response_schema, reasoning, output_adapter, reason_adapter)
	debug_context = _model_call_debug_context(request_id, request, provider, endpoint, url, model, headers, messages, response_schema, payload, output_tokens, temperature, timeout_sec, reasoning, connection_test)
	debug_context["attempt"] = 1
	debug_context["max_retries"] = max_retries
	debug_context["retry_delay_sec"] = retry_delay_sec
	debug_context["retry_max_delay_sec"] = retry_max_delay_sec
	print("[ModelChatClient] complete start id=%d purpose=%s provider=%s endpoint=%s url=%s model=%s transport_mode=%s output_type=%s reasoning_mode=%s output_adapter=%s reason_adapter=%s api_key=%s timeout=%.1f max_retries=%d retry_delay=%.2f temperature=%.2f output_tokens=%d reasoning=%s connection_test=%s messages=%d headers=%s schema=%s payload_schema=%s payload=%s" % [request_id, String(debug_context.get("purpose", "")), provider, endpoint, url, model, transport_mode, output_type, reasoning_mode, output_adapter, reason_adapter, _api_key_debug(api_key), timeout_sec, max_retries, retry_delay_sec, temperature, output_tokens, reasoning, connection_test, messages.size(), _headers_debug(headers), _response_schema_debug(response_schema), _payload_schema_state(payload), _payload_preview(payload)])
	if _payload_schema_state(payload) != "empty":
		_print_log_chunks("[ModelChatClient][request_schema_payload] id=%d" % request_id, _payload_schema_payload_text(payload))
	var request_state := {
		"request_id": request_id,
		"provider": provider,
		"url": url,
		"headers": headers.duplicate(true),
		"payload": payload.duplicate(true),
		"timeout_sec": timeout_sec,
		"model": model,
		"reasoning": reasoning,
		"connection_test": connection_test,
		"debug_context": debug_context.duplicate(true),
		"attempt": 1,
		"max_retries": max_retries,
		"retry_delay_sec": retry_delay_sec,
		"retry_max_delay_sec": retry_max_delay_sec,
	}
	var err := _start_chat_request(request_state)
	if err != OK:
		push_warning("[ModelChatClient] complete request create failed id=%d err=%s url=%s" % [request_id, err, url])
		_log_model_call_error_io("request_create_failed", request_id, debug_context, "")
		call_deferred("_emit_final_result_deferred", request_id, false, "", _request_start_error(err, url), {}, debug_context, "")
	return request_id


func _start_chat_request(request_state: Dictionary) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return ERR_UNAVAILABLE
	var request_id := int(request_state.get("request_id", 0))
	var provider := String(request_state.get("provider", ""))
	var url := String(request_state.get("url", ""))
	var headers: Array = request_state.get("headers", []) if request_state.get("headers", []) is Array else []
	var payload: Dictionary = request_state.get("payload", {}) if request_state.get("payload", {}) is Dictionary else {}
	var timeout_sec := float(request_state.get("timeout_sec", 30.0))
	var attempt := maxi(1, int(request_state.get("attempt", 1)))
	var max_retries := maxi(0, int(request_state.get("max_retries", DEFAULT_MAX_RETRIES)))
	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	var pending_state := request_state.duplicate(true)
	pending_state["attempt"] = attempt
	pending_state["max_retries"] = max_retries
	var debug_context: Dictionary = pending_state.get("debug_context", {}) if pending_state.get("debug_context", {}) is Dictionary else {}
	debug_context["attempt"] = attempt
	debug_context["max_retries"] = max_retries
	debug_context["retry_delay_sec"] = float(pending_state.get("retry_delay_sec", DEFAULT_RETRY_DELAY_SEC))
	debug_context["retry_max_delay_sec"] = float(pending_state.get("retry_max_delay_sec", DEFAULT_RETRY_MAX_DELAY_SEC))
	pending_state["debug_context"] = debug_context.duplicate(true)
	pending_state["http"] = http
	_pending[request_id] = {
		"http": pending_state.get("http"),
		"request_id": request_id,
		"provider": provider,
		"url": url,
		"headers": headers.duplicate(true),
		"payload": payload.duplicate(true),
		"timeout_sec": timeout_sec,
		"model": String(pending_state.get("model", "")),
		"reasoning": bool(pending_state.get("reasoning", false)),
		"connection_test": bool(pending_state.get("connection_test", false)),
		"debug_context": debug_context.duplicate(true),
		"attempt": attempt,
		"max_retries": max_retries,
		"retry_delay_sec": float(pending_state.get("retry_delay_sec", DEFAULT_RETRY_DELAY_SEC)),
		"retry_max_delay_sec": float(pending_state.get("retry_max_delay_sec", DEFAULT_RETRY_MAX_DELAY_SEC)),
	}
	http.request_completed.connect(_on_request_completed.bind(request_id, provider))
	tree.root.add_child(http)
	print("[ModelChatClient] request send id=%d provider=%s url=%s attempt=%d/%d" % [request_id, provider, url, attempt, max_retries + 1])
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_pending.erase(request_id)
		http.queue_free()
	return err


func _request_start_error(err: int, url: String) -> String:
	if err == ERR_UNAVAILABLE:
		return "当前没有可用 SceneTree url=%s" % url
	return "HTTP 请求创建失败：%s url=%s" % [err, url]


func _request_result_error(result: int, url: String) -> String:
	return "模型请求失败：%s(%s/%d) url=%s" % [_request_result_description(result), _request_result_label(result), result, url]


func _request_result_description(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "分块响应大小不匹配"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "无法连接"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "域名解析失败"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "连接错误"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS 握手失败"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "没有响应"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "响应体超过限制"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "响应体解压失败"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "请求失败"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "下载文件无法打开"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "下载文件写入失败"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "重定向次数超过限制"
		HTTPRequest.RESULT_TIMEOUT:
			return "请求超时"
		_:
			return "请求失败"


func _request_result_label(result: int) -> String:
	match result:
		HTTPRequest.RESULT_SUCCESS:
			return "RESULT_SUCCESS"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "RESULT_CHUNKED_BODY_SIZE_MISMATCH"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "RESULT_CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "RESULT_CANT_RESOLVE"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "RESULT_CONNECTION_ERROR"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "RESULT_TLS_HANDSHAKE_ERROR"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "RESULT_NO_RESPONSE"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "RESULT_BODY_SIZE_LIMIT_EXCEEDED"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "RESULT_BODY_DECOMPRESS_FAILED"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "RESULT_REQUEST_FAILED"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "RESULT_DOWNLOAD_FILE_CANT_OPEN"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "RESULT_DOWNLOAD_FILE_WRITE_ERROR"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "RESULT_REDIRECT_LIMIT_REACHED"
		HTTPRequest.RESULT_TIMEOUT:
			return "RESULT_TIMEOUT"
		_:
			return "RESULT_UNKNOWN"


func _retryable_request_result(result: int) -> bool:
	match result:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return true
		HTTPRequest.RESULT_CANT_CONNECT:
			return true
		HTTPRequest.RESULT_CANT_RESOLVE:
			return true
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return true
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return true
		HTTPRequest.RESULT_NO_RESPONSE:
			return true
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return true
		HTTPRequest.RESULT_REQUEST_FAILED:
			return true
		HTTPRequest.RESULT_TIMEOUT:
			return true
		_:
			return false


func _retryable_http_response_code(response_code: int) -> bool:
	return response_code == 408 or response_code == 429 or (response_code >= 500 and response_code <= 599)


func _retry_delay_for_attempt(attempt: int, base_delay_sec: float, max_delay_sec: float) -> float:
	if base_delay_sec <= 0.0:
		return 0.0
	var delay := base_delay_sec * pow(RETRY_BACKOFF_MULTIPLIER, maxi(0, attempt - 1))
	if max_delay_sec > 0.0:
		delay = minf(delay, max_delay_sec)
	return delay


func _request_error_with_attempts(result: int, url: String, attempt: int) -> String:
	var error := _request_result_error(result, url)
	if attempt > 1:
		error += "，已尝试 %d 次" % attempt
	return error


func _http_error_with_attempts(provider: String, url: String, text: String, response_code: int, attempt: int) -> String:
	var error := "%s模型响应异常 %d url=%s body=%s" % [_endpoint_hint(provider, url, text), response_code, url, _response_preview(text)]
	if attempt > 1:
		error += "，已尝试 %d 次" % attempt
	return error


func _schedule_retry(request_id: int, pending: Dictionary, reason: String, response_code: int = 0, result: int = -1, body_preview: String = "") -> bool:
	var attempt := maxi(1, int(pending.get("attempt", 1)))
	var max_retries := maxi(0, int(pending.get("max_retries", DEFAULT_MAX_RETRIES)))
	if attempt > max_retries:
		return false
	var next_attempt := attempt + 1
	var base_delay_sec := maxf(0.0, float(pending.get("retry_delay_sec", DEFAULT_RETRY_DELAY_SEC)))
	var max_delay_sec := maxf(0.0, float(pending.get("retry_max_delay_sec", DEFAULT_RETRY_MAX_DELAY_SEC)))
	var delay_sec := _retry_delay_for_attempt(attempt, base_delay_sec, max_delay_sec)
	var retry_state := pending.duplicate(false)
	retry_state.erase("http")
	if retry_state.get("headers", []) is Array:
		retry_state["headers"] = (retry_state.get("headers", []) as Array).duplicate(true)
	if retry_state.get("payload", {}) is Dictionary:
		retry_state["payload"] = (retry_state.get("payload", {}) as Dictionary).duplicate(true)
	retry_state["attempt"] = next_attempt
	var debug_context: Dictionary = retry_state.get("debug_context", {}) if retry_state.get("debug_context", {}) is Dictionary else {}
	debug_context["attempt"] = next_attempt
	debug_context["max_retries"] = max_retries
	debug_context["last_retry_reason"] = reason
	debug_context["last_retry_response_code"] = response_code
	debug_context["last_retry_result"] = result
	retry_state["debug_context"] = debug_context.duplicate(true)
	_emit_protocol_event(request_id, {
		"type": "retry",
		"request_id": request_id,
		"reason": reason,
		"result": result,
		"result_label": _request_result_label(result) if result >= 0 else "",
		"response_code": response_code,
		"attempt": attempt,
		"next_attempt": next_attempt,
		"max_attempts": max_retries + 1,
		"delay_sec": delay_sec,
		"url": String(pending.get("url", "")),
		"body_preview": body_preview,
	})
	print("[ModelChatClient] retry scheduled id=%d reason=%s attempt=%d/%d next=%d delay=%.2f url=%s" % [request_id, reason, attempt, max_retries + 1, next_attempt, delay_sec, String(pending.get("url", ""))])
	if delay_sec <= 0.0:
		call_deferred("_retry_chat_request_deferred", retry_state)
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var timer := tree.create_timer(delay_sec)
	timer.timeout.connect(_retry_chat_request_deferred.bind(retry_state))
	return true


func _retry_chat_request_deferred(request_state: Dictionary) -> void:
	var request_id := int(request_state.get("request_id", 0))
	var err := _start_chat_request(request_state)
	if err != OK:
		var debug_context: Dictionary = request_state.get("debug_context", {}) if request_state.get("debug_context", {}) is Dictionary else {}
		var url := String(request_state.get("url", ""))
		push_warning("[ModelChatClient] retry request create failed id=%d err=%s url=%s" % [request_id, err, url])
		_log_model_call_error_io("retry_request_create_failed", request_id, debug_context, "")
		_emit_final_result(request_id, false, "", _request_start_error(err, url), {}, debug_context, "")


func _emit_completed(request_id: int, ok: bool, content: String, error: String) -> void:
	completed.emit(request_id, ok, content, error)


func _emit_protocol_event(request_id: int, event: Dictionary) -> void:
	if event.is_empty():
		return
	protocol_event.emit(request_id, event.duplicate(true))


func _emit_chunk_event(request_id: int, kind: String, text: String) -> void:
	_emit_protocol_event(request_id, {
		"type": "chunk",
		"kind": kind,
		"text": text,
	})


func _emit_final_result(request_id: int, ok: bool, content: String, error: String, diagnostic: Dictionary = {}, debug_context: Dictionary = {}, raw_text: String = "") -> void:
	var result := {
		"type": "final",
		"request_id": request_id,
		"ok": ok,
		"text": content,
		"error": error,
		"raw_text": raw_text,
		"output_type": String(debug_context.get("output_type", OUTPUT_TYPE_TEXT)),
		"transport_mode": String(debug_context.get("transport_mode", TRANSPORT_MODE_SYNC)),
		"reasoning_mode": String(debug_context.get("reasoning_mode", REASONING_MODE_OFF)),
		"output_adapter": String(debug_context.get("output_adapter", FORMT_ADAPTER_AUTO)),
		"reason_adapter": String(debug_context.get("reason_adapter", REASON_ADAPTER_AUTO)),
		"provider": String(debug_context.get("provider", "")),
		"model": String(debug_context.get("model", "")),
		"purpose": String(debug_context.get("purpose", "")),
		"attempt": int(debug_context.get("attempt", 1)),
		"max_retries": int(debug_context.get("max_retries", DEFAULT_MAX_RETRIES)),
		"diagnostic": diagnostic.duplicate(true) if diagnostic is Dictionary else {},
	}
	if diagnostic is Dictionary:
		var diag: Dictionary = diagnostic
		result["reasoning_text"] = String(diag.get("reasoning_output", ""))
		result["has_text_output"] = bool(diag.get("has_text_output", false))
		result["has_reasoning_output"] = bool(diag.get("has_reasoning_output", false))
		result["has_stream_output"] = bool(diag.get("has_stream_output", false))
		result["response_code"] = int(diag.get("response_code", 0))
	_completed_results[request_id] = result.duplicate(true)
	_emit_protocol_event(request_id, result)
	_emit_completed(request_id, ok, content, error)


func _emit_final_result_deferred(request_id: int, ok: bool, content: String, error: String, diagnostic: Dictionary = {}, debug_context: Dictionary = {}, raw_text: String = "") -> void:
	_emit_final_result(request_id, ok, content, error, diagnostic, debug_context, raw_text)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request_id: int, provider: String) -> void:
	var pending: Dictionary = _pending.get(request_id, {})
	_pending.erase(request_id)
	var http := pending.get("http") as HTTPRequest
	var url := String(pending.get("url", ""))
	var model := String(pending.get("model", ""))
	var reasoning := bool(pending.get("reasoning", false))
	var connection_test := bool(pending.get("connection_test", false))
	var attempt := maxi(1, int(pending.get("attempt", 1)))
	var max_retries := maxi(0, int(pending.get("max_retries", DEFAULT_MAX_RETRIES)))
	var debug_context: Dictionary = pending.get("debug_context", {}) if pending.get("debug_context", {}) is Dictionary else {}
	debug_context["attempt"] = attempt
	debug_context["max_retries"] = max_retries
	var stream_requested := String(debug_context.get("transport_mode", TRANSPORT_MODE_SYNC)) == TRANSPORT_MODE_STREAM
	if http != null:
		http.queue_free()
	var text := body.get_string_from_utf8()
	print("[ModelChatClient] response id=%d provider=%s model=%s result=%s code=%d attempt=%d/%d url=%s bytes=%d body=%s" % [request_id, provider, model, result, response_code, attempt, max_retries + 1, url, body.size(), _response_preview(text)])
	if result != HTTPRequest.RESULT_SUCCESS:
		if _retryable_request_result(result) and _schedule_retry(request_id, pending, "request_result_%s" % _request_result_label(result), 0, result, _response_preview(text)):
			return
		push_warning("[ModelChatClient] request failed id=%d result=%s label=%s url=%s" % [request_id, result, _request_result_label(result), url])
		_log_model_call_error_io("request_failed_%s" % _request_result_label(result), request_id, debug_context, text)
		_emit_final_result(request_id, false, "", _request_error_with_attempts(result, url, attempt), {}, debug_context, text)
		return
	if response_code < 200 or response_code >= 300:
		if _retryable_http_response_code(response_code) and _schedule_retry(request_id, pending, "http_%d" % response_code, response_code, result, _response_preview(text)):
			return
		push_warning("[ModelChatClient] response http error id=%d code=%d url=%s body=%s" % [request_id, response_code, url, _response_preview(text)])
		_print_log_chunks("[ModelChatClient][http_error_body] id=%d" % request_id, text)
		_log_model_call_error_io("http_error_%d" % response_code, request_id, debug_context, text)
		var http_diagnostic := _response_diagnostic(provider, reasoning, stream_requested, false, {}, "", "", text, response_code)
		http_diagnostic["attempt"] = attempt
		http_diagnostic["max_retries"] = max_retries
		_emit_diagnostic_ready(request_id, http_diagnostic)
		_emit_final_result(request_id, false, "", _http_error_with_attempts(provider, url, text, response_code, attempt), http_diagnostic, debug_context, text)
		return
	if stream_requested:
		var stream_result := _parse_stream_response(request_id, provider, text)
		var stream_diag := _response_diagnostic(provider, reasoning, true, stream_result.get("ok", false), stream_result.get("parsed", {}), String(stream_result.get("content", "")), String(stream_result.get("reasoning_content", "")), text, response_code)
		_emit_diagnostic_ready(request_id, stream_diag)
		if not bool(stream_result.get("ok", false)):
			_log_model_call_error_io("stream_parse_failed", request_id, debug_context, text)
			_emit_final_result(request_id, false, "", String(stream_result.get("error", "模型流式响应解析失败")), stream_diag, debug_context, text)
			return
		var stream_content := String(stream_result.get("content", "")).strip_edges()
		if stream_content == "":
			var stream_reasoning := String(stream_result.get("reasoning_content", "")).strip_edges()
			if connection_test and reasoning and stream_reasoning != "":
				print("[ModelChatClient] stream reasoning-only response accepted for connection test id=%d provider=%s model=%s chars=%d preview=%s" % [request_id, provider, model, stream_reasoning.length(), _response_preview(stream_reasoning)])
				_emit_final_result(request_id, true, "reasoning 已响应", "", stream_diag, debug_context, text)
				return
			_log_model_call_error_io("stream_empty_content", request_id, debug_context, text)
			_emit_final_result(request_id, false, "", "模型流式响应内容为空：url=%s body=%s" % [url, _response_preview(text)], stream_diag, debug_context, text)
			return
		print("[ModelChatClient] parsed stream content id=%d provider=%s model=%s chars=%d preview=%s" % [request_id, provider, model, stream_content.length(), _response_preview(stream_content)])
		_emit_final_result(request_id, true, stream_content, "", stream_diag, debug_context, text)
		return
	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		push_warning("[ModelChatClient] response parse failed id=%d url=%s error=%s body=%s" % [request_id, url, json.get_error_message(), _response_preview(text)])
		_print_log_chunks("[ModelChatClient][parse_failed_body] id=%d" % request_id, text)
		_log_model_call_error_io("response_parse_failed", request_id, debug_context, text)
		var parse_diagnostic := _response_diagnostic(provider, reasoning, false, false, {}, "", "", text, response_code)
		_emit_diagnostic_ready(request_id, parse_diagnostic)
		_emit_final_result(request_id, false, "", "%s模型响应不是 JSON：url=%s parse=%s body=%s" % [_endpoint_hint(provider, url, text), url, json.get_error_message(), _response_preview(text)], parse_diagnostic, debug_context, text)
		return
	var parsed = json.data
	if not (parsed is Dictionary):
		push_warning("[ModelChatClient] response is not object id=%d url=%s body=%s" % [request_id, url, _response_preview(text)])
		_print_log_chunks("[ModelChatClient][non_object_body] id=%d" % request_id, text)
		_log_model_call_error_io("response_not_object", request_id, debug_context, text)
		var object_diagnostic := _response_diagnostic(provider, reasoning, false, false, {}, "", "", text, response_code)
		_emit_diagnostic_ready(request_id, object_diagnostic)
		_emit_final_result(request_id, false, "", "%s模型响应不是 JSON 对象：url=%s body=%s" % [_endpoint_hint(provider, url, text), url, _response_preview(text)], object_diagnostic, debug_context, text)
		return
	var raw_content := _parse_content(provider, parsed)
	var content := _normalize_json_output_content(raw_content, debug_context)
	var reasoning_content := _parse_reasoning_content(provider, parsed)
	var response_diagnostic := _response_diagnostic(provider, reasoning, false, true, parsed, content, reasoning_content, text, response_code)
	if content != raw_content:
		response_diagnostic["content_normalized"] = true
		response_diagnostic["content_normalization"] = "markdown_json_fence"
		response_diagnostic["raw_text_output"] = raw_content
	_emit_diagnostic_ready(request_id, response_diagnostic)
	if reasoning_content.strip_edges() != "":
		_emit_chunk_event(request_id, "reasoning", reasoning_content)
	if content.strip_edges() != "":
		_emit_chunk_event(request_id, "text", content)
	if content.strip_edges() == "":
		var debug_reason_adapter := _normalize_reason_adapter(String(debug_context.get("reason_adapter", REASON_ADAPTER_AUTO)))
		if connection_test and reasoning_content.strip_edges() != "" and (reasoning or debug_reason_adapter == REASON_ADAPTER_MINIMAX_REASONING_SPLIT):
			print("[ModelChatClient] reasoning-only response accepted for connection test id=%d provider=%s model=%s reasoning=%s reason_adapter=%s chars=%d preview=%s" % [request_id, provider, model, str(reasoning), debug_reason_adapter, reasoning_content.length(), _response_preview(reasoning_content)])
			_emit_final_result(request_id, true, "reasoning 已响应", "", response_diagnostic, debug_context, text)
			return
		push_warning("[ModelChatClient] parsed empty content id=%d provider=%s model=%s reasoning=%s connection_test=%s url=%s keys=%s body=%s" % [request_id, provider, model, reasoning, connection_test, url, _dictionary_keys_text(parsed), _response_preview(text)])
		_print_log_chunks("[ModelChatClient][empty_content_body] id=%d" % request_id, text)
		_log_model_call_error_io("empty_content", request_id, debug_context, text)
		_emit_final_result(request_id, false, "", "模型响应内容为空：url=%s body=%s" % [url, _response_preview(text)], response_diagnostic, debug_context, text)
		return
	print("[ModelChatClient] parsed content id=%d provider=%s model=%s chars=%d preview=%s" % [request_id, provider, model, content.length(), _response_preview(content)])
	_emit_final_result(request_id, true, content, "", response_diagnostic, debug_context, text)


func _payload(provider: String, model: String, messages: Array, temperature: float, reasoning: bool = false, max_output_tokens: int = 0, options: Dictionary = {}) -> Dictionary:
	var normalized_messages := _normalize_messages(messages)
	var response_schema := _response_schema_from_request({}, options)
	var output_adapter := _output_adapter_from_request({}, options)
	var reason_adapter := _reason_adapter_from_request({}, options)
	var stream := _stream_requested(options)
	var output_token_limit := 0 if reasoning else max_output_tokens
	if provider == "ollama":
		var ollama_options := {
			"temperature": temperature,
		}
		_apply_ollama_model_params(ollama_options, options)
		if output_token_limit > 0:
			ollama_options["num_predict"] = output_token_limit
		var ollama_payload := {
			"model": model,
			"messages": normalized_messages,
			"stream": stream,
			"options": ollama_options,
		}
		if _output_adapter_matches(output_adapter, FORMT_ADAPTER_OLLAMA_FORMAT_SCHEMA):
			_apply_ollama_response_schema(ollama_payload, response_schema)
		_apply_payload_overrides(ollama_payload, options)
		if reasoning:
			_clear_output_token_limit_payload(ollama_payload, provider)
		return ollama_payload
	if provider == "anthropic":
		var anthropic_payload := {
			"model": model,
			"messages": _anthropic_messages(normalized_messages),
			"temperature": temperature,
		}
		if stream:
			anthropic_payload["stream"] = true
		_apply_anthropic_model_params(anthropic_payload, options)
		if output_token_limit > 0:
			anthropic_payload["max_tokens"] = output_token_limit
		var system_prompt := _system_prompt(normalized_messages)
		if system_prompt != "":
			anthropic_payload["system"] = system_prompt
		if _output_adapter_matches(output_adapter, FORMT_ADAPTER_ANTHROPIC_TOOL):
			_apply_anthropic_response_schema(anthropic_payload, response_schema)
		_apply_payload_overrides(anthropic_payload, options)
		if reasoning:
			_clear_output_token_limit_payload(anthropic_payload, provider)
		return anthropic_payload
	if provider == "gemini":
		var generation_config := {
			"temperature": temperature,
		}
		_apply_gemini_model_params(generation_config, options)
		if output_token_limit > 0:
			generation_config["maxOutputTokens"] = output_token_limit
		if _output_adapter_matches(output_adapter, FORMT_ADAPTER_GEMINI_JSON_SCHEMA):
			_apply_gemini_response_schema(generation_config, response_schema)
		var gemini_payload := {
			"contents": _gemini_contents(normalized_messages),
			"generationConfig": generation_config,
		}
		var instruction := _gemini_system_instruction(normalized_messages)
		if not instruction.is_empty():
			gemini_payload["systemInstruction"] = instruction
		_apply_payload_overrides(gemini_payload, options)
		if reasoning:
			_clear_output_token_limit_payload(gemini_payload, provider)
		return gemini_payload
	var payload := {
		"model": model,
		"messages": normalized_messages,
		"temperature": temperature,
	}
	if stream:
		payload["stream"] = true
	_apply_openai_model_params(payload, options)
	if output_token_limit > 0:
		payload["max_tokens"] = output_token_limit
	_apply_reasoning_adapter_payload(payload, response_schema, reason_adapter, model, reasoning)
	if _output_adapter_matches(output_adapter, FORMT_ADAPTER_OPENAI_JSON_SCHEMA):
		_apply_openai_response_schema(payload, response_schema)
	_apply_payload_overrides(payload, options)
	if reasoning:
		_clear_output_token_limit_payload(payload, provider)
	return payload


func _clear_output_token_limit_payload(payload: Dictionary, provider: String) -> void:
	match provider:
		"ollama":
			var ollama_options = payload.get("options", {})
			if ollama_options is Dictionary:
				(ollama_options as Dictionary).erase("num_predict")
		"gemini":
			var generation_config = payload.get("generationConfig", {})
			if generation_config is Dictionary:
				(generation_config as Dictionary).erase("maxOutputTokens")
		_:
			payload.erase("max_tokens")
			payload.erase("max_completion_tokens")


func _messages_from_request(request: Dictionary) -> Array:
	var value = request.get("messages", request.get("prompt", []))
	if value is Array:
		return _normalize_messages(value as Array)
	if value is String:
		return [{"role": "user", "content": String(value)}]
	return []


func _normalize_messages(messages: Array) -> Array:
	var result := []
	for message in messages:
		if message is Dictionary:
			result.append({
				"role": String((message as Dictionary).get("role", "user")),
				"content": String((message as Dictionary).get("content", "")),
			})
		elif message is String:
			result.append({
				"role": "user",
				"content": String(message),
			})
	return result


func _request_options_from_request(request: Dictionary) -> Dictionary:
	var options := {}
	var nested = request.get("options", {})
	if nested is Dictionary:
		for key in (nested as Dictionary).keys():
			options[key] = (nested as Dictionary).get(key)
	for key in [
		"top_p",
		"topP",
		"top_k",
		"topK",
		"presence_penalty",
		"frequency_penalty",
		"repetition_penalty",
		"stop",
		"stop_sequences",
		"stopSequences",
		"seed",
		"candidate_count",
		"candidateCount",
		"extra_payload",
		"payload_overrides",
		"model_params",
		"generation_config",
		"ollama_options",
		"output_adapter",
		"formt_adapter",
		"reason_adapter",
		"transport_mode",
		"output_type",
		"stream",
		"max_retries",
		"retry_count",
		"retry_delay_sec",
		"retry_max_delay_sec",
	]:
		if request.has(key) and not options.has(key):
			options[key] = request.get(key)
	var output_adapter := _normalize_output_adapter(String(options.get("output_adapter", options.get("formt_adapter", request.get("output_adapter", request.get("formt_adapter", ""))))))
	if output_adapter != FORMT_ADAPTER_AUTO or options.has("output_adapter") or options.has("formt_adapter") or request.has("output_adapter") or request.has("formt_adapter"):
		options["output_adapter"] = output_adapter
	var reason_adapter := _normalize_reason_adapter(String(options.get("reason_adapter", request.get("reason_adapter", ""))))
	if reason_adapter != REASON_ADAPTER_AUTO or options.has("reason_adapter") or request.has("reason_adapter"):
		options["reason_adapter"] = reason_adapter
	var schema := _response_schema_from_request(request, options)
	if not schema.is_empty():
		options["response_schema"] = schema
	if _transport_mode_from_request(request, options) == TRANSPORT_MODE_STREAM:
		options["stream"] = true
	return options


func _max_retries_from_request(request: Dictionary, options: Dictionary = {}) -> int:
	var value = options.get("max_retries", options.get("retry_count", request.get("max_retries", request.get("retry_count", DEFAULT_MAX_RETRIES))))
	return clampi(int(value), 0, 10)


func _retry_delay_from_request(request: Dictionary, options: Dictionary = {}) -> float:
	var value = options.get("retry_delay_sec", request.get("retry_delay_sec", DEFAULT_RETRY_DELAY_SEC))
	return clampf(float(value), 0.0, 30.0)


func _retry_max_delay_from_request(request: Dictionary, options: Dictionary = {}) -> float:
	var value = options.get("retry_max_delay_sec", request.get("retry_max_delay_sec", DEFAULT_RETRY_MAX_DELAY_SEC))
	return clampf(float(value), 0.0, 60.0)


func _response_schema_from_request(request: Dictionary, options: Dictionary = {}) -> Dictionary:
	var value = options.get("response_schema", options.get("schema", request.get("response_schema", request.get("schema", {}))))
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _output_adapter_from_request(request: Dictionary, options: Dictionary = {}) -> String:
	return _normalize_output_adapter(String(options.get("output_adapter", options.get("formt_adapter", request.get("output_adapter", request.get("formt_adapter", ""))))))


func _reason_adapter_from_request(request: Dictionary, options: Dictionary = {}) -> String:
	return _normalize_reason_adapter(String(options.get("reason_adapter", request.get("reason_adapter", ""))))


func _transport_mode_from_request(request: Dictionary, options: Dictionary = {}) -> String:
	var value := String(request.get("transport_mode", options.get("transport_mode", ""))).strip_edges().to_lower()
	if value == TRANSPORT_MODE_STREAM:
		return TRANSPORT_MODE_STREAM
	if value == TRANSPORT_MODE_SYNC:
		return TRANSPORT_MODE_SYNC
	return TRANSPORT_MODE_STREAM if bool(options.get("stream", request.get("stream", false))) else TRANSPORT_MODE_SYNC


func _output_type_from_request(request: Dictionary, options: Dictionary = {}, response_schema: Dictionary = {}) -> String:
	var value := String(request.get("output_type", options.get("output_type", ""))).strip_edges().to_lower()
	if value == OUTPUT_TYPE_TEXT:
		return OUTPUT_TYPE_TEXT
	if value == OUTPUT_TYPE_JSON:
		return OUTPUT_TYPE_JSON
	return OUTPUT_TYPE_JSON if not response_schema.is_empty() else OUTPUT_TYPE_TEXT


func _reasoning_mode_from_request(request: Dictionary) -> String:
	var value := String(request.get("reasoning_mode", "")).strip_edges().to_lower()
	if value == REASONING_MODE_ON:
		return REASONING_MODE_ON
	if value == REASONING_MODE_OFF:
		return REASONING_MODE_OFF
	return REASONING_MODE_ON if bool(request.get("reasoning", false)) else REASONING_MODE_OFF


func _stream_requested(options: Dictionary) -> bool:
	return _transport_mode_from_request({}, options) == TRANSPORT_MODE_STREAM


func _normalize_output_adapter(value: String) -> String:
	return _adapter_registry.normalize_output_adapter(value)


func _normalize_formt_adapter(value: String) -> String:
	return _normalize_output_adapter(value)


func _normalize_reason_adapter(value: String) -> String:
	return _adapter_registry.normalize_reason_adapter(value)


func _output_adapter_matches(adapter: String, concrete_adapter: String) -> bool:
	var normalized := _normalize_output_adapter(adapter)
	return normalized == FORMT_ADAPTER_AUTO or normalized == concrete_adapter


func _apply_openai_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	if response_schema.is_empty():
		return
	payload["response_format"] = {
		"type": "json_schema",
		"json_schema": {
			"name": _response_schema_name(response_schema),
			"strict": bool(response_schema.get("strict", true)),
			"schema": _response_schema_body(response_schema),
		},
	}


func _apply_openai_compat_payload_adjustments(payload: Dictionary, provider: String, endpoint: String, response_schema: Dictionary, reasoning: bool, formt_adapter: String = FORMT_ADAPTER_AUTO, reason_adapter: String = REASON_ADAPTER_AUTO) -> void:
	if provider != "openai":
		return
	var adapter := _normalize_output_adapter(formt_adapter)
	var thinking_adapter := _normalize_reason_adapter(reason_adapter)
	_apply_openai_compat_reasoning_payload(payload, endpoint, reasoning, thinking_adapter)
	_apply_kimi_moonshot_text_thinking_payload(payload, response_schema, reasoning, thinking_adapter)
	var model := String(payload.get("model", ""))
	var effective_adapter := adapter
	if effective_adapter == FORMT_ADAPTER_AUTO:
		effective_adapter = _default_openai_formt_adapter(model)
	if effective_adapter != FORMT_ADAPTER_AUTO:
		_apply_explicit_openai_formt_adapter(payload, effective_adapter, response_schema, reasoning, thinking_adapter, model)


func _default_openai_formt_adapter(model: String) -> String:
	return _adapter_registry.default_openai_formt_adapter(model)


func _apply_explicit_openai_formt_adapter(payload: Dictionary, adapter: String, response_schema: Dictionary, reasoning: bool, reason_adapter: String = REASON_ADAPTER_AUTO, model: String = "") -> void:
	match adapter:
		FORMT_ADAPTER_NONE:
			_clear_structured_output_payload(payload)
		FORMT_ADAPTER_OPENAI_JSON_SCHEMA:
			if not response_schema.is_empty():
				_apply_openai_response_schema(payload, response_schema)
		FORMT_ADAPTER_OPENAI_JSON_OBJECT:
			if not response_schema.is_empty():
				if _is_deepseek_model_name(model):
					_apply_deepseek_response_schema(payload, response_schema)
				elif _is_kimi_model_name(model):
					_apply_kimi_response_schema(payload, response_schema)
				else:
					_apply_openai_json_object_response_schema(payload, response_schema)
		FORMT_ADAPTER_OPENAI_TOOL_FORCED:
			if not response_schema.is_empty():
				_apply_openai_tool_response_schema(payload, response_schema)
		FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL:
			if not response_schema.is_empty():
				if _is_minimax_model_name(model):
					_apply_minimax_response_schema(payload, response_schema)
				else:
					_apply_openai_tool_optional_response_schema(payload, response_schema)
		FORMT_ADAPTER_OPENAI_MIMO_TOOL:
			if not response_schema.is_empty():
				_apply_openai_tool_response_schema(payload, response_schema)
			if _normalize_reason_adapter(reason_adapter) == REASON_ADAPTER_MIMO_CHAT_TEMPLATE or _normalize_reason_adapter(reason_adapter) == REASON_ADAPTER_AUTO:
				_apply_mimo_chat_template_payload(payload, reasoning)


func _clear_structured_output_payload(payload: Dictionary) -> void:
	payload.erase("response_format")
	payload.erase("tools")
	payload.erase("tool_choice")
	payload.erase("parallel_tool_calls")


func _apply_mimo_chat_template_payload(payload: Dictionary, reasoning: bool) -> void:
	var template_kwargs = payload.get("chat_template_kwargs", {})
	if not (template_kwargs is Dictionary):
		template_kwargs = {}
	template_kwargs["enable_thinking"] = reasoning
	payload["chat_template_kwargs"] = template_kwargs
	if not reasoning:
		payload["include_reasoning"] = false


func _apply_reasoning_adapter_payload(payload: Dictionary, response_schema: Dictionary, reason_adapter: String, model: String, reasoning: bool) -> void:
	var adapter := _normalize_reason_adapter(reason_adapter)
	match adapter:
		REASON_ADAPTER_NATIVE:
			_apply_kimi_reasoning_control(payload, model, response_schema, false)
		REASON_ADAPTER_OPENAI_REASONING_EFFORT:
			if reasoning:
				payload["reasoning_effort"] = "medium"
		REASON_ADAPTER_DEEPSEEK_THINKING:
			_apply_deepseek_thinking_control(payload, model, reasoning)
		REASON_ADAPTER_GLM_THINKING:
			_apply_glm_thinking_control(payload, model, reasoning)
		REASON_ADAPTER_ARK_THINKING:
			_apply_ark_thinking_control(payload, model, reasoning)
		REASON_ADAPTER_MINIMAX_REASONING_SPLIT:
			_apply_minimax_reasoning_split_payload(payload, model)
		REASON_ADAPTER_MIMO_CHAT_TEMPLATE:
			_apply_mimo_chat_template_payload(payload, reasoning)
		REASON_ADAPTER_KIMI_THINKING_CONTROL:
			_apply_kimi_reasoning_control(payload, model, response_schema, reasoning)
		REASON_ADAPTER_AUTO:
			if _is_deepseek_model_name(model):
				_apply_deepseek_thinking_control(payload, model, reasoning)
			elif _is_glm_model_name(model):
				_apply_glm_thinking_control(payload, model, reasoning)
			elif _is_doubao_model_name(model):
				_apply_ark_thinking_control(payload, model, reasoning)
			elif _is_minimax_model_name(model):
				_apply_minimax_reasoning_split_payload(payload, model)
			elif reasoning:
				payload["reasoning_effort"] = "medium"
			else:
				_apply_kimi_reasoning_control(payload, model, response_schema, false)


func _apply_minimax_reasoning_split_payload(payload: Dictionary, model: String) -> void:
	if not _is_minimax_model_name(model):
		return
	payload["reasoning_split"] = true


func _apply_openai_compat_reasoning_payload(payload: Dictionary, endpoint: String, reasoning: bool, reason_adapter: String = REASON_ADAPTER_AUTO) -> void:
	if not reasoning:
		return
	if _normalize_reason_adapter(reason_adapter) != REASON_ADAPTER_OPENAI_REASONING_EFFORT and _normalize_reason_adapter(reason_adapter) != REASON_ADAPTER_AUTO:
		return
	if not payload.has("reasoning_effort"):
		return
	if _is_openai_native_endpoint(endpoint):
		return
	payload.erase("reasoning_effort")


func _apply_kimi_moonshot_text_thinking_payload(payload: Dictionary, response_schema: Dictionary, reasoning: bool, reason_adapter: String = REASON_ADAPTER_AUTO) -> void:
	if reasoning:
		return
	if not response_schema.is_empty():
		return
	if not _is_kimi_model_name(String(payload.get("model", ""))):
		return
	var adapter := _normalize_reason_adapter(reason_adapter)
	if adapter != REASON_ADAPTER_AUTO and adapter != REASON_ADAPTER_KIMI_THINKING_CONTROL and adapter != REASON_ADAPTER_NATIVE:
		return
	_apply_kimi_reasoning_control(payload, String(payload.get("model", "")), response_schema, false)


func _apply_kimi_reasoning_control(payload: Dictionary, model: String, response_schema: Dictionary, enabled: bool) -> void:
	if not _is_kimi_model_name(model):
		return
	if not response_schema.is_empty() and enabled:
		return
	if payload.has("thinking") and enabled:
		return
	payload["thinking"] = {"type": "enabled" if enabled else "disabled"}


func _apply_deepseek_thinking_control(payload: Dictionary, model: String, enabled: bool) -> void:
	if not _is_deepseek_model_name(model):
		return
	payload["thinking"] = {"type": "enabled" if enabled else "disabled"}
	if enabled and not payload.has("reasoning_effort"):
		payload["reasoning_effort"] = "high"
	if not enabled:
		payload.erase("reasoning_effort")


func _apply_glm_thinking_control(payload: Dictionary, model: String, enabled: bool) -> void:
	if not _is_glm_model_name(model):
		return
	payload["thinking"] = {"type": "enabled" if enabled else "disabled"}
	payload.erase("reasoning_effort")


func _apply_ark_thinking_control(payload: Dictionary, model: String, enabled: bool) -> void:
	if not _is_doubao_model_name(model):
		return
	payload["thinking"] = {"type": "enabled" if enabled else "disabled"}
	payload.erase("reasoning_effort")


func _is_openai_native_endpoint(endpoint: String) -> bool:
	var lower := endpoint.strip_edges().to_lower()
	return lower.contains("api.openai.com") or lower.contains("openai.azure.com")


func _is_xiaomi_mimo_model_name(model_name: String) -> bool:
	return _adapter_registry.is_xiaomi_mimo_model_name(model_name)


func _is_deepseek_model_name(model_name: String) -> bool:
	return _adapter_registry.is_deepseek_model_name(model_name)


func _is_doubao_model_name(model_name: String) -> bool:
	return _adapter_registry.is_doubao_model_name(model_name)


func _apply_deepseek_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	payload.erase("tools")
	payload.erase("tool_choice")
	payload.erase("parallel_tool_calls")
	payload["response_format"] = {"type": "json_object"}
	_ensure_deepseek_json_mode_prompt(payload, response_schema)


func _apply_openai_json_object_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	payload.erase("tools")
	payload.erase("tool_choice")
	payload.erase("parallel_tool_calls")
	payload["response_format"] = {"type": "json_object"}
	_ensure_openai_json_object_mode_prompt(payload, response_schema)


func _ensure_openai_json_object_mode_prompt(payload: Dictionary, response_schema: Dictionary) -> void:
	var messages = payload.get("messages", [])
	if not (messages is Array):
		return
	var prompt_messages: Array = messages
	var instruction := _openai_json_object_mode_instruction(response_schema)
	for i in range(prompt_messages.size()):
		var item = prompt_messages[i]
		if not (item is Dictionary):
			continue
		var message: Dictionary = (item as Dictionary).duplicate(true)
		if String(message.get("role", "")) != "system":
			continue
		var content := String(message.get("content", "")).strip_edges()
		if content.contains("[OpenAI JSON Object Mode]"):
			payload["messages"] = prompt_messages
			return
		message["content"] = "%s\n\n%s" % [content, instruction] if content != "" else instruction
		prompt_messages[i] = message
		payload["messages"] = prompt_messages
		return
	prompt_messages.push_front({"role": "system", "content": instruction})
	payload["messages"] = prompt_messages


func _openai_json_object_mode_instruction(response_schema: Dictionary) -> String:
	return "[OpenAI JSON Object Mode]\n当前端点使用 response_format={\"type\":\"json_object\"}。你必须只返回一个 JSON object，不要 Markdown，不要解释，不要包裹代码块。JSON object 必须符合以下 JSON Schema：\n%s" % JSON.stringify(_response_schema_body(response_schema), "\t")


func _ensure_deepseek_json_mode_prompt(payload: Dictionary, response_schema: Dictionary) -> void:
	var messages = payload.get("messages", [])
	if not (messages is Array):
		return
	var prompt_messages: Array = messages
	var instruction := _deepseek_json_mode_instruction(response_schema)
	for i in range(prompt_messages.size()):
		var item = prompt_messages[i]
		if not (item is Dictionary):
			continue
		var message: Dictionary = (item as Dictionary).duplicate(true)
		if String(message.get("role", "")) != "system":
			continue
		var content := String(message.get("content", "")).strip_edges()
		if content.contains("[DeepSeek JSON Mode]"):
			payload["messages"] = prompt_messages
			return
		message["content"] = "%s\n\n%s" % [content, instruction] if content != "" else instruction
		prompt_messages[i] = message
		payload["messages"] = prompt_messages
		return
	prompt_messages.push_front({"role": "system", "content": instruction})
	payload["messages"] = prompt_messages


func _deepseek_json_mode_instruction(response_schema: Dictionary) -> String:
	return "[DeepSeek JSON Mode]\n当前 DeepSeek 端点只支持 response_format={\"type\":\"json_object\"}。你必须只返回一个 JSON object，不要 Markdown，不要解释，不要包裹代码块。JSON object 必须符合以下 JSON Schema：\n%s" % JSON.stringify(_response_schema_body(response_schema), "\t")


func _is_glm_model_name(model_name: String) -> bool:
	return _adapter_registry.is_glm_model_name(model_name)


func _is_minimax_model_name(model_name: String) -> bool:
	return _adapter_registry.is_minimax_model_name(model_name)


func _is_kimi_model_name(model_name: String) -> bool:
	return _adapter_registry.is_kimi_model_name(model_name)


func _model_family_matches(model_name: String, family: String) -> bool:
	return _adapter_registry.model_family_matches(model_name, family)


func _apply_glm_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	_apply_openai_tool_response_schema(payload, response_schema)


func _apply_kimi_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	payload.erase("tools")
	payload.erase("tool_choice")
	payload.erase("parallel_tool_calls")
	payload["response_format"] = {"type": "json_object"}
	_ensure_kimi_json_mode_prompt(payload, response_schema)


func _ensure_kimi_json_mode_prompt(payload: Dictionary, response_schema: Dictionary) -> void:
	var messages = payload.get("messages", [])
	if not (messages is Array):
		return
	var prompt_messages: Array = messages
	var instruction := _kimi_json_mode_instruction(response_schema)
	for i in range(prompt_messages.size()):
		var item = prompt_messages[i]
		if not (item is Dictionary):
			continue
		var message: Dictionary = (item as Dictionary).duplicate(true)
		if String(message.get("role", "")) != "system":
			continue
		var content := String(message.get("content", "")).strip_edges()
		if content.contains("[Kimi JSON Mode]"):
			payload["messages"] = prompt_messages
			return
		message["content"] = "%s\n\n%s" % [content, instruction] if content != "" else instruction
		prompt_messages[i] = message
		payload["messages"] = prompt_messages
		return
	prompt_messages.push_front({"role": "system", "content": instruction})
	payload["messages"] = prompt_messages


func _kimi_json_mode_instruction(response_schema: Dictionary) -> String:
	return "[Kimi JSON Mode]\n当前 Kimi/Moonshot 模型使用 response_format={\"type\":\"json_object\"}。你必须只返回一个 JSON object，不要 Markdown，不要解释，不要包裹代码块。JSON object 必须符合以下 JSON Schema：\n%s" % JSON.stringify(_response_schema_body(response_schema), "\t")


func _apply_minimax_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	payload.erase("tool_choice")
	payload.erase("parallel_tool_calls")
	payload.erase("response_format")
	var tool_name := _openai_tool_schema_name(response_schema)
	payload["tools"] = [
		{
			"type": "function",
			"function": {
				"name": tool_name,
				"description": "结构化输出。",
				"parameters": _response_schema_body(response_schema),
			},
		},
	]
	_ensure_minimax_tool_mode_prompt(payload, response_schema, tool_name)


func _ensure_minimax_tool_mode_prompt(payload: Dictionary, response_schema: Dictionary, tool_name: String) -> void:
	var messages = payload.get("messages", [])
	if not (messages is Array):
		return
	var prompt_messages: Array = messages
	var instruction := _minimax_tool_mode_instruction(response_schema, tool_name)
	for i in range(prompt_messages.size()):
		var item = prompt_messages[i]
		if not (item is Dictionary):
			continue
		var message: Dictionary = (item as Dictionary).duplicate(true)
		if String(message.get("role", "")) != "system":
			continue
		var content := String(message.get("content", "")).strip_edges()
		if content.contains("[MiniMax Tool Mode]"):
			payload["messages"] = prompt_messages
			return
		message["content"] = "%s\n\n%s" % [content, instruction] if content != "" else instruction
		prompt_messages[i] = message
		payload["messages"] = prompt_messages
		return
	prompt_messages.push_front({"role": "system", "content": instruction})
	payload["messages"] = prompt_messages


func _minimax_tool_mode_instruction(response_schema: Dictionary, tool_name: String) -> String:
	return "[MiniMax Tool Mode]\n当前端点使用 tools 承载结构化输出。只调用工具 %s。arguments 必须符合以下 JSON Schema：\n%s" % [tool_name, JSON.stringify(_response_schema_body(response_schema), "\t")]


func _apply_openai_tool_optional_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	payload.erase("tool_choice")
	payload.erase("parallel_tool_calls")
	payload.erase("response_format")
	var tool_name := _openai_tool_schema_name(response_schema)
	payload["tools"] = [
		{
			"type": "function",
			"function": {
				"name": tool_name,
				"description": "结构化输出。",
				"parameters": _response_schema_body(response_schema),
			},
		},
	]
	_ensure_openai_tool_optional_mode_prompt(payload, response_schema, tool_name)


func _ensure_openai_tool_optional_mode_prompt(payload: Dictionary, response_schema: Dictionary, tool_name: String) -> void:
	var messages = payload.get("messages", [])
	if not (messages is Array):
		return
	var prompt_messages: Array = messages
	var instruction := _openai_tool_optional_mode_instruction(response_schema, tool_name)
	for i in range(prompt_messages.size()):
		var item = prompt_messages[i]
		if not (item is Dictionary):
			continue
		var message: Dictionary = (item as Dictionary).duplicate(true)
		if String(message.get("role", "")) != "system":
			continue
		var content := String(message.get("content", "")).strip_edges()
		if content.contains("[OpenAI Tool Optional Mode]"):
			payload["messages"] = prompt_messages
			return
		message["content"] = "%s\n\n%s" % [content, instruction] if content != "" else instruction
		prompt_messages[i] = message
		payload["messages"] = prompt_messages
		return
	prompt_messages.push_front({"role": "system", "content": instruction})
	payload["messages"] = prompt_messages


func _openai_tool_optional_mode_instruction(response_schema: Dictionary, tool_name: String) -> String:
	return "[OpenAI Tool Optional Mode]\n当前端点使用 tools 承载结构化输出。只调用工具 %s。arguments 必须符合以下 JSON Schema：\n%s" % [tool_name, JSON.stringify(_response_schema_body(response_schema), "\t")]


func _apply_openai_tool_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	var tool_name := _openai_tool_schema_name(response_schema)
	payload.erase("response_format")
	payload["tools"] = [
		{
			"type": "function",
			"function": {
				"name": tool_name,
				"description": "结构化输出。",
				"parameters": _response_schema_body(response_schema),
				"strict": bool(response_schema.get("strict", true)),
			},
		},
	]
	payload["tool_choice"] = {
		"type": "function",
		"function": {
			"name": tool_name,
		},
	}
	payload["parallel_tool_calls"] = false


func _apply_anthropic_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	if response_schema.is_empty():
		return
	var tool_name := _anthropic_response_schema_tool_name(response_schema)
	payload["tools"] = [
		{
			"name": tool_name,
			"description": "结构化输出。",
			"input_schema": _response_schema_body(response_schema),
		},
	]
	payload["tool_choice"] = {
		"type": "tool",
		"name": tool_name,
	}


func _apply_gemini_response_schema(generation_config: Dictionary, response_schema: Dictionary) -> void:
	if response_schema.is_empty():
		return
	generation_config["responseMimeType"] = "application/json"
	generation_config["responseJsonSchema"] = _gemini_response_schema_body(response_schema)


func _apply_ollama_response_schema(payload: Dictionary, response_schema: Dictionary) -> void:
	if response_schema.is_empty():
		return
	payload["format"] = _response_schema_body(response_schema)


func _apply_openai_model_params(payload: Dictionary, options: Dictionary) -> void:
	for key in ["top_p", "presence_penalty", "frequency_penalty", "seed", "stop"]:
		if options.has(key):
			payload[key] = options.get(key)
	_apply_dictionary_params(payload, options.get("model_params", {}), [
		"top_p",
		"presence_penalty",
		"frequency_penalty",
		"seed",
		"stop",
		"logit_bias",
		"user",
	])


func _apply_anthropic_model_params(payload: Dictionary, options: Dictionary) -> void:
	if options.has("top_p"):
		payload["top_p"] = options.get("top_p")
	if options.has("top_k"):
		payload["top_k"] = options.get("top_k")
	if options.has("stop_sequences"):
		payload["stop_sequences"] = options.get("stop_sequences")
	elif options.has("stop"):
		payload["stop_sequences"] = options.get("stop")
	_apply_dictionary_params(payload, options.get("model_params", {}), [
		"top_p",
		"top_k",
		"stop_sequences",
		"metadata",
	])


func _apply_gemini_model_params(generation_config: Dictionary, options: Dictionary) -> void:
	var key_map := {
		"top_p": "topP",
		"topP": "topP",
		"top_k": "topK",
		"topK": "topK",
		"candidate_count": "candidateCount",
		"candidateCount": "candidateCount",
		"stop_sequences": "stopSequences",
		"stopSequences": "stopSequences",
		"seed": "seed",
	}
	for source_key in key_map.keys():
		if options.has(source_key):
			generation_config[String(key_map[source_key])] = options.get(source_key)
	_apply_dictionary_params(generation_config, options.get("generation_config", {}), [
		"topP",
		"topK",
		"candidateCount",
		"stopSequences",
		"seed",
	])
	_apply_dictionary_params(generation_config, options.get("model_params", {}), [
		"topP",
		"topK",
		"candidateCount",
		"stopSequences",
		"seed",
	])


func _apply_ollama_model_params(ollama_options: Dictionary, options: Dictionary) -> void:
	var key_map := {
		"top_p": "top_p",
		"top_k": "top_k",
		"repetition_penalty": "repeat_penalty",
		"seed": "seed",
		"stop": "stop",
	}
	for source_key in key_map.keys():
		if options.has(source_key):
			ollama_options[String(key_map[source_key])] = options.get(source_key)
	_apply_dictionary_params(ollama_options, options.get("ollama_options", {}), [])
	_apply_dictionary_params(ollama_options, options.get("model_params", {}), [])


func _apply_payload_overrides(payload: Dictionary, options: Dictionary) -> void:
	_apply_dictionary_params(payload, options.get("payload_overrides", {}), [])
	_apply_dictionary_params(payload, options.get("extra_payload", {}), [])


func _apply_dictionary_params(target: Dictionary, value, allowed_keys: Array) -> void:
	if not (value is Dictionary):
		return
	for key in (value as Dictionary).keys():
		var text_key := String(key)
		if not allowed_keys.is_empty() and not allowed_keys.has(text_key):
			continue
		target[text_key] = (value as Dictionary).get(key)


func _response_schema_name(response_schema: Dictionary) -> String:
	var name := String(response_schema.get("name", "structured_response")).strip_edges()
	if name == "":
		name = "structured_response"
	return name


func _anthropic_response_schema_tool_name(response_schema: Dictionary) -> String:
	return _openai_tool_schema_name(response_schema)


func _openai_tool_schema_name(response_schema: Dictionary) -> String:
	var name := _response_schema_name(response_schema)
	var clean := ""
	for i in range(name.length()):
		var code := name.unicode_at(i)
		var is_digit := code >= 48 and code <= 57
		var is_upper := code >= 65 and code <= 90
		var is_lower := code >= 97 and code <= 122
		if is_digit or is_upper or is_lower or code == 45 or code == 95:
			clean += name.substr(i, 1)
		else:
			clean += "_"
	clean = clean.strip_edges()
	if clean == "":
		clean = "structured_response"
	if clean.length() > 64:
		clean = clean.substr(0, 64)
	return clean


func _response_schema_body(response_schema: Dictionary) -> Dictionary:
	var body = response_schema.get("schema", response_schema)
	if body is Dictionary:
		return (body as Dictionary).duplicate(true)
	return {}


func _gemini_response_schema_body(response_schema: Dictionary) -> Dictionary:
	var body := _response_schema_body(response_schema)
	if String(body.get("type", "")) != "object" or body.has("propertyOrdering"):
		return body
	var properties = body.get("properties", {})
	if not (properties is Dictionary):
		return body
	var ordering := []
	var required = body.get("required", [])
	if required is Array:
		for item in required:
			var key := String(item)
			if (properties as Dictionary).has(key) and not ordering.has(key):
				ordering.append(key)
	for key in (properties as Dictionary).keys():
		var text_key := String(key)
		if not ordering.has(text_key):
			ordering.append(text_key)
	if not ordering.is_empty():
		body["propertyOrdering"] = ordering
	return body


func _max_output_tokens(profile: Dictionary, requested: int) -> int:
	if requested > 0:
		return requested
	if profile.has("max_output"):
		return maxi(1, int(profile.get("max_output", 4096)))
	return 0


func _effective_max_output_tokens(profile: Dictionary, requested: int, reasoning: bool) -> int:
	if reasoning:
		return 0
	return _max_output_tokens(profile, requested)


func _parse_content(provider: String, json: Dictionary) -> String:
	if provider == "ollama":
		var message = json.get("message", {})
		if message is Dictionary:
			return String(message.get("content", ""))
		return ""
	if provider == "anthropic":
		return _parse_anthropic_content(json)
	if provider == "gemini":
		return _parse_gemini_content(json)
	var choices = json.get("choices", [])
	if choices is Array and not choices.is_empty() and choices[0] is Dictionary:
		var message = choices[0].get("message", {})
		if message is Dictionary:
			var tool_content := _parse_openai_tool_call_content(message as Dictionary)
			if tool_content != "":
				return tool_content
			return String(message.get("content", ""))
	return ""


func _parse_reasoning_content(provider: String, json: Dictionary) -> String:
	if provider == "ollama":
		var message = json.get("message", {})
		if message is Dictionary:
			return String(message.get("reasoning_content", message.get("thinking", "")))
		return ""
	if provider == "anthropic":
		var content = json.get("content", [])
		if content is Array:
			var parts := []
			for item in content:
				if item is Dictionary:
					var type := String(item.get("type", ""))
					if type == "thinking" or type == "reasoning":
						var text := String(item.get("text", item.get("thinking", ""))).strip_edges()
						if text != "":
							parts.append(text)
			return "\n".join(parts)
		return ""
	if provider == "gemini":
		var candidates = json.get("candidates", [])
		if candidates is Array and not candidates.is_empty() and candidates[0] is Dictionary:
			var content = candidates[0].get("content", {})
			if content is Dictionary:
				var parts = content.get("parts", [])
				if parts is Array:
					var texts := []
					for part in parts:
						if part is Dictionary and bool(part.get("thought", false)):
							var text := String(part.get("text", "")).strip_edges()
							if text != "":
								texts.append(text)
					return "\n".join(texts)
		return ""
	var choices = json.get("choices", [])
	if choices is Array and not choices.is_empty() and choices[0] is Dictionary:
		var message = choices[0].get("message", {})
		if message is Dictionary:
			var message_dict := message as Dictionary
			var direct_reasoning := String(message_dict.get("reasoning_content", message_dict.get("reasoning", ""))).strip_edges()
			if direct_reasoning != "":
				return direct_reasoning
			return _parse_openai_reasoning_details(message_dict.get("reasoning_details", []))
	return ""


func _parse_openai_reasoning_details(value) -> String:
	if value is String:
		return String(value).strip_edges()
	if not (value is Array):
		return ""
	var parts := []
	for item in value:
		var text := _parse_openai_reasoning_detail_item(item)
		if text != "":
			parts.append(text)
	return "\n".join(parts)


func _parse_openai_reasoning_detail_item(value) -> String:
	if value is String:
		return String(value).strip_edges()
	if value is Array:
		var parts := []
		for item in value:
			var text := _parse_openai_reasoning_detail_item(item)
			if text != "":
				parts.append(text)
		return "\n".join(parts)
	if not (value is Dictionary):
		return ""
	var detail := value as Dictionary
	for key in ["text", "reasoning", "reasoning_content", "content", "summary"]:
		var direct_value = detail.get(key, null)
		if direct_value is String and String(direct_value).strip_edges() != "":
			return String(direct_value).strip_edges()
		if direct_value is Array:
			var nested_text := _parse_openai_reasoning_detail_item(direct_value)
			if nested_text != "":
				return nested_text
	var inner_text := _parse_openai_reasoning_detail_item(detail.get("text", []))
	if inner_text != "":
		return inner_text
	var inner_content := _parse_openai_reasoning_detail_item(detail.get("content", []))
	if inner_content != "":
		return inner_content
	return ""


func _parse_openai_tool_call_content(message: Dictionary) -> String:
	var tool_calls = message.get("tool_calls", [])
	if tool_calls is Array and not (tool_calls as Array).is_empty():
		for tool_call in tool_calls:
			if not (tool_call is Dictionary):
				continue
			var function_call = (tool_call as Dictionary).get("function", {})
			if not (function_call is Dictionary):
				continue
			var arguments = (function_call as Dictionary).get("arguments", "")
			if arguments is Dictionary:
				return JSON.stringify(arguments)
			var text := String(arguments).strip_edges()
			if text != "":
				return text
	var legacy_call = message.get("function_call", {})
	if legacy_call is Dictionary:
		var legacy_arguments = (legacy_call as Dictionary).get("arguments", "")
		if legacy_arguments is Dictionary:
			return JSON.stringify(legacy_arguments)
		return String(legacy_arguments).strip_edges()
	return ""


func _normalize_json_output_content(content: String, debug_context: Dictionary) -> String:
	if String(debug_context.get("output_type", OUTPUT_TYPE_TEXT)) != OUTPUT_TYPE_JSON:
		return content
	var text := content.strip_edges()
	if text.begins_with("{") and text.ends_with("}"):
		return text
	var fenced := _strict_markdown_json_fence_inner(text)
	if fenced.begins_with("{") and fenced.ends_with("}"):
		return fenced
	return content


func _strict_markdown_json_fence_inner(text: String) -> String:
	var clean := text.strip_edges()
	if not clean.begins_with("```"):
		return ""
	var first_line_end := clean.find("\n")
	if first_line_end < 0:
		return ""
	var opening := clean.substr(0, first_line_end).strip_edges().to_lower()
	if opening != "```" and opening != "```json":
		return ""
	var closing_start := clean.rfind("```")
	if closing_start <= first_line_end:
		return ""
	var trailing := clean.substr(closing_start + 3).strip_edges()
	if trailing != "":
		return ""
	return clean.substr(first_line_end + 1, closing_start - first_line_end - 1).strip_edges()


func _response_preview(text: String) -> String:
	var clean := text.strip_edges().replace("\r", " ").replace("\n", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.length() > 240:
		return "%s..." % clean.substr(0, 237)
	return clean


func _endpoint_hint(provider: String, url: String, body: String = "") -> String:
	if provider != "openai":
		return ""
	var lower_url := url.to_lower()
	var lower_body := body.strip_edges().to_lower()
	if lower_url.contains("/v1/"):
		return ""
	if lower_body.begins_with("<!doctype html") or lower_body.begins_with("<html") or lower_body.contains("<title>"):
		return "BaseUrl 可能缺少 /v1；"
	return ""


func _model_call_debug_context(request_id: int, request: Dictionary, provider: String, endpoint: String, url: String, model: String, headers: Array, messages: Array, response_schema: Dictionary, payload: Dictionary, output_tokens: int, temperature: float, timeout_sec: float, reasoning: bool, connection_test: bool) -> Dictionary:
	var purpose := String(request.get("purpose", request.get("module", request.get("debug_label", "")))).strip_edges()
	var request_options := _request_options_from_request(request)
	return {
		"request_id": request_id,
		"purpose": purpose,
		"provider": provider,
		"endpoint": endpoint,
		"url": url,
		"model": model,
		"transport_mode": _transport_mode_from_request(request, request_options),
		"output_type": _output_type_from_request(request, request_options, response_schema),
		"reasoning_mode": _reasoning_mode_from_request(request),
		"output_adapter": _output_adapter_from_request(request, request_options),
		"reason_adapter": _reason_adapter_from_request(request, request_options),
		"api_key": _api_key_state(String(request.get("api_key", ""))),
		"api_key_debug": _api_key_debug(String(request.get("api_key", ""))),
		"timeout_sec": timeout_sec,
		"temperature": temperature,
		"output_tokens": output_tokens,
		"reasoning": reasoning,
		"connection_test": connection_test,
		"headers": _headers_debug(headers),
		"request_options": request_options.duplicate(true),
		"payload_schema": _payload_schema_state(payload),
		"message_count": messages.size(),
		"messages": messages.duplicate(true),
		"response_schema": response_schema.duplicate(true),
		"payload": payload.duplicate(true),
	}


func _log_model_call_error_io(reason: String, request_id: int, debug_context: Dictionary, output: String) -> void:
	var messages = debug_context.get("messages", [])
	var prompt_text := JSON.stringify(messages, "\t") if messages is Array else "[]"
	var schema = debug_context.get("response_schema", {})
	var schema_text := JSON.stringify(schema, "\t") if schema is Dictionary and not (schema as Dictionary).is_empty() else "<empty>"
	var request_options = debug_context.get("request_options", {})
	var request_options_text := ""
	if request_options is Dictionary and not (request_options as Dictionary).is_empty():
		request_options_text = JSON.stringify(request_options, "\t")
	var payload = debug_context.get("payload", {})
	var payload_text := ""
	if payload is Dictionary and not (payload as Dictionary).is_empty():
		payload_text = JSON.stringify(payload, "\t")
	var api_key_debug := String(debug_context.get("api_key_debug", debug_context.get("api_key", "")))
	var meta := {
		"request_id": request_id,
		"reason": reason,
		"purpose": String(debug_context.get("purpose", "")),
		"provider": String(debug_context.get("provider", "")),
		"endpoint": String(debug_context.get("endpoint", "")),
		"url": String(debug_context.get("url", "")),
		"model": String(debug_context.get("model", "")),
		"transport_mode": String(debug_context.get("transport_mode", TRANSPORT_MODE_SYNC)),
		"output_type": String(debug_context.get("output_type", OUTPUT_TYPE_TEXT)),
		"reasoning_mode": String(debug_context.get("reasoning_mode", REASONING_MODE_OFF)),
		"output_adapter": String(debug_context.get("output_adapter", FORMT_ADAPTER_AUTO)),
		"reason_adapter": String(debug_context.get("reason_adapter", REASON_ADAPTER_AUTO)),
		"api_key": api_key_debug,
		"timeout_sec": float(debug_context.get("timeout_sec", 0.0)),
		"temperature": float(debug_context.get("temperature", 0.0)),
		"output_tokens": int(debug_context.get("output_tokens", 0)),
		"reasoning": bool(debug_context.get("reasoning", false)),
		"connection_test": bool(debug_context.get("connection_test", false)),
		"headers": String(debug_context.get("headers", "")),
		"payload_schema": String(debug_context.get("payload_schema", "")),
		"message_count": int(debug_context.get("message_count", 0)),
		"input_prompt_chars": prompt_text.length(),
		"input_schema_chars": schema_text.length(),
		"request_options_chars": request_options_text.length(),
		"request_payload_chars": payload_text.length(),
		"raw_output_chars": output.length(),
	}
	print("[ModelCall][error] %s" % JSON.stringify(meta))
	_print_log_chunks("[ModelCall][error][input_prompt] id=%d reason=%s" % [request_id, reason], prompt_text)
	_print_log_chunks("[ModelCall][error][input_schema] id=%d reason=%s" % [request_id, reason], schema_text)
	if request_options_text != "":
		_print_log_chunks("[ModelCall][error][request_options] id=%d reason=%s" % [request_id, reason], request_options_text)
	if payload_text != "":
		_print_log_chunks("[ModelCall][error][request_payload] id=%d reason=%s" % [request_id, reason], payload_text)
	_print_log_chunks("[ModelCall][error][raw_output] id=%d reason=%s" % [request_id, reason], output)


func _payload_preview(payload: Dictionary) -> String:
	var clean := JSON.stringify(payload).replace("\r", " ").replace("\n", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.length() > 600:
		return "%s..." % clean.substr(0, 597)
	return clean


func _emit_diagnostic_ready(request_id: int, diagnostic: Dictionary) -> void:
	if diagnostic.is_empty():
		return
	_completed_diagnostics[request_id] = diagnostic.duplicate(true)
	diagnostic_ready.emit(request_id, diagnostic.duplicate(true))


func _response_diagnostic(provider: String, reasoning: bool, stream_requested: bool, parse_ok: bool, parsed, content: String, reasoning_content: String, raw_text: String, response_code: int) -> Dictionary:
	return {
		"provider": provider,
		"reasoning_enabled": reasoning,
		"stream_requested": stream_requested,
		"parse_ok": parse_ok,
		"response_code": response_code,
		"text_output": content,
		"reasoning_output": reasoning_content,
		"has_text_output": content.strip_edges() != "",
		"has_reasoning_output": reasoning_content.strip_edges() != "",
		"has_stream_output": stream_requested and ((content.strip_edges() != "") or (reasoning_content.strip_edges() != "")),
		"raw_output_preview": _response_preview(raw_text),
		"parsed_keys": _dictionary_keys_text(parsed) if parsed is Dictionary else "",
	}


func _parse_stream_response(request_id: int, provider: String, text: String) -> Dictionary:
	if provider == "gemini":
		return _parse_gemini_stream_response(request_id, text)
	if provider == "anthropic":
		return _parse_anthropic_stream_response(request_id, text)
	if provider == "ollama":
		return _parse_ollama_stream_response(request_id, text)
	return _parse_openai_stream_response(request_id, text)


func _parse_openai_stream_response(request_id: int, text: String) -> Dictionary:
	var content_parts := []
	var reasoning_parts := []
	var parsed_messages := 0
	for payload_text in _sse_data_events(text):
		if payload_text == "[DONE]":
			continue
		var json := JSON.new()
		if json.parse(payload_text) != OK or not (json.data is Dictionary):
			continue
		parsed_messages += 1
		var data: Dictionary = json.data as Dictionary
		var choices = data.get("choices", [])
		if not (choices is Array):
			continue
		for choice in choices:
			if not (choice is Dictionary):
				continue
			var delta = (choice as Dictionary).get("delta", {})
			if delta is Dictionary:
				var delta_dict := delta as Dictionary
				var content := String(delta_dict.get("content", ""))
				if content != "":
					content_parts.append(content)
				var reasoning_content := String(delta_dict.get("reasoning_content", delta_dict.get("reasoning", "")))
				if reasoning_content != "":
					reasoning_parts.append(reasoning_content)
				var tool_calls = delta_dict.get("tool_calls", [])
				if tool_calls is Array:
					for tool_call in tool_calls:
						if not (tool_call is Dictionary):
							continue
						var function_call = (tool_call as Dictionary).get("function", {})
						if function_call is Dictionary:
							var arguments := String((function_call as Dictionary).get("arguments", ""))
							if arguments != "":
								content_parts.append(arguments)
		if parsed_messages > 0:
			continue
	if parsed_messages <= 0:
		return {"ok": false, "error": "模型流式响应中没有有效事件"}
	var content_text := "".join(content_parts).strip_edges()
	var reasoning_text := "".join(reasoning_parts).strip_edges()
	if content_text != "":
		stream_output.emit(request_id, "text", content_text)
		_emit_chunk_event(request_id, "text", content_text)
	if reasoning_text != "":
		stream_output.emit(request_id, "reasoning", reasoning_text)
		_emit_chunk_event(request_id, "reasoning", reasoning_text)
	return {
		"ok": true,
		"content": content_text,
		"reasoning_content": reasoning_text,
		"parsed": {"choices": parsed_messages},
	}


func _parse_anthropic_stream_response(request_id: int, text: String) -> Dictionary:
	var content_parts := []
	var reasoning_parts := []
	var event_count := 0
	for payload_text in _sse_data_events(text):
		var json := JSON.new()
		if json.parse(payload_text) != OK or not (json.data is Dictionary):
			continue
		event_count += 1
		var data: Dictionary = json.data as Dictionary
		var event_type := String(data.get("type", ""))
		match event_type:
			"content_block_delta":
				var delta = data.get("delta", {})
				if delta is Dictionary:
					var delta_dict := delta as Dictionary
					var text_delta := String(delta_dict.get("text", ""))
					if text_delta != "":
						content_parts.append(text_delta)
					var thinking_delta := String(delta_dict.get("thinking", ""))
					if thinking_delta != "":
						reasoning_parts.append(thinking_delta)
			"message_delta":
				var delta = data.get("delta", {})
				if delta is Dictionary:
					var thinking_text := String((delta as Dictionary).get("thinking", ""))
					if thinking_text != "":
						reasoning_parts.append(thinking_text)
	if event_count <= 0:
		return {"ok": false, "error": "模型流式响应中没有有效事件"}
	var content_text := "".join(content_parts).strip_edges()
	var reasoning_text := "".join(reasoning_parts).strip_edges()
	if content_text != "":
		stream_output.emit(request_id, "text", content_text)
		_emit_chunk_event(request_id, "text", content_text)
	if reasoning_text != "":
		stream_output.emit(request_id, "reasoning", reasoning_text)
		_emit_chunk_event(request_id, "reasoning", reasoning_text)
	return {
		"ok": true,
		"content": content_text,
		"reasoning_content": reasoning_text,
		"parsed": {"events": event_count},
	}


func _parse_gemini_stream_response(request_id: int, text: String) -> Dictionary:
	var content_parts := []
	var reasoning_parts := []
	var event_count := 0
	for payload_text in _sse_data_events(text):
		var json := JSON.new()
		if json.parse(payload_text) != OK or not (json.data is Dictionary):
			continue
		event_count += 1
		var data: Dictionary = json.data as Dictionary
		var candidates = data.get("candidates", [])
		if not (candidates is Array):
			continue
		for candidate in candidates:
			if not (candidate is Dictionary):
				continue
			var candidate_content = (candidate as Dictionary).get("content", {})
			if not (candidate_content is Dictionary):
				continue
			var parts = (candidate_content as Dictionary).get("parts", [])
			if not (parts is Array):
				continue
			for part in parts:
				if not (part is Dictionary):
					continue
				var part_dict := part as Dictionary
				var part_text := String(part_dict.get("text", ""))
				if part_text == "":
					continue
				if bool(part_dict.get("thought", false)):
					reasoning_parts.append(part_text)
				else:
					content_parts.append(part_text)
	if event_count <= 0:
		return {"ok": false, "error": "模型流式响应中没有有效事件"}
	var content_text := "".join(content_parts).strip_edges()
	var reasoning_text := "".join(reasoning_parts).strip_edges()
	if content_text != "":
		stream_output.emit(request_id, "text", content_text)
		_emit_chunk_event(request_id, "text", content_text)
	if reasoning_text != "":
		stream_output.emit(request_id, "reasoning", reasoning_text)
		_emit_chunk_event(request_id, "reasoning", reasoning_text)
	return {
		"ok": true,
		"content": content_text,
		"reasoning_content": reasoning_text,
		"parsed": {"events": event_count},
	}


func _parse_ollama_stream_response(request_id: int, text: String) -> Dictionary:
	var lines := text.replace("\r", "\n").split("\n", false)
	var content_parts := []
	var reasoning_parts := []
	var event_count := 0
	for line in lines:
		var payload_text := String(line).strip_edges()
		if payload_text == "":
			continue
		var json := JSON.new()
		if json.parse(payload_text) != OK or not (json.data is Dictionary):
			continue
		event_count += 1
		var data: Dictionary = json.data as Dictionary
		var message = data.get("message", {})
		if message is Dictionary:
			var message_dict := message as Dictionary
			var content := String(message_dict.get("content", ""))
			if content != "":
				content_parts.append(content)
			var reasoning_content := String(message_dict.get("reasoning_content", message_dict.get("thinking", "")))
			if reasoning_content != "":
				reasoning_parts.append(reasoning_content)
	if event_count <= 0:
		return {"ok": false, "error": "模型流式响应中没有有效事件"}
	var content_text := "".join(content_parts).strip_edges()
	var reasoning_text := "".join(reasoning_parts).strip_edges()
	if content_text != "":
		stream_output.emit(request_id, "text", content_text)
		_emit_chunk_event(request_id, "text", content_text)
	if reasoning_text != "":
		stream_output.emit(request_id, "reasoning", reasoning_text)
		_emit_chunk_event(request_id, "reasoning", reasoning_text)
	return {
		"ok": true,
		"content": content_text,
		"reasoning_content": reasoning_text,
		"parsed": {"events": event_count},
	}


func _sse_data_events(text: String) -> Array:
	var normalized := text.replace("\r\n", "\n").replace("\r", "\n")
	var blocks := normalized.split("\n\n", false)
	var events := []
	for block in blocks:
		var lines := String(block).split("\n", false)
		var parts := []
		for raw_line in lines:
			var line := String(raw_line)
			if not line.begins_with("data:"):
				continue
			parts.append(line.substr(5, line.length()).strip_edges())
		if not parts.is_empty():
			events.append("\n".join(parts))
	return events


func _response_schema_debug(response_schema: Dictionary) -> String:
	if response_schema.is_empty():
		return "empty"
	var body := _response_schema_body(response_schema)
	var required := []
	var required_value = body.get("required", [])
	if required_value is Array:
		for item in required_value:
			required.append(String(item))
	var properties := []
	var properties_value = body.get("properties", {})
	if properties_value is Dictionary:
		for key in (properties_value as Dictionary).keys():
			properties.append(String(key))
	properties.sort()
	return "present name=%s strict=%s required=%s properties=%s" % [
		_response_schema_name(response_schema),
		str(bool(response_schema.get("strict", true))),
		",".join(required),
		",".join(properties),
	]


func _payload_schema_state(payload: Dictionary) -> String:
	if payload.has("response_format"):
		return "response_format"
	if payload.has("format") and payload.get("format") is Dictionary:
		return "format"
	if payload.has("tools") and payload.has("tool_choice"):
		return "tools.tool_choice"
	if payload.has("tools"):
		return "tools"
	var generation_config = payload.get("generationConfig", {})
	if generation_config is Dictionary and (generation_config as Dictionary).has("responseJsonSchema"):
		return "generationConfig.responseJsonSchema"
	return "empty"


func _payload_schema_payload_text(payload: Dictionary) -> String:
	if payload.has("response_format"):
		var schema_payload := {"response_format": payload.get("response_format", {})}
		if payload.has("chat_template_kwargs"):
			schema_payload["chat_template_kwargs"] = payload.get("chat_template_kwargs", {})
		if payload.has("include_reasoning"):
			schema_payload["include_reasoning"] = payload.get("include_reasoning")
		return JSON.stringify(schema_payload, "\t")
	if payload.has("format") and payload.get("format") is Dictionary:
		return JSON.stringify({"format": payload.get("format", {})}, "\t")
	if payload.has("tools") and payload.has("tool_choice"):
		var schema_payload := {
			"tools": payload.get("tools", []),
			"tool_choice": payload.get("tool_choice", {}),
		}
		if payload.has("parallel_tool_calls"):
			schema_payload["parallel_tool_calls"] = payload.get("parallel_tool_calls")
		if payload.has("chat_template_kwargs"):
			schema_payload["chat_template_kwargs"] = payload.get("chat_template_kwargs", {})
		if payload.has("include_reasoning"):
			schema_payload["include_reasoning"] = payload.get("include_reasoning")
		return JSON.stringify(schema_payload, "\t")
	if payload.has("tools"):
		var schema_payload := {
			"tools": payload.get("tools", []),
		}
		if payload.has("chat_template_kwargs"):
			schema_payload["chat_template_kwargs"] = payload.get("chat_template_kwargs", {})
		if payload.has("include_reasoning"):
			schema_payload["include_reasoning"] = payload.get("include_reasoning")
		return JSON.stringify(schema_payload, "\t")
	var generation_config = payload.get("generationConfig", {})
	if generation_config is Dictionary and (generation_config as Dictionary).has("responseJsonSchema"):
		return JSON.stringify({
			"generationConfig.responseMimeType": (generation_config as Dictionary).get("responseMimeType", ""),
			"generationConfig.responseJsonSchema": (generation_config as Dictionary).get("responseJsonSchema", {}),
		}, "\t")
	return "<empty>"


func _print_log_chunks(prefix: String, text: String, chunk_size: int = 1800) -> void:
	var clean_prefix := prefix.strip_edges()
	if clean_prefix == "":
		clean_prefix = "[ModelChatClient][body]"
	if text == "":
		print("%s <empty>" % clean_prefix)
		return
	var size := maxi(256, chunk_size)
	var total := int(ceil(float(text.length()) / float(size)))
	for i in range(total):
		var start := i * size
		print("%s chunk=%d/%d\n%s" % [clean_prefix, i + 1, total, text.substr(start, size)])


func _headers_debug(headers: Array) -> String:
	var parts := []
	for header in headers:
		var text := String(header)
		var lower := text.to_lower()
		if lower.begins_with("authorization:"):
			parts.append("Authorization=set")
		elif lower.begins_with("x-api-key:"):
			parts.append("x-api-key=set")
		elif lower.begins_with("x-goog-api-key:"):
			parts.append("x-goog-api-key=set")
		else:
			parts.append(text)
	return ", ".join(parts)


func _api_key_state(api_key: String) -> String:
	return "set" if api_key.strip_edges() != "" else "empty"


func _api_key_debug(api_key: String) -> String:
	var clean := api_key.strip_edges()
	if clean == "":
		return "empty"
	var masked := clean if clean.length() <= 8 else "%s...%s" % [clean.substr(0, 4), clean.substr(clean.length() - 4, 4)]
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(clean.to_utf8_buffer())
	var digest := Marshalls.raw_to_base64(context.finish()).replace("+", "-").replace("/", "_").replace("=", "")
	return "set len=%d masked=%s sha256=%s" % [clean.length(), masked, digest.substr(0, 12)]


func _dictionary_keys_text(value: Dictionary) -> String:
	var keys := []
	for key in value.keys():
		keys.append(String(key))
	return ",".join(keys)


func _request_url(provider: String, endpoint: String, model: String, options: Dictionary = {}) -> String:
	var url := _chat_url(provider, endpoint, model)
	if not _stream_requested(options):
		return url
	if provider == "gemini":
		return url.replace(":generateContent", ":streamGenerateContent")
	return url


func _chat_url(provider: String, endpoint: String, model: String = "") -> String:
	var clean := endpoint.strip_edges()
	while clean.ends_with("/") and clean.length() > 1:
		clean = clean.substr(0, clean.length() - 1)
	if provider == "ollama":
		if clean.ends_with("/api/chat"):
			return clean
		if clean.ends_with("/api"):
			return "%s/chat" % clean
		return "%s/api/chat" % clean
	if provider == "anthropic":
		if clean.ends_with("/messages"):
			return clean
		return "%s/messages" % clean
	if provider == "gemini":
		if clean.ends_with(":generateContent"):
			return clean
		if model_path_from_endpoint(clean) != "":
			return "%s:generateContent" % clean
		var base_path := clean
		var model_name := model.strip_edges()
		if model_name.begins_with("models/"):
			model_name = model_name.substr("models/".length())
		while base_path.ends_with("/") and base_path.length() > 1:
			base_path = base_path.substr(0, base_path.length() - 1)
		return "%s/models/%s:generateContent" % [base_path, model_name]
	if clean.ends_with("/chat/completions"):
		return clean
	if clean.ends_with("/models"):
		clean = clean.substr(0, clean.length() - "/models".length())
	return "%s/chat/completions" % clean


func _normalize_provider(provider: String) -> String:
	return _adapter_registry.normalize_provider(provider)


func _system_prompt(messages: Array) -> String:
	var parts := []
	for message in messages:
		if message is Dictionary and String(message.get("role", "")) == "system":
			var content := String(message.get("content", "")).strip_edges()
			if content != "":
				parts.append(content)
	return "\n\n".join(parts)


func _anthropic_messages(messages: Array) -> Array:
	var result := []
	for message in messages:
		if not (message is Dictionary):
			continue
		var role := String(message.get("role", "user"))
		if role == "system":
			continue
		result.append({
			"role": "assistant" if role == "assistant" else "user",
			"content": String(message.get("content", "")),
		})
	if result.is_empty():
		result.append({"role": "user", "content": ""})
	return result


func _gemini_system_instruction(messages: Array) -> Dictionary:
	var system := _system_prompt(messages)
	if system == "":
		return {}
	return {
		"parts": [
			{"text": system},
		],
	}


func _gemini_contents(messages: Array) -> Array:
	var result := []
	for message in messages:
		if not (message is Dictionary):
			continue
		var role := String(message.get("role", "user"))
		if role == "system":
			continue
		result.append({
			"role": "model" if role == "assistant" else "user",
			"parts": [
				{"text": String(message.get("content", ""))},
			],
		})
	if result.is_empty():
		result.append({"role": "user", "parts": [{"text": ""}]})
	return result


func _parse_anthropic_content(json: Dictionary) -> String:
	var content = json.get("content", [])
	var tool_inputs := []
	var parts := []
	if content is Array:
		for block in content:
			if not (block is Dictionary):
				continue
			var type := String(block.get("type", ""))
			if type == "tool_use":
				var input = (block as Dictionary).get("input", {})
				if input is Dictionary:
					tool_inputs.append(JSON.stringify(input))
			elif type == "text":
				var text := String(block.get("text", "")).strip_edges()
				if text != "":
					parts.append(text)
	if not tool_inputs.is_empty():
		return "\n".join(tool_inputs)
	return "\n".join(parts)


func _parse_gemini_content(json: Dictionary) -> String:
	var candidates = json.get("candidates", [])
	if not (candidates is Array) or candidates.is_empty() or not (candidates[0] is Dictionary):
		return ""
	var candidate: Dictionary = candidates[0]
	var content = candidate.get("content", {})
	if not (content is Dictionary):
		return ""
	var parts = (content as Dictionary).get("parts", [])
	var texts := []
	if parts is Array:
		for part in parts:
			if part is Dictionary:
				var text := String(part.get("text", "")).strip_edges()
				if text != "":
					texts.append(text)
	return "\n".join(texts)


func model_path_from_endpoint(endpoint: String) -> String:
	var marker := endpoint.find("/models/")
	if marker < 0:
		return ""
	return endpoint.substr(marker + 1)
