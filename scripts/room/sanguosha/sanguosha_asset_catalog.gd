extends RefCounted
class_name SanguoshaAssetCatalog

const CardCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_card_catalog.gd")
const GeneralCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_general_catalog.gd")

const CARD_BACK := "res://assets/images/sanguosha/cards/card_back.png"
const TABLE_BACKGROUND := "res://assets/images/werewolf/backgrounds/map_basic.png"


static func card_back_path() -> String:
	return CARD_BACK


static func card_asset_path(template_id: String) -> String:
	return CardCatalogScript.new().card_asset_path(template_id)


static func general_asset_path(general_id: String) -> String:
	return GeneralCatalogScript.new().general_asset_path(general_id)


static func table_background_path() -> String:
	return TABLE_BACKGROUND


static func lobby_background_path() -> String:
	return TABLE_BACKGROUND


static func map_background_path(_map_id: String) -> String:
	return TABLE_BACKGROUND


static func room_background_path(_room: Dictionary) -> String:
	return TABLE_BACKGROUND
