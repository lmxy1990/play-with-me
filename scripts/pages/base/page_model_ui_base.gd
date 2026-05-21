extends "res://scripts/pages/base/page_tts_ui_base.gd"

const ConfigRepositoryScript := preload("res://scripts/core/config/config_repository.gd")
const ModelChatClientScript := preload("res://scripts/core/model/model_chat_client.gd")
const ModelCatalogClientScript := preload("res://scripts/core/model/model_catalog_client.gd")
const ModelProfileSelectorScript := preload("res://scripts/core/model/model_profile_selector.gd")
const PageModelAdapterRegistryScript := preload("res://scripts/core/model/model_adapter_registry.gd")
const AndroidModelConfigStoreScript := preload("res://scripts/android/android_model_config_store.gd")
const MODEL_TRANSPORT_MODE_SYNC := "sync"
const MODEL_TRANSPORT_MODE_STREAM := "stream"
const MODEL_OUTPUT_TYPE_TEXT := "text"
const MODEL_OUTPUT_TYPE_JSON := "json"
const MODEL_REASONING_MODE_OFF := "off"
const MODEL_REASONING_MODE_ON := "on"
const MODEL_FORMT_ADAPTER_AUTO := "auto"
const MODEL_FORMT_ADAPTER_NONE := "none"
const MODEL_REASON_ADAPTER_AUTO := "auto"

var _config_repository = ConfigRepositoryScript.new()
var _model_chat_client = ModelChatClientScript.new()
var _model_catalog_client = ModelCatalogClientScript.new()
var _model_profile_selector = ModelProfileSelectorScript.new()
var _model_adapter_registry = PageModelAdapterRegistryScript.new()
var _model_config_store = AndroidModelConfigStoreScript.new()
var _app_state
var _model_catalog_requests := {}
var _model_configs := []
var _config_storage_deferred_requested := false


func _connect_model_clients() -> void:
	var model_chat_completed := Callable(self, "_dispatch_model_chat_completed")
	if not _model_chat_client.completed.is_connected(model_chat_completed):
		_model_chat_client.completed.connect(model_chat_completed)
	if has_method("_on_model_chat_protocol_event"):
		var model_chat_protocol_event := Callable(self, "_dispatch_model_chat_protocol_event")
		if not _model_chat_client.protocol_event.is_connected(model_chat_protocol_event):
			_model_chat_client.protocol_event.connect(model_chat_protocol_event)
	if has_method("_on_model_catalog_completed"):
		var model_catalog_completed := Callable(self, "_on_model_catalog_completed")
		if not _model_catalog_client.completed.is_connected(model_catalog_completed):
			_model_catalog_client.completed.connect(model_catalog_completed)


func _disconnect_model_clients() -> void:
	var model_chat_completed := Callable(self, "_dispatch_model_chat_completed")
	if _model_chat_client != null and _model_chat_client.completed.is_connected(model_chat_completed):
		_model_chat_client.completed.disconnect(model_chat_completed)
	if has_method("_on_model_chat_protocol_event"):
		var model_chat_protocol_event := Callable(self, "_dispatch_model_chat_protocol_event")
		if _model_chat_client != null and _model_chat_client.protocol_event.is_connected(model_chat_protocol_event):
			_model_chat_client.protocol_event.disconnect(model_chat_protocol_event)
	if _model_catalog_client != null:
		var model_catalog_completed := Callable(self, "_on_model_catalog_completed")
		if _model_catalog_client.completed.is_connected(model_catalog_completed):
			_model_catalog_client.completed.disconnect(model_catalog_completed)


func _load_model_configs_from_storage(seed_when_empty: bool = true) -> bool:
	var store_available := _model_config_store.is_available()
	if not store_available:
		_config_storage_debug("model store unavailable; persistence=%s backend=%s app_state_count=%d" % [
			str(bool(_app_state != null and _app_state.persistence_enabled)),
			str(_model_config_store.backend_attached()),
			_model_configs.size(),
		])
		return false
	var stored := _model_config_store.list_configs()
	_config_storage_debug("model store loaded count=%d app_state_count=%d" % [stored.size(), _model_configs.size()])
	if stored.is_empty() and seed_when_empty and not _model_configs.is_empty():
		for item in _model_configs:
			if item is Dictionary:
				_model_config_store.save_config(item as Dictionary)
		stored = _model_config_store.list_configs()
	if not stored.is_empty() or not seed_when_empty:
		_model_configs = stored
	return true


func _refresh_model_configs_from_storage(reason: String = "") -> bool:
	var refreshed := _load_model_configs_from_storage(false)
	_config_storage_debug("model store refresh reason=%s ok=%s count=%d backend=%s persistence=%s" % [
		reason.strip_edges(),
		str(refreshed),
		_model_configs.size(),
		str(_model_config_store.backend_attached()),
		str(bool(_app_state != null and _app_state.persistence_enabled)),
	])
	return refreshed


func _request_android_config_storage_deferred_load() -> void:
	if OS.get_name() != "Android" or _config_storage_deferred_requested:
		return
	_config_storage_deferred_requested = true
	call_deferred("_reload_config_storage_after_android_singleton")


func _reload_config_storage_after_android_singleton() -> void:
	for attempt in range(1, 7):
		await get_tree().create_timer(0.35).timeout
		var model_available := _model_config_store.is_available()
		var voice_available := _tts_voice_repository.storage_available()
		_config_storage_debug("android deferred attempt=%d model_available=%s voice_available=%s" % [attempt, str(model_available), str(voice_available)])
		if model_available:
			_load_model_configs_from_storage()
			if has_method("_initialize_controlled_bot_model_profiles"):
				call("_initialize_controlled_bot_model_profiles", "android_deferred_model_store", true)
		if voice_available:
			_load_voice_configs_from_storage()
		if model_available and voice_available:
			call("_commit_state")
			return
	_config_storage_debug("android deferred storage unavailable")


func _normalize_model_configs(configs: Array) -> Array:
	var result: Array = []
	for item in configs:
		if not (item is Dictionary):
			continue
		var config: Dictionary = item
		var model := String(config.get("model", "")).strip_edges()
		if model == "":
			model = String(config.get("name", "")).strip_edges()
		var endpoint := String(config.get("endpoint", "")).strip_edges()
		if model == "" or endpoint == "":
			continue
		var max_context := maxi(1, int(config.get("max_context", config.get("max_token", 262144))))
		result.append({
			"id": int(config.get("id", 0)),
			"model": model,
			"provider": String(config.get("provider", "openai_api")).strip_edges(),
			"endpoint": endpoint,
			"memory": "",
			"api_key": String(config.get("api_key", "")).strip_edges(),
			"context_window_tokens": maxi(1, int(config.get("context_window_tokens", roundi(float(max_context) * 0.7)))),
			"max_context": max_context,
			"max_output": _max_output_from_model_config(config, max_context),
			"temperature": clampf(float(config.get("temperature", 0.6)), 0.0, 2.0),
			"reasoning": bool(config.get("reasoning", false)),
			"formt_adapter": String(config.get("formt_adapter", "auto")).strip_edges().to_lower(),
			"reason_adapter": String(config.get("reason_adapter", "auto")).strip_edges().to_lower(),
		})
	return result


func _max_output_from_model_config(config: Dictionary, _max_context: int, default_value: int = 4096) -> int:
	if config.has("max_output"):
		return maxi(1, int(config.get("max_output", default_value)))
	return default_value


func _model_profile_for_player(player: Dictionary) -> Dictionary:
	return _model_profile_selector.profile_for_player(player, _model_configs)


func _model_profile_for_name(model_name: String) -> Dictionary:
	return _model_profile_selector.profile_for_model_name(model_name, _model_configs)


func _usable_model_profile(profile: Dictionary) -> Dictionary:
	return _model_profile_selector.usable_profile(profile)


func _profile_temperature(profile: Dictionary, default_value: float) -> float:
	return _model_profile_selector.temperature(profile, default_value)


func _profile_context_window_tokens(profile: Dictionary, default_value: int = 8192) -> int:
	return _model_profile_selector.context_window_tokens(profile, default_value)


func _complete_model_request(profile: Dictionary, messages: Array, temperature: float, max_output_tokens: int = 0, timeout_sec: float = 30.0, options: Dictionary = {}, purpose: String = "") -> int:
	var request := _model_completion_request(profile, messages, temperature, max_output_tokens, timeout_sec, options, purpose)
	return int(_model_chat_client.complete_request(request))


func _model_completion_request(profile: Dictionary, messages: Array, temperature: float, max_output_tokens: int = 0, timeout_sec: float = 30.0, options: Dictionary = {}, purpose: String = "") -> Dictionary:
	var request_options := options.duplicate(true)
	var response_schema = request_options.get("response_schema", request_options.get("schema", {}))
	var output_type := MODEL_OUTPUT_TYPE_JSON if response_schema is Dictionary and not (response_schema as Dictionary).is_empty() else MODEL_OUTPUT_TYPE_TEXT
	if request_options.has("output_type"):
		output_type = String(request_options.get("output_type", output_type)).strip_edges().to_lower()
	var transport_mode := MODEL_TRANSPORT_MODE_STREAM if bool(request_options.get("stream", false)) else MODEL_TRANSPORT_MODE_SYNC
	if request_options.has("transport_mode"):
		transport_mode = String(request_options.get("transport_mode", transport_mode)).strip_edges().to_lower()
	var output_adapter := _model_adapter_registry.normalize_output_adapter(String(request_options.get("output_adapter", request_options.get("formt_adapter", String(profile.get("formt_adapter", MODEL_FORMT_ADAPTER_AUTO))))))
	if output_type == MODEL_OUTPUT_TYPE_TEXT and not request_options.has("output_adapter") and not request_options.has("formt_adapter"):
		output_adapter = MODEL_FORMT_ADAPTER_NONE
	var reasoning_mode := MODEL_REASONING_MODE_ON if bool(profile.get("reasoning", false)) else MODEL_REASONING_MODE_OFF
	if request_options.has("reasoning_mode"):
		reasoning_mode = String(request_options.get("reasoning_mode", reasoning_mode)).strip_edges().to_lower()
	var effective_max_output_tokens := max_output_tokens
	var effective_profile_max_output := int(profile.get("max_output", 0))
	if reasoning_mode == MODEL_REASONING_MODE_ON:
		effective_max_output_tokens = 0
		effective_profile_max_output = 0
	var request := {
		"purpose": purpose.strip_edges(),
		"provider": String(profile.get("provider", "")).strip_edges(),
		"endpoint": String(profile.get("endpoint", "")).strip_edges(),
		"api_key": String(profile.get("api_key", "")).strip_edges(),
		"model": String(profile.get("model", "")).strip_edges(),
		"transport_mode": transport_mode,
		"output_type": output_type,
		"reasoning_mode": reasoning_mode,
		"output_adapter": output_adapter,
		"reason_adapter": _model_adapter_registry.normalize_reason_adapter(String(profile.get("reason_adapter", MODEL_REASON_ADAPTER_AUTO))),
		"connection_test": bool(profile.get("connection_test", false)),
		"temperature": temperature,
		"max_output_tokens": effective_max_output_tokens,
		"max_output": effective_profile_max_output,
		"timeout_sec": timeout_sec,
		"messages": messages.duplicate(true),
		"options": request_options,
	}
	if response_schema is Dictionary and not (response_schema as Dictionary).is_empty():
		request["response_schema"] = (response_schema as Dictionary).duplicate(true)
	return request


func _take_model_chat_completed_result(request_id: int) -> Dictionary:
	if _model_chat_client == null:
		return {}
	return _model_chat_client.take_completed_result(request_id)


func _take_model_chat_completed_diagnostic(request_id: int) -> Dictionary:
	if _model_chat_client == null:
		return {}
	return _model_chat_client.take_completed_diagnostic(request_id)


func _build_model_request_debug_payload(request: Dictionary) -> Dictionary:
	if _model_chat_client == null:
		return {}
	return _model_chat_client.build_request_debug_payload(request)


func _model_chat_result_from_callback(request_id: int, ok: bool, content: String, error: String) -> Dictionary:
	var completed_result := _take_model_chat_completed_result(request_id)
	if completed_result.is_empty():
		completed_result = {
			"ok": ok,
			"text": content,
			"error": error,
			"diagnostic": _take_model_chat_completed_diagnostic(request_id),
		}
	return completed_result


func _dispatch_model_chat_completed(request_id: int, ok: bool, content: String, error: String) -> void:
	var completed_result := _model_chat_result_from_callback(request_id, ok, content, error)
	if has_method("_on_model_chat_result"):
		call("_on_model_chat_result", request_id, completed_result)
		return
	if has_method("_on_model_chat_completed"):
		call("_on_model_chat_completed", request_id, ok, content, error)


func _dispatch_model_chat_protocol_event(request_id: int, event: Dictionary) -> void:
	if has_method("_on_model_chat_event"):
		call("_on_model_chat_event", request_id, event)
		return
	if has_method("_on_model_chat_protocol_event"):
		call("_on_model_chat_protocol_event", request_id, event)


func _config_storage_debug(message: String) -> void:
	if OS.is_debug_build():
		if OS.is_debug_build():
			print("[ConfigStorage][debug] %s" % message)
