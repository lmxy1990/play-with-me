extends SceneTree


func _initialize() -> void:
	var qr = load("res://scripts/network/qr_join_payload.gd").new()
	var payload: String = qr.build_encoded("192.168.1.8", 42871, "room_1", "月下长桌", "werewolf", false, "1234", "host_a", "pub", "guard_village", "守卫村庄", "res://assets/images/werewolf/backgrounds/map_guard_standard.png")
	var parsed: Dictionary = qr.parse(payload)
	assert(bool(parsed["ok"]))
	assert(String(parsed["host"]) == "192.168.1.8")
	assert(int(parsed["port"]) == 42871)
	assert(String(parsed["joinToken"]) == "1234")
	assert(String(parsed["mapId"]) == "guard_village")
	assert(String(parsed["mapName"]) == "守卫村庄")
	assert(String(parsed["bg"]) == "res://assets/images/werewolf/backgrounds/map_guard_standard.png")
	assert(not bool(qr.parse("{}").get("ok", false)))

	var discovery = load("res://scripts/network/lan_room_discovery.gd").new()
	var source_room := {
		"roomId": "room_1",
		"roomName": "月下长桌",
		"gameId": "werewolf",
		"host": "",
		"port": 42871,
		"minPlayers": 6,
		"maxPlayers": 8,
		"allowObservers": true,
		"maxObservers": 3,
		"participants": [
			{"id": "p1", "displayName": "1号", "type": "player", "seatNumber": 1},
			{"id": "b1", "displayName": "受控玩家", "type": "player", "seatNumber": 2},
			{"id": "o1", "displayName": "观者", "type": "observer", "seatNumber": 0},
		],
		"botProfileIds": ["bot_a"],
		"requiresJoinToken": true,
		"gameStarted": false,
		"mapId": "guard_village",
		"mapName": "守卫村庄",
		"bg": "res://assets/images/werewolf/backgrounds/map_guard_standard.png",
	}
	var packet := JSON.stringify(discovery.room_to_json(source_room))
	var found: Dictionary = discovery.parse_packet(packet, "192.168.1.9")
	assert(bool(found["ok"]))
	assert(String(found["host"]) == "192.168.1.9")
	assert(int(found["playerCount"]) == 2)
	assert(int(found["observerCount"]) == 1)
	assert(bool(found["allowObservers"]))
	assert(int(found["maxObservers"]) == 3)
	assert((found["botProfileIds"] as Array).is_empty())
	assert(String(found["mapId"]) == "guard_village")
	var app_room: Dictionary = discovery.app_room_from_discovery(found)
	assert(String(app_room["id"]) == "room_1")
	assert(String(app_room["lock"]) == "密码")
	assert(String(app_room["address"]) == "192.168.1.9:42871")
	assert(String(app_room["map_id"]) == "guard_village")
	assert((app_room["active_bot_profile_ids"] as Array).is_empty())

	var state_room: Dictionary = discovery.room_from_state(
		{"id": "room_2", "name": "本地长桌", "type": "狼人杀", "password": "", "max_players": 6, "allow_observers": true, "max_observers": 2, "map_id": "basic_village", "map_name": "标准村庄", "observers": [{"id": "o1", "displayName": "观者"}]},
		[
			{"id": "self", "name": "阿景", "owner": "self"},
			{"id": "player_1", "name": "机器人1", "owner": "human", "participant_id": "", "controller_participant_id": "host"},
		],
		"192.168.1.10",
		42871
	)
	assert(String(state_room["gameId"]) == "werewolf")
	assert((state_room["participants"] as Array).size() == 3)
	assert(int(discovery.observer_count(state_room)) == 1)
	assert(bool(state_room["allowObservers"]))
	assert(int(state_room["maxObservers"]) == 2)
	assert(not bool(state_room["requiresJoinToken"]))
	assert(String(state_room["mapId"]) == "basic_village")
	assert((state_room["botProfileIds"] as Array).is_empty())

	var closed_packet := JSON.stringify(discovery.room_closed_to_json("room_2", "", 42871, "host_a", "pub"))
	var closed: Dictionary = discovery.parse_packet(closed_packet, "192.168.1.11")
	assert(bool(closed["ok"]))
	assert(bool(closed["closed"]))
	assert(String(closed["roomId"]) == "room_2")
	assert(String(closed["host"]) == "192.168.1.11")
	quit()
