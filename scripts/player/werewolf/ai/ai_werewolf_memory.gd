extends RefCounted

const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")

const MAX_TIMELINE_EVENTS := 24

var _role_catalog = RoleCatalogScript.new()


func observation_entry(state: Dictionary, players: Array, viewer_index: int, history: Array) -> Dictionary:
	return _observation_entry_with_events(state, players, viewer_index, _history_descriptions(history, 8), history.size())


func observation_entry_from_timeline_events(state: Dictionary, players: Array, viewer_index: int, timeline_events: Array) -> Dictionary:
	return _observation_entry_with_events(state, players, viewer_index, _timeline_event_descriptions(timeline_events, players, 8), timeline_events.size())


func _observation_entry_with_events(state: Dictionary, players: Array, viewer_index: int, latest_events: Array, timeline_count: int) -> Dictionary:
	var private_lines := []
	var role := _role_label_for_player(players, viewer_index)
	if role != "未知":
		private_lines.append("我的身份：%s" % role)
	var wolves := _known_wolves(players, viewer_index)
	if not wolves.is_empty():
		private_lines.append("我的狼队友：%s" % "、".join(wolves))

	var content_lines := [
		"第%d天，当前阶段：%s。" % [int(state.get("day", 0)), _phase_label(String(state.get("phase", "lobby")))],
		"我的座位：%s。" % _player_label(players, viewer_index),
	]
	if not private_lines.is_empty():
		content_lines.append("；".join(private_lines))
	content_lines.append("存活玩家：%s。" % "、".join(_alive_labels(players)))
	var dead := _dead_labels(players)
	if not dead.is_empty():
		content_lines.append("出局玩家：%s。" % "、".join(dead))
	if not latest_events.is_empty():
		content_lines.append("最近事件：%s" % " / ".join(latest_events))

	return {
		"content": "\n".join(content_lines),
		"visibility": "private" if not private_lines.is_empty() else "public",
		"created_at": Time.get_unix_time_from_system(),
		"metadata": {
			"kind": "visible_context",
			"viewer_index": viewer_index,
			"day_number": int(state.get("day", 0)),
			"phase": String(state.get("phase", "lobby")),
			"timeline_count": timeline_count,
		},
	}


func speech_entry(speaker_index: int, players: Array, text: String) -> Dictionary:
	return {
		"content": "botSpeech=%s：%s" % [_player_label(players, speaker_index), text.strip_edges()],
		"visibility": "public",
		"created_at": Time.get_unix_time_from_system(),
		"metadata": {
			"kind": "bot_speech",
			"speaker_index": speaker_index,
		},
	}


func decision_entry(actor_index: int, target_index: int, action_key: String, players: Array) -> Dictionary:
	return {
		"content": "botDecision=%s 执行 %s，目标 %s。" % [_player_label(players, actor_index), _action_label(action_key), _player_label(players, target_index)],
		"visibility": "private",
		"created_at": Time.get_unix_time_from_system(),
		"metadata": {
			"kind": "bot_decision",
			"actor_index": actor_index,
			"target_index": target_index,
			"action": action_key,
		},
	}


func prompt_memory(memory_context: Dictionary, config_summary: String) -> Dictionary:
	var recent := []
	for item in memory_context.get("recentMemoryEntries", []):
		if item is Dictionary:
			recent.append({
				"content": String(item.get("content", "")),
				"visibility": String(item.get("visibility", "public")),
				"metadata": item.get("metadata", {}),
			})
	var summaries := []
	for item in memory_context.get("roundSummaries", []):
		if item is Dictionary:
			summaries.append({
				"dayNumber": int(item.get("day_number", 0)),
				"phase": String(item.get("phase", "")),
				"publicSummary": String(item.get("public_summary", "")),
				"privateSummary": String(item.get("private_summary", "")),
				"decisionSummary": String(item.get("decision_summary", "")),
				"suspicionSummary": String(item.get("suspicion_summary", "")),
				"strategySummary": String(item.get("strategy_summary", "")),
			})
	var retrieved := []
	for item in memory_context.get("retrievedMemoryEntries", []):
		if item is Dictionary:
			retrieved.append({
				"content": String(item.get("content", "")),
				"source": String(item.get("source", "")),
				"score": float(item.get("score", 0.0)),
				"visibility": String(item.get("visibility", "public")),
				"metadata": item.get("metadata", {}),
			})
	return {
		"configSummary": config_summary.strip_edges(),
		"longTermMemorySummary": String(memory_context.get("longTermMemorySummary", "")),
		"recentMemoryEntries": recent,
		"roundSummaries": summaries,
		"retrievedMemoryEntries": retrieved,
	}


func long_term_summary(state: Dictionary, players: Array, viewer_index: int, history: Array, existing_summary: String = "") -> String:
	var lines := []
	var existing := _trim_text(existing_summary, 360)
	if existing != "":
		lines.append("历史记忆延续：%s" % existing)
	lines.append("本局我作为%s参与狼人杀，结果：%s。" % [_player_role_label(players, viewer_index), _winner_label(String(state.get("winner", "")))])
	var speech_lines := _player_history_lines(history, players, viewer_index, 3)
	if not speech_lines.is_empty():
		lines.append("我的关键发言：%s。" % " / ".join(speech_lines))
	var death_lines := _death_history_lines(history, 3)
	if not death_lines.is_empty():
		lines.append("关键死亡或放逐：%s。" % " / ".join(death_lines))
	lines.append(_strategy_memory_for_role(String(players[viewer_index].get("role_key", "")) if viewer_index >= 0 and viewer_index < players.size() else ""))
	return _trim_text("\n".join(lines), 900)


func compact_request(state: Dictionary, players: Array, history: Array, phase_name: String = "") -> Dictionary:
	var public_events := _history_descriptions(history, 10)
	var decisions := []
	var speeches := []
	for item in history:
		if not (item is Dictionary):
			continue
		var speaker := String(item.get("speaker", ""))
		var text := String(item.get("text", ""))
		if text.contains("选择") or text.contains("投票"):
			decisions.append("%s：%s" % [speaker, text])
		elif speaker != "主持人":
			speeches.append("%s：%s" % [speaker, text])
	return {
		"day_number": int(state.get("day", 0)),
		"phase": phase_name if phase_name != "" else String(state.get("phase", "")),
		"public_summary": _trim_text("公开事件：%s" % " / ".join(public_events), 700),
		"private_summary": "",
		"decision_summary": _trim_text("行动记录：%s" % " / ".join(_tail_strings(decisions, 5)), 700),
		"suspicion_summary": _trim_text(_suspicion_summary(history), 700),
		"strategy_summary": _trim_text("下一次行动继续只根据当前信息、发言和票型判断。", 700),
	}


func _role_label_for_player(players: Array, index: int) -> String:
	if index < 0 or index >= players.size():
		return "未知"
	return String(players[index].get("role", "未知"))


func _player_role_label(players: Array, index: int) -> String:
	return "%s，身份是%s" % [_player_label(players, index), _role_label_for_player(players, index)]


func _known_wolves(players: Array, viewer_index: int) -> Array:
	if viewer_index < 0 or viewer_index >= players.size():
		return []
	if not _role_catalog.can_see_wolf_teammates(String(players[viewer_index].get("role_key", ""))):
		return []
	var wolves := []
	for i in range(players.size()):
		if i == viewer_index:
			continue
		var role_key := String(players[i].get("role_key", ""))
		if String(players[i].get("owner", "")) != "" and _role_catalog.is_wolf_team(role_key) and _role_catalog.visible_to_wolf_teammates(role_key):
			wolves.append(_player_label(players, i))
	return wolves


func _alive_labels(players: Array) -> Array:
	var labels := []
	for i in range(players.size()):
		if String(players[i].get("owner", "")) != "" and bool(players[i].get("alive", true)):
			labels.append(_player_label(players, i))
	return labels


func _dead_labels(players: Array) -> Array:
	var labels := []
	for i in range(players.size()):
		if String(players[i].get("owner", "")) != "" and not bool(players[i].get("alive", true)):
			labels.append(_player_label(players, i))
	return labels


func _history_descriptions(history: Array, limit: int) -> Array:
	var lines := []
	var start: int = maxi(0, history.size() - limit)
	for i in range(start, history.size()):
		var item = history[i]
		if item is Dictionary:
			var text := String(item.get("text", "")).strip_edges()
			if text != "":
				lines.append("%s：%s" % [String(item.get("speaker", "系统")), text])
	return lines


func _timeline_event_descriptions(events: Array, players: Array, limit: int) -> Array:
	var lines := []
	var start: int = maxi(0, events.size() - limit)
	for i in range(start, events.size()):
		var item = events[i]
		if not (item is Dictionary):
			continue
		var event: Dictionary = item
		var text := String(event.get("speechText", event.get("description", ""))).strip_edges()
		if text == "":
			continue
		lines.append("%s：%s" % [_timeline_event_speaker(event, players), text])
	return lines


func _timeline_event_speaker(event: Dictionary, players: Array) -> String:
	var actor_id := String(event.get("actorId", "")).strip_edges()
	if actor_id != "":
		for i in range(players.size()):
			if String((players[i] as Dictionary).get("id", "")).strip_edges() == actor_id:
				return _player_label(players, i)
	if String(event.get("type", "")) == "wolf_spoke":
		return "狼队"
	return "主持人"


func _player_history_lines(history: Array, players: Array, player_index: int, limit: int) -> Array:
	var player_name := String(players[player_index].get("name", "")) if player_index >= 0 and player_index < players.size() else ""
	var seat_prefix := "%d号" % [player_index + 1]
	var lines := []
	for item in history:
		if not (item is Dictionary):
			continue
		var speaker := String(item.get("speaker", ""))
		if speaker.contains(player_name) or speaker.contains(seat_prefix):
			lines.append(String(item.get("text", "")))
	return _tail_strings(lines, limit)


func _death_history_lines(history: Array, limit: int) -> Array:
	var lines := []
	for item in history:
		if not (item is Dictionary):
			continue
		var text := String(item.get("text", ""))
		if text.contains("死亡") or text.contains("放逐") or text.contains("胜利"):
			lines.append(text)
	return _tail_strings(lines, limit)


func _tail_strings(values: Array, limit: int) -> Array:
	var start: int = maxi(0, values.size() - limit)
	var result := []
	for i in range(start, values.size()):
		result.append(String(values[i]))
	return result


func _player_label(players: Array, index: int) -> String:
	if index >= 0 and index < players.size():
		var name := String(players[index].get("name", "")).strip_edges()
		return "%d号位%s" % [index + 1, name] if name != "" else "%d号位" % [index + 1]
	return "未知玩家"


func _phase_label(phase: String) -> String:
	match phase:
		"wolf_chat":
			return "狼队夜聊"
		"wolf_action":
			return "狼人行动"
		"seer_action":
			return "预言家行动"
		"witch_action":
			return "女巫行动"
		"day_discussion":
			return "白天讨论"
		"vote":
			return "投票"
		"game_over":
			return "游戏结束"
		_:
			return "等待"


func _action_label(action_key: String) -> String:
	match action_key:
		"wolf_kill":
			return "刀人"
		"seer_check":
			return "查验"
		"witch_act":
			return "用药"
		"vote":
			return "投票"
		"sheriff_speech_order":
			return "发言顺序"
		_:
			return action_key


func _winner_label(winner: String) -> String:
	match winner:
		"wolf":
			return "狼人胜利"
		"good":
			return "好人胜利"
		_:
			return "已结束"


func _strategy_memory_for_role(role_key: String) -> String:
	if _role_catalog.is_wolf_team(role_key):
		return "经验：狼队下局继续先统一夜晚目标，白天少暴露同阵营联动。"
	match role_key:
		"seer":
			return "经验：预言家下局要把查验转成清晰站边和投票压力。"
		"witch":
			return "经验：女巫下局先核对刀口和发言，再决定救毒节奏。"
		"hunter":
			return "经验：猎人下局要提前点出怀疑位，避免临死才给信息。"
		_:
			return "经验：下局优先观察发言矛盾、死亡信息和票型，不盲目跟强发言。"


func _suspicion_summary(history: Array) -> String:
	for item in history:
		if item is Dictionary and String(item.get("text", "")).contains("投票"):
			return "重点复盘投票关系和被放逐目标。"
	return "公开信息较少，暂不形成强怀疑。"


func _trim_text(value: String, max_chars: int) -> String:
	var normalized := value.strip_edges()
	if normalized.length() <= max_chars:
		return normalized
	return normalized.substr(0, max(0, max_chars - 3)) + "..."
