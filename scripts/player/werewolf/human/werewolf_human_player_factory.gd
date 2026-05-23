extends RefCounted

const HumanPlayerControllerScript := preload("res://scripts/player/human/human_player_controller.gd")
const WerewolfAssetCatalogScript := preload("res://scripts/room/werewolf/werewolf_asset_catalog.gd")

var _human_controller = HumanPlayerControllerScript.new()


func self_player(participant_id: String, display_name: String, idle_motion: int = 0) -> Dictionary:
	return self_player_from_identity(participant_id, {"name": display_name}, idle_motion)


func self_player_from_identity(participant_id: String, identity: Dictionary, idle_motion: int = 0) -> Dictionary:
	return _human_player_payload(participant_id, identity, "self", idle_motion)


func human_player(participant_id: String, display_name: String, idle_motion: int = 0) -> Dictionary:
	return human_player_from_identity(participant_id, {"name": display_name}, idle_motion)


func human_player_from_identity(participant_id: String, identity: Dictionary, idle_motion: int = 0) -> Dictionary:
	return _human_player_payload(participant_id, identity, "human", idle_motion)


func _human_player_payload(participant_id: String, identity: Dictionary, owner: String, idle_motion: int) -> Dictionary:
	var avatar_path := String(identity.get("avatar", "")).strip_edges()
	if avatar_path == "":
		avatar_path = WerewolfAssetCatalogScript.avatar_path("villager")
	var voice_config_id := String(identity.get("voice_config_id", identity.get("voiceConfigId", identity.get("playback_voice_config_id", identity.get("playbackVoiceConfigId", ""))))).strip_edges()
	var payload := {
		"id": "self",
		"participant_id": participant_id,
		"name": _human_controller.display_name_or_fallback(String(identity.get("name", identity.get("displayName", ""))), "玩家"),
		"role": "未知",
		"avatar": avatar_path,
		"base_avatar": avatar_path,
		"state": "等待",
		"motion": idle_motion,
		"alive": true,
		"ready": false,
		"owner": owner,
	}
	if owner != "self":
		payload["id"] = participant_id
	var avatar_id := String(identity.get("avatar_id", identity.get("avatarId", ""))).strip_edges()
	if avatar_id != "":
		payload["avatar_id"] = avatar_id
		payload["avatarId"] = avatar_id
	if voice_config_id != "":
		payload["voice_config_id"] = voice_config_id
		payload["voiceConfigId"] = voice_config_id
		payload["playback_voice_config_id"] = voice_config_id
		payload["playbackVoiceConfigId"] = voice_config_id
	return payload


func empty_seat(index: int, idle_motion: int = 0) -> Dictionary:
	return {
		"name": "%d号位" % [index + 1],
		"role": "待加入",
		"avatar": "",
		"state": "可落座",
		"motion": idle_motion,
		"alive": true,
		"ready": false,
		"owner": "",
	}


func visible_role_for_player(player: Dictionary) -> String:
	var owner := String(player.get("owner", ""))
	if owner == "":
		return "空位"
	if owner == "self" or bool(player.get("role_visible", false)) or bool(player.get("idiot_revealed", false)) or bool(player.get("public_role_visible", false)):
		return String(player.get("role", "未知"))
	return "未知"
