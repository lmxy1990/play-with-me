extends RefCounted

const WerewolfHumanPlayerFactoryScript := preload("res://scripts/player/werewolf/human/werewolf_human_player_factory.gd")
const WerewolfAiPlayerFactoryScript := preload("res://scripts/player/werewolf/ai/werewolf_ai_player_factory.gd")

var _werewolf_human_factory = WerewolfHumanPlayerFactoryScript.new()
var _werewolf_ai_factory = WerewolfAiPlayerFactoryScript.new()


func self_player(participant_id: String, display_name: String, idle_motion: int = 0) -> Dictionary:
	return _werewolf_human_factory.self_player(participant_id, display_name, idle_motion)


func self_player_from_identity(participant_id: String, identity: Dictionary, room_players: Array = [], ignore_index: int = -1, idle_motion: int = 0) -> Dictionary:
	var initialized := _initialized_player_identity(identity, room_players, ignore_index, "玩家")
	return _werewolf_human_factory.self_player_from_identity(participant_id, initialized, idle_motion)


func human_player(participant_id: String, display_name: String, idle_motion: int = 0) -> Dictionary:
	return _werewolf_human_factory.human_player(participant_id, display_name, idle_motion)


func human_player_from_identity(participant_id: String, identity: Dictionary, room_players: Array = [], ignore_index: int = -1, idle_motion: int = 0) -> Dictionary:
	var initialized := _initialized_player_identity(identity, room_players, ignore_index, "玩家")
	return _werewolf_human_factory.human_player_from_identity(participant_id, initialized, idle_motion)


func bot_player(bot_serial: int, bot_name: String, controller_participant_id: String, idle_motion: int = 0) -> Dictionary:
	return _werewolf_ai_factory.bot_player(bot_serial, bot_name, controller_participant_id, idle_motion)


func bot_player_from_profile(bot_serial: int, profile: Dictionary, controller_participant_id: String, room_players: Array = [], ignore_index: int = -1, idle_motion: int = 0) -> Dictionary:
	var initialized := _initialized_bot_identity(profile, room_players, ignore_index, bot_serial)
	return _werewolf_ai_factory.bot_player_from_identity(bot_serial, initialized, controller_participant_id, idle_motion)


func empty_seat(index: int, idle_motion: int = 0) -> Dictionary:
	return _werewolf_human_factory.empty_seat(index, idle_motion)


func visible_role_for_player(player: Dictionary) -> String:
	return _werewolf_human_factory.visible_role_for_player(player)


func room_unique_name(base_name: String, room_players: Array, ignore_index: int = -1, fallback: String = "玩家") -> String:
	var clean := base_name.strip_edges()
	if clean == "":
		clean = fallback
	var existing := {}
	for i in range(room_players.size()):
		if i == ignore_index or not (room_players[i] is Dictionary):
			continue
		var player: Dictionary = room_players[i]
		if String(player.get("owner", "")).strip_edges() == "":
			continue
		var name := String(player.get("name", player.get("displayName", ""))).strip_edges()
		if name != "":
			existing[name] = true
	if not existing.has(clean):
		return clean
	var serial := 2
	while existing.has("%s %d" % [clean, serial]):
		serial += 1
	return "%s %d" % [clean, serial]


func _initialized_player_identity(identity: Dictionary, room_players: Array, ignore_index: int, fallback_name: String) -> Dictionary:
	var result := _normalized_identity(identity, fallback_name)
	result["name"] = room_unique_name(String(result.get("name", "")), room_players, ignore_index, fallback_name)
	result["displayName"] = result["name"]
	return result


func _initialized_bot_identity(profile: Dictionary, room_players: Array, ignore_index: int, bot_serial: int) -> Dictionary:
	var fallback := "机器人%d" % bot_serial
	var result := _normalized_identity(profile, fallback)
	result["name"] = room_unique_name(String(result.get("name", "")), room_players, ignore_index, fallback)
	result["displayName"] = result["name"]
	if String(result.get("avatar", "")).strip_edges() == "":
		result["avatar"] = String(profile.get("avatar_path", profile.get("avatarPath", ""))).strip_edges()
	if String(result.get("voice", "")).strip_edges() == "":
		result["voice"] = String(profile.get("voice", profile.get("voiceName", ""))).strip_edges()
	return result


func _normalized_identity(identity: Dictionary, fallback_name: String) -> Dictionary:
	var name := String(identity.get("name", identity.get("display_name", identity.get("displayName", identity.get("nickname", ""))))).strip_edges()
	if name == "":
		name = fallback_name
	var avatar_id := String(identity.get("avatar_id", identity.get("avatarId", ""))).strip_edges()
	var avatar := String(identity.get("avatar", identity.get("avatar_path", identity.get("avatarPath", "")))).strip_edges()
	var voice_config_id := String(identity.get("voice_config_id", identity.get("voiceConfigId", identity.get("playback_voice_config_id", identity.get("playbackVoiceConfigId", ""))))).strip_edges()
	return {
		"name": name,
		"displayName": name,
		"avatar_id": avatar_id,
		"avatarId": avatar_id,
		"avatar": avatar,
		"voice_config_id": voice_config_id,
		"voiceConfigId": voice_config_id,
		"playback_voice_config_id": voice_config_id,
		"playbackVoiceConfigId": voice_config_id,
		"voice": String(identity.get("voice", identity.get("voiceName", ""))).strip_edges(),
	}
