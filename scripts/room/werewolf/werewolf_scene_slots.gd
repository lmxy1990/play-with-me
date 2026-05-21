extends RefCounted
class_name WerewolfSceneSlots

const MapCatalogScript := preload("res://scripts/room/werewolf/werewolf_map_catalog.gd")

var _catalog = MapCatalogScript.new()


func build(map_id: String, player_count: int) -> Dictionary:
	return _catalog.get_scene_slots(map_id, player_count)
