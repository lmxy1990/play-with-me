extends RefCounted
class_name SanguoshaMapCatalog

const RulePackCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_rule_pack_catalog.gd")
const AssetCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_asset_catalog.gd")

const DEFAULT_MAP_ID := "sanguosha_duel_2p"

var _rules = RulePackCatalogScript.new()


func get_map_list() -> Array:
	var result: Array = []
	for map_id in _map_order():
		var item := get_map(String(map_id))
		if not item.is_empty():
			result.append(item)
	return result


func get_map(map_id: String) -> Dictionary:
	var normalized := map_id.strip_edges()
	if normalized == "":
		normalized = DEFAULT_MAP_ID
	for item_value in _map_definitions():
		var item: Dictionary = item_value
		if String(item.get("id", "")) == normalized:
			return _inflate_map(item)
	return {}


func get_supported_player_counts(map_id: String) -> Array:
	var map_data := get_map(map_id)
	if map_data.is_empty():
		return []
	return (map_data.get("supported_player_counts", []) as Array).duplicate()


func get_scene_slots(map_id: String, player_count: int) -> Dictionary:
	var map_data := get_map(map_id)
	if map_data.is_empty():
		return {}
	if not get_supported_player_counts(map_id).has(player_count):
		return {}
	var rule_pack_id := String(map_data.get("rule_pack_id", ""))
	var identities := _rules.identities_for_rule_pack(rule_pack_id)
	if identities.size() != player_count:
		return {}
	var slots: Array = []
	for i in range(player_count):
		var role_key := String(identities[i])
		slots.append({
			"slot_number": i + 1,
			"seat_index": i,
			"name": "%d号位" % [i + 1],
			"role_key": role_key,
			"role_name": _rules.role_label(role_key),
			"identity_visible": role_key == "lord" or rule_pack_id == RulePackCatalogScript.DUEL_2P,
			"position": _slot_position(i, player_count),
		})
	return {
		"map_id": String(map_data.get("id", "")),
		"map_name": String(map_data.get("name", "")),
		"scene": String(map_data.get("scene", "")),
		"player_count": player_count,
		"rule_pack_id": rule_pack_id,
		"slots": slots,
		"identity_distribution": _role_counts(identities),
	}


func rule_pack_id(map_id: String) -> String:
	var map_data := get_map(map_id)
	return String(map_data.get("rule_pack_id", ""))


func role_distribution(map_id: String) -> Dictionary:
	var rule_pack := rule_pack_id(map_id)
	if rule_pack == "":
		return {}
	return _rules.role_distribution(rule_pack)


func rule_text(map_id: String) -> String:
	var map_data := get_map(map_id)
	return String(map_data.get("rule_text", ""))


func map_background_path(map_id: String) -> String:
	return AssetCatalogScript.map_background_path(map_id)


func _map_definitions() -> Array:
	return [
		{
			"id": "sanguosha_duel_2p",
			"name": "双人对决",
			"description": "2人三国杀对决，先击败对方者获胜",
			"scene": "双人牌桌",
			"rule_pack_id": RulePackCatalogScript.DUEL_2P,
			"supported_player_counts": [2],
		},
		{
			"id": "sanguosha_identity_4p",
			"name": "四人身份局",
			"description": "主公、忠臣、反贼、内奸各一名",
			"scene": "四人环形牌桌",
			"rule_pack_id": RulePackCatalogScript.IDENTITY_4P,
			"supported_player_counts": [4],
		},
		{
			"id": "sanguosha_identity_5p",
			"name": "五人身份局",
			"description": "主公1、忠臣1、反贼2、内奸1",
			"scene": "五人环形牌桌",
			"rule_pack_id": RulePackCatalogScript.IDENTITY_5P,
			"supported_player_counts": [5],
		},
		{
			"id": "sanguosha_identity_6p",
			"name": "六人身份局",
			"description": "主公1、忠臣1、反贼3、内奸1",
			"scene": "六人环形牌桌",
			"rule_pack_id": RulePackCatalogScript.IDENTITY_6P,
			"supported_player_counts": [6],
		},
		{
			"id": "sanguosha_identity_7p",
			"name": "七人身份局",
			"description": "主公1、忠臣2、反贼3、内奸1",
			"scene": "七人环形牌桌",
			"rule_pack_id": RulePackCatalogScript.IDENTITY_7P,
			"supported_player_counts": [7],
		},
		{
			"id": "sanguosha_identity_8p",
			"name": "八人身份局",
			"description": "主公1、忠臣2、反贼4、内奸1",
			"scene": "八人环形牌桌",
			"rule_pack_id": RulePackCatalogScript.IDENTITY_8P,
			"supported_player_counts": [8],
		},
	]


func _inflate_map(item: Dictionary) -> Dictionary:
	var map_data := item.duplicate(true)
	var rule_pack_id_value := String(map_data.get("rule_pack_id", ""))
	var rule_pack := _rules.get_rule_pack(rule_pack_id_value)
	map_data["background"] = AssetCatalogScript.map_background_path(String(map_data.get("id", "")))
	map_data["rule_text"] = String(rule_pack.get("rule_text", ""))
	map_data["role_distribution"] = _rules.role_distribution(rule_pack_id_value)
	map_data["card_pack_id"] = String(rule_pack.get("card_pack_id", ""))
	map_data["general_pack_id"] = String(rule_pack.get("general_pack_id", ""))
	map_data["skill_pack_id"] = String(rule_pack.get("skill_pack_id", ""))
	return map_data


func _map_order() -> Array:
	return [
		"sanguosha_duel_2p",
		"sanguosha_identity_4p",
		"sanguosha_identity_5p",
		"sanguosha_identity_6p",
		"sanguosha_identity_7p",
		"sanguosha_identity_8p",
	]


func _slot_position(index: int, total: int) -> Dictionary:
	var radius_x := 0.42 if total > 2 else 0.34
	var radius_y := 0.36 if total > 2 else 0.0
	var angle := -PI * 0.5 + TAU * float(index) / float(maxi(total, 1))
	if total == 2:
		return {"x": 0.22 if index == 0 else 0.78, "y": 0.5}
	return {
		"x": snapped(0.5 + cos(angle) * radius_x, 0.001),
		"y": snapped(0.5 + sin(angle) * radius_y, 0.001),
	}


func _role_counts(roles: Array) -> Array:
	var counts := {}
	for role_value in roles:
		var role_key := String(role_value)
		counts[role_key] = int(counts.get(role_key, 0)) + 1
	var result: Array = []
	for role_key in ["lord", "loyalist", "rebel", "renegade", "duelist_a", "duelist_b"]:
		if counts.has(role_key):
			result.append({
				"role_key": role_key,
				"role_name": _rules.role_label(role_key),
				"count": int(counts.get(role_key, 0)),
			})
	return result
