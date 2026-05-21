extends RefCounted
class_name WerewolfPhaseOrchestrator

const EngineScript := preload("res://scripts/room/werewolf/werewolf_engine.gd")

var _engine = EngineScript.new()


func phase_label(state: Dictionary) -> String:
	return _engine.phase_label(state)


func is_night_phase(state: Dictionary) -> bool:
	return _engine.is_night_phase(state)
