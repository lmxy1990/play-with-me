extends "res://scripts/pages/base/page_tts_history_ui_base.gd"

const BotProfileRepositoryScript := preload("res://scripts/core/bot/bot_profile_repository.gd")
const BotCapabilityFacadeScript := preload("res://scripts/core/bot/bot_capability_facade.gd")
const MemoryManagerScript := preload("res://scripts/core/memory/memory_manager.gd")

var _bot_profile_repository = BotProfileRepositoryScript.new()
var _bot_facade = BotCapabilityFacadeScript.new()
var _memory_manager = MemoryManagerScript.new()
var _memory_load_deferred_requested := false
var _bot_profiles := []


func _bot_profile_by_key_for_controlled_player(profile_id: String) -> Dictionary:
	if _bot_profile_repository == null:
		return {}
	return _bot_profile_repository.profile_by_key(profile_id)


func _ensure_memory_loaded() -> void:
	if _app_state != null:
		_memory_manager.persistence_enabled = bool(_app_state.persistence_enabled)
	_memory_manager.load_or_create()
	if OS.get_name() == "Android" and not _memory_load_deferred_requested:
		_memory_load_deferred_requested = true
		call_deferred("_ensure_memory_loaded_after_android_singleton")


func _ensure_memory_loaded_after_android_singleton() -> void:
	_memory_manager.load_or_create()
