extends RefCounted

const WerewolfTargetIntentScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_target_intent.gd")

var _target_intent = WerewolfTargetIntentScript.new()


func reset(private_history: Array, speech_keys: Dictionary, target_vote_keys: Dictionary, target_votes: Dictionary) -> void:
	private_history.clear()
	speech_keys.clear()
	target_vote_keys.clear()
	target_votes.clear()


func night_prefix(room_id: String, day: int, kind: String) -> String:
	var clean_room_id := room_id.strip_edges()
	if clean_room_id == "":
		clean_room_id = "local_room"
	return "%s_%d_%s" % [clean_room_id, day, kind]


func speech_key(prefix: String, actor_id: String) -> String:
	return "%s_%s" % [prefix, actor_id]


func target_vote_prefix(room_id: String, day: int) -> String:
	return night_prefix(room_id, day, "wolf_target_vote")


func target_vote_key(prefix: String, actor_id: String) -> String:
	return "%s_%s" % [prefix, actor_id]


func speech_count_for_prefix(speech_keys: Dictionary, prefix: String) -> int:
	var count := 0
	for key in speech_keys.keys():
		if String(key).begins_with(prefix):
			count += 1
	return count


func record_chat(
	private_history: Array,
	speech_keys: Dictionary,
	key: String,
	actor_index: int,
	actor_title: String,
	actor_id: String,
	day: int,
	phase: String,
	speech: String,
	at: float = 0.0
) -> Dictionary:
	if actor_index < 0 or key.strip_edges() == "":
		return {"ok": false}
	if speech_keys.has(key):
		return {"ok": false}
	var content := speech.replace("\r", " ").replace("\n", " ").strip_edges()
	if content == "":
		return {"ok": false}
	if at <= 0.0:
		at = Time.get_unix_time_from_system()
	var entry := {
		"speaker": actor_title,
		"text": content,
		"actor_index": actor_index,
		"actor_id": actor_id,
		"day": day,
		"phase": phase,
		"at": at,
	}
	speech_keys[key] = true
	private_history.append(entry)
	return {"ok": true, "content": content, "entry": entry}


func normalize_target_vote_decision(
	decision: Dictionary,
	actor_index: int,
	latest_intent: Dictionary,
	legal_target: Callable
) -> Dictionary:
	var normalized := {"action": "wolf_kill"}
	var target_index := int(decision.get("target_index", -1))
	if not latest_intent.is_empty():
		var intent_target := int(latest_intent.get("target_index", -1))
		if bool(legal_target.call(actor_index, intent_target)) and target_index != intent_target:
			target_index = intent_target
	if not bool(legal_target.call(actor_index, target_index)):
		target_index = -1
	normalized["target_index"] = target_index
	normalized["target_seat_number"] = target_index + 1 if target_index >= 0 else -1
	return normalized


func record_target_vote(target_vote_keys: Dictionary, target_votes: Dictionary, key: String, normalized: Dictionary) -> Dictionary:
	if key.strip_edges() == "" or target_vote_keys.has(key):
		return {"ok": false}
	var target_index := int(normalized.get("target_index", -1))
	if target_index < 0:
		return {"ok": false}
	var vote := {
		"action": "wolf_kill",
		"target_index": target_index,
		"targetSeatNumber": target_index + 1,
	}
	target_vote_keys[key] = true
	target_votes[key] = vote
	return {"ok": true, "vote": vote}


func resolved_target_index(target_votes: Dictionary, prefix: String, submitter_index: int, legal_target: Callable, first_legal_target: Callable) -> int:
	var counts := {}
	for key in target_votes.keys():
		if not String(key).begins_with(prefix):
			continue
		var vote: Dictionary = target_votes[key]
		var target_index := int(vote.get("target_index", -1))
		if not bool(legal_target.call(submitter_index, target_index)):
			continue
		counts[str(target_index)] = int(counts.get(str(target_index), 0)) + 1
	if counts.is_empty():
		return -1
	var best_index := -1
	var best_count := -1
	for key in counts.keys():
		var target_index := int(String(key).to_int())
		var count := int(counts[key])
		if count > best_count or (count == best_count and (best_index < 0 or target_index < best_index)):
			best_index = target_index
			best_count = count
	return best_index


func latest_target_intent(private_history: Array, day: int, actor_index: int, legal_by_seat: Callable, player_title: Callable) -> Dictionary:
	for i in range(private_history.size() - 1, -1, -1):
		var item = private_history[i]
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		if int(entry.get("day", -1)) != day:
			continue
		var entry_actor := int(entry.get("actor_index", -1))
		if actor_index >= 0 and entry_actor != actor_index:
			continue
		var parsed: Dictionary = _target_intent.infer(String(entry.get("text", "")))
		if parsed.is_empty():
			continue
		var target_index := int(legal_by_seat.call(actor_index, int(parsed.get("seat_number", -1))))
		if target_index < 0:
			continue
		return {
			"actor_index": entry_actor,
			"actor": String(player_title.call(entry_actor)),
			"target_index": target_index,
			"targetSeatNumber": target_index + 1,
			"target": String(player_title.call(target_index)),
			"phrase": String(parsed.get("phrase", "")),
		}
	return {}


func target_intents_debug(private_history: Array, day: int, legal_by_seat: Callable, player_title: Callable) -> Array:
	var result := []
	var seen := {}
	for i in range(private_history.size() - 1, -1, -1):
		var item = private_history[i]
		if not (item is Dictionary):
			continue
		var actor_index := int((item as Dictionary).get("actor_index", -1))
		if actor_index < 0 or seen.has(actor_index):
			continue
		seen[actor_index] = true
		var intent := latest_target_intent(private_history, day, actor_index, legal_by_seat, player_title)
		if not intent.is_empty():
			result.append(intent)
	return result


func target_vote_debug(target_votes: Dictionary, prefix: String, player_title: Callable) -> Array:
	var result := []
	for key in target_votes.keys():
		if not String(key).begins_with(prefix):
			continue
		var vote: Dictionary = target_votes[key]
		var target_index := int(vote.get("target_index", -1))
		result.append({
			"action": String(vote.get("action", "wolf_kill")),
			"targetSeatNumber": int(vote.get("targetSeatNumber", target_index + 1)),
			"target": String(player_title.call(target_index)),
		})
	return result
