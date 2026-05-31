extends RefCounted
class_name AppState

const SAVE_PATH := "user://play_with_me_state.json"
const STATE_VERSION := 6

const WerewolfAssetCatalogScript := preload("res://scripts/room/werewolf/werewolf_asset_catalog.gd")
const XiangqiAssetCatalogScript := preload("res://scripts/room/xiangqi/xiangqi_asset_catalog.gd")
const XiangqiEngineScript := preload("res://scripts/room/xiangqi/xiangqi_engine.gd")
const DEFAULT_MAP_ID := "basic_village"
const DEFAULT_MAP_NAME := "标准村庄"
const XIANGQI_MAP_ID := "xiangqi_standard"
const XIANGQI_MAP_NAME := "标准象棋"
const DEFAULT_ROOM_MAX_OUTPUT_TOKENS := 2000
const DEFAULT_TIMELINE_COMPRESSION_INTERVAL := 8
const DEFAULT_TIMELINE_COMPRESSION_PROMPT := "把以下时间线转化为事实，减短内容。"

enum SeatMotion { IDLE, THINKING, SPEAKING, DEAD }

var rooms: Array = []
var model_configs: Array = []
var voice_configs: Array = []
var bot_profiles: Array = []
var players: Array = []
var local_player_index := 0
var local_nickname := "阿景"
var bot_serial := 1
var phase_night := false
var active_room_id := ""
var system_message := "等待创建房间"
var werewolf: Dictionary = {}
var xiangqi: Dictionary = {}
var history: Array = []
var device_identity_json: Dictionary = {}
var persistence_enabled := true


func load_or_create() -> void:
	_apply_defaults()
	if not persistence_enabled:
		return
	if not FileAccess.file_exists(SAVE_PATH):
		save()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_apply_json(parsed)


func save() -> void:
	if not persistence_enabled:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(to_json(), "\t"))


func to_json() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"model_configs": model_configs,
		"voice_configs": voice_configs,
		"bot_profiles": bot_profiles,
		"local_nickname": local_nickname,
	}


func create_room(game_type: String, player_count: int, password: String, map_id: String = "", map_name: String = "", allow_observers: bool = true, max_observers: int = 3, room_options: Dictionary = {}) -> Dictionary:
	var id := "room_%d" % Time.get_ticks_usec()
	var game_room_id := _game_room_id_for_create(game_type, room_options)
	var normalized_map_id := map_id.strip_edges()
	var normalized_map_name := map_name.strip_edges()
	var normalized_room_options := _normalized_room_options(room_options)
	normalized_room_options["game_room_id"] = game_room_id
	normalized_room_options["gameId"] = game_room_id
	if normalized_map_id == "":
		normalized_map_id = XIANGQI_MAP_ID if game_room_id == "xiangqi" else DEFAULT_MAP_ID
	if normalized_map_name == "":
		normalized_map_name = XIANGQI_MAP_NAME if game_room_id == "xiangqi" else DEFAULT_MAP_NAME
	var room := {
		"id": id,
		"name": "%s房间" % game_type,
		"state": "等待中",
		"type": game_type,
		"players": "0/%d" % player_count,
		"lock": "密码" if password.strip_edges() != "" else "公开",
		"address": "本机",
		"bg": map_background_path_for_game(game_room_id, normalized_map_id),
		"password": password,
		"game_room_id": game_room_id,
		"gameId": game_room_id,
		"min_players": player_count,
		"max_players": player_count,
		"allow_observers": allow_observers,
		"max_observers": clampi(max_observers, 0, 3),
		"max_participants": player_count + clampi(max_observers, 0, 3),
		"map_id": normalized_map_id,
		"map_name": normalized_map_name,
		"enable_timers": bool(normalized_room_options.get("clock_enabled", false)),
	}
	for key in normalized_room_options.keys():
		room[key] = normalized_room_options[key]
	rooms.push_front(room)
	active_room_id = id
	players.clear()
	for i in range(player_count):
		players.append(empty_seat_data(i))
	local_player_index = -1
	system_message = "房间已创建"
	reset_game_flow(game_room_id, normalized_room_options)
	save()
	return room


func reset_game_flow(game_room_id: String = "werewolf", room_options: Dictionary = {}) -> void:
	phase_night = false
	if game_room_id == "xiangqi":
		werewolf = {}
		xiangqi = XiangqiEngineScript.new().default_state(room_options)
	else:
		werewolf = _default_werewolf_state()
		xiangqi = {}
	history.clear()


func push_history(speaker: String, text: String) -> void:
	history.append({
		"speaker": speaker,
		"text": text,
		"at": Time.get_unix_time_from_system(),
	})


func update_active_room_counts() -> void:
	var occupied := 0
	for player in players:
		if String(player.get("owner", "")) != "":
			occupied += 1
	var observers := 0
	for room in rooms:
		if String(room.get("id", "")) == active_room_id:
			var observers_value = room.get("observers", [])
			if observers_value is Array:
				observers = (observers_value as Array).size()
			var max_observers := int(room.get("max_observers", 3))
			var capacity := int(room.get("max_participants", players.size() + max_observers))
			capacity = maxi(capacity, occupied + observers)
			capacity = maxi(capacity, players.size())
			room["max_participants"] = capacity
			room["players"] = "%d/%d" % [occupied + observers, capacity]
			var game_room_id := _game_room_id_for_room(room)
			var game_state := xiangqi if game_room_id == "xiangqi" else werewolf
			if game_room_id == "xiangqi" and String(game_state.get("phase", "lobby")) == "completed":
				room["state"] = "已结束"
			elif game_room_id != "xiangqi" and String(game_state.get("phase", "lobby")) in ["post_game_summary", "mvp_vote", "completed"]:
				room["state"] = "已结束"
			elif bool(game_state.get("started", false)):
				room["state"] = "游戏中"
			else:
				room["state"] = "等待中"
			return


func empty_seat_data(index: int) -> Dictionary:
	return {
		"name": "%d号位" % [index + 1],
		"role": "待加入",
		"avatar": "",
		"state": "可落座",
		"motion": SeatMotion.IDLE,
		"alive": true,
		"ready": false,
		"owner": "",
	}


func _apply_json(data: Dictionary) -> void:
	if int(data.get("state_version", 0)) != STATE_VERSION:
		_apply_defaults()
		save()
		return
	model_configs = _array_or_default(data.get("model_configs"), model_configs)
	voice_configs = _array_or_default(data.get("voice_configs"), voice_configs)
	bot_profiles = _array_or_default(data.get("bot_profiles"), bot_profiles)
	local_nickname = String(data.get("local_nickname", local_nickname))
	_clear_room_runtime_state()


func _array_or_default(value, default_value: Array) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return default_value


func _dict_or_default(value, default_value: Dictionary) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return default_value


func _normalize_rooms() -> void:
	for i in range(rooms.size()):
		if rooms[i] is Dictionary:
			var room: Dictionary = (rooms[i] as Dictionary)
			if not room.has("map_id"):
				room["map_id"] = XIANGQI_MAP_ID if _game_room_id_for_room(room) == "xiangqi" else DEFAULT_MAP_ID
			if not room.has("map_name"):
				room["map_name"] = XIANGQI_MAP_NAME if _game_room_id_for_room(room) == "xiangqi" else DEFAULT_MAP_NAME
			room["bg"] = map_background_path_for_game(_game_room_id_for_room(room), String(room.get("map_id", DEFAULT_MAP_ID)))
			var options := _normalized_room_options(room)
			for key in options.keys():
				room[key] = options[key]


func clear_room_runtime_state() -> void:
	_clear_room_runtime_state()
	save()


func _clear_room_runtime_state() -> void:
	rooms.clear()
	players = _default_players()
	local_player_index = -1
	bot_serial = 1
	phase_night = false
	active_room_id = ""
	system_message = "等待创建房间"
	werewolf = _default_werewolf_state()
	xiangqi = {}
	history.clear()


func map_background_path(map_id: String) -> String:
	return WerewolfAssetCatalogScript.map_background_path(map_id)


func map_background_path_for_game(game_room_id: String, map_id: String) -> String:
	if game_room_id == "xiangqi":
		return XiangqiAssetCatalogScript.map_background_path(map_id)
	return WerewolfAssetCatalogScript.map_background_path(map_id)


func _default_system_voice_config() -> Dictionary:
	return {"id": 0, "key": "voice_system_default", "name": "系统默认", "engine": "local_kokoro", "gender": "女声", "voice": "zf_001", "speed": "0.90", "pitch": "1.00", "volume": "1.00", "enabled": true, "active": true}


func _apply_defaults() -> void:
	rooms = _default_rooms()
	model_configs = _default_model_configs()
	voice_configs = _default_voice_configs()
	bot_profiles = _default_bot_profiles()
	players = _default_players()
	local_player_index = -1
	local_nickname = "阿景"
	bot_serial = 1
	phase_night = false
	active_room_id = ""
	system_message = "等待创建房间"
	werewolf = _default_werewolf_state()
	xiangqi = {}
	history = []


func _default_rooms() -> Array:
	return []


static func default_room_options() -> Dictionary:
	return {
		"game_room_id": "werewolf",
		"timeline_compression_enabled": false,
		"timeline_compression_model": "",
		"timeline_compression_interval": DEFAULT_TIMELINE_COMPRESSION_INTERVAL,
		"timeline_compression_prompt": DEFAULT_TIMELINE_COMPRESSION_PROMPT,
		"bot_max_output_tokens": DEFAULT_ROOM_MAX_OUTPUT_TOKENS,
		"clock_enabled": false,
		"time_limit_ms": 600000,
	}


static func _normalized_room_options(options: Dictionary) -> Dictionary:
	var result := default_room_options()
	var game_room_id := String(options.get("game_room_id", options.get("gameId", result["game_room_id"]))).strip_edges()
	result["game_room_id"] = "xiangqi" if game_room_id == "xiangqi" or game_room_id == "象棋" else "werewolf"
	result["timeline_compression_enabled"] = bool(options.get("timeline_compression_enabled", result["timeline_compression_enabled"]))
	result["timeline_compression_model"] = String(options.get("timeline_compression_model", result["timeline_compression_model"])).strip_edges()
	result["timeline_compression_interval"] = maxi(1, int(options.get("timeline_compression_interval", result["timeline_compression_interval"])))
	var prompt := String(options.get("timeline_compression_prompt", result["timeline_compression_prompt"])).strip_edges()
	result["timeline_compression_prompt"] = prompt if prompt != "" else DEFAULT_TIMELINE_COMPRESSION_PROMPT
	result["bot_max_output_tokens"] = maxi(1, int(options.get("bot_max_output_tokens", result["bot_max_output_tokens"])))
	result["clock_enabled"] = bool(options.get("clock_enabled", options.get("enableTimers", result["clock_enabled"])))
	result["time_limit_ms"] = maxi(60000, int(options.get("time_limit_ms", options.get("timeLimitMs", result["time_limit_ms"]))))
	return result


static func _game_room_id_for_create(game_type: String, room_options: Dictionary = {}) -> String:
	var explicit := String(room_options.get("game_room_id", room_options.get("gameId", ""))).strip_edges()
	if explicit == "xiangqi" or explicit == "象棋":
		return "xiangqi"
	if explicit == "werewolf" or explicit == "狼人杀":
		return "werewolf"
	return "xiangqi" if game_type.strip_edges() == "象棋" else "werewolf"


static func _game_room_id_for_room(room: Dictionary) -> String:
	var explicit := String(room.get("game_room_id", room.get("gameId", ""))).strip_edges()
	if explicit == "xiangqi" or explicit == "象棋":
		return "xiangqi"
	if explicit == "werewolf" or explicit == "狼人杀":
		return "werewolf"
	return "xiangqi" if String(room.get("type", "")).strip_edges() == "象棋" else "werewolf"


func _default_model_configs() -> Array:
	return []


func _default_voice_configs() -> Array:
	return [
		_default_system_voice_config(),
	]


func _default_bot_profiles() -> Array:
	return []


func _default_players() -> Array:
	var seats := []
	for i in range(6):
		seats.append(empty_seat_data(i))
	return seats


func _default_werewolf_state() -> Dictionary:
	return {
		"phase": "lobby",
		"day": 0,
		"started": false,
		"current_action": {},
		"speech_index": -1,
		"night": {},
		"witch_antidote": true,
		"witch_poison": true,
		"map_id": DEFAULT_MAP_ID,
		"map_name": DEFAULT_MAP_NAME,
		"map_scene": "村庄长桌",
		"winner": "",
	}
