extends RefCounted
class_name DeviceIdentity

const PREFERENCES_SAVE_PATH := "user://preferences.json"
const AUTH_DOMAIN := "chat_with_me.device_auth.v1"
const ANDROID_SINGLETON := "PlayWithMeAndroid"
const ANDROID_GENERATE_METHODS := ["identity_generate", "generateDeviceIdentity"]
const ANDROID_SIGN_METHODS := ["identity_sign", "signDeviceChallenge"]
const ANDROID_VERIFY_METHODS := ["identity_verify", "verifyDeviceAuth"]

var device_id := ""
var public_key := ""
var private_key := ""
var algorithm := "godot_sha256_v1"
var persistence_enabled := true


func load_or_create() -> void:
	if device_id != "" and public_key != "" and private_key != "":
		return
	if persistence_enabled:
		var preference_identity := _load_identity_from_preferences()
		if not preference_identity.is_empty() and _apply_json(preference_identity):
			return
	_generate()


func to_public_json() -> Dictionary:
	_ensure_generated()
	return {
		"deviceId": device_id,
		"publicKey": public_key,
	}


func to_stored_json() -> Dictionary:
	_ensure_generated()
	return {
		"deviceId": device_id,
		"publicKey": public_key,
		"privateKey": private_key,
		"algorithm": algorithm,
	}


func auth_payload(challenge: String = "") -> Dictionary:
	_ensure_generated()
	return auth_payload_from_identity(to_stored_json(), challenge)


static func auth_payload_from_identity(identity: Dictionary, challenge: String = "") -> Dictionary:
	var normalized_identity := _normalize_identity(identity)
	var device_id_value := String(normalized_identity.get("deviceId", "")).strip_edges()
	var public_key_value := String(normalized_identity.get("publicKey", "")).strip_edges()
	var private_key_value := String(normalized_identity.get("privateKey", "")).strip_edges()
	var algorithm_value := String(normalized_identity.get("algorithm", "")).strip_edges()
	var plugin_payload := _android_sign(normalized_identity, challenge)
	if not plugin_payload.is_empty():
		return plugin_payload
	if algorithm_value == "ed25519":
		algorithm_value = "godot_sha256_v1"
	if algorithm_value == "":
		algorithm_value = "godot_sha256_v1"
	return {
		"deviceId": device_id_value,
		"publicKey": public_key_value,
		"signature": _godot_signature(challenge, device_id_value, public_key_value),
		"algorithm": algorithm_value,
		"hasPrivateKey": private_key_value != "",
	}


static func verify_auth_payload(auth: Dictionary, challenge: String = "") -> bool:
	var device_id_value := String(auth.get("deviceId", "")).strip_edges()
	var public_key_value := String(auth.get("publicKey", "")).strip_edges()
	var signature_value := String(auth.get("signature", "")).strip_edges()
	if device_id_value == "" or public_key_value == "" or signature_value == "":
		return false
	var algorithm_value := String(auth.get("algorithm", "")).strip_edges()
	if algorithm_value == "ed25519":
		return _android_verify(auth, challenge)
	if _android_verify(auth, challenge):
		return true
	return signature_value == _godot_signature(challenge, device_id_value, public_key_value)


func _apply_json(data: Dictionary) -> bool:
	var normalized := _normalize_identity(data)
	var next_device_id := String(normalized.get("deviceId", "")).strip_edges()
	var next_public_key := String(normalized.get("publicKey", "")).strip_edges()
	var next_private_key := String(normalized.get("privateKey", "")).strip_edges()
	if next_device_id == "" or next_public_key == "" or next_private_key == "":
		return false
	device_id = next_device_id
	public_key = next_public_key
	private_key = next_private_key
	algorithm = String(normalized.get("algorithm", "godot_sha256_v1")).strip_edges()
	if algorithm == "":
		algorithm = "godot_sha256_v1"
	return true


func _ensure_generated() -> void:
	if device_id == "" or public_key == "" or private_key == "":
		_generate()


func _generate() -> void:
	var generated := _android_generate()
	if not generated.is_empty():
		device_id = String(generated.get("deviceId", "")).strip_edges()
		public_key = String(generated.get("publicKey", "")).strip_edges()
		private_key = String(generated.get("privateKey", "")).strip_edges()
		algorithm = String(generated.get("algorithm", "ed25519")).strip_edges()
	if device_id != "" and public_key != "" and private_key != "":
		return
	var derived_identity := identity_from_private_key(generate_private_key())
	device_id = String(derived_identity.get("deviceId", ""))
	public_key = String(derived_identity.get("publicKey", ""))
	private_key = String(derived_identity.get("privateKey", ""))
	algorithm = String(derived_identity.get("algorithm", "godot_sha256_v1"))


static func generate_private_key(byte_length: int = 32) -> String:
	return _base64_url(Crypto.new().generate_random_bytes(maxi(16, byte_length)))


static func identity_from_private_key(value: String) -> Dictionary:
	var clean := value.strip_edges()
	if clean == "":
		return {}
	var derived_public_key := public_key_from_private_key(clean)
	return {
		"deviceId": device_id_from_public_key(derived_public_key),
		"publicKey": derived_public_key,
		"privateKey": clean,
		"algorithm": "godot_sha256_v1",
	}


static func public_key_from_private_key(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(("%s\npublic\n%s" % [AUTH_DOMAIN, value.strip_edges()]).to_utf8_buffer())
	return _base64_url(context.finish())


static func device_id_from_public_key(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(("%s\ndevice\n%s" % [AUTH_DOMAIN, value.strip_edges()]).to_utf8_buffer())
	return "device_%s" % _base64_url(context.finish()).substr(0, 18)


static func _godot_signature(challenge: String, device_id_value: String, public_key_value: String) -> String:
	var source := "%s\n%s\n%s\n%s\n%s" % [AUTH_DOMAIN, challenge, device_id_value, public_key_value, public_key_value]
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(source.to_utf8_buffer())
	return _base64_url(context.finish())


func _nonce(byte_length: int) -> String:
	var crypto := Crypto.new()
	return _base64_url(crypto.generate_random_bytes(byte_length))


static func _base64_url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


static func _normalize_identity(identity: Dictionary) -> Dictionary:
	var private_key_value := String(identity.get("privateKey", identity.get("device_private_key", ""))).strip_edges()
	var normalized := identity.duplicate(true)
	if private_key_value != "":
		normalized["privateKey"] = private_key_value
		if String(normalized.get("publicKey", "")).strip_edges() == "" or String(normalized.get("deviceId", "")).strip_edges() == "":
			var derived := identity_from_private_key(private_key_value)
			if String(normalized.get("publicKey", "")).strip_edges() == "":
				normalized["publicKey"] = String(derived.get("publicKey", ""))
			if String(normalized.get("deviceId", "")).strip_edges() == "":
				normalized["deviceId"] = String(derived.get("deviceId", ""))
			if String(normalized.get("algorithm", "")).strip_edges() == "":
				normalized["algorithm"] = String(derived.get("algorithm", "godot_sha256_v1"))
	if String(normalized.get("algorithm", "")).strip_edges() == "":
		normalized["algorithm"] = "godot_sha256_v1"
	return normalized


static func _load_identity_from_preferences() -> Dictionary:
	if not FileAccess.file_exists(PREFERENCES_SAVE_PATH):
		return {}
	var file := FileAccess.open(PREFERENCES_SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	var private_key_value := String((parsed as Dictionary).get("device_private_key", "")).strip_edges()
	if private_key_value == "":
		return {}
	return identity_from_private_key(private_key_value)


static func _android_generate() -> Dictionary:
	var plugin = _android_plugin()
	if plugin == null:
		return {}
	var method := _plugin_method(plugin, ANDROID_GENERATE_METHODS)
	if method == "":
		return {}
	var parsed = _parse_json(plugin.call(method, ""))
	if parsed is Dictionary and bool((parsed as Dictionary).get("ok", false)):
		return parsed as Dictionary
	return {}


static func _android_sign(identity: Dictionary, challenge: String) -> Dictionary:
	var plugin = _android_plugin()
	if plugin == null:
		return {}
	var method := _plugin_method(plugin, ANDROID_SIGN_METHODS)
	if method == "":
		return {}
	var parsed = _parse_json(plugin.call(method, JSON.stringify(identity), challenge))
	if parsed is Dictionary and bool((parsed as Dictionary).get("ok", false)):
		var payload: Dictionary = parsed
		return {
			"deviceId": String(payload.get("deviceId", "")),
			"publicKey": String(payload.get("publicKey", "")),
			"signature": String(payload.get("signature", "")),
			"algorithm": String(payload.get("algorithm", "ed25519")),
		}
	return {}


static func _android_verify(auth: Dictionary, challenge: String) -> bool:
	var plugin = _android_plugin()
	if plugin == null:
		return false
	var method := _plugin_method(plugin, ANDROID_VERIFY_METHODS)
	if method == "":
		return false
	var result = plugin.call(method, JSON.stringify(auth), challenge)
	return bool(result) if result is bool else false


static func _android_plugin():
	if OS.get_name() != "Android":
		return null
	if not Engine.has_singleton(ANDROID_SINGLETON):
		return null
	return Engine.get_singleton(ANDROID_SINGLETON)


static func _plugin_method(plugin, methods: Array) -> String:
	for method in methods:
		if plugin.has_method(method):
			return String(method)
	return ""


static func _parse_json(payload):
	if payload is Dictionary or payload is Array:
		return payload
	if payload is String:
		var raw := String(payload).strip_edges()
		if raw == "":
			return {}
		var json := JSON.new()
		if json.parse(raw) != OK:
			return {}
		return json.data
	return {}
