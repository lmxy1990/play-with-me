extends "res://scripts/ui/base/page_ui_base.gd"

const WerewolfAssetCatalogScript := preload("res://scripts/room/werewolf/werewolf_asset_catalog.gd")
const XiangqiAssetCatalogScript := preload("res://scripts/room/xiangqi/xiangqi_asset_catalog.gd")


func _lobby_background_path() -> String:
	return WerewolfAssetCatalogScript.lobby_background_path()


func _day_background_path() -> String:
	return WerewolfAssetCatalogScript.day_background_path()


func _night_background_path() -> String:
	return WerewolfAssetCatalogScript.night_background_path()


func _werewolf_action_path(action_id: String) -> String:
	return WerewolfAssetCatalogScript.action_path(action_id)


func _werewolf_avatar_path(avatar_id: String) -> String:
	return WerewolfAssetCatalogScript.avatar_path(avatar_id)


func _werewolf_bot_avatar_paths() -> Array:
	return WerewolfAssetCatalogScript.bot_avatar_paths()


func _map_background_path(map_id: String) -> String:
	return WerewolfAssetCatalogScript.map_background_path(map_id)


func _room_background_path(room: Dictionary) -> String:
	var game_id := String(room.get("game_room_id", room.get("gameId", ""))).strip_edges()
	if game_id == "xiangqi" or game_id == "象棋" or String(room.get("type", "")).strip_edges() == "象棋":
		return XiangqiAssetCatalogScript.room_background_path(room)
	return WerewolfAssetCatalogScript.room_background_path(room)


func _action_icon(path: String, size_px: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _texture(path)
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return icon


func _action_effect_kind(action: String) -> String:
	match action:
		"查验":
			return "inspect"
		"投票", "警长", "MVP":
			return "vote"
		"发言顺序":
			return "speech"
		"刀人", "开枪":
			return "kill"
		"守护":
			return "guard"
		"用药":
			return "potion"
		"跳过":
			return "skip"
		_:
			return "action"
