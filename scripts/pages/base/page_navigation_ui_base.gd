extends "res://scripts/pages/base/page_app_state_bridge_base.gd"

@export_enum("lobby", "table", "preferences", "model_config", "voice_config", "bot_config", "replay") var initial_route := "lobby"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_apply_mobile_orientation()
	call("_ensure_scan_join_ui")
	_connect_model_clients()
	_ensure_device_identity_loaded()
	call("_setup_android_qr_scanner")
	_bind_state()
	call("_setup_room_discovery")
	_build_base()
	_setup_click_sound()
	_setup_tts_runtime()
	_show_initial_route()


func _show_initial_route() -> void:
	match initial_route:
		"table":
			call("_show_table")
		"preferences":
			call("_show_preferences_page")
		"model_config":
			call("_show_model_config_page")
		"voice_config":
			call("_show_voice_config_page")
		"bot_config":
			call("_show_bot_config_page")
		"replay":
			call("_show_replay_page")
		_:
			call("_show_lobby")


func _process(delta: float) -> void:
	for seat in _seat_cards:
		seat.tick(delta)
	_effect_layer.tick(delta)
	call("_tick_room_discovery", delta)
	call("_tick_scan_join_animation", delta)


func _exit_tree() -> void:
	_disconnect_model_clients()
	_disconnect_android_qr_scanner()
	_disconnect_tts_runtime()
	_disconnect_room_network_signals()
	if _scan_join_ui != null:
		_scan_join_ui.clear()
		_scan_join_ui.setup(null)
	if _tts_voice_catalog != null:
		_tts_voice_catalog.set_runtime(null)
	if _click_player != null:
		_click_player.stop()
		_click_player.stream = null
	if _tts_runtime != null:
		_tts_runtime.stop()
	_room_discovery.stop()
	if _owns_room_network_session and _room_network_session != null:
		_room_network_session.stop()



