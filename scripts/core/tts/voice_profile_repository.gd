extends RefCounted
class_name TtsVoiceProfileRepository

signal profiles_changed(profiles: Array)

const AndroidVoiceConfigStoreScript := preload("res://scripts/core/tts/adapters/android_voice_config_store.gd")
const TtsVoiceProfileSchemaScript := preload("res://scripts/core/tts/voice_profile_schema.gd")

var persistence_enabled := true

var _store = AndroidVoiceConfigStoreScript.new()
var _schema = TtsVoiceProfileSchemaScript.new()
var _profiles: Array = []


func set_persistence_enabled(enabled: bool) -> void:
	persistence_enabled = enabled
	_store.persistence_enabled = enabled


func load_or_seed(seed_profiles: Array = []) -> Array:
	_store.persistence_enabled = persistence_enabled
	_profiles = _schema.normalize_profiles(seed_profiles)
	if not _store.is_available():
		_repository_debug("store unavailable; using seed count=%d" % _profiles.size())
		_emit_profiles_changed()
		return list_profiles()

	var stored := _store.list_configs()
	_repository_debug("store loaded count=%d seed_count=%d" % [stored.size(), _profiles.size()])
	if stored.is_empty() and not _profiles.is_empty():
		for item in _profiles:
			if item is Dictionary:
				_store.save_config(item as Dictionary)
		stored = _store.list_configs()
	if not stored.is_empty():
		_profiles = _schema.normalize_profiles(stored)
	_emit_profiles_changed()
	return list_profiles()


func reload_from_storage() -> Array:
	return load_or_seed(_profiles)


func set_profiles(configs: Array) -> Array:
	_profiles = _schema.normalize_profiles(configs)
	_emit_profiles_changed()
	return list_profiles()


func list_profiles() -> Array:
	var result: Array = []
	for item in _profiles:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func profile_at(index: int) -> Dictionary:
	if index >= 0 and index < _profiles.size() and _profiles[index] is Dictionary:
		return (_profiles[index] as Dictionary).duplicate(true)
	return {}


func normalize_profiles(configs: Array) -> Array:
	return _schema.normalize_profiles(configs)


func enforce_active_unique(configs: Array) -> Array:
	return _schema.enforce_active_unique(configs)


func active_profile(configs: Array = []) -> Dictionary:
	return _schema.active_profile(_profiles if configs.is_empty() else configs)


func playback_profile(profile_key: String, configs: Array = []) -> Dictionary:
	return _schema.playback_profile(_profiles if configs.is_empty() else configs, profile_key)


func storage_available() -> bool:
	_store.persistence_enabled = persistence_enabled
	return _store.is_available()


func save_profile(index: int, request: Dictionary) -> Dictionary:
	_store.persistence_enabled = persistence_enabled
	var normalized_engine := _schema.normalize_engine(String(request.get("engine", "system")))
	var gender := String(request.get("gender", "女声")).strip_edges()
	var display_name := String(request.get("name", "")).strip_edges()
	if display_name == "":
		display_name = next_default_name(normalized_engine, gender, index)
	var enabled := bool(request.get("enabled", true))
	var active := bool(request.get("active", false))
	if active:
		enabled = true
	var id := _schema.existing_id(_profiles, index)
	if id <= 0 and not storage_available():
		id = _schema.next_local_id(_profiles)
	var item := _schema.build_profile(
		id,
		display_name,
		normalized_engine,
		gender,
		String(request.get("voice", "")),
		String(request.get("speed", "0.90")),
		String(request.get("pitch", "1.00")),
		String(request.get("volume", "1.00")),
		enabled,
		active
	)
	if item.is_empty():
		return _error("声音配置格式错误")

	if storage_available():
		var saved := _store.save_config(item)
		if not bool(saved.get("ok", false)):
			return _error(String(saved.get("error", "声音保存失败")))
		saved.erase("ok")
		_profiles = _upsert(_profiles, index, saved)
		var stored := _store.list_configs()
		_profiles = _schema.normalize_profiles(stored if not stored.is_empty() else _profiles)
	else:
		_profiles = _schema.normalize_profiles(_upsert(_profiles, index, item))
	_emit_profiles_changed()
	return _ok(profile_at(_find_profile_index_by_id(int(item.get("id", 0)))), list_profiles())


func delete_profile(index: int) -> Dictionary:
	_store.persistence_enabled = persistence_enabled
	if index >= 0 and index < _profiles.size() and _profiles[index] is Dictionary and storage_available():
		var id := int((_profiles[index] as Dictionary).get("id", 0))
		var deleted := _store.delete_config(id)
		if not bool(deleted.get("ok", false)):
			return _error(String(deleted.get("error", "声音删除失败")))
	_profiles = _schema.normalize_profiles(_delete_at(_profiles, index))
	if storage_available():
		var stored := _store.list_configs()
		if not stored.is_empty():
			_profiles = _schema.normalize_profiles(stored)
	_emit_profiles_changed()
	return _ok({}, list_profiles())


func configure_runtime(runtime) -> Dictionary:
	if runtime == null or not runtime.has_method("configure_voice_configs"):
		return {"ok": true, "configured": false, "profiles": list_profiles()}
	var result: Dictionary = runtime.call("configure_voice_configs", _profiles)
	if not bool(result.get("ok", true)):
		_repository_debug("engine service configure warning=%s" % JSON.stringify(result))
	return result


func next_default_name(engine: String, gender: String, edit_index: int = -1) -> String:
	var normalized_engine := _schema.normalize_engine(engine)
	var prefix := "%s%s" % [_schema.engine_label(normalized_engine), gender.strip_edges()]
	var max_number := 0
	for i in range(_profiles.size()):
		if i == edit_index or not (_profiles[i] is Dictionary):
			continue
		var existing := String((_profiles[i] as Dictionary).get("name", "")).strip_edges()
		if not existing.begins_with(prefix):
			continue
		var suffix := existing.substr(prefix.length()).strip_edges()
		if suffix.is_valid_int():
			max_number = maxi(max_number, int(suffix))
		else:
			max_number = maxi(max_number, 1)
	return "%s%d" % [prefix, max_number + 1]


func _upsert(configs: Array, index: int, item: Dictionary) -> Array:
	var next := configs.duplicate(true)
	if index >= 0 and index < next.size():
		next[index] = item.duplicate(true)
	else:
		next.append(item.duplicate(true))
	return next


func _delete_at(configs: Array, index: int) -> Array:
	var next := configs.duplicate(true)
	if index >= 0 and index < next.size():
		next.remove_at(index)
	return next


func _find_profile_index_by_id(id: int) -> int:
	if id <= 0:
		return _profiles.size() - 1
	for i in range(_profiles.size()):
		if _profiles[i] is Dictionary and int((_profiles[i] as Dictionary).get("id", 0)) == id:
			return i
	return _profiles.size() - 1


func _emit_profiles_changed() -> void:
	profiles_changed.emit(list_profiles())


func _ok(profile: Dictionary, profiles: Array) -> Dictionary:
	return {
		"ok": true,
		"profile": profile.duplicate(true),
		"profiles": profiles.duplicate(true),
		"error": "",
	}


func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"profiles": list_profiles(),
	}


func _repository_debug(message: String) -> void:
	if OS.is_debug_build():
		if OS.is_debug_build():
			print("[TtsVoiceProfileRepository][debug] %s" % message)
