extends "res://scripts/pages/base/page_room_discovery_ui_base.gd"

const DeviceIdentityScript := preload("res://scripts/core/device_identity.gd")
const RoomSessionStoreScript := preload("res://scripts/room/room_session_store.gd")

var _local_nickname := "阿景"
var _device_identity = DeviceIdentityScript.new()
var _room_session_store = RoomSessionStoreScript.new()
var _room_network_session
var _preference_repository


func set_preference_repository(repository) -> void:
	_preference_repository = repository
	_sync_preference_repository_persistence()
	_apply_preference_identity_to_runtime()


func _ensure_preference_repository():
	if _preference_repository == null:
		var repository_script := load("res://scripts/core/preferences/preference_repository.gd")
		if repository_script != null:
			_preference_repository = repository_script.new()
	_sync_preference_repository_persistence()
	return _preference_repository


func _sync_preference_repository_persistence() -> void:
	if _preference_repository == null or _app_state == null:
		return
	_preference_repository.persistence_enabled = bool(_app_state.persistence_enabled)


func _apply_preference_identity_to_runtime() -> void:
	if _preference_repository == null:
		return
	_sync_preference_repository_persistence()
	var result: Dictionary = _preference_repository.get_preferences()
	if not bool(result.get("ok", false)):
		return
	var state: Dictionary = result.get("state", {})
	var nickname := String(state.get("nickname", "")).strip_edges()
	if nickname == "":
		return
	_local_nickname = nickname
	if _app_state != null:
		_app_state.local_nickname = nickname


func _preference_identity_snapshot() -> Dictionary:
	var nickname := _local_nickname.strip_edges()
	var avatar_id := ""
	var avatar_path := ""
	var playback_voice_config_id := "voice_system_default"
	var repository = _ensure_preference_repository()
	if repository != null:
		var result: Dictionary = repository.get_preferences()
		if bool(result.get("ok", false)):
			var state: Dictionary = result.get("state", {})
			var preferred_name := String(state.get("nickname", "")).strip_edges()
			if preferred_name != "":
				nickname = preferred_name
			avatar_id = String(state.get("avatar_id", "")).strip_edges()
			playback_voice_config_id = String(state.get("playback_voice_config_id", playback_voice_config_id)).strip_edges()
			avatar_path = _preference_avatar_path(avatar_id)
	if nickname == "":
		nickname = "玩家"
	if playback_voice_config_id == "":
		playback_voice_config_id = "voice_system_default"
	return {
		"nickname": nickname,
		"displayName": nickname,
		"avatar_id": avatar_id,
		"avatarId": avatar_id,
		"avatar": avatar_path,
		"playback_voice_config_id": playback_voice_config_id,
		"playbackVoiceConfigId": playback_voice_config_id,
		"voice_config_id": playback_voice_config_id,
		"voiceConfigId": playback_voice_config_id,
	}


func _preference_avatar_path(avatar_id: String) -> String:
	var clean := avatar_id.strip_edges()
	if clean == "":
		return ""
	var repository = _ensure_preference_repository()
	if repository == null or not repository.has_method("list_avatars"):
		return ""
	var result: Dictionary = repository.list_avatars()
	if not bool(result.get("ok", false)):
		return ""
	var avatars_value = result.get("avatars", [])
	if not (avatars_value is Array):
		return ""
	for item in avatars_value as Array:
		if item is Dictionary and String((item as Dictionary).get("id", "")).strip_edges() == clean:
			return String((item as Dictionary).get("path", "")).strip_edges()
	return ""


func _preference_identity_network_payload() -> Dictionary:
	var identity := _preference_identity_snapshot()
	return {
		"avatarId": String(identity.get("avatarId", "")),
		"avatar": String(identity.get("avatar", "")),
		"playbackVoiceConfigId": String(identity.get("playbackVoiceConfigId", "")),
		"voiceConfigId": String(identity.get("voiceConfigId", "")),
	}


func _ensure_device_identity_loaded() -> void:
	if _app_state != null:
		_device_identity.persistence_enabled = bool(_app_state.persistence_enabled)
		_room_session_store.persistence_enabled = bool(_app_state.persistence_enabled)
		var cached_identity: Dictionary = _app_state.device_identity_json
		if not cached_identity.is_empty():
			_device_identity._apply_json(cached_identity)
	_device_identity.load_or_create()
	if _app_state != null and _app_state.device_identity_json.is_empty():
		_app_state.device_identity_json = _device_identity.to_stored_json()


func _apply_network_identity() -> void:
	if _room_network_session == null:
		return
	if _room_network_session.has_method("set_device_identity"):
		_room_network_session.call("set_device_identity", _device_identity.to_stored_json())


func _apply_mobile_orientation() -> void:
	if OS.get_name() != "Android":
		return
	if ClassDB.class_has_method("DisplayServer", "screen_set_orientation"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
