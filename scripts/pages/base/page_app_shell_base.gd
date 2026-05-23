extends "res://scripts/room/werewolf/werewolf_room_create_page_flow.gd"

var _scene_root: Control
var _effect_layer: Control


func _build_base() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_bg)

	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tint)

	_scene_root = Control.new()
	_scene_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scene_root)

	_hud_layer = Control.new()
	_hud_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_layer)

	_effect_layer = EffectLayerScript.new()
	_effect_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_effect_layer)

	_modal_layer = Control.new()
	_modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_layer.z_index = 100
	add_child(_modal_layer)


func _clear_scene() -> void:
	for child in _scene_root.get_children():
		child.queue_free()
	for child in _hud_layer.get_children():
		child.queue_free()
	_clear_modal()
	_seat_cards.clear()
	_center_body = null
	if has_method("_clear_system_progress_toast"):
		call("_clear_system_progress_toast")
	if has_method("_clear_center_speech_display"):
		call("_clear_center_speech_display")
	_ready_button = null
	_start_button = null
	_pause_button = null
	_observer_bar = null


func _clear_modal() -> void:
	for child in _modal_layer.get_children():
		child.queue_free()
	_clear_scan_overlay_refs()


func _show_lobby() -> void:
	_mode = Mode.LOBBY
	_clear_scene()
	navigate_requested.emit("lobby", {})


func _enter_table() -> void:
	_play_click()
	_bind_state()
	if has_method("_initialize_controlled_bot_model_profiles"):
		call("_initialize_controlled_bot_model_profiles", "enter_table", true)
	navigate_requested.emit("table", {})
	_show_table()


func _show_table() -> void:
	_mode = Mode.TABLE
	_clear_scene()
	navigate_requested.emit("table", {})


func _build_table_hud() -> void:
	pass


func _flash_effect(kind: String) -> void:
	_effect_layer.play(kind)
