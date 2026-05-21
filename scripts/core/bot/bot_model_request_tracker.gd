extends RefCounted


var _action_requests := {}
var _speech_requests := {}


func clear() -> void:
	_action_requests.clear()
	_speech_requests.clear()


func register_action(request_id: int, request: Dictionary) -> void:
	_action_requests[request_id] = request.duplicate(true)


func register_speech(request_id: int, request: Dictionary) -> void:
	_speech_requests[request_id] = request.duplicate(true)


func has_action(request_id: int) -> bool:
	return _action_requests.has(request_id)


func has_speech(request_id: int) -> bool:
	return _speech_requests.has(request_id)


func pop_action(request_id: int) -> Dictionary:
	return _pop(_action_requests, request_id)


func pop_speech(request_id: int) -> Dictionary:
	return _pop(_speech_requests, request_id)


func peek_action(request_id: int) -> Dictionary:
	return _peek(_action_requests, request_id)


func peek_speech(request_id: int) -> Dictionary:
	return _peek(_speech_requests, request_id)


func has_pending_actions() -> bool:
	return not _action_requests.is_empty()


func has_pending_speech() -> bool:
	return not _speech_requests.is_empty()


func classify(request_id: int) -> String:
	if has_action(request_id):
		return "action"
	if has_speech(request_id):
		return "speech"
	return ""


func counts() -> Dictionary:
	return {
		"action": _action_requests.size(),
		"speech": _speech_requests.size(),
	}


func snapshot() -> Dictionary:
	return {
		"counts": counts(),
		"actions": _requests_snapshot(_action_requests),
		"speech": _requests_snapshot(_speech_requests),
	}


func _pop(store: Dictionary, request_id: int) -> Dictionary:
	if not store.has(request_id):
		return {}
	var request: Dictionary = store[request_id]
	store.erase(request_id)
	return request


func _peek(store: Dictionary, request_id: int) -> Dictionary:
	if not store.has(request_id):
		return {}
	return (store[request_id] as Dictionary).duplicate(true) if store[request_id] is Dictionary else {}


func _requests_snapshot(store: Dictionary) -> Array:
	var result := []
	for request_id in store.keys():
		var entry := {}
		if store[request_id] is Dictionary:
			entry = (store[request_id] as Dictionary).duplicate(true)
		entry["request_id"] = int(request_id)
		result.append(entry)
	return result
