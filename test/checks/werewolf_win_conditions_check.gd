extends SceneTree

const WinConditionsScript := preload("res://scripts/room/werewolf/werewolf_win_conditions.gd")


func _initialize() -> void:
	var rules = WinConditionsScript.new()
	_check_all_good_dead(rules)
	_check_slaughter_side(rules)
	_check_wolf_team_variants(rules)
	_check_third_party_rules(rules)
	quit()


func _check_all_good_dead(rules) -> void:
	var state := {"wolf_win_condition": "all_good_dead"}
	var players := [
		_player("wolf", true),
		_player("seer", true),
		_player("villager", false),
	]
	assert(String(rules.check(state, players).get("winner", "")) == "")
	players[1]["alive"] = false
	var wolf_win: Dictionary = rules.check(state, players)
	assert(String(wolf_win.get("winner", "")) == "wolf")
	assert(String(wolf_win.get("condition", "")) == "all_good_dead")


func _check_slaughter_side(rules) -> void:
	var state := {"wolf_win_condition": "slaughter_side"}
	var villagers_dead := [
		_player("wolf", true),
		_player("seer", true),
		_player("old_rogue", false),
	]
	var wolf_win: Dictionary = rules.check(state, villagers_dead)
	assert(String(wolf_win.get("winner", "")) == "wolf")
	assert(String(wolf_win.get("condition", "")) == "slaughter_side")
	var gods_dead := [
		_player("wolf", true),
		_player("seer", false),
		_player("villager", true),
	]
	var side_win: Dictionary = rules.check(state, gods_dead)
	assert(String(side_win.get("winner", "")) == "wolf")


func _check_wolf_team_variants(rules) -> void:
	var state := {"wolf_win_condition": "all_good_dead"}
	var hidden_alive := [
		_player("hidden_wolf", true),
		_player("seer", true),
		_player("villager", true),
	]
	assert(String(rules.check(state, hidden_alive).get("winner", "")) == "")
	hidden_alive[0]["alive"] = false
	var good_win: Dictionary = rules.check(state, hidden_alive)
	assert(String(good_win.get("winner", "")) == "good")
	assert(String(good_win.get("condition", "")) == "all_wolves_dead")
	var counts: Dictionary = rules.alive_role_counts([
		_player("wolf_king", true),
		_player("villager", true),
	])
	assert(int(counts.get("wolves", 0)) == 1)
	assert(int(counts.get("villagers", 0)) == 1)


func _check_third_party_rules(rules) -> void:
	var piper_state := {
		"win_conditions": ["pied_piper_all_charmed"],
		"pied_piper_charmed_indices": [1, 2],
		"wolf_win_condition": "all_good_dead",
	}
	var piper_players := [
		_player("pied_piper", true),
		_player("wolf", true),
		_player("villager", true),
	]
	var piper_win: Dictionary = rules.check(piper_state, piper_players)
	assert(String(piper_win.get("winner", "")) == "third_party")
	assert(String(piper_win.get("condition", "")) == "pied_piper_all_charmed")

	var solo_state := {
		"win_conditions": ["solo_role_last_alive"],
		"wolf_win_condition": "all_good_dead",
	}
	var solo_players := [
		_player("lone_wolf", true),
		_player("wolf", false),
		_player("villager", false),
	]
	var solo_win: Dictionary = rules.check(solo_state, solo_players)
	assert(String(solo_win.get("winner", "")) == "third_party")
	assert(String(solo_win.get("condition", "")) == "solo_role_last_alive")


func _player(role_key: String, alive: bool) -> Dictionary:
	return {
		"id": role_key,
		"name": role_key,
		"role_key": role_key,
		"role": role_key,
		"alive": alive,
		"owner": "bot",
	}
