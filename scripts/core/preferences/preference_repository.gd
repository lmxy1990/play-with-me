extends RefCounted
class_name PreferenceRepository

const SAVE_PATH := "user://preferences.json"
const PreferenceDefaultsScript := preload("res://scripts/core/preferences/preference_defaults.gd")
const PreferenceSchemaScript := preload("res://scripts/core/preferences/preference_schema.gd")
const AvatarCatalogScript := preload("res://scripts/core/preferences/avatar_catalog.gd")

var save_path := SAVE_PATH
var persistence_enabled := true

var _state: Dictionary = {}
var _schema = PreferenceSchemaScript.new()
var _defaults = PreferenceDefaultsScript.new()
var _avatar_catalog = AvatarCatalogScript.new()


func ensure_preferences() -> Dictionary:
	if not persistence_enabled:
		if _state.is_empty():
			_state = _defaults.default_state()
		return _ok(_state, [])

	if not FileAccess.file_exists(save_path):
		_state = _defaults.default_state()
		return _save_or_error(_state, [])

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return _error("无法读取偏好设置文件", "read_failed")
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		var backup_path := _backup_corrupt_file()
		_state = _defaults.default_state()
		var warnings := ["preferences_json_recreated"]
		if backup_path != "":
			warnings.append("corrupt_backup:%s" % backup_path)
		return _save_or_error(_state, warnings)

	var normalized: Dictionary = _schema.normalize(parsed as Dictionary)
	_state = (normalized.get("state", {}) as Dictionary).duplicate(true)
	var warnings_value = normalized.get("warnings", [])
	var warnings: Array = warnings_value.duplicate(true) if warnings_value is Array else []
	if bool(normalized.get("changed", false)):
		return _save_or_error(_state, warnings)
	return _ok(_state, warnings)


func get_preferences() -> Dictionary:
	if _state.is_empty():
		return ensure_preferences()
	return _ok(_state, [])


func update_nickname(request: Dictionary) -> Dictionary:
	var ensured := ensure_preferences()
	if not bool(ensured.get("ok", false)):
		return ensured
	var validation := _schema.validate_nickname(String(request.get("nickname", "")))
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": String(validation.get("error", "")),
			"code": String(validation.get("code", "")),
			"state": _state.duplicate(true),
		}
	var next_state := _state.duplicate(true)
	next_state["nickname"] = String(validation.get("nickname", ""))
	next_state["updated_at"] = _timestamp()
	return _save_or_error(next_state, [])


func update_avatar(request: Dictionary) -> Dictionary:
	var ensured := ensure_preferences()
	if not bool(ensured.get("ok", false)):
		return ensured
	var validation := _schema.validate_avatar_id(String(request.get("avatar_id", "")))
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": String(validation.get("error", "")),
			"code": String(validation.get("code", "")),
			"state": _state.duplicate(true),
		}
	var next_state := _state.duplicate(true)
	next_state["avatar_id"] = String(validation.get("avatar_id", ""))
	next_state["updated_at"] = _timestamp()
	return _save_or_error(next_state, [])


func update_playback_voice_config(request: Dictionary) -> Dictionary:
	var ensured := ensure_preferences()
	if not bool(ensured.get("ok", false)):
		return ensured
	var validation := _schema.validate_playback_voice_config_id(String(request.get("playback_voice_config_id", "")))
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": String(validation.get("error", "")),
			"code": String(validation.get("code", "")),
			"state": _state.duplicate(true),
		}
	var next_state := _state.duplicate(true)
	next_state["playback_voice_config_id"] = String(validation.get("playback_voice_config_id", ""))
	next_state["updated_at"] = _timestamp()
	return _save_or_error(next_state, [])


func list_avatars(_request: Dictionary = {}) -> Dictionary:
	return {
		"ok": true,
		"avatars": _avatar_catalog.list(),
		"default_avatar_id": _avatar_catalog.default_avatar_id(),
		"error": "",
	}


func get_device_private_key_view(_request: Dictionary = {}) -> Dictionary:
	var ensured := ensure_preferences()
	if not bool(ensured.get("ok", false)):
		return ensured
	return {
		"ok": true,
		"readonly": true,
		"value": String(_state.get("device_private_key", "")),
		"error": "",
	}


func get_preferences_debug_state(_request: Dictionary = {}) -> Dictionary:
	var state := _state
	if state.is_empty():
		var ensured := ensure_preferences()
		if bool(ensured.get("ok", false)):
			state = ensured.get("state", {})
	var file_exists := FileAccess.file_exists(save_path) if persistence_enabled else not state.is_empty()
	return {
		"ok": true,
		"file_exists": file_exists,
		"state": _schema.public_debug_state(state),
		"error": "",
	}


func _save_or_error(state: Dictionary, warnings: Array) -> Dictionary:
	if not persistence_enabled:
		_state = state.duplicate(true)
		return _ok(_state, warnings)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return _error("无法保存偏好设置文件", "write_failed")
	file.store_string(JSON.stringify(_stored_state(state), "\t"))
	_state = state.duplicate(true)
	return _ok(_state, warnings)


func _stored_state(state: Dictionary) -> Dictionary:
	return {
		"schema_version": int(state.get("schema_version", 2)),
		"nickname": String(state.get("nickname", "")),
		"avatar_id": String(state.get("avatar_id", "")),
		"playback_voice_config_id": String(state.get("playback_voice_config_id", "")),
		"device_private_key": String(state.get("device_private_key", "")),
		"created_at": String(state.get("created_at", "")),
		"updated_at": String(state.get("updated_at", "")),
	}


func _backup_corrupt_file() -> String:
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return ""
	var backup_path := "%s.corrupt.%d" % [save_path, Time.get_unix_time_from_system()]
	var backup := FileAccess.open(backup_path, FileAccess.WRITE)
	if backup == null:
		return ""
	backup.store_string(file.get_as_text())
	return backup_path


func _ok(state: Dictionary, warnings: Array) -> Dictionary:
	return {
		"ok": true,
		"state": state.duplicate(true),
		"warnings": warnings.duplicate(true),
		"error": "",
	}


func _error(message: String, code: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"code": code,
	}


func _timestamp() -> String:
	return "%sZ" % Time.get_datetime_string_from_system(true)
