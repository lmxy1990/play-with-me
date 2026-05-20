extends SceneTree

const PreferenceRepositoryScript := preload("res://scripts/core/preferences/preference_repository.gd")
const DeviceIdentityScript := preload("res://scripts/core/device_identity.gd")


func _initialize() -> void:
	var repo = PreferenceRepositoryScript.new()
	repo.persistence_enabled = false

	var ensured: Dictionary = repo.ensure_preferences()
	assert(bool(ensured.get("ok", false)))
	var state: Dictionary = ensured.get("state", {})
	assert(int(state.get("schema_version", 0)) == 2)
	assert(String(state.get("nickname", "")).begins_with("玩家"))
	assert(String(state.get("avatar_id", "")) == "animal_fox_01")
	assert(String(state.get("playback_voice_config_id", "")) == "voice_system_default")
	assert(String(state.get("device_private_key", "")) != "")

	var avatars: Dictionary = repo.list_avatars()
	assert(bool(avatars.get("ok", false)))
	assert((avatars.get("avatars", []) as Array).size() == 24)
	assert(String(avatars.get("default_avatar_id", "")) == "animal_fox_01")

	var updated_name: Dictionary = repo.update_nickname({"nickname": "  阿景  "})
	assert(bool(updated_name.get("ok", false)))
	assert(String((updated_name.get("state", {}) as Dictionary).get("nickname", "")) == "阿景")
	var bad_name: Dictionary = repo.update_nickname({"nickname": "坏\n名字"})
	assert(not bool(bad_name.get("ok", false)))
	assert(String((repo.get_preferences().get("state", {}) as Dictionary).get("nickname", "")) == "阿景")

	var updated_avatar: Dictionary = repo.update_avatar({"avatar_id": "person_girl_06"})
	assert(bool(updated_avatar.get("ok", false)))
	assert(String((updated_avatar.get("state", {}) as Dictionary).get("avatar_id", "")) == "person_girl_06")
	var bad_avatar: Dictionary = repo.update_avatar({"avatar_id": "res://external.png"})
	assert(not bool(bad_avatar.get("ok", false)))

	var updated_voice: Dictionary = repo.update_playback_voice_config({"playback_voice_config_id": "voice_config_7"})
	assert(bool(updated_voice.get("ok", false)))
	assert(String((updated_voice.get("state", {}) as Dictionary).get("playback_voice_config_id", "")) == "voice_config_7")
	var bad_voice: Dictionary = repo.update_playback_voice_config({"playback_voice_config_id": "voice config 7"})
	assert(not bool(bad_voice.get("ok", false)))

	var secret_view: Dictionary = repo.get_device_private_key_view()
	assert(bool(secret_view.get("ok", false)))
	assert(bool(secret_view.get("readonly", false)))
	assert(String(secret_view.get("value", "")) == String(state.get("device_private_key", "")))

	var debug: Dictionary = repo.get_preferences_debug_state()
	assert(bool(debug.get("ok", false)))
	var debug_state: Dictionary = debug.get("state", {})
	assert(not debug_state.has("device_private_key"))
	assert(bool(debug_state.get("has_device_private_key", false)))

	var existing_key := "existing_private_key"
	var identity: Dictionary = DeviceIdentityScript.identity_from_private_key(existing_key)
	assert(String(identity.get("deviceId", "")).begins_with("device_"))
	assert(String(identity.get("publicKey", "")) != "")
	var auth: Dictionary = DeviceIdentityScript.auth_payload_from_identity({
		"device_private_key": existing_key,
	}, "challenge")
	assert(DeviceIdentityScript.verify_auth_payload(auth, "challenge"))
	assert(not DeviceIdentityScript.verify_auth_payload(auth, "wrong_challenge"))
	quit()
