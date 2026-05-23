extends SceneTree

const BuilderScript := preload("res://scripts/room/network/room_network_snapshot_builder.gd")


func _initialize() -> void:
	var builder = BuilderScript.new()
	var room := {
		"id": "room_a",
		"name": "测试房",
		"observers": [{"id": "observer_a", "device_id": "od", "public_key": "op"}],
	}
	var players := [
		{"id": "p1", "name": "房主", "owner": "self", "participant_id": "", "device_id": "hd", "public_key": "hp", "role_key": "villager"},
		{"id": "p2", "name": "玩家", "owner": "human", "participant_id": "peer_a", "device_id": "pd", "public_key": "pp", "role_key": "wolf"},
		{"id": "p3", "name": "受控玩家", "owner": "human", "participant_id": "", "controller_participant_id": "peer_a", "device_id": "", "public_key": "", "voice": "系统默认", "voiceName": "系统默认", "bot_profile_id": "private-profile", "model": "private-model", "api_key": "sk-private", "endpoint": "https://private.example/v1", "modelProfile": {"api_key": "sk-nested"}, "formt_adapter": "openai_json_schema", "outputAdapter": "openai_json_schema", "reason_adapter": "native", "max_output": 4096, "temperature": 0.6},
	]
	assert(builder.participant_matches("host", "self", ""))
	assert(builder.participant_matches("peer_a", "human", "peer_a"))
	assert(not builder.participant_matches("peer_b", "human", "peer_a"))

	var host_players: Array = builder.players_for_participant(players, "host")
	assert(String((host_players[0] as Dictionary).get("owner", "")) == "self")
	assert(String((host_players[1] as Dictionary).get("owner", "")) == "human")
	var peer_players: Array = builder.players_for_participant(players, "peer_a")
	assert(String((peer_players[0] as Dictionary).get("owner", "")) == "human")
	assert(String((peer_players[1] as Dictionary).get("owner", "")) == "self")
	assert(String((peer_players[2] as Dictionary).get("owner", "")) == "human")
	assert(not (peer_players[2] as Dictionary).has("model"))
	assert(String((peer_players[2] as Dictionary).get("voice", "")) == "系统默认")
	assert(String((peer_players[2] as Dictionary).get("voiceName", "")) == "系统默认")
	assert(not (peer_players[2] as Dictionary).has("api_key"))
	assert(not (peer_players[2] as Dictionary).has("endpoint"))
	assert(not (peer_players[2] as Dictionary).has("modelProfile"))
	assert(not (peer_players[2] as Dictionary).has("bot_profile_id"))
	assert(not (peer_players[2] as Dictionary).has("formt_adapter"))
	assert(not (peer_players[2] as Dictionary).has("outputAdapter"))
	assert(not (peer_players[2] as Dictionary).has("reason_adapter"))
	assert(not (peer_players[2] as Dictionary).has("max_output"))
	assert(not (peer_players[2] as Dictionary).has("temperature"))

	var role_players := [
		{"id": "role_host", "name": "房主", "owner": "self", "participant_id": "", "role": "村民", "role_key": "villager", "role_title": "平民", "role_avatar": "role://villager"},
		{"id": "role_peer", "name": "狼人甲", "owner": "human", "participant_id": "peer_a", "role": "狼人", "role_key": "wolf", "role_title": "夜行者", "role_avatar": "role://wolf"},
		{"id": "role_wolf", "name": "狼人乙", "owner": "human", "participant_id": "peer_b", "role": "狼人", "role_key": "wolf", "role_title": "夜行者", "role_avatar": "role://wolf"},
		{"id": "role_idiot", "name": "白痴", "owner": "human", "participant_id": "peer_c", "role": "白痴", "role_key": "idiot", "role_title": "明牌", "role_avatar": "role://idiot", "idiot_revealed": true},
		{"id": "role_seer", "name": "预言家", "owner": "human", "participant_id": "peer_d", "role": "预言家", "role_key": "seer", "role_title": "洞察者", "role_avatar": "role://seer"},
	]
	var started := {"phase": "wolf_action", "started": true}
	var host_started: Array = builder.players_for_participant(role_players, "host", room, started)
	assert(String((host_started[0] as Dictionary).get("role_key", "")) == "villager")
	assert(String((host_started[1] as Dictionary).get("role", "")) == "未知")
	assert(String((host_started[1] as Dictionary).get("role_key", "")) == "")
	assert(not bool((host_started[1] as Dictionary).get("role_visible", true)))
	var peer_started: Array = builder.players_for_participant(role_players, "peer_a", room, started)
	assert(String((peer_started[1] as Dictionary).get("role_key", "")) == "wolf")
	assert(String((peer_started[2] as Dictionary).get("role_key", "")) == "wolf")
	assert(String((peer_started[3] as Dictionary).get("role_key", "")) == "idiot")
	assert(String((peer_started[4] as Dictionary).get("role", "")) == "未知")
	assert(String((peer_started[4] as Dictionary).get("role_title", "")) == "")
	assert(String((peer_started[4] as Dictionary).get("role_avatar", "")) == "")
	var observer_started: Array = builder.players_for_participant(role_players, "observer_a", room, started)
	assert(String((observer_started[4] as Dictionary).get("role_key", "")) == "seer")
	var post_game: Array = builder.players_for_participant(role_players, "peer_a", room, {"phase": "completed", "started": true})
	assert(String((post_game[4] as Dictionary).get("role_key", "")) == "seer")

	var history := [
		{"speaker": "主持人", "text": "第1夜开始", "visibility": "public"},
		{"speaker": "1号 房主", "text": "查验2号：狼人阵营。", "speaker_index": 0, "actor_index": 0, "visibility": "private", "visible_to_indices": [0]},
		{"speaker": "2号 玩家", "text": "选择袭击1号 房主。", "speaker_index": 1, "actor_index": 1, "visibility": "wolf", "action_key": "wolf_kill"},
	]
	var snapshot_hidden: Dictionary = builder.snapshot_for_participant(room, players, {"phase": "wolf_action"}, history, [{"text": "刀3号"}], "peer_a", 1, false, "等待", true, 4)
	assert(not (snapshot_hidden["room"] as Dictionary).has("active_bot_profile_ids"))
	assert((snapshot_hidden["wolfPrivateHistory"] as Array).is_empty())
	assert((snapshot_hidden["history"] as Array).size() == 2)
	assert(not String(((snapshot_hidden["history"] as Array)[1] as Dictionary).get("text", "")).contains("查验"))
	assert(int(snapshot_hidden.get("localPlayerIndex", -1)) == 1)
	var snapshot_visible: Dictionary = builder.snapshot_for_participant(room, players, {}, history, [{"text": "刀3号"}], "host", 0, true, "等待", false, 5)
	assert((snapshot_visible["wolfPrivateHistory"] as Array).size() == 1)
	assert((snapshot_visible["history"] as Array).size() == 3)
	assert(int(snapshot_visible.get("botSerial", 0)) == 5)
	var observer_snapshot: Dictionary = builder.snapshot_for_participant(room, players, {}, history, [{"text": "刀3号"}], "observer_a", -1, false, "等待", false, 5)
	assert((observer_snapshot["history"] as Array).size() == 3)
	assert((observer_snapshot["wolfPrivateHistory"] as Array).size() == 1)

	var replica: Dictionary = builder.replica_state_payload(room, players, {"phase": "day"}, history, "同步", false, 8)
	assert(bool(replica.get("visibleReplicaOnly", false)))
	assert(String(((replica["players"] as Array)[0] as Dictionary).get("owner", "")) == "human")
	assert((replica["history"] as Array).size() == 1)
	var roster: Array = builder.roster_payload(room, players)
	assert(roster.size() == 4)
	assert(String((roster[2] as Dictionary).get("id", "")) == "peer_a")
	assert(String((roster[2] as Dictionary).get("type", "")) == "player")
	assert(String((roster.back() as Dictionary).get("type", "")) == "observer")
	quit()
