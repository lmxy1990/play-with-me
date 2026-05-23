extends RefCounted

const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")

var _role_catalog = RoleCatalogScript.new()


func snapshot_for_participant(
	room: Dictionary,
	players: Array,
	werewolf: Dictionary,
	history: Array,
	wolf_private_history: Array,
	participant_id: String,
	local_player_index: int,
	can_view_wolf_private_history: bool,
	system_message: String,
	phase_night: bool,
	bot_serial: int
) -> Dictionary:
	var can_view_private := can_view_wolf_private_history or participant_is_observer(room, participant_id)
	return {
		"room": _public_room(room),
		"players": players_for_participant(players, participant_id, room, werewolf),
		"werewolf": werewolf.duplicate(true),
		"history": history_for_participant(history, players, room, participant_id, local_player_index, can_view_private),
		"wolfPrivateHistory": wolf_private_history.duplicate(true) if can_view_private else [],
		"systemMessage": system_message,
		"phaseNight": phase_night,
		"botSerial": bot_serial,
		"participantId": participant_id,
		"localPlayerIndex": local_player_index,
	}


func replica_state_payload(
	room: Dictionary,
	players: Array,
	werewolf: Dictionary,
	history: Array,
	system_message: String,
	phase_night: bool,
	bot_serial: int
) -> Dictionary:
	return {
		"room": _public_room(room),
		"players": players_for_participant(players, ""),
		"werewolf": werewolf.duplicate(true),
		"history": public_history(history),
		"systemMessage": system_message,
		"phaseNight": phase_night,
		"botSerial": bot_serial,
		"visibleReplicaOnly": true,
	}


func players_for_participant(players: Array, participant_id: String, room: Dictionary = {}, werewolf: Dictionary = {}) -> Array:
	var result := []
	var viewer_index := seat_for_participant(players, participant_id)
	var viewer_is_observer := participant_is_observer(room, participant_id)
	var reveal_all_roles := _roles_visible_to_all(werewolf)
	for i in range(players.size()):
		if not (players[i] is Dictionary):
			result.append(players[i])
			continue
		var player: Dictionary = (players[i] as Dictionary).duplicate(true)
		_strip_private_player_fields(player)
		_apply_role_visibility(player, players, i, viewer_index, viewer_is_observer, reveal_all_roles)
		var owner := String(player.get("owner", ""))
		var player_participant := String(player.get("participant_id", ""))
		if owner == "self" or owner == "human":
			player["owner"] = "self" if participant_matches(participant_id, owner, player_participant) else "human"
		result.append(player)
	return result


func history_for_participant(history: Array, players: Array, room: Dictionary, participant_id: String, local_player_index: int, can_view_wolf_private_history: bool) -> Array:
	var result := []
	for item in history:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		if history_item_visible_for_participant(entry, players, room, participant_id, local_player_index, can_view_wolf_private_history):
			result.append(entry.duplicate(true))
	return result


func public_history(history: Array) -> Array:
	var result := []
	for item in history:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var visibility := String(entry.get("visibility", "public")).strip_edges()
		if visibility == "" or visibility == "public":
			result.append(entry.duplicate(true))
	return result


func history_item_visible_for_participant(item: Dictionary, players: Array, room: Dictionary, participant_id: String, local_player_index: int, can_view_wolf_private_history: bool) -> bool:
	var visibility := String(item.get("visibility", "public")).strip_edges()
	if visibility == "" or visibility == "public":
		return true
	if participant_is_observer(room, participant_id):
		return true
	var viewer_index := local_player_index
	if viewer_index < 0:
		viewer_index = seat_for_participant(players, participant_id)
	if viewer_index < 0:
		return false
	var visible_indices := visible_to_indices(item)
	if visible_indices.has(viewer_index):
		return true
	match visibility:
		"private":
			return history_item_actor_index(item, players.size()) == viewer_index
		"wolf":
			return can_view_wolf_private_history or player_role_key(players, viewer_index) == "wolf"
		"observer":
			return false
		_:
			return true
	return true


func visible_to_indices(item: Dictionary) -> Array:
	var result := []
	var value = item.get("visible_to_indices", item.get("visibleToIndices", []))
	if value is Array:
		for entry in value as Array:
			var index := int(entry)
			if index >= 0 and not result.has(index):
				result.append(index)
	return result


func history_item_actor_index(item: Dictionary, player_count: int) -> int:
	var explicit := int(item.get("speaker_index", item.get("actor_index", -1)))
	if explicit >= 0:
		return explicit
	return speaker_index_for_history(String(item.get("speaker", "")), player_count)


func speaker_index_for_history(speaker: String, player_count: int) -> int:
	var marker := speaker.find("号")
	if marker <= 0:
		return -1
	var seat_text := speaker.substr(0, marker).strip_edges()
	if not seat_text.is_valid_int():
		return -1
	var index := int(seat_text.to_int()) - 1
	if index < 0 or index >= player_count:
		return -1
	return index


func player_role_key(players: Array, index: int) -> String:
	if index < 0 or index >= players.size() or not (players[index] is Dictionary):
		return ""
	return String((players[index] as Dictionary).get("role_key", ""))


func seat_for_participant(players: Array, participant_id: String) -> int:
	var clean := participant_id.strip_edges()
	for i in range(players.size()):
		if not (players[i] is Dictionary):
			continue
		var player: Dictionary = players[i]
		var owner := String(player.get("owner", ""))
		var player_participant := String(player.get("participant_id", ""))
		if clean != "" and player_participant == clean:
			return i
		if clean == "host" and owner == "self":
			return i
	return -1


func participant_is_observer(room: Dictionary, participant_id: String) -> bool:
	var clean := participant_id.strip_edges()
	if clean == "":
		return false
	var observers_value = room.get("observers", [])
	if not (observers_value is Array):
		return false
	for item in observers_value as Array:
		if item is Dictionary and String((item as Dictionary).get("id", "")).strip_edges() == clean:
			return true
	return false


func _public_room(room: Dictionary) -> Dictionary:
	var result := room.duplicate(true)
	for field in ["password", "qr_secrets", "reconnect_tokens", "active_bot_profile_ids", "botProfileIds"]:
		result.erase(field)
	return result


func _strip_private_player_fields(player: Dictionary) -> void:
	for field in ["api_key", "apiKey", "endpoint", "provider", "model", "modelName", "model_name", "modelProfile", "model_profile", "modelConfig", "model_config", "requestOptions", "request_options", "response_schema", "responseSchema", "schema", "bot_profile_id", "botProfileId", "formt_adapter", "formtAdapter", "format_adapter", "formatAdapter", "output_adapter", "outputAdapter", "reason_adapter", "reasonAdapter", "reasoning_adapter", "reasoningAdapter", "temperature", "max_output", "maxOutput", "max_output_tokens", "maxOutputTokens", "max_context", "maxContext"]:
		player.erase(field)


func _apply_role_visibility(player: Dictionary, players: Array, target_index: int, viewer_index: int, viewer_is_observer: bool, reveal_all_roles: bool) -> void:
	if String(player.get("owner", "")).strip_edges() == "":
		player["role_visible"] = true
		return
	var visible := _role_visible_for_viewer(players, target_index, viewer_index, viewer_is_observer, reveal_all_roles)
	player["role_visible"] = visible
	if visible:
		return
	player["role"] = "未知"
	player["role_key"] = ""
	player["roleKey"] = ""
	player["role_title"] = ""
	player["roleTitle"] = ""
	player["role_avatar"] = ""
	player["roleAvatar"] = ""


func _role_visible_for_viewer(players: Array, target_index: int, viewer_index: int, viewer_is_observer: bool, reveal_all_roles: bool) -> bool:
	if target_index < 0 or target_index >= players.size() or not (players[target_index] is Dictionary):
		return false
	if reveal_all_roles or viewer_is_observer or target_index == viewer_index:
		return true
	var player: Dictionary = players[target_index]
	if _role_publicly_revealed(player):
		return true
	if viewer_index >= 0 and viewer_index < players.size() and players[viewer_index] is Dictionary:
		var viewer_role := String((players[viewer_index] as Dictionary).get("role_key", "")).strip_edges()
		var target_role := String(player.get("role_key", "")).strip_edges()
		if _role_catalog.can_see_wolf_teammates(viewer_role) and _role_catalog.is_wolf_team(target_role) and _role_catalog.visible_to_wolf_teammates(target_role):
			return true
	return false


func _role_publicly_revealed(player: Dictionary) -> bool:
	return bool(player.get("idiot_revealed", false)) or bool(player.get("public_role_visible", false))


func _roles_visible_to_all(werewolf: Dictionary) -> bool:
	var phase := String(werewolf.get("phase", "lobby")).strip_edges()
	if phase == "" or phase == "lobby":
		return true
	if not bool(werewolf.get("started", false)):
		return true
	return phase in ["replay_round", "post_game_summary", "mvp_vote", "completed"]


func participant_matches(participant_id: String, owner: String, player_participant: String) -> bool:
	var clean := participant_id.strip_edges()
	if clean == "":
		return false
	if player_participant.strip_edges() != "":
		return clean == player_participant
	return clean == "host" and owner == "self"


func roster_payload(room: Dictionary, players: Array) -> Array:
	var roster: Array = []
	for player in players:
		if player is Dictionary and String((player as Dictionary).get("owner", "")).strip_edges() != "":
			var participant_id := String((player as Dictionary).get("participant_id", "")).strip_edges()
			if participant_id == "":
				participant_id = String((player as Dictionary).get("controller_participant_id", (player as Dictionary).get("controllerParticipantId", ""))).strip_edges()
			roster.append({
				"id": participant_id,
				"type": "player",
				"deviceId": String((player as Dictionary).get("device_id", "")),
				"publicKey": String((player as Dictionary).get("public_key", "")),
			})
	var observers_value = room.get("observers", [])
	if observers_value is Array:
		for observer in observers_value as Array:
			if observer is Dictionary:
				roster.append({
					"id": String((observer as Dictionary).get("id", "")),
					"type": "observer",
					"deviceId": String((observer as Dictionary).get("device_id", "")),
					"publicKey": String((observer as Dictionary).get("public_key", "")),
				})
	return roster
