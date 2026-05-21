extends RefCounted
class_name WerewolfMapCatalog

const DEFAULT_MAP_ID := "basic_village"

const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")
const WinConditionsScript := preload("res://scripts/room/werewolf/werewolf_win_conditions.gd")
const BasicVillageScript := preload("res://scripts/room/werewolf/maps/basic_village/map.gd")
const HunterPressureVillageScript := preload("res://scripts/room/werewolf/maps/hunter_pressure_village/map.gd")
const QuickNoWitchVillageScript := preload("res://scripts/room/werewolf/maps/quick_no_witch_village/map.gd")
const GuardVillageScript := preload("res://scripts/room/werewolf/maps/guard_village/map.gd")
const SheriffSquareScript := preload("res://scripts/room/werewolf/maps/sheriff_square/map.gd")
const SheriffGuardSquareScript := preload("res://scripts/room/werewolf/maps/sheriff_guard_square/map.gd")

var _role_catalog = RoleCatalogScript.new()
var _win_conditions = WinConditionsScript.new()


func get_map_list() -> Array:
	var result: Array = []
	for map_id in _map_order():
		var item := get_map(String(map_id))
		if item.is_empty():
			continue
		result.append({
			"id": String(item.get("id", "")),
			"name": String(item.get("name", "")),
			"description": String(item.get("description", "")),
			"scene": String(item.get("scene", "")),
			"background": String(item.get("background", "")),
			"rule_text": String(item.get("rule_text", "")),
			"rule_text_by_count": (item.get("rule_text_by_count", {}) as Dictionary).duplicate(true),
			"wolf_win_condition_by_count": (item.get("wolf_win_condition_by_count", {}) as Dictionary).duplicate(true),
			"has_sheriff": bool(item.get("has_sheriff", false)),
			"supported_player_counts": get_supported_player_counts(String(item.get("id", ""))),
		})
	return result


func get_supported_player_counts(map_id: String) -> Array:
	var roles_by_count := _roles_by_count(map_id)
	var counts: Array = []
	for key in roles_by_count.keys():
		counts.append(int(key))
	counts.sort()
	return counts


func get_scene_slots(map_id: String, player_count: int) -> Dictionary:
	var map_data := get_map(map_id)
	if map_data.is_empty():
		return {}
	var roles := get_role_config(map_id, player_count)
	if roles.is_empty():
		return {}
	var slots: Array = []
	for i in range(player_count):
		var role_key := String(roles[i])
		slots.append({
			"slot_number": i + 1,
			"seat_index": i,
			"name": "%d号位" % [i + 1],
			"role_key": role_key,
			"role_name": role_label(role_key),
			"position": _slot_position(i, player_count),
		})
	return {
		"map_id": String(map_data.get("id", "")),
		"map_name": String(map_data.get("name", "")),
		"scene": String(map_data.get("scene", "")),
		"player_count": player_count,
		"slots": slots,
		"identity_distribution": _role_counts(roles),
	}


func get_role_config(map_id: String, player_count: int) -> Array:
	var roles_by_count := _roles_by_count(map_id)
	if roles_by_count.has(player_count):
		return (roles_by_count[player_count] as Array).duplicate()
	return []


func get_map(map_id: String) -> Dictionary:
	var script = _map_script(map_id)
	if script == null:
		return {}
	var data: Dictionary = script.new().definition()
	return data.duplicate(true)


func map_background_path(map_id: String) -> String:
	var data := get_map(map_id)
	return String(data.get("background", "res://assets/images/werewolf/backgrounds/map_basic.png"))


func rule_text(map_id: String, player_count: int = 0) -> String:
	var data := get_map(map_id)
	var by_count: Dictionary = data.get("rule_text_by_count", {})
	if player_count > 0 and by_count.has(player_count):
		return String(by_count[player_count])
	return String(data.get("rule_text", ""))


func wolf_win_condition_key(map_id: String, player_count: int) -> String:
	var data := get_map(map_id)
	var by_count: Dictionary = data.get("wolf_win_condition_by_count", {})
	if player_count > 0 and by_count.has(player_count):
		return String(by_count[player_count])
	return _win_conditions.default_wolf_condition_key(player_count)


func wolf_win_condition_text(map_id: String, player_count: int) -> String:
	return _win_conditions.condition_text(wolf_win_condition_key(map_id, player_count))


func wolf_win_condition_summary(map_id: String, player_count: int) -> String:
	return _win_conditions.condition_summary(wolf_win_condition_key(map_id, player_count))


func role_label(role: String) -> String:
	return _role_catalog.role_label(role)


func role_avatar(role: String) -> String:
	return _role_catalog.role_avatar(role)


func role_title(role: String) -> String:
	return _role_catalog.role_title(role)


func role_definition(role: String) -> Dictionary:
	return _role_catalog.definition(role)


func role_skill_text(role: String) -> String:
	return _role_catalog.role_skill_text(role)


func _roles_by_count(map_id: String) -> Dictionary:
	var map_data := get_map(map_id)
	if map_data.is_empty():
		return {}
	return (map_data.get("roles", {}) as Dictionary).duplicate(true)


func _map_order() -> Array:
	return [
		"basic_village",
		"hunter_pressure_village",
		"quick_no_witch_village",
		"guard_village",
		"sheriff_square",
		"sheriff_guard_square",
	]


func _map_script(map_id: String):
	match map_id.strip_edges():
		"basic_village":
			return BasicVillageScript
		"hunter_pressure_village":
			return HunterPressureVillageScript
		"quick_no_witch_village":
			return QuickNoWitchVillageScript
		"guard_village":
			return GuardVillageScript
		"sheriff_square":
			return SheriffSquareScript
		"sheriff_guard_square":
			return SheriffGuardSquareScript
		_:
			return null


func _slot_position(index: int, total: int) -> Dictionary:
	var angle := -PI * 0.5 + TAU * float(index) / float(maxi(total, 1))
	return {
		"x": snapped(0.5 + cos(angle) * 0.42, 0.001),
		"y": snapped(0.5 + sin(angle) * 0.36, 0.001),
	}


func _role_counts(roles: Array) -> Array:
	return _role_catalog.role_counts(roles)
