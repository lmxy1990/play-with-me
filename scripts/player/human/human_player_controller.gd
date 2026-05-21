extends RefCounted

const PLAYER_TYPE := "human"
const CONTROLLER_TYPE_LOCAL := "local_human"
const CONTROLLER_TYPE_REMOTE := "remote_human"


func display_name_or_fallback(display_name: String, fallback: String) -> String:
	var normalized := display_name.strip_edges()
	if normalized == "":
		return fallback
	return normalized


func local_controller_type() -> String:
	return CONTROLLER_TYPE_LOCAL


func remote_controller_type() -> String:
	return CONTROLLER_TYPE_REMOTE

