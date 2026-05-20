extends SceneTree

const TrackerScript := preload("res://scripts/core/bot/bot_model_request_tracker.gd")


func _initialize() -> void:
	var tracker = TrackerScript.new()
	tracker.register_action(1, {"kind": "action", "target": 2})
	var speech_source := {"line": "先听大家发言", "nested": {"turn": 1}}
	tracker.register_speech(2, speech_source)
	speech_source["nested"]["turn"] = 9

	assert(tracker.has_action(1))
	assert(tracker.has_speech(2))
	assert(tracker.classify(1) == "action")
	assert(tracker.classify(2) == "speech")
	assert(int(tracker.counts().get("action", -1)) == 1)
	assert(int(tracker.counts().get("speech", -1)) == 1)

	var speech: Dictionary = tracker.pop_speech(2)
	assert(String(speech.get("line", "")) == "先听大家发言")
	assert(int((speech.get("nested", {}) as Dictionary).get("turn", -1)) == 1)
	assert(not tracker.has_speech(2))
	assert(not tracker.has_pending_speech())
	assert(tracker.pop_speech(2).is_empty())

	var action: Dictionary = tracker.pop_action(1)
	assert(String(action.get("kind", "")) == "action")
	assert(not tracker.has_pending_actions())
	assert(tracker.classify(3) == "")

	tracker.register_action(4, {})
	tracker.register_speech(5, {})
	tracker.clear()
	assert(int(tracker.counts().get("action", -1)) == 0)
	assert(int(tracker.counts().get("speech", -1)) == 0)
	quit()
