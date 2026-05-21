extends RefCounted
class_name WerewolfReplayBuilder


func build_from_state(state: Dictionary, players: Array, history: Array) -> Dictionary:
	var post: Dictionary = (state.get("post_game", {}) as Dictionary) if state.get("post_game", {}) is Dictionary else {}
	var replay: Dictionary = (post.get("replay_round", {}) as Dictionary) if post.get("replay_round", {}) is Dictionary else {}
	return {
		"room_id": String(state.get("room_id", "")),
		"map_id": String(state.get("map_id", "")),
		"map_name": String(state.get("map_name", "")),
		"phase": String(state.get("phase", "")),
		"winner": String(state.get("winner", "")),
		"replay_round": replay.duplicate(true),
		"history": history.duplicate(true),
		"players": players.duplicate(true),
	}
