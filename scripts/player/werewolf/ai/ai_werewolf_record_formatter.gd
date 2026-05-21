extends RefCounted


func recent_text_timeline(history: Array, limit: int) -> Array:
	var timeline := []
	var start: int = maxi(0, history.size() - limit)
	for i in range(start, history.size()):
		var item = history[i]
		if item is Dictionary:
			timeline.append({
				"speaker": String(item.get("speaker", "系统")),
				"description": String(item.get("text", "")),
			})
	return timeline


func recent_public_events(history: Array, limit: int, player_ids: Array, phase: String) -> Array:
	var timeline := []
	var start: int = maxi(0, history.size() - limit)
	for i in range(start, history.size()):
		var item = history[i]
		if item is Dictionary:
			timeline.append(history_item_to_model_event(item as Dictionary, player_ids, phase))
	return timeline


func recent_visible_events(history: Array, wolf_private_history: Array, limit: int, player_ids: Array, phase: String, viewer_index: int, can_view_wolf_private: bool) -> Array:
	var timeline := []
	var private_wolf_chat_keys := {}
	if can_view_wolf_private:
		private_wolf_chat_keys = private_wolf_chat_dedupe_keys(wolf_private_history, player_ids)
	for item in history:
		if item is Dictionary:
			if not history_item_visible_to_viewer(item as Dictionary, viewer_index, can_view_wolf_private):
				continue
			if can_view_wolf_private and is_duplicate_private_wolf_chat(item as Dictionary, private_wolf_chat_keys, player_ids):
				continue
			var event := history_item_to_model_event(item as Dictionary, player_ids, phase)
			event["_sortAt"] = float((item as Dictionary).get("at", 0.0))
			insert_timeline_event(timeline, event)
	if can_view_wolf_private:
		for item in wolf_private_history:
			if item is Dictionary:
				insert_timeline_event(timeline, wolf_private_item_to_model_event(item as Dictionary, player_ids))
	var result := []
	var start: int = maxi(0, timeline.size() - limit)
	for i in range(start, timeline.size()):
		result.append(timeline[i])
	return result


func visible_timeline_event_count(history: Array, wolf_private_history: Array, player_ids: Array, viewer_index: int, can_view_wolf_private: bool) -> int:
	var count := 0
	var private_wolf_chat_keys := {}
	if can_view_wolf_private:
		private_wolf_chat_keys = private_wolf_chat_dedupe_keys(wolf_private_history, player_ids)
	for item in history:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		if not history_item_visible_to_viewer(entry, viewer_index, can_view_wolf_private):
			continue
		if can_view_wolf_private and is_duplicate_private_wolf_chat(entry, private_wolf_chat_keys, player_ids):
			continue
		count += 1
	if can_view_wolf_private:
		for item in wolf_private_history:
			if item is Dictionary:
				count += 1
	return count


func history_item_visible_to_viewer(item: Dictionary, viewer_index: int, can_view_wolf_private: bool) -> bool:
	var visibility := String(item.get("visibility", "public")).strip_edges()
	if visibility == "" or visibility == "public":
		return true
	if viewer_index >= 0 and visible_to_indices(item).has(viewer_index):
		return true
	match visibility:
		"private":
			return viewer_index >= 0 and int(item.get("actor_index", item.get("speaker_index", -1))) == viewer_index
		"wolf":
			return can_view_wolf_private
		"observer":
			return false
		_:
			return true


func visible_to_indices(item: Dictionary) -> Array:
	var result := []
	var value = item.get("visible_to_indices", item.get("visibleToIndices", []))
	if value is Array:
		for entry in value as Array:
			var index := int(entry)
			if index >= 0 and not result.has(index):
				result.append(index)
	return result


func private_wolf_chat_dedupe_keys(wolf_private_history: Array, player_ids: Array) -> Dictionary:
	var result := {}
	for item in wolf_private_history:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var text := normalized_timeline_text(String(entry.get("text", "")))
		if text == "":
			continue
		for actor_key in actor_keys_from_private_wolf_item(entry, player_ids):
			result["%s|%s" % [String(actor_key), text]] = true
	return result


func is_duplicate_private_wolf_chat(item: Dictionary, private_wolf_chat_keys: Dictionary, player_ids: Array) -> bool:
	if String(item.get("action_key", "")).strip_edges() != "wolf_chat":
		return false
	var text := normalized_timeline_text(String(item.get("text", "")))
	if text == "":
		return false
	for actor_key in actor_keys_from_history_item(item, player_ids):
		if private_wolf_chat_keys.has("%s|%s" % [String(actor_key), text]):
			return true
	return false


func actor_keys_from_private_wolf_item(item: Dictionary, player_ids: Array) -> Array:
	var result := []
	var actor_id := String(item.get("actor_id", "")).strip_edges()
	if actor_id != "":
		result.append("id:%s" % actor_id)
	var actor_index := int(item.get("actor_index", -1))
	var player_id := player_id_for_index(player_ids, actor_index)
	if player_id != "" and not result.has("id:%s" % player_id):
		result.append("id:%s" % player_id)
	if actor_index >= 0:
		result.append("index:%d" % actor_index)
	return result


func actor_keys_from_history_item(item: Dictionary, player_ids: Array) -> Array:
	var result := []
	var speaker := String(item.get("speaker", ""))
	var text := String(item.get("text", ""))
	var actor_id := actor_id_from_item(item, speaker, text, player_ids)
	if actor_id != "":
		result.append("id:%s" % actor_id)
	var actor_index := int(item.get("actor_index", item.get("speaker_index", -1)))
	if actor_index >= 0:
		result.append("index:%d" % actor_index)
	return result


func actor_key_from_private_wolf_item(item: Dictionary, player_ids: Array) -> String:
	var actor_id := String(item.get("actor_id", "")).strip_edges()
	if actor_id != "":
		return "id:%s" % actor_id
	var actor_index := int(item.get("actor_index", -1))
	var player_id := player_id_for_index(player_ids, actor_index)
	if player_id != "":
		return "id:%s" % player_id
	if actor_index >= 0:
		return "index:%d" % actor_index
	return ""


func actor_key_from_history_item(item: Dictionary, player_ids: Array) -> String:
	var speaker := String(item.get("speaker", ""))
	var text := String(item.get("text", ""))
	var actor_id := actor_id_from_item(item, speaker, text, player_ids)
	if actor_id != "":
		return "id:%s" % actor_id
	var actor_index := int(item.get("actor_index", item.get("speaker_index", -1)))
	if actor_index >= 0:
		return "index:%d" % actor_index
	return ""


func normalized_timeline_text(text: String) -> String:
	var result := text.replace("\r", " ").replace("\n", " ").strip_edges()
	while result.contains("  "):
		result = result.replace("  ", " ")
	return result


func insert_timeline_event(timeline: Array, event: Dictionary) -> void:
	var event_time := float(event.get("_sortAt", 0.0))
	for i in range(timeline.size()):
		if event_time < float((timeline[i] as Dictionary).get("_sortAt", 0.0)):
			timeline.insert(i, event)
			return
	timeline.append(event)


func wolf_private_item_to_model_event(item: Dictionary, player_ids: Array) -> Dictionary:
	var text := String(item.get("text", "")).strip_edges()
	var actor_index := int(item.get("actor_index", -1))
	var event := {
		"type": "wolf_spoke",
		"eventKind": "actor_speech",
		"description": text,
		"speechText": text,
		"occurredAt": str(item.get("at", "")),
		"_sortAt": float(item.get("at", 0.0)),
	}
	var actor_id := String(item.get("actor_id", ""))
	if actor_id == "":
		actor_id = player_id_for_index(player_ids, actor_index)
	if actor_id != "":
		event["actorId"] = actor_id
	return event


func history_item_to_model_event(item: Dictionary, player_ids: Array, phase: String) -> Dictionary:
	var speaker := String(item.get("speaker", "系统"))
	var text := String(item.get("text", "")).strip_edges()
	var event_type := history_event_type_for_item(item, speaker, text, player_ids.size(), phase)
	var actor_id := actor_id_from_item(item, speaker, text, player_ids)
	var target_id := target_id_from_item(item, text, player_ids, actor_id)
	var event := {
		"type": event_type,
		"eventKind": history_event_kind(event_type, actor_id, speaker),
		"description": text,
		"occurredAt": str(item.get("at", "")),
	}
	if actor_id != "":
		event["actorId"] = actor_id
	if target_id != "":
		event["targetId"] = target_id
	if actor_id != "" and ["player_spoke", "sheriff_spoke", "last_words", "post_game_summary", "wolf_spoke"].has(event_type):
		event["speechText"] = speech_text_from_history(text)
	return event


func history_event_type_for_item(item: Dictionary, speaker: String, text: String, player_count: int, phase: String) -> String:
	var action_key := String(item.get("action_key", "")).strip_edges()
	match action_key:
		"wolf_kill":
			return "wolf_targeted"
		"guard_protect":
			return "guard_protected"
		"seer_check":
			return "seer_checked"
		"witch_act":
			return "witch_acted"
		"sheriff_vote":
			return "sheriff_vote_cast"
		"sheriff_speech_order":
			return "sheriff_speech_order_selected"
		"sheriff_badge_pass":
			return "sheriff_badge_passed"
		"sheriff_badge_destroy":
			return "sheriff_badge_destroyed"
		"vote":
			return "vote_cast"
		"hunter_shoot":
			return "hunter_shot" if not text.contains("不使用") else "hunter_skipped"
		"mvp_vote":
			return "mvp_vote_cast"
		_:
			return history_event_type(speaker, text, player_count, phase)


func history_event_type(speaker: String, text: String, player_count: int, phase: String) -> String:
	if speaker == "警长投票":
		return "sheriff_vote_cast"
	if speaker == "投票":
		return "vote_cast"
	if speaker == "MVP投票":
		return "mvp_vote_cast"
	if speaker == "查验结果":
		return "seer_checked"
	if speaker == "猎人":
		return "hunter_shot" if text.contains("开枪") else "hunter_skipped"
	if speaker == "夜间记录":
		if text.contains("袭击"):
			return "wolf_targeted"
		if text.contains("守护"):
			return "guard_protected"
		if text.contains("救治") or text.contains("毒药") or text.contains("不使用药"):
			return "witch_acted"
	if text.contains("系统询问女巫"):
		return "witch_prompted"
	if text.contains("游戏开始"):
		return "game_started"
	if text.contains("本局地图") or text.contains("本局选择"):
		return "map_selected"
	if text.contains("夜开始"):
		return "night_started"
	if text.contains("昨夜"):
		return "day_announced"
	if text.contains("警长竞选发言"):
		return "sheriff_speech_started"
	if text.contains("警长投票"):
		return "sheriff_vote_started"
	if text.contains("本局警长"):
		return "sheriff_selected"
	if text.contains("被投票放逐"):
		return "player_exiled"
	if text.contains("遗言阶段"):
		return "last_words_started"
	if text.contains("胜利"):
		return "game_over"
	var actor_index := speaker_index_for_history(speaker, player_count)
	if actor_index >= 0:
		match phase:
			"sheriff_speech":
				return "sheriff_spoke"
			"last_words":
				return "last_words"
			"game_over":
				return "post_game_summary"
			_:
				return "player_spoke"
	return "narrator"


func history_event_kind(event_type: String, actor_id: String, speaker: String) -> String:
	if actor_id != "":
		if event_type in ["wolf_targeted", "guard_protected", "seer_checked", "witch_acted", "sheriff_vote_cast", "sheriff_speech_order_selected", "sheriff_badge_passed", "sheriff_badge_destroyed", "vote_cast", "hunter_shot", "hunter_skipped", "mvp_vote_cast"]:
			return "actor_action"
		return "actor_speech"
	if event_type.ends_with("_started") or event_type == "witch_prompted" or speaker == "系统":
		return "system_instruction"
	return "narrator"


func actor_id_from_item(item: Dictionary, speaker: String, text: String, player_ids: Array) -> String:
	var index := int(item.get("actor_index", item.get("speaker_index", -1)))
	if index >= 0:
		return player_id_for_index(player_ids, index)
	return actor_id_from_history(speaker, text, player_ids)


func target_id_from_item(item: Dictionary, text: String, player_ids: Array, actor_id: String = "") -> String:
	var target_index := int(item.get("target_index", -1))
	if target_index >= 0:
		var direct := player_id_for_index(player_ids, target_index)
		if direct != "":
			return direct
	return target_id_from_history(text, player_ids, actor_id)


func actor_id_from_history(speaker: String, text: String, player_ids: Array) -> String:
	var index := speaker_index_for_history(speaker, player_ids.size())
	if index < 0:
		index = first_seat_index_in_text(text, player_ids.size())
	return player_id_for_index(player_ids, index) if index >= 0 else ""


func target_id_from_history(text: String, player_ids: Array, actor_id: String = "") -> String:
	for i in range(player_ids.size()):
		var id := player_id_for_index(player_ids, i)
		if id == "" or id == actor_id:
			continue
		if text.contains("%d号" % [i + 1]) or text.contains("%d号位" % [i + 1]):
			return id
	return ""


func first_seat_index_in_text(text: String, player_count: int) -> int:
	for i in range(player_count):
		if text.begins_with("%d号" % [i + 1]) or text.begins_with("%d号位" % [i + 1]):
			return i
	return -1


func speech_text_from_history(text: String) -> String:
	var result := text.strip_edges()
	for marker in ["遗言：", "遗言:", "赛后总结：", "赛后总结:"]:
		var index := result.find(marker)
		if index >= 0:
			result = result.substr(index + marker.length()).strip_edges()
	return result


func player_id_for_index(player_ids: Array, index: int) -> String:
	if index < 0 or index >= player_ids.size():
		return ""
	return String(player_ids[index])


func speaker_index_for_history(speaker: String, player_count: int) -> int:
	var marker := speaker.find("号")
	if marker <= 0:
		return -1
	var seat_text := speaker.substr(0, marker).strip_edges()
	if not seat_text.is_valid_int():
		return -1
	var index := int(seat_text.to_int()) - 1
	if index < 0 or index >= player_count:
		return -1
	return index
