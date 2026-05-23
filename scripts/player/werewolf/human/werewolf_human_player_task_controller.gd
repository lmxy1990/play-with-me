extends RefCounted


const TASK_TYPE_ACTION := "player_action"
const TASK_TYPE_SPEECH := "player_speech"
const ACTION_DESTROY_SHERIFF_BADGE := "sheriff_badge_destroy"
const ACTION_SKIP := "skip"
const ACTION_WITCH_SKIP := "witch_skip"


func action_prompt_state(task: Dictionary, task_frame: Dictionary = {}, current_label: String = "", current_icon: String = "", actor_title: String = "") -> Dictionary:
	var actor_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	var action := _task_action(task, task_frame)
	var label := current_label
	var icon := current_icon
	if not action.is_empty():
		label = String(action.get("label", label))
		icon = String(action.get("icon", icon))
	var title := actor_title.strip_edges()
	if title == "":
		title = "%d号玩家" % [actor_index + 1] if actor_index >= 0 else "玩家"
	return {
		"pending_actor_index": actor_index,
		"pending_action": label,
		"pending_action_icon": icon,
		"speech_prompt_index": -1,
		"system_message": "轮到 %s 行动" % title,
	}


func speech_prompt_state(task: Dictionary, speaker_title: String = "") -> Dictionary:
	var speaker_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	var title := speaker_title.strip_edges()
	if title == "":
		title = "%d号玩家" % [speaker_index + 1] if speaker_index >= 0 else "玩家"
	return {
		"pending_actor_index": -1,
		"pending_action": "",
		"pending_action_icon": "",
		"speech_prompt_index": speaker_index,
		"system_message": "轮到 %s 发言" % title,
		"open_speech_editor": true,
	}


func action_result_payload(target_index: int, action_name: String = "") -> Dictionary:
	var clean_action := action_name.strip_edges()
	var payload := {
		"ok": true,
		"type": TASK_TYPE_ACTION,
		"taskType": TASK_TYPE_ACTION,
		"targetIndex": target_index,
		"targetSeatNumber": target_index + 1,
	}
	if clean_action != "":
		payload["action"] = clean_action
	if clean_action in [ACTION_DESTROY_SHERIFF_BADGE, ACTION_SKIP, ACTION_WITCH_SKIP]:
		payload["targetIndex"] = -1
		payload["targetSeatNumber"] = -1
	return payload


func speech_result_payload(text: String) -> Dictionary:
	return {
		"ok": true,
		"type": TASK_TYPE_SPEECH,
		"taskType": TASK_TYPE_SPEECH,
		"text": text,
	}


func _task_action(task: Dictionary, task_frame: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = task.get("payload", {}) if task.get("payload", {}) is Dictionary else {}
	var action_value = payload.get("action", {})
	if action_value is Dictionary and not (action_value as Dictionary).is_empty():
		return (action_value as Dictionary).duplicate(true)
	var frame_action_value = task_frame.get("currentAction", {})
	if frame_action_value is Dictionary:
		return (frame_action_value as Dictionary).duplicate(true)
	return {}
