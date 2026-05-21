extends RefCounted
class_name WerewolfActionExecutor

const EngineScript := preload("res://scripts/room/werewolf/werewolf_engine.gd")

var _engine = EngineScript.new()


func apply_target(state: Dictionary, players: Array, target_index: int, local_index: int = -1, action_choice: String = "") -> Dictionary:
	return _engine.apply_target(state, players, target_index, local_index, action_choice)


func submit_speech(state: Dictionary, players: Array, text: String, local_index: int = -1) -> Dictionary:
	return _engine.submit_speech(state, players, text, local_index)


func skip_current_action(state: Dictionary, players: Array, local_index: int = -1) -> Dictionary:
	return _engine.skip_current_action(state, players, local_index)
