extends "res://scripts/pages/base/page_book_ui_base.gd"

signal navigate_requested(route: String, payload: Dictionary)


func _open_model_config() -> void:
	navigate_requested.emit("model_config", {})
	_show_model_config_page()


func _open_voice_config() -> void:
	navigate_requested.emit("voice_config", {})
	_show_voice_config_page()


func _open_bot_config() -> void:
	navigate_requested.emit("bot_config", {})
	_show_bot_config_page()


func _open_preferences() -> void:
	navigate_requested.emit("preferences", {})
	_show_preferences_page()


func _show_model_config_page(edit_index: int = -2) -> void:
	navigate_requested.emit("model_config", {"edit_index": edit_index})


func _show_preferences_page() -> void:
	navigate_requested.emit("preferences", {})


func _show_voice_config_page(edit_index: int = -2) -> void:
	navigate_requested.emit("voice_config", {"edit_index": edit_index})


func _show_bot_config_page(edit_index: int = -2) -> void:
	navigate_requested.emit("bot_config", {"edit_index": edit_index})


func _show_replay_page() -> void:
	navigate_requested.emit("replay", {})
