extends RefCounted

const PROFILE_SCHEMA_VERSION := 1


func normalize_profiles(configs: Array) -> Array:
	var result: Array = []
	for item in configs:
		if item is Dictionary:
			var profile := normalize_profile(item)
			if not profile.is_empty():
				result.append(profile)
	return result


func normalize_profile(config: Dictionary) -> Dictionary:
	var model := String(config.get("model", "")).strip_edges()
	var name := String(config.get("name", config.get("display_name", ""))).strip_edges()
	if name == "" and model != "":
		name = model
	if name == "":
		return {}
	var id := String(config.get("id", config.get("bot_id", ""))).strip_edges()
	if id == "":
		id = "bot_%d" % Time.get_ticks_usec()
	var now := int(Time.get_unix_time_from_system())
	var created_at := int(config.get("created_at", now))
	var updated_at := int(config.get("updated_at", now))
	return {
		"schema_version": int(config.get("schema_version", PROFILE_SCHEMA_VERSION)),
		"id": id,
		"bot_id": id,
		"name": name,
		"display_name": name,
		"avatar_id": String(config.get("avatar_id", config.get("avatar", ""))).strip_edges(),
		"persona_id": String(config.get("persona_id", "")).strip_edges(),
		"description": String(config.get("description", "")).strip_edges(),
		"persona": String(config.get("persona", "")).strip_edges(),
		"personality": _dict_or_empty(config.get("personality", {})),
		"speaking_style": String(config.get("speaking_style", "")).strip_edges(),
		"strategy_style": String(config.get("strategy_style", "")).strip_edges(),
		"background_story": String(config.get("background_story", "")).strip_edges(),
		"model": model,
		"voice": String(config.get("voice", "")).strip_edges(),
		"enabled": bool(config.get("enabled", true)),
		"memory": normalize_memory(config.get("memory", {})),
		"created_at": created_at,
		"updated_at": updated_at,
	}


func normalize_memory(value) -> Dictionary:
	var source: Dictionary = {}
	if value is Dictionary:
		source = value
	return {
		"profile": String(source.get("profile", "")).strip_edges(),
		"working": String(source.get("working", "")).strip_edges(),
		"long_term": String(source.get("long_term", "")).strip_edges(),
		"notes": String(source.get("notes", "")).strip_edges(),
		"updated_at": int(source.get("updated_at", 0)),
	}


func build_profile(id: String, name: String, description: String, persona: String, model: String, voice: String, enabled: bool, memory: Dictionary = {}, avatar_id: String = "", extra: Dictionary = {}) -> Dictionary:
	var clean_id := id.strip_edges()
	var clean_name := name.strip_edges()
	if clean_name == "":
		clean_name = model.strip_edges()
	if clean_name == "":
		clean_name = "未命名机器人"
	if clean_id == "":
		clean_id = "bot_%d" % Time.get_ticks_usec()
	var payload := extra.duplicate(true)
	payload.merge({
		"id": clean_id,
		"name": clean_name,
		"avatar_id": avatar_id,
		"description": description,
		"persona": persona,
		"model": model,
		"voice": voice,
		"enabled": enabled,
		"memory": memory,
	}, true)
	return normalize_profile(payload)


func existing_id(configs: Array, index: int) -> String:
	if index >= 0 and index < configs.size() and configs[index] is Dictionary:
		return String((configs[index] as Dictionary).get("id", "")).strip_edges()
	return ""


func existing_memory(configs: Array, index: int) -> Dictionary:
	if index >= 0 and index < configs.size() and configs[index] is Dictionary:
		return normalize_memory((configs[index] as Dictionary).get("memory", {}))
	return normalize_memory({})


func profile_summary(profile: Dictionary) -> String:
	var parts: Array = []
	var persona := String(profile.get("persona", "")).strip_edges()
	var background_story := String(profile.get("background_story", "")).strip_edges()
	var speaking_style := String(profile.get("speaking_style", "")).strip_edges()
	var strategy_style := String(profile.get("strategy_style", "")).strip_edges()
	var memory := normalize_memory(profile.get("memory", {}))
	var profile_memory := String(memory.get("profile", "")).strip_edges()
	var long_term := String(memory.get("long_term", "")).strip_edges()
	if persona != "":
		parts.append(persona)
	if background_story != "":
		parts.append(background_story)
	if speaking_style != "":
		parts.append("表达风格：%s" % speaking_style)
	if strategy_style != "":
		parts.append("长期策略偏好：%s" % strategy_style)
	if profile_memory != "":
		parts.append(profile_memory)
	if long_term != "":
		parts.append(long_term)
	return "\n".join(parts)


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
