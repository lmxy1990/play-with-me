extends RefCounted

const AiPlayerControllerScript := preload("res://scripts/player/ai/ai_player_controller.gd")
const WerewolfAssetCatalogScript := preload("res://scripts/room/werewolf/werewolf_asset_catalog.gd")

var _ai_controller = AiPlayerControllerScript.new()


func bot_player(bot_serial: int, bot_name: String, controller_participant_id: String, idle_motion: int = 0) -> Dictionary:
	var avatars := WerewolfAssetCatalogScript.bot_avatar_paths()
	var avatar_index := _ai_controller.avatar_index_for_bot(bot_serial, avatars.size())
	return {
		"id": _ai_controller.player_id_for_bot(bot_serial),
		"name": bot_name,
		"role": "未知",
		"role_key": "",
		"avatar": avatars[avatar_index],
		"state": "已准备",
		"motion": idle_motion,
		"alive": true,
		"ready": true,
		"owner": "human",
		"participant_id": "",
		"controller_participant_id": controller_participant_id,
	}

