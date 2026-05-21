extends RefCounted
class_name WerewolfActionRequestBuilder


func from_state(state: Dictionary) -> Dictionary:
	var action: Dictionary = (state.get("current_action", {}) as Dictionary) if state.get("current_action", {}) is Dictionary else {}
	if not action.is_empty():
		return {
			"type": "target",
			"action_key": String(action.get("key", "")),
			"actor_index": int(action.get("actor_index", -1)),
			"label": String(action.get("label", "")),
			"icon": String(action.get("icon", "")),
			"effect": String(action.get("effect", "")),
		}
	var speech_index := int(state.get("speech_index", -1))
	if speech_index >= 0:
		return {
			"type": "speech",
			"phase": String(state.get("phase", "")),
			"actor_index": speech_index,
		}
	return {}
