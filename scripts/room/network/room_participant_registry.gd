extends RefCounted


const OBSERVER_MUTATING_MESSAGES := [
	"player_ready",
	"player_unready",
	"game_action",
	"chat_message",
	"start_game",
	"vote_map",
]


func auth_payload(payload: Dictionary) -> Dictionary:
	if payload.has("auth"):
		var auth_value = payload.get("auth", {})
		if auth_value is Dictionary:
			return (auth_value as Dictionary).duplicate(true)
	return {}


func identity_matches(participant: Dictionary, auth: Dictionary) -> bool:
	var expected_device_id := String(participant.get("device_id", participant.get("deviceId", ""))).strip_edges()
	var expected_public_key := String(participant.get("public_key", participant.get("publicKey", ""))).strip_edges()
	var device_id := String(auth.get("deviceId", "")).strip_edges()
	var public_key := String(auth.get("publicKey", "")).strip_edges()
	if expected_device_id != "" and device_id != "" and expected_device_id != device_id:
		return false
	if expected_public_key != "" and public_key != "" and expected_public_key != public_key:
		return false
	return true


func reconnect_token(room: Dictionary, participant_id: String) -> String:
	var tokens_value = room.get("reconnect_tokens", {})
	if not (tokens_value is Dictionary):
		return ""
	var tokens: Dictionary = tokens_value
	return String(tokens.get(participant_id, "")).strip_edges()


func ensure_reconnect_token(room: Dictionary, participant_id: String) -> String:
	var tokens_value = room.get("reconnect_tokens", {})
	var tokens: Dictionary = (tokens_value as Dictionary) if tokens_value is Dictionary else {}
	var token := String(tokens.get(participant_id, "")).strip_edges()
	if token == "":
		token = "%s_%s" % [participant_id, nonce(18)]
		tokens[participant_id] = token
		room["reconnect_tokens"] = tokens
	return token


func register_observer(room: Dictionary, participant_id: String, display_name: String, auth: Dictionary) -> void:
	var observers_value = room.get("observers", [])
	var observers: Array = (observers_value as Array) if observers_value is Array else []
	for i in range(observers.size()):
		if observers[i] is Dictionary and String((observers[i] as Dictionary).get("id", "")) == participant_id:
			var existing: Dictionary = observers[i]
			existing["displayName"] = display_name
			existing["device_id"] = String(auth.get("deviceId", ""))
			existing["public_key"] = String(auth.get("publicKey", ""))
			observers[i] = existing
			room["observers"] = observers
			return
	observers.append({
		"id": participant_id,
		"displayName": display_name,
		"device_id": String(auth.get("deviceId", "")),
		"public_key": String(auth.get("publicKey", "")),
	})
	room["observers"] = observers


func observer_for_participant(room: Dictionary, participant_id: String) -> Dictionary:
	var observers_value = room.get("observers", [])
	if not (observers_value is Array):
		return {}
	for item in observers_value as Array:
		if item is Dictionary and String((item as Dictionary).get("id", "")) == participant_id:
			return item as Dictionary
	return {}


func remove_observer(room: Dictionary, participant_id: String) -> bool:
	var observers_value = room.get("observers", [])
	if not (observers_value is Array):
		return false
	var observers: Array = observers_value as Array
	for i in range(observers.size()):
		if observers[i] is Dictionary and String((observers[i] as Dictionary).get("id", "")) == participant_id:
			observers.remove_at(i)
			room["observers"] = observers
			return true
	return false


func is_observer_participant(room: Dictionary, participant_id: String) -> bool:
	var clean := participant_id.strip_edges()
	return clean != "" and not observer_for_participant(room, clean).is_empty()


func observer_count(room: Dictionary) -> int:
	var observers_value = room.get("observers", [])
	if observers_value is Array:
		return (observers_value as Array).size()
	return 0


func can_add_observer(room: Dictionary, occupied_player_count: int = -1) -> Dictionary:
	if not bool(room.get("allow_observers", true)):
		return {
			"ok": false,
			"code": "observer_disabled",
			"message": "该房间不允许观察者加入",
		}
	var max_observers := int(room.get("max_observers", 3))
	if max_observers < 0:
		max_observers = 0
	if observer_count(room) >= max_observers:
		return {
			"ok": false,
			"code": "observer_full",
			"message": "观察者人数已满",
		}
	var capacity := room_capacity(room)
	var players := occupied_player_count
	if players < 0:
		players = participant_player_count(room)
	if capacity > 0 and players + observer_count(room) >= capacity:
		return {
			"ok": false,
			"code": "room_full",
			"message": "房间已满",
		}
	return {"ok": true}


func room_capacity(room: Dictionary) -> int:
	var explicit := int(room.get("max_participants", room.get("maxParticipants", 0)))
	if explicit > 0:
		return explicit
	var max_players := int(room.get("max_players", room.get("maxPlayers", 0)))
	var max_observers := int(room.get("max_observers", room.get("maxObservers", 3)))
	return max_players + maxi(0, max_observers)


func participant_player_count(room: Dictionary) -> int:
	var count := 0
	var participants_value = room.get("participants", [])
	if participants_value is Array:
		for item in participants_value as Array:
			if item is Dictionary and String((item as Dictionary).get("type", "")) != "observer":
				count += 1
	var text := String(room.get("players", "")).strip_edges()
	var slash := text.find("/")
	if count == 0 and slash > 0:
		var left := text.substr(0, slash).strip_edges()
		if left.is_valid_int():
			count = int(left.to_int())
	return count


func observer_message_is_read_only(room: Dictionary, participant_id: String, type: String) -> bool:
	return is_observer_participant(room, participant_id) and OBSERVER_MUTATING_MESSAGES.has(type)


func nonce(byte_length: int) -> String:
	var crypto := Crypto.new()
	return base64_url(crypto.generate_random_bytes(byte_length))


func base64_url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")
