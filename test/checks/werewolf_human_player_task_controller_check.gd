extends SceneTree


func _initialize() -> void:
	var controller = load("res://scripts/player/werewolf/human/werewolf_human_player_task_controller.gd").new()
	var action_state: Dictionary = controller.action_prompt_state({
		"id": "task_a",
		"type": "player_action",
		"actor_index": 1,
		"payload": {
			"action": {
				"label": "警长决定发言顺序",
				"icon": "res://speech.png",
			},
		},
	}, {}, "", "", "2号 玩家")
	if not _expect(int(action_state.get("pending_actor_index", -1)) == 1, "action state captures actor"):
		return
	if not _expect(String(action_state.get("pending_action", "")) == "警长决定发言顺序", "action label comes from task payload"):
		return
	if not _expect(int(action_state.get("speech_prompt_index", 99)) == -1, "action state clears speech prompt"):
		return
	if not _expect(String(action_state.get("system_message", "")) == "轮到 2号 玩家 行动", "action state message is clear"):
		return
	var frame_state: Dictionary = controller.action_prompt_state({
		"type": "player_action",
		"actorIndex": 2,
		"payload": {},
	}, {
		"currentAction": {
			"label": "投票",
			"icon": "res://vote.png",
		},
	}, "旧行动", "old.png", "3号 玩家")
	if not _expect(String(frame_state.get("pending_action", "")) == "投票", "action label falls back to task frame"):
		return
	var speech_state: Dictionary = controller.speech_prompt_state({"type": "player_speech", "actorIndex": 0}, "1号 玩家")
	if not _expect(int(speech_state.get("speech_prompt_index", -1)) == 0, "speech state captures speaker"):
		return
	if not _expect(String(speech_state.get("pending_action", "x")) == "", "speech state clears pending action"):
		return
	if not _expect(bool(speech_state.get("open_speech_editor", false)), "speech state opens editor"):
		return
	var action_payload: Dictionary = controller.action_result_payload(3, "sheriff_speech_order_clockwise")
	if not _expect(String(action_payload.get("type", "")) == "player_action", "action result type is generic"):
		return
	if not _expect(int(action_payload.get("targetSeatNumber", -1)) == 4, "action result uses one-based seat"):
		return
	if not _expect(String(action_payload.get("action", "")) == "sheriff_speech_order_clockwise", "action result carries action choice"):
		return
	var destroy_payload: Dictionary = controller.action_result_payload(4, "sheriff_badge_destroy")
	if not _expect(int(destroy_payload.get("targetIndex", 99)) == -1, "destroy badge action has no target"):
		return
	if not _expect(int(destroy_payload.get("targetSeatNumber", 99)) == -1, "destroy badge action has no target seat"):
		return
	var skip_payload: Dictionary = controller.action_result_payload(2, "witch_skip")
	if not _expect(int(skip_payload.get("targetIndex", 99)) == -1, "skip action has no target"):
		return
	if not _expect(int(skip_payload.get("targetSeatNumber", 99)) == -1, "skip action has no target seat"):
		return
	var speech_payload: Dictionary = controller.speech_result_payload("我发言。")
	if not _expect(String(speech_payload.get("type", "")) == "player_speech", "speech result type is generic"):
		return
	if not _expect(String(speech_payload.get("text", "")) == "我发言。", "speech result carries text"):
		return
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_human_player_task_controller_check failed: %s" % message)
	quit(1)
	return false
