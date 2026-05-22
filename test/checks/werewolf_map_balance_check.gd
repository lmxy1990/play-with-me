extends SceneTree

const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")


func _initialize() -> void:
	var catalog = load("res://scripts/room/werewolf/werewolf_map_catalog.gd").new()
	var role_catalog = RoleCatalogScript.new()
	for map_value in catalog.get_map_list():
		var map_data: Dictionary = map_value
		var map_id := String(map_data.get("id", ""))
		var counts: Array = map_data.get("supported_player_counts", [])
		_expect(not counts.is_empty(), "%s has no supported player counts" % map_id)
		for count_value in counts:
			var count := int(count_value)
			var roles: Array = catalog.get_role_config(map_id, count)
			_expect(roles.size() == count, "%s %d roles size mismatch: %d" % [map_id, count, roles.size()])
			var win_key := String(catalog.wolf_win_condition_key(map_id, count))
			if count == 6:
				_expect(win_key == "all_good_dead", "%s 6-player game must use all_good_dead" % map_id)
			else:
				_expect(win_key == "slaughter_side", "%s %d-player game must use slaughter_side" % [map_id, count])
				_expect(_count_by_group(role_catalog, roles, RoleCatalogScript.SLAUGHTER_GROUP_VILLAGER) >= 3, "%s %d-player game has too few villagers for slaughter-side" % [map_id, count])
				_expect(_count_by_group(role_catalog, roles, RoleCatalogScript.SLAUGHTER_GROUP_GOD) >= 2, "%s %d-player game has too few gods for slaughter-side" % [map_id, count])
			_expect(_count_wolves(role_catalog, roles) >= 2, "%s %d-player game has too few wolves" % [map_id, count])
			_expect(catalog.rule_text(map_id, count).contains("%d人局" % count), "%s %d rule text is not count-specific" % [map_id, count])
	quit()


func _count_wolves(role_catalog, roles: Array) -> int:
	var total := 0
	for role_value in roles:
		if role_catalog.counts_as_wolf_for_win(String(role_value)):
			total += 1
	return total


func _count_by_group(role_catalog, roles: Array, group: String) -> int:
	var total := 0
	for role_value in roles:
		if role_catalog.slaughter_group(String(role_value)) == group:
			total += 1
	return total


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
