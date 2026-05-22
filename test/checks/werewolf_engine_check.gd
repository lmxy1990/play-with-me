extends SceneTree


func _initialize() -> void:
	var engine = load("res://scripts/room/werewolf/werewolf_engine.gd").new()
	_check_basic_day_vote_flow(engine)
	_check_sheriff_guard_flow(engine)
	_check_sheriff_speech_order(engine)
	_check_sheriff_badge_action(engine)
	_check_multi_wolf_target_vote(engine)
	_check_witch_auto_skip_and_action_rules(engine)
	_check_dead_player_post_game_summary(engine)
	_check_post_game_summary_to_mvp_completion(engine)
	_check_win_conditions(engine)
	_check_wolf_attack_only_records_target_before_night_resolution(engine)
	_check_attacked_seer_can_still_act_before_night_resolution(engine)
	_check_night_attack_on_hunter_uses_night_end_death_flow(engine)
	_check_vote_exiled_hunter_shoots_before_exile_settlement(engine)
	_check_vote_exiled_hunter_can_skip_before_exile_settlement(engine)
	_check_idiot_reveal_vote_flow(engine)
	quit()


func _check_basic_day_vote_flow(engine) -> void:
	var players := _players(6)
	var result: Dictionary = engine.start_game("basic_check", players, [0, 1, 2, 3, 4, 5], 0)
	assert(bool(result.get("ok", false)))
	var state: Dictionary = result["werewolf"]
	players = result["players"]
	assert(bool(state.get("started", false)))
	assert(String(state.get("phase", "")) == "wolf_chat")
	for player in players:
		if player is Dictionary and String((player as Dictionary).get("owner", "")) != "":
			assert(String((player as Dictionary).get("role_key", "")) != "")
			assert(String((player as Dictionary).get("role", "")) != "未知")
			assert(String((player as Dictionary).get("role_title", "")) != "")
			assert(String((player as Dictionary).get("role_avatar", "")).begins_with("res://assets/images/werewolf/avatars/roles/"))
			assert(String((player as Dictionary).get("avatar", "")) == String((player as Dictionary).get("base_avatar", "")))

	var guard := 0
	while engine.is_night_phase(state) and guard < 8:
		guard += 1
		var step: Dictionary = _advance_night_prompt(engine, state, players)
		state = step["werewolf"]
		players = step["players"]
	assert(guard > 0)
	assert(String(state.get("phase", "")) in ["day_discussion", "last_words", "hunter_action", "game_over"])

	while String(state.get("phase", "")) == "last_words":
		var last_words: Dictionary = engine.submit_speech(state, players, "测试遗言", 0)
		assert(bool(last_words.get("ok", false)))
		state = last_words["werewolf"]
		players = last_words["players"]

	if String(state.get("phase", "")) == "hunter_action":
		var hunter_step: Dictionary = _apply_prompt_target(engine, state, players)
		state = hunter_step["werewolf"]
		players = hunter_step["players"]

	while String(state.get("phase", "")) == "last_words":
		var hunter_last_words: Dictionary = engine.submit_speech(state, players, "猎人后续遗言", 0)
		assert(bool(hunter_last_words.get("ok", false)))
		state = hunter_last_words["werewolf"]
		players = hunter_last_words["players"]

	if String(state.get("phase", "")) == "game_over":
		return

	assert(String(state.get("phase", "")) == "day_discussion")
	while String(state.get("phase", "")) == "day_discussion":
		var speech: Dictionary = engine.submit_speech(state, players, "测试发言", 0)
		assert(bool(speech.get("ok", false)))
		state = speech["werewolf"]
		players = speech["players"]
	assert(String(state.get("phase", "")) == "vote")

	var alive_before_vote := _alive_count(players)
	var votes_cast := 0
	while String(state.get("phase", "")) == "vote":
		var vote_step: Dictionary = _apply_prompt_target(engine, state, players)
		assert(bool(vote_step.get("ok", false)))
		votes_cast += 1
		state = vote_step["werewolf"]
		players = vote_step["players"]
		if votes_cast < alive_before_vote:
			assert(String(state.get("phase", "")) == "vote")
	assert(votes_cast == alive_before_vote)


func _check_sheriff_guard_flow(engine) -> void:
	var players := _players(12)
	var result: Dictionary = engine.start_game("sheriff_guard_check", players, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], 0, "sheriff_guard_square")
	assert(bool(result.get("ok", false)))
	var state: Dictionary = result["werewolf"]
	players = result["players"]
	assert(String(state.get("phase", "")) == "sheriff_speech")
	assert(bool(state.get("has_sheriff", false)))

	while String(state.get("phase", "")) == "sheriff_speech":
		var speech: Dictionary = engine.submit_speech(state, players, "竞选测试", 0)
		assert(bool(speech.get("ok", false)))
		state = speech["werewolf"]
		players = speech["players"]
	assert(String(state.get("phase", "")) == "sheriff_vote")

	var votes_cast := 0
	while String(state.get("phase", "")) == "sheriff_vote":
		if votes_cast == 0:
			var self_vote: Dictionary = engine.apply_target(state, players, 0, 0)
			assert(bool(self_vote.get("ok", false)))
			state = self_vote["werewolf"]
			players = self_vote["players"]
			votes_cast += 1
			continue
		var sheriff_vote: Dictionary = _apply_prompt_target(engine, state, players)
		assert(bool(sheriff_vote.get("ok", false)))
		state = sheriff_vote["werewolf"]
		players = sheriff_vote["players"]
		votes_cast += 1
	assert(int(state.get("sheriff_player_index", -1)) >= 0)
	assert(String(state.get("phase", "")) == "wolf_chat")

	var saw_guard := false
	var guard_actor := -1
	var guard_target := -1
	var night_steps := 0
	while engine.is_night_phase(state) and night_steps < 16:
		night_steps += 1
		var action: Dictionary = state.get("current_action", {})
		if String(action.get("key", "")) == "guard_protect":
			saw_guard = true
			guard_actor = int(action.get("actor_index", -1))
			guard_target = int(engine.suggested_target_for_current_action(state, players))
		var step: Dictionary = _advance_night_prompt(engine, state, players)
		assert(bool(step.get("ok", false)))
		state = step["werewolf"]
		players = step["players"]
	assert(saw_guard)
	assert(int(state.get("last_guarded_index", -1)) == guard_target)

	var repeat_state: Dictionary = state.duplicate(true)
	repeat_state["phase"] = "guard_action"
	repeat_state["current_action"] = {
		"key": "guard_protect",
		"label": "守护",
		"icon": "",
		"effect": "guard",
		"actor_index": guard_actor,
	}
	var repeat: Dictionary = engine.apply_target(repeat_state, players, guard_target, 0)
	assert(not bool(repeat.get("ok", false)))


func _check_multi_wolf_target_vote(engine) -> void:
	var players := [
		_role_player("wolf", true),
		_role_player("wolf", true),
		_role_player("villager", true),
		_role_player("villager", true),
		_role_player("guard", true),
	]
	players[0]["name"] = "狼A"
	players[1]["name"] = "狼B"
	players[2]["name"] = "村A"
	players[3]["name"] = "村B"
	players[4]["name"] = "守卫"
	var state := {
		"phase": "wolf_action",
		"day": 1,
		"votes": {},
		"night": {"day": 1, "wolf_target_index": -1},
		"current_action": {"key": "wolf_kill", "actor_index": 0, "label": "投刀", "effect": "vote"},
		"spoken_indices": [],
		"last_guarded_index": -1,
		"witch_antidote": true,
		"witch_poison": true,
		"sheriff_player_index": -1,
		"post_game": {"stage": ""},
	}
	var first: Dictionary = engine.apply_target(state, players, 2, 0)
	assert(bool(first.get("ok", false)))
	state = first["werewolf"]
	players = first["players"]
	assert(String(state.get("phase", "")) == "wolf_action")
	assert(int((state.get("votes", {}) as Dictionary).get("0", -1)) == 2)
	assert(int((state.get("current_action", {}) as Dictionary).get("actor_index", -1)) == 1)
	assert(int((state.get("night", {}) as Dictionary).get("wolf_target_index", -1)) == -1)
	assert(String(first.get("effect", "")) == "vote")

	var second: Dictionary = engine.apply_target(state, players, 3, 0)
	assert(bool(second.get("ok", false)))
	state = second["werewolf"]
	players = second["players"]
	var target := int((state.get("night", {}) as Dictionary).get("wolf_target_index", -1))
	assert(target == 2 or target == 3)
	assert((state.get("votes", {}) as Dictionary).is_empty())
	assert(String(state.get("phase", "")) == "guard_action")
	assert(String((state.get("current_action", {}) as Dictionary).get("key", "")) == "guard_protect")
	var history: Array = second.get("history", [])
	assert(history.any(func(item): return item is Dictionary and String((item as Dictionary).get("speaker", "")) == "主持人" and String((item as Dictionary).get("visibility", "")) == "wolf" and String((item as Dictionary).get("text", "")).contains("平票")))


func _check_witch_auto_skip_and_action_rules(engine) -> void:
	var players := [
		_role_player("witch", true),
		_role_player("wolf", true),
		_role_player("villager", true),
		_role_player("seer", true),
	]
	var no_potions := _witch_state(false, false, -1)
	var no_potions_step: Dictionary = engine.skip_current_action(no_potions, players, 0)
	assert(not bool(no_potions_step.get("ok", false)))
	no_potions = _prepare_witch_phase(engine, no_potions, players)
	assert((no_potions.get("current_action", {}) as Dictionary).is_empty())

	var antidote_no_target := _prepare_witch_phase(engine, _witch_state(true, false, -1), players)
	assert((antidote_no_target.get("current_action", {}) as Dictionary).is_empty())

	var poison_only := _prepare_witch_phase(engine, _witch_state(false, true, -1), players)
	assert(String((poison_only.get("current_action", {}) as Dictionary).get("key", "")) == "witch_act")
	assert(int(engine.suggested_target_for_current_action(poison_only, players)) == 1)
	var poison_result: Dictionary = engine.apply_target(poison_only, players, 1, 0)
	assert(bool(poison_result.get("ok", false)))
	assert(not bool((poison_result["players"] as Array)[1].get("alive", true)))

	var both_potions_no_target := _prepare_witch_phase(engine, _witch_state(true, true, -1), players)
	assert(String((both_potions_no_target.get("current_action", {}) as Dictionary).get("key", "")) == "witch_act")
	assert(int(engine.suggested_target_for_current_action(both_potions_no_target, players)) == 1)

	var save_only := _prepare_witch_phase(engine, _witch_state(true, false, 2), players)
	assert(String((save_only.get("current_action", {}) as Dictionary).get("key", "")) == "witch_act")
	assert(int(engine.suggested_target_for_current_action(save_only, players)) == 2)
	var save_result: Dictionary = engine.apply_target(save_only, players, 2, 0)
	assert(bool(save_result.get("ok", false)))
	assert(bool((save_result["players"] as Array)[2].get("alive", false)))

	var day_state := _witch_state(true, true, 2)
	day_state["phase"] = "day_discussion"
	day_state["current_action"] = {"key": "witch_act", "actor_index": 0, "label": "用药", "effect": "potion"}
	var day_witch: Dictionary = engine.apply_target(day_state, players, 2, 0)
	assert(not bool(day_witch.get("ok", false)))
	var day_skip: Dictionary = engine.skip_current_action(day_state, players, 0)
	assert(not bool(day_skip.get("ok", false)))


func _prepare_witch_phase(engine, state: Dictionary, players: Array) -> Dictionary:
	var result: Dictionary = engine.apply_target(state, players, 1, 3)
	if not bool(result.get("ok", false)):
		return {}
	return result.get("werewolf", {}) as Dictionary


func _witch_state(antidote: bool, poison: bool, wolf_target: int) -> Dictionary:
	return {
		"phase": "seer_action",
		"day": 1,
		"votes": {},
		"night": {"day": 1, "wolf_target_index": wolf_target},
		"current_action": {"key": "seer_check", "actor_index": 3, "label": "查验", "effect": "inspect"},
		"speech_index": -1,
		"spoken_indices": [],
		"last_guarded_index": -1,
		"witch_antidote": antidote,
		"witch_poison": poison,
		"sheriff_player_index": -1,
		"post_game": {"stage": ""},
	}


func _check_sheriff_speech_order(engine) -> void:
	var players := [
		_role_player("villager", true),
		_role_player("seer", true),
		_role_player("witch", true),
		_role_player("guard", true),
		_role_player("wolf", true),
	]
	var state := {
		"phase": "sheriff_speech_order",
		"day": 2,
		"votes": {},
		"night": {},
		"current_action": {"key": "sheriff_speech_order", "actor_index": 1, "label": "发言顺序", "effect": "speech"},
		"spoken_indices": [],
		"has_sheriff": true,
		"sheriff_player_index": 1,
		"post_game": {"stage": ""},
	}
	var invalid_actor_state: Dictionary = state.duplicate(true)
	invalid_actor_state["current_action"] = {"key": "sheriff_speech_order", "actor_index": 0, "label": "发言顺序", "effect": "speech"}
	var invalid_actor: Dictionary = engine.apply_target(invalid_actor_state, players, 3, 0, "sheriff_speech_order_counterclockwise")
	assert(not bool(invalid_actor.get("ok", false)))

	var missing_direction: Dictionary = engine.apply_target(state, players, 3, 0)
	assert(not bool(missing_direction.get("ok", false)))

	var selected: Dictionary = engine.apply_target(state, players, 3, 0, "sheriff_speech_order_counterclockwise")
	assert(bool(selected.get("ok", false)))
	state = selected["werewolf"]
	players = selected["players"]
	assert(String(state.get("phase", "")) == "day_discussion")
	assert(String(state.get("day_speech_order_direction", "")) == "counterclockwise")
	var order: Array = state.get("day_speech_order", [])
	assert(order.size() == 5)
	assert(int(order[0]) == 3)
	assert(int(order[1]) == 2)
	assert(int(order[2]) == 1)
	assert(int(order[3]) == 0)
	assert(int(order[4]) == 4)
	assert(int(state.get("speech_index", -1)) == 3)
	var first_speech: Dictionary = engine.submit_speech(state, players, "4号先发言", 0)
	assert(bool(first_speech.get("ok", false)))
	state = first_speech["werewolf"]
	assert(int(state.get("speech_index", -1)) == 2)


func _check_sheriff_badge_action(engine) -> void:
	var players := [
		_role_player("seer", false),
		_role_player("villager", true),
		_role_player("wolf", true),
		_role_player("guard", true),
	]
	var state := {
		"phase": "sheriff_badge_action",
		"day": 2,
		"map_id": "sheriff_square",
		"wolf_win_condition": "all_good_dead",
		"votes": {},
		"night": {},
		"current_action": {"key": "sheriff_badge_action", "actor_index": 0, "label": "警徽", "effect": "vote"},
		"spoken_indices": [],
		"last_words_pending": [],
		"last_words_used": [],
		"has_sheriff": true,
		"sheriff_player_index": 0,
		"sheriff_badge_dead_index": 0,
		"sheriff_badge_return_phase": "day_entry",
		"sheriff_badge_candidates": [0],
		"sheriff_badge_check_hunter": false,
		"post_game": {"stage": ""},
	}
	var missing_choice: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(not bool(missing_choice.get("ok", false)))

	var passed: Dictionary = engine.apply_target(state, players, 1, 0, "sheriff_badge_pass")
	assert(bool(passed.get("ok", false)))
	var passed_state: Dictionary = passed["werewolf"]
	var passed_players: Array = passed["players"]
	assert(int(passed_state.get("sheriff_player_index", -1)) == 1)
	assert(String(passed_state.get("phase", "")) == "last_words")
	var passed_history: Array = passed.get("history", [])
	assert(passed_history.any(func(item): return item is Dictionary and String((item as Dictionary).get("action_key", "")) == "sheriff_badge_pass"))
	var last_words: Dictionary = engine.submit_speech(passed_state, passed_players, "警徽给2号，按2号归票。", 0)
	assert(bool(last_words.get("ok", false)))
	passed_state = last_words["werewolf"]
	assert(String(passed_state.get("phase", "")) == "sheriff_speech_order")
	assert(int((passed_state.get("current_action", {}) as Dictionary).get("actor_index", -1)) == 1)

	players = [
		_role_player("seer", false),
		_role_player("villager", true),
		_role_player("wolf", true),
		_role_player("guard", true),
	]
	var destroyed: Dictionary = engine.skip_current_action(state, players, 0)
	assert(bool(destroyed.get("ok", false)))
	var destroyed_state: Dictionary = destroyed["werewolf"]
	var destroyed_players: Array = destroyed["players"]
	assert(int(destroyed_state.get("sheriff_player_index", -2)) == -1)
	assert(String(destroyed_state.get("phase", "")) == "last_words")
	var destroyed_history: Array = destroyed.get("history", [])
	assert(destroyed_history.any(func(item): return item is Dictionary and String((item as Dictionary).get("action_key", "")) == "sheriff_badge_destroy"))
	var destroyed_last_words: Dictionary = engine.submit_speech(destroyed_state, destroyed_players, "警徽撕了，后面按座位发言。", 0)
	assert(bool(destroyed_last_words.get("ok", false)))
	destroyed_state = destroyed_last_words["werewolf"]
	assert(String(destroyed_state.get("phase", "")) == "day_discussion")


func _check_dead_player_post_game_summary(engine) -> void:
	var players := [
		_role_player("seer", false),
		_role_player("witch", true),
	]
	players[0]["name"] = "死亡预言家"
	players[1]["name"] = "女巫"
	var state := {
		"phase": "post_game_summary",
		"day": 3,
		"speech_index": 0,
		"spoken_indices": [],
		"current_action": {},
		"post_game": {
			"stage": "summary",
			"summaries": {},
			"summary_pending": [0, 1],
			"mvp_votes": {},
			"mvp_index": -1,
		},
	}
	var result: Dictionary = engine.submit_speech(state, players, "死亡玩家赛后总结", 0)
	assert(bool(result.get("ok", false)))
	state = result["werewolf"]
	players = result["players"]
	var post: Dictionary = state.get("post_game", {})
	assert(String((post.get("summaries", {}) as Dictionary).get("0", "")) == "死亡玩家赛后总结")
	var pending: Array = post.get("summary_pending", [])
	assert(pending.size() == 1)
	assert(int(pending[0]) == 1)
	assert(String(state.get("phase", "")) == "post_game_summary")
	assert(int(state.get("speech_index", -1)) == 1)


func _check_post_game_summary_to_mvp_completion(engine) -> void:
	var players := [
		_role_player("seer", false),
		_role_player("witch", true),
	]
	players[0]["name"] = "死亡预言家"
	players[1]["name"] = "女巫"
	var state := {
		"phase": "post_game_summary",
		"day": 3,
		"speech_index": 0,
		"spoken_indices": [],
		"current_action": {},
		"post_game": {
			"stage": "summary",
			"summaries": {},
			"summary_pending": [0, 1],
			"mvp_votes": {},
			"mvp_index": -1,
		},
	}
	var first_summary: Dictionary = engine.submit_speech(state, players, "1号赛后总结", 0)
	assert(bool(first_summary.get("ok", false)))
	state = first_summary["werewolf"]
	players = first_summary["players"]
	assert(String(state.get("phase", "")) == "post_game_summary")
	assert(int(state.get("speech_index", -1)) == 1)

	var second_summary: Dictionary = engine.submit_speech(state, players, "2号赛后总结", 0)
	assert(bool(second_summary.get("ok", false)))
	state = second_summary["werewolf"]
	players = second_summary["players"]
	var post: Dictionary = state.get("post_game", {})
	assert(String(state.get("phase", "")) == "mvp_vote")
	assert(String(post.get("stage", "")) == "mvp_vote")
	assert((post.get("summary_pending", []) as Array).is_empty())
	assert(String((post.get("summaries", {}) as Dictionary).get("0", "")) == "1号赛后总结")
	assert(String((post.get("summaries", {}) as Dictionary).get("1", "")) == "2号赛后总结")
	assert(int((state.get("current_action", {}) as Dictionary).get("actor_index", -1)) == 0)

	var first_vote: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(first_vote.get("ok", false)))
	state = first_vote["werewolf"]
	players = first_vote["players"]
	post = state.get("post_game", {})
	assert(String(state.get("phase", "")) == "mvp_vote")
	assert(int((state.get("current_action", {}) as Dictionary).get("actor_index", -1)) == 1)
	assert(int((post.get("mvp_votes", {}) as Dictionary).get("0", -1)) == 1)

	var second_vote: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(second_vote.get("ok", false)))
	state = second_vote["werewolf"]
	post = state.get("post_game", {})
	assert(String(state.get("phase", "")) == "completed")
	assert(String(post.get("stage", "")) == "completed")
	assert(int(post.get("mvp_index", -1)) == 1)
	assert((state.get("current_action", {}) as Dictionary).is_empty())


func _check_win_conditions(engine) -> void:
	var all_good_dead_state := {
		"map_id": "basic_village",
		"wolf_win_condition": "all_good_dead",
	}
	var all_good_dead_players := [
		_role_player("wolf", true),
		_role_player("wolf", true),
		_role_player("seer", true),
		_role_player("villager", false),
		_role_player("villager", false),
	]
	var not_over: Dictionary = engine._check_win(all_good_dead_state, all_good_dead_players)
	assert(String(not_over.get("winner", "")) == "")
	_set_alive(all_good_dead_players, 2, false)
	var wolf_win: Dictionary = engine._check_win(all_good_dead_state, all_good_dead_players)
	assert(String(wolf_win.get("winner", "")) == "wolf")

	var slaughter_side_state := {
		"map_id": "basic_village",
		"wolf_win_condition": "slaughter_side",
	}
	var slaughter_side_players := [
		_role_player("wolf", true),
		_role_player("seer", true),
		_role_player("villager", false),
	]
	var side_win: Dictionary = engine._check_win(slaughter_side_state, slaughter_side_players)
	assert(String(side_win.get("winner", "")) == "wolf")

	var good_win_players := [
		_role_player("wolf", false),
		_role_player("seer", true),
		_role_player("villager", true),
	]
	var good_win: Dictionary = engine._check_win(all_good_dead_state, good_win_players)
	assert(String(good_win.get("winner", "")) == "good")


func _check_wolf_attack_only_records_target_before_night_resolution(engine) -> void:
	var players := [
		_role_player("wolf", true),
		_role_player("hunter", true),
		_role_player("guard", true),
		_role_player("seer", true),
	]
	var state := {
		"phase": "wolf_action",
		"day": 1,
		"map_id": "basic_village",
		"wolf_win_condition": "all_good_dead",
		"votes": {},
		"night": {"day": 1, "wolf_target_index": -1},
		"current_action": {"key": "wolf_kill", "actor_index": 0, "label": "投刀", "effect": "vote"},
		"spoken_indices": [],
		"last_guarded_index": -1,
		"witch_antidote": false,
		"witch_poison": false,
		"sheriff_player_index": -1,
		"post_game": {"stage": ""},
	}
	var result: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(result.get("ok", false)))
	state = result["werewolf"]
	players = result["players"]
	assert(String(state.get("phase", "")) == "guard_action")
	assert(bool((players[1] as Dictionary).get("alive", false)))
	assert(int(((state.get("night", {}) as Dictionary).get("wolf_target_index", -1))) == 1)
	assert((result.get("death_indices", []) as Array).is_empty())


func _check_attacked_seer_can_still_act_before_night_resolution(engine) -> void:
	var players := [
		_role_player("wolf", true),
		_role_player("seer", true),
		_role_player("villager", true),
	]
	var state := {
		"phase": "wolf_action",
		"day": 1,
		"map_id": "quick_no_witch_village",
		"wolf_win_condition": "all_good_dead",
		"votes": {},
		"night": {"day": 1, "wolf_target_index": -1},
		"current_action": {"key": "wolf_kill", "actor_index": 0, "label": "投刀", "effect": "vote"},
		"spoken_indices": [],
		"last_guarded_index": -1,
		"witch_antidote": false,
		"witch_poison": false,
		"sheriff_player_index": -1,
		"post_game": {"stage": ""},
	}
	var attack_result: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(attack_result.get("ok", false)))
	state = attack_result["werewolf"]
	players = attack_result["players"]
	assert(String(state.get("phase", "")) == "seer_action")
	assert(bool((players[1] as Dictionary).get("alive", false)))
	assert(String((state.get("current_action", {}) as Dictionary).get("key", "")) == "seer_check")

	var seer_result: Dictionary = engine.apply_target(state, players, 0, 0)
	assert(bool(seer_result.get("ok", false)))
	state = seer_result["werewolf"]
	players = seer_result["players"]
	assert(not bool((players[1] as Dictionary).get("alive", true)))
	assert(String((players[1] as Dictionary).get("death_reason", "")) == "wolf")


func _check_night_attack_on_hunter_uses_night_end_death_flow(engine) -> void:
	var players := [
		_role_player("wolf", true),
		_role_player("hunter", true),
		_role_player("villager", true),
	]
	var state := {
		"phase": "wolf_action",
		"day": 4,
		"map_id": "quick_no_witch_village",
		"wolf_win_condition": "all_good_dead",
		"votes": {},
		"night": {"day": 4, "wolf_target_index": -1},
		"current_action": {"key": "wolf_kill", "actor_index": 0, "label": "投刀", "effect": "vote"},
		"spoken_indices": [],
		"last_guarded_index": -1,
		"witch_antidote": false,
		"witch_poison": false,
		"sheriff_player_index": -1,
		"post_game": {"stage": ""},
	}
	var night_result: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(night_result.get("ok", false)))
	state = night_result["werewolf"]
	players = night_result["players"]
	assert(String(state.get("phase", "")) == "hunter_action")
	assert(bool((players[1] as Dictionary).get("alive", false)))
	assert(bool((players[1] as Dictionary).get("can_hunter_shoot", false)))
	assert(String((state.get("current_action", {}) as Dictionary).get("key", "")) == "hunter_shoot")
	assert(String(state.get("winner", "")) == "")

	var shot_result: Dictionary = engine.apply_target(state, players, 0, 0)
	assert(bool(shot_result.get("ok", false)))
	state = shot_result["werewolf"]
	players = shot_result["players"]
	assert(not bool((players[0] as Dictionary).get("alive", true)))
	assert(String(state.get("winner", "")) == "good")


func _check_vote_exiled_hunter_shoots_before_exile_settlement(engine) -> void:
	var players := [
		_role_player("wolf", true),
		_role_player("hunter", true),
		_role_player("villager", true),
	]
	var state := {
		"phase": "vote",
		"day": 2,
		"map_id": "quick_no_witch_village",
		"wolf_win_condition": "all_good_dead",
		"votes": {},
		"night": {},
		"current_action": {"key": "vote", "actor_index": 0, "label": "投票", "effect": "vote"},
		"spoken_indices": [],
		"last_guarded_index": -1,
		"witch_antidote": false,
		"witch_poison": false,
		"sheriff_player_index": -1,
		"post_game": {"stage": ""},
	}
	var first: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(first.get("ok", false)))
	state = first["werewolf"]
	players = first["players"]
	var second: Dictionary = engine.apply_target(state, players, 0, 0)
	assert(bool(second.get("ok", false)))
	state = second["werewolf"]
	players = second["players"]
	var third: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(third.get("ok", false)))
	state = third["werewolf"]
	players = third["players"]
	assert(String(state.get("phase", "")) == "hunter_action")
	assert(bool((players[1] as Dictionary).get("alive", false)))
	assert(bool((players[1] as Dictionary).get("can_hunter_shoot", false)))
	assert(int(state.get("pending_vote_exile_index", -1)) == 1)
	assert(String(state.get("winner", "")) == "")

	var shot: Dictionary = engine.apply_target(state, players, 0, 0)
	assert(bool(shot.get("ok", false)))
	state = shot["werewolf"]
	players = shot["players"]
	assert(not bool((players[0] as Dictionary).get("alive", true)))
	assert(bool((players[1] as Dictionary).get("alive", false)))
	assert(String((players[1] as Dictionary).get("death_reason", "")) == "")
	assert(String(state.get("winner", "")) == "good")


func _check_vote_exiled_hunter_can_skip_before_exile_settlement(engine) -> void:
	var players := [
		_role_player("wolf", true),
		_role_player("hunter", true),
		_role_player("wolf", true),
	]
	var state := {
		"phase": "vote",
		"day": 2,
		"map_id": "quick_no_witch_village",
		"wolf_win_condition": "all_good_dead",
		"votes": {},
		"night": {},
		"current_action": {"key": "vote", "actor_index": 0, "label": "投票", "effect": "vote"},
		"spoken_indices": [],
		"last_guarded_index": -1,
		"witch_antidote": false,
		"witch_poison": false,
		"sheriff_player_index": -1,
		"post_game": {"stage": ""},
	}
	var first: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(first.get("ok", false)))
	state = first["werewolf"]
	players = first["players"]
	var second: Dictionary = engine.apply_target(state, players, 0, 0)
	assert(bool(second.get("ok", false)))
	state = second["werewolf"]
	players = second["players"]
	var third: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(third.get("ok", false)))
	state = third["werewolf"]
	players = third["players"]
	assert(String(state.get("phase", "")) == "hunter_action")
	assert(bool((players[1] as Dictionary).get("alive", false)))
	assert(int(state.get("pending_vote_exile_index", -1)) == 1)

	var skip: Dictionary = engine.skip_current_action(state, players, 0)
	assert(bool(skip.get("ok", false)))
	state = skip["werewolf"]
	players = skip["players"]
	assert(not bool((players[1] as Dictionary).get("alive", true)))
	assert(String((players[1] as Dictionary).get("death_reason", "")) == "exiled")
	assert(String(state.get("winner", "")) == "wolf")


func _check_idiot_reveal_vote_flow(engine) -> void:
	var players := [
		_role_player("idiot", true),
		_role_player("wolf", true),
		_role_player("villager", true),
	]
	var state := {
		"phase": "vote",
		"day": 1,
		"map_id": "sheriff_square",
		"wolf_win_condition": "slaughter_side",
		"votes": {},
		"night": {},
		"current_action": {"key": "vote", "actor_index": 0, "label": "投票", "effect": "vote"},
		"spoken_indices": [],
		"post_game": {"stage": ""},
	}
	var first: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(bool(first.get("ok", false)))
	state = first["werewolf"]
	players = first["players"]
	var second: Dictionary = engine.apply_target(state, players, 0, 0)
	assert(bool(second.get("ok", false)))
	state = second["werewolf"]
	players = second["players"]
	var third: Dictionary = engine.apply_target(state, players, 0, 0)
	assert(bool(third.get("ok", false)))
	state = third["werewolf"]
	players = third["players"]
	assert(bool((players[0] as Dictionary).get("alive", false)))
	assert(bool((players[0] as Dictionary).get("idiot_revealed", false)))
	assert(String((players[0] as Dictionary).get("idiot_reveal_source", "")) == "vote_exile")
	assert(String(state.get("phase", "")) == "wolf_chat")
	assert(int(state.get("day", 0)) == 2)

	state["phase"] = "vote"
	state["current_action"] = {"key": "vote", "actor_index": 0, "label": "投票", "effect": "vote"}
	var blocked: Dictionary = engine.apply_target(state, players, 1, 0)
	assert(not bool(blocked.get("ok", false)))


func _apply_prompt_target(engine, state: Dictionary, players: Array) -> Dictionary:
	var action: Dictionary = state.get("current_action", {})
	assert(not action.is_empty())
	var target := int(engine.suggested_target_for_current_action(state, players))
	assert(target >= 0)
	var action_choice := ""
	if String(action.get("key", "")) == "sheriff_speech_order":
		action_choice = "sheriff_speech_order_clockwise"
	elif String(action.get("key", "")) == "sheriff_badge_action":
		action_choice = "sheriff_badge_pass"
	return engine.apply_target(state, players, target, 0, action_choice)


func _advance_night_prompt(engine, state: Dictionary, players: Array) -> Dictionary:
	if String(state.get("phase", "")) == "wolf_chat":
		var speech: Dictionary = engine.submit_speech(state, players, "狼队夜聊测试", 0)
		assert(bool(speech.get("ok", false)))
		var history: Array = speech.get("history", [])
		assert(not history.is_empty())
		assert(String((history[0] as Dictionary).get("visibility", "")) == "wolf")
		if String((speech["werewolf"] as Dictionary).get("phase", "")) == "wolf_action":
			assert(int((speech["werewolf"] as Dictionary).get("speech_index", -1)) == -1)
		return speech
	return _apply_prompt_target(engine, state, players)


func _players(count: int) -> Array:
	var players := []
	for i in range(count):
		players.append({
			"id": "p%d" % i,
			"name": "玩家%d" % [i + 1],
			"role": "未知",
			"avatar": "",
			"state": "已准备",
			"motion": 0,
			"alive": true,
			"ready": true,
			"owner": "self" if i == 0 else "bot",
		})
	return players


func _role_player(role_key: String, alive: bool) -> Dictionary:
	return {
		"id": "%s_check" % role_key,
		"name": role_key,
		"role": role_key,
		"role_key": role_key,
		"avatar": "",
		"state": "测试",
		"motion": 0,
		"alive": alive,
		"ready": true,
		"owner": "bot",
	}


func _set_alive(players: Array, index: int, alive: bool) -> void:
	var player: Dictionary = players[index]
	player["alive"] = alive
	players[index] = player


func _alive_count(players: Array) -> int:
	var count := 0
	for item in players:
		var player: Dictionary = item
		if String(player.get("owner", "")) != "" and bool(player.get("alive", true)):
			count += 1
	return count
