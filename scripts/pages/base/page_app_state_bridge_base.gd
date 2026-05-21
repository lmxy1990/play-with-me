extends "res://scripts/pages/base/page_app_shell_base.gd"


func set_app_state(state) -> void:
	_app_state = state
	_bind_state()


func set_android_qr_scanner(scanner) -> void:
	_disconnect_android_qr_scanner()
	_android_qr_scanner = scanner
	call("_setup_android_qr_scanner")


func _bind_state() -> void:
	if _app_state == null:
		return
	_device_identity.persistence_enabled = bool(_app_state.persistence_enabled)
	_room_session_store.persistence_enabled = bool(_app_state.persistence_enabled)
	_model_config_store.persistence_enabled = bool(_app_state.persistence_enabled)
	_tts_voice_repository.set_persistence_enabled(bool(_app_state.persistence_enabled))
	_room_replica_store.persistence_enabled = bool(_app_state.persistence_enabled)
	_room_replica_store.load_or_create()
	_rooms = _app_state.rooms
	_model_configs = _normalize_model_configs(_app_state.model_configs)
	_load_model_configs_from_storage()
	_voice_configs = _app_state.voice_configs
	_load_voice_configs_from_storage()
	_request_android_config_storage_deferred_load()
	_bot_profiles = _bot_profile_repository.load_or_seed(_app_state.bot_profiles)
	_bot_facade.configure(_bot_profile_repository, _memory_manager)
	_main_ui_debug("bind_state rooms=%d models=%d voices=%d bot_profiles=%d players=%d active_room=%s" % [
		_rooms.size(),
		_model_configs.size(),
		_voice_configs.size(),
		_bot_profiles.size(),
		_app_state.players.size(),
		String(_app_state.active_room_id),
	])
	_players = _app_state.players
	_local_player_index = _app_state.local_player_index
	_local_nickname = _app_state.local_nickname
	_apply_preference_identity_to_runtime()
	_bot_serial = _app_state.bot_serial
	_phase_night = _app_state.phase_night
	_system_message = _app_state.system_message
	_werewolf = _app_state.werewolf
	_history = _app_state.history
	_ensure_memory_loaded()


func _commit_state() -> void:
	if _app_state == null:
		return
	_app_state.rooms = _rooms
	_app_state.model_configs = _normalize_model_configs(_model_configs)
	_voice_configs = _tts_voice_repository.list_profiles()
	if _voice_configs.is_empty():
		_voice_configs = _normalize_voice_configs(_voice_configs)
	_app_state.voice_configs = _voice_configs
	_app_state.bot_profiles = _bot_profile_repository.set_profiles(_bot_profiles)
	_main_ui_debug("commit_state rooms=%d models=%d voices=%d bot_profiles=%d players=%d active_room=%s" % [
		_rooms.size(),
		_model_configs.size(),
		_voice_configs.size(),
		_bot_profiles.size(),
		_players.size(),
		String(_app_state.active_room_id),
	])
	_app_state.players = _players
	_app_state.local_player_index = _local_player_index
	_app_state.local_nickname = _local_nickname
	_app_state.bot_serial = _bot_serial
	_app_state.phase_night = _phase_night
	_app_state.system_message = _system_message
	_app_state.werewolf = _werewolf
	_app_state.history = _history
	_app_state.update_active_room_counts()
	_app_state.save()
	if not _applying_network_snapshot:
		call("_broadcast_network_snapshot")


func _main_ui_debug(message: String) -> void:
	if OS.is_debug_build():
		if OS.is_debug_build():
			print("[MainUI][debug] %s" % message)
