extends SceneTree

const MapperScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_record_formatter.gd")


func _initialize() -> void:
	var mapper = MapperScript.new()
	var player_ids := ["p1", "p2", "p3"]
	var history := [
		{"speaker": "系统", "text": "第1夜开始", "at": 5.0},
		{"speaker": "1号 甲", "text": "我怀疑2号", "at": 10.0},
	]
	var private_history := [
		{"actor_index": 1, "text": "我建议刀3号位", "at": 7.0},
	]

	var text_timeline: Array = mapper.recent_text_timeline(history, 1)
	assert(text_timeline.size() == 1)
	assert(String((text_timeline[0] as Dictionary).get("speaker", "")) == "1号 甲")

	var public_event: Dictionary = mapper.history_item_to_model_event(history[1] as Dictionary, player_ids, "day")
	assert(String(public_event.get("type", "")) == "player_spoke")
	assert(String(public_event.get("eventKind", "")) == "actor_speech")
	assert(String(public_event.get("actorId", "")) == "p1")
	assert(String(public_event.get("targetId", "")) == "p2")
	assert(String(public_event.get("speechText", "")) == "我怀疑2号")

	var system_event: Dictionary = mapper.history_item_to_model_event(history[0] as Dictionary, player_ids, "night")
	assert(String(system_event.get("type", "")) == "night_started")
	assert(String(system_event.get("eventKind", "")) == "system_instruction")

	var wolf_event: Dictionary = mapper.wolf_private_item_to_model_event(private_history[0] as Dictionary, player_ids)
	assert(String(wolf_event.get("type", "")) == "wolf_spoke")
	assert(String(wolf_event.get("actorId", "")) == "p2")
	assert(String(wolf_event.get("speechText", "")) == "我建议刀3号位")

	var visible: Array = mapper.recent_visible_events(history, private_history, 2, player_ids, "day", 1, true)
	assert(visible.size() == 2)
	assert(String((visible[0] as Dictionary).get("type", "")) == "wolf_spoke")
	assert(String((visible[1] as Dictionary).get("type", "")) == "player_spoke")
	assert(mapper.visible_timeline_event_count(history, private_history, player_ids, 2, false) == 2)
	assert(mapper.visible_timeline_event_count(history, private_history, player_ids, 1, true) == 3)

	var duplicate_history := [
		{"speaker": "系统", "text": "第1夜开始", "at": 5.0},
		{"speaker": "2号 乙", "text": "我建议刀3号位", "actor_index": 1, "speaker_index": 1, "visibility": "wolf", "action_key": "wolf_chat", "at": 8.0},
		{"speaker": "3号 丙", "text": "我不知道狼聊", "actor_index": 2, "speaker_index": 2, "visibility": "private", "visible_to_indices": [2], "at": 9.0},
	]
	var deduped_wolf_view: Array = mapper.recent_visible_events(duplicate_history, private_history, 10, player_ids, "wolf_chat", 1, true)
	assert(deduped_wolf_view.size() == 2)
	assert(String((deduped_wolf_view[0] as Dictionary).get("type", "")) == "night_started")
	assert(String((deduped_wolf_view[1] as Dictionary).get("type", "")) == "wolf_spoke")
	assert(mapper.visible_timeline_event_count(duplicate_history, private_history, player_ids, 1, true) == 2)
	var villager_view: Array = mapper.recent_visible_events(duplicate_history, private_history, 10, player_ids, "wolf_chat", 2, false)
	assert(villager_view.size() == 2)
	assert(String((villager_view[0] as Dictionary).get("type", "")) == "night_started")
	assert(String((villager_view[1] as Dictionary).get("actorId", "")) == "p3")

	var stale_id_private_history := [
		{"actor_index": 1, "actor_id": "old_wolf_b", "text": "我建议刀3号位", "at": 7.0},
	]
	var stale_id_wolf_view: Array = mapper.recent_visible_events(duplicate_history, stale_id_private_history, 10, player_ids, "wolf_chat", 1, true)
	assert(stale_id_wolf_view.size() == 2)
	assert(mapper.visible_timeline_event_count(duplicate_history, stale_id_private_history, player_ids, 1, true) == 2)

	assert(mapper.history_event_type("2号 乙", "遗言：我觉得3号可疑", 3, "last_words") == "last_words")
	assert(mapper.speech_text_from_history("遗言：我觉得3号可疑") == "我觉得3号可疑")
	assert(mapper.first_seat_index_in_text("3号位说话", 3) == 2)
	var action_event: Dictionary = mapper.history_item_to_model_event({
		"speaker": "2号 乙",
		"text": "选择袭击3号 丙。",
		"actor_index": 1,
		"target_index": 2,
		"action_key": "wolf_kill",
	}, player_ids, "wolf_action")
	assert(String(action_event.get("type", "")) == "wolf_targeted")
	assert(String(action_event.get("eventKind", "")) == "actor_action")
	assert(String(action_event.get("actorId", "")) == "p2")
	assert(String(action_event.get("targetId", "")) == "p3")
	quit()
