extends SceneTree

const EngineScript := preload("res://scripts/room/sanguosha/sanguosha_engine.gd")


func _initialize() -> void:
	var engine = EngineScript.new()
	_check_default_state(engine)
	_check_start_state(engine)
	_check_legal_play_actions(engine)
	_check_slash_and_dodge(engine)
	_check_slash_pass_damage_and_duel_win(engine)
	_check_draw_two(engine)
	_check_equip_replacement_and_distance(engine)
	print("sanguosha_engine_check passed")
	quit()


func _check_default_state(engine) -> void:
	var state: Dictionary = engine.default_state()
	_expect(String(state.get("game_id", "")) == "sanguosha", "default game id mismatch")
	_expect(String(state.get("phase", "")) == engine.PHASE_LOBBY, "default phase mismatch")
	_expect(not bool(state.get("started", true)), "default should not be started")
	_expect(String(state.get("card_pack_id", "")) == "standard_108", "default card pack mismatch")
	_expect(String(state.get("general_pack_id", "")) == "standard_core_adult_female", "default general pack mismatch")
	_expect((state.get("players", []) as Array).is_empty(), "default players should be empty")


func _check_start_state(engine) -> void:
	var state: Dictionary = engine.start_state(4, "sanguosha_identity_4p")
	_expect(bool(state.get("started", false)), "4p should start")
	_expect(String(state.get("phase", "")) == engine.PHASE_PLAY, "started phase should be play")
	_expect((state.get("players", []) as Array).size() == 4, "4p player count mismatch")
	_expect((state.get("hands", []) as Array).size() == 4, "4p hands count mismatch")
	_expect(_hand(state, 0).size() == 4, "initial hand size mismatch")
	_expect(_hand(state, 3).size() == 4, "initial hand size mismatch")
	_expect((state.get("deck", []) as Array).size() == 108 - 16, "deck should shrink by initial hands")
	var players: Array = state.get("players", [])
	_expect(String((players[0] as Dictionary).get("identity", "")) == "lord", "seat 0 should be lord")
	_expect(int((players[0] as Dictionary).get("max_hp", 0)) >= 4, "lord should have hp")
	_expect((players[0] as Dictionary).get("general_options", []) is Array, "general options should exist")
	var eight: Dictionary = engine.start_state(8, "sanguosha_identity_8p")
	_expect(bool(eight.get("started", false)), "8p should start")
	_expect((eight.get("players", []) as Array).size() == 8, "8p player count mismatch")
	_expect((eight.get("deck", []) as Array).size() == 108 - 32, "8p deck should shrink by initial hands")


func _check_legal_play_actions(engine) -> void:
	var state: Dictionary = engine.start_state(2, "sanguosha_duel_2p", {"deck_front_template_ids": ["std_019", "std_003", "std_014", "std_020", "std_009", "std_021", "std_005", "std_041"]})
	var actions: Array = engine.legal_actions(state, 0)
	_expect(_has_action_type(actions, "end_play"), "play actions should include end_play")
	_expect(_has_play_card_key(actions, "slash"), "play actions should include slash when in range")
	_expect(_has_play_card_key(actions, "draw_two"), "play actions should include draw_two")
	_expect(_has_play_card_key(actions, "qilin_bow"), "play actions should include equipment")


func _check_slash_and_dodge(engine) -> void:
	var state: Dictionary = engine.start_state(2, "sanguosha_duel_2p", {"deck_front_template_ids": ["std_019", "std_003", "std_005", "std_041", "std_007", "std_043", "std_011", "std_045"]})
	var slash := _first_play_card_action(engine.legal_actions(state, 0), "slash")
	_expect(not slash.is_empty(), "slash setup action missing")
	var played: Dictionary = engine.apply_action(state, 0, slash)
	_expect(bool(played.get("ok", false)), "slash should apply")
	var response_state: Dictionary = played.get("state", {})
	_expect(String(response_state.get("phase", "")) == engine.PHASE_RESPONSE, "slash should enter response phase")
	var window: Dictionary = response_state.get("response_window", {})
	_expect(String(window.get("kind", "")) == "dodge_slash", "slash should create dodge response")
	_expect(int(window.get("target_seat", -1)) == 1, "dodge target mismatch")
	var response_actions: Array = engine.legal_actions(response_state, 1)
	_expect(_has_action_type(response_actions, "respond_card"), "target should be able to dodge")
	var before_hp := _hp(response_state, 1)
	var dodge := _first_action_type(response_actions, "respond_card")
	var dodged: Dictionary = engine.apply_action(response_state, 1, dodge)
	_expect(bool(dodged.get("ok", false)), "dodge should apply")
	var dodged_state: Dictionary = dodged.get("state", {})
	_expect(String(dodged_state.get("phase", "")) == engine.PHASE_PLAY, "dodge should return to play")
	_expect((dodged_state.get("response_window", {}) as Dictionary).is_empty(), "dodge should clear response window")
	_expect(_hp(dodged_state, 1) == before_hp, "dodge should prevent damage")


func _check_slash_pass_damage_and_duel_win(engine) -> void:
	var state: Dictionary = engine.start_state(2, "sanguosha_duel_2p", {"deck_front_template_ids": ["std_019", "std_041", "std_005", "std_043", "std_007", "std_045", "std_011", "std_047"]})
	_set_hp(state, 1, 1)
	var slash := _first_play_card_action(engine.legal_actions(state, 0), "slash")
	var played: Dictionary = engine.apply_action(state, 0, slash)
	_expect(bool(played.get("ok", false)), "slash should apply before pass")
	var response_state: Dictionary = played.get("state", {})
	var pass_action := _first_action_type(engine.legal_actions(response_state, 1), "pass")
	var passed: Dictionary = engine.apply_action(response_state, 1, pass_action)
	_expect(bool(passed.get("ok", false)), "pass should apply")
	var next: Dictionary = passed.get("state", {})
	_expect(not _alive(next, 1), "target should die after lethal slash")
	_expect(String(next.get("phase", "")) == engine.PHASE_COMPLETED, "duel should complete when enemy dies")
	_expect(String(next.get("winner", "")) == engine.WINNER_DUELIST_A, "seat 0 should win duel")


func _check_draw_two(engine) -> void:
	var state: Dictionary = engine.start_state(2, "sanguosha_duel_2p", {"deck_front_template_ids": ["std_014", "std_019", "std_005", "std_041", "std_007", "std_043", "std_011", "std_045"]})
	var before_hand := _hand(state, 0).size()
	var before_deck := (state.get("deck", []) as Array).size()
	var draw_two := _first_play_card_action(engine.legal_actions(state, 0), "draw_two")
	_expect(not draw_two.is_empty(), "draw_two setup action missing")
	var result: Dictionary = engine.apply_action(state, 0, draw_two)
	_expect(bool(result.get("ok", false)), "draw_two should apply")
	var next: Dictionary = result.get("state", {})
	_expect(_hand(next, 0).size() == before_hand + 1, "draw_two uses one card and draws two")
	_expect((next.get("deck", []) as Array).size() == before_deck - 2, "draw_two should draw two from deck")


func _check_equip_replacement_and_distance(engine) -> void:
	var state: Dictionary = engine.start_state(4, "sanguosha_identity_4p", {"deck_front_template_ids": ["std_009", "std_019", "std_020", "std_021", "std_037", "std_041", "std_043", "std_044", "std_010", "std_005", "std_007", "std_011", "std_013", "std_015", "std_017", "std_023"]})
	var equip_qilin := _first_play_card_action(engine.legal_actions(state, 0), "qilin_bow")
	_expect(not equip_qilin.is_empty(), "qilin bow action missing")
	var first: Dictionary = engine.apply_action(state, 0, equip_qilin)
	_expect(bool(first.get("ok", false)), "first weapon equip should apply")
	var first_state: Dictionary = first.get("state", {})
	_expect(engine.attack_range(first_state, 0) == 5, "qilin bow range should be 5")
	var equip_dragon := _first_play_card_action(engine.legal_actions(first_state, 0), "green_dragon_blade")
	_expect(not equip_dragon.is_empty(), "green dragon blade action missing")
	var second: Dictionary = engine.apply_action(first_state, 0, equip_dragon)
	_expect(bool(second.get("ok", false)), "weapon replacement should apply")
	var second_state: Dictionary = second.get("state", {})
	_expect(engine.attack_range(second_state, 0) == 3, "green dragon blade range should be 3")
	_expect((second_state.get("discard_pile", []) as Array).size() >= 1, "replaced equipment should go discard")
	var before_distance: int = engine.distance_between(second_state, 0, 2)
	var equip_horse := _first_play_card_action(engine.legal_actions(second_state, 0), "red_hare")
	_expect(not equip_horse.is_empty(), "attack horse action missing")
	var horse: Dictionary = engine.apply_action(second_state, 0, equip_horse)
	_expect(bool(horse.get("ok", false)), "attack horse equip should apply")
	var horse_state: Dictionary = horse.get("state", {})
	_expect(engine.distance_between(horse_state, 0, 2) == maxi(1, before_distance - 1), "attack horse should reduce distance to others")


func _hand(state: Dictionary, seat_index: int) -> Array:
	var hands: Array = state.get("hands", [])
	if seat_index < 0 or seat_index >= hands.size() or not (hands[seat_index] is Array):
		return []
	return hands[seat_index] as Array


func _hp(state: Dictionary, seat_index: int) -> int:
	var players: Array = state.get("players", [])
	if seat_index < 0 or seat_index >= players.size():
		return 0
	var player: Dictionary = players[seat_index]
	return int(player.get("hp", 0))


func _set_hp(state: Dictionary, seat_index: int, hp: int) -> void:
	var players: Array = state.get("players", [])
	var player: Dictionary = players[seat_index]
	player["hp"] = hp
	players[seat_index] = player
	state["players"] = players


func _alive(state: Dictionary, seat_index: int) -> bool:
	var players: Array = state.get("players", [])
	if seat_index < 0 or seat_index >= players.size():
		return false
	var player: Dictionary = players[seat_index]
	return bool(player.get("alive", false))


func _has_action_type(actions: Array, action_type: String) -> bool:
	return not _first_action_type(actions, action_type).is_empty()


func _has_play_card_key(actions: Array, card_key: String) -> bool:
	return not _first_play_card_action(actions, card_key).is_empty()


func _first_action_type(actions: Array, action_type: String) -> Dictionary:
	for action_value in actions:
		var action: Dictionary = action_value
		if String(action.get("action_type", "")) == action_type:
			return action
	return {}


func _first_play_card_action(actions: Array, card_key: String) -> Dictionary:
	for action_value in actions:
		var action: Dictionary = action_value
		if String(action.get("action_type", "")) == "play_card" and String(action.get("card_key", "")) == card_key:
			return action
	return {}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	assert(false, message)
