extends RefCounted
class_name WerewolfRuleState

const RoomModuleScript := preload("res://scripts/room/werewolf/werewolf_room_module.gd")

var _room_module = RoomModuleScript.new()


func empty() -> Dictionary:
	return _room_module.default_state()
