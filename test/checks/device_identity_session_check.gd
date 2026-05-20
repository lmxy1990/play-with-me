extends SceneTree


func _initialize() -> void:
	var identity = load("res://scripts/core/device_identity.gd").new()
	identity.persistence_enabled = false
	identity.load_or_create()
	var public_identity: Dictionary = identity.to_public_json()
	assert(String(public_identity.get("deviceId", "")).begins_with("device_"))
	assert(String(public_identity.get("publicKey", "")) != "")
	var auth: Dictionary = identity.auth_payload("challenge")
	assert(String(auth.get("deviceId", "")) == String(public_identity.get("deviceId", "")))
	assert(String(auth.get("signature", "")) != "")
	assert(identity.verify_auth_payload(auth, "challenge"))
	assert(not identity.verify_auth_payload(auth, "wrong_challenge"))
	var tampered := auth.duplicate(true)
	tampered["publicKey"] = "bad_key"
	assert(not identity.verify_auth_payload(tampered, "challenge"))

	var store = load("res://scripts/room/room_session_store.gd").new()
	store.persistence_enabled = false
	assert(store.load().is_empty())
	store.save({
		"host": "127.0.0.1",
		"port": 42871,
		"participantId": "peer_1",
		"reconnectToken": "token_1",
		"isObserver": false,
		"roomId": "room_1",
	})
	var loaded: Dictionary = store.load()
	assert(store.is_valid(loaded))
	assert(String(loaded.get("host", "")) == "127.0.0.1")
	assert(int(loaded.get("port", 0)) == 42871)
	store.clear()
	assert(store.load().is_empty())
	quit()
