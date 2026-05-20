extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")
const PreferenceRepositoryScript := preload("res://scripts/core/preferences/preference_repository.gd")
const LobbyScene := preload("res://scenes/lobby.tscn")
const PreferencesScene := preload("res://scenes/preferences.tscn")


func _initialize() -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	var repository = PreferenceRepositoryScript.new()
	repository.persistence_enabled = false
	assert(bool(repository.ensure_preferences().get("ok", false)))

	var page := PreferencesScene.instantiate() as Control
	page.set_preference_repository(repository)
	page.set_app_state(state)
	root.add_child(page)
	await process_frame

	var nickname_input := page.find_child("PreferenceNicknameInput", true, false) as LineEdit
	assert(nickname_input != null)
	assert(nickname_input.text.strip_edges() != "")
	var avatar_picker_button := page.find_child("PreferenceAvatarPickerButton", true, false) as Button
	assert(avatar_picker_button != null)
	avatar_picker_button.pressed.emit()
	await process_frame
	var avatar_scroll := page.find_child("PreferenceAvatarPickerScroll", true, false) as ScrollContainer
	assert(avatar_scroll != null)
	var avatar_grid := page.find_child("PreferenceAvatarGrid", true, false) as GridContainer
	assert(avatar_grid != null)
	assert(avatar_grid.get_child_count() == 24)
	var private_key_line := page.find_child("PreferenceDevicePrivateKey", true, false) as LineEdit
	assert(private_key_line != null)
	assert(not private_key_line.editable)
	assert(private_key_line.secret)
	var playback_voice_dropdown := page.find_child("PreferencePlaybackVoiceDropdown", true, false) as OptionButton
	assert(playback_voice_dropdown != null)
	assert(playback_voice_dropdown.get_item_count() >= 1)
	assert(String(playback_voice_dropdown.get_item_metadata(playback_voice_dropdown.selected)) == "voice_system_default")

	page._save_preference_nickname("  偏好玩家  ")
	await process_frame
	var state_after_name: Dictionary = repository.get_preferences().get("state", {})
	assert(String(state_after_name.get("nickname", "")) == "偏好玩家")
	assert(String(state.local_nickname) == "偏好玩家")

	page._save_preference_avatar("person_girl_06")
	await process_frame
	var state_after_avatar: Dictionary = repository.get_preferences().get("state", {})
	assert(String(state_after_avatar.get("avatar_id", "")) == "person_girl_06")
	avatar_picker_button = page.find_child("PreferenceAvatarPickerButton", true, false) as Button
	assert(avatar_picker_button != null)

	page._save_preference_playback_voice_config("voice_system_default")
	await process_frame
	var state_after_voice: Dictionary = repository.get_preferences().get("state", {})
	assert(String(state_after_voice.get("playback_voice_config_id", "")) == "voice_system_default")

	page._toggle_device_key_visible()
	await process_frame
	private_key_line = page.find_child("PreferenceDevicePrivateKey", true, false) as LineEdit
	assert(private_key_line != null)
	assert(not private_key_line.editable)
	assert(not private_key_line.secret)

	page.queue_free()
	await process_frame

	var lobby := LobbyScene.instantiate() as Control
	lobby.set_app_state(state)
	root.add_child(lobby)
	await process_frame
	assert(_has_button_tooltip(lobby, "偏好设置"))
	lobby.queue_free()
	await process_frame
	quit()


func _has_button_tooltip(node: Node, tooltip: String) -> bool:
	if node is Button and String((node as Button).tooltip_text) == tooltip:
		return true
	for child in node.get_children():
		if _has_button_tooltip(child, tooltip):
			return true
	return false
