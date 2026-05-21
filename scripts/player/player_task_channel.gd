extends RefCounted


const PARTICIPANT_HOST := "host"

var _tasks := {}
var _serial := 0
var _task_id_prefix := "player_task"


func set_task_id_prefix(prefix: String) -> void:
	var clean := prefix.strip_edges()
	if clean == "":
		return
	_task_id_prefix = clean


func blocks_auto_advance() -> bool:
	return pending_count() > 0


func clear() -> void:
	_tasks.clear()
	_serial = 0


func create_task(task_type: String, actor_index: int, controller_participant_id: String, payload: Dictionary = {}) -> Dictionary:
	var clean_type := task_type.strip_edges()
	var controller := controller_participant_id.strip_edges()
	if clean_type == "" or actor_index < 0 or controller == "":
		return {}
	_serial += 1
	var id := "%s_%d_%d" % [_task_id_prefix, Time.get_ticks_msec(), _serial]
	var actor = payload.get("actor", {})
	var actor_data: Dictionary = actor.duplicate(true) if actor is Dictionary else {}
	var requester := String(payload.get("hostParticipantId", payload.get("host_participant_id", PARTICIPANT_HOST))).strip_edges()
	if requester == "":
		requester = PARTICIPANT_HOST
	var task := {
		"id": id,
		"task_id": id,
		"type": clean_type,
		"taskType": clean_type,
		"actor_index": actor_index,
		"actorIndex": actor_index,
		"actorSeatNumber": actor_index + 1,
		"actor": actor_data,
		"actor_participant_id": String(actor_data.get("participantId", actor_data.get("participant_id", ""))).strip_edges(),
		"actorParticipantId": String(actor_data.get("participantId", actor_data.get("participant_id", ""))).strip_edges(),
		"actor_kind": String(actor_data.get("kind", "player")),
		"actorKind": String(actor_data.get("kind", "player")),
		"controller_participant_id": controller,
		"controllerParticipantId": controller,
		"controller": {"participantId": controller},
		"host_participant_id": requester,
		"hostParticipantId": requester,
		"delivery": "device",
		"payload": payload.duplicate(true),
		"created_at_msec": Time.get_ticks_msec(),
		"status": "pending",
		"delivery_status": "created",
		"dispatched_at_msec": 0,
		"failed_at_msec": 0,
		"route_error": "",
	}
	_tasks[id] = task
	return task.duplicate(true)


func has_task(task_id: String) -> bool:
	return _tasks.has(task_id.strip_edges())


func task(task_id: String) -> Dictionary:
	var clean := task_id.strip_edges()
	if not _tasks.has(clean):
		return {}
	return (_tasks[clean] as Dictionary).duplicate(true) if _tasks[clean] is Dictionary else {}


func pop_task(task_id: String) -> Dictionary:
	var clean := task_id.strip_edges()
	if not _tasks.has(clean):
		return {}
	var task_value = _tasks[clean]
	_tasks.erase(clean)
	return (task_value as Dictionary).duplicate(true) if task_value is Dictionary else {}


func mark_dispatched(task_id: String, peer_id: int = 0) -> void:
	var clean := task_id.strip_edges()
	if not _tasks.has(clean) or not (_tasks[clean] is Dictionary):
		return
	var task: Dictionary = _tasks[clean]
	task["status"] = "waiting_result"
	task["delivery_status"] = "dispatched"
	task["dispatched_at_msec"] = Time.get_ticks_msec()
	task["route_peer_id"] = peer_id
	_tasks[clean] = task


func mark_route_failed(task_id: String, error: String) -> void:
	var clean := task_id.strip_edges()
	if not _tasks.has(clean) or not (_tasks[clean] is Dictionary):
		return
	var task: Dictionary = _tasks[clean]
	task["status"] = "route_failed"
	task["delivery_status"] = "failed"
	task["failed_at_msec"] = Time.get_ticks_msec()
	task["route_error"] = error.strip_edges()
	_tasks[clean] = task


func remove_task(task_id: String) -> void:
	_tasks.erase(task_id.strip_edges())


func remove_tasks_for_participant(participant_id: String) -> Array:
	var clean := participant_id.strip_edges()
	var removed := []
	if clean == "":
		return removed
	for task_id in _tasks.keys():
		var task: Dictionary = _tasks[task_id]
		if String(task.get("controller_participant_id", task.get("controllerParticipantId", ""))).strip_edges() != clean:
			continue
		removed.append((task as Dictionary).duplicate(true))
	for task in removed:
		_tasks.erase(String((task as Dictionary).get("id", "")))
	return removed


func has_pending_for_actor(actor_index: int, task_types: Array = []) -> bool:
	for task_id in _tasks.keys():
		var task: Dictionary = _tasks[task_id]
		if int(task.get("actor_index", task.get("actorIndex", -1))) != actor_index:
			continue
		if task_types.is_empty() or task_types.has(String(task.get("type", task.get("taskType", "")))):
			return true
	return false


func pending_count() -> int:
	return _tasks.size()


func pending_by_controller() -> Dictionary:
	var result := {}
	for task_id in _tasks.keys():
		if not (_tasks[task_id] is Dictionary):
			continue
		var task: Dictionary = _tasks[task_id]
		var controller := String(task.get("controller_participant_id", task.get("controllerParticipantId", ""))).strip_edges()
		if controller == "":
			controller = "unknown"
		result[controller] = int(result.get(controller, 0)) + 1
	return result


func snapshot() -> Dictionary:
	var rows := []
	for task_id in _tasks.keys():
		var task: Dictionary = (_tasks[task_id] as Dictionary).duplicate(true)
		rows.append(task)
	return {
		"pendingCount": rows.size(),
		"blocksAutoAdvance": blocks_auto_advance(),
		"pendingByController": pending_by_controller(),
		"tasks": rows,
	}
