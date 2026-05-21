extends RefCounted

signal profiles_changed(profiles: Array)

const BotProfileSchemaScript := preload("res://scripts/core/bot/bot_profile_schema.gd")

var _schema = BotProfileSchemaScript.new()
var _profiles: Array = []


func load_or_seed(seed_profiles: Array = []) -> Array:
	_profiles = _schema.normalize_profiles(seed_profiles)
	_repository_debug("load_or_seed seed=%d normalized=%d enabled=%d" % [seed_profiles.size(), _profiles.size(), enabled_profiles().size()])
	_emit_profiles_changed()
	return list_profiles()


func set_profiles(configs: Array) -> Array:
	_profiles = _schema.normalize_profiles(configs)
	_repository_debug("set_profiles input=%d normalized=%d enabled=%d" % [configs.size(), _profiles.size(), enabled_profiles().size()])
	_emit_profiles_changed()
	return list_profiles()


func list_profiles() -> Array:
	var result: Array = []
	for item in _profiles:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func enabled_profiles() -> Array:
	var result: Array = []
	for item in _profiles:
		if item is Dictionary and bool((item as Dictionary).get("enabled", true)):
			result.append((item as Dictionary).duplicate(true))
	return result


func profile_at(index: int) -> Dictionary:
	if index >= 0 and index < _profiles.size() and _profiles[index] is Dictionary:
		return (_profiles[index] as Dictionary).duplicate(true)
	return {}


func profile_by_key(profile_key: String) -> Dictionary:
	var key := profile_key.strip_edges()
	if key == "":
		_repository_debug("profile_by_key empty key")
		return {}
	for item in _profiles:
		if not (item is Dictionary):
			continue
		var profile: Dictionary = item
		if String(profile.get("id", "")).strip_edges() == key or String(profile.get("name", "")).strip_edges() == key:
			_repository_debug("profile_by_key hit key=%s id=%s enabled=%s" % [key, String(profile.get("id", "")), str(bool(profile.get("enabled", true)))])
			return profile.duplicate(true)
	_repository_debug("profile_by_key miss key=%s total=%d" % [key, _profiles.size()])
	return {}


func first_enabled_profile() -> Dictionary:
	for item in _profiles:
		if item is Dictionary and bool((item as Dictionary).get("enabled", true)):
			return (item as Dictionary).duplicate(true)
	return {}


func save_profile(index: int, request: Dictionary) -> Dictionary:
	var existing_profile: Dictionary = profile_at(index)
	var id := _schema.existing_id(_profiles, index)
	if id == "":
		id = String(request.get("id", request.get("bot_id", ""))).strip_edges()
	if id == "":
		id = _next_id()
	var memory_data: Dictionary = {}
	if request.get("memory", null) is Dictionary:
		memory_data = request.get("memory", {}) as Dictionary
	else:
		memory_data = _schema.existing_memory(_profiles, index)
	var model := String(request.get("model", existing_profile.get("model", ""))).strip_edges()
	var name := String(request.get("name", "")).strip_edges()
	if name == "":
		name = String(request.get("display_name", existing_profile.get("display_name", ""))).strip_edges()
	if name == "":
		name = model
	if name == "":
		name = next_default_name(index)
	var now := int(Time.get_unix_time_from_system())
	var created_at := int(request.get("created_at", existing_profile.get("created_at", now)))
	var extra := {
		"schema_version": int(request.get("schema_version", existing_profile.get("schema_version", 1))),
		"bot_id": id,
		"display_name": name,
		"persona_id": String(request.get("persona_id", existing_profile.get("persona_id", ""))),
		"personality": _dict_or_empty(request.get("personality", existing_profile.get("personality", {}))),
		"speaking_style": String(request.get("speaking_style", existing_profile.get("speaking_style", ""))),
		"strategy_style": String(request.get("strategy_style", existing_profile.get("strategy_style", ""))),
		"background_story": String(request.get("background_story", existing_profile.get("background_story", ""))),
		"created_at": created_at,
		"updated_at": int(request.get("updated_at", now)),
	}
	var item := _schema.build_profile(
		id,
		name,
		String(request.get("description", existing_profile.get("description", ""))),
		String(request.get("persona", existing_profile.get("persona", ""))),
		model,
		String(request.get("voice", existing_profile.get("voice", ""))),
		bool(request.get("enabled", existing_profile.get("enabled", true))),
		memory_data,
		String(request.get("avatar_id", request.get("avatar", existing_profile.get("avatar_id", "")))),
		extra
	)
	if item.is_empty():
		_repository_debug("save_profile failed index=%d requested_name=%s" % [index, name])
		return _error("机器人配置格式错误")
	_profiles = _schema.normalize_profiles(_upsert(_profiles, index, item))
	_repository_debug("save_profile index=%d id=%s name=%s model=%s voice=%s enabled=%s memory_fields=%s total=%d" % [
		index,
		String(item.get("id", "")),
		String(item.get("name", "")),
		String(item.get("model", "")),
		String(item.get("voice", "")),
		str(bool(item.get("enabled", true))),
		_memory_field_flags(item.get("memory", {})),
		_profiles.size(),
	])
	_emit_profiles_changed()
	return _ok(profile_at(_find_profile_index_by_id(id)), list_profiles())


func delete_profile(index: int) -> Dictionary:
	var deleted_id := ""
	var deleted_name := ""
	if index >= 0 and index < _profiles.size() and _profiles[index] is Dictionary:
		deleted_id = String((_profiles[index] as Dictionary).get("id", ""))
		deleted_name = String((_profiles[index] as Dictionary).get("name", ""))
	_profiles = _schema.normalize_profiles(_delete_at(_profiles, index))
	_repository_debug("delete_profile index=%d id=%s name=%s total=%d" % [index, deleted_id, deleted_name, _profiles.size()])
	_emit_profiles_changed()
	return _ok({}, list_profiles())


func summary_for_bot(profile_key: String) -> String:
	var profile := profile_by_key(profile_key)
	if profile.is_empty():
		_repository_debug("summary_for_bot empty key=%s" % profile_key)
		return ""
	var summary := _schema.profile_summary(profile)
	_repository_debug("summary_for_bot key=%s id=%s chars=%d" % [profile_key, String(profile.get("id", "")), summary.length()])
	return summary


func next_default_name(edit_index: int = -1) -> String:
	var max_number := 0
	for i in range(_profiles.size()):
		if i == edit_index or not (_profiles[i] is Dictionary):
			continue
		var existing := String((_profiles[i] as Dictionary).get("name", "")).strip_edges()
		if not existing.begins_with("机器人"):
			continue
		var suffix := existing.substr("机器人".length()).strip_edges()
		if suffix.is_valid_int():
			max_number = maxi(max_number, int(suffix))
		else:
			max_number = maxi(max_number, 1)
	return "机器人%d" % [max_number + 1]


func normalize_memory(value) -> Dictionary:
	return _schema.normalize_memory(value)


func _next_id() -> String:
	var existing := {}
	for item in _profiles:
		if item is Dictionary:
			existing[String((item as Dictionary).get("id", ""))] = true
	for _attempt in range(20):
		var candidate := "bot_%d" % Time.get_ticks_usec()
		if not existing.has(candidate):
			return candidate
	return "bot_%d_%d" % [Time.get_ticks_usec(), randi()]


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


func _find_profile_index_by_id(id: String) -> int:
	for i in range(_profiles.size()):
		if _profiles[i] is Dictionary and String((_profiles[i] as Dictionary).get("id", "")) == id:
			return i
	return _profiles.size() - 1


func _emit_profiles_changed() -> void:
	_repository_debug("profiles_changed total=%d enabled=%d" % [_profiles.size(), enabled_profiles().size()])
	profiles_changed.emit(list_profiles())


func _memory_field_flags(value) -> String:
	var memory := _schema.normalize_memory(value)
	var parts := []
	for key in ["profile", "working", "long_term", "notes"]:
		if String(memory.get(key, "")).strip_edges() != "":
			parts.append(key)
	return "none" if parts.is_empty() else ",".join(parts)


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


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
			print("[BotProfileRepository][debug] %s" % message)
