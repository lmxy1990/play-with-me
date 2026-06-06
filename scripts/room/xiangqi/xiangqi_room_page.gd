extends "res://scripts/ui/base/page_ui_base.gd"

signal navigate_requested(route: String, payload: Dictionary)

const XiangqiEngineScript := preload("res://scripts/room/xiangqi/xiangqi_engine.gd")
const XiangqiAssetCatalogScript := preload("res://scripts/room/xiangqi/xiangqi_asset_catalog.gd")
const RoomPlayerFactoryScript := preload("res://scripts/player/player_factory.gd")
const XiangqiAiRuntimeScript := preload("res://scripts/player/xiangqi/ai/ai_xiangqi_player_runtime.gd")
const ModelChatClientScript := preload("res://scripts/core/model/model_chat_client.gd")
const ModelProfileSelectorScript := preload("res://scripts/core/model/model_profile_selector.gd")
const ModelAdapterRegistryScript := preload("res://scripts/core/model/model_adapter_registry.gd")
const AndroidModelConfigStoreScript := preload("res://scripts/android/android_model_config_store.gd")
const TtsRuntimeScript := preload("res://scripts/core/tts/tts_runtime.gd")
const TtsVoiceProfileRepositoryScript := preload("res://scripts/core/tts/voice_profile_repository.gd")
const PlayerSpeechOutputScript := preload("res://scripts/player/player_speech_output.gd")
const CircleAvatarScript := preload("res://scripts/ui/common/circle_avatar.gd")

const BOARD_FILES := 9
const BOARD_RANKS := 10
const BOARD_VIEW_SIZE := Vector2(468, 520)
const BOARD_SVG_SIZE := Vector2(720, 800)
const BOARD_GRID_ORIGIN := Vector2(76, 76)
const BOARD_GRID_STEP := Vector2(71, 72)
const OBSERVER_SLOT_COUNT := 3
const AI_TURN_DELAY_SEC := 0.45
const AI_MODEL_TIMEOUT_SEC := 45.0
const AI_MODEL_MAX_OUTPUT_TOKENS := 512

var _app_state
var _network_session
var _preference_repository
var _engine = XiangqiEngineScript.new()
var _player_factory = RoomPlayerFactoryScript.new()
var _ai_runtime = XiangqiAiRuntimeScript.new()
var _model_chat_client = ModelChatClientScript.new()
var _model_profile_selector = ModelProfileSelectorScript.new()
var _model_adapter_registry = ModelAdapterRegistryScript.new()
var _model_config_store = AndroidModelConfigStoreScript.new()
var _tts_runtime
var _tts_voice_repository = TtsVoiceProfileRepositoryScript.new()
var _player_speech_output = PlayerSpeechOutputScript.new()
var _rooms: Array = []
var _players: Array = []
var _bot_profiles: Array = []
var _model_configs: Array = []
var _voice_configs: Array = []
var _xiangqi: Dictionary = {}
var _history: Array = []
var _bot_serial := 1
var _local_player_index := -1
var _local_nickname := "玩家"
var _system_message := ""
var _selected_square := {}
var _legal_targets: Array = []
var _board_layer: Control
var _board_input_layer: Control
var _pieces_layer: Control
var _markers_layer: Control
var _left_panel: VBoxContainer
var _right_panel: VBoxContainer
var _observer_bar: HBoxContainer
var _log_list: VBoxContainer
var _status_label: Label
var _clock_label: Label
var _ready_button: Button
var _modal_layer: Control
var _toast_layer: Control
var _toast_tween: Tween
var _ai_turn_pending := false
var _ai_turn_token := 0
var _ai_model_requests := {}
var _adding_bot := false


func set_app_state(state) -> void:
	_app_state = state
	_bind_state()


func set_network_session(session) -> void:
	_network_session = session


func set_preference_repository(repository) -> void:
	_preference_repository = repository


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_connect_model_client()
	_bind_state()
	_ensure_xiangqi_state()
	_build_page()


func _exit_tree() -> void:
	_disconnect_model_client()
	if _tts_runtime != null and _tts_runtime.has_method("stop"):
		_tts_runtime.stop()


func _bind_state() -> void:
	if _app_state == null:
		return
	_rooms = _app_state.rooms
	_players = _app_state.players
	_bot_profiles = _app_state.bot_profiles
	_model_configs = _normalize_model_configs(_app_state.model_configs)
	_voice_configs = _normalize_voice_configs(_app_state.voice_configs)
	_model_config_store.persistence_enabled = bool(_app_state.persistence_enabled)
	_tts_voice_repository.set_persistence_enabled(bool(_app_state.persistence_enabled))
	_load_model_configs_from_storage()
	_load_voice_configs_from_storage()
	_xiangqi = _app_state.xiangqi
	_history = _app_state.history
	_bot_serial = _app_state.bot_serial
	_local_player_index = _app_state.local_player_index
	_local_nickname = _app_state.local_nickname
	_system_message = _app_state.system_message


func _commit_state() -> void:
	if _app_state == null:
		return
	_app_state.rooms = _rooms
	_app_state.players = _players
	_app_state.bot_profiles = _bot_profiles
	_app_state.model_configs = _model_configs
	_app_state.voice_configs = _voice_configs
	_app_state.xiangqi = _xiangqi
	_app_state.history = _history
	_app_state.bot_serial = _bot_serial
	_app_state.local_player_index = _local_player_index
	_app_state.local_nickname = _local_nickname
	_app_state.system_message = _system_message
	_app_state.update_active_room_counts()
	_app_state.save()


func _ensure_xiangqi_state() -> void:
	if _xiangqi.is_empty():
		var room := _active_room()
		_xiangqi = _engine.default_state(room)
	if _players.size() != 2:
		_players.clear()
		for i in range(2):
			_players.append(_empty_seat_data(i))
		if _app_state != null:
			_app_state.players = _players


func _connect_model_client() -> void:
	var callback := Callable(self, "_on_model_chat_completed")
	if not _model_chat_client.completed.is_connected(callback):
		_model_chat_client.completed.connect(callback)


func _disconnect_model_client() -> void:
	var callback := Callable(self, "_on_model_chat_completed")
	if _model_chat_client != null and _model_chat_client.completed.is_connected(callback):
		_model_chat_client.completed.disconnect(callback)


func _load_model_configs_from_storage() -> bool:
	if not _model_config_store.is_available():
		return false
	var stored := _model_config_store.list_configs()
	if stored.is_empty():
		return false
	_model_configs = _normalize_model_configs(stored)
	return true


func _normalize_model_configs(configs: Array) -> Array:
	var result: Array = []
	for item in configs:
		if not (item is Dictionary):
			continue
		var profile := _model_profile_selector.usable_profile(item as Dictionary)
		if profile.is_empty():
			continue
		result.append(profile)
	return result


func _normalize_voice_configs(configs: Array) -> Array:
	return _tts_voice_repository.normalize_profiles(configs)


func _load_voice_configs_from_storage() -> void:
	_voice_configs = _tts_voice_repository.load_or_seed(_voice_configs)
	_configure_tts_runtime()


func _setup_tts_runtime() -> void:
	if _tts_runtime != null:
		_configure_tts_runtime()
		return
	_tts_runtime = TtsRuntimeScript.new()
	_tts_runtime.enabled = true
	add_child(_tts_runtime)
	_configure_tts_runtime()


func _configure_tts_runtime() -> void:
	if _tts_runtime == null:
		return
	_tts_voice_repository.configure_runtime(_tts_runtime)


func _build_page() -> void:
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null
	_toast_layer = null
	_clear_children_now(self)
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.texture = _texture(XiangqiAssetCatalogScript.table_background_path())
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_bg)

	var tint := ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.04, 0.07, 0.06, 0.10)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)

	var safe := MarginContainer.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin_each(safe, 18, 14, 18, 14)
	add_child(safe)

	var root := HBoxContainer.new()
	root.name = "XiangqiRoomRoot"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	safe.add_child(root)

	_left_panel = _player_side_panel(0)
	root.add_child(_left_panel)
	root.add_child(_board_column())
	_right_panel = _player_side_panel(1)
	root.add_child(_right_panel)
	_modal_layer = Control.new()
	_modal_layer.name = "XiangqiModalLayer"
	_modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_layer.z_index = 50
	add_child(_modal_layer)
	_toast_layer = Control.new()
	_toast_layer.name = "XiangqiToastLayer"
	_toast_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.z_index = 70
	add_child(_toast_layer)
	_refresh_all()


func _board_column() -> Control:
	var holder := VBoxContainer.new()
	holder.name = "XiangqiBoardColumn"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 8)

	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 40)
	top.add_theme_constant_override("separation", 8)
	holder.add_child(top)
	_status_label = _nowrap_label("", 15, Color(0.98, 0.88, 0.66), true, HORIZONTAL_ALIGNMENT_LEFT)
	_status_label.name = "XiangqiStatusLabel"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_status_label)
	_clock_label = _nowrap_label("", 13, Color(0.78, 0.88, 0.80), true, HORIZONTAL_ALIGNMENT_RIGHT)
	_clock_label.name = "XiangqiClockLabel"
	_clock_label.custom_minimum_size = Vector2(170, 0)
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_clock_label)
	var exit_button := _fresh_button("退出", false, func(): _leave_room_to_lobby(), true)
	exit_button.name = "XiangqiActionExitButton"
	exit_button.custom_minimum_size = Vector2(70, 36)
	top.add_child(exit_button)

	var board_shell := CenterContainer.new()
	board_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(board_shell)
	var board_panel := Control.new()
	board_panel.name = "XiangqiBoardPanel"
	board_panel.custom_minimum_size = BOARD_VIEW_SIZE
	board_panel.size = BOARD_VIEW_SIZE
	board_panel.clip_contents = false
	board_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_shell.add_child(board_panel)
	_board_layer = board_panel

	var board := TextureRect.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.texture = _texture(XiangqiAssetCatalogScript.board_path())
	board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board.stretch_mode = TextureRect.STRETCH_SCALE
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_panel.add_child(board)

	_board_input_layer = Control.new()
	_board_input_layer.name = "XiangqiBoardInputLayer"
	_board_input_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_input_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_board_input_layer.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_board_input_layer.gui_input.connect(func(event: InputEvent):
		_on_board_input_gui(event, _board_input_layer)
	)
	board_panel.add_child(_board_input_layer)

	_markers_layer = Control.new()
	_markers_layer.name = "XiangqiMarkersLayer"
	_markers_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_panel.add_child(_markers_layer)
	_pieces_layer = Control.new()
	_pieces_layer.name = "XiangqiPiecesLayer"
	_pieces_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pieces_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_panel.add_child(_pieces_layer)

	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.custom_minimum_size = Vector2(0, 48)
	controls.add_theme_constant_override("separation", 10)
	holder.add_child(controls)
	_ready_button = _fresh_button(_ready_button_text(), true, func(): _start_xiangqi_from_button())
	_ready_button.name = "XiangqiActionReadyButton"
	_ready_button.custom_minimum_size = Vector2(92, 38)
	controls.add_child(_ready_button)
	controls.add_child(_action_button("求和", "draw", Callable(self, "_offer_draw")))
	controls.add_child(_action_button("悔棋", "undo", Callable(self, "_offer_undo")))
	controls.add_child(_action_button("认输", "resign", Callable(self, "_resign")))
	controls.add_child(_action_button("暂停", "pause", Callable(self, "_toggle_pause")))

	_observer_bar = HBoxContainer.new()
	_observer_bar.name = "XiangqiObserverBar"
	_observer_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_observer_bar.custom_minimum_size = Vector2(0, 48)
	_observer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_observer_bar.add_theme_constant_override("separation", 8)
	holder.add_child(_observer_bar)

	return holder


func _player_side_panel(index: int) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.name = "XiangqiPlayerPanel%d" % (index + 1)
	panel.custom_minimum_size = Vector2(238, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 10)
	return panel


func _refresh_all() -> void:
	_refresh_status()
	_refresh_ready_button()
	_refresh_player_panel(_left_panel, 0)
	_refresh_player_panel(_right_panel, 1)
	_refresh_observer_slots()
	_refresh_board()
	_refresh_pending_offer_modal()
	_resolve_bot_pending_offer_if_needed()
	_schedule_ai_turn_if_needed()


func _refresh_status() -> void:
	if _status_label == null:
		return
	var result := String(_xiangqi.get("game_result", XiangqiEngineScript.RESULT_PLAYING))
	if not _is_game_started():
		_status_label.text = "等待开局 · %d/2" % _ready_player_count()
	elif result != XiangqiEngineScript.RESULT_PLAYING:
		_status_label.text = _result_text(result)
	elif _has_pending_draw_offer():
		_status_label.text = "%s请求求和" % _engine.side_label(_pending_offer_side("draw"))
	elif _has_pending_undo_offer():
		_status_label.text = "%s请求悔棋" % _engine.side_label(_pending_offer_side("undo"))
	elif bool(_xiangqi.get("paused", false)):
		_status_label.text = "棋局暂停"
	else:
		_status_label.text = "%s行棋 · 第%d回合" % [_engine.side_label(String(_xiangqi.get("side_to_move", XiangqiEngineScript.SIDE_RED))), int(_xiangqi.get("turn_number", 1))]
	if _clock_label != null:
		_clock_label.text = _clock_text()


func _refresh_ready_button() -> void:
	if _ready_button == null:
		return
	_ready_button.text = _ready_button_text()
	_ready_button.disabled = _is_game_started() or not _all_xiangqi_seats_occupied()
	_ready_button.visible = not _is_game_started()


func _refresh_player_panel(panel: VBoxContainer, index: int) -> void:
	if panel == null:
		return
	_clear_children_now(panel)
	var side := _engine.side_for_seat(index)
	var player := _player_at(index)
	var occupied := String(player.get("owner", "")).strip_edges() != ""
	var card := _panel(Color(0.95, 0.86, 0.60, 0.84), Color(0.38, 0.22, 0.08, 0.42), 8)
	card.name = "XiangqiSeatCard%d" % (index + 1)
	card.custom_minimum_size = Vector2(0, 170)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent):
		if not _seat_click_event(event):
			return
		card.accept_event()
		_on_seat_card_pressed(index)
	)
	panel.add_child(card)
	var margin := MarginContainer.new()
	_margin_each(margin, 12, 10, 12, 10)
	if not occupied:
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	var identity_row := HBoxContainer.new()
	identity_row.name = "XiangqiSeatIdentityRow%d" % (index + 1)
	identity_row.add_theme_constant_override("separation", 10)
	body.add_child(identity_row)
	var avatar := _seat_avatar_control(index, player, 72)
	identity_row.add_child(avatar)
	var info_box := VBoxContainer.new()
	info_box.name = "XiangqiSeatInfo%d" % (index + 1)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 4)
	identity_row.add_child(info_box)
	var name_label := _nowrap_label(String(player.get("name", "%d号位" % [index + 1])), 16, BOOK_TEXT, true, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.name = "XiangqiSeatNameLabel%d" % (index + 1)
	info_box.add_child(name_label)
	var side_label := _nowrap_label("%s · %d号位" % [_engine.side_label(side), index + 1], 13, BOOK_GOLD, true, HORIZONTAL_ALIGNMENT_LEFT)
	side_label.name = "XiangqiSeatSideLabel%d" % (index + 1)
	info_box.add_child(side_label)
	var state := "等待落座"
	if occupied:
		if not _is_game_started():
			state = "已落座"
		else:
			state = "行棋方" if String(_xiangqi.get("side_to_move", "")) == side else "等待"
	var state_label := _nowrap_label(state, 12, BOOK_MUTED, false, HORIZONTAL_ALIGNMENT_LEFT)
	state_label.name = "XiangqiSeatStateLabel%d" % (index + 1)
	info_box.add_child(state_label)
	if occupied:
		info_box.add_child(_voice_toggle_button(index))
	if index == _local_player_index:
		body.add_child(_fresh_button("离座", false, func(): _stand_up(index)))
	elif _is_bot_player(player):
		body.add_child(_fresh_button("移除", false, func(): _remove_bot_at(index), true))

	var chat_card := _panel(Color(0.96, 0.90, 0.72, 0.68), Color(0.42, 0.28, 0.10, 0.28), 8)
	chat_card.name = "XiangqiHistoryCard%d" % (index + 1)
	chat_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(chat_card)
	var chat_margin := MarginContainer.new()
	_margin_each(chat_margin, 10, 8, 10, 8)
	chat_card.add_child(chat_margin)
	var chat_body := VBoxContainer.new()
	chat_body.add_theme_constant_override("separation", 6)
	chat_margin.add_child(chat_body)
	chat_body.add_child(_nowrap_label("记录", 13, BOOK_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "XiangqiHistoryList%d" % (index + 1)
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	if index == 0:
		_log_list = list
	_refresh_history_list(list)
	if _can_send_chat_from_seat(index, player):
		chat_body.add_child(_chat_input_row(index))


func _refresh_observer_slots() -> void:
	if _observer_bar == null:
		return
	_clear_children_now(_observer_bar)
	var observers := _room_observers()
	for i in range(OBSERVER_SLOT_COUNT):
		var observer := {}
		if i < observers.size() and observers[i] is Dictionary:
			observer = (observers[i] as Dictionary).duplicate(true)
		_observer_bar.add_child(_observer_slot_button(i, observer))


func _observer_slot_button(slot_index: int, observer: Dictionary) -> Button:
	var occupied := not observer.is_empty()
	var mine := occupied and String(observer.get("id", "")).strip_edges() == _current_network_participant_id()
	var display_name := _observer_display_name(observer, "空位") if occupied else "空位"
	var button := Button.new()
	button.name = "ObserverSlotButton%d" % [slot_index + 1]
	button.text = "观战%d\n%s" % [slot_index + 1, "自己" if mine else display_name]
	button.custom_minimum_size = Vector2(112, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "我的观战位" if mine else ("观战位" if occupied else "进入观战")
	_style_fresh_button(button, false)
	button.disabled = occupied
	if not occupied:
		button.pressed.connect(func():
			_play_click()
			_switch_local_to_observer()
		)
	return button


func _refresh_history_list(list: VBoxContainer) -> void:
	if list == null:
		return
	_clear_children_now(list)
	var chat_items := []
	for item in _history:
		if not (item is Dictionary):
			continue
		if _history_item_is_chat(item as Dictionary):
			chat_items.append(item)
	var start: int = maxi(0, chat_items.size() - 14)
	for i in range(start, chat_items.size()):
		var item: Dictionary = chat_items[i]
		var row := _label("%s：%s" % [String(item.get("speaker", "玩家")), String(item.get("text", ""))], 11, BOOK_TEXT)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(0, 22)
		list.add_child(row)


func _can_send_chat_from_seat(index: int, player: Dictionary) -> bool:
	if index != _local_player_index:
		return false
	if String(player.get("owner", "")).strip_edges() == "":
		return false
	return not _is_bot_player(player)


func _voice_toggle_button(index: int) -> Button:
	var enabled := _player_tts_enabled(index)
	var button := Button.new()
	button.name = "XiangqiSeatVoiceToggleButton%d" % (index + 1)
	button.custom_minimum_size = Vector2(34, 30)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "关闭棋子播报" if enabled else "开启棋子播报"
	button.icon = _texture(XiangqiAssetCatalogScript.voice_path())
	button.expand_icon = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 22)
	button.add_theme_constant_override("icon_separation", 0)
	_style_fresh_button(button, enabled)
	var icon_color := BOOK_GREEN if enabled else Color(0.48, 0.48, 0.44, 0.58)
	button.add_theme_color_override("icon_normal_color", icon_color)
	button.add_theme_color_override("icon_hover_color", icon_color.lightened(0.08))
	button.add_theme_color_override("icon_pressed_color", icon_color.darkened(0.10))
	button.add_theme_color_override("icon_focus_color", icon_color)
	button.pressed.connect(func():
		_play_click()
		_set_player_tts_enabled(index, not _player_tts_enabled(index))
		_refresh_all()
	)
	return button


func _player_tts_enabled(index: int) -> bool:
	return _player_speech_output.speaker_tts_enabled(index, _players)


func _set_player_tts_enabled(index: int, enabled: bool) -> void:
	_player_speech_output.set_speaker_tts_enabled(index, enabled, _players)


func _play_ai_move_voice(move: Dictionary) -> void:
	if move.is_empty():
		_xiangqi_voice_debug("skip reason=empty_move")
		return
	var side := String(move.get("side", ""))
	var seat := _engine.seat_for_side(side)
	if seat < 0 or seat >= _players.size():
		_xiangqi_voice_debug("skip reason=invalid_seat side=%s seat=%d" % [side, seat])
		return
	var player := _player_at(seat)
	if not _is_bot_player(player):
		_xiangqi_voice_debug("skip reason=not_ai seat=%d player=%s" % [seat + 1, String(player.get("name", ""))])
		return
	if not _player_tts_enabled(seat):
		_xiangqi_voice_debug("skip reason=muted seat=%d player=%s" % [seat + 1, String(player.get("name", ""))])
		return
	var text := _ai_move_voice_text(move)
	if text == "":
		_xiangqi_voice_debug("skip reason=empty_text seat=%d" % [seat + 1])
		return
	var voice := _voice_config_for_player(player)
	if voice.is_empty() or not bool(voice.get("enabled", true)):
		_xiangqi_voice_debug("skip reason=voice_config_disabled seat=%d player=%s voice=%s" % [
			seat + 1,
			String(player.get("name", "")),
			JSON.stringify(voice),
		])
		return
	_setup_tts_runtime()
	if _tts_runtime == null:
		_xiangqi_voice_debug("skip reason=no_tts_runtime seat=%d" % [seat + 1])
		return
	var item := {
		"speaker": "%d号 %s" % [seat + 1, String(player.get("name", "AI"))],
		"speaker_index": seat,
		"text": text,
		"display_text": text,
		"voice": String(voice.get("voice", "")),
		"engine": String(voice.get("engine", "system")),
		"speed": String(voice.get("speed", "0.90")),
		"pitch": String(voice.get("pitch", "1.00")),
		"volume": String(voice.get("volume", "1.00")),
		"interrupt": true,
		"at": Time.get_unix_time_from_system(),
	}
	_xiangqi_voice_debug("enqueue seat=%d player=%s text=%s engine=%s voice=%s" % [
		seat + 1,
		String(player.get("name", "")),
		text,
		String(voice.get("engine", "")),
		String(voice.get("voice", "")),
	])
	_tts_runtime.enqueue(item)


func _ai_move_voice_text(move: Dictionary) -> String:
	var piece: Dictionary = move.get("piece", {}) if move.get("piece", {}) is Dictionary else {}
	var captured: Dictionary = move.get("captured", {}) if move.get("captured", {}) is Dictionary else {}
	var side := String(move.get("side", ""))
	var kind := String(piece.get("kind", ""))
	var text := "走棋"
	match kind:
		"soldier":
			text = "上%s" % _engine.piece_label(piece)
		"horse":
			text = "走马"
		"rook":
			text = "走车"
		"cannon":
			text = "走炮"
		"elephant":
			text = "走%s" % _engine.piece_label(piece)
		"advisor":
			text = "走%s" % _engine.piece_label(piece)
		"king":
			text = "走%s" % _engine.piece_label(piece)
	if not captured.is_empty():
		text = "吃%s" % _engine.piece_label(captured)
	var check_side := String(_xiangqi.get("check_side", ""))
	if check_side != "" and check_side != side:
		text += "，将军"
	return text


func _voice_config_for_player(player: Dictionary) -> Dictionary:
	var key := String(player.get("playback_voice_config_id", player.get("playbackVoiceConfigId", player.get("voice_config_id", player.get("voiceConfigId", ""))))).strip_edges()
	var profile := _tts_voice_repository.playback_profile(key, _voice_configs)
	if not profile.is_empty():
		return profile
	var voice_name := String(player.get("voice", player.get("voiceName", ""))).strip_edges()
	if voice_name != "":
		for item_value in _voice_configs:
			if item_value is Dictionary:
				var item: Dictionary = item_value
				if String(item.get("name", "")).strip_edges() == voice_name or String(item.get("key", "")).strip_edges() == voice_name:
					return item.duplicate(true)
	return _tts_voice_repository.active_profile(_voice_configs)


func _chat_input_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "XiangqiChatInputRow%d" % (index + 1)
	row.add_theme_constant_override("separation", 6)
	var input := LineEdit.new()
	input.name = "XiangqiChatInput%d" % (index + 1)
	input.placeholder_text = "输入发言"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 34)
	_style_input(input)
	row.add_child(input)
	var send := _fresh_button("发送", true, func(): _send_chat_from_input(index, input))
	send.name = "XiangqiChatSendButton%d" % (index + 1)
	send.custom_minimum_size = Vector2(62, 34)
	row.add_child(send)
	input.text_submitted.connect(func(_submitted: String): _send_chat_from_input(index, input))
	return row


func _send_chat_from_input(index: int, input: LineEdit) -> void:
	if input == null:
		return
	var text := input.text.strip_edges()
	if text == "":
		return
	var player := _player_at(index)
	if not _can_send_chat_from_seat(index, player):
		_set_message("当前座位不能发言")
		return
	_history.append({
		"speaker": String(player.get("name", "%d号位" % [index + 1])),
		"speaker_index": index,
		"type": "chat",
		"text": text,
		"visibility": "public",
		"at": Time.get_unix_time_from_system(),
	})
	input.text = ""
	_commit_state()
	_refresh_all()


func _history_item_is_chat(item: Dictionary) -> bool:
	return String(item.get("type", "")).strip_edges() == "chat"


func _refresh_board() -> void:
	if _pieces_layer == null or _markers_layer == null:
		return
	_clear_children_now(_pieces_layer)
	_clear_children_now(_markers_layer)
	for target in _legal_targets:
		if target is Dictionary:
			_add_marker(int((target as Dictionary).get("file", -1)), int((target as Dictionary).get("rank", -1)), "legal_dot")
	for entry_value in _engine.board_summary(_xiangqi):
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		_pieces_layer.add_child(_piece_button(entry))


func _piece_button(entry: Dictionary) -> Control:
	var file := int(entry.get("file", 0))
	var rank := int(entry.get("rank", 0))
	var side := String(entry.get("side", "red"))
	var button := Button.new()
	button.name = "XiangqiPieceButton_%d_%d" % [file, rank]
	button.custom_minimum_size = Vector2(48, 48)
	button.size = Vector2(48, 48)
	button.position = _square_position(file, rank) - button.size * 0.5
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.icon = _texture(XiangqiAssetCatalogScript.piece_base_path(side))
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 48)
	_style_transparent_button(button)
	button.pressed.connect(func(): _on_square_pressed(file, rank))
	var label := _nowrap_label(String(entry.get("label", "")), 21, Color(0.55, 0.05, 0.03) if side == "red" else Color(0.06, 0.06, 0.05), true, HORIZONTAL_ALIGNMENT_CENTER)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_top = -3
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	return button


func _on_board_input_gui(event: InputEvent, source: Control = null) -> void:
	if not _seat_click_event(event):
		return
	var local_position := _event_local_position(event, source)
	if local_position.x < 0.0 or local_position.y < 0.0:
		return
	var square := _board_square_from_local_position(local_position)
	if square.is_empty():
		return
	if source != null:
		source.accept_event()
	_on_square_pressed(int(square.get("file", -1)), int(square.get("rank", -1)))


func _event_local_position(event: InputEvent, source: Control = null) -> Vector2:
	var position := Vector2(-1.0, -1.0)
	if event is InputEventMouseButton:
		position = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch:
		position = (event as InputEventScreenTouch).position
	if position.x < 0.0 or position.y < 0.0:
		return position
	if source == null:
		return position
	return source.get_global_transform_with_canvas().affine_inverse() * position


func _board_square_from_local_position(local_position: Vector2) -> Dictionary:
	var scale := _board_render_scale()
	if scale.x <= 0.0 or scale.y <= 0.0:
		return {}
	var board_position := Vector2(local_position.x / scale.x, local_position.y / scale.y)
	var file := int(round((board_position.x - BOARD_GRID_ORIGIN.x) / BOARD_GRID_STEP.x))
	var view_rank := int(round((board_position.y - BOARD_GRID_ORIGIN.y) / BOARD_GRID_STEP.y))
	var rank := BOARD_RANKS - 1 - view_rank
	if file < 0 or file >= BOARD_FILES or rank < 0 or rank >= BOARD_RANKS:
		return {}
	return {"file": file, "rank": rank}


func _add_marker(file: int, rank: int, kind: String) -> void:
	if file < 0 or rank < 0:
		return
	var marker := TextureRect.new()
	marker.name = "XiangqiLegalDot_%d_%d" % [file, rank]
	var size := Vector2(16, 16)
	marker.texture = _texture(XiangqiAssetCatalogScript.marker_path(kind))
	marker.size = size
	marker.position = _square_position(file, rank) - size * 0.5
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers_layer.add_child(marker)


func _on_square_pressed(file: int, rank: int) -> void:
	if not _is_game_started():
		_set_message("请先准备开局")
		return
	if _has_pending_offer():
		_set_message("等待对方处理请求")
		return
	if bool(_xiangqi.get("paused", false)):
		_set_message("棋局已暂停")
		return
	if String(_xiangqi.get("game_result", XiangqiEngineScript.RESULT_PLAYING)) != XiangqiEngineScript.RESULT_PLAYING:
		return
	if OS.is_debug_build():
		print("[XiangqiInput][debug] press file=%d rank=%d selected=%s targets=%d" % [
			file,
			rank,
			JSON.stringify(_selected_square),
			_legal_targets.size(),
		])
	var side := String(_xiangqi.get("side_to_move", XiangqiEngineScript.SIDE_RED))
	var seat := _engine.seat_for_side(side)
	if _local_player_index < 0:
		_set_message("观战者不能走棋")
		return
	if _local_player_index != seat:
		_set_message("等待%s行棋" % _engine.side_label(side))
		return
	if _selected_square.is_empty():
		_select_square(file, rank)
		return
	for target in _legal_targets:
		if target is Dictionary and int((target as Dictionary).get("file", -1)) == file and int((target as Dictionary).get("rank", -1)) == rank:
			_apply_move(int(_selected_square.get("file", -1)), int(_selected_square.get("rank", -1)), file, rank)
			return
	_select_square(file, rank)


func _select_square(file: int, rank: int) -> void:
	var piece := _piece_at(file, rank)
	if piece.is_empty():
		_selected_square = {}
		_legal_targets = []
		_refresh_board()
		return
	if String(piece.get("side", "")) != String(_xiangqi.get("side_to_move", XiangqiEngineScript.SIDE_RED)):
		_selected_square = {}
		_legal_targets = []
		_refresh_board()
		return
	_selected_square = {"file": file, "rank": rank}
	_legal_targets = _engine.legal_moves_from(_xiangqi, file, rank)
	_refresh_board()


func _apply_move(from_file: int, from_rank: int, to_file: int, to_rank: int) -> void:
	var result: Dictionary = _engine.apply_move(_xiangqi, from_file, from_rank, to_file, to_rank)
	if not bool(result.get("ok", false)):
		_set_message(String(result.get("message", "走法不合法")))
		return
	_xiangqi = result.get("state", {}) as Dictionary
	var move: Dictionary = result.get("move", {}) if result.get("move", {}) is Dictionary else {}
	_print_move_debug(move)
	_play_ai_move_voice(move)
	_selected_square = {}
	_legal_targets = []
	_commit_state()
	_refresh_all()


func _offer_draw() -> void:
	if not _is_game_started():
		_set_message("对局未开始")
		return
	if not _local_player_can_act():
		return
	if _has_pending_offer():
		_set_message("已有待处理请求")
		return
	var result := _engine.offer_draw(_xiangqi, _current_side_for_local_action())
	_apply_non_move_result(result, "提出求和")


func _offer_undo() -> void:
	if not _is_game_started():
		_set_message("对局未开始")
		return
	if not _local_player_can_act():
		return
	if _has_pending_offer():
		_set_message("已有待处理请求")
		return
	var result := _engine.offer_undo(_xiangqi, _current_side_for_local_action())
	_apply_non_move_result(result, "提出悔棋")


func _respond_draw(accepted: bool) -> void:
	if not _is_game_started():
		_set_message("对局未开始")
		return
	if not _local_player_can_act():
		return
	var side := _current_side_for_local_action()
	var result := _engine.respond_draw(_xiangqi, side, accepted)
	_apply_non_move_result(result, "同意求和" if accepted else "拒绝求和")


func _respond_undo(accepted: bool) -> void:
	if not _is_game_started():
		_set_message("对局未开始")
		return
	if not _local_player_can_act():
		return
	var side := _current_side_for_local_action()
	var result := _engine.respond_undo(_xiangqi, side, accepted)
	_apply_non_move_result(result, "同意悔棋" if accepted else "拒绝悔棋")


func _resign() -> void:
	if not _is_game_started():
		_set_message("对局未开始")
		return
	if not _local_player_can_act():
		return
	var result := _engine.resign(_xiangqi, _current_side_for_local_action())
	_apply_non_move_result(result, "认输")


func _toggle_pause() -> void:
	if not _is_game_started():
		_set_message("对局未开始")
		return
	if not _local_player_can_act():
		return
	_xiangqi["paused"] = not bool(_xiangqi.get("paused", false))
	_commit_state()
	_refresh_all()


func _apply_non_move_result(result: Dictionary, action_text: String) -> void:
	if not bool(result.get("ok", false)):
		_set_message(String(result.get("message", "操作失败")))
		return
	_xiangqi = result.get("state", {}) as Dictionary
	_commit_state()
	_refresh_all()


func _has_pending_offer() -> bool:
	return _has_pending_draw_offer() or _has_pending_undo_offer()


func _has_pending_draw_offer() -> bool:
	return _pending_offer("draw").size() > 0


func _has_pending_undo_offer() -> bool:
	return _pending_offer("undo").size() > 0


func _pending_offer(kind: String) -> Dictionary:
	var key := "pending_draw_offer" if kind == "draw" else "pending_undo_offer"
	var value = _xiangqi.get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _pending_offer_side(kind: String) -> String:
	return String(_pending_offer(kind).get("side", XiangqiEngineScript.SIDE_RED))


func _pending_offer_response_seat(kind: String) -> int:
	var pending := _pending_offer(kind)
	if pending.is_empty():
		return -1
	return _engine.seat_for_side(XiangqiEngineScript.SIDE_BLACK if String(pending.get("side", "")) == XiangqiEngineScript.SIDE_RED else XiangqiEngineScript.SIDE_RED)


func _refresh_pending_offer_modal() -> void:
	if _modal_layer == null:
		return
	var kind := _active_pending_offer_kind()
	if kind == "":
		if _modal_layer.get_child_count() > 0 and _modal_layer.get_child(0).name == "XiangqiPendingOfferOverlay":
			_clear_modal()
		return
	if _pending_offer_response_seat(kind) != _local_player_index:
		return
	if _modal_layer.get_child_count() > 0 and _modal_layer.get_child(0).name == "XiangqiPendingOfferOverlay":
		return
	_open_pending_offer_dialog(kind)


func _active_pending_offer_kind() -> String:
	if _has_pending_draw_offer():
		return "draw"
	if _has_pending_undo_offer():
		return "undo"
	return ""


func _open_pending_offer_dialog(kind: String) -> void:
	_clear_modal()
	if _modal_layer == null:
		return
	var pending := _pending_offer(kind)
	if pending.is_empty():
		return
	var requester_side := String(pending.get("side", ""))
	var title := "求和请求" if kind == "draw" else "悔棋请求"
	var body_text := "%s请求%s" % [_engine.side_label(requester_side), "求和" if kind == "draw" else "悔棋"]
	var overlay := Control.new()
	overlay.name = "XiangqiPendingOfferOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(overlay)

	var viewport_size := get_viewport_rect().size
	var popup_size := Vector2(minf(420.0, maxf(320.0, viewport_size.x - 32.0)), 188.0)
	var card := _panel(Color(0.97, 0.90, 0.70, 0.97), Color(0.42, 0.27, 0.10, 0.48), 8)
	card.custom_minimum_size = popup_size
	card.size = popup_size
	card.position = Vector2((viewport_size.x - popup_size.x) * 0.5, 18.0) - _modal_layer.global_position
	overlay.add_child(card)
	var body := _panel_body(card, 14)
	body.add_child(_nowrap_label(title, 17, BOOK_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(_label(body_text, 14, BOOK_TEXT, false, HORIZONTAL_ALIGNMENT_CENTER))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	body.add_child(actions)
	actions.add_child(_pending_offer_button("同意", true, func(): _respond_pending_offer(kind, true)))
	actions.add_child(_pending_offer_button("拒绝", false, func(): _respond_pending_offer(kind, false), true))


func _pending_offer_button(text: String, primary: bool, callback: Callable, danger: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(96, 38)
	button.focus_mode = Control.FOCUS_NONE
	_style_fresh_button(button, primary, danger)
	button.pressed.connect(callback)
	return button


func _respond_pending_offer(kind: String, accepted: bool) -> void:
	_play_click()
	_clear_modal()
	if kind == "draw":
		_respond_draw(accepted)
	else:
		_respond_undo(accepted)


func _resolve_bot_pending_offer_if_needed() -> void:
	var kind := _active_pending_offer_kind()
	if kind == "":
		return
	var seat := _pending_offer_response_seat(kind)
	if seat < 0 or seat >= _players.size():
		return
	var player := _player_at(seat)
	if not _is_bot_player(player):
		return
	var side := _engine.side_for_seat(seat)
	var result := _engine.respond_draw(_xiangqi, side, false) if kind == "draw" else _engine.respond_undo(_xiangqi, side, false)
	if bool(result.get("ok", false)):
		_xiangqi = result.get("state", {}) as Dictionary
		_commit_state()
		_refresh_all()


func _current_side_for_local_action() -> String:
	if _local_player_index >= 0:
		return _engine.side_for_seat(_local_player_index)
	return String(_xiangqi.get("side_to_move", XiangqiEngineScript.SIDE_RED))


func _local_player_can_act() -> bool:
	if _local_player_index < 0 or _local_player_index >= _players.size():
		_set_message("观战者不能操作棋局")
		return false
	var player := _player_at(_local_player_index)
	if String(player.get("owner", "")).strip_edges() == "":
		_set_message("请先落座")
		return false
	return true


func _start_xiangqi_from_button() -> void:
	if _is_game_started():
		return
	if not _all_xiangqi_seats_occupied():
		_set_message("双方落座后才能开始")
		return
	_try_start_xiangqi_game()
	_commit_state()
	_refresh_all()


func _toggle_ready() -> void:
	_start_xiangqi_from_button()


func _try_start_xiangqi_game() -> bool:
	if _is_game_started():
		return false
	if not _all_xiangqi_seats_occupied():
		return false
	var room := _active_room()
	var options := room.duplicate(true)
	if options.is_empty():
		options = _xiangqi.duplicate(true)
	_xiangqi = _engine.start_state(options)
	_selected_square = {}
	_legal_targets = []
	for i in range(_players.size()):
		if _players[i] is Dictionary:
			var player: Dictionary = _players[i]
			if String(player.get("owner", "")).strip_edges() != "":
				player["state"] = "等待"
				_players[i] = player
	_system_message = "象棋开局"
	return true


func _all_xiangqi_seats_occupied() -> bool:
	if _players.size() < 2:
		return false
	for i in range(2):
		if not (_players[i] is Dictionary):
			return false
		if String((_players[i] as Dictionary).get("owner", "")).strip_edges() == "":
			return false
	return true


func _all_xiangqi_players_ready() -> bool:
	if _players.size() < 2:
		return false
	for i in range(2):
		if not (_players[i] is Dictionary):
			return false
		var player: Dictionary = _players[i]
		if String(player.get("owner", "")).strip_edges() == "":
			return false
		if not bool(player.get("ready", false)):
			return false
	return true


func _ready_player_count() -> int:
	var count := 0
	for i in range(mini(2, _players.size())):
		if _players[i] is Dictionary and String((_players[i] as Dictionary).get("owner", "")).strip_edges() != "":
			count += 1
	return count


func _ready_button_text() -> String:
	return "开始"


func _is_game_started() -> bool:
	return bool(_xiangqi.get("started", false))


func _sit_down(index: int) -> void:
	if index < 0 or index >= _players.size():
		return
	_clear_modal()
	if _local_player_index >= 0 and _local_player_index < _players.size():
		_players[_local_player_index] = _empty_seat_data(_local_player_index)
	_remove_observer(_active_room(), _current_network_participant_id())
	var identity := _preference_identity_snapshot()
	var player := _player_factory.self_player_from_identity(_current_network_participant_id(), identity, _players, index, AppState.SeatMotion.IDLE)
	player["role"] = _engine.side_label(_engine.side_for_seat(index))
	player["role_key"] = _engine.side_for_seat(index)
	player["ready"] = true
	player["state"] = "已落座"
	_players[index] = player
	_local_player_index = index
	_local_nickname = String(player.get("name", _local_nickname))
	_commit_state()
	_refresh_all()


func _add_bot_at(index: int, bot_profile: Dictionary = {}) -> void:
	if index < 0 or index >= _players.size():
		return
	if _adding_bot:
		return
	if String((_players[index] as Dictionary).get("owner", "")).strip_edges() != "":
		_set_message("该座位已有玩家")
		return
	_adding_bot = true
	_clear_modal()
	var profile := _normalized_bot_profile_for_add(bot_profile)
	var bot := _player_factory.xiangqi_bot_player_from_profile(_bot_serial, profile, _current_network_participant_id(), _players, index, AppState.SeatMotion.IDLE)
	bot["role"] = _engine.side_label(_engine.side_for_seat(index))
	bot["role_key"] = _engine.side_for_seat(index)
	bot["ready"] = true
	bot["state"] = "已准备"
	_players[index] = bot
	_bot_serial += 1
	_system_message = "%s 加入 %d号位" % [String(bot.get("name", "机器人")), index + 1]
	_commit_state()
	_refresh_all()
	_adding_bot = false


func _remove_bot_at(index: int) -> void:
	if index < 0 or index >= _players.size():
		return
	var player := _player_at(index)
	if not _is_bot_player(player):
		return
	_players[index] = _empty_seat_data(index)
	_system_message = "%s 已离开" % String(player.get("name", "机器人"))
	_commit_state()
	if _destroy_active_room_if_no_people("remove_bot", true):
		return
	_refresh_all()


func _stand_up(index: int) -> void:
	if index < 0 or index >= _players.size():
		return
	if index == _local_player_index:
		_switch_local_to_observer()
		return
	_players[index] = _empty_seat_data(index)
	_commit_state()
	_refresh_all()


func _schedule_ai_turn_if_needed() -> void:
	if _ai_turn_pending:
		return
	if not is_inside_tree():
		return
	if not _is_game_started():
		return
	if bool(_xiangqi.get("paused", false)):
		return
	if String(_xiangqi.get("game_result", XiangqiEngineScript.RESULT_PLAYING)) != XiangqiEngineScript.RESULT_PLAYING:
		return
	var side := String(_xiangqi.get("side_to_move", XiangqiEngineScript.SIDE_RED))
	var seat := _engine.seat_for_side(side)
	if seat < 0 or seat >= _players.size():
		return
	var player := _player_at(seat)
	if not _is_bot_player(player):
		return
	_ai_turn_pending = true
	_ai_turn_token += 1
	var token := _ai_turn_token
	get_tree().create_timer(AI_TURN_DELAY_SEC).timeout.connect(func():
		_resolve_ai_turn(seat, token)
	)


func _resolve_ai_turn(seat: int, token: int = -1) -> void:
	if token != -1 and token != _ai_turn_token:
		return
	_ai_turn_pending = false
	if seat < 0 or seat >= _players.size():
		return
	if not is_inside_tree():
		return
	if not _is_game_started():
		return
	if bool(_xiangqi.get("paused", false)):
		return
	var expected_side := _engine.side_for_seat(seat)
	if String(_xiangqi.get("side_to_move", "")) != expected_side:
		return
	var player := _player_at(seat)
	if not _is_bot_player(player):
		return
	var context := _ai_runtime.build_move_context(_xiangqi, player, seat, _history)
	_print_ai_context_debug(seat, context)
	if _try_start_ai_model_move(seat, player, context, token):
		return
	var fallback_action: Dictionary = _ai_runtime.fallback_move_action(context)
	fallback_action["fallback_reason"] = "model_unavailable"
	_show_ai_fallback_toast(player, "模型不可用")
	_apply_ai_action_or_report(fallback_action, player, expected_side)


func _try_start_ai_model_move(seat: int, player: Dictionary, context: Dictionary, token: int) -> bool:
	var profile := _model_profile_for_player(player)
	if profile.is_empty():
		_xiangqi_ai_debug("model skipped seat=%d player=%s reason=no_model_profile model_ref=%s" % [
			seat + 1,
			String(player.get("name", "AI")),
			String(player.get("model", "")),
		])
		return false
	var messages := _ai_runtime.build_messages(context)
	var request_options := _ai_runtime.request_options_for_context(context)
	if messages.is_empty() or request_options.is_empty():
		return false
	var request := _model_completion_request(profile, messages, _profile_temperature(profile, 0.25), AI_MODEL_MAX_OUTPUT_TOKENS, AI_MODEL_TIMEOUT_SEC, request_options, "xiangqi.player.move")
	var request_id := int(_model_chat_client.complete_request(request))
	_ai_model_requests[request_id] = {
		"seat": seat,
		"token": token,
		"side": _engine.side_for_seat(seat),
		"player": player.duplicate(true),
		"context": context.duplicate(true),
		"model": String(profile.get("model", "")),
	}
	_xiangqi_ai_debug("model request id=%d seat=%d player=%s model=%s legal_moves=%d timeline=%d" % [
		request_id,
		seat + 1,
		String(player.get("name", "AI")),
		String(profile.get("model", "")),
		(context.get("legal_moves", []) as Array).size(),
		(context.get("timeline", []) as Array).size(),
	])
	return true


func _on_model_chat_completed(request_id: int, ok: bool, content: String, error: String) -> void:
	if not _ai_model_requests.has(request_id):
		return
	var completed := _model_chat_client.take_completed_result(request_id)
	if completed.is_empty():
		completed = {"ok": ok, "text": content, "error": error}
	var request: Dictionary = _ai_model_requests.get(request_id, {})
	_ai_model_requests.erase(request_id)
	var seat := int(request.get("seat", -1))
	var token := int(request.get("token", -1))
	var expected_side := String(request.get("side", ""))
	var player: Dictionary = request.get("player", {}) if request.get("player", {}) is Dictionary else {}
	var context: Dictionary = request.get("context", {}) if request.get("context", {}) is Dictionary else {}
	if token != _ai_turn_token:
		return
	if seat < 0 or seat >= _players.size():
		return
	if not is_inside_tree() or not _is_game_started():
		return
	if bool(_xiangqi.get("paused", false)):
		return
	if String(_xiangqi.get("side_to_move", "")) != expected_side:
		return
	var result_ok := bool(completed.get("ok", false))
	var result_text := String(completed.get("text", content))
	var result_error := String(completed.get("error", error))
	var action: Dictionary = _ai_runtime.parse_decision(result_text, context) if result_ok else {}
	if not result_ok or not bool(action.get("ok", false)):
		var fallback_reason := _ai_fallback_reason(result_ok, result_error, action)
		_xiangqi_ai_debug("model fallback request=%d seat=%d ok=%s model_error=%s parse=%s raw=%s" % [
			request_id,
			seat + 1,
			str(result_ok),
			result_error,
			JSON.stringify(action),
			result_text,
		])
		_show_ai_fallback_toast(player, fallback_reason)
		action = _ai_runtime.fallback_move_action(context)
		action["fallback_reason"] = fallback_reason
	else:
		action["context"] = context
		_xiangqi_ai_debug("model decision request=%d seat=%d action=%s move_id=%s reason=%s" % [
			request_id,
			seat + 1,
			String(action.get("action", "")),
			String(action.get("move_id", "")),
			String(action.get("reason", "")),
		])
	_apply_ai_action_or_report(action, player, expected_side)


func _apply_ai_action_or_report(action: Dictionary, player: Dictionary, expected_side: String) -> void:
	if not bool(action.get("ok", false)):
		_set_message("%s 行棋失败：%s" % [String(player.get("name", "AI")), String(action.get("message", "无有效行动"))])
		return
	match String(action.get("action", "")):
		"move":
			var from: Dictionary = action.get("from", {})
			var to: Dictionary = action.get("to", {})
			_apply_move(int(from.get("file", -1)), int(from.get("rank", -1)), int(to.get("file", -1)), int(to.get("rank", -1)))
		"resign":
			_apply_non_move_result(_engine.resign(_xiangqi, expected_side), "%s 认输" % String(player.get("name", "AI")))
		_:
			_set_message("AI 动作暂不支持")


func _ai_fallback_reason(model_ok: bool, model_error: String, action: Dictionary) -> String:
	if not model_ok:
		return "模型请求失败" if model_error.strip_edges() != "" else "模型无响应"
	match String(action.get("error", "")).strip_edges():
		"invalid_json":
			return "模型未返回有效JSON"
		"invalid_move_id":
			return "模型选择了无效走法"
		"missing_move_id":
			return "模型缺少走法编号"
		"unsupported_action":
			return "模型返回了不支持的动作"
		_:
			return "模型输出无效"


func _show_ai_fallback_toast(player: Dictionary, reason: String = "") -> void:
	var player_name := String(player.get("name", "AI")).strip_edges()
	if player_name == "":
		player_name = "AI"
	var clean_reason := reason.strip_edges()
	if clean_reason == "":
		clean_reason = "模型异常"
	_show_xiangqi_toast("%s：%s，已用本地兜底走法" % [player_name, clean_reason], BOOK_RED)


func _model_profile_for_player(player: Dictionary) -> Dictionary:
	var profile := _model_profile_selector.profile_for_player(player, _model_configs)
	if not profile.is_empty():
		return profile
	_load_model_configs_from_storage()
	return _model_profile_selector.profile_for_player(player, _model_configs)


func _profile_temperature(profile: Dictionary, default_value: float) -> float:
	return _model_profile_selector.temperature(profile, default_value)


func _model_completion_request(profile: Dictionary, messages: Array, temperature: float, max_output_tokens: int, timeout_sec: float, options: Dictionary, purpose: String) -> Dictionary:
	var request_options := options.duplicate(true)
	var response_schema = request_options.get("response_schema", request_options.get("schema", {}))
	var output_type := "json" if response_schema is Dictionary and not (response_schema as Dictionary).is_empty() else "text"
	if request_options.has("output_type"):
		output_type = String(request_options.get("output_type", output_type)).strip_edges().to_lower()
	var transport_mode := "stream" if bool(request_options.get("stream", false)) else "sync"
	if request_options.has("transport_mode"):
		transport_mode = String(request_options.get("transport_mode", transport_mode)).strip_edges().to_lower()
	var output_adapter := _model_adapter_registry.normalize_output_adapter(String(request_options.get("output_adapter", request_options.get("formt_adapter", String(profile.get("formt_adapter", "auto"))))))
	if output_type == "text" and not request_options.has("output_adapter") and not request_options.has("formt_adapter"):
		output_adapter = "none"
	var reasoning_mode := "on" if bool(profile.get("reasoning", false)) else "off"
	if request_options.has("reasoning_mode"):
		reasoning_mode = String(request_options.get("reasoning_mode", reasoning_mode)).strip_edges().to_lower()
	var effective_max_output_tokens := max_output_tokens
	var effective_profile_max_output := int(profile.get("max_output", 0))
	if reasoning_mode == "on":
		effective_max_output_tokens = 0
		effective_profile_max_output = 0
	var request := {
		"purpose": purpose.strip_edges(),
		"provider": String(profile.get("provider", "")).strip_edges(),
		"endpoint": String(profile.get("endpoint", "")).strip_edges(),
		"api_key": String(profile.get("api_key", "")).strip_edges(),
		"model": String(profile.get("model", "")).strip_edges(),
		"transport_mode": transport_mode,
		"output_type": output_type,
		"reasoning_mode": reasoning_mode,
		"output_adapter": output_adapter,
		"reason_adapter": _model_adapter_registry.normalize_reason_adapter(String(profile.get("reason_adapter", "auto"))),
		"temperature": temperature,
		"max_output_tokens": effective_max_output_tokens,
		"max_output": effective_profile_max_output,
		"timeout_sec": timeout_sec,
		"messages": messages.duplicate(true),
		"options": request_options,
	}
	if response_schema is Dictionary and not (response_schema as Dictionary).is_empty():
		request["response_schema"] = (response_schema as Dictionary).duplicate(true)
	return request


func _xiangqi_ai_debug(message: String) -> void:
	if OS.is_debug_build():
		print("[XiangqiAI][debug] %s" % message)


func _print_ai_context_debug(seat: int, context: Dictionary) -> void:
	if not OS.is_debug_build():
		return
	var side := _engine.side_for_seat(seat)
	var label := "红方" if side == XiangqiEngineScript.SIDE_RED else "黑方"
	print("[XiangqiAI][context][%s][seat=%d] %s" % [label, seat + 1, JSON.stringify(context)])


func _active_room() -> Dictionary:
	if _app_state == null:
		return _rooms[0] if not _rooms.is_empty() and _rooms[0] is Dictionary else {}
	var active_id := String(_app_state.active_room_id)
	for room in _rooms:
		if room is Dictionary and String((room as Dictionary).get("id", "")) == active_id:
			return room as Dictionary
	return {}


func _active_room_has_no_people() -> bool:
	for player_value in _players:
		if not (player_value is Dictionary):
			continue
		var player: Dictionary = player_value
		var owner := String(player.get("owner", "")).strip_edges()
		if owner == "self":
			return false
		if owner == "human" and String(player.get("participant_id", player.get("participantId", ""))).strip_edges() != "":
			return false
	for observer_value in _room_observers():
		if not (observer_value is Dictionary):
			continue
		var observer: Dictionary = observer_value
		var participant := String(observer.get("id", observer.get("participantId", ""))).strip_edges()
		if participant == "":
			participant = String(observer.get("participant_id", "")).strip_edges()
		if participant != "":
			return false
	return true


func _destroy_active_room_if_no_people(reason: String, navigate_to_lobby: bool = false) -> bool:
	if not _active_room_has_no_people():
		return false
	var room_id := String(_app_state.active_room_id) if _app_state != null else String(_active_room().get("id", ""))
	if room_id == "":
		return false
	if OS.is_debug_build():
		print("[XiangqiRoom][lifecycle] destroy empty room reason=%s room=%s players=%s" % [reason, room_id, JSON.stringify(_room_people_debug_snapshot())])
	_destroy_active_room(room_id)
	if navigate_to_lobby:
		navigate_requested.emit("lobby", {})
	return true


func _destroy_active_room(room_id: String) -> void:
	var clean_room_id := room_id.strip_edges()
	if clean_room_id == "":
		return
	for i in range(_rooms.size() - 1, -1, -1):
		if _rooms[i] is Dictionary and String((_rooms[i] as Dictionary).get("id", "")) == clean_room_id:
			_rooms.remove_at(i)
	_players.clear()
	for i in range(2):
		_players.append(_empty_seat_data(i))
	_xiangqi = {}
	_history.clear()
	_local_player_index = -1
	_system_message = "房间已销毁"
	if _network_session != null and _network_session.has_method("is_active") and bool(_network_session.call("is_active")):
		if _network_session.has_method("broadcast"):
			_network_session.call("broadcast", "room_closed", {"roomId": clean_room_id})
		_network_session.call("stop")
	if _app_state != null:
		_app_state.active_room_id = ""
	_commit_state()


func _room_people_debug_snapshot() -> Dictionary:
	var seats := []
	for i in range(_players.size()):
		if not (_players[i] is Dictionary):
			continue
		var player: Dictionary = _players[i]
		var owner := String(player.get("owner", "")).strip_edges()
		var participant := String(player.get("participant_id", player.get("participantId", ""))).strip_edges()
		var controller := String(player.get("controller_participant_id", player.get("controllerParticipantId", ""))).strip_edges()
		if owner == "" and participant == "" and controller == "":
			continue
		seats.append({
			"seat": i,
			"name": String(player.get("name", "")),
			"owner": owner,
			"participant": participant,
			"controller": controller,
			"module": String(player.get("player_module", "")),
		})
	return {"seats": seats, "observers": _room_observers()}


func _player_at(index: int) -> Dictionary:
	if index >= 0 and index < _players.size() and _players[index] is Dictionary:
		return (_players[index] as Dictionary).duplicate(true)
	return _empty_seat_data(index)


func _empty_seat_data(index: int) -> Dictionary:
	return {
		"name": "%d号位" % [index + 1],
		"role": _engine.side_label(_engine.side_for_seat(index)) if index >= 0 and index < 2 else "待加入",
		"role_key": _engine.side_for_seat(index) if index >= 0 and index < 2 else "",
		"avatar": "",
		"state": "可落座",
		"motion": AppState.SeatMotion.IDLE,
		"alive": true,
		"ready": false,
		"owner": "",
	}


func _is_bot_player(player: Dictionary) -> bool:
	if String(player.get("owner", "")).strip_edges() == "":
		return false
	return String(player.get("player_module", "")).strip_edges() == "xiangqi_ai" or String(player.get("player_type", "")).strip_edges() == "ai"


func _normalized_bot_profile_for_add(profile: Dictionary) -> Dictionary:
	if not profile.is_empty():
		return profile.duplicate(true)
	for item_value in _bot_profiles:
		if item_value is Dictionary and bool((item_value as Dictionary).get("enabled", true)):
			return (item_value as Dictionary).duplicate(true)
	return {
		"id": "",
		"name": "象棋AI%d" % _bot_serial,
		"model": "默认模型",
		"voice": "系统默认",
		"persona": "",
	}


func _enabled_bot_profiles() -> Array:
	var result := []
	for item_value in _bot_profiles:
		if not (item_value is Dictionary):
			continue
		var profile: Dictionary = item_value
		if bool(profile.get("enabled", true)):
			result.append(profile.duplicate(true))
	return result


func _current_network_participant_id() -> String:
	if _network_session != null and _network_session.has_method("local_participant_id"):
		var id := String(_network_session.call("local_participant_id")).strip_edges()
		if id != "":
			return id
	return "host"


func _piece_at(file: int, rank: int) -> Dictionary:
	var board_value = _xiangqi.get("board", [])
	if not (board_value is Array):
		return {}
	var board: Array = board_value
	if rank < 0 or rank >= board.size() or not (board[rank] is Array):
		return {}
	var row: Array = board[rank]
	if file < 0 or file >= row.size() or not (row[file] is Dictionary):
		return {}
	return (row[file] as Dictionary).duplicate(true)


func _square_position(file: int, rank: int) -> Vector2:
	var scale := _board_render_scale()
	var view_rank := BOARD_RANKS - 1 - rank
	return Vector2(
		(BOARD_GRID_ORIGIN.x + float(file) * BOARD_GRID_STEP.x) * scale.x,
		(BOARD_GRID_ORIGIN.y + float(view_rank) * BOARD_GRID_STEP.y) * scale.y
	)


func _board_render_scale() -> Vector2:
	var board_size := BOARD_VIEW_SIZE
	if _board_layer != null:
		if _board_layer.size.x > 0.0 and _board_layer.size.y > 0.0:
			board_size = _board_layer.size
		else:
			var minimum := _board_layer.get_combined_minimum_size()
			if minimum.x > 0.0 and minimum.y > 0.0:
				board_size = minimum
	return Vector2(board_size.x / BOARD_SVG_SIZE.x, board_size.y / BOARD_SVG_SIZE.y)


func _action_button(text: String, icon_id: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = "XiangqiAction%sButton" % icon_id.capitalize()
	button.text = text
	button.icon = _texture(XiangqiAssetCatalogScript.action_path(icon_id))
	button.expand_icon = true
	button.custom_minimum_size = Vector2(92, 38)
	button.focus_mode = Control.FOCUS_NONE
	_style_fresh_button(button, false, icon_id == "resign")
	button.pressed.connect(func():
		_play_click()
		callback.call()
	)
	return button


func _set_message(message: String) -> void:
	_system_message = message
	if _status_label != null:
		_status_label.text = message
	_commit_state()


func _show_xiangqi_toast(text: String, color: Color = BOOK_GREEN) -> void:
	var message := text.strip_edges()
	if message == "":
		return
	if _toast_layer == null or not is_instance_valid(_toast_layer):
		return
	for child in _toast_layer.get_children():
		if child.name == "XiangqiToast":
			child.queue_free()
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null
	var toast := PanelContainer.new()
	toast.name = "XiangqiToast"
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 0.0
	toast.anchor_bottom = 0.0
	toast.offset_left = -280
	toast.offset_right = 280
	toast.offset_top = 22
	toast.offset_bottom = 72
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_stylebox_override("panel", _style_box(Color(1.0, 0.94, 0.76, 0.96), Color(color.r, color.g, color.b, 0.62), 8, 1))
	var margin := MarginContainer.new()
	_margin_each(margin, 16, 6, 16, 6)
	toast.add_child(margin)
	var label := _label(message, 12, color, true, HORIZONTAL_ALIGNMENT_CENTER)
	label.name = "XiangqiToastLabel"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(label)
	_toast_layer.add_child(toast)
	toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.12)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.22)
	_toast_tween.tween_callback(toast.queue_free)


func _print_move_debug(move: Dictionary) -> void:
	if move.is_empty() or not OS.is_debug_build():
		return
	var piece: Dictionary = move.get("piece", {}) if move.get("piece", {}) is Dictionary else {}
	var captured: Dictionary = move.get("captured", {}) if move.get("captured", {}) is Dictionary else {}
	var from: Dictionary = move.get("from", {}) if move.get("from", {}) is Dictionary else {}
	var to: Dictionary = move.get("to", {}) if move.get("to", {}) is Dictionary else {}
	print("[XiangqiMove][debug] side=%s piece=%s from=(%d,%d) to=(%d,%d) captured=%s text=%s" % [
		String(move.get("side", "")),
		String(piece.get("kind", "")),
		int(from.get("file", -1)),
		int(from.get("rank", -1)),
		int(to.get("file", -1)),
		int(to.get("rank", -1)),
		String(captured.get("kind", "")) if not captured.is_empty() else "",
		String(move.get("text", "")),
	])
	if String(piece.get("kind", "")) == "horse":
		var leg := _horse_leg_square(from, to)
		var leg_piece := _piece_at(int(leg.get("file", -1)), int(leg.get("rank", -1)))
		print("[XiangqiMove][debug] horse_leg=(%d,%d) occupied=%s" % [
			int(leg.get("file", -1)),
			int(leg.get("rank", -1)),
			String(leg_piece.get("kind", "")) if not leg_piece.is_empty() else "",
		])


func _horse_leg_square(from: Dictionary, to: Dictionary) -> Dictionary:
	var from_file := int(from.get("file", -1))
	var from_rank := int(from.get("rank", -1))
	var to_file := int(to.get("file", -1))
	var to_rank := int(to.get("rank", -1))
	var delta_file := to_file - from_file
	var delta_rank := to_rank - from_rank
	if abs(delta_file) == 2:
		return {"file": from_file + (1 if delta_file > 0 else -1), "rank": from_rank}
	return {"file": from_file, "rank": from_rank + (1 if delta_rank > 0 else -1)}


func _xiangqi_voice_debug(message: String) -> void:
	if OS.is_debug_build():
		print("[XiangqiVoice][debug] %s" % message)


func _result_text(result: String) -> String:
	match result:
		XiangqiEngineScript.RESULT_RED_WIN:
			return "红方胜"
		XiangqiEngineScript.RESULT_BLACK_WIN:
			return "黑方胜"
		XiangqiEngineScript.RESULT_DRAW:
			return "和棋"
		_:
			return "棋局进行中"


func _clock_text() -> String:
	if not bool(_xiangqi.get("clock_enabled", false)):
		return "不计时"
	var clock_value = _xiangqi.get("clock_state", {})
	if not (clock_value is Dictionary):
		return "不计时"
	var clock: Dictionary = clock_value
	return "红 %s  黑 %s" % [_format_ms(int(clock.get("red_remaining_ms", 0))), _format_ms(int(clock.get("black_remaining_ms", 0)))]


func _format_ms(value: int) -> String:
	var total_seconds := maxi(0, int(value / 1000))
	return "%02d:%02d" % [int(total_seconds / 60), total_seconds % 60]


func _seat_click_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _on_seat_card_pressed(index: int) -> void:
	_play_click()
	if index < 0 or index >= _players.size():
		return
	if String((_players[index] as Dictionary).get("owner", "")).strip_edges() != "":
		_open_seat_detail(index)
		return
	_open_empty_seat_actions(index)


func _seat_avatar_control(index: int, player: Dictionary, size_px: int) -> Control:
	var avatar = CircleAvatarScript.new()
	avatar.name = "XiangqiSeatAvatar%d" % (index + 1)
	avatar.custom_minimum_size = Vector2(size_px, size_px)
	avatar.texture = _texture(String(player.get("avatar", player.get("base_avatar", ""))))
	avatar.ring_color = Color(0.62, 0.35, 0.09, 0.84)
	avatar.shadow_color = Color(0, 0, 0, 0.18)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return avatar


func _open_seat_detail(index: int) -> void:
	_clear_modal()
	if index < 0 or index >= _players.size() or _modal_layer == null:
		return
	var player := _player_at(index)
	if String(player.get("owner", "")).strip_edges() == "":
		return
	var overlay := Control.new()
	overlay.name = "XiangqiSeatDetailOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(overlay)

	var viewport_size := get_viewport_rect().size
	var popup_size := Vector2(minf(420.0, maxf(320.0, viewport_size.x - 32.0)), 250.0)
	var card := _panel(Color(0.97, 0.90, 0.70, 0.97), Color(0.42, 0.27, 0.10, 0.48), 8)
	card.custom_minimum_size = popup_size
	card.size = popup_size
	card.position = Vector2((viewport_size.x - popup_size.x) * 0.5, 18.0) - _modal_layer.global_position
	overlay.add_child(card)
	var body := _panel_body(card, 14)
	body.add_child(_nowrap_label("%d号位 · %s" % [index + 1, _engine.side_label(_engine.side_for_seat(index))], 15, BOOK_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	row.add_child(_seat_avatar_control(index, player, 72))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	info.add_child(_nowrap_label(String(player.get("name", "%d号位" % [index + 1])), 17, BOOK_TEXT, true))
	info.add_child(_nowrap_label("阵营：%s" % _engine.side_label(_engine.side_for_seat(index)), 12, BOOK_MUTED))
	info.add_child(_nowrap_label("状态：%s" % String(player.get("state", "等待")), 12, BOOK_MUTED))
	info.add_child(_nowrap_label("类型：%s" % ("AI机器人" if _is_bot_player(player) else "真人玩家"), 12, BOOK_MUTED))
	body.add_child(_voice_toggle_button(index))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	if index == _local_player_index:
		actions.add_child(_small_button("离座", false, func(): _stand_up(index)))
	elif _is_bot_player(player):
		actions.add_child(_small_button("移除", false, func(): _remove_bot_at(index), true))
	actions.add_child(_small_button("关闭", false, func(): _clear_modal()))


func _open_add_bot_dialog(index: int) -> void:
	_clear_modal()
	if index < 0 or index >= _players.size():
		return
	if String((_players[index] as Dictionary).get("owner", "")).strip_edges() != "":
		_set_message("该座位已有玩家")
		return
	if _modal_layer == null:
		return
	var overlay := Control.new()
	overlay.name = "AddBotDialogOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(overlay)

	var viewport_size := get_viewport_rect().size
	var popup_size := Vector2(
		minf(640.0, maxf(360.0, viewport_size.x - 32.0)),
		minf(500.0, maxf(320.0, viewport_size.y - 48.0))
	)
	var card := _panel(Color(0.97, 0.90, 0.70, 0.96), Color(0.42, 0.27, 0.10, 0.45), 8)
	card.custom_minimum_size = popup_size
	card.size = popup_size
	card.position = Vector2((viewport_size.x - popup_size.x) * 0.5, 18.0) - _modal_layer.global_position
	overlay.add_child(card)
	var body := _panel_body(card, 14)
	body.add_child(_nowrap_label("添加机器人到 %d号位" % [index + 1], 16, BOOK_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER))

	var enabled_profiles := _enabled_bot_profiles()
	if enabled_profiles.is_empty():
		body.add_child(_label("没有可用机器人配置", 13, BOOK_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var scroll := ScrollContainer.new()
		scroll.name = "AddBotProfileListScroll"
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(scroll)
		var list := GridContainer.new()
		list.name = "AddBotProfileList"
		list.columns = 1 if popup_size.x < 560.0 else 2
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("h_separation", 10)
		list.add_theme_constant_override("v_separation", 10)
		scroll.add_child(list)
		for profile_value in enabled_profiles:
			if profile_value is Dictionary:
				list.add_child(_add_bot_profile_choice_card(index, profile_value as Dictionary))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	actions.add_child(_small_button("取消", false, func(): _clear_modal()))


func _add_bot_profile_choice_card(index: int, profile: Dictionary) -> Control:
	var card := _panel(Color(1.0, 0.94, 0.76, 0.82), Color(0.45, 0.30, 0.12, 0.36), 8)
	card.name = "AddBotProfileCard"
	card.custom_minimum_size = Vector2(0, 86)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	_margin_each(margin, 10, 8, 10, 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(52, 52)
	avatar.texture = _texture(String(profile.get("avatar", profile.get("avatar_path", profile.get("avatarPath", "")))))
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(avatar)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 3)
	row.add_child(text_box)
	text_box.add_child(_nowrap_label(String(profile.get("name", profile.get("displayName", "机器人"))), 14, BOOK_TEXT, true))
	text_box.add_child(_nowrap_label(String(profile.get("model", "默认模型")), 11, BOOK_MUTED))
	var hit := Button.new()
	hit.name = "AddBotProfileHit"
	hit.text = "选择"
	hit.custom_minimum_size = Vector2(58, 34)
	hit.focus_mode = Control.FOCUS_NONE
	_style_fresh_button(hit, true)
	hit.pressed.connect(func():
		_play_click()
		_add_bot_at(index, profile)
	)
	row.add_child(hit)
	return card


func _open_empty_seat_actions(index: int) -> void:
	_clear_modal()
	var seat := find_child("XiangqiSeatCard%d" % [index + 1], true, false) as Control
	if seat == null or _modal_layer == null:
		return
	var sit_button := _seat_bubble("落座", true, func(): _sit_down(index))
	var bot_button := _seat_bubble("AI机器人", false, func(): _open_add_bot_dialog(index))
	_modal_layer.add_child(sit_button)
	_modal_layer.add_child(bot_button)
	_layout_seat_bubbles_above(seat, [sit_button, bot_button])


func _seat_bubble(text: String, primary: bool, callback: Callable) -> Button:
	var button := Button.new()
	button.name = "SeatBubbleAction"
	button.set_meta("seat_bubble", true)
	button.text = text
	button.custom_minimum_size = Vector2(110, 42)
	button.focus_mode = Control.FOCUS_NONE
	_style_fresh_button(button, primary)
	button.pressed.connect(func():
		_play_click()
		callback.call()
	)
	return button


func _layout_seat_bubbles_above(seat: Control, bubbles: Array) -> void:
	if seat == null or _modal_layer == null or bubbles.is_empty():
		return
	var valid_bubbles := []
	for value in bubbles:
		if value is Control:
			valid_bubbles.append(value)
	if valid_bubbles.is_empty():
		return
	var spacing := 10.0
	var total_width := -spacing
	var max_height := 0.0
	for bubble in valid_bubbles:
		var control := bubble as Control
		var bubble_size := _seat_bubble_size(control)
		total_width += bubble_size.x + spacing
		max_height = maxf(max_height, bubble_size.y)
	var center := Vector2(seat.global_position.x + seat.size.x * 0.5, seat.global_position.y + 4.0)
	var x := center.x - total_width * 0.5
	var y := center.y - max_height - 10.0
	var viewport_size := get_viewport_rect().size
	x = clampf(x, 8.0, maxf(8.0, viewport_size.x - total_width - 8.0))
	y = maxf(8.0, y)
	var cursor := x
	for bubble in valid_bubbles:
		var control := bubble as Control
		var bubble_size := _seat_bubble_size(control)
		control.position = Vector2(cursor, y + (max_height - bubble_size.y) * 0.5) - _modal_layer.global_position
		control.size = bubble_size
		cursor += bubble_size.x + spacing


func _seat_bubble_size(control: Control) -> Vector2:
	var size := control.size
	var minimum := control.get_combined_minimum_size()
	size.x = maxf(size.x, minimum.x)
	size.y = maxf(size.y, minimum.y)
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(110, 42)
	return size


func _room_observers() -> Array:
	var room := _active_room()
	var value = room.get("observers", [])
	if value is Array:
		return (value as Array).duplicate(true)
	return []


func _observer_display_name(observer: Dictionary, fallback: String) -> String:
	var name := String(observer.get("displayName", observer.get("name", fallback))).strip_edges()
	return fallback if name == "" else name


func _switch_local_to_observer() -> void:
	var room := _active_room()
	if room.is_empty():
		_set_message("当前没有房间")
		return
	var participant_id := _current_network_participant_id()
	var observers := _room_observers()
	if _observer_index_for_participant(observers, participant_id) >= 0:
		_local_player_index = -1
		_refresh_all()
		return
	if observers.size() >= OBSERVER_SLOT_COUNT:
		_set_message("观战位已满")
		return
	var display_name := _local_nickname
	var identity := _preference_identity_snapshot()
	if _local_player_index >= 0 and _local_player_index < _players.size():
		var player: Dictionary = _players[_local_player_index]
		display_name = String(player.get("name", _local_nickname)).strip_edges()
		identity = player.duplicate(true)
		_players[_local_player_index] = _empty_seat_data(_local_player_index)
	else:
		display_name = String(identity.get("displayName", identity.get("name", _local_nickname))).strip_edges()
	if display_name == "":
		display_name = "观战者"
	observers.append(_observer_payload(participant_id, display_name, identity))
	room["observers"] = observers
	_local_player_index = -1
	_system_message = "%s 进入观战" % display_name
	_clear_modal()
	_commit_state()
	if _destroy_active_room_if_no_people("switch_to_observer", true):
		return
	_refresh_all()


func _observer_index_for_participant(observers: Array, participant_id: String) -> int:
	var clean := participant_id.strip_edges()
	for i in range(observers.size()):
		if observers[i] is Dictionary and String((observers[i] as Dictionary).get("id", "")).strip_edges() == clean:
			return i
	return -1


func _observer_payload(participant_id: String, display_name: String, identity: Dictionary) -> Dictionary:
	return {
		"id": participant_id,
		"participantId": participant_id,
		"displayName": display_name,
		"name": display_name,
		"avatar": String(identity.get("avatar", "")),
		"avatar_id": String(identity.get("avatar_id", identity.get("avatarId", ""))),
		"avatarId": String(identity.get("avatar_id", identity.get("avatarId", ""))),
		"voice_config_id": String(identity.get("voice_config_id", identity.get("voiceConfigId", ""))),
		"voiceConfigId": String(identity.get("voice_config_id", identity.get("voiceConfigId", ""))),
		"playback_voice_config_id": String(identity.get("playback_voice_config_id", identity.get("playbackVoiceConfigId", ""))),
		"playbackVoiceConfigId": String(identity.get("playback_voice_config_id", identity.get("playbackVoiceConfigId", ""))),
	}


func _remove_observer(room: Dictionary, participant_id: String) -> void:
	var value = room.get("observers", [])
	if not (value is Array):
		return
	var clean := participant_id.strip_edges()
	var kept := []
	for observer_value in value as Array:
		if observer_value is Dictionary and String((observer_value as Dictionary).get("id", "")).strip_edges() == clean:
			continue
		kept.append(observer_value)
	room["observers"] = kept


func _leave_room_to_lobby() -> void:
	_clear_modal()
	var participant_id := _current_network_participant_id()
	if _network_session != null and _network_session.has_method("is_client") and bool(_network_session.call("is_client")):
		if _network_session.has_method("request_leave_room"):
			_network_session.call("request_leave_room")
		_network_session.call("stop")
		if _app_state != null:
			_app_state.active_room_id = ""
		_commit_state()
		navigate_requested.emit("lobby", {})
		return
	for i in range(_players.size()):
		if not (_players[i] is Dictionary):
			continue
		var player: Dictionary = _players[i]
		if String(player.get("owner", "")).strip_edges() == "self" or String(player.get("participant_id", player.get("participantId", ""))).strip_edges() == participant_id:
			_players[i] = _empty_seat_data(i)
	_remove_observer(_active_room(), participant_id)
	_local_player_index = -1
	_system_message = "已退出房间"
	_commit_state()
	if _destroy_active_room_if_no_people("leave_room", true):
		return
	navigate_requested.emit("lobby", {})


func _preference_identity_snapshot() -> Dictionary:
	var nickname := _local_nickname.strip_edges()
	var avatar_id := ""
	var avatar_path := ""
	var playback_voice_config_id := "voice_system_default"
	if _preference_repository != null:
		var result: Dictionary = _preference_repository.get_preferences()
		if bool(result.get("ok", false)):
			var state: Dictionary = result.get("state", {})
			var preferred_name := String(state.get("nickname", "")).strip_edges()
			if preferred_name != "":
				nickname = preferred_name
			avatar_id = String(state.get("avatar_id", "")).strip_edges()
			playback_voice_config_id = String(state.get("playback_voice_config_id", playback_voice_config_id)).strip_edges()
			avatar_path = _preference_avatar_path(avatar_id)
	if nickname == "":
		nickname = "玩家"
	if playback_voice_config_id == "":
		playback_voice_config_id = "voice_system_default"
	return {
		"nickname": nickname,
		"displayName": nickname,
		"avatar_id": avatar_id,
		"avatarId": avatar_id,
		"avatar": avatar_path,
		"playback_voice_config_id": playback_voice_config_id,
		"playbackVoiceConfigId": playback_voice_config_id,
		"voice_config_id": playback_voice_config_id,
		"voiceConfigId": playback_voice_config_id,
	}


func _preference_avatar_path(avatar_id: String) -> String:
	var clean := avatar_id.strip_edges()
	if clean == "" or _preference_repository == null or not _preference_repository.has_method("list_avatars"):
		return ""
	var result: Dictionary = _preference_repository.list_avatars()
	if not bool(result.get("ok", false)):
		return ""
	var avatars_value = result.get("avatars", [])
	if not (avatars_value is Array):
		return ""
	for item in avatars_value as Array:
		if item is Dictionary and String((item as Dictionary).get("id", "")).strip_edges() == clean:
			return String((item as Dictionary).get("path", "")).strip_edges()
	return ""


func _clear_children_now(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _clear_modal() -> void:
	if _modal_layer == null:
		return
	_clear_children_now(_modal_layer)
