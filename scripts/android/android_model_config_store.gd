extends RefCounted
class_name AndroidModelConfigStore

const ModelAdapterRegistryScript := preload("res://scripts/core/model/model_adapter_registry.gd")
const DEFAULT_SINGLETON := "PlayWithMeAndroid"
const AVAILABLE_METHODS := ["model_config_available", "modelConfigAvailable"]
const LIST_METHODS := ["model_config_list", "modelConfigList"]
const SAVE_METHODS := ["model_config_save", "modelConfigSave"]
const DELETE_METHODS := ["model_config_delete", "modelConfigDelete"]
const DEFAULT_MAX_OUTPUT_TOKEN := 4096
const DEFAULT_FORMT_ADAPTER := "auto"
const DEFAULT_REASON_ADAPTER := "auto"

var singleton_name := DEFAULT_SINGLETON
var persistence_enabled := true
var _adapter_registry = ModelAdapterRegistryScript.new()


func backend_attached() -> bool:
	var plugin = _plugin()
	if plugin == null:
		return false
	return _method(plugin, LIST_METHODS) != "" and _method(plugin, SAVE_METHODS) != "" and _method(plugin, DELETE_METHODS) != ""


func is_available() -> bool:
	if not persistence_enabled:
		_store_debug("is_available=false persistence=disabled")
		return false
	var plugin = _plugin()
	if plugin == null:
		_store_debug("is_available=false plugin=missing")
		return false
	var available_method := _method(plugin, AVAILABLE_METHODS)
	if available_method != "":
		var result = plugin.call(available_method)
		if result is bool:
			var available := bool(result)
			_store_debug("is_available=%s via=%s" % [str(available), available_method])
			return available
	var fallback_available := _method(plugin, LIST_METHODS) != "" and _method(plugin, SAVE_METHODS) != "" and _method(plugin, DELETE_METHODS) != ""
	_store_debug("is_available=%s via=fallback_methods" % str(fallback_available))
	return fallback_available


func list_configs() -> Array:
	var plugin = _plugin()
	if plugin == null:
		return []
	var method := _method(plugin, LIST_METHODS)
	if method == "":
		return []
	var parsed = _parse_json(plugin.call(method))
	var source: Array = []
	if parsed is Array:
		source = parsed
	elif parsed is Dictionary:
		var payload: Dictionary = parsed
		if not bool(payload.get("ok", true)):
			return []
		source = _array_or_empty(payload.get("models", payload.get("items", [])))
	var result: Array = []
	for item in source:
		if item is Dictionary:
			var normalized := _normalize_config(item as Dictionary)
			if not normalized.is_empty():
				result.append(normalized)
	return result


func save_config(config: Dictionary) -> Dictionary:
	if not _formt_adapter_can_save(_formt_adapter_from_config(config)):
		return {"ok": false, "error": "模型适配器必须先通过测试后保存"}
	if not _reason_adapter_can_save(bool(config.get("reasoning", false)), _reason_adapter_from_config(config)):
		return {"ok": false, "error": "思考兼容必须先通过测试后保存"}
	var payload := _call_json(SAVE_METHODS, [JSON.stringify(_config_payload(config))])
	if not bool(payload.get("ok", false)):
		return {"ok": false, "error": String(payload.get("error", "SQLite 模型配置保存失败"))}
	var source = payload.get("model", payload.get("item", payload))
	if source is Dictionary:
		var normalized := _normalize_config(source as Dictionary)
		if not normalized.is_empty():
			normalized["ok"] = true
			return normalized
	return {"ok": false, "error": "SQLite 模型配置返回格式错误"}


func delete_config(id: int) -> Dictionary:
	if id <= 0:
		return {"ok": true}
	var payload := _call_json(DELETE_METHODS, [id])
	if not bool(payload.get("ok", false)):
		return {"ok": false, "error": String(payload.get("error", "SQLite 模型配置删除失败"))}
	return {"ok": true}


func _config_payload(config: Dictionary) -> Dictionary:
	var model := String(config.get("model", "")).strip_edges()
	if model == "":
		model = String(config.get("name", "")).strip_edges()
	var max_context := maxi(1, int(config.get("max_context", config.get("max_token", 262144))))
	return {
		"id": int(config.get("id", 0)),
		"model": model,
		"provider": String(config.get("provider", "openai_api")).strip_edges(),
		"endpoint": String(config.get("endpoint", "")).strip_edges(),
		"api_key": String(config.get("api_key", "")).strip_edges(),
		"context_window_tokens": maxi(1, int(config.get("context_window_tokens", roundi(float(max_context) * 0.7)))),
		"max_context": max_context,
		"max_output": _max_output_from_config(config, max_context),
		"temperature": clampf(float(config.get("temperature", 0.6)), 0.0, 2.0),
		"reasoning": bool(config.get("reasoning", false)),
		"formt_adapter": _formt_adapter_from_config(config),
		"reason_adapter": _reason_adapter_from_config(config),
	}


func _normalize_config(config: Dictionary) -> Dictionary:
	var model := String(config.get("model", "")).strip_edges()
	if model == "":
		model = String(config.get("name", "")).strip_edges()
	var endpoint := String(config.get("endpoint", "")).strip_edges()
	if model == "" or endpoint == "":
		return {}
	var max_context := maxi(1, int(config.get("max_context", config.get("max_token", 262144))))
	return {
		"id": int(config.get("id", 0)),
		"model": model,
		"provider": String(config.get("provider", "openai_api")).strip_edges(),
		"endpoint": endpoint,
		"memory": "",
		"api_key": String(config.get("api_key", "")).strip_edges(),
		"context_window_tokens": maxi(1, int(config.get("context_window_tokens", roundi(float(max_context) * 0.7)))),
		"max_context": max_context,
		"max_output": _max_output_from_config(config, max_context),
		"temperature": clampf(float(config.get("temperature", 0.6)), 0.0, 2.0),
		"reasoning": bool(config.get("reasoning", false)),
		"formt_adapter": _formt_adapter_from_config(config),
		"reason_adapter": _reason_adapter_from_config(config),
	}


func _max_output_from_config(config: Dictionary, _max_context: int, default_value: int = DEFAULT_MAX_OUTPUT_TOKEN) -> int:
	if config.has("max_output"):
		return maxi(1, int(config.get("max_output", default_value)))
	return default_value


func _formt_adapter_from_config(config: Dictionary) -> String:
	var adapter := _adapter_registry.normalize_formt_adapter(String(config.get("formt_adapter", DEFAULT_FORMT_ADAPTER)))
	return adapter if adapter != "" else DEFAULT_FORMT_ADAPTER


func _formt_adapter_can_save(formt_adapter: String) -> bool:
	return _adapter_registry.formt_adapter_can_save(formt_adapter)


func _reason_adapter_from_config(config: Dictionary) -> String:
	var adapter := _adapter_registry.normalize_reason_adapter(String(config.get("reason_adapter", DEFAULT_REASON_ADAPTER)))
	return adapter if adapter != "" else DEFAULT_REASON_ADAPTER


func _reason_adapter_can_save(reasoning: bool, reason_adapter: String) -> bool:
	return _adapter_registry.reason_adapter_can_save(reasoning, reason_adapter)


func _call_json(methods: Array, args: Array) -> Dictionary:
	var plugin = _plugin()
	if plugin == null:
		return {"ok": false, "error": "Android 模型配置插件未接入：缺少 singleton %s" % singleton_name}
	var method := _method(plugin, methods)
	if method == "":
		return {"ok": false, "error": "Android 模型配置插件缺少方法"}
	var parsed = _parse_json(plugin.callv(method, args))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {"ok": false, "error": "Android 模型配置插件返回格式错误"}


func _plugin():
	if Engine.has_singleton(singleton_name):
		return Engine.get_singleton(singleton_name)
	return null


func _method(plugin, methods: Array) -> String:
	for method in methods:
		if plugin.has_method(method):
			return method
	if OS.get_name() == "Android" and not methods.is_empty():
		return String(methods[0])
	return ""


func _parse_json(payload):
	if payload is Dictionary or payload is Array:
		return payload
	if payload is String:
		var raw := String(payload).strip_edges()
		if raw == "":
			return {}
		var json := JSON.new()
		if json.parse(raw) != OK:
			return {}
		return json.data
	return {}


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


func _store_debug(message: String) -> void:
	if OS.is_debug_build():
		if OS.is_debug_build():
			print("[AndroidModelConfigStore][debug] %s" % message)
