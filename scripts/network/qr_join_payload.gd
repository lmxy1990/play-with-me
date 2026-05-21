extends RefCounted
class_name QrJoinPayload

const APP_ID := "chat_with_me"
const VERSION := 3
const FORMAT_PLAIN := "lan_join_plain"
const FORMAT_SECURE := "lan_join_secure"
const ENCRYPTION_ALGORITHM := "AES-256-CBC+SHA256"
const KEY_EXCHANGE_ALGORITHM := "RSA-2048-WRAP"
const MAC_DOMAIN := "chat_with_me.qr_join.v2"


func build(host: String, port: int, room_id: String, room_name: String, game_id: String = "werewolf", as_observer: bool = false, join_token: String = "", host_device_id: String = "", host_public_key: String = "", map_id: String = "", map_name: String = "", bg: String = "") -> Dictionary:
	return {
		"app": APP_ID,
		"version": VERSION,
		"format": FORMAT_PLAIN,
		"host": host.strip_edges(),
		"port": port,
		"roomId": room_id.strip_edges(),
		"roomName": _default_text(room_name, "狼人杀房间"),
		"gameId": _default_text(game_id, "werewolf"),
		"asObserver": as_observer,
		"joinToken": join_token.strip_edges(),
		"hostDeviceId": host_device_id.strip_edges(),
		"hostPublicKey": host_public_key.strip_edges(),
		"mapId": map_id.strip_edges(),
		"mapName": map_name.strip_edges(),
		"bg": bg.strip_edges(),
	}


func encode(payload: Dictionary) -> String:
	return JSON.stringify(payload)


func build_encoded(host: String, port: int, room_id: String, room_name: String, game_id: String = "werewolf", as_observer: bool = false, join_token: String = "", host_device_id: String = "", host_public_key: String = "", map_id: String = "", map_name: String = "", bg: String = "") -> String:
	return encode(build(host, port, room_id, room_name, game_id, as_observer, join_token, host_device_id, host_public_key, map_id, map_name, bg))


func generate_secret_id() -> String:
	return _base64_url(Crypto.new().generate_random_bytes(12))


func generate_secret_key() -> String:
	return _base64_url(Crypto.new().generate_random_bytes(32))


func build_secure(host: String, port: int, room_id: String, room_name: String, game_id: String = "werewolf", as_observer: bool = false, join_token: String = "", host_device_id: String = "", host_public_key: String = "", map_id: String = "", map_name: String = "", bg: String = "", secret_id: String = "", secret_key: String = "", network_protocol_version: int = 1) -> Dictionary:
	var clean_host := host.strip_edges()
	var clean_secret_id := secret_id.strip_edges()
	if clean_secret_id == "":
		clean_secret_id = generate_secret_id()
	var encrypted: Dictionary = encrypt_secret({
		"roomId": room_id.strip_edges(),
		"roomName": _default_text(room_name, "狼人杀房间"),
		"gameId": _default_text(game_id, "werewolf"),
		"asObserver": as_observer,
		"joinToken": join_token.strip_edges(),
		"hostDeviceId": host_device_id.strip_edges(),
		"hostPublicKey": host_public_key.strip_edges(),
		"mapId": map_id.strip_edges(),
		"mapName": map_name.strip_edges(),
		"bg": bg.strip_edges(),
		"host": clean_host,
		"port": port,
		"networkProtocolVersion": network_protocol_version,
	}, secret_key)
	if not bool(encrypted.get("ok", false)):
		return encrypted
	return {
		"app": APP_ID,
		"version": VERSION,
		"format": FORMAT_SECURE,
		"address": "%s:%d" % [clean_host, port],
		"host": clean_host,
		"port": port,
		"secretId": clean_secret_id,
		"alg": ENCRYPTION_ALGORITHM,
		"keyExchange": KEY_EXCHANGE_ALGORITHM,
		"iv": String(encrypted.get("iv", "")),
		"cipher": String(encrypted.get("cipher", "")),
		"mac": String(encrypted.get("mac", "")),
	}


func build_secure_encoded(host: String, port: int, room_id: String, room_name: String, game_id: String = "werewolf", as_observer: bool = false, join_token: String = "", host_device_id: String = "", host_public_key: String = "", map_id: String = "", map_name: String = "", bg: String = "", secret_id: String = "", secret_key: String = "", network_protocol_version: int = 1) -> String:
	var payload := build_secure(host, port, room_id, room_name, game_id, as_observer, join_token, host_device_id, host_public_key, map_id, map_name, bg, secret_id, secret_key, network_protocol_version)
	return encode(payload)


func parse(value: String) -> Dictionary:
	var trimmed := value.strip_edges()
	if trimmed == "":
		return _error("加入码为空")
	var decoded = JSON.parse_string(trimmed)
	if not (decoded is Dictionary):
		return _error("加入码必须是 JSON 对象")
	var json: Dictionary = decoded
	if String(json.get("app", "")) != APP_ID:
		return _error("不是本应用的加入码")
	var version := int(json.get("version", 0))
	if version != VERSION:
		return _error("不支持的加入码版本：%s" % str(json.get("version", "")), "unsupported_qr_version")
	if String(json.get("format", "")) == FORMAT_SECURE:
		return _parse_secure(json)
	if String(json.get("format", "")) != FORMAT_PLAIN:
		return _error("不支持的加入码格式", "unsupported_qr_format")
	var host := String(json.get("host", "")).strip_edges()
	if host == "":
		return _error("加入码缺少 Host", "missing_host")
	var port := int(json.get("port", 0))
	if port <= 0 or port > 65535:
		return _error("加入码端口无效", "invalid_port")
	return {
		"ok": true,
		"secure": false,
		"host": host,
		"port": port,
		"roomId": String(json.get("roomId", "")),
		"roomName": _default_text(String(json.get("roomName", "")), "狼人杀房间"),
		"gameId": _default_text(String(json.get("gameId", "")), "werewolf"),
		"asObserver": bool(json.get("asObserver", false)),
		"joinToken": String(json.get("joinToken", "")),
		"hostDeviceId": String(json.get("hostDeviceId", "")),
		"hostPublicKey": String(json.get("hostPublicKey", "")),
		"mapId": String(json.get("mapId", "")),
		"mapName": String(json.get("mapName", "")),
		"bg": String(json.get("bg", "")),
		"error": "",
	}


func decrypt_secure_payload(secure_payload: Dictionary, secret_key) -> Dictionary:
	if not bool(secure_payload.get("secure", false)) and int(secure_payload.get("version", 0)) != VERSION:
		return _error("加入码不是加密格式", "invalid_secure_payload")
	var key := _key_bytes(secret_key)
	if key.size() != 32:
		return _error("二维码解密密钥无效", "invalid_qr_secret_key")
	var iv := _base64_url_decode(String(secure_payload.get("iv", "")))
	var cipher := _base64_url_decode(String(secure_payload.get("cipher", "")))
	var expected_mac := _base64_url_decode(String(secure_payload.get("mac", "")))
	if iv.size() != 16 or cipher.is_empty() or expected_mac.is_empty():
		return _error("加密加入码内容不完整", "invalid_secure_payload")
	var actual_mac := _mac(key, iv, cipher)
	if not _bytes_equal(actual_mac, expected_mac):
		return _error("二维码解密校验失败", "decrypt_failed")
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_DECRYPT, key, iv) != OK:
		return _error("二维码解密初始化失败", "decrypt_failed")
	var padded := aes.update(cipher)
	aes.finish()
	var plain := _pkcs7_unpad(padded)
	if plain.is_empty():
		return _error("二维码解密失败", "decrypt_failed")
	var decoded = JSON.parse_string(plain.get_string_from_utf8())
	if not (decoded is Dictionary):
		return _error("二维码解密结果无效", "decrypt_failed")
	var json: Dictionary = decoded
	var host := String(json.get("host", secure_payload.get("host", ""))).strip_edges()
	var port := int(json.get("port", secure_payload.get("port", 0)))
	if host == "" or port <= 0 or port > 65535:
		return _error("解密后的房间地址无效", "invalid_secure_payload")
	return {
		"ok": true,
		"secure": true,
		"host": host,
		"port": port,
		"address": "%s:%d" % [host, port],
		"roomId": String(json.get("roomId", "")),
		"roomName": _default_text(String(json.get("roomName", "")), "狼人杀房间"),
		"gameId": _default_text(String(json.get("gameId", "")), "werewolf"),
		"asObserver": bool(json.get("asObserver", false)),
		"joinToken": String(json.get("joinToken", "")),
		"hostDeviceId": String(json.get("hostDeviceId", "")),
		"hostPublicKey": String(json.get("hostPublicKey", "")),
		"mapId": String(json.get("mapId", "")),
		"mapName": String(json.get("mapName", "")),
		"bg": String(json.get("bg", "")),
		"networkProtocolVersion": int(json.get("networkProtocolVersion", 0)),
		"error": "",
	}


func encrypt_secret(secret_payload: Dictionary, secret_key) -> Dictionary:
	var key := _key_bytes(secret_key)
	if key.size() != 32:
		return _error("二维码加密密钥无效", "invalid_qr_secret_key")
	var iv := Crypto.new().generate_random_bytes(16)
	var plain := JSON.stringify(secret_payload).to_utf8_buffer()
	var padded := _pkcs7_pad(plain, 16)
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv) != OK:
		return _error("二维码加密初始化失败", "encrypt_failed")
	var cipher := aes.update(padded)
	aes.finish()
	return {
		"ok": true,
		"iv": _base64_url(iv),
		"cipher": _base64_url(cipher),
		"mac": _base64_url(_mac(key, iv, cipher)),
	}


func _parse_secure(json: Dictionary) -> Dictionary:
	if String(json.get("format", "")) != FORMAT_SECURE:
		return _error("不支持的加密加入码格式", "unsupported_qr_format")
	var host := String(json.get("host", "")).strip_edges()
	var port := int(json.get("port", 0))
	if host == "" or port <= 0 or port > 65535:
		var address := String(json.get("address", "")).strip_edges()
		var parsed_address := parse_address(address)
		if not bool(parsed_address.get("ok", false)):
			return _error("加密加入码地址无效", "invalid_address")
		host = String(parsed_address.get("host", ""))
		port = int(parsed_address.get("port", 0))
	var secret_id := String(json.get("secretId", "")).strip_edges()
	if secret_id == "":
		return _error("加密加入码缺少密钥编号", "missing_secret_id")
	for field in ["iv", "cipher", "mac"]:
		if String(json.get(field, "")).strip_edges() == "":
			return _error("加密加入码内容不完整", "invalid_secure_payload")
	return {
		"ok": true,
		"secure": true,
		"version": VERSION,
		"format": FORMAT_SECURE,
		"host": host,
		"port": port,
		"address": "%s:%d" % [host, port],
		"secretId": secret_id,
		"alg": String(json.get("alg", ENCRYPTION_ALGORITHM)),
		"keyExchange": String(json.get("keyExchange", KEY_EXCHANGE_ALGORITHM)),
		"iv": String(json.get("iv", "")),
		"cipher": String(json.get("cipher", "")),
		"mac": String(json.get("mac", "")),
		"error": "",
	}


func parse_address(address: String) -> Dictionary:
	var clean := address.strip_edges()
	var colon := clean.rfind(":")
	if colon <= 0 or colon >= clean.length() - 1:
		return _error("房间地址格式应为 IP:端口", "invalid_address")
	var host := clean.substr(0, colon).strip_edges()
	var port := int(clean.substr(colon + 1).to_int())
	if host == "" or port <= 0 or port > 65535:
		return _error("房间地址无效", "invalid_address")
	return {"ok": true, "host": host, "port": port, "address": "%s:%d" % [host, port]}


func _default_text(value: String, default_value: String) -> String:
	var trimmed := value.strip_edges()
	return trimmed if trimmed != "" else default_value


func _error(message: String, code: String = "invalid_join_payload") -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"error": message,
	}


func _key_bytes(secret_key) -> PackedByteArray:
	if secret_key is PackedByteArray:
		return secret_key
	if secret_key is String:
		return _base64_url_decode(String(secret_key))
	return PackedByteArray()


func _pkcs7_pad(bytes: PackedByteArray, block_size: int) -> PackedByteArray:
	var result := PackedByteArray(bytes)
	var pad := block_size - (result.size() % block_size)
	if pad <= 0:
		pad = block_size
	for _i in range(pad):
		result.append(pad)
	return result


func _pkcs7_unpad(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.is_empty():
		return PackedByteArray()
	var pad := int(bytes[bytes.size() - 1])
	if pad <= 0 or pad > 16 or pad > bytes.size():
		return PackedByteArray()
	for i in range(bytes.size() - pad, bytes.size()):
		if int(bytes[i]) != pad:
			return PackedByteArray()
	return bytes.slice(0, bytes.size() - pad)


func _mac(key: PackedByteArray, iv: PackedByteArray, cipher: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(MAC_DOMAIN.to_utf8_buffer())
	context.update(key)
	context.update(iv)
	context.update(cipher)
	return context.finish()


func _bytes_equal(left: PackedByteArray, right: PackedByteArray) -> bool:
	if left.size() != right.size():
		return false
	var diff := 0
	for i in range(left.size()):
		diff |= int(left[i]) ^ int(right[i])
	return diff == 0


func _base64_url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


func _base64_url_decode(value: String) -> PackedByteArray:
	var text := value.strip_edges().replace("-", "+").replace("_", "/")
	while text.length() % 4 != 0:
		text += "="
	return Marshalls.base64_to_raw(text)
