extends SceneTree


func _initialize() -> void:
	var expected := {
		"basic_village": "res://assets/images/werewolf/backgrounds/map_basic.png",
		"hunter_pressure_village": "res://assets/images/werewolf/backgrounds/map_hunter_pressure.png",
		"quick_no_witch_village": "res://assets/images/werewolf/backgrounds/map_quick_no_witch.png",
		"guard_village": "res://assets/images/werewolf/backgrounds/map_guard_standard.png",
		"sheriff_square": "res://assets/images/werewolf/backgrounds/map_sheriff_standard.png",
		"sheriff_guard_square": "res://assets/images/werewolf/backgrounds/map_sheriff_guard.png",
	}
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()

	var seen := {}
	for map_id in expected.keys():
		var path := String(expected[map_id])
		assert(ResourceLoader.exists(path))
		assert(state.map_background_path(String(map_id)) == path)
		var room: Dictionary = state.create_room("狼人杀", 6, "", String(map_id), "测试地图")
		assert(String(room.get("bg", "")) == path)
		seen[path] = true
	assert(seen.size() == expected.size())

	var discovery = load("res://scripts/network/lan_room_discovery.gd").new()
	var guard_path := String(expected["guard_village"])
	var broadcast: Dictionary = discovery.room_from_state({
		"id": "room_guard",
		"name": "守卫房间",
		"type": "狼人杀",
		"max_players": 6,
		"password": "",
		"map_id": "guard_village",
		"map_name": "守卫村庄",
		"bg": guard_path,
	}, [], "127.0.0.1", 42871)
	assert(String(broadcast.get("mapId", "")) == "guard_village")
	assert(String(broadcast.get("mapName", "")) == "守卫村庄")
	assert(String(broadcast.get("bg", "")) == guard_path)

	var app_room: Dictionary = discovery.app_room_from_discovery(broadcast)
	assert(String(app_room.get("map_id", "")) == "guard_village")
	assert(String(app_room.get("map_name", "")) == "守卫村庄")
	assert(String(app_room.get("bg", "")) == guard_path)
	var qr = load("res://scripts/network/qr_join_payload.gd").new()
	var parsed_payload: Dictionary = qr.parse(String(app_room.get("join_payload", "")))
	assert(bool(parsed_payload.get("ok", false)))
	assert(String(parsed_payload.get("mapId", "")) == "guard_village")
	assert(String(parsed_payload.get("mapName", "")) == "守卫村庄")
	assert(String(parsed_payload.get("bg", "")) == guard_path)
	quit()
