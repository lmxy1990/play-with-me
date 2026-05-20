extends SceneTree


func _initialize() -> void:
	var codec = load("res://scripts/network/room_network_codec.gd").new()
	var client_text: String = codec.encode_client_message("join_room", "join_1", {"displayName": "阿景"})
	var client: Dictionary = codec.decode_client_message(client_text)
	assert(bool(client["ok"]))
	assert(String(client["type"]) == "join_room")
	assert(String(client["messageId"]) == "join_1")
	assert(String((client["payload"] as Dictionary)["displayName"]) == "阿景")

	var ping: Dictionary = codec.decode_client_message(codec.ping())
	assert(String(ping["type"]) == "ping")

	var server_text: String = codec.encode_server_message("room_snapshot", "snap_1", {"roomId": "room_1"})
	var server: Dictionary = codec.decode_server_message(server_text.to_utf8_buffer())
	assert(bool(server["ok"]))
	assert(String(server["type"]) == "room_snapshot")
	assert(String((server["payload"] as Dictionary)["roomId"]) == "room_1")

	var rejected: Dictionary = codec.decode_server_message("{\"protocolVersion\":2,\"type\":\"pong\",\"messageId\":\"p\"}")
	assert(not bool(rejected["ok"]))
	var bad_type: Dictionary = codec.decode_client_message("{\"type\":\"bad\",\"messageId\":\"m\"}")
	assert(not bool(bad_type["ok"]))
	quit()
