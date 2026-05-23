extends SceneTree

const RegistryScript := preload("res://scripts/room/network/room_participant_registry.gd")


func _initialize() -> void:
	var registry = RegistryScript.new()
	_check_auth_payload(registry)
	_check_identity_match(registry)
	_check_reconnect_tokens(registry)
	_check_observer_registry(registry)
	_check_base64_url(registry)
	quit()


func _check_auth_payload(registry) -> void:
	var direct: Dictionary = registry.auth_payload({"auth": {"deviceId": "d1", "publicKey": "p1"}})
	assert(String(direct.get("deviceId", "")) == "d1")
	assert(registry.auth_payload({"device": {"deviceId": "d2", "publicKey": "p2"}}).is_empty())
	assert(registry.auth_payload({}).is_empty())


func _check_identity_match(registry) -> void:
	var participant := {"device_id": "device_a", "public_key": "key_a"}
	assert(registry.identity_matches(participant, {"deviceId": "device_a", "publicKey": "key_a"}))
	assert(not registry.identity_matches(participant, {"deviceId": "device_b", "publicKey": "key_a"}))
	assert(not registry.identity_matches(participant, {"deviceId": "device_a", "publicKey": "key_b"}))
	assert(registry.identity_matches(participant, {}))


func _check_reconnect_tokens(registry) -> void:
	var room := {}
	var token := String(registry.ensure_reconnect_token(room, "p1"))
	assert(token.begins_with("p1_"))
	assert(String(registry.reconnect_token(room, "p1")) == token)
	assert(String(registry.ensure_reconnect_token(room, "p1")) == token)


func _check_observer_registry(registry) -> void:
	var room := {"allow_observers": true, "max_observers": 1}
	assert(bool(registry.can_add_observer(room).get("ok", false)))
	registry.register_observer(room, "o1", "观察者", {"deviceId": "d1", "publicKey": "p1"}, {
		"avatarId": "avatar_custom",
		"avatar": "res://custom/avatar.png",
		"playbackVoiceConfigId": "voice_custom",
		"voiceName": "系统默认",
	})
	assert(int(registry.observer_count(room)) == 1)
	assert(registry.is_observer_participant(room, "o1"))
	assert(String(registry.observer_for_participant(room, "o1").get("displayName", "")) == "观察者")
	assert(String(registry.observer_for_participant(room, "o1").get("avatarId", "")) == "avatar_custom")
	assert(String(registry.observer_for_participant(room, "o1").get("avatar", "")) == "res://custom/avatar.png")
	assert(String(registry.observer_for_participant(room, "o1").get("playbackVoiceConfigId", "")) == "voice_custom")
	assert(String(registry.observer_for_participant(room, "o1").get("voiceName", "")) == "系统默认")
	assert(registry.observer_message_is_read_only(room, "o1", "chat_message"))
	assert(not registry.observer_message_is_read_only(room, "o1", "switch_seat"))
	assert(not registry.observer_message_is_read_only(room, "o1", "leave_room"))
	var full: Dictionary = registry.can_add_observer(room)
	assert(not bool(full.get("ok", false)))
	assert(String(full.get("code", "")) == "observer_full")
	registry.register_observer(room, "o1", "旁观者", {"deviceId": "d2", "publicKey": "p2"}, {
		"avatarId": "avatar_updated",
		"playbackVoiceConfigId": "voice_updated",
	})
	assert(int(registry.observer_count(room)) == 1)
	assert(String(registry.observer_for_participant(room, "o1").get("displayName", "")) == "旁观者")
	assert(String(registry.observer_for_participant(room, "o1").get("avatarId", "")) == "avatar_updated")
	assert(String(registry.observer_for_participant(room, "o1").get("playbackVoiceConfigId", "")) == "voice_updated")
	assert(registry.remove_observer(room, "o1"))
	assert(int(registry.observer_count(room)) == 0)
	room["allow_observers"] = false
	var disabled: Dictionary = registry.can_add_observer(room)
	assert(not bool(disabled.get("ok", false)))
	assert(String(disabled.get("code", "")) == "observer_disabled")


func _check_base64_url(registry) -> void:
	assert(String(registry.base64_url(PackedByteArray([0xfb, 0xff]))) == "-_8")
