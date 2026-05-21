extends RefCounted
class_name ModelCatalogClient

signal completed(request_id: int, ok: bool, models: Array, error: String)

var _next_request_id := 1
var _pending := {}


func list_models(profile: Dictionary, timeout_sec: float = 20.0) -> int:
	var request_id := _next_request_id
	_next_request_id += 1
	var endpoint := String(profile.get("endpoint", "")).strip_edges()
	if endpoint == "":
		push_warning("[ModelCatalogClient] list_models skipped: endpoint_empty id=%d" % request_id)
		call_deferred("_emit_completed", request_id, false, [], "Endpoint 为空")
		return request_id
	var provider := _normalize_provider(String(profile.get("provider", "")))
	var url := _models_url(provider, endpoint)
	var api_key := String(profile.get("api_key", ""))
	var headers := _model_catalog_headers(provider, api_key)
	print("[ModelCatalogClient] list_models start id=%d provider=%s endpoint=%s url=%s api_key=%s timeout=%.1f headers=%s" % [request_id, provider, endpoint, url, _api_key_state(api_key), timeout_sec, _headers_debug(headers)])
	var err := _start_model_catalog_request(request_id, provider, url, headers, timeout_sec)
	if err != OK:
		push_warning("[ModelCatalogClient] list_models request create failed id=%d err=%s url=%s" % [request_id, err, url])
		call_deferred("_emit_completed", request_id, false, [], _request_start_error(err, url))
	return request_id


func _model_catalog_headers(provider: String, api_key_text: String) -> Array:
	var headers := ["Accept: application/json"]
	var api_key := api_key_text.strip_edges()
	if provider == "anthropic":
		headers.append("anthropic-version: 2023-06-01")
		if api_key != "":
			headers.append("x-api-key: %s" % api_key)
	elif provider == "gemini":
		if api_key != "":
			headers.append("x-goog-api-key: %s" % api_key)
	elif api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)
	return headers


func _start_model_catalog_request(request_id: int, provider: String, url: String, headers: Array, timeout_sec: float) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return ERR_UNAVAILABLE
	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	_pending[request_id] = {
		"http": http,
		"url": url,
	}
	http.request_completed.connect(_on_request_completed.bind(request_id, provider))
	tree.root.add_child(http)
	print("[ModelCatalogClient] request send id=%d provider=%s url=%s" % [request_id, provider, url])
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_pending.erase(request_id)
		http.queue_free()
	return err


func _request_start_error(err: int, url: String) -> String:
	if err == ERR_UNAVAILABLE:
		return "当前没有可用 SceneTree url=%s" % url
	return "模型列表请求创建失败：%s url=%s" % [err, url]


func _emit_completed(request_id: int, ok: bool, models: Array, error: String) -> void:
	completed.emit(request_id, ok, models, error)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request_id: int, provider: String) -> void:
	var pending: Dictionary = _pending.get(request_id, {})
	_pending.erase(request_id)
	var http := pending.get("http") as HTTPRequest
	var url := String(pending.get("url", ""))
	if http != null:
		http.queue_free()
	var text := body.get_string_from_utf8()
	print("[ModelCatalogClient] response id=%d provider=%s result=%s code=%d url=%s bytes=%d body=%s" % [request_id, provider, result, response_code, url, body.size(), _response_preview(text)])
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[ModelCatalogClient] request failed id=%d result=%s url=%s" % [request_id, result, url])
		completed.emit(request_id, false, [], "模型列表请求失败：%s url=%s" % [result, url])
		return
	if response_code < 200 or response_code >= 300:
		push_warning("[ModelCatalogClient] response http error id=%d code=%d url=%s body=%s" % [request_id, response_code, url, _response_preview(text)])
		completed.emit(request_id, false, [], "%s模型列表响应异常 %d url=%s body=%s" % [_endpoint_hint(provider, url, text), response_code, url, _response_preview(text)])
		return
	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		push_warning("[ModelCatalogClient] response parse failed id=%d url=%s error=%s body=%s" % [request_id, url, json.get_error_message(), _response_preview(text)])
		completed.emit(request_id, false, [], "%s模型列表响应不是 JSON：url=%s parse=%s body=%s" % [_endpoint_hint(provider, url, text), url, json.get_error_message(), _response_preview(text)])
		return
	var parsed = json.data
	if not (parsed is Dictionary):
		push_warning("[ModelCatalogClient] response is not object id=%d url=%s body=%s" % [request_id, url, _response_preview(text)])
		completed.emit(request_id, false, [], "%s模型列表响应不是 JSON 对象：url=%s body=%s" % [_endpoint_hint(provider, url, text), url, _response_preview(text)])
		return
	var models := _parse_models(provider, parsed)
	print("[ModelCatalogClient] parsed models id=%d provider=%s count=%d keys=%s" % [request_id, provider, models.size(), _dictionary_keys_text(parsed)])
	completed.emit(request_id, true, models, "")


func _parse_models(provider: String, json: Dictionary) -> Array:
	if provider == "ollama":
		return _parse_ollama_models(json)
	if provider == "gemini":
		return _parse_gemini_models(json)
	if provider == "anthropic":
		return _parse_anthropic_models(json)
	return _parse_openai_models(json)


func _parse_openai_models(json: Dictionary) -> Array:
	var data = json.get("data", [])
	var items := []
	if data is Array:
		for item in data:
			if item is Dictionary:
				var id := String(item.get("id", "")).strip_edges()
				if id != "":
					items.append({
						"id": id,
						"display_name": id,
						"description": String(item.get("owned_by", "")),
					})
	return _unique_sorted(items)


func _parse_ollama_models(json: Dictionary) -> Array:
	var models = json.get("models", [])
	var items := []
	if models is Array:
		for item in models:
			if item is Dictionary:
				var id := String(item.get("name", item.get("model", ""))).strip_edges()
				if id != "":
					items.append({
						"id": id,
						"display_name": id,
						"description": String(item.get("modified_at", "")),
					})
	return _unique_sorted(items)


func _parse_gemini_models(json: Dictionary) -> Array:
	var models = json.get("models", [])
	var items := []
	if models is Array:
		for item in models:
			if item is Dictionary:
				var methods = item.get("supportedGenerationMethods", [])
				if methods is Array and not methods.is_empty() and not methods.has("generateContent"):
					continue
				var raw_id := String(item.get("name", "")).strip_edges()
				if raw_id.begins_with("models/"):
					raw_id = raw_id.substr("models/".length())
				if raw_id != "":
					items.append({
						"id": raw_id,
						"display_name": String(item.get("displayName", raw_id)),
						"description": String(item.get("description", "")),
					})
	return _unique_sorted(items)


func _parse_anthropic_models(json: Dictionary) -> Array:
	var data = json.get("data", [])
	var items := []
	if data is Array:
		for item in data:
			if item is Dictionary:
				var id := String(item.get("id", "")).strip_edges()
				if id != "":
					items.append({
						"id": id,
						"display_name": String(item.get("display_name", id)),
						"description": String(item.get("type", "")),
					})
	return _unique_sorted(items)


func _unique_sorted(items: Array) -> Array:
	var by_id := {}
	for item in items:
		if item is Dictionary:
			var id := String(item.get("id", ""))
			if id != "" and not by_id.has(id):
				by_id[id] = item
	var ids := by_id.keys()
	ids.sort()
	var result := []
	for id in ids:
		result.append(by_id[id])
	return result


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


func _dictionary_keys_text(value: Dictionary) -> String:
	var keys := []
	for key in value.keys():
		keys.append(String(key))
	return ",".join(keys)


func _models_url(provider: String, endpoint: String) -> String:
	var clean := endpoint.strip_edges()
	while clean.ends_with("/") and clean.length() > 1:
		clean = clean.substr(0, clean.length() - 1)
	if provider == "ollama":
		if clean.ends_with("/api/chat"):
			return clean.substr(0, clean.length() - "/chat".length()) + "/tags"
		if clean.ends_with("/api"):
			return "%s/tags" % clean
		if clean.ends_with("/tags"):
			return clean
		return "%s/api/tags" % clean
	if provider == "gemini":
		if clean.ends_with(":generateContent"):
			var models_marker := clean.find("/models/")
			if models_marker >= 0:
				return clean.substr(0, models_marker + "/models".length())
		var model_marker := clean.find("/models/")
		if model_marker >= 0:
			return clean.substr(0, model_marker + "/models".length())
		if clean.ends_with("/models"):
			return clean
		return "%s/models" % clean
	if provider == "anthropic":
		if clean.ends_with("/messages"):
			clean = clean.substr(0, clean.length() - "/messages".length())
		if clean.ends_with("/models"):
			return clean
		return "%s/models" % clean
	if clean.ends_with("/chat/completions"):
		clean = clean.substr(0, clean.length() - "/chat/completions".length())
	if clean.ends_with("/models"):
		return clean
	if clean.ends_with("/v1"):
		return "%s/models" % clean
	return "%s/models" % clean


func _normalize_provider(provider: String) -> String:
	var lower := provider.strip_edges().to_lower()
	if lower.contains("ollama"):
		return "ollama"
	if lower.contains("anthropic") or lower.contains("claude"):
		return "anthropic"
	if lower.contains("gemini") or lower.contains("google"):
		return "gemini"
	return "openai"
