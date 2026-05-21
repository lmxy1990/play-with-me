extends RefCounted

const MapCatalogScript := preload("res://scripts/room/werewolf/werewolf_map_catalog.gd")
const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")

const BG_LOBBY := "res://assets/images/werewolf/backgrounds/lobby.png"
const BG_DAY := "res://assets/images/werewolf/backgrounds/day.png"
const BG_NIGHT := "res://assets/images/werewolf/backgrounds/night_soft_village.png"
const BG_MAP_BASIC := "res://assets/images/werewolf/backgrounds/map_basic.png"

const ACTIONS := {
	"inspect": "res://assets/images/werewolf/actions/inspect.png",
	"vote": "res://assets/images/werewolf/actions/vote.png",
	"kill": "res://assets/images/werewolf/actions/kill.png",
	"guard": "res://assets/images/werewolf/actions/guard.png",
	"potion": "res://assets/images/werewolf/actions/potion.png",
	"skip": "res://assets/images/werewolf/actions/skip.png",
	"speech": "res://assets/images/werewolf/actions/speech.png",
	"dead_avatar": "res://assets/images/werewolf/actions/dead_avatar.png",
	"pencil": "res://assets/images/werewolf/actions/pencil.png",
	"seat": "res://assets/images/werewolf/actions/seat.png",
	"bot": "res://assets/images/werewolf/actions/bot.png",
	"create_room": "res://assets/images/werewolf/actions/create_room.svg",
	"scan_join": "res://assets/images/werewolf/actions/scan_join.svg",
	"refresh_rooms": "res://assets/images/werewolf/actions/refresh_rooms.svg",
	"reconnect": "res://assets/images/werewolf/actions/reconnect.svg",
	"model_config": "res://assets/images/werewolf/actions/model_config.svg",
	"brain": "res://assets/images/werewolf/actions/brain.svg",
	"voice_config": "res://assets/images/werewolf/actions/voice_config.svg",
	"speaker": "res://assets/images/werewolf/actions/speaker.svg",
	"key": "res://assets/images/werewolf/actions/key.svg",
	"preferences": "res://assets/images/werewolf/actions/preferences.svg",
	"badge_sheriff": "res://assets/images/werewolf/actions/badge_sheriff.svg",
	"badge_guard": "res://assets/images/werewolf/actions/badge_guard.svg",
	"badge_mvp": "res://assets/images/werewolf/actions/badge_mvp.svg",
}

const AVATARS := {
	"wolf": "res://assets/images/werewolf/avatars/wolf.png",
	"villager": "res://assets/images/werewolf/avatars/villager.png",
	"seer": "res://assets/images/werewolf/avatars/seer.png",
	"witch": "res://assets/images/werewolf/avatars/witch.png",
	"hunter": "res://assets/images/werewolf/avatars/hunter.png",
	"guard": "res://assets/images/werewolf/avatars/roles/guard.png",
	"sheriff": "res://assets/images/werewolf/avatars/sheriff.png",
	"bot": "res://assets/images/werewolf/avatars/robot.png",
}


static func lobby_background_path() -> String:
	return BG_LOBBY


static func day_background_path() -> String:
	return BG_DAY


static func night_background_path() -> String:
	return BG_NIGHT


static func map_background_path(map_id: String) -> String:
	var path := String(MapCatalogScript.new().map_background_path(map_id)).strip_edges()
	if path != "":
		return path
	return BG_MAP_BASIC


static func room_background_path(room: Dictionary) -> String:
	var map_id := String(room.get("map_id", room.get("mapId", ""))).strip_edges()
	if map_id != "":
		return map_background_path(map_id)
	var bg_path := String(room.get("bg", "")).strip_edges()
	if bg_path != "":
		return bg_path
	return BG_LOBBY


static func action_path(action_id: String) -> String:
	var key := action_id.strip_edges()
	if ACTIONS.has(key):
		return String(ACTIONS[key])
	return ""


static func avatar_path(avatar_id: String) -> String:
	var key := avatar_id.strip_edges()
	if AVATARS.has(key):
		return String(AVATARS[key])
	var role_avatar := String(RoleCatalogScript.new().role_avatar(key)).strip_edges()
	if role_avatar != "":
		return role_avatar
	return String(AVATARS["villager"])


static func bot_avatar_paths() -> Array:
	return [
		avatar_path("bot"),
		avatar_path("bot"),
		avatar_path("bot"),
		avatar_path("bot"),
	]
