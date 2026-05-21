extends RefCounted
class_name WerewolfDeliveryBuilder

const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")

var _role_catalog = RoleCatalogScript.new()


func build_player_frame(state: Dictionary, players: Array, history: Array, receiver_index: int) -> Dictionary:
	return {
		"receiver_seat_number": receiver_index + 1,
		"phase": String(state.get("phase", "")),
		"map_id": String(state.get("map_id", "")),
		"map_name": String(state.get("map_name", "")),
		"players": _players_for_receiver(state, players, receiver_index),
		"history": history.duplicate(true),
		"current_action": _action_for_receiver(state, receiver_index),
		"speech_index": int(state.get("speech_index", -1)),
	}


func _players_for_receiver(state: Dictionary, players: Array, receiver_index: int) -> Array:
	var result: Array = []
	var receiver_role := ""
	if receiver_index >= 0 and receiver_index < players.size() and players[receiver_index] is Dictionary:
		receiver_role = String((players[receiver_index] as Dictionary).get("role_key", ""))
	for i in range(players.size()):
		if not (players[i] is Dictionary):
			continue
		var player: Dictionary = players[i]
		if String(player.get("owner", "")) == "":
			continue
		var row := {
			"seat_number": i + 1,
			"name": String(player.get("name", "")),
			"alive": bool(player.get("alive", true)),
			"state": String(player.get("state", "")),
		}
		var role_key := String(player.get("role_key", ""))
		if i == receiver_index or String(state.get("phase", "")) in ["replay_round", "post_game_summary", "mvp_vote", "completed"] or _wolf_teammate_visible(receiver_role, role_key):
			row["role_key"] = role_key
			row["role_name"] = String(player.get("role", ""))
		result.append(row)
	return result


func _wolf_teammate_visible(receiver_role: String, target_role: String) -> bool:
	return _role_catalog.can_see_wolf_teammates(receiver_role) and _role_catalog.is_wolf_team(target_role) and _role_catalog.visible_to_wolf_teammates(target_role)


func _action_for_receiver(state: Dictionary, receiver_index: int) -> Dictionary:
	var action: Dictionary = (state.get("current_action", {}) as Dictionary) if state.get("current_action", {}) is Dictionary else {}
	if action.is_empty() or int(action.get("actor_index", -1)) != receiver_index:
		return {}
	return action.duplicate(true)
