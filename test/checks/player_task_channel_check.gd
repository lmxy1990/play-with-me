extends SceneTree


func _initialize() -> void:
	var channel = load("res://scripts/player/player_task_channel.gd").new()
	var rejected: Dictionary = channel.create_task("", 0, "peer_alpha", {})
	if not _expect(rejected.is_empty(), "empty task type is rejected"):
		return
	rejected = channel.create_task("player_action", -1, "peer_alpha", {})
	if not _expect(rejected.is_empty(), "invalid actor is rejected"):
		return
	rejected = channel.create_task("player_action", 0, "", {})
	if not _expect(rejected.is_empty(), "empty controller is rejected"):
		return
	var task: Dictionary = channel.create_task("player_action", 2, "peer_alpha", {
		"turn_key": "turn_a",
		"actor": {
			"participantId": "player_alpha",
			"kind": "player",
		},
	})
	if not _expect(not task.is_empty(), "task is created"):
		return
	var task_id := String(task.get("id", ""))
	if not _expect(task_id.begins_with("player_task_"), "task id uses player module prefix"):
		return
	if not _expect(channel.has_task(task_id), "task is stored"):
		return
	if not _expect(channel.has_pending_for_actor(2, ["player_action"]), "actor pending lookup works"):
		return
	if not _expect(int(task.get("actorSeatNumber", 0)) == 3, "actor seat is captured"):
		return
	if not _expect(String(task.get("actorParticipantId", "")) == "player_alpha", "actor participant is captured"):
		return
	if not _expect(String(task.get("controllerParticipantId", "")) == "peer_alpha", "controller device is captured"):
		return
	if not _expect(String(task.get("hostParticipantId", "")) == "host", "host requester defaults to host"):
		return
	var snapshot: Dictionary = channel.snapshot()
	if not _expect(int(snapshot.get("pendingCount", 0)) == 1, "snapshot contains pending task"):
		return
	if not _expect(bool(snapshot.get("blocksAutoAdvance", false)), "pending task blocks auto advance"):
		return
	var by_controller: Dictionary = snapshot.get("pendingByController", {})
	if not _expect(int(by_controller.get("peer_alpha", 0)) == 1, "snapshot groups by controller"):
		return
	channel.mark_dispatched(task_id, 42)
	var dispatched: Dictionary = channel.task(task_id)
	if not _expect(String(dispatched.get("delivery_status", "")) == "dispatched", "dispatch status is tracked"):
		return
	if not _expect(int(dispatched.get("route_peer_id", -1)) == 42, "dispatch peer is tracked"):
		return
	var wrong_removed: Array = channel.remove_tasks_for_participant("peer_beta")
	if not _expect(wrong_removed.is_empty(), "unrelated participant does not remove task"):
		return
	var removed: Array = channel.remove_tasks_for_participant("peer_alpha")
	if not _expect(removed.size() == 1, "controller participant removes task"):
		return
	if not _expect(not channel.has_task(task_id), "removed task is gone"):
		return
	var second: Dictionary = channel.create_task("player_speech", 1, "host", {"hostParticipantId": "host_device"})
	channel.mark_route_failed(String(second.get("id", "")), "send_failed")
	var failed: Dictionary = channel.task(String(second.get("id", "")))
	if not _expect(String(failed.get("delivery_status", "")) == "failed", "route failure status is tracked"):
		return
	if not _expect(String(failed.get("route_error", "")) == "send_failed", "route failure reason is tracked"):
		return
	var popped: Dictionary = channel.pop_task(String(second.get("id", "")))
	if not _expect(String(popped.get("type", "")) == "player_speech", "pop returns task"):
		return
	if not _expect(int(channel.pending_count()) == 0, "channel is empty after pop"):
		return
	if not _expect(not channel.blocks_auto_advance(), "empty channel does not block"):
		return
	channel.set_task_id_prefix("custom_task")
	var custom: Dictionary = channel.create_task("player_action", 0, "host", {})
	if not _expect(String(custom.get("id", "")).begins_with("custom_task_"), "custom task prefix works"):
		return
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("player_task_channel_check failed: %s" % message)
	quit(1)
	return false
