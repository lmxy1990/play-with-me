extends RefCounted
class_name PreferenceDefaults

const DeviceIdentityScript := preload("res://scripts/core/device_identity.gd")
const AvatarCatalogScript := preload("res://scripts/core/preferences/avatar_catalog.gd")

const DEFAULT_PLAYBACK_VOICE_CONFIG_ID := "voice_system_default"

var _avatar_catalog = AvatarCatalogScript.new()


func default_state() -> Dictionary:
	var now := _timestamp()
	return {
		"schema_version": 2,
		"nickname": default_nickname(),
		"avatar_id": _avatar_catalog.default_avatar_id(),
		"playback_voice_config_id": default_playback_voice_config_id(),
		"device_private_key": default_device_private_key(),
		"created_at": now,
		"updated_at": now,
	}


func default_nickname() -> String:
	var bytes := Crypto.new().generate_random_bytes(2)
	var raw := 0
	if bytes.size() >= 2:
		raw = (int(bytes[0]) << 8) | int(bytes[1])
	else:
		raw = int(Time.get_ticks_usec() % 65535)
	return "玩家%d" % [1000 + raw % 9000]


func default_device_private_key() -> String:
	return DeviceIdentityScript.generate_private_key()


func default_playback_voice_config_id() -> String:
	return DEFAULT_PLAYBACK_VOICE_CONFIG_ID


func _timestamp() -> String:
	return "%sZ" % Time.get_datetime_string_from_system(true)
