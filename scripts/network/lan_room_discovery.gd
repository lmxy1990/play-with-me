extends RefCounted
class_name LanRoomDiscovery

signal room_discovered(room: Dictionary)

const APP_ID := "play_with_me"
const VERSION := 1
const DEFAULT_DISCOVERY_PORT := 42870
const DEFAULT_ROOM_PORT := 42871
const DEFAULT_BROADCAST_ADDRESS := "255.255.255.255"
const ROOM_TTL_SEC := 8.0

var discovery_port := DEFAULT_DISCOVERY_PORT
var broadcast_address := DEFAULT_BROADCAST_ADDRESS

var _udp: PacketPeerUDP
var _rooms: Dictionary = {}


func start(port: int = DEFAULT_DISCOVERY_PORT, address: String = DEFAULT_BROADCAST_ADDRESS) -> bool:
	if _udp != null:
		return true
	discovery_port = port
	broadcast_address = address
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(discovery_port)
	if err != OK:
		_udp = null
		return false
	_udp.set_broadcast_enabled(true)
	return true


func stop() -> void:
	if _udp != null:
		_udp.close()
	_udp = null
	_rooms.clear()


func poll() -> Array:
	var discovered := []
	if _udp == null:
		return discovered
	while _udp.get_available_packet_count() > 0:
		var data := _udp.get_packet()
		var text := data.get_string_from_utf8()
		var room := parse_packet(text, _udp.get_packet_ip())
		if bool(room.get("ok", false)):
			var room_id := String(room.get("roomId", ""))
			if bool(room.get("closed", false)):
				_rooms.erase(room_id)
			else:
				_rooms[room_id] = room
			discovered.append(room)
			room_discovered.emit(room.duplicate(true))
	_prune_stale_rooms()
	return discovered


func publish(room: Dictionary) -> bool:
	if _udp == null and not start(discovery_port, broadcast_address):
		return false
	var payload := JSON.stringify(room_to_json(room))
	_udp.set_dest_address(broadcast_address, discovery_port)
	var err := _udp.put_packet(payload.to_utf8_buffer())
	return err == OK


func publish_closed(room_id: String, host: String, port: int, host_device_id: String = "", host_public_key: String = "") -> bool:
	var clean_id := room_id.strip_edges()
	if clean_id == "":
		return false
	if _udp == null and not start(discovery_port, broadcast_address):
		return false
	var payload := JSON.stringify(room_closed_to_json(clean_id, host, port, host_device_id, host_public_key))
	_udp.set_dest_address(broadcast_address, discovery_port)
	var err := _udp.put_packet(payload.to_utf8_buffer())
	return err == OK


func room_to_json(room: Dictionary) -> Dictionary:
	return {
		"app": APP_ID,
		"version": VERSION,
		"roomId": String(room.get("roomId", room.get("id", ""))),
		"roomName": String(room.get("roomName", room.get("name", "狼人杀房间"))),
		"gameId": String(room.get("gameId", _game_id_for_type(String(room.get("type", "狼人杀"))))),
		"host": String(room.get("host", room.get("address", ""))),
		"port": int(room.get("port", DEFAULT_ROOM_PORT)),
		"minPlayers": int(room.get("minPlayers", room.get("min_players", 6))),
		"maxPlayers": int(room.get("maxPlayers", room.get("max_players", 6))),
		"allowObservers": bool(room.get("allowObservers", room.get("allow_observers", true))),
		"maxObservers": int(room.get("maxObservers", room.get("max_observers", 3))),
		"maxParticipants": int(room.get("maxParticipants", room.get("max_participants", int(room.get("maxPlayers", room.get("max_players", 6))) + int(room.get("maxObservers", room.get("max_observers", 3)))))),
		"participants": _participants_json(room.get("participants", [])),
		"botProfileIds": [],
		"hostDeviceId": String(room.get("hostDeviceId", "")),
		"hostPublicKey": String(room.get("hostPublicKey", "")),
		"requiresJoinToken": bool(room.get("requiresJoinToken", false)),
		"gameStarted": bool(room.get("gameStarted", false)),
		"enableTimers": bool(room.get("enableTimers", false)),
		"mapId": String(room.get("mapId", room.get("map_id", ""))),
		"mapName": String(room.get("mapName", room.get("map_name", ""))),
		"bg": String(room.get("bg", "")),
		"closed": bool(room.get("closed", false)),
	}


func room_closed_to_json(room_id: String, host: String, port: int, host_device_id: String = "", host_public_key: String = "") -> Dictionary:
	return {
		"app": APP_ID,
		"version": VERSION,
		"roomId": room_id.strip_edges(),
		"roomName": "",
		"gameId": "werewolf",
		"host": host.strip_edges(),
		"port": port,
		"hostDeviceId": host_device_id,
		"hostPublicKey": host_public_key,
		"closed": true,
	}


func parse_packet(value: String, source_host: String = "") -> Dictionary:
	var decoded = JSON.parse_string(value.strip_edges())
	if not (decoded is Dictionary):
		return _error("发现包不是 JSON 对象")
	var json: Dictionary = decoded
	if String(json.get("app", "")) != APP_ID or int(json.get("version", 0)) != VERSION:
		return _error("发现包协议不匹配")
	var room_id := String(json.get("roomId", "")).strip_edges()
	var port := int(json.get("port", 0))
	var closed := bool(json.get("closed", false))
	if room_id == "" or port > 65535 or (not closed and port <= 0):
		return _error("发现包房间或端口无效")
	var host := String(json.get("host", "")).strip_edges()
	if host == "":
		host = source_host.strip_edges()
	if closed:
		return {
			"ok": true,
			"closed": true,
			"roomId": room_id,
			"host": host,
			"port": port,
			"hostDeviceId": String(json.get("hostDeviceId", "")),
			"hostPublicKey": String(json.get("hostPublicKey", "")),
			"lastSeenAt": Time.get_unix_time_from_system(),
			"error": "",
		}
	var room := {
		"ok": true,
		"roomId": room_id,
		"roomName": _default_text(String(json.get("roomName", "")), "狼人杀房间"),
		"gameId": _default_text(String(json.get("gameId", "")), "werewolf"),
		"host": host,
		"port": port,
		"minPlayers": int(json.get("minPlayers", 0)),
		"maxPlayers": int(json.get("maxPlayers", 0)),
		"allowObservers": bool(json.get("allowObservers", true)),
		"maxObservers": int(json.get("maxObservers", 3)),
		"maxParticipants": int(json.get("maxParticipants", int(json.get("maxPlayers", 0)) + int(json.get("maxObservers", 3)))),
		"participants": _participants_json(json.get("participants", [])),
		"botProfileIds": [],
		"hostDeviceId": String(json.get("hostDeviceId", "")),
		"hostPublicKey": String(json.get("hostPublicKey", "")),
		"requiresJoinToken": bool(json.get("requiresJoinToken", false)),
		"gameStarted": bool(json.get("gameStarted", false)),
		"enableTimers": bool(json.get("enableTimers", false)),
		"mapId": String(json.get("mapId", "")),
		"mapName": String(json.get("mapName", "")),
		"bg": String(json.get("bg", "")),
		"closed": false,
		"lastSeenAt": Time.get_unix_time_from_system(),
		"error": "",
	}
	room["playerCount"] = player_count(room)
	room["observerCount"] = observer_count(room)
	room["participantCount"] = int(room["playerCount"]) + int(room["observerCount"])
	return room


func discovered_rooms() -> Array:
	_prune_stale_rooms()
	var result := []
	for key in _rooms.keys():
		result.append((_rooms[key] as Dictionary).duplicate(true))
	return result


func app_room_from_discovery(room: Dictionary) -> Dictionary:
	var max_players := int(room.get("maxPlayers", 0))
	var players := int(room.get("playerCount", player_count(room)))
	var observers := int(room.get("observerCount", observer_count(room)))
	var participants := int(room.get("participantCount", players + observers))
	var max_participants := int(room.get("maxParticipants", max_players + int(room.get("maxObservers", 3))))
	var requires_token := bool(room.get("requiresJoinToken", false))
	var game_id := String(room.get("gameId", "werewolf"))
	var map_id := String(room.get("mapId", room.get("map_id", ""))).strip_edges()
	var map_name := String(room.get("mapName", room.get("map_name", "标准村庄" if game_id != "xiangqi" else "标准象棋"))).strip_edges()
	var bg := String(room.get("bg", "res://assets/images/werewolf/backgrounds/lobby.png")).strip_edges()
	var default_map_id := "xiangqi_standard" if game_id == "xiangqi" else "basic_village"
	var default_map_name := "标准象棋" if game_id == "xiangqi" else "标准村庄"
	var default_bg := "res://assets/images/xiangqi/backgrounds/table.svg" if game_id == "xiangqi" else "res://assets/images/werewolf/backgrounds/lobby.png"
	return {
		"id": String(room.get("roomId", "")),
		"name": String(room.get("roomName", "象棋房间" if game_id == "xiangqi" else "狼人杀房间")),
		"state": "游戏中" if bool(room.get("gameStarted", false)) else "等待中",
		"type": _type_for_game_id(game_id),
		"game_room_id": game_id,
		"gameId": game_id,
		"players": "%d/%d" % [participants, max(0, max_participants)],
		"lock": "密码" if requires_token else "公开",
		"address": "%s:%d" % [String(room.get("host", "")), int(room.get("port", 0))],
		"bg": bg if bg != "" else default_bg,
		"max_players": max_players,
		"allow_observers": bool(room.get("allowObservers", true)),
		"max_observers": int(room.get("maxObservers", 3)),
		"max_participants": max_participants,
		"active_bot_profile_ids": [],
		"map_id": default_map_id if map_id == "" else map_id,
		"map_name": default_map_name if map_name == "" else map_name,
		"host": String(room.get("host", "")),
		"port": int(room.get("port", 0)),
		"host_device_id": String(room.get("hostDeviceId", "")),
		"host_public_key": String(room.get("hostPublicKey", "")),
		"join_payload": JSON.stringify({
			"app": "chat_with_me",
			"version": 3,
			"format": "lan_join_plain",
			"host": String(room.get("host", "")),
			"port": int(room.get("port", 0)),
			"roomId": String(room.get("roomId", "")),
			"roomName": String(room.get("roomName", "象棋房间" if game_id == "xiangqi" else "狼人杀房间")),
			"gameId": game_id,
			"asObserver": false,
			"joinToken": "",
			"hostDeviceId": String(room.get("hostDeviceId", "")),
			"hostPublicKey": String(room.get("hostPublicKey", "")),
			"mapId": default_map_id if map_id == "" else map_id,
			"mapName": default_map_name if map_name == "" else map_name,
			"bg": bg if bg != "" else default_bg,
		}),
		"discovered": true,
	}


func room_from_state(room: Dictionary, players: Array, host: String, port: int, host_device_id: String = "", host_public_key: String = "") -> Dictionary:
	var participants := []
	for i in range(players.size()):
		var player: Dictionary = players[i]
		var owner := String(player.get("owner", ""))
		if owner == "":
			continue
		participants.append({
			"id": String(player.get("id", "seat_%d" % [i + 1])),
			"displayName": String(player.get("name", "")),
			"type": "player",
			"seatNumber": i + 1,
		})
	var observers_value = room.get("observers", [])
	if observers_value is Array:
		for observer in observers_value as Array:
			if not (observer is Dictionary):
				continue
			var observer_id := String((observer as Dictionary).get("id", "")).strip_edges()
			if observer_id == "":
				continue
			participants.append({
				"id": observer_id,
				"displayName": String((observer as Dictionary).get("displayName", "观察者")),
				"type": "observer",
				"seatNumber": 0,
			})
	var game_type := String(room.get("type", "狼人杀"))
	var game_id := String(room.get("game_room_id", room.get("gameId", _game_id_for_type(game_type)))).strip_edges()
	if game_id == "":
		game_id = _game_id_for_type(game_type)
	var requires_token := String(room.get("password", "")).strip_edges() != "" or String(room.get("lock", "")) == "密码"
	return {
		"roomId": String(room.get("id", "")),
		"roomName": String(room.get("name", "狼人杀房间")),
		"gameId": game_id,
		"host": host,
		"port": port,
		"minPlayers": int(room.get("min_players", 6)),
		"maxPlayers": int(room.get("max_players", max(6, players.size()))),
		"allowObservers": bool(room.get("allow_observers", true)),
		"maxObservers": int(room.get("max_observers", 3)),
		"maxParticipants": int(room.get("max_participants", int(room.get("max_players", max(6, players.size()))) + int(room.get("max_observers", 3)))),
		"participants": participants,
		"botProfileIds": [],
		"hostDeviceId": host_device_id,
		"hostPublicKey": host_public_key,
		"requiresJoinToken": requires_token,
		"gameStarted": String(room.get("state", "")) == "游戏中",
		"enableTimers": bool(room.get("enable_timers", false)),
		"mapId": String(room.get("map_id", "")),
		"mapName": String(room.get("map_name", "")),
		"bg": String(room.get("bg", "")),
	}


func player_count(room: Dictionary) -> int:
	var count := 0
	for participant in room.get("participants", []):
		if participant is Dictionary and String(participant.get("type", "")) != "observer":
			count += 1
	return count


func observer_count(room: Dictionary) -> int:
	var count := 0
	for participant in room.get("participants", []):
		if participant is Dictionary and String(participant.get("type", "")) == "observer":
			count += 1
	return count


static func local_ipv4() -> String:
	for address in IP.get_local_addresses():
		var value := String(address)
		if value.contains(":"):
			continue
		if value.begins_with("127.") or value.begins_with("169.254."):
			continue
		return value
	return "127.0.0.1"


func _participants_json(value) -> Array:
	var result := []
	if not (value is Array):
		return result
	for item in value:
		if not (item is Dictionary):
			continue
		var data: Dictionary = item
		var id := String(data.get("id", "")).strip_edges()
		if id == "":
			continue
		result.append({
			"id": id,
			"displayName": String(data.get("displayName", "")),
			"type": String(data.get("type", "")),
			"seatNumber": int(data.get("seatNumber", 0)),
		})
	return result


func _string_array(value) -> Array:
	var result := []
	if not (value is Array):
		return result
	for item in value as Array:
		var text := String(item).strip_edges()
		if text != "" and not result.has(text):
			result.append(text)
	return result


func _prune_stale_rooms() -> void:
	var now := Time.get_unix_time_from_system()
	for key in _rooms.keys():
		var room: Dictionary = _rooms[key]
		if now - float(room.get("lastSeenAt", 0.0)) > ROOM_TTL_SEC:
			_rooms.erase(key)


func _game_id_for_type(game_type: String) -> String:
	if game_type == "狼人杀":
		return "werewolf"
	if game_type == "象棋":
		return "xiangqi"
	return game_type.to_lower()


func _type_for_game_id(game_id: String) -> String:
	if game_id == "werewolf":
		return "狼人杀"
	if game_id == "xiangqi":
		return "象棋"
	return game_id


func _default_text(value: String, default_value: String) -> String:
	var trimmed := value.strip_edges()
	return trimmed if trimmed != "" else default_value


func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
