extends RefCounted

const HumanPlayerControllerScript := preload("res://scripts/player/human/human_player_controller.gd")
const WerewolfAssetCatalogScript := preload("res://scripts/room/werewolf/werewolf_asset_catalog.gd")

var _human_controller = HumanPlayerControllerScript.new()


func self_player(participant_id: String, display_name: String, idle_motion: int = 0) -> Dictionary:
	return {
		"id": "self",
		"participant_id": participant_id,
		"name": _human_controller.display_name_or_fallback(display_name, "玩家"),
		"role": "未知",
		"avatar": WerewolfAssetCatalogScript.avatar_path("villager"),
		"state": "等待",
		"motion": idle_motion,
		"alive": true,
		"ready": false,
		"owner": "self",
	}


func human_player(participant_id: String, display_name: String, idle_motion: int = 0) -> Dictionary:
	return {
		"id": participant_id,
		"participant_id": participant_id,
		"name": _human_controller.display_name_or_fallback(display_name, "玩家"),
		"role": "未知",
		"avatar": WerewolfAssetCatalogScript.avatar_path("villager"),
		"state": "等待",
		"motion": idle_motion,
		"alive": true,
		"ready": false,
		"owner": "human",
	}


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
