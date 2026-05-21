extends SceneTree


func _initialize() -> void:
	var catalog = load("res://scripts/room/werewolf/werewolf_map_catalog.gd").new()
	_check_sheriff_square(catalog)
	_check_sheriff_guard_square(catalog)
	quit()


func _check_sheriff_square(catalog) -> void:
	_expect_array(catalog.get_supported_player_counts("sheriff_square"), [10, 12], "sheriff_square counts")
	_expect_roles(catalog.get_role_config("sheriff_square", 10), {
		"wolf": 3,
		"seer": 1,
		"witch": 1,
		"hunter": 1,
		"idiot": 1,
		"villager": 3,
	}, "sheriff_square 10 roles")
	_expect_roles(catalog.get_role_config("sheriff_square", 12), {
		"wolf": 4,
		"seer": 1,
		"witch": 1,
		"hunter": 1,
		"idiot": 1,
		"villager": 4,
	}, "sheriff_square 12 roles")
	_expect(catalog.wolf_win_condition_key("sheriff_square", 10) == "slaughter_side", "sheriff_square 10 win condition")
	_expect(catalog.wolf_win_condition_key("sheriff_square", 12) == "slaughter_side", "sheriff_square 12 win condition")


func _check_sheriff_guard_square(catalog) -> void:
	_expect_array(catalog.get_supported_player_counts("sheriff_guard_square"), [12], "sheriff_guard_square counts")
	_expect_roles(catalog.get_role_config("sheriff_guard_square", 12), {
		"wolf": 4,
		"seer": 1,
		"witch": 1,
		"hunter": 1,
		"guard": 1,
		"villager": 4,
	}, "sheriff_guard_square 12 roles")
	_expect(catalog.wolf_win_condition_key("sheriff_guard_square", 12) == "slaughter_side", "sheriff_guard_square 12 win condition")


func _expect_roles(roles: Array, expected: Dictionary, label: String) -> void:
	var actual := {}
	for role_value in roles:
		var role := String(role_value)
		actual[role] = int(actual.get(role, 0)) + 1
	_expect(actual == expected, "%s mismatch: %s" % [label, str(actual)])


func _expect_array(actual: Array, expected: Array, label: String) -> void:
	_expect(actual == expected, "%s mismatch: %s" % [label, str(actual)])


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
