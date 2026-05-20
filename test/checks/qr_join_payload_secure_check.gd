extends SceneTree


func _initialize() -> void:
	var qr = load("res://scripts/network/qr_join_payload.gd").new()
	var secret_id: String = qr.generate_secret_id()
	var secret_key: String = qr.generate_secret_key()
	var encoded: String = qr.build_secure_encoded(
		"192.168.1.8",
		42871,
		"room_secure",
		"Secure Room",
		"werewolf",
		false,
		"pass-1234",
		"host-device",
		"host-public",
		"guard_village",
		"Guard Village",
		"res://assets/images/werewolf/backgrounds/map_guard_standard.png",
		secret_id,
		secret_key,
		7
	)
	var raw = JSON.parse_string(encoded)
	assert(raw is Dictionary)
	var raw_dict: Dictionary = raw
	assert(String(raw_dict.get("address", "")) == "192.168.1.8:42871")
	assert(String(raw_dict.get("host", "")) == "192.168.1.8")
	assert(int(raw_dict.get("port", 0)) == 42871)
	assert(String(raw_dict.get("secretId", "")) == secret_id)
	assert(not raw_dict.has("roomId"))
	assert(not raw_dict.has("joinToken"))
	assert(not encoded.contains("room_secure"))
	assert(not encoded.contains("pass-1234"))

	var parsed: Dictionary = qr.parse(encoded)
	assert(bool(parsed.get("ok", false)))
	assert(bool(parsed.get("secure", false)))
	assert(String(parsed.get("address", "")) == "192.168.1.8:42871")
	assert(String(parsed.get("secretId", "")) == secret_id)
	assert(not parsed.has("roomId"))
	assert(not parsed.has("joinToken"))

	var decrypted: Dictionary = qr.decrypt_secure_payload(parsed, secret_key)
	assert(bool(decrypted.get("ok", false)))
	assert(String(decrypted.get("roomId", "")) == "room_secure")
	assert(String(decrypted.get("joinToken", "")) == "pass-1234")
	assert(String(decrypted.get("hostDeviceId", "")) == "host-device")
	assert(String(decrypted.get("hostPublicKey", "")) == "host-public")
	assert(String(decrypted.get("mapId", "")) == "guard_village")
	assert(String(decrypted.get("mapName", "")) == "Guard Village")
	assert(int(decrypted.get("networkProtocolVersion", 0)) == 7)

	var wrong_key: String = qr.generate_secret_key()
	var failed: Dictionary = qr.decrypt_secure_payload(parsed, wrong_key)
	assert(not bool(failed.get("ok", false)))
	assert(String(failed.get("code", "")) == "decrypt_failed")

	var plain: String = qr.build_encoded("192.168.1.9", 42872, "room_plain", "Plain Room", "werewolf", false, "plain-pass", "", "", "basic_village", "标准村庄")
	var plain_parsed: Dictionary = qr.parse(plain)
	assert(bool(plain_parsed.get("ok", false)))
	assert(not bool(plain_parsed.get("secure", false)))
	assert(String(plain_parsed.get("roomId", "")) == "room_plain")
	assert(String(plain_parsed.get("joinToken", "")) == "plain-pass")
	assert(String(plain_parsed.get("mapId", "")) == "basic_village")
	quit()
