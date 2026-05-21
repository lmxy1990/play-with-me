extends RefCounted

const PromptPolicyScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_prompt_policy.gd")
const MemoryContextScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_memory_context.gd")
const TimelineMapperScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_record_formatter.gd")
const WolfPrivateFlowScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_wolf_private_flow.gd")
const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")
const WinConditionsScript := preload("res://scripts/room/werewolf/werewolf_win_conditions.gd")

const MAX_WOLF_NIGHT_CHAT_MESSAGES := 3

var _memory_context = MemoryContextScript.new()
var _timeline_mapper = TimelineMapperScript.new()
var _wolf_private_flow = WolfPrivateFlowScript.new()
var _role_catalog = RoleCatalogScript.new()
var _win_conditions = WinConditionsScript.new()


func action_context(input: Dictionary, actor_index: int, action_key: String, memory_payload: Dictionary = {}) -> Dictionary:
	return turn_context(
		input,
		actor_index,
		model_allowed_actions(input, actor_index, action_key),
		action_instruction_for_actor(input, actor_index, action_key),
		sequence_kind_for_action(action_key),
		memory_payload
	)


func speech_context(input: Dictionary, speaker_index: int, memory_payload: Dictionary = {}) -> Dictionary:
	var action := speech_action_for_phase(input)
	return turn_context(
		input,
		speaker_index,
		[action],
		speech_instruction_for_phase(input, action),
		sequence_kind_for_speech(input, action),
		memory_payload
	)


func wolf_chat_context(input: Dictionary, actor_index: int, memory_payload: Dictionary = {}) -> Dictionary:
	return turn_context(
		input,
		actor_index,
		["wolf_chat"],
		wolf_chat_instruction(),
		"wolf_night_chat",
		memory_payload
	)


func turn_context(input: Dictionary, player_index: int, allowed_actions: Array, current_question: String, sequence_kind: String, memory_payload: Dictionary = {}) -> Dictionary:
	var context_budget := context_budget_from_memory(memory_payload)
	return {
		"bot_id": player_id_for_index(input, player_index),
		"visible_state": visible_state(input, player_index, memory_payload),
		"allowed_actions": allowed_actions,
		"memory_hints": memory_hints(memory_payload),
		"turn_metadata": turn_metadata(input, sequence_kind, player_index, context_budget),
		"memory": memory_payload,
		"current_question": current_question,
	}


func memory_hints(memory_payload: Dictionary) -> Dictionary:
	if not bool(PromptPolicyScript.include_memory_hints):
		return {}
	var result := {}
	var budget_state := {"remaining": _memory_hint_token_budget(memory_payload)}
	var retrieved := _fit_memory_texts_to_budget(_memory_context.retrieved_entry_texts(memory_payload), budget_state)
	if not retrieved.is_empty():
		result["relevantMemory"] = retrieved
	var round_summaries := _fit_memory_texts_to_budget(_memory_context.round_summary_texts(memory_payload), budget_state)
	if not round_summaries.is_empty():
		result["roundSummaries"] = round_summaries
	var long_term := _fit_memory_text_to_budget(String(memory_payload.get("longTermMemorySummary", "")).strip_edges(), budget_state)
	if long_term != "":
		result["longTermSummary"] = long_term
	return result


func _memory_hint_token_budget(memory_payload: Dictionary) -> int:
	return maxi(1, int(memory_payload.get("memoryContextBudgetTokens", memory_payload.get("contextBudgetTokens", 1024))))


func _fit_memory_texts_to_budget(texts: Array, budget_state: Dictionary) -> Array:
	var result := []
	for value in texts:
		var text := _fit_memory_text_to_budget(String(value), budget_state)
		if text != "":
			result.append(text)
		if int(budget_state.get("remaining", 0)) <= 0:
			break
	return result


func _fit_memory_text_to_budget(value: String, budget_state: Dictionary) -> String:
	var remaining := int(budget_state.get("remaining", 0))
	if remaining <= 0:
		return ""
	var text := value.strip_edges()
	if text == "":
		return ""
	var estimated := _estimate_memory_tokens(text)
	if estimated <= remaining:
		budget_state["remaining"] = remaining - estimated
		return text
	var trimmed := text.substr(0, remaining).strip_edges()
	budget_state["remaining"] = maxi(0, remaining - _estimate_memory_tokens(trimmed))
	return trimmed


func _estimate_memory_tokens(text: String) -> int:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return 0
	return trimmed.length()


func visible_state(input: Dictionary, viewer_index: int, memory_payload: Dictionary = {}) -> Dictionary:
	var werewolf := _werewolf(input)
	var context_budget := context_budget_from_memory(memory_payload)
	var timeline_limit := timeline_limit_for_context_budget(context_budget)
	var visible_count := visible_timeline_event_count(input, viewer_index)
	var timeline := visible_timeline_events(input, timeline_limit, viewer_index)
	var compression := timeline_compression_config(input)
	var timeline_compressed_count := 0
	var timeline_dropped_count := 0
	if bool(compression.get("enabled", false)):
		var full_timeline := visible_timeline_events(input, visible_count, viewer_index)
		var compression_result := _compressed_timeline_events(input, full_timeline, timeline_limit, compression)
		timeline = compression_result.get("events", timeline)
		timeline_compressed_count = int(compression_result.get("compressed_count", 0))
		timeline_dropped_count = int(compression_result.get("dropped_count", 0))
	var state := {
		"phase": String(werewolf.get("phase", "")),
		"phaseLabel": phase_label(input),
		"dayNumber": int(werewolf.get("day", 0)),
		"myRole": player_role_key(input, viewer_index),
		"facts": state_facts(input, viewer_index),
		"ruleSummary": map_rule_summary(input),
		"scriptSummary": script_prompt_context(input),
		"viewer": player_id_for_index(input, viewer_index),
		"players": visible_players(input, viewer_index),
		"timeline": timeline,
		"privateInfo": private_info(input, viewer_index),
	}
	var known_wolves := known_wolf_ids(input, viewer_index)
	if not known_wolves.is_empty():
		state["knownWolfIds"] = known_wolves
	if timeline_compressed_count > 0:
		state["timelineCompressedCount"] = timeline_compressed_count
		if timeline_dropped_count > 0:
			state["timelineTruncatedCount"] = timeline_dropped_count
	elif visible_count > timeline_limit:
		state["timelineTruncatedCount"] = visible_count - timeline_limit
	return state


func visible_players(input: Dictionary, viewer_index: int) -> Array:
	var result := []
	var counts := visible_vote_counts(input)
	var werewolf := _werewolf(input)
	var night: Dictionary = werewolf.get("night", {})
	var wolf_target := int(night.get("wolf_target_index", -1))
	var players := _players(input)
	for i in range(players.size()):
		var player: Dictionary = players[i]
		if String(player.get("owner", "")) == "":
			continue
		var id := player_id_for_index(input, i)
		var visible := {
			"playerId": id,
			"seatNumber": i + 1,
			"displayName": String(player.get("name", "")),
			"alive": bool(player.get("alive", true)),
			"state": String(player.get("state", "")),
		}
		if counts.has(id):
			visible["voteCount"] = int(counts[id])
		if i == wolf_target and can_view_night_target(input, viewer_index):
			visible["nightTargeted"] = true
		var role_key := visible_role_key(input, viewer_index, i)
		if role_key != "":
			visible["revealedRole"] = role_key
		result.append(visible)
	return result


func state_facts(input: Dictionary, viewer_index: int) -> Array:
	var facts := []
	var werewolf := _werewolf(input)
	var phase := String(werewolf.get("phase", ""))
	var day := int(werewolf.get("day", 0))
	if day <= 1 and phase in ["sheriff_speech", "sheriff_vote"]:
		facts.append("本局尚未进入首夜，所有玩家都还没有夜间技能结果。")
	var role_key := player_role_key(input, viewer_index)
	match role_key:
		"seer":
			var checks := _seer_check_summaries(input, viewer_index)
			if checks.is_empty():
				facts.append("你目前没有查验结果。")
			else:
				facts.append("你已知查验结果：%s。" % "；".join(checks))
		"guard":
			var last_guarded := int(werewolf.get("last_guarded_index", -1))
			if last_guarded < 0:
				facts.append("你没有上一夜守护记录。")
		"witch":
			var night: Dictionary = werewolf.get("night", {})
			if int(night.get("wolf_target_index", -1)) < 0:
				facts.append("你当前没有可见的夜间被刀信息。")
	return facts


func model_allowed_actions(input: Dictionary, actor_index: int, action_key: String) -> Array:
	match action_key:
		"witch_act":
			return ["witch_act"]
		"hunter_shoot":
			return ["hunter_shoot"]
		"sheriff_speech_order":
			return ["sheriff_speech_order"]
		"sheriff_badge_action":
			return ["sheriff_badge_action"]
		_:
			return [model_action_key(action_key)]


func is_legal_model_target(input: Dictionary, actor_index: int, target_index: int, action_key: String) -> bool:
	var players := _players(input)
	if target_index < 0 or target_index >= players.size():
		return false
	var player: Dictionary = players[target_index]
	if String(player.get("owner", "")) == "":
		return false
	if action_key == "mvp_vote":
		return true
	if not bool(player.get("alive", true)):
		return false
	match action_key:
		"guard_protect":
			return target_index != int(_werewolf(input).get("last_guarded_index", -1))
		"sheriff_vote":
			return true
		"sheriff_speech_order":
			return true
		"sheriff_badge_action":
			return target_index != actor_index
		"witch_act":
			var night: Dictionary = _werewolf(input).get("night", {})
			var wolf_target := int(night.get("wolf_target_index", -1))
			if target_index == wolf_target and bool(_werewolf(input).get("witch_antidote", true)):
				return true
			return target_index != actor_index and bool(_werewolf(input).get("witch_poison", true))
		"wolf_kill":
			return is_legal_wolf_target(input, actor_index, target_index)
		_:
			return target_index != actor_index


func legal_wolf_target_by_seat(input: Dictionary, actor_index: int, seat_number: int) -> int:
	var target_index := seat_number - 1
	return target_index if is_legal_wolf_target(input, actor_index, target_index) else -1


func is_legal_wolf_target(input: Dictionary, actor_index: int, target_index: int) -> bool:
	var players := _players(input)
	if target_index < 0 or target_index >= players.size():
		return false
	var player: Dictionary = players[target_index]
	if String(player.get("owner", "")) == "" or not bool(player.get("alive", true)):
		return false
	return target_index != actor_index and _role_catalog.can_be_wolf_kill_target(String(player.get("role_key", "")))


func first_legal_wolf_target(input: Dictionary, actor_index: int) -> int:
	var players := _players(input)
	for i in range(players.size()):
		if is_legal_wolf_target(input, actor_index, i):
			return i
	return -1


func latest_wolf_target_intent(input: Dictionary, actor_index: int = -1) -> Dictionary:
	var werewolf := _werewolf(input)
	var private_history := _array(input.get("wolf_private_history", []))
	for i in range(private_history.size() - 1, -1, -1):
		var item = private_history[i]
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		if int(entry.get("day", -1)) != int(werewolf.get("day", 0)):
			continue
		var entry_actor := int(entry.get("actor_index", -1))
		if actor_index >= 0 and entry_actor != actor_index:
			continue
		var target := _wolf_private_flow.latest_target_intent(
			[entry],
			int(werewolf.get("day", 0)),
			entry_actor,
			func(check_actor: int, seat_number: int) -> int: return legal_wolf_target_by_seat(input, check_actor, seat_number),
			func(index: int) -> String: return player_title(input, index)
		)
		if not target.is_empty():
			return target
	return {}


func wolf_target_intents_debug(input: Dictionary) -> Array:
	return _wolf_private_flow.target_intents_debug(
		_array(input.get("wolf_private_history", [])),
		int(_werewolf(input).get("day", 0)),
		func(actor_index: int, seat_number: int) -> int: return legal_wolf_target_by_seat(input, actor_index, seat_number),
		func(index: int) -> String: return player_title(input, index)
	)


func wolf_target_vote_debug(input: Dictionary) -> Array:
	return _wolf_private_flow.target_vote_debug(
		_dict(input.get("wolf_target_votes", {})),
		wolf_target_vote_prefix(input),
		func(index: int) -> String: return player_title(input, index)
	)


func normalized_wolf_target_vote(input: Dictionary, actor_index: int, decision: Dictionary) -> Dictionary:
	return _wolf_private_flow.normalize_target_vote_decision(
		decision,
		actor_index,
		latest_wolf_target_intent(input, actor_index),
		func(check_actor: int, target_index: int) -> bool: return is_legal_wolf_target(input, check_actor, target_index)
	)


func resolved_wolf_target_index(input: Dictionary, submitter_index: int) -> int:
	return _wolf_private_flow.resolved_target_index(
		_dict(input.get("wolf_target_votes", {})),
		wolf_target_vote_prefix(input),
		submitter_index,
		func(actor_index: int, target_index: int) -> bool: return is_legal_wolf_target(input, actor_index, target_index),
		func(actor_index: int) -> int: return first_legal_wolf_target(input, actor_index)
	)


func wolf_target_vote_prefix(input: Dictionary) -> String:
	return _wolf_private_flow.target_vote_prefix(room_id(input), int(_werewolf(input).get("day", 0)))


func visible_timeline_events(input: Dictionary, limit: int, viewer_index: int) -> Array:
	return _timeline_mapper.recent_visible_events(
		_array(input.get("history", [])),
		_array(input.get("wolf_private_history", [])),
		limit,
		player_ids(input),
		String(_werewolf(input).get("phase", "")),
		viewer_index,
		can_view_wolf_private_history(input, viewer_index)
	)


func timeline_compression_config(input: Dictionary) -> Dictionary:
	var raw := _dict(input.get("timeline_compression", {}))
	var enabled := bool(raw.get("enabled", raw.get("timeline_compression_enabled", false)))
	var interval := maxi(1, int(raw.get("interval", raw.get("timeline_compression_interval", AppState.DEFAULT_TIMELINE_COMPRESSION_INTERVAL))))
	var prompt := String(raw.get("prompt", raw.get("timeline_compression_prompt", AppState.DEFAULT_TIMELINE_COMPRESSION_PROMPT))).strip_edges()
	return {
		"enabled": enabled,
		"model": String(raw.get("model", raw.get("timeline_compression_model", ""))).strip_edges(),
		"interval": interval,
		"prompt": prompt if prompt != "" else AppState.DEFAULT_TIMELINE_COMPRESSION_PROMPT,
	}


func _compressed_timeline_events(input: Dictionary, events: Array, limit: int, compression: Dictionary) -> Dictionary:
	var result := {"events": events, "compressed_count": 0, "dropped_count": 0}
	if events.is_empty() or limit <= 0:
		return result
	var interval := maxi(1, int(compression.get("interval", AppState.DEFAULT_TIMELINE_COMPRESSION_INTERVAL)))
	var recent_count := mini(events.size(), mini(interval, limit))
	if events.size() <= recent_count:
		return result
	var split_index := events.size() - recent_count
	var combined: Array = []
	var chunk: Array = []
	for i in range(split_index):
		if events[i] is Dictionary:
			chunk.append(events[i])
		if chunk.size() >= interval:
			combined.append(_timeline_summary_event(input, chunk))
			chunk.clear()
	if not chunk.is_empty():
		combined.append(_timeline_summary_event(input, chunk))
	for i in range(split_index, events.size()):
		combined.append(events[i])
	var dropped := 0
	if combined.size() > limit:
		dropped = combined.size() - limit
		var trimmed: Array = []
		for i in range(dropped, combined.size()):
			trimmed.append(combined[i])
		combined = trimmed
	result["events"] = combined
	result["compressed_count"] = split_index
	result["dropped_count"] = dropped
	return result


func _timeline_summary_event(input: Dictionary, events: Array) -> Dictionary:
	var parts := []
	for item in events:
		if not (item is Dictionary):
			continue
		var event: Dictionary = item
		var description := String(event.get("speechText", event.get("description", ""))).strip_edges()
		if description == "":
			continue
		parts.append("%s:%s" % [_timeline_event_speaker_label(input, event), _timeline_brief_text(description, 42)])
		if parts.size() >= 12:
			break
	var text := "事实摘要：%s" % "；".join(parts)
	if events.size() > parts.size():
		text = "%s；另%d条记录。" % [text, events.size() - parts.size()]
	if parts.is_empty():
		text = "事实摘要：%d条历史记录。" % events.size()
	var first_event: Dictionary = events.front() as Dictionary
	var last_event: Dictionary = events.back() as Dictionary
	return {
		"type": "timeline_summary",
		"eventKind": "summary",
		"description": text,
		"occurredAt": "%s-%s" % [str(first_event.get("occurredAt", "")), str(last_event.get("occurredAt", ""))],
		"_sortAt": float(last_event.get("_sortAt", 0.0)),
	}


func _timeline_event_speaker_label(input: Dictionary, event: Dictionary) -> String:
	var actor_id := String(event.get("actorId", "")).strip_edges()
	if actor_id != "":
		for i in range(_players(input).size()):
			if player_id_for_index(input, i) == actor_id:
				return "%d号" % [i + 1]
	if String(event.get("type", "")) == "wolf_spoke":
		return "狼队"
	return "主持人"


func _timeline_brief_text(text: String, max_chars: int) -> String:
	var clean := text.replace("\r", " ").replace("\n", " ").strip_edges()
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.length() <= max_chars:
		return clean
	return "%s..." % clean.substr(0, maxi(1, max_chars - 3)).strip_edges()


func visible_timeline_event_count(input: Dictionary, viewer_index: int) -> int:
	return _timeline_mapper.visible_timeline_event_count(
		_array(input.get("history", [])),
		_array(input.get("wolf_private_history", [])),
		player_ids(input),
		viewer_index,
		can_view_wolf_private_history(input, viewer_index)
	)


func recent_text_timeline(input: Dictionary, limit: int) -> Array:
	return _timeline_mapper.recent_text_timeline(_array(input.get("history", [])), limit)


func recent_public_events(input: Dictionary, limit: int) -> Array:
	return _timeline_mapper.recent_public_events(_array(input.get("history", [])), limit, player_ids(input), String(_werewolf(input).get("phase", "")))


func memory_retrieval_query(input: Dictionary, player_index: int, context_budget: int = 8192) -> String:
	return _memory_context.retrieval_query(
		_werewolf(input),
		player_title(input, player_index),
		role_label_for_memory(input, player_index),
		phase_label(input),
		private_info(input, player_index),
		visible_timeline_events(input, prior_event_limit_for_context_budget(context_budget), player_index),
		context_budget
	)


func memory_players_payload(input: Dictionary) -> Array:
	var result := []
	var players := _players(input)
	for i in range(players.size()):
		var player: Dictionary = players[i]
		if String(player.get("owner", "")) == "":
			continue
		result.append({
			"seatNumber": i + 1,
			"label": player_title(input, i),
			"alive": bool(player.get("alive", true)),
			"role": role_label_for_memory(input, i),
		})
	return result


func memory_final_timeline_payload(input: Dictionary, viewer_index: int, context_budget: int = 8192) -> Array:
	var timeline := []
	for item in visible_timeline_events(input, summary_timeline_limit_for_context_budget(context_budget), viewer_index):
		if not (item is Dictionary):
			continue
		var event: Dictionary = (item as Dictionary).duplicate(true)
		event.erase("_sortAt")
		timeline.append(event)
	return timeline


func role_label_for_memory(input: Dictionary, player_index: int) -> String:
	var players := _players(input)
	if player_index < 0 or player_index >= players.size():
		return "未知"
	var role_key := String(players[player_index].get("role_key", "")).strip_edges()
	if role_key != "" and _role_catalog.role_enum_from_key(role_key) >= 0:
		return _role_catalog.role_label(role_key)
	var role := String(players[player_index].get("role", "")).strip_edges()
	return role if role != "" else "未知"


func target_from_decision(runtime, content: String, input: Dictionary, actor_index: int, action_key: String) -> int:
	var context := action_context(input, actor_index, action_key, {})
	var decision: Dictionary = runtime.parse_decision(content, context)
	if not bool(decision.get("ok", false)):
		return -1
	var target_index := int(decision.get("target_index", -1))
	if not is_legal_model_target(input, actor_index, target_index, action_key):
		return -1
	return target_index


func context_budget_from_memory(memory_payload: Dictionary) -> int:
	return maxi(1, int(memory_payload.get("contextBudgetTokens", 8192)))


func timeline_limit_for_context_budget(context_budget: int) -> int:
	if context_budget < 4096:
		return 8
	if context_budget < 8192:
		return 12
	if context_budget < 32768:
		return 24
	if context_budget < 131072:
		return 40
	return 64


func prior_event_limit_for_context_budget(context_budget: int) -> int:
	return maxi(4, mini(16, int(ceil(float(timeline_limit_for_context_budget(context_budget)) / 4.0))))


func summary_timeline_limit_for_context_budget(context_budget: int) -> int:
	if context_budget < 4096:
		return 16
	if context_budget < 8192:
		return 24
	if context_budget < 32768:
		return 48
	if context_budget < 131072:
		return 64
	return 96


func model_action_key(action_key: String) -> String:
	match action_key:
		"wolf_kill":
			return "wolf_kill"
		"guard_protect":
			return "guard_protect"
		"seer_check":
			return "seer_check"
		"witch_act":
			return "witch_act"
		"sheriff_vote":
			return "sheriff_vote"
		"sheriff_speech_order":
			return "sheriff_speech_order"
		"sheriff_badge_action":
			return "sheriff_badge_action"
		"vote":
			return "vote"
		"hunter_shoot":
			return "hunter_shoot"
		"mvp_vote":
			return "mvp_vote"
		_:
			return action_key


func action_instruction(action_key: String) -> String:
	match action_key:
		"wolf_kill":
			return "选择今晚狼队击杀目标。"
		"guard_protect":
			return "选择今晚守护目标。"
		"seer_check":
			return "选择今晚查验目标。"
		"witch_act":
			return "选择救人、毒人或跳过。"
		"sheriff_vote":
			return "选择警长投票目标。"
		"sheriff_speech_order":
			return "指定白天发言起点和方向。"
		"sheriff_badge_action":
			return "选择飞警徽或撕警徽。"
		"vote":
			return "选择白天放逐投票目标。"
		"hunter_shoot":
			return "请猎人选择开枪目标或不开枪。"
		"mvp_vote":
			return "选择赛后 MVP。"
		_:
			return "选择目标玩家。"


func wolf_chat_instruction() -> String:
	return "发表狼队夜聊。"


func action_instruction_for_actor(input: Dictionary, actor_index: int, action_key: String) -> String:
	return action_instruction(action_key)


func speech_action_for_phase(input: Dictionary) -> String:
	var phase_key := String(_werewolf(input).get("phase", ""))
	if phase_key == "last_words":
		return "last_words"
	if phase_key == "post_game_summary":
		return "post_game_summary"
	return "speak"


func speech_instruction_for_phase(input: Dictionary, action: String) -> String:
	match action:
		"last_words":
			return "发表遗言。"
		"post_game_summary":
			return "发表赛后总结。"
		_:
			if String(_werewolf(input).get("phase", "")) == "sheriff_speech":
				return "发表警长竞选发言。"
			return "发表白天讨论发言。"


func _question(parts: Array) -> String:
	var result := []
	for part in parts:
		var text := String(part).strip_edges()
		if text != "":
			result.append(text)
	return " ".join(result)


func sequence_kind_for_action(action_key: String) -> String:
	match action_key:
		"wolf_kill":
			return "wolf_target_vote"
		"guard_protect":
			return "guard_action"
		"seer_check":
			return "seer_action"
		"witch_act":
			return "witch_action"
		"sheriff_vote":
			return "sheriff_vote"
		"sheriff_speech_order":
			return "sheriff_speech_order"
		"sheriff_badge_action":
			return "sheriff_badge_action"
		"vote":
			return "vote"
		"hunter_shoot":
			return "hunter_shoot"
		"mvp_vote":
			return "mvp_vote"
		_:
			return action_key


func sequence_kind_for_speech(input: Dictionary, action: String) -> String:
	match action:
		"last_words":
			return "last_words"
		"post_game_summary":
			return "post_game_summary"
		_:
			return "sheriff_campaign_speech" if String(_werewolf(input).get("phase", "")) == "sheriff_speech" else "discussion_speech"


func turn_metadata(input: Dictionary, sequence_kind: String, viewer_index: int, context_budget: int = 8192) -> Dictionary:
	var metadata := {
		"sequenceKind": sequence_kind,
		"sequenceIndex": visible_timeline_event_count(input, viewer_index),
	}
	var vote_counts := visible_vote_counts(input)
	if not vote_counts.is_empty():
		metadata["voteCounts"] = vote_counts
	if String(_werewolf(input).get("phase", "")) in ["wolf_chat", "wolf_action"]:
		metadata["wolfNightChat"] = {
			"maxMessages": int(input.get("max_wolf_night_chat_messages", MAX_WOLF_NIGHT_CHAT_MESSAGES)),
			"sentMessagesByThisDevice": int(input.get("wolf_speech_count", 0)),
			"targetVotes": wolf_target_vote_debug(input),
		}
		var own_intent := latest_wolf_target_intent(input, viewer_index)
		if not own_intent.is_empty():
			metadata["ownWolfTargetIntent"] = own_intent
		var team_intents := wolf_target_intents_debug(input)
		if not team_intents.is_empty():
			metadata["teamWolfTargetIntents"] = team_intents
	return metadata


func visible_role_key(input: Dictionary, viewer_index: int, target_index: int) -> String:
	var players := _players(input)
	if target_index < 0 or target_index >= players.size():
		return ""
	var player: Dictionary = players[target_index]
	if String(player.get("owner", "")) == "":
		return ""
	if target_index == viewer_index or is_post_game_phase(input) or is_role_publicly_revealed(player):
		return String(player.get("role_key", ""))
	return ""


func is_role_publicly_revealed(player: Dictionary) -> bool:
	return bool(player.get("role_visible", false)) \
		or bool(player.get("roleVisible", false)) \
		or bool(player.get("idiot_revealed", false))


func known_wolf_ids(input: Dictionary, viewer_index: int) -> Array:
	var players := _players(input)
	if viewer_index < 0 or viewer_index >= players.size():
		return []
	if not _role_catalog.can_see_wolf_teammates(String(players[viewer_index].get("role_key", ""))):
		return []
	var ids := []
	for i in range(players.size()):
		var role_key := String(players[i].get("role_key", ""))
		if i != viewer_index and String(players[i].get("owner", "")) != "" and _role_catalog.is_wolf_team(role_key) and _role_catalog.visible_to_wolf_teammates(role_key):
			ids.append(player_id_for_index(input, i))
	return ids


func private_info(input: Dictionary, viewer_index: int) -> Dictionary:
	var info := {}
	var players := _players(input)
	var werewolf := _werewolf(input)
	if viewer_index < 0 or viewer_index >= players.size():
		return info
	var role_key := String(players[viewer_index].get("role_key", ""))
	if role_key == "seer":
		var check_history: Dictionary = werewolf.get("seer_check_history", {})
		var own_checks: Dictionary = check_history.get(str(viewer_index), {})
		var checks := {}
		for target_key in own_checks.keys():
			var target_index := int(String(target_key).to_int())
			var target_id := player_id_for_index(input, target_index)
			if target_id != "":
				checks[target_id] = own_checks[target_key]
		if not checks.is_empty():
			info["checks"] = checks
	if role_key == "guard":
		var last_guarded := int(werewolf.get("last_guarded_index", -1))
		if last_guarded >= 0:
			info["lastGuardedPlayerId"] = player_id_for_index(input, last_guarded)
	if role_key == "witch":
		var night: Dictionary = werewolf.get("night", {})
		var killed := int(night.get("wolf_target_index", -1))
		if killed >= 0:
			info["tonightKilledPlayerId"] = player_id_for_index(input, killed)
		info["antidoteAvailable"] = bool(werewolf.get("witch_antidote", true))
		info["poisonAvailable"] = bool(werewolf.get("witch_poison", true))
	return info


func _seer_check_summaries(input: Dictionary, viewer_index: int) -> Array:
	var result := []
	var werewolf := _werewolf(input)
	var check_history: Dictionary = werewolf.get("seer_check_history", {})
	var own_checks: Dictionary = check_history.get(str(viewer_index), {})
	for target_key in own_checks.keys():
		var target_index := int(String(target_key).to_int())
		var camp := String(own_checks[target_key])
		result.append("%s是%s" % [player_title(input, target_index), camp])
	return result


func can_view_night_target(input: Dictionary, viewer_index: int) -> bool:
	var role_key := player_role_key(input, viewer_index)
	return _role_catalog.can_view_wolf_target(role_key)


func can_view_wolf_private_history(input: Dictionary, viewer_index: int) -> bool:
	var players := _players(input)
	if viewer_index < 0 or viewer_index >= players.size():
		return false
	var player: Dictionary = players[viewer_index]
	return String(player.get("owner", "")) != "" and _role_catalog.can_join_wolf_chat(String(player.get("role_key", "")))


func witch_can_save(input: Dictionary) -> bool:
	var night: Dictionary = _werewolf(input).get("night", {})
	var wolf_target := int(night.get("wolf_target_index", -1))
	return wolf_target >= 0 and bool(_werewolf(input).get("witch_antidote", true))


func witch_can_poison(input: Dictionary, actor_index: int) -> bool:
	if not bool(_werewolf(input).get("witch_poison", true)):
		return false
	var players := _players(input)
	for i in range(players.size()):
		if i != actor_index and String(players[i].get("owner", "")) != "" and bool(players[i].get("alive", true)):
			return true
	return false


func visible_vote_counts(input: Dictionary) -> Dictionary:
	var counts := {}
	var votes: Dictionary = _werewolf(input).get("votes", {})
	var sheriff_index := int(_werewolf(input).get("sheriff_player_index", -1))
	for voter_key in votes.keys():
		var target_index := int(votes[voter_key])
		var target_id := player_id_for_index(input, target_index)
		if target_id == "":
			continue
		var weight := 2 if int(String(voter_key).to_int()) == sheriff_index else 1
		counts[target_id] = int(counts.get(target_id, 0)) + weight
	return counts


func script_prompt_context(input: Dictionary) -> Dictionary:
	var occupied_count := 0
	for player_value in _players(input):
		if String((player_value as Dictionary).get("owner", "")) != "":
			occupied_count += 1
	return {
		"name": String(_werewolf(input).get("map_name", "标准村庄")),
		"playerCount": occupied_count,
		"roleSetup": role_setup_summary(input),
		"winCondition": _win_condition_summary(input, occupied_count),
		"sheriffRule": "开局先进行警长竞选发言，再投票选警长；警长每天白天发言前可指定从某号位开始顺时针或逆时针发言；警长白天放逐投票额外计一票；警长死亡时必须先选择飞警徽给存活玩家或撕警徽，飞警徽后新警长继承票权，撕警徽后本局不再有警长。" if bool(_werewolf(input).get("has_sheriff", false)) else "",
	}


func _win_condition_summary(input: Dictionary, occupied_count: int) -> String:
	var wolf_condition := String(_werewolf(input).get("wolf_win_condition", "")).strip_edges()
	if wolf_condition == "":
		wolf_condition = _win_conditions.default_wolf_condition_key(occupied_count)
	return _win_conditions.condition_summary(wolf_condition)


func role_setup_summary(input: Dictionary) -> String:
	return _role_catalog.role_setup_summary_from_players(_players(input))


func map_rule_summary(input: Dictionary) -> String:
	var map_rule := String(input.get("map_rule_text", "")).strip_edges()
	if map_rule != "":
		return map_rule
	return String(_werewolf(input).get("map_rule_text", "")).strip_edges()


func player_ids(input: Dictionary) -> Array:
	var ids := []
	for i in range(_players(input).size()):
		ids.append(player_id_for_index(input, i))
	return ids


func player_id_for_index(input: Dictionary, index: int) -> String:
	var players := _players(input)
	if index < 0 or index >= players.size():
		return ""
	var player: Dictionary = players[index]
	var id := String(player.get("id", "")).strip_edges()
	return id if id != "" else "seat_%d" % [index + 1]


func player_title(input: Dictionary, index: int) -> String:
	var players := _players(input)
	if index < 0 or index >= players.size():
		return "未知玩家"
	return "%d号 %s" % [index + 1, String(players[index].get("name", "玩家"))]


func player_role_key(input: Dictionary, index: int) -> String:
	var players := _players(input)
	if index < 0 or index >= players.size():
		return ""
	return String(players[index].get("role_key", ""))


func phase_label(input: Dictionary) -> String:
	return String(input.get("phase_label", _werewolf(input).get("phase", "未知阶段")))


func room_id(input: Dictionary) -> String:
	var id := String(input.get("room_id", "")).strip_edges()
	return id if id != "" else "local_room"


func is_post_game_phase(input: Dictionary) -> bool:
	return String(_werewolf(input).get("phase", "")) in ["post_game_summary", "mvp_vote", "completed"]


func _werewolf(input: Dictionary) -> Dictionary:
	return _dict(input.get("werewolf", {}))


func _players(input: Dictionary) -> Array:
	var result := []
	for item in _array(input.get("players", [])):
		if item is Dictionary:
			result.append(item)
	return result


func _array(value) -> Array:
	return value if value is Array else []


func _dict(value) -> Dictionary:
	return value if value is Dictionary else {}
