extends SceneTree

const MapCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_map_catalog.gd")
const RulePackCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_rule_pack_catalog.gd")


func _initialize() -> void:
	var maps = MapCatalogScript.new()
	var rules = RulePackCatalogScript.new()
	_check_rule_packs(rules)
	_check_map_list(maps)
	_check_scene_slots(maps)
	print("sanguosha_map_catalog_check passed")
	quit()


func _check_rule_packs(rules) -> void:
	_expect(rules.supported_player_counts() == [2, 4, 5, 6, 7, 8], "supported player counts mismatch")
	_expect(_dist_equals(rules.role_distribution("duel_2p"), {"lord": 0, "loyalist": 0, "rebel": 0, "renegade": 0}), "2p distribution mismatch")
	_expect(_dist_equals(rules.role_distribution("identity_4p"), {"lord": 1, "loyalist": 1, "rebel": 1, "renegade": 1}), "4p distribution mismatch")
	_expect(_dist_equals(rules.role_distribution("identity_5p"), {"lord": 1, "loyalist": 1, "rebel": 2, "renegade": 1}), "5p distribution mismatch")
	_expect(_dist_equals(rules.role_distribution("identity_6p"), {"lord": 1, "loyalist": 1, "rebel": 3, "renegade": 1}), "6p distribution mismatch")
	_expect(_dist_equals(rules.role_distribution("identity_7p"), {"lord": 1, "loyalist": 2, "rebel": 3, "renegade": 1}), "7p distribution mismatch")
	_expect(_dist_equals(rules.role_distribution("identity_8p"), {"lord": 1, "loyalist": 2, "rebel": 4, "renegade": 1}), "8p distribution mismatch")
	var pack: Dictionary = rules.get_rule_pack("identity_8p")
	_expect(String(pack.get("card_pack_id", "")) == "standard_108", "rule pack should link standard_108")
	_expect(String(pack.get("general_pack_id", "")) == "standard_core_adult_female", "rule pack should link adult female general pack")


func _check_map_list(maps) -> void:
	var list: Array = maps.get_map_list()
	_expect(list.size() == 6, "sanguosha map list size mismatch")
	_expect(String((list[0] as Dictionary).get("id", "")) == "sanguosha_duel_2p", "first map should be 2p duel")
	_expect((maps.get_supported_player_counts("sanguosha_identity_8p") as Array) == [8], "8p map count mismatch")
	_expect(String(maps.rule_pack_id("sanguosha_identity_6p")) == "identity_6p", "6p map rule pack mismatch")


func _check_scene_slots(maps) -> void:
	var duel: Dictionary = maps.get_scene_slots("sanguosha_duel_2p", 2)
	_expect((duel.get("slots", []) as Array).size() == 2, "2p slots mismatch")
	var identity: Dictionary = maps.get_scene_slots("sanguosha_identity_8p", 8)
	var slots: Array = identity.get("slots", [])
	_expect(slots.size() == 8, "8p slots mismatch")
	_expect(String((slots[0] as Dictionary).get("role_key", "")) == "lord", "first 8p slot should be lord")
	_expect(bool((slots[0] as Dictionary).get("identity_visible", false)), "lord identity should be visible")
	_expect(not bool((slots[1] as Dictionary).get("identity_visible", true)), "non-lord identity should be hidden")
	var counts: Array = identity.get("identity_distribution", [])
	_expect(_role_count(counts, "rebel") == 4, "8p rebel count mismatch")
	_expect(_role_count(counts, "loyalist") == 2, "8p loyalist count mismatch")
	_expect(maps.get_scene_slots("sanguosha_identity_8p", 4).is_empty(), "wrong player count should not return slots")


func _dist_equals(actual: Dictionary, expected: Dictionary) -> bool:
	for key in expected.keys():
		if int(actual.get(key, -1)) != int(expected[key]):
			return false
	return true


func _role_count(counts: Array, role_key: String) -> int:
	for item_value in counts:
		var item: Dictionary = item_value
		if String(item.get("role_key", "")) == role_key:
			return int(item.get("count", 0))
	return 0


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	assert(false, message)
