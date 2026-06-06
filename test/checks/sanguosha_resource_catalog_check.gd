extends SceneTree

const CardCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_card_catalog.gd")
const GeneralCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_general_catalog.gd")
const AssetCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_asset_catalog.gd")


func _init() -> void:
	var cards = CardCatalogScript.new()
	var generals = GeneralCatalogScript.new()
	var assets = AssetCatalogScript.new()

	_expect(cards.card_count() == 108, "standard_108 should contain 108 game cards")
	var type_counts: Dictionary = cards.counts_by_type()
	_expect(int(type_counts.get("basic", 0)) == 53, "standard_108 basic count should be 53")
	_expect(int(type_counts.get("trick", 0)) == 36, "standard_108 trick count should be 36")
	_expect(int(type_counts.get("equip", 0)) == 19, "standard_108 equip count should be 19")

	var key_counts: Dictionary = cards.counts_by_card_key()
	_expect(int(key_counts.get("slash", 0)) == 30, "standard_108 slash count should be 30")
	_expect(int(key_counts.get("dodge", 0)) == 15, "standard_108 dodge count should be 15")
	_expect(int(key_counts.get("peach", 0)) == 8, "standard_108 peach count should be 8")

	_expect(generals.general_count() == 25, "standard core general count should be 25")
	_expect(generals.skills().size() > 0, "standard skills should be present")
	var card_asset_path := assets.card_asset_path("std_001")
	var general_asset_path := assets.general_asset_path("shu_liubei")
	_expect(card_asset_path.ends_with(".png"), "card asset lookup should return png")
	_expect(general_asset_path.ends_with(".png"), "general asset lookup should return png")
	_expect(FileAccess.file_exists(card_asset_path), "card png asset should exist")
	_expect(FileAccess.file_exists(assets.card_back_path()), "card back png asset should exist")

	print("sanguosha_resource_catalog_check passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		assert(false, message)
