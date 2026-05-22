extends SceneTree


func _initialize() -> void:
	var catalog = load("res://scripts/room/werewolf/werewolf_map_catalog.gd").new()
	_check_sheriff_square(catalog)
	_check_sheriff_guard_square(catalog)
	quit()


func _check_sheriff_square(catalog) -> void:
	var counts := [7, 8, 9, 10, 11, 12]
	_expect_array(catalog.get_supported_player_counts("sheriff_square"), counts, "sheriff_square counts")
	for count in counts:
		_expect(catalog.get_role_config("sheriff_square", count).size() == count, "sheriff_square %d role count mismatch" % count)
		_expect(catalog.wolf_win_condition_key("sheriff_square", count) == "slaughter_side", "sheriff_square %d win condition" % count)
		_expect(catalog.rule_text("sheriff_square", count).contains("%d人局" % count), "sheriff_square %d rule text missing count" % count)
		_expect(catalog.rule_text("sheriff_square", count).contains("警长流程"), "sheriff_square %d rule text missing sheriff flow" % count)
	_expect_roles(catalog.get_role_config("sheriff_square", 7), {
		"wolf": 2,
		"seer": 1,
		"witch": 1,
		"villager": 3,
	}, "sheriff_square 7 roles")
	_expect_roles(catalog.get_role_config("sheriff_square", 10), {
		"wolf": 3,
		"seer": 1,
		"witch": 1,
		"hunter": 1,
		"villager": 4,
	}, "sheriff_square 10 roles")
	_expect_roles(catalog.get_role_config("sheriff_square", 12), {
		"wolf": 4,
		"seer": 1,
		"witch": 1,
		"hunter": 1,
		"idiot": 1,
		"villager": 4,
	}, "sheriff_square 12 roles")


func _check_sheriff_guard_square(catalog) -> void:
	var counts := [7, 8, 9, 10, 11, 12]
	_expect_array(catalog.get_supported_player_counts("sheriff_guard_square"), counts, "sheriff_guard_square counts")
	for count in counts:
		_expect(catalog.get_role_config("sheriff_guard_square", count).size() == count, "sheriff_guard_square %d role count mismatch" % count)
		_expect(catalog.wolf_win_condition_key("sheriff_guard_square", count) == "slaughter_side", "sheriff_guard_square %d win condition" % count)
		_expect(catalog.rule_text("sheriff_guard_square", count).contains("%d人局" % count), "sheriff_guard_square %d rule text missing count" % count)
		_expect(catalog.rule_text("sheriff_guard_square", count).contains("警长流程"), "sheriff_guard_square %d rule text missing sheriff flow" % count)
		_expect(catalog.rule_text("sheriff_guard_square", count).contains("守卫每夜守护"), "sheriff_guard_square %d rule text missing guard flow" % count)
	_expect_roles(catalog.get_role_config("sheriff_guard_square", 7), {
		"wolf": 2,
		"seer": 1,
		"guard": 1,
		"villager": 3,
	}, "sheriff_guard_square 7 roles")
	_expect_roles(catalog.get_role_config("sheriff_guard_square", 10), {
		"wolf": 3,
		"seer": 1,
		"witch": 1,
		"guard": 1,
		"villager": 4,
	}, "sheriff_guard_square 10 roles")
	_expect_roles(catalog.get_role_config("sheriff_guard_square", 12), {
		"wolf": 4,
		"seer": 1,
		"witch": 1,
		"hunter": 1,
		"guard": 1,
		"villager": 4,
	}, "sheriff_guard_square 12 roles")


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
