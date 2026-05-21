extends RefCounted
class_name WerewolfRoomModule

const EngineScript := preload("res://scripts/room/werewolf/werewolf_engine.gd")
const MapCatalogScript := preload("res://scripts/room/werewolf/werewolf_map_catalog.gd")
const ReplayBuilderScript := preload("res://scripts/room/werewolf/werewolf_replay_builder.gd")
const DeliveryBuilderScript := preload("res://scripts/room/werewolf/werewolf_delivery_builder.gd")
const RecoveryBuilderScript := preload("res://scripts/room/werewolf/werewolf_recovery_builder.gd")

var _engine = EngineScript.new()
var _map_catalog = MapCatalogScript.new()
var _replay_builder = ReplayBuilderScript.new()
var _delivery_builder = DeliveryBuilderScript.new()
var _recovery_builder = RecoveryBuilderScript.new()


func default_state() -> Dictionary:
	return _engine.default_state()


func get_map_list() -> Array:
	return _map_catalog.get_map_list()


func get_supported_player_counts(map_id: String) -> Array:
	return _map_catalog.get_supported_player_counts(map_id)


func get_scene_slots(map_id: String, player_count: int) -> Dictionary:
	return _map_catalog.get_scene_slots(map_id, player_count)


func get_role_config(map_id: String, player_count: int) -> Array:
	return _map_catalog.get_role_config(map_id, player_count)


func map_background_path(map_id: String) -> String:
	return _map_catalog.map_background_path(map_id)


func map_rule_text(map_id: String, player_count: int = 0) -> String:
	return _map_catalog.rule_text(map_id, player_count)


func start_game(room_id: String, players: Array, occupied_indices: Array, local_index: int = -1, map_id: String = MapCatalogScript.DEFAULT_MAP_ID) -> Dictionary:
	return _engine.start_game(room_id, players, occupied_indices, local_index, map_id)


func apply_target(state: Dictionary, players: Array, target_index: int, local_index: int = -1, action_choice: String = "") -> Dictionary:
	return _engine.apply_target(state, players, target_index, local_index, action_choice)


func submit_speech(state: Dictionary, players: Array, text: String, local_index: int = -1) -> Dictionary:
	return _engine.submit_speech(state, players, text, local_index)


func skip_current_action(state: Dictionary, players: Array, local_index: int = -1) -> Dictionary:
	return _engine.skip_current_action(state, players, local_index)


func phase_label(state: Dictionary) -> String:
	return _engine.phase_label(state)


func is_night_phase(state: Dictionary) -> bool:
	return _engine.is_night_phase(state)


func vote_counts(votes: Dictionary, state: Dictionary, use_sheriff_weight: bool) -> Dictionary:
	var result = _engine.call("_vote_counts", votes, state, use_sheriff_weight)
	return result if result is Dictionary else {}


func suggested_target_for_current_action(state: Dictionary, players: Array) -> int:
	return _engine.suggested_target_for_current_action(state, players)


func build_player_frame(state: Dictionary, players: Array, history: Array, receiver_index: int) -> Dictionary:
	return _delivery_builder.build_player_frame(state, players, history, receiver_index)


func build_recovery_frame(state: Dictionary, players: Array, history: Array, receiver_index: int) -> Dictionary:
	return _recovery_builder.build_recovery_frame(state, players, history, receiver_index)


func build_replay(state: Dictionary, players: Array, history: Array) -> Dictionary:
	return _replay_builder.build_from_state(state, players, history)
