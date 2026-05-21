extends RefCounted
class_name WerewolfRecoveryBuilder

const DeliveryBuilderScript := preload("res://scripts/room/werewolf/werewolf_delivery_builder.gd")

var _delivery_builder = DeliveryBuilderScript.new()


func build_recovery_frame(state: Dictionary, players: Array, history: Array, receiver_index: int) -> Dictionary:
	var frame: Dictionary = _delivery_builder.build_player_frame(state, players, history, receiver_index)
	frame["recovery"] = true
	frame["history_size"] = history.size()
	return frame
