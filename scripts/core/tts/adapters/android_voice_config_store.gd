extends RefCounted
class_name AndroidVoiceConfigStore

const DEFAULT_SINGLETON := "PlayWithMeAndroid"
const AVAILABLE_METHODS := ["voice_config_available", "voiceConfigAvailable"]
const LIST_METHODS := ["voice_config_list", "voiceConfigList"]
const SAVE_METHODS := ["voice_config_save", "voiceConfigSave"]
const DELETE_METHODS := ["voice_config_delete", "voiceConfigDelete"]

var singleton_name := DEFAULT_SINGLETON
var persistence_enabled := true


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
			_store_debug("is_available=%s method=%s" % [str(bool(result)), available_method])
			return bool(result)
	var available := _method(plugin, LIST_METHODS) != "" and _method(plugin, SAVE_METHODS) != "" and _method(plugin, DELETE_METHODS) != ""
	_store_debug("is_available=%s source=method_probe" % str(available))
	return available


func list_configs() -> Array:
	var plugin = _plugin()
	if plugin == null:
		_store_debug("list skipped plugin=missing")
		return []
	var method := _method(plugin, LIST_METHODS)
	if method == "":
		_store_debug("list skipped method=missing")
		return []
	var parsed = _parse_json(plugin.call(method))
	var source: Array = []
	if parsed is Array:
		source = parsed
	elif parsed is Dictionary:
		var payload: Dictionary = parsed
		if not bool(payload.get("ok", true)):
			_store_debug("list failed error=%s" % String(payload.get("error", "")))
			return []
		source = _array_or_empty(payload.get("voices", payload.get("items", [])))
	var result: Array = []
	for item in source:
		if item is Dictionary:
			var normalized := _normalize_config(item as Dictionary)
			if not normalized.is_empty():
				result.append(normalized)
	_store_debug("list count=%d raw=%d" % [result.size(), source.size()])
	return result


func save_config(config: Dictionary) -> Dictionary:
	_store_debug("save request id=%d name=%s engine=%s voice=%s active=%s enabled=%s" % [int(config.get("id", 0)), String(config.get("name", "")), String(config.get("engine", "")), _voice_debug(String(config.get("voice", ""))), str(bool(config.get("active", false))), str(bool(config.get("enabled", true)))])
	var payload := _call_json(SAVE_METHODS, [JSON.stringify(_config_payload(config))])
	if not bool(payload.get("ok", false)):
		return {"ok": false, "error": String(payload.get("error", "SQLite 声音配置保存失败"))}
	var source = payload.get("voice", payload.get("item", payload))
	if source is Dictionary:
		var normalized := _normalize_config(source as Dictionary)
		if not normalized.is_empty():
			normalized["ok"] = true
			_store_debug("save ok id=%d name=%s engine=%s voice=%s" % [int(normalized.get("id", 0)), String(normalized.get("name", "")), String(normalized.get("engine", "")), _voice_debug(String(normalized.get("voice", "")))])
			return normalized
	return {"ok": false, "error": "SQLite 声音配置返回格式错误"}


func delete_config(id: int) -> Dictionary:
	_store_debug("delete request id=%d" % id)
	if id <= 0:
		return {"ok": true}
	var payload := _call_json(DELETE_METHODS, [id])
	if not bool(payload.get("ok", false)):
		return {"ok": false, "error": String(payload.get("error", "SQLite 声音配置删除失败"))}
	return {"ok": true}


func _config_payload(config: Dictionary) -> Dictionary:
	return {
		"id": int(config.get("id", 0)),
		"name": String(config.get("name", "")).strip_edges(),
		"engine": String(config.get("engine", "system")).strip_edges(),
		"gender": String(config.get("gender", "女声")).strip_edges(),
		"voice": String(config.get("voice", "")).strip_edges(),
		"speed": String(config.get("speed", "0.90")).strip_edges(),
		"pitch": String(config.get("pitch", "1.00")).strip_edges(),
		"volume": String(config.get("volume", "1.00")).strip_edges(),
		"enabled": bool(config.get("enabled", true)),
		"active": bool(config.get("active", false)),
	}


func _normalize_config(config: Dictionary) -> Dictionary:
	var name := String(config.get("name", "")).strip_edges()
	var engine := String(config.get("engine", "system")).strip_edges()
	if name == "" or engine == "":
		return {}
	return {
		"id": int(config.get("id", 0)),
		"name": name,
		"engine": engine,
		"gender": String(config.get("gender", "女声")).strip_edges(),
		"voice": String(config.get("voice", "")).strip_edges(),
		"speed": String(config.get("speed", "0.90")).strip_edges(),
		"pitch": String(config.get("pitch", "1.00")).strip_edges(),
		"volume": String(config.get("volume", "1.00")).strip_edges(),
		"enabled": bool(config.get("enabled", true)),
		"active": bool(config.get("active", false)),
	}


func _call_json(methods: Array, args: Array) -> Dictionary:
	var plugin = _plugin()
	if plugin == null:
		return {"ok": false, "error": "Android 声音配置插件未接入：缺少 singleton %s" % singleton_name}
	var method := _method(plugin, methods)
	if method == "":
		_store_debug("call_json failed method=missing candidates=%s" % JSON.stringify(methods))
		return {"ok": false, "error": "Android 声音配置插件缺少方法"}
	_store_debug("call_json method=%s args=%d" % [method, args.size()])
	var parsed = _parse_json(plugin.callv(method, args))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {"ok": false, "error": "Android 声音配置插件返回格式错误"}


func _plugin():
	if Engine.has_singleton(singleton_name):
		return Engine.get_singleton(singleton_name)
	return null


func _method(plugin, methods: Array) -> String:
	for method in methods:
		if plugin.has_method(method):
			return method
	if plugin != null and not methods.is_empty():
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


func _voice_debug(voice: String) -> String:
	var clean := voice.strip_edges()
	return "<default>" if clean == "" else clean


func _store_debug(message: String) -> void:
	if OS.is_debug_build():
		if OS.is_debug_build():
			print("[AndroidVoiceConfigStore][debug] %s" % message)
