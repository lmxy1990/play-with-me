extends RefCounted

const AiPlayerControllerScript := preload("res://scripts/player/ai/ai_player_controller.gd")

var _ai_controller = AiPlayerControllerScript.new()


func bot_player(bot_serial: int, bot_name: String, controller_participant_id: String, idle_motion: int = 0) -> Dictionary:
	return bot_player_from_identity(bot_serial, {"name": bot_name}, controller_participant_id, idle_motion)


func bot_player_from_identity(bot_serial: int, identity: Dictionary, controller_participant_id: String, idle_motion: int = 0) -> Dictionary:
	var name := String(identity.get("name", identity.get("displayName", "机器人%d" % bot_serial))).strip_edges()
	if name == "":
		name = "机器人%d" % bot_serial
	var avatar_path := String(identity.get("avatar", identity.get("avatar_path", identity.get("avatarPath", "")))).strip_edges()
	var voice_name := String(identity.get("voice", identity.get("voiceName", ""))).strip_edges()
	var voice_config_id := String(identity.get("voice_config_id", identity.get("voiceConfigId", identity.get("playback_voice_config_id", identity.get("playbackVoiceConfigId", ""))))).strip_edges()
	var payload := {
		"id": _ai_controller.player_id_for_bot(bot_serial),
		"name": name,
		"role": "棋手",
		"role_key": "",
		"avatar": avatar_path,
		"base_avatar": avatar_path,
		"state": "已准备",
		"motion": idle_motion,
		"alive": true,
		"ready": true,
		"owner": "human",
		"participant_id": "",
		"controller_participant_id": controller_participant_id,
		"player_type": "ai",
		"player_module": "xiangqi_ai",
		"game_id": "xiangqi",
	}
	var avatar_id := String(identity.get("avatar_id", identity.get("avatarId", ""))).strip_edges()
	if avatar_id != "":
		payload["avatar_id"] = avatar_id
		payload["avatarId"] = avatar_id
	var model_name := String(identity.get("model", identity.get("modelName", identity.get("model_name", "")))).strip_edges()
	if model_name != "":
		payload["model"] = model_name
	if voice_name != "":
		payload["voice"] = voice_name
		payload["voiceName"] = voice_name
	if voice_config_id != "":
		payload["voice_config_id"] = voice_config_id
		payload["voiceConfigId"] = voice_config_id
		payload["playback_voice_config_id"] = voice_config_id
		payload["playbackVoiceConfigId"] = voice_config_id
	return payload
