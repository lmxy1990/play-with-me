extends "res://scripts/pages/base/page_audio_ui_base.gd"

const TtsRuntimeScript := preload("res://scripts/core/tts/tts_runtime.gd")
const TtsVoiceProfileRepositoryScript := preload("res://scripts/core/tts/voice_profile_repository.gd")
const TtsVoiceCatalogScript := preload("res://scripts/core/tts/voice_catalog.gd")
const TtsVoicePreviewControllerScript := preload("res://scripts/core/tts/voice_preview_controller.gd")

var _tts_runtime
var _tts_voice_repository = TtsVoiceProfileRepositoryScript.new()
var _tts_voice_catalog = TtsVoiceCatalogScript.new()
var _tts_voice_preview_controller = TtsVoicePreviewControllerScript.new()
var _voice_configs := [
	{"id": 0, "key": "voice_system_default", "name": "系统默认", "engine": "local_kokoro", "gender": "女声", "voice": "zf_001", "speed": "0.90", "pitch": "1.00", "volume": "1.00", "enabled": true, "active": true},
]
var _voice_preview_button: Button
var _voice_preview_status_label: Label
var _voice_preview_text_label: RichTextLabel
var _voice_preview_progress_supported := false
var _voice_preview_tween: Tween


func _disconnect_tts_runtime() -> void:
	if _tts_runtime == null:
		return
	var speech_started := Callable(self, "_on_tts_speech_started")
	var speech_progress := Callable(self, "_on_tts_speech_progress")
	var speech_finished := Callable(self, "_on_tts_speech_finished")
	var speech_failed := Callable(self, "_on_tts_speech_failed")
	if _tts_runtime.speech_started.is_connected(speech_started):
		_tts_runtime.speech_started.disconnect(speech_started)
	if _tts_runtime.speech_progress.is_connected(speech_progress):
		_tts_runtime.speech_progress.disconnect(speech_progress)
	if _tts_runtime.speech_finished.is_connected(speech_finished):
		_tts_runtime.speech_finished.disconnect(speech_finished)
	if _tts_runtime.speech_failed.is_connected(speech_failed):
		_tts_runtime.speech_failed.disconnect(speech_failed)


func _setup_tts_runtime() -> void:
	if _tts_runtime != null:
		_tts_voice_catalog.set_runtime(_tts_runtime)
		return
	_tts_runtime = TtsRuntimeScript.new()
	_tts_runtime.enabled = true
	_tts_voice_catalog.set_runtime(_tts_runtime)
	_tts_runtime.speech_started.connect(Callable(self, "_on_tts_speech_started"))
	_tts_runtime.speech_progress.connect(Callable(self, "_on_tts_speech_progress"))
	_tts_runtime.speech_finished.connect(Callable(self, "_on_tts_speech_finished"))
	_tts_runtime.speech_failed.connect(Callable(self, "_on_tts_speech_failed"))
	add_child(_tts_runtime)
	call("_apply_voice_config_engine_services")


func _load_voice_configs_from_storage() -> void:
	_voice_configs = _tts_voice_repository.load_or_seed(_voice_configs)
	_apply_voice_config_engine_services()


func _normalize_voice_configs(configs: Array) -> Array:
	return _tts_voice_repository.normalize_profiles(configs)


func _enforce_voice_active_unique(configs: Array) -> Array:
	return _tts_voice_repository.enforce_active_unique(configs)


func _apply_voice_config_engine_services() -> void:
	_tts_voice_repository.configure_runtime(_tts_runtime)


func _active_voice_config() -> Dictionary:
	return _tts_voice_repository.active_profile()


func _playback_voice_config(profile_key: String) -> Dictionary:
	return _tts_voice_repository.playback_profile(profile_key)


func _normalize_voice_engine(engine: String) -> String:
	return _tts_voice_catalog.normalize_engine(engine)


func _preview_voice_config(engine: String, voice_id: String, speed: String, pitch: String, volume: String, status: Label, preview_button: Button, preview_text: RichTextLabel = null) -> void:
	if _tts_runtime == null:
		_setup_tts_runtime()
	_voice_preview_status_label = status
	_voice_preview_text_label = preview_text
	_voice_preview_progress_supported = false
	_update_voice_preview_text(_voice_preview_sample_text(), 0.0, false)
	var prepared: Dictionary = _tts_voice_preview_controller.prepare_preview(_tts_runtime, engine, voice_id, speed, pitch, volume)
	if not bool(prepared.get("ok", false)):
		_book_status(status, String(prepared.get("error", "试听配置不可用")), BOOK_RED)
		return
	_start_voice_preview_animation(preview_button)
	var result: Dictionary = _tts_voice_preview_controller.enqueue_preview(_tts_runtime, prepared.get("item", {}) as Dictionary)
	if not bool(result.get("ok", false)):
		_book_status(status, String(result.get("error", "试听配置不可用")), BOOK_RED)
		_stop_voice_preview_animation()
		return
	_book_status(status, "正在试听", BOOK_GREEN)


func _voice_preview_sample_text() -> String:
	return _tts_voice_preview_controller.preview_text()


func _update_voice_preview_text(text: String, ratio: float = 0.0, show_progress: bool = false) -> void:
	if _voice_preview_text_label == null or not is_instance_valid(_voice_preview_text_label):
		return
	var preview := text.strip_edges()
	if preview == "":
		preview = _voice_preview_sample_text()
	var label := _voice_preview_text_label
	if not show_progress:
		label.bbcode_enabled = false
		label.text = preview
		label.add_theme_color_override("default_color", BOOK_MUTED)
		return
	var split_index := int(round(float(preview.length()) * clampf(ratio, 0.0, 1.0)))
	split_index = maxi(0, mini(preview.length(), split_index))
	var played := _escape_voice_preview_bbcode(preview.substr(0, split_index))
	var pending := _escape_voice_preview_bbcode(preview.substr(split_index))
	label.bbcode_enabled = true
	label.text = "[color=#%s][b]%s[/b][/color][color=#%s]%s[/color]" % [
		BOOK_GREEN.to_html(false),
		played,
		BOOK_MUTED.to_html(false),
		pending,
	]


func _escape_voice_preview_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


func _start_voice_preview_animation(button: Button) -> void:
	_stop_voice_preview_animation(false)
	_voice_preview_button = button
	if button == null:
		return
	button.disabled = false
	button.scale = Vector2.ONE
	button.modulate = Color(1.0, 0.92, 0.68, 1.0)
	_voice_preview_tween = create_tween()
	_voice_preview_tween.set_loops()
	_voice_preview_tween.tween_property(button, "scale", Vector2(1.16, 1.16), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_voice_preview_tween.tween_property(button, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_voice_preview_tween.tween_property(button, "modulate", Color(1.0, 0.78, 0.36, 1.0), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_voice_preview_tween.tween_property(button, "modulate", Color(1.0, 0.92, 0.68, 1.0), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _stop_voice_preview_animation(clear_status: bool = true) -> void:
	if _voice_preview_tween != null:
		_voice_preview_tween.kill()
		_voice_preview_tween = null
	if _voice_preview_button != null:
		_voice_preview_button.scale = Vector2.ONE
		_voice_preview_button.modulate = Color.WHITE
	if clear_status:
		_voice_preview_button = null
