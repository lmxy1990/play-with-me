extends RefCounted
class_name PreferenceSchema

const SCHEMA_VERSION := 2
const MAX_NICKNAME_LENGTH := 16
const MAX_PLAYBACK_VOICE_CONFIG_ID_LENGTH := 64
const AvatarCatalogScript := preload("res://scripts/core/preferences/avatar_catalog.gd")
const PreferenceDefaultsScript := preload("res://scripts/core/preferences/preference_defaults.gd")

var _avatar_catalog = AvatarCatalogScript.new()
var _defaults = PreferenceDefaultsScript.new()


func normalize(data: Dictionary) -> Dictionary:
	var warnings: Array = []
	var changed := false
	var now := _timestamp()
	var state := data.duplicate(true)

	if int(state.get("schema_version", 0)) != SCHEMA_VERSION:
		return {
			"ok": true,
			"state": _defaults.default_state(),
			"changed": true,
			"warnings": [],
		}

	var nickname_result := validate_nickname(String(state.get("nickname", "")))
	if bool(nickname_result.get("ok", false)):
		var next_nickname := String(nickname_result.get("nickname", ""))
		if next_nickname != String(state.get("nickname", "")):
			changed = true
		state["nickname"] = next_nickname
	else:
		state["nickname"] = _defaults.default_nickname()
		changed = true
		warnings.append("nickname_defaulted")

	var avatar_id := String(state.get("avatar_id", "")).strip_edges()
	if not _avatar_catalog.has_avatar(avatar_id):
		state["avatar_id"] = _avatar_catalog.default_avatar_id()
		changed = true
		warnings.append("avatar_defaulted")
	else:
		state["avatar_id"] = avatar_id

	var voice_result := validate_playback_voice_config_id(String(state.get("playback_voice_config_id", "")))
	if bool(voice_result.get("ok", false)):
		var next_voice_config_id := String(voice_result.get("playback_voice_config_id", ""))
		if next_voice_config_id != String(state.get("playback_voice_config_id", "")):
			changed = true
		state["playback_voice_config_id"] = next_voice_config_id
	else:
		state["playback_voice_config_id"] = _defaults.default_playback_voice_config_id()
		changed = true
		warnings.append("playback_voice_config_defaulted")

	var private_key := String(state.get("device_private_key", "")).strip_edges()
	if private_key == "":
		state["device_private_key"] = _defaults.default_device_private_key()
		changed = true
		warnings.append("device_private_key_created")
	else:
		state["device_private_key"] = private_key

	if String(state.get("created_at", "")).strip_edges() == "":
		state["created_at"] = now
		changed = true
	if String(state.get("updated_at", "")).strip_edges() == "":
		state["updated_at"] = now
		changed = true

	if changed:
		state["updated_at"] = now

	return {
		"ok": true,
		"state": state,
		"changed": changed,
		"warnings": warnings,
	}


func validate_nickname(nickname: String) -> Dictionary:
	var clean := nickname.strip_edges()
	if clean == "":
		return _error("昵称不能为空", "empty_nickname")
	if clean.length() > MAX_NICKNAME_LENGTH:
		return _error("昵称不能超过 %d 个字符" % MAX_NICKNAME_LENGTH, "nickname_too_long")
	for i in range(clean.length()):
		var code := clean.unicode_at(i)
		if code < 32 or code == 127:
			return _error("昵称不能包含控制字符", "invalid_nickname_char")
	return {
		"ok": true,
		"nickname": clean,
		"error": "",
	}


func validate_avatar_id(avatar_id: String) -> Dictionary:
	var clean := avatar_id.strip_edges()
	if not _avatar_catalog.has_avatar(clean):
		return _error("头像不存在", "unknown_avatar")
	return {
		"ok": true,
		"avatar_id": clean,
		"error": "",
	}


func validate_playback_voice_config_id(config_id: String) -> Dictionary:
	var clean := config_id.strip_edges()
	if clean == "":
		return _error("播放声音配置不能为空", "empty_playback_voice_config")
	if clean.length() > MAX_PLAYBACK_VOICE_CONFIG_ID_LENGTH:
		return _error("播放声音配置 ID 过长", "playback_voice_config_id_too_long")
	for i in range(clean.length()):
		var code := clean.unicode_at(i)
		var valid := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 95
		if not valid:
			return _error("播放声音配置 ID 格式错误", "invalid_playback_voice_config_id")
	return {
		"ok": true,
		"playback_voice_config_id": clean,
		"error": "",
	}


func public_debug_state(state: Dictionary) -> Dictionary:
	return {
		"schema_version": int(state.get("schema_version", 0)),
		"nickname": String(state.get("nickname", "")),
		"avatar_id": String(state.get("avatar_id", "")),
		"playback_voice_config_id": String(state.get("playback_voice_config_id", "")),
		"has_device_private_key": String(state.get("device_private_key", "")).strip_edges() != "",
		"created_at": String(state.get("created_at", "")),
		"updated_at": String(state.get("updated_at", "")),
	}


func _timestamp() -> String:
	return "%sZ" % Time.get_datetime_string_from_system(true)


func _error(message: String, code: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"code": code,
	}
