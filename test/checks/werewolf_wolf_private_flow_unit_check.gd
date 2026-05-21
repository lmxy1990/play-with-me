extends SceneTree

const FlowScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_wolf_private_flow.gd")

var _legal_targets := {}


func _initialize() -> void:
	var flow = FlowScript.new()
	var private_history := []
	var speech_keys := {}
	var target_vote_keys := {}
	var target_votes := {}
	var prefix := flow.night_prefix("room_a", 1, "wolf_speech")
	var key := flow.speech_key(prefix, "wolf_a")
	var chat: Dictionary = flow.record_chat(
		private_history,
		speech_keys,
		key,
		0,
		"1号 甲",
		"wolf_a",
		1,
		"wolf_action",
		"我倾向今晚先刀3号位。\n别拖。",
		10.0
	)
	assert(bool(chat.get("ok", false)))
	assert(int(flow.speech_count_for_prefix(speech_keys, prefix)) == 1)
	assert(not bool(flow.record_chat(private_history, speech_keys, key, 0, "1号 甲", "wolf_a", 1, "wolf_action", "重复", 11.0).get("ok", false)))
	var long_text := "我这轮倾向继续压3号位，因为他白天对警徽流和票型的回应明显绕开重点，还试图把焦点甩给低信息位；如果队友没有更强神职判断，我建议优先确认这个目标。"
	var long_chat: Dictionary = flow.record_chat(
		private_history,
		speech_keys,
		flow.speech_key(prefix, "wolf_b"),
		1,
		"2号 乙",
		"wolf_b",
		1,
		"wolf_action",
		long_text,
		12.0
	)
	assert(bool(long_chat.get("ok", false)))
	assert(String(long_chat.get("content", "")) == long_text)
	assert(String((private_history.back() as Dictionary).get("text", "")) == long_text)
	assert(int(flow.speech_count_for_prefix(speech_keys, prefix)) == 2)
	_legal_targets = {"1": true, "2": true}
	var intent: Dictionary = flow.latest_target_intent(private_history, 1, 0, Callable(self, "_legal_by_seat"), Callable(self, "_player_title"))
	assert(int(intent.get("target_index", -1)) == 2)
	var normalized: Dictionary = flow.normalize_target_vote_decision(
		{"action": "wolf_kill", "target_index": 1},
		0,
		intent,
		Callable(self, "_is_legal_target")
	)
	assert(int(normalized.get("target_index", -1)) == 2)
	var vote_prefix := flow.target_vote_prefix("room_a", 1)
	var vote_a: Dictionary = flow.record_target_vote(target_vote_keys, target_votes, flow.target_vote_key(vote_prefix, "wolf_a"), normalized)
	assert(bool(vote_a.get("ok", false)))
	var vote_b: Dictionary = flow.record_target_vote(target_vote_keys, target_votes, flow.target_vote_key(vote_prefix, "wolf_b"), {"target_index": 1, "target_player_id": "p2"})
	assert(bool(vote_b.get("ok", false)))
	assert(flow.resolved_target_index(target_votes, vote_prefix, 0, Callable(self, "_is_legal_target"), Callable(self, "_first_legal_target")) == 1)
	assert((flow.target_vote_debug(target_votes, vote_prefix, Callable(self, "_player_title")) as Array).size() == 2)
	flow.reset(private_history, speech_keys, target_vote_keys, target_votes)
	assert(private_history.is_empty())
	assert(speech_keys.is_empty())
	assert(target_vote_keys.is_empty())
	assert(target_votes.is_empty())
	quit()


func _is_legal_target(_actor_index: int, target_index: int) -> bool:
	return bool(_legal_targets.get(str(target_index), false))


func _first_legal_target(_actor_index: int) -> int:
	return 1


func _legal_by_seat(_actor_index: int, seat_number: int) -> int:
	var index := seat_number - 1
	return index if _is_legal_target(_actor_index, index) else -1


func _player_title(index: int) -> String:
	return "%d号 玩家" % [index + 1] if index >= 0 else "系统"
