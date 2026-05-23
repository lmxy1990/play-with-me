extends RefCounted

const AiPlayerControllerScript := preload("res://scripts/player/ai/ai_player_controller.gd")
const WerewolfAssetCatalogScript := preload("res://scripts/room/werewolf/werewolf_asset_catalog.gd")

var _ai_controller = AiPlayerControllerScript.new()


func bot_player(bot_serial: int, bot_name: String, controller_participant_id: String, idle_motion: int = 0) -> Dictionary:
	return bot_player_from_identity(bot_serial, {"name": bot_name}, controller_participant_id, idle_motion)


func bot_player_from_identity(bot_serial: int, identity: Dictionary, controller_participant_id: String, idle_motion: int = 0) -> Dictionary:
	var avatars := WerewolfAssetCatalogScript.bot_avatar_paths()
	var avatar_index := _ai_controller.avatar_index_for_bot(bot_serial, avatars.size())
	var avatar_path := String(identity.get("avatar", "")).strip_edges()
	if avatar_path == "":
		avatar_path = avatars[avatar_index]
	var voice_name := String(identity.get("voice", identity.get("voiceName", ""))).strip_edges()
	var payload := {
		"id": _ai_controller.player_id_for_bot(bot_serial),
		"name": String(identity.get("name", identity.get("displayName", "机器人%d" % bot_serial))).strip_edges(),
		"role": "未知",
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
	}
	var avatar_id := String(identity.get("avatar_id", identity.get("avatarId", ""))).strip_edges()
	if avatar_id != "":
		payload["avatar_id"] = avatar_id
		payload["avatarId"] = avatar_id
	if voice_name != "":
		payload["voice"] = voice_name
		payload["voiceName"] = voice_name
	return payload
