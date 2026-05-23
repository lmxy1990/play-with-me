extends "res://scripts/room/werewolf/werewolf_room_page_state.gd"

const BotModelRequestTrackerScript := preload("res://scripts/core/bot/bot_model_request_tracker.gd")
const WerewolfHumanPlayerTaskControllerScript := preload("res://scripts/player/werewolf/human/werewolf_human_player_task_controller.gd")
const WerewolfBotRuntimeScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_player_runtime.gd")
const WerewolfMemoryScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_memory.gd")
const WerewolfMemoryContextScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_memory_context.gd")
const PromptPolicyScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_prompt_policy.gd")
const WerewolfWolfPrivateFlowScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_wolf_private_flow.gd")
const WerewolfTurnContextBuilderScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_turn_context_builder.gd")

const MAX_WOLF_NIGHT_CHAT_MESSAGES := 3
const MEMORY_CONTEXT_TOKEN_LIMIT := 1024
const BOT_DEFAULT_CONTEXT_BUDGET_TOKENS := 8192
const BOT_MODEL_TIMEOUT_SEC := 150.0
const REMOTE_BOT_DEVICE_TASK_TIMEOUT_SEC := BOT_MODEL_TIMEOUT_SEC + 10.0
const BOT_MODEL_MAX_OUTPUT_TOKENS := AppState.DEFAULT_ROOM_MAX_OUTPUT_TOKENS
const WEREWOLF_BOT_PROMPT_LOG_PATH := "user://werewolf_bot_prompts.jsonl"
const WEREWOLF_BOT_PROMPT_TEXT_LOG_PATH := "user://werewolf_bot_prompts_by_identity.txt"

var _bot_request_tracker = BotModelRequestTrackerScript.new()
var _werewolf_human_task_controller = WerewolfHumanPlayerTaskControllerScript.new()
var _bot_runtime = WerewolfBotRuntimeScript.new()
var _werewolf_memory_builder = WerewolfMemoryScript.new()
var _werewolf_memory_context = WerewolfMemoryContextScript.new()
var _wolf_private_flow = WerewolfWolfPrivateFlowScript.new()
var _werewolf_turn_context_builder = WerewolfTurnContextBuilderScript.new()
var _auto_resolving := false
var _wolf_private_history: Array = []
var _bot_wolf_speech_keys := {}
var _bot_wolf_target_vote_keys := {}
var _bot_wolf_target_votes := {}
var _waiting_bot_action := false
var _waiting_bot_speech := false
var _auto_resolve_waiting_for_tts := false
var _auto_resolve_deferred_pending := false
var _werewolf_bot_prompt_log_last_error := ""
var _werewolf_bot_prompt_log_sequence := 0
var _last_model_error_popup_signature := ""
var _last_model_error_popup_msec := 0
var _bot_flow_halted := false
var _bot_flow_halt_error: Dictionary = {}
var _bot_stream_preview_texts := {}
var _bot_model_request_to_device_task := {}
var _controlled_bot_model_profiles := {}
var _controlled_bot_model_profile_errors := {}
var _controlled_bot_model_profile_signature := ""
var _last_bot_reasoning_warning_signature := ""
var _last_bot_reasoning_warning_msec := 0


func _bot_debug(message: String) -> void:
	if OS.is_debug_build():
		print(message)


func _clear_werewolf_room_runtime() -> void:
	_bot_request_tracker.clear()
	_auto_resolving = false
	_wolf_private_history.clear()
	_bot_wolf_speech_keys.clear()
	_bot_wolf_target_vote_keys.clear()
	_bot_wolf_target_votes.clear()
	_player_speech_output.clear_muted_speaker_keys()
	_waiting_bot_action = false
	_waiting_bot_speech = false
	_auto_resolve_waiting_for_tts = false
	_auto_resolve_deferred_pending = false
	_bot_flow_halted = false
	_bot_flow_halt_error.clear()
	_bot_stream_preview_texts.clear()
	_bot_model_request_to_device_task.clear()
	_controlled_bot_model_profiles.clear()
	_controlled_bot_model_profile_errors.clear()
	_controlled_bot_model_profile_signature = ""
	_last_bot_reasoning_warning_signature = ""
	_last_bot_reasoning_warning_msec = 0
	_pending_action = ""
	_pending_action_icon = ""
	_pending_actor_index = -1
	_speech_prompt_index = -1
	if has_method("_clear_presentation_ack_state"):
		call("_clear_presentation_ack_state")
	if has_method("_clear_center_speech_display"):
		call("_clear_center_speech_display")


func _initialize_controlled_bot_model_profiles(reason: String = "", force: bool = false) -> void:
	var signature := _controlled_bot_signature()
	if not force and signature == _controlled_bot_model_profile_signature:
		return
	_controlled_bot_model_profile_signature = signature
	_controlled_bot_model_profiles.clear()
	_controlled_bot_model_profile_errors.clear()
	if signature == "[]":
		_bot_debug("[WerewolfBotModel][debug] local bot model profile init skipped reason=%s controlled=0" % reason.strip_edges())
		return
	var storage_loaded := _load_model_configs_from_storage(false)
	var storage_required := _bot_model_config_storage_required()
	_bot_debug("[WerewolfBotModel][debug] local bot model profile init reason=%s force=%s storage_loaded=%s storage_required=%s models=%d signature=%s" % [
		reason.strip_edges(),
		str(force),
		str(storage_loaded),
		str(storage_required),
		_model_configs.size(),
		signature,
	])
	for i in range(_players.size()):
		if not _local_controls_bot_actor(i):
			continue
		var key := _bot_model_profile_key_for_actor(i)
		var model_name := _bot_model_name_for_actor(i)
		if model_name == "":
			var private_profile := _local_bot_profile_for_actor(i)
			if not private_profile.is_empty():
				model_name = _bot_profile_model_name_for_local_ai(private_profile)
		if storage_required and not storage_loaded:
			_controlled_bot_model_profile_errors[key] = "执行设备模型配置数据库不可用，无法初始化本机机器人模型配置"
			continue
		if model_name == "":
			_controlled_bot_model_profile_errors[key] = "机器人任务缺少模型标识"
			continue
		var profile := _model_profile_for_name(model_name)
		if profile.is_empty():
			_controlled_bot_model_profile_errors[key] = "执行设备未找到模型配置：%s" % model_name
			continue
		_controlled_bot_model_profiles[key] = profile.duplicate(true)
		_bot_debug("[WerewolfBotModel][debug] local bot model profile cached key=%s actor=%s model=%s provider=%s endpoint=%s formt_adapter=%s reason_adapter=%s api_key=%s" % [
			key,
			_player_title(i),
			String(profile.get("model", "")),
			String(profile.get("provider", "")),
			String(profile.get("endpoint", "")),
			String(profile.get("formt_adapter", "")),
			String(profile.get("reason_adapter", "")),
			_bot_model_api_key_state(profile),
		])


func _ensure_controlled_bot_model_profiles_initialized(reason: String = "") -> void:
	var signature := _controlled_bot_signature()
	if signature == _controlled_bot_model_profile_signature and (signature == "[]" or not _controlled_bot_model_profiles.is_empty() or not _controlled_bot_model_profile_errors.is_empty()):
		return
	_initialize_controlled_bot_model_profiles(reason, true)


func _controlled_bot_model_profile_for_actor(actor_index: int, reason: String = "") -> Dictionary:
	_ensure_controlled_bot_model_profiles_initialized(reason)
	if not _local_controls_bot_actor(actor_index):
		return {}
	var key := _bot_model_profile_key_for_actor(actor_index)
	var profile_value = _controlled_bot_model_profiles.get(key, {})
	if profile_value is Dictionary:
		return (profile_value as Dictionary).duplicate(true)
	return {}


func _controlled_bot_model_profile_error_for_actor(actor_index: int) -> String:
	var key := _bot_model_profile_key_for_actor(actor_index)
	var cached_error := String(_controlled_bot_model_profile_errors.get(key, "")).strip_edges()
	if cached_error != "":
		return cached_error
	var model_name := _bot_model_name_for_actor(actor_index)
	if model_name == "":
		return "机器人任务缺少模型标识"
	if not _local_controls_bot_actor(actor_index):
		return "当前设备不控制该机器人"
	return "本机机器人模型配置未初始化：%s" % model_name


func _controlled_bot_model_profiles_debug_snapshot() -> Dictionary:
	var cached := []
	for key in _controlled_bot_model_profiles.keys():
		var profile_value = _controlled_bot_model_profiles.get(key, {})
		if not (profile_value is Dictionary):
			continue
		var profile: Dictionary = profile_value
		cached.append({
			"key": String(key),
			"model": String(profile.get("model", "")),
			"provider": String(profile.get("provider", "")),
			"endpoint": String(profile.get("endpoint", "")),
			"formtAdapter": String(profile.get("formt_adapter", "")),
			"reasonAdapter": String(profile.get("reason_adapter", "")),
			"apiKey": _bot_model_api_key_state(profile),
		})
	return {
		"signature": _controlled_bot_model_profile_signature,
		"cachedCount": cached.size(),
		"errorCount": _controlled_bot_model_profile_errors.size(),
		"cached": cached,
		"errors": _controlled_bot_model_profile_errors.duplicate(true),
	}


func _controlled_bot_signature() -> String:
	var parts := []
	for i in range(_players.size()):
		if not _local_controls_bot_actor(i):
			continue
		var player: Dictionary = _players[i]
		var profile_id := _local_private_bot_profile_id_for_seat(i)
		if profile_id == "":
			continue
		parts.append("%d|%s|%s|%s" % [
			i,
			String(player.get("id", "")),
			String(player.get("controller_participant_id", "")),
			profile_id,
		])
	return JSON.stringify(parts)


func _local_controls_bot_actor(actor_index: int) -> bool:
	if actor_index < 0 or actor_index >= _players.size() or not (_players[actor_index] is Dictionary):
		return false
	var player: Dictionary = _players[actor_index]
	if String(player.get("owner", "")).strip_edges() == "":
		return false
	if _local_private_bot_profile_id_for_seat(actor_index) == "":
		return false
	var controller := String(player.get("controller_participant_id", "")).strip_edges()
	var local_participant := _current_network_participant_id()
	return controller == local_participant or (controller == "" and local_participant == "host")


func _bot_model_profile_key_for_actor(actor_index: int) -> String:
	if actor_index < 0 or actor_index >= _players.size() or not (_players[actor_index] is Dictionary):
		return "seat_%d" % actor_index
	var player: Dictionary = _players[actor_index]
	var id := String(player.get("id", "")).strip_edges()
	if id != "":
		return "%d|%s" % [actor_index, id]
	return "seat_%d" % actor_index


func _local_bot_profile_for_actor(actor_index: int) -> Dictionary:
	if actor_index < 0 or actor_index >= _players.size() or not (_players[actor_index] is Dictionary):
		return {}
	var local_private_profile := _local_private_bot_profile_for_seat(actor_index)
	if not local_private_profile.is_empty():
		return local_private_profile
	return {}


func _bot_profile_model_name_for_local_ai(profile: Dictionary) -> String:
	return String(profile.get("model", "")).strip_edges()


func _bot_model_config_storage_required() -> bool:
	return bool(_app_state != null and _app_state.persistence_enabled and (OS.get_name() == "Android" or _model_config_store.backend_attached()))


func _on_werewolf_pause_changed(paused: bool) -> void:
	if not paused:
		return
	_bot_request_tracker.clear()
	_bot_stream_preview_texts.clear()
	_bot_model_request_to_device_task.clear()
	if has_method("_clear_presentation_ack_state"):
		call("_clear_presentation_ack_state")
	if has_method("_clear_device_task_state"):
		call("_clear_device_task_state")
	_auto_resolving = false
	_waiting_bot_action = false
	_waiting_bot_speech = false
	_auto_resolve_waiting_for_tts = false
	_auto_resolve_deferred_pending = false


func _sync_werewolf_view_state() -> void:
	if _werewolf.is_empty():
		_werewolf = _engine.default_state()
	_pending_action = ""
	_pending_action_icon = ""
	_pending_actor_index = -1
	_speech_prompt_index = -1
	var action: Dictionary = _werewolf.get("current_action", {})
	if not action.is_empty():
		_pending_action = String(action.get("label", "行动"))
		_pending_action_icon = String(action.get("icon", ""))
		_pending_actor_index = int(action.get("actor_index", -1))
	_speech_prompt_index = int(_werewolf.get("speech_index", -1))
	_phase_night = _engine.is_night_phase(_werewolf)
	if _system_message == "":
		_system_message = _engine.phase_label(_werewolf)
	if not _is_network_client() and not _bot_flow_halted and not _is_werewolf_paused():
		_schedule_auto_resolve_bot_turns()


func _maybe_start_local_game() -> bool:
	return _start_local_game_if_ready()


func _start_local_game_if_ready() -> bool:
	var gate: Dictionary = _room_runtime.start_gate(_players, _werewolf)
	if not bool(gate.get("ok", false)):
		_system_message = String(gate.get("message", "等待开局"))
		_sync_werewolf_view_state()
		if has_method("_show_room_system_message_toast"):
			call("_show_room_system_message_toast")
		_refresh_center_panel()
		return false
	var room_id := String(_app_state.active_room_id) if _app_state != null else "local_room"
	var occupied: Array = gate.get("occupied_indices", [])
	var room: Dictionary = _active_room()
	var map_id := String(room.get("map_id", "basic_village"))
	_bot_flow_halted = false
	_bot_flow_halt_error.clear()
	_finalize_completed_werewolf_game_if_needed()
	_clear_previous_werewolf_round_data_for_restart(map_id)
	var result: Dictionary = _engine.start_game(room_id, _players, occupied, _local_player_index, map_id)
	return _apply_engine_result(result)


func _start_game_from_button() -> void:
	if _is_network_client():
		_system_message = "等待房主开始游戏"
		if has_method("_show_room_system_message_toast"):
			call("_show_room_system_message_toast")
		_refresh_center_panel()
		_flash_effect("skip")
		return
	_start_local_game_if_ready()


func _reset_werewolf_round_presentation() -> void:
	_history.clear()
	if has_method("_reset_werewolf_final_perspective_text_debug"):
		call("_reset_werewolf_final_perspective_text_debug")
	if _tts_runtime != null and is_instance_valid(_tts_runtime) and _tts_runtime.has_method("stop"):
		_tts_runtime.call("stop")
	if _player_speech_output != null and _player_speech_output.has_method("clear"):
		_player_speech_output.call("clear")
	if has_method("_clear_presentation_ack_state"):
		call("_clear_presentation_ack_state")
	if has_method("_clear_center_speech_display"):
		call("_clear_center_speech_display")


func _should_show_start_button() -> bool:
	if _is_game_started() or _is_network_client():
		return false
	var gate: Dictionary = _room_runtime.start_gate(_players, _werewolf)
	return bool(gate.get("ok", false))


func _apply_engine_result(result: Dictionary) -> bool:
	if _bot_flow_halted:
		if has_method("_show_system_progress_toast"):
			call("_show_system_progress_toast", _system_message if _system_message != "" else "机器人错误，游戏已中止", 6.0)
		_flash_effect("skip")
		return false
	if _is_werewolf_paused():
		if has_method("_show_system_progress_toast"):
			call("_show_system_progress_toast", _system_message if _system_message != "" else "游戏已暂停，等待真人玩家重连", 6.0)
		_flash_effect("skip")
		return false
	if not bool(result.get("ok", false)):
		_system_message = String(result.get("message", "操作失败"))
		_sync_werewolf_view_state()
		_refresh_all_seats()
		_refresh_center_panel()
		_commit_state()
		_flash_effect(String(result.get("effect", "skip")))
		return false
	if result.has("players"):
		_players = (result["players"] as Array).duplicate(true)
	if result.has("werewolf"):
		_werewolf = (result["werewolf"] as Dictionary).duplicate(true)
	if result.has("history"):
		for item in result["history"]:
			if item is Dictionary:
				_append_history_item((item as Dictionary).duplicate(true))
	var message := String(result.get("message", ""))
	if message != "":
		_system_message = message
	_sync_werewolf_view_state()
	_refresh_all_seats()
	_refresh_room_controls()
	_refresh_center_panel()
	_finalize_completed_werewolf_game_if_needed()
	_commit_state()
	_flash_effect(String(result.get("effect", "action")))
	for item in result.get("death_indices", []):
		var index := int(item)
		if index >= 0 and index < _seat_cards.size():
			_seat_cards[index].start_motion(SeatMotion.DEAD)
	if not _bot_flow_halted:
		_schedule_auto_resolve_bot_turns()
	return true


func _apply_engine_result_without_auto(result: Dictionary) -> bool:
	if _bot_flow_halted:
		if has_method("_show_system_progress_toast"):
			call("_show_system_progress_toast", _system_message if _system_message != "" else "机器人错误，游戏已中止", 6.0)
		_flash_effect("skip")
		return false
	if _is_werewolf_paused():
		if has_method("_show_system_progress_toast"):
			call("_show_system_progress_toast", _system_message if _system_message != "" else "游戏已暂停，等待真人玩家重连", 6.0)
		_flash_effect("skip")
		return false
	if not bool(result.get("ok", false)):
		_system_message = String(result.get("message", "操作失败"))
		_flash_effect(String(result.get("effect", "skip")))
		return false
	if result.has("players"):
		_players = (result["players"] as Array).duplicate(true)
	if result.has("werewolf"):
		_werewolf = (result["werewolf"] as Dictionary).duplicate(true)
	if result.has("history"):
		for item in result["history"]:
			if item is Dictionary:
				_append_history_item((item as Dictionary).duplicate(true))
	var message := String(result.get("message", ""))
	if message != "":
		_system_message = message
	_sync_werewolf_view_state_without_auto()
	_refresh_all_seats()
	_refresh_room_controls()
	_refresh_center_panel()
	_finalize_completed_werewolf_game_if_needed()
	_commit_state()
	_flash_effect(String(result.get("effect", "action")))
	for item in result.get("death_indices", []):
		var index := int(item)
		if index >= 0 and index < _seat_cards.size():
			_seat_cards[index].start_motion(SeatMotion.DEAD)
	return true


func _auto_resolve_bot_turns() -> void:
	if _bot_flow_halted:
		_auto_resolve_waiting_for_tts = false
		_auto_resolve_deferred_pending = false
		return
	if _is_werewolf_paused():
		_auto_resolve_waiting_for_tts = false
		_auto_resolve_deferred_pending = false
		return
	if _presentation_pending_for_auto_advance():
		_auto_resolve_waiting_for_tts = true
		return
	if _device_task_blocks_auto_advance():
		_bot_debug("[WerewolfDeviceTask][debug] auto resolve gated reason=device_task_pending snapshot=%s" % JSON.stringify(_device_task_snapshot()))
		return
	if _auto_resolving or _waiting_bot_action or _waiting_bot_speech or _mode != Mode.TABLE or _is_network_client():
		return
	_auto_resolve_waiting_for_tts = false
	_auto_resolving = true
	var guard := 0
	while guard < 32:
		guard += 1
		_sync_werewolf_view_state_without_auto()
		if _pending_action != "":
			_request_player_device_action_if_needed(_pending_actor_index)
			break
		if _speech_prompt_index >= 0:
			_request_player_device_speech_if_needed(_speech_prompt_index)
			break
		break
	_sync_werewolf_view_state_without_auto()
	_refresh_all_seats()
	_refresh_room_controls()
	_refresh_center_panel()
	_commit_state()
	_auto_resolving = false


func _schedule_auto_resolve_bot_turns() -> void:
	if _bot_flow_halted:
		_auto_resolve_waiting_for_tts = false
		_auto_resolve_deferred_pending = false
		return
	if _is_werewolf_paused():
		_auto_resolve_waiting_for_tts = false
		_auto_resolve_deferred_pending = false
		return
	if _mode != Mode.TABLE or _is_network_client():
		_auto_resolve_waiting_for_tts = false
		return
	if _presentation_pending_for_auto_advance():
		_auto_resolve_waiting_for_tts = true
		return
	if _device_task_blocks_auto_advance():
		_bot_debug("[WerewolfDeviceTask][debug] schedule gated reason=device_task_pending snapshot=%s" % JSON.stringify(_device_task_snapshot()))
		return
	_auto_resolve_waiting_for_tts = false
	if _auto_resolve_deferred_pending:
		return
	_auto_resolve_deferred_pending = true
	_run_scheduled_auto_resolve_bot_turns.call_deferred()


func _run_scheduled_auto_resolve_bot_turns() -> void:
	if not _auto_resolve_deferred_pending:
		return
	if _bot_flow_halted:
		_auto_resolve_deferred_pending = false
		_auto_resolve_waiting_for_tts = false
		return
	if _is_werewolf_paused():
		_auto_resolve_deferred_pending = false
		_auto_resolve_waiting_for_tts = false
		return
	_auto_resolve_deferred_pending = false
	_auto_resolve_bot_turns()


func _pause_auto_loop_for_tts_if_needed() -> bool:
	if not _presentation_pending_for_auto_advance():
		return false
	_auto_resolve_waiting_for_tts = true
	return true


func _presentation_pending_for_auto_advance() -> bool:
	return has_method("_presentation_ack_gate_blocks_auto_advance") and bool(call("_presentation_ack_gate_blocks_auto_advance"))


func _tts_playback_pending_for_auto_advance() -> bool:
	if _tts_runtime == null or not is_instance_valid(_tts_runtime):
		return false
	if _mode != Mode.TABLE or _is_network_client():
		return false
	if _tts_runtime.has_method("pending_count"):
		return int(_tts_runtime.call("pending_count")) > 0
	if _tts_runtime.has_method("is_speaking"):
		return bool(_tts_runtime.call("is_speaking"))
	return false


func _resume_auto_resolve_after_tts_if_ready() -> void:
	if _bot_flow_halted:
		_auto_resolve_waiting_for_tts = false
		return
	if _is_werewolf_paused():
		_auto_resolve_waiting_for_tts = false
		return
	if not _auto_resolve_waiting_for_tts:
		return
	if _presentation_pending_for_auto_advance():
		return
	_schedule_auto_resolve_bot_turns()


func _resume_auto_resolve_after_center_speech_if_ready() -> void:
	if _bot_flow_halted:
		_auto_resolve_waiting_for_tts = false
		return
	if _is_werewolf_paused():
		_auto_resolve_waiting_for_tts = false
		return
	if not _auto_resolve_waiting_for_tts:
		return
	if _presentation_pending_for_auto_advance():
		return
	_schedule_auto_resolve_bot_turns()


func _on_presentation_ack_gate_open(_presentation_id: String) -> void:
	if has_method("_present_next_deferred_center_history_item") and bool(call("_present_next_deferred_center_history_item")):
		return
	if has_method("_show_next_queued_center_speech_item") and bool(call("_show_next_queued_center_speech_item")):
		return
	if _bot_flow_halted:
		_auto_resolve_waiting_for_tts = false
		return
	if _is_werewolf_paused():
		_auto_resolve_waiting_for_tts = false
		return
	if not _presentation_pending_for_auto_advance():
		_schedule_auto_resolve_bot_turns()


func _on_device_task_gate_open(task_id: String) -> void:
	_bot_debug("[WerewolfDeviceTask][debug] gate open id=%s snapshot=%s" % [task_id, JSON.stringify(_device_task_snapshot())])
	if _bot_flow_halted:
		_auto_resolve_waiting_for_tts = false
		return
	if _is_werewolf_paused():
		_auto_resolve_waiting_for_tts = false
		return
	if not _presentation_pending_for_auto_advance() and not _device_task_blocks_auto_advance():
		_schedule_auto_resolve_bot_turns()


func _on_tts_speech_finished(item: Dictionary) -> void:
	super._on_tts_speech_finished(item)
	_resume_auto_resolve_after_tts_if_ready()


func _on_tts_speech_failed(item: Dictionary, error: String) -> void:
	super._on_tts_speech_failed(item, error)
	_resume_auto_resolve_after_tts_if_ready()


func _sync_werewolf_view_state_without_auto() -> void:
	if _werewolf.is_empty():
		_werewolf = _engine.default_state()
	_pending_action = ""
	_pending_action_icon = ""
	_pending_actor_index = -1
	_speech_prompt_index = -1
	var action: Dictionary = _werewolf.get("current_action", {})
	if not action.is_empty():
		_pending_action = String(action.get("label", "行动"))
		_pending_action_icon = String(action.get("icon", ""))
		_pending_actor_index = int(action.get("actor_index", -1))
	_speech_prompt_index = int(_werewolf.get("speech_index", -1))
	_phase_night = _engine.is_night_phase(_werewolf)
	if _system_message == "":
		_system_message = _engine.phase_label(_werewolf)


func _is_bot_actor(index: int) -> bool:
	if index < 0 or index >= _players.size():
		return false
	if not (_players[index] is Dictionary):
		return false
	if String((_players[index] as Dictionary).get("owner", "")).strip_edges() == "":
		return false
	return _local_private_bot_profile_id_for_seat(index) != ""


func _request_player_device_action_if_needed(actor_index: int) -> bool:
	if _is_werewolf_paused():
		return true
	if actor_index < 0 or actor_index >= _players.size():
		return false
	if _device_task_pending_for_turn("player_action", actor_index):
		return true
	var action: Dictionary = _werewolf.get("current_action", {}) if _werewolf.get("current_action", {}) is Dictionary else {}
	if action.is_empty() or int(action.get("actor_index", -1)) != actor_index:
		return false
	var action_key := String(action.get("key", "")).strip_edges()
	var question := "%s 需要选择目标" % _player_title(actor_index)
	if action_key == "sheriff_speech_order":
		question = "%s 需要决定白天发言顺序" % _player_title(actor_index)
	var task := _create_device_task_for_actor("player_action", actor_index, {
		"action": action.duplicate(true),
		"question": question,
	})
	if task.is_empty():
		return false
	if not _route_device_task(task):
		_remove_device_task(String(task.get("id", "")))
		_system_message = "%s 的设备不在线，无法行动" % _player_title(actor_index)
		if has_method("_show_system_progress_toast"):
			call("_show_system_progress_toast", _system_message, 8.0)
		_refresh_center_panel()
		_flash_effect("skip")
		return false
	_system_message = "已下发行动给 %s 的设备" % _player_title(actor_index)
	_commit_state()
	return true


func _request_human_device_action_if_needed(actor_index: int) -> bool:
	return _request_player_device_action_if_needed(actor_index)


func _request_player_device_speech_if_needed(speaker_index: int) -> bool:
	if _is_werewolf_paused():
		return true
	if speaker_index < 0 or speaker_index >= _players.size():
		return false
	if _device_task_pending_for_turn("player_speech", speaker_index):
		return true
	if _speech_prompt_index != speaker_index:
		return false
	var task := _create_device_task_for_actor("player_speech", speaker_index, {
		"question": "%s 需要发言" % _player_title(speaker_index),
	})
	if task.is_empty():
		return false
	if not _route_device_task(task):
		_remove_device_task(String(task.get("id", "")))
		_system_message = "%s 的设备不在线，无法发言" % _player_title(speaker_index)
		if has_method("_show_system_progress_toast"):
			call("_show_system_progress_toast", _system_message, 8.0)
		_refresh_center_panel()
		_flash_effect("skip")
		return false
	_system_message = "已下发发言给 %s 的设备" % _player_title(speaker_index)
	_commit_state()
	return true


func _request_human_device_speech_if_needed(speaker_index: int) -> bool:
	return _request_player_device_speech_if_needed(speaker_index)


func _advance_bot_wolf_chain(submitter_index: int) -> String:
	var wolf_indices := _alive_wolf_indices()
	if wolf_indices.is_empty():
		return "blocked"
	for actor_index in wolf_indices:
		if _bot_wolf_target_vote_keys.has(_wolf_target_vote_key(int(actor_index))):
			continue
		if _request_player_device_action_if_needed(int(actor_index)):
			return "waiting"
		return "blocked"
	var target := _resolved_wolf_target_index(submitter_index)
	if target < 0:
		return "blocked"
	var result: Dictionary = _engine.apply_target(_werewolf, _players, target, _local_player_index)
	if bool(result.get("ok", false)):
		_record_bot_decision(submitter_index, target, "wolf_kill")
	if not _apply_engine_result_without_auto(result):
		return "blocked"
	if target >= 0 and target < _seat_cards.size():
		_seat_cards[target].play_action_effect("kill")
	return "advanced"


func _alive_wolf_indices() -> Array:
	var result := []
	for i in range(_players.size()):
		var player: Dictionary = _players[i]
		if String(player.get("owner", "")) != "" and bool(player.get("alive", true)) and _role_catalog.can_wolf_night_kill(String(player.get("role_key", ""))):
			result.append(i)
	return result


func _controlled_alive_wolf_bot_indices() -> Array:
	var result := []
	for i in range(_players.size()):
		var player: Dictionary = _players[i]
		if _local_controls_bot_actor(i) and bool(player.get("alive", true)) and _role_catalog.can_wolf_night_kill(String(player.get("role_key", ""))):
			result.append(i)
	return result


func _reset_wolf_private_flow() -> void:
	_wolf_private_flow.reset(_wolf_private_history, _bot_wolf_speech_keys, _bot_wolf_target_vote_keys, _bot_wolf_target_votes)


func _clear_previous_werewolf_round_data_for_restart(map_id: String = "") -> void:
	_reset_werewolf_round_presentation()
	_reset_wolf_private_flow()
	_reset_werewolf_bot_prompt_logs()
	_reset_werewolf_session_memories(map_id)


func _wolf_night_prefix(kind: String) -> String:
	var room_id := String(_app_state.active_room_id) if _app_state != null else "local_room"
	return _wolf_private_flow.night_prefix(room_id, int(_werewolf.get("day", 0)), kind)


func _wolf_speech_key(actor_index: int) -> String:
	return _wolf_private_flow.speech_key(_wolf_night_prefix("wolf_speech"), _player_id_for_index(actor_index))


func _wolf_target_vote_key(actor_index: int) -> String:
	return _wolf_private_flow.target_vote_key(_wolf_target_vote_prefix(), _player_id_for_index(actor_index))


func _wolf_target_vote_prefix() -> String:
	var room_id := String(_app_state.active_room_id) if _app_state != null else "local_room"
	return _wolf_private_flow.target_vote_prefix(room_id, int(_werewolf.get("day", 0)))


func _wolf_speech_count_for_current_night() -> int:
	return _wolf_private_flow.speech_count_for_prefix(_bot_wolf_speech_keys, _wolf_night_prefix("wolf_speech"))


func _record_wolf_private_chat(actor_index: int, speech: String, mark_bot_speech: bool = false) -> bool:
	if actor_index < 0 or actor_index >= _players.size():
		return false
	var content := speech.strip_edges()
	if content == "":
		content = "（跳过狼队夜聊）"
	var result: Dictionary = _wolf_private_flow.record_chat(
		_wolf_private_history,
		_bot_wolf_speech_keys,
		_wolf_speech_key(actor_index),
		actor_index,
		_player_title(actor_index),
		_player_id_for_index(actor_index),
		int(_werewolf.get("day", 0)),
		String(_werewolf.get("phase", "")),
		content
	)
	if not bool(result.get("ok", false)):
		return false
	content = String(result.get("content", ""))
	if mark_bot_speech:
		_record_bot_speech(actor_index, content)
	_system_message = "狼队夜聊已更新"
	_refresh_all_seats()
	_refresh_center_panel()
	_commit_state()
	return true


func _record_bot_wolf_chat(actor_index: int, speech: String) -> bool:
	return _record_wolf_private_chat(actor_index, speech, true)


func _record_bot_wolf_target_vote(actor_index: int, decision: Dictionary) -> bool:
	var normalized := _normalized_wolf_target_vote_decision(actor_index, decision)
	var target_index := int(normalized.get("target_index", -1))
	if not _is_legal_wolf_target_index(actor_index, target_index):
		return false
	var result: Dictionary = _wolf_private_flow.record_target_vote(
		_bot_wolf_target_vote_keys,
		_bot_wolf_target_votes,
		_wolf_target_vote_key(actor_index),
		normalized
	)
	if not bool(result.get("ok", false)):
		return false
	_record_bot_decision(actor_index, target_index, "wolf_kill")
	_system_message = "狼队目标票已更新"
	_refresh_all_seats()
	_refresh_center_panel()
	_commit_state()
	return true


func _normalized_wolf_target_vote_decision(actor_index: int, decision: Dictionary) -> Dictionary:
	return _werewolf_turn_context_builder.normalized_wolf_target_vote(_ai_turn_input(), actor_index, decision)


func _resolved_wolf_target_index(submitter_index: int) -> int:
	return _werewolf_turn_context_builder.resolved_wolf_target_index(_ai_turn_input(), submitter_index)


func _latest_wolf_target_intent(actor_index: int = -1) -> Dictionary:
	return _werewolf_turn_context_builder.latest_wolf_target_intent(_ai_turn_input(), actor_index)


func _wolf_target_intents_debug() -> Array:
	return _werewolf_turn_context_builder.wolf_target_intents_debug(_ai_turn_input())


func _wolf_target_vote_debug() -> Array:
	return _werewolf_turn_context_builder.wolf_target_vote_debug(_ai_turn_input())


func _legal_wolf_target_index_by_seat_number(actor_index: int, seat_number: int) -> int:
	return _werewolf_turn_context_builder.legal_wolf_target_by_seat(_ai_turn_input(), actor_index, seat_number)


func _is_legal_wolf_target_index(actor_index: int, target_index: int) -> bool:
	return _werewolf_turn_context_builder.is_legal_wolf_target(_ai_turn_input(), actor_index, target_index)


func _first_legal_wolf_target_index(actor_index: int) -> int:
	return _werewolf_turn_context_builder.first_legal_wolf_target(_ai_turn_input(), actor_index)


func _player_device_task_kind(task: Dictionary) -> String:
	var task_type := String(task.get("type", task.get("taskType", ""))).strip_edges()
	var payload: Dictionary = task.get("payload", {}) if task.get("payload", {}) is Dictionary else {}
	var kind := String(payload.get("kind", "")).strip_edges()
	if kind != "":
		return kind
	if task_type == "player_speech":
		return "speech"
	if task_type == "player_action":
		return "action"
	return "action"


func _player_device_task_action_key(task: Dictionary, kind: String = "") -> String:
	var payload: Dictionary = task.get("payload", {}) if task.get("payload", {}) is Dictionary else {}
	var explicit := String(payload.get("actionKey", payload.get("action_key", ""))).strip_edges()
	if explicit != "":
		return explicit
	if kind == "wolf_target_vote":
		return "wolf_kill"
	var action: Dictionary = {}
	var action_value = payload.get("action", {})
	if action_value is Dictionary:
		action = action_value
	elif _current_device_task_frame is Dictionary and (_current_device_task_frame as Dictionary).get("currentAction", {}) is Dictionary:
		action = (_current_device_task_frame as Dictionary).get("currentAction", {})
	if action.is_empty():
		var current_action = _werewolf.get("current_action", {})
		if current_action is Dictionary:
			action = current_action
	return String(action.get("key", ""))


func _start_local_ai_player_device_task(task: Dictionary) -> bool:
	var task_id := String(task.get("id", task.get("task_id", ""))).strip_edges()
	var task_type := String(task.get("type", task.get("taskType", ""))).strip_edges()
	var actor_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	if task_id == "":
		return false
	if actor_index < 0 or actor_index >= _players.size():
		_send_device_task_result(task_id, {"ok": false, "fatal": true, "failureKind": "ai_player", "type": task_type, "taskType": task_type, "error": "AI 玩家不存在"})
		return false
	if not _local_controls_bot_actor(actor_index):
		_send_device_task_result(task_id, {
			"ok": false,
			"fatal": true,
			"failureKind": "ai_player",
			"type": task_type,
			"taskType": task_type,
			"actorIndex": actor_index,
			"error": "当前设备不控制该 AI 玩家",
		})
		return false
	_ensure_controlled_bot_model_profiles_initialized("ai_player_device_task:%s" % task_id)
	var profile := _controlled_bot_model_profile_for_actor(actor_index, "ai_player_device_task:%s" % task_id)
	if profile.is_empty():
		var cached_model_error := _controlled_bot_model_profile_error_for_actor(actor_index)
		_send_device_task_result(task_id, {
			"ok": false,
			"fatal": true,
			"failureKind": "ai_player",
			"type": task_type,
			"taskType": task_type,
			"actorIndex": actor_index,
			"error": cached_model_error,
		})
		return false
	var kind := _player_device_task_kind(task)
	var action_key := _player_device_task_action_key(task, kind)
	var context_budget := _profile_context_window_tokens(profile)
	var memory_payload := _prepare_bot_memory_prompt(actor_index, context_budget)
	var context := _local_ai_context_for_player_task(kind, actor_index, action_key, memory_payload)
	if context.is_empty():
		_send_device_task_result(task_id, {
			"ok": false,
			"fatal": true,
			"failureKind": "ai_player",
			"type": task_type,
			"taskType": task_type,
			"actorIndex": actor_index,
			"error": "AI 玩家任务上下文构造失败",
		})
		return false
	var messages := _bot_runtime.build_messages(context)
	var request_options := _bot_runtime.request_options_for_context(context)
	var temperature := _profile_temperature(profile, 0.72 if kind in ["speech", "wolf_chat"] else 0.45)
	var purpose := "werewolf.player.%s" % kind
	_bot_debug("[WerewolfDeviceTask][debug] ai player local model source=controlled_runtime_cache id=%s type=%s kind=%s actor=%s model=%s provider=%s endpoint=%s formt_adapter=%s reason_adapter=%s reasoning=%s api_key=%s" % [
		task_id,
		task_type,
		kind,
		_player_title(actor_index),
		String(profile.get("model", "")),
		String(profile.get("provider", "")),
		String(profile.get("endpoint", "")),
		String(profile.get("formt_adapter", "")),
		String(profile.get("reason_adapter", "")),
		str(bool(profile.get("reasoning", false))),
		_bot_model_api_key_state(profile),
	])
	var max_output_tokens := _bot_max_output_tokens_for_task_kind(kind)
	_debug_log_bot_prompt(kind, actor_index, action_key if action_key != "" else kind, messages, request_options, profile, temperature, purpose, max_output_tokens)
	var request_id := _complete_model_request(profile, messages, temperature, max_output_tokens, BOT_MODEL_TIMEOUT_SEC, request_options, purpose)
	var request_kind := kind
	if request_kind == "action" and action_key == "wolf_kill":
		request_kind = "wolf_target_vote"
	var request := {
		"kind": request_kind,
		"actor_index": actor_index,
		"speaker_index": actor_index,
		"action_key": action_key,
		"context": context,
		"state": _werewolf.duplicate(true),
		"messages": messages,
		"request_options": request_options,
		"expected_reasoning": bool(profile.get("reasoning", false)),
		"model_profile": {
			"model": String(profile.get("model", "")),
			"provider": String(profile.get("provider", "")),
			"endpoint": String(profile.get("endpoint", "")),
			"formt_adapter": String(profile.get("formt_adapter", "")),
			"reason_adapter": String(profile.get("reason_adapter", "")),
			"reasoning": bool(profile.get("reasoning", false)),
		},
		"device_task_id": task_id,
		"device_task_type": task_type,
	}
	_bot_model_request_to_device_task[request_id] = request
	_system_message = "%s 正在本机执行玩家任务" % _player_title(actor_index)
	_refresh_center_panel()
	_commit_state()
	return true


func _local_ai_context_for_player_task(kind: String, actor_index: int, action_key: String, memory_payload: Dictionary = {}) -> Dictionary:
	match kind:
		"speech":
			if String(_werewolf.get("phase", "")) == "wolf_chat":
				return _bot_wolf_chat_context(actor_index, memory_payload)
			return _bot_speech_context(actor_index, memory_payload)
		"wolf_chat":
			return _bot_wolf_chat_context(actor_index, memory_payload)
		"wolf_target_vote":
			return _bot_action_context(actor_index, "wolf_kill", memory_payload)
		_:
			var clean_action_key := action_key.strip_edges()
			if clean_action_key == "":
				clean_action_key = _pending_action_key_for_task_payload()
			return _bot_action_context(actor_index, clean_action_key, memory_payload)


func _start_remote_bot_device_task_watchdog(task: Dictionary) -> void:
	var task_id := String(task.get("id", task.get("task_id", ""))).strip_edges()
	if task_id == "":
		return
	var task_type := String(task.get("type", task.get("taskType", ""))).strip_edges()
	var actor_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	get_tree().create_timer(REMOTE_BOT_DEVICE_TASK_TIMEOUT_SEC).timeout.connect(func():
		if _bot_flow_halted:
			return
		if not _device_task_channel.has_task(task_id):
			return
		var pending_task := _device_task_channel.pop_task(task_id)
		_sync_device_task_gate_state()
		_bot_debug("[WerewolfDeviceTask][error] bot task timeout id=%s type=%s actor=%s snapshot=%s" % [
			task_id,
			task_type,
			_player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else str(actor_index),
			JSON.stringify(_device_task_snapshot()),
		])
		_halt_werewolf_bot_game("机器人设备任务超时", "挂载设备未返回机器人模型结果", {
			"actor_index": actor_index,
			"action_key": _player_device_task_action_key(pending_task),
			"task_id": task_id,
			"task": pending_task,
		})
	)


func _pending_action_key_for_task_payload() -> String:
	var action_value = _werewolf.get("current_action", {})
	if action_value is Dictionary:
		return String((action_value as Dictionary).get("key", ""))
	return ""


func _on_device_task_received(task: Dictionary) -> void:
	var task_id := String(task.get("id", task.get("task_id", ""))).strip_edges()
	var task_type := String(task.get("type", task.get("taskType", ""))).strip_edges()
	var actor_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	var controller := String(task.get("controller_participant_id", task.get("controllerParticipantId", ""))).strip_edges()
	var local_participant := _current_network_participant_id()
	if controller != "" and controller != local_participant:
		_bot_debug("[WerewolfDeviceTask][error] received task for different controller id=%s type=%s expected=%s local=%s" % [
			task_id,
			task_type,
			controller,
			local_participant,
		])
		return
	_current_device_task_id = task_id
	_apply_device_task_frame(task)
	var actor_title := str(actor_index)
	if actor_index >= 0 and actor_index < _players.size():
		actor_title = _player_title(actor_index)
	var frame_api := ""
	if _current_device_task_frame is Dictionary:
		frame_api = String(_current_device_task_frame.get("api", ""))
	_bot_debug("[WerewolfDeviceTask][debug] received id=%s type=%s actor=%s controller=%s frame=%s" % [
		task_id,
		task_type,
		actor_title,
		_current_network_participant_id(),
		frame_api,
	])
	match task_type:
		"player_action":
			if _local_controls_bot_actor(actor_index):
				_start_local_ai_player_device_task(task)
			else:
				_on_player_action_device_task(task)
		"player_speech":
			if _local_controls_bot_actor(actor_index):
				_start_local_ai_player_device_task(task)
			else:
				_on_player_speech_device_task(task)
		"bot_action", "bot_speech", "bot_wolf_chat", "bot_wolf_target_vote":
			_send_device_task_result(task_id, {"ok": false, "type": task_type, "taskType": task_type, "error": "旧版 bot_* 设备任务已禁用，主机只能下发 player_action/player_speech"})
		_:
			_send_device_task_result(task_id, {"ok": false, "error": "未知设备任务类型：%s" % task_type})


func _apply_device_task_frame(task: Dictionary) -> void:
	var payload := {}
	var payload_value = task.get("payload", {})
	if payload_value is Dictionary:
		payload = payload_value
	var frame_value = payload.get("taskFrame", payload.get("playerFrame", {}))
	if not (frame_value is Dictionary):
		_current_device_task_frame.clear()
		return
	var frame: Dictionary = (frame_value as Dictionary).duplicate(true)
	if String(frame.get("api", "")) != "werewolf_device_task_frame.v1":
		_bot_debug("[WerewolfDeviceTask][error] task frame ignored reason=bad_api id=%s api=%s" % [
			String(task.get("id", task.get("task_id", ""))),
			String(frame.get("api", "")),
		])
		_current_device_task_frame.clear()
		return
	_current_device_task_frame = frame
	var frame_players_value = frame.get("players", [])
	if frame_players_value is Array and not (frame_players_value as Array).is_empty():
		_merge_device_task_frame_players(frame_players_value as Array)
	if frame.has("phase"):
		_werewolf["phase"] = String(frame.get("phase", _werewolf.get("phase", "")))
	if frame.has("day"):
		_werewolf["day"] = int(frame.get("day", _werewolf.get("day", 0)))
	if frame.has("mapId"):
		_werewolf["map_id"] = String(frame.get("mapId", _werewolf.get("map_id", "")))
	if frame.has("mapName"):
		_werewolf["map_name"] = String(frame.get("mapName", _werewolf.get("map_name", "")))
	if frame.has("speechIndex"):
		_werewolf["speech_index"] = int(frame.get("speechIndex", _werewolf.get("speech_index", -1)))
	var action_value = frame.get("currentAction", {})
	if action_value is Dictionary:
		_werewolf["current_action"] = (action_value as Dictionary).duplicate(true)
	var controller_id := ""
	var controller_value = frame.get("controller", {})
	if controller_value is Dictionary:
		controller_id = String((controller_value as Dictionary).get("participantId", ""))
	var frame_players_count := 0
	if frame_players_value is Array:
		frame_players_count = (frame_players_value as Array).size()
	var timeline_count := 0
	var timeline_value = frame.get("timeline", [])
	if timeline_value is Array:
		timeline_count = (timeline_value as Array).size()
	_bot_debug("[WerewolfDeviceTask][debug] frame applied id=%s actor=%s controller=%s players=%d timeline=%d" % [
		String(task.get("id", task.get("task_id", ""))),
		str(frame.get("actorSeatNumber", "")),
		controller_id,
		frame_players_count,
		timeline_count,
	])


func _merge_device_task_frame_players(frame_players: Array) -> void:
	if frame_players.is_empty():
		return
	while _players.size() < frame_players.size():
		var empty_seat := {}
		if has_method("_empty_seat_data"):
			var empty_value = call("_empty_seat_data", _players.size())
			if empty_value is Dictionary:
				empty_seat = empty_value
		_players.append(empty_seat)
	for i in range(frame_players.size()):
		if not (frame_players[i] is Dictionary):
			continue
		var frame_player: Dictionary = frame_players[i]
		var current := {}
		if i < _players.size() and _players[i] is Dictionary:
			current = (_players[i] as Dictionary).duplicate(true)
		current["name"] = String(frame_player.get("displayName", current.get("name", "%d号位" % [i + 1])))
		current["state"] = String(frame_player.get("state", current.get("state", "")))
		current["alive"] = bool(frame_player.get("alive", current.get("alive", true)))
		current["owner"] = String(frame_player.get("owner", current.get("owner", "")))
		current["avatar"] = String(frame_player.get("avatar", current.get("avatar", "")))
		current["base_avatar"] = String(frame_player.get("baseAvatar", current.get("base_avatar", current.get("avatar", ""))))
		current["participant_id"] = String(frame_player.get("participantId", current.get("participant_id", "")))
		current["controller_participant_id"] = String(frame_player.get("controllerParticipantId", current.get("controller_participant_id", "")))
		current["device_task_role_visible"] = bool(frame_player.get("roleVisible", false))
		current["device_task_role"] = String(frame_player.get("role", current.get("device_task_role", "未知")))
		if bool(frame_player.get("roleVisible", false)):
			current["role"] = String(frame_player.get("role", current.get("role", "未知")))
			current["role_key"] = String(frame_player.get("roleKey", current.get("role_key", "")))
			current["role_title"] = String(frame_player.get("roleTitle", current.get("role_title", "")))
			current["role_avatar"] = String(frame_player.get("roleAvatar", current.get("role_avatar", current.get("avatar", ""))))
		else:
			current["role_title"] = ""
			current["role_avatar"] = ""
		_players[i] = current
	_sync_werewolf_view_state_without_auto()
	_refresh_all_seats()
	_refresh_center_panel()


func _on_player_action_device_task(task: Dictionary) -> void:
	var actor_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	var state := _werewolf_human_task_controller.action_prompt_state(task, _current_device_task_frame, _pending_action, _pending_action_icon, _player_title(actor_index))
	_pending_actor_index = int(state.get("pending_actor_index", actor_index))
	_pending_action = String(state.get("pending_action", _pending_action))
	_pending_action_icon = String(state.get("pending_action_icon", _pending_action_icon))
	_speech_prompt_index = int(state.get("speech_prompt_index", -1))
	_system_message = String(state.get("system_message", "轮到 %s 行动" % _player_title(actor_index)))
	if has_method("_show_room_system_message_toast"):
		call("_show_room_system_message_toast")
	_refresh_center_panel()
	if _can_local_control_index(_pending_actor_index) and has_method("_open_target_confirm"):
		var target := _first_auto_open_target_for_current_action()
		if target >= 0:
			call("_open_target_confirm", target)
			_bot_debug("[WerewolfDeviceTask][debug] auto_open_action id=%s actor=%s target=%d action=%s" % [
				String(task.get("id", task.get("task_id", ""))),
				_player_title(_pending_actor_index),
				target + 1,
				_pending_action,
			])
		else:
			_bot_debug("[WerewolfDeviceTask][debug] auto_open_action skipped id=%s actor=%s reason=no_target action=%s" % [
				String(task.get("id", task.get("task_id", ""))),
				_player_title(_pending_actor_index),
				_pending_action,
			])


func _on_player_speech_device_task(task: Dictionary) -> void:
	var speaker_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	var state := _werewolf_human_task_controller.speech_prompt_state(task, _player_title(speaker_index))
	_speech_prompt_index = int(state.get("speech_prompt_index", speaker_index))
	_pending_action = String(state.get("pending_action", ""))
	_pending_action_icon = String(state.get("pending_action_icon", ""))
	_pending_actor_index = int(state.get("pending_actor_index", -1))
	_system_message = String(state.get("system_message", "轮到 %s 发言" % _player_title(speaker_index)))
	if has_method("_show_room_system_message_toast"):
		call("_show_room_system_message_toast")
	_refresh_center_panel()
	if bool(state.get("open_speech_editor", true)) and has_method("_open_speech_editor"):
		call("_open_speech_editor", speaker_index)


func _bot_model_name_for_actor(actor_index: int) -> String:
	if actor_index < 0 or actor_index >= _players.size() or not (_players[actor_index] is Dictionary):
		return ""
	var private_profile := _local_bot_profile_for_actor(actor_index)
	if not private_profile.is_empty():
		return _bot_profile_model_name_for_local_ai(private_profile)
	return ""


func _local_model_config_names() -> Array:
	var result := []
	for item in _model_configs:
		if not (item is Dictionary):
			continue
		var model_name := String((item as Dictionary).get("model", (item as Dictionary).get("name", ""))).strip_edges()
		if model_name != "":
			result.append(model_name)
	return result


func _bot_model_api_key_state(profile: Dictionary) -> String:
	return "set" if String(profile.get("api_key", "")).strip_edges() != "" else "empty"


func _bot_max_output_tokens_for_task_kind(kind: String) -> int:
	return _room_bot_max_output_tokens()


func _room_bot_max_output_tokens() -> int:
	var room := _active_room()
	if room.is_empty():
		return BOT_MODEL_MAX_OUTPUT_TOKENS
	return maxi(1, int(room.get("bot_max_output_tokens", BOT_MODEL_MAX_OUTPUT_TOKENS)))


func _room_timeline_compression_config() -> Dictionary:
	var room := _active_room()
	if room.is_empty():
		return {
			"enabled": false,
			"model": "",
			"interval": AppState.DEFAULT_TIMELINE_COMPRESSION_INTERVAL,
			"prompt": AppState.DEFAULT_TIMELINE_COMPRESSION_PROMPT,
		}
	return {
		"enabled": bool(room.get("timeline_compression_enabled", false)),
		"model": String(room.get("timeline_compression_model", "")).strip_edges(),
		"interval": maxi(1, int(room.get("timeline_compression_interval", AppState.DEFAULT_TIMELINE_COMPRESSION_INTERVAL))),
		"prompt": String(room.get("timeline_compression_prompt", AppState.DEFAULT_TIMELINE_COMPRESSION_PROMPT)).strip_edges(),
	}


func _debug_log_bot_prompt(kind: String, actor_index: int, action_key: String, messages: Array, request_options: Dictionary = {}, profile: Dictionary = {}, temperature: float = 0.0, purpose: String = "", max_output_tokens: int = 0) -> void:
	_werewolf_bot_prompt_log_sequence += 1
	var model_request := _bot_effective_model_request_payload(profile, messages, temperature, request_options, purpose, max_output_tokens)
	var direct_log := _bot_prompt_direct_log_block(_werewolf_bot_prompt_log_sequence, kind, actor_index, action_key, messages, request_options, model_request)
	_bot_debug(direct_log)
	_append_bot_prompt_log(kind, actor_index, action_key, messages, request_options, model_request)
	_append_bot_prompt_text_log(direct_log)


func _bot_effective_model_request_payload(profile: Dictionary, messages: Array, temperature: float, request_options: Dictionary = {}, purpose: String = "", max_output_tokens: int = 0) -> Dictionary:
	if profile.is_empty() or not has_method("_build_model_request_debug_payload"):
		return {}
	var request := _model_completion_request(profile, messages, temperature, max_output_tokens, BOT_MODEL_TIMEOUT_SEC, request_options, purpose)
	return _build_model_request_debug_payload(request)


func _bot_prompt_direct_log_block(sequence: int, kind: String, actor_index: int, action_key: String, messages: Array, request_options: Dictionary = {}, model_request: Dictionary = {}) -> String:
	var player_text := _player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else "未知玩家"
	var role_text := _bot_prompt_actor_role_text(actor_index)
	var lines := []
	lines.append("===== #%d 身份=%s 玩家=%s kind=%s action=%s =====" % [
		sequence,
		role_text,
		player_text,
		kind,
		action_key,
	])
	for i in range(messages.size()):
		var message := {}
		if messages[i] is Dictionary:
			message = messages[i] as Dictionary
		var role := String(message.get("role", ""))
		var content := String(message.get("content", ""))
		var label := "SYSTEM" if role == "system" else "USER" if role == "user" else role.to_upper()
		lines.append("")
		lines.append("[%s]" % label)
		lines.append(content)
	if not request_options.is_empty():
		lines.append("")
		lines.append("[RESPONSE_SCHEMA]")
		lines.append(JSON.stringify(request_options, "\t"))
	if not model_request.is_empty():
		lines.append("")
		lines.append("[MODEL_REQUEST_PAYLOAD]")
		lines.append(JSON.stringify(model_request, "\t"))
	lines.append("")
	return "\n".join(lines)


func _append_bot_prompt_log(kind: String, actor_index: int, action_key: String, messages: Array, request_options: Dictionary = {}, model_request: Dictionary = {}) -> void:
	var player_text := _player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else "未知玩家"
	var prompt_messages := []
	for i in range(messages.size()):
		if not (messages[i] is Dictionary):
			continue
		var message: Dictionary = messages[i]
		prompt_messages.append({
			"index": i,
			"role": String(message.get("role", "")),
			"content": String(message.get("content", "")),
		})
	var player := {}
	if actor_index >= 0 and actor_index < _players.size() and _players[actor_index] is Dictionary:
		player = (_players[actor_index] as Dictionary).duplicate(true)
	var record := {
		"sequence": _werewolf_bot_prompt_log_sequence,
		"generatedAtUnix": Time.get_unix_time_from_system(),
		"roomId": String(_app_state.active_room_id) if _app_state != null else "local_room",
		"day": int(_werewolf.get("day", 0)),
		"phase": String(_werewolf.get("phase", "")),
		"phaseLabel": _engine.phase_label(_werewolf),
		"kind": kind,
		"actionKey": action_key,
		"actorIndex": actor_index,
		"actorSeatNumber": actor_index + 1 if actor_index >= 0 else -1,
		"actorTitle": player_text,
		"actorName": String(player.get("name", "")),
		"actorRoleKey": String(player.get("role_key", "")),
		"actorRole": String(player.get("role", "")),
		"messages": prompt_messages,
	}
	if not request_options.is_empty():
		record["requestOptions"] = request_options.duplicate(true)
	if not model_request.is_empty():
		record["modelRequestPayload"] = model_request.duplicate(true)
	var file := FileAccess.open(WEREWOLF_BOT_PROMPT_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(WEREWOLF_BOT_PROMPT_LOG_PATH, FileAccess.WRITE)
	if file == null:
		_werewolf_bot_prompt_log_last_error = "open_failed:%s" % FileAccess.get_open_error()
		_bot_debug("机器人 prompt 日志写入失败：%s" % _werewolf_bot_prompt_log_last_error)
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))
	_werewolf_bot_prompt_log_last_error = ""


func _append_bot_prompt_text_log(direct_log: String) -> void:
	var file := FileAccess.open(WEREWOLF_BOT_PROMPT_TEXT_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(WEREWOLF_BOT_PROMPT_TEXT_LOG_PATH, FileAccess.WRITE)
	if file == null:
		_werewolf_bot_prompt_log_last_error = "text_open_failed:%s" % FileAccess.get_open_error()
		_bot_debug("机器人 prompt 文本日志写入失败：%s" % _werewolf_bot_prompt_log_last_error)
		return
	file.seek_end()
	file.store_string(direct_log)
	_werewolf_bot_prompt_log_last_error = ""


func _bot_prompt_actor_role_text(actor_index: int) -> String:
	if actor_index < 0 or actor_index >= _players.size() or not (_players[actor_index] is Dictionary):
		return "未知身份"
	var player: Dictionary = _players[actor_index]
	var role := String(player.get("role", "")).strip_edges()
	if role != "":
		return role
	var role_key := String(player.get("role_key", "")).strip_edges()
	return _role_catalog.role_label(role_key) if role_key != "" else "未知身份"


func _debug_bot_prompt_log_snapshot() -> Dictionary:
	return {
		"path": WEREWOLF_BOT_PROMPT_LOG_PATH,
		"textPath": WEREWOLF_BOT_PROMPT_TEXT_LOG_PATH,
		"lastError": _werewolf_bot_prompt_log_last_error,
	}


func _reset_werewolf_bot_prompt_logs() -> void:
	_werewolf_bot_prompt_log_sequence = 0
	_werewolf_bot_prompt_log_last_error = ""
	for path in [WEREWOLF_BOT_PROMPT_LOG_PATH, WEREWOLF_BOT_PROMPT_TEXT_LOG_PATH]:
		if FileAccess.file_exists(String(path)):
			var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(String(path)))
			if error != OK:
				_werewolf_bot_prompt_log_last_error = "clear_failed:%s:%s" % [String(path), error_string(error)]


func _reset_werewolf_session_memories(map_id: String = "") -> void:
	if not bool(PromptPolicyScript.write_memory_enabled):
		_bot_debug("[BotMemory][debug] reset skipped reason=write_disabled")
		return
	_ensure_memory_loaded()
	for i in range(_players.size()):
		if not _is_bot_actor(i):
			continue
		var scope := _memory_scope_for_player(i, true)
		if map_id.strip_edges() != "":
			scope["map_id"] = map_id.strip_edges()
		_memory_manager.discard_session(scope)


func _ai_turn_input() -> Dictionary:
	_ensure_ai_player_ids()
	var room_id := String(_app_state.active_room_id) if _app_state != null else "local_room"
	var map_rule := String(_werewolf.get("map_rule_text", "")).strip_edges()
	if map_rule == "":
		map_rule = _engine.map_rule_text(String(_werewolf.get("map_id", "basic_village")), _occupied_indices().size())
	return {
		"room_id": room_id,
		"werewolf": _werewolf,
		"players": _players,
		"history": _history,
		"wolf_private_history": _wolf_private_history,
		"wolf_target_votes": _bot_wolf_target_votes,
		"timeline_compression": _room_timeline_compression_config(),
		"wolf_speech_count": _wolf_speech_count_for_current_night(),
		"max_wolf_night_chat_messages": MAX_WOLF_NIGHT_CHAT_MESSAGES,
		"phase_label": _engine.phase_label(_werewolf),
		"map_rule_text": map_rule,
	}


func _ensure_ai_player_ids() -> void:
	for i in range(_players.size()):
		_player_id_for_index(i)


func _bot_wolf_chat_context(actor_index: int, memory_payload: Dictionary = {}) -> Dictionary:
	return _werewolf_turn_context_builder.wolf_chat_context(_ai_turn_input(), actor_index, memory_payload)


func _bot_speech_messages(speaker_index: int) -> Array:
	var memory_payload := _prepare_bot_memory_prompt(speaker_index)
	return _bot_runtime.build_messages(_bot_speech_context(speaker_index, memory_payload))


func _bot_action_messages(actor_index: int, action_key: String) -> Array:
	var memory_payload := _prepare_bot_memory_prompt(actor_index)
	return _bot_runtime.build_messages(_bot_action_context(actor_index, action_key, memory_payload))


func _bot_action_context(actor_index: int, action_key: String, memory_payload: Dictionary = {}) -> Dictionary:
	return _werewolf_turn_context_builder.action_context(_ai_turn_input(), actor_index, action_key, memory_payload)


func _bot_speech_context(speaker_index: int, memory_payload: Dictionary = {}) -> Dictionary:
	return _werewolf_turn_context_builder.speech_context(_ai_turn_input(), speaker_index, memory_payload)


func _bot_visible_state(viewer_index: int, memory_payload: Dictionary = {}) -> Dictionary:
	return _werewolf_turn_context_builder.visible_state(_ai_turn_input(), viewer_index, memory_payload)


func _model_allowed_actions_for_current_action(actor_index: int, action_key: String) -> Array:
	return _werewolf_turn_context_builder.model_allowed_actions(_ai_turn_input(), actor_index, action_key)


func _is_legal_model_target(actor_index: int, target_index: int, action_key: String) -> bool:
	return _werewolf_turn_context_builder.is_legal_model_target(_ai_turn_input(), actor_index, target_index, action_key)


func _recent_timeline_events_for_viewer(limit: int, viewer_index: int) -> Array:
	return _werewolf_turn_context_builder.visible_timeline_events(_ai_turn_input(), limit, viewer_index)


func _visible_timeline_event_count(viewer_index: int) -> int:
	return _werewolf_turn_context_builder.visible_timeline_event_count(_ai_turn_input(), viewer_index)


func _can_view_wolf_private_history(viewer_index: int) -> bool:
	return _werewolf_turn_context_builder.can_view_wolf_private_history(_ai_turn_input(), viewer_index)


func _context_budget_from_memory(memory_payload: Dictionary) -> int:
	return _werewolf_turn_context_builder.context_budget_from_memory(memory_payload)


func _memory_context_budget(context_budget: int) -> int:
	return mini(maxi(1, context_budget), MEMORY_CONTEXT_TOKEN_LIMIT)


func _timeline_limit_for_context_budget(context_budget: int) -> int:
	return _werewolf_turn_context_builder.timeline_limit_for_context_budget(context_budget)


func _prior_event_limit_for_context_budget(context_budget: int) -> int:
	return _werewolf_turn_context_builder.prior_event_limit_for_context_budget(context_budget)


func _summary_timeline_limit_for_context_budget(context_budget: int) -> int:
	return _werewolf_turn_context_builder.summary_timeline_limit_for_context_budget(context_budget)


func _player_id_for_index(index: int) -> String:
	if index < 0 or index >= _players.size():
		return ""
	var player: Dictionary = _players[index]
	var id := String(player.get("id", "")).strip_edges()
	if id == "":
		id = "seat_%d" % [index + 1]
		player["id"] = id
		_players[index] = player
	return id


func _memory_round_summary_texts(memory_payload: Dictionary) -> Array:
	return _werewolf_memory_context.round_summary_texts(memory_payload)


func _recent_memory_entry_texts(memory_payload: Dictionary) -> Array:
	return _werewolf_memory_context.recent_entry_texts(memory_payload)


func _retrieved_memory_entry_texts(memory_payload: Dictionary) -> Array:
	return _werewolf_memory_context.retrieved_entry_texts(memory_payload)


func _bot_config_memory_summary(bot_profile_key: String) -> String:
	if bot_profile_key == "":
		_bot_debug("[BotMemory][debug] summary empty_key")
		return ""
	var summary := _bot_profile_repository.summary_for_bot(bot_profile_key)
	if summary != "":
		_bot_debug("[BotMemory][debug] summary profile_key=%s source=profile chars=%d" % [bot_profile_key, summary.length()])
		return summary
	_bot_debug("[BotMemory][debug] summary profile_key=%s source=none" % bot_profile_key)
	return ""


func _prepare_bot_memory_prompt(player_index: int, context_budget: int = 8192) -> Dictionary:
	if player_index < 0 or player_index >= _players.size():
		return {}
	_record_bot_observation(player_index)
	var turn_budget := maxi(1, context_budget)
	var memory_budget := _memory_context_budget(turn_budget)
	var bot_memory_key := _memory_key_for_player(player_index)
	var config_summary := _bot_config_memory_summary(bot_memory_key)
	var session_scope := _memory_scope_for_player(player_index, true)
	var profile_scope := _memory_scope_for_player(player_index, false)
	_bot_debug("[BotMemory][debug] prepare_prompt player=%s key=%s session=%s profile=%s memory_budget=%d turn_budget=%d config_chars=%d" % [
		_player_title(player_index),
		bot_memory_key,
		_memory_manager.scope_key(session_scope),
		_memory_manager.scope_key(profile_scope),
		memory_budget,
		turn_budget,
		config_summary.length(),
	])
	var payload: Dictionary = _werewolf_memory_context.build_prompt(
		_memory_manager,
		_werewolf_memory_builder,
		session_scope,
		profile_scope,
		config_summary,
		_memory_retrieval_query(player_index, memory_budget),
		memory_budget
	)
	payload["memoryContextBudgetTokens"] = memory_budget
	payload["contextBudgetTokens"] = turn_budget
	_log_bot_context_budget(player_index, turn_budget, payload)
	return payload


func _memory_retrieval_query(player_index: int, context_budget: int = 8192) -> String:
	return _werewolf_turn_context_builder.memory_retrieval_query(_ai_turn_input(), player_index, context_budget)


func _log_bot_context_budget(player_index: int, context_budget: int, memory_payload: Dictionary) -> void:
	var recent = memory_payload.get("recentMemoryEntries", [])
	var summaries = memory_payload.get("roundSummaries", [])
	var retrieved = memory_payload.get("retrievedMemoryEntries", [])
	_bot_debug("[BotContext] player=%s context_budget=%d memory_budget=%d recent=%d summaries=%d retrieved=%d long_term_chars=%d config_chars=%d" % [
		_player_title(player_index),
		context_budget,
		int(memory_payload.get("memoryContextBudgetTokens", context_budget)),
		(recent as Array).size() if recent is Array else 0,
		(summaries as Array).size() if summaries is Array else 0,
		(retrieved as Array).size() if retrieved is Array else 0,
		String(memory_payload.get("longTermMemorySummary", "")).length(),
		String(memory_payload.get("configSummary", "")).length(),
	])


func _memory_system_summary(memory_payload: Dictionary) -> String:
	var parts := []
	var config_summary := String(memory_payload.get("configSummary", "")).strip_edges()
	var long_term := String(memory_payload.get("longTermMemorySummary", "")).strip_edges()
	if config_summary != "":
		parts.append(config_summary)
	if long_term != "":
		parts.append(long_term)
	return "\n".join(parts)


func _record_bot_observation(player_index: int) -> void:
	if not bool(PromptPolicyScript.write_memory_enabled):
		return
	if not _is_bot_actor(player_index):
		return
	var visible_events := _recent_timeline_events_for_viewer(8, player_index)
	var entry := _werewolf_memory_builder.observation_entry_from_timeline_events(_werewolf, _players, player_index, visible_events)
	_append_player_memory(player_index, entry)


func _record_bot_speech(player_index: int, text: String) -> void:
	if not bool(PromptPolicyScript.write_memory_enabled):
		return
	if not _is_bot_actor(player_index):
		return
	var entry := _werewolf_memory_builder.speech_entry(player_index, _players, text)
	_append_player_memory(player_index, entry)


func _record_bot_decision(player_index: int, target_index: int, action_key: String) -> void:
	if not bool(PromptPolicyScript.write_memory_enabled):
		return
	if not _is_bot_actor(player_index):
		return
	var entry := _werewolf_memory_builder.decision_entry(player_index, target_index, action_key, _players)
	_append_player_memory(player_index, entry)


func _append_player_memory(player_index: int, entry: Dictionary) -> void:
	if not bool(PromptPolicyScript.write_memory_enabled):
		return
	if player_index < 0 or player_index >= _players.size():
		_bot_debug("[BotMemory][debug] append ignored invalid_index=%d players=%d" % [player_index, _players.size()])
		return
	_ensure_memory_loaded()
	var scope := _memory_scope_for_player(player_index, true)
	_bot_debug("[BotMemory][debug] append player=%s scope=%s type=%s importance=%s" % [
		_player_title(player_index),
		_memory_manager.scope_key(scope),
		String(entry.get("type", "")),
		str(entry.get("importance", "")),
	])
	_memory_manager.append(scope, entry)


func _memory_scope_for_player(player_index: int, include_room: bool) -> Dictionary:
	var player: Dictionary = _players[player_index]
	var owner_id := _local_private_bot_profile_id_for_seat(player_index)
	if owner_id == "":
		owner_id = String(player.get("id", "")).strip_edges()
	if owner_id == "":
		owner_id = "%s_%d" % [String(player.get("owner", "seat")), player_index + 1]
	var room_id := ""
	if include_room and _app_state != null:
		room_id = String(_app_state.active_room_id)
	var key := _memory_key_for_player(player_index)
	var scope := _memory_manager.scope(owner_id, "werewolf", key, String(_werewolf.get("map_id", "basic_village")), room_id)
	_bot_debug("[BotMemory][debug] scope player=%s include_room=%s owner_id=%s key=%s room=%s scope=%s" % [
		_player_title(player_index),
		str(include_room),
		owner_id,
		key,
		room_id,
		_memory_manager.scope_key(scope),
	])
	return scope


func _memory_key_for_player(player_index: int) -> String:
	if player_index >= 0 and player_index < _players.size():
		var bot_profile_id := _local_private_bot_profile_id_for_seat(player_index)
		if bot_profile_id != "":
			_bot_debug("[BotMemory][debug] key player=%s source=local_private_profile key=%s" % [_player_title(player_index), bot_profile_id])
			return bot_profile_id
		var player_id := String(_players[player_index].get("id", "")).strip_edges()
		if player_id != "":
			_bot_debug("[BotMemory][debug] key player=%s source=player_id key=%s" % [_player_title(player_index), player_id])
			return player_id
	var profile := _bot_profile_repository.first_enabled_profile()
	if not profile.is_empty():
		var profile_id := String(profile.get("id", "")).strip_edges()
		if profile_id != "":
			_bot_debug("[BotMemory][debug] key index=%d source=first_enabled key=%s" % [player_index, profile_id])
			return profile_id
	_bot_debug("[BotMemory][debug] key index=%d source=session" % player_index)
	return "session"


func _save_long_term_memories_if_completed() -> void:
	if String(_werewolf.get("phase", "")) != "completed":
		return
	if bool(_werewolf.get("memory_long_term_saved", false)):
		return
	if not bool(PromptPolicyScript.write_memory_enabled):
		_werewolf["memory_long_term_saved"] = true
		_bot_debug("[BotMemory][debug] long_term skipped reason=write_disabled")
		return
	_ensure_memory_loaded()
	var compact := _werewolf_memory_builder.compact_request(_werewolf, _players, _history, "completed")
	for i in range(_players.size()):
		if not _is_bot_actor(i):
			continue
		if not _local_controls_bot_actor(i):
			continue
		var profile := _controlled_bot_model_profile_for_actor(i, "save_long_term_memory")
		var context_budget := _memory_context_budget(_profile_context_window_tokens(profile))
		var memory_limits: Dictionary = _werewolf_memory_context.limits_for_context_budget(context_budget)
		var profile_scope := _memory_scope_for_player(i, false)
		var session_scope := _memory_scope_for_player(i, true)
		var profile_context := _memory_manager.prompt_context(profile_scope, int(memory_limits.get("profileEntryLimit", 2)), int(memory_limits.get("profileSummaryLimit", 2)))
		var existing := String(profile_context.get("longTermMemorySummary", ""))
		var summary := _werewolf_memory_builder.long_term_summary(_werewolf, _players, i, _history, existing)
		_memory_manager.save_long_term(profile_scope, summary, true)
		_memory_manager.compact(session_scope, compact)
	_werewolf["memory_long_term_saved"] = true


func _finalize_completed_werewolf_game_if_needed() -> void:
	if String(_werewolf.get("phase", "")) != "completed":
		return
	if has_method("_maybe_print_werewolf_final_perspective_text_debug"):
		call("_maybe_print_werewolf_final_perspective_text_debug")
	_save_long_term_memories_if_completed()


func _memory_players_payload() -> Array:
	return _werewolf_turn_context_builder.memory_players_payload(_ai_turn_input())


func _memory_final_timeline_payload(viewer_index: int, context_budget: int = 8192) -> Array:
	return _werewolf_turn_context_builder.memory_final_timeline_payload(_ai_turn_input(), viewer_index, context_budget)


func _role_label_for_memory(player_index: int) -> String:
	return _werewolf_turn_context_builder.role_label_for_memory(_ai_turn_input(), player_index)


func _on_model_chat_result(request_id: int, completed_result: Dictionary) -> void:
	_bot_stream_preview_texts.erase(request_id)
	if _bot_model_request_to_device_task.has(request_id):
		_on_device_bot_model_result(request_id, completed_result)
		return
	var ok := bool(completed_result.get("ok", false))
	var content := String(completed_result.get("text", ""))
	var error := String(completed_result.get("error", ""))
	match _bot_request_tracker.classify(request_id):
		"action":
			_on_model_action_completed(request_id, ok, content, error, completed_result)
			return
		"speech":
			pass
		_:
			return
	var request: Dictionary = _bot_request_tracker.pop_speech(request_id)
	_waiting_bot_speech = _bot_request_tracker.has_pending_speech()
	if request.is_empty():
		return
	request["request_id"] = request_id
	if _mode != Mode.TABLE:
		return
	_sync_werewolf_view_state_without_auto()
	var speaker_index := int(request.get("speaker_index", -1))
	if speaker_index != _speech_prompt_index:
		_log_bot_stale_result("speech", request_id, speaker_index, _speech_prompt_index, request)
		_schedule_auto_resolve_bot_turns()
		return
	_warn_bot_unexpected_reasoning(request, completed_result)
	var context: Dictionary = request.get("context", {})
	var decision: Dictionary = _bot_runtime.parse_decision(content, context) if ok else {}
	if not ok or not bool(decision.get("ok", false)):
		_log_bot_model_failure_output("机器人发言失败", request, ok, content, error, decision)
		_halt_werewolf_bot_game("机器人发言失败", _bot_failure_reason(error, decision), {"speaker_index": speaker_index})
		return
	var speech := String(decision.get("speech_text", "")).strip_edges()
	if speech == "":
		_log_bot_model_failure_output("机器人发言失败", request, ok, content, "模型返回空发言", decision)
		_halt_werewolf_bot_game("机器人发言失败", "模型返回空发言", {"speaker_index": speaker_index})
		return
	var result: Dictionary = _engine.submit_speech(_werewolf, _players, speech, _local_player_index)
	if not bool(result.get("ok", false)):
		var submit_error := String(result.get("message", "模型发言无法提交"))
		_log_bot_model_failure_output("机器人发言提交失败", request, ok, content, submit_error, decision)
		_halt_werewolf_bot_game("机器人发言提交失败", submit_error, {"speaker_index": speaker_index})
		return
	if _apply_engine_result(result):
		_record_bot_speech(speaker_index, speech)


func _on_model_chat_event(request_id: int, event: Dictionary) -> void:
	if event.is_empty():
		return
	if String(event.get("type", "")) != "chunk":
		return
	if String(event.get("kind", "")) != "text":
		return
	var request_kind := _bot_request_tracker.classify(request_id)
	var request: Dictionary = {}
	if _bot_model_request_to_device_task.has(request_id) and _bot_model_request_to_device_task[request_id] is Dictionary:
		request = (_bot_model_request_to_device_task[request_id] as Dictionary).duplicate(true)
		request_kind = String(request.get("kind", request_kind))
	elif request_kind == "speech":
		request = _bot_request_tracker.peek_speech(request_id)
	elif request_kind == "action":
		request = _bot_request_tracker.peek_action(request_id)
	if request.is_empty():
		return
	var kind := String(request.get("kind", request_kind))
	if kind != "speech" and kind != "wolf_chat":
		return
	var chunk_text := String(event.get("text", ""))
	if chunk_text == "":
		return
	var accumulated := String(_bot_stream_preview_texts.get(request_id, ""))
	accumulated += chunk_text
	_bot_stream_preview_texts[request_id] = accumulated
	_preview_bot_stream_speech(request, accumulated)


func _preview_bot_stream_speech(request: Dictionary, text: String) -> void:
	if text.strip_edges() == "":
		return
	var speaker_index := int(request.get("speaker_index", request.get("actor_index", -1)))
	if speaker_index < 0 or speaker_index >= _players.size():
		return
	if not has_method("_show_center_speech_item"):
		return
	var preview_item := {
		"speaker": _player_title(speaker_index),
		"text": text,
		"display_text": text,
		"speaker_index": speaker_index,
		"avatar": _players[speaker_index].get("avatar", ""),
		"seat": "%d号" % (speaker_index + 1),
		"name": String(_players[speaker_index].get("name", "")),
		"at": "stream_%d" % speaker_index,
	}
	call("_show_center_speech_item", preview_item, false, true, true)
	call("_update_center_speech_progress", preview_item, 0.99)


func _on_device_bot_model_result(request_id: int, completed_result: Dictionary) -> void:
	var request_value = _bot_model_request_to_device_task.get(request_id, {})
	_bot_model_request_to_device_task.erase(request_id)
	if not (request_value is Dictionary):
		return
	var request: Dictionary = request_value
	request["request_id"] = request_id
	var ok := bool(completed_result.get("ok", false))
	var content := String(completed_result.get("text", ""))
	var error := String(completed_result.get("error", ""))
	var context: Dictionary = request.get("context", {}) if request.get("context", {}) is Dictionary else {}
	var task_id := String(request.get("device_task_id", "")).strip_edges()
	var task_type := String(request.get("device_task_type", request.get("kind", ""))).strip_edges()
	var actor_index := int(request.get("actor_index", -1))
	_warn_bot_unexpected_reasoning(request, completed_result)
	var decision: Dictionary = _bot_runtime.parse_decision(content, context) if ok else {}
	if not ok or not bool(decision.get("ok", false)):
		var repaired_decision := _repair_bot_target_decision_if_possible(request, decision, String(request.get("action_key", "")))
		if not repaired_decision.is_empty():
			_log_bot_target_repair("机器人设备任务目标修复", request, repaired_decision)
			decision = repaired_decision
		else:
			_log_bot_model_failure_output("机器人设备任务失败", request, ok, content, error, decision)
			_send_device_task_result(task_id, {
				"ok": false,
				"fatal": true,
				"failureKind": "ai_player",
				"type": task_type,
				"taskType": task_type,
				"actorIndex": actor_index,
				"error": _bot_failure_reason(error, decision),
				"rawOutput": content,
			})
			return
	var payload := {
		"ok": true,
		"type": task_type,
		"taskType": task_type,
		"actorIndex": actor_index,
		"rawOutput": content,
		"decision": decision.duplicate(true),
	}
	if decision.has("speech_text"):
		payload["text"] = String(decision.get("speech_text", ""))
		payload["speechText"] = String(decision.get("speech_text", ""))
	if decision.has("action"):
		payload["action"] = String(decision.get("action", ""))
	if decision.has("target_index"):
		payload["targetIndex"] = int(decision.get("target_index", -1))
	if decision.has("target_seat_number"):
		payload["targetSeatNumber"] = int(decision.get("target_seat_number", -1))
	_send_device_task_result(task_id, payload)


func _report_bot_model_error(title: String, error: String = "", details: Dictionary = {}) -> void:
	_halt_werewolf_bot_game(title, error, details)


func _warn_bot_unexpected_reasoning(request: Dictionary, completed_result: Dictionary) -> bool:
	var warning := _bot_unexpected_reasoning_warning(request, completed_result)
	if warning == "":
		return false
	_bot_debug("[WerewolfBotModel][reasoning_warning] %s" % warning)
	var now := Time.get_ticks_msec()
	if warning != _last_bot_reasoning_warning_signature or now - _last_bot_reasoning_warning_msec > 3500:
		_last_bot_reasoning_warning_signature = warning
		_last_bot_reasoning_warning_msec = now
		if has_method("_show_system_progress_toast"):
			call("_show_system_progress_toast", warning, 6.0)
	return true


func _bot_unexpected_reasoning_warning(request: Dictionary, completed_result: Dictionary) -> String:
	if not _bot_should_validate_reasoning_result(completed_result):
		return ""
	var expected := _bot_expected_reasoning_for_request(request, completed_result)
	var actual := _bot_completed_has_reasoning_output(completed_result)
	if expected or not actual:
		return ""
	var model_profile: Dictionary = request.get("model_profile", {}) if request.get("model_profile", {}) is Dictionary else {}
	var model := String(model_profile.get("model", completed_result.get("model", ""))).strip_edges()
	if model == "":
		model = "未知"
	var reason_adapter := String(model_profile.get("reason_adapter", completed_result.get("reason_adapter", ""))).strip_edges()
	if reason_adapter == "":
		reason_adapter = "未知"
	return "%s模型,适配方式%s,仍旧返回了思考,fuck. 这个模型是低能儿." % [model, reason_adapter]


func _bot_reasoning_expectation_error(request: Dictionary, completed_result: Dictionary) -> String:
	if not _bot_should_validate_reasoning_result(completed_result):
		return ""
	var expected := _bot_expected_reasoning_for_request(request, completed_result)
	var actual := _bot_completed_has_reasoning_output(completed_result)
	if expected == actual:
		return ""
	var actor_index := int(request.get("actor_index", request.get("speaker_index", -1)))
	var model_profile: Dictionary = request.get("model_profile", {}) if request.get("model_profile", {}) is Dictionary else {}
	var model := String(model_profile.get("model", completed_result.get("model", ""))).strip_edges()
	var provider := String(model_profile.get("provider", completed_result.get("provider", ""))).strip_edges()
	var reason_adapter := String(model_profile.get("reason_adapter", completed_result.get("reason_adapter", ""))).strip_edges()
	var response_code := int(completed_result.get("response_code", 0))
	var diagnostic: Dictionary = completed_result.get("diagnostic", {}) if completed_result.get("diagnostic", {}) is Dictionary else {}
	if response_code == 0:
		response_code = int(diagnostic.get("response_code", 0))
	_bot_debug("[WerewolfBotModel][reasoning_mismatch] request_id=%d actor=%s expected=%s actual=%s model=%s provider=%s reason_adapter=%s reasoning_mode=%s response_code=%d diagnostic=%s" % [
		int(request.get("request_id", -1)),
		_player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else str(actor_index),
		str(expected),
		str(actual),
		model,
		provider,
		reason_adapter,
		String(completed_result.get("reasoning_mode", "")),
		response_code,
		JSON.stringify(diagnostic),
	])
	if expected:
		return "思考输出与模型配置不一致：模型配置已开启思考，但本次机器人推理没有返回思考输出。请重新测试并保存该模型的思考兼容方式。"
	return "思考输出与模型配置不一致：模型配置已关闭思考，但本次机器人推理返回了思考输出。请重新测试并保存该模型的思考兼容方式。"


func _bot_should_validate_reasoning_result(completed_result: Dictionary) -> bool:
	var diagnostic: Dictionary = completed_result.get("diagnostic", {}) if completed_result.get("diagnostic", {}) is Dictionary else {}
	var response_code := int(completed_result.get("response_code", diagnostic.get("response_code", 0)))
	if response_code != 0 and (response_code < 200 or response_code >= 300):
		return false
	if diagnostic.has("parse_ok") and not bool(diagnostic.get("parse_ok", false)):
		return false
	if bool(completed_result.get("ok", false)):
		return true
	return diagnostic.has("parse_ok") and bool(diagnostic.get("parse_ok", false))


func _bot_expected_reasoning_for_request(request: Dictionary, completed_result: Dictionary) -> bool:
	if request.has("expected_reasoning"):
		return bool(request.get("expected_reasoning", false))
	var model_profile: Dictionary = request.get("model_profile", {}) if request.get("model_profile", {}) is Dictionary else {}
	if model_profile.has("reasoning"):
		return bool(model_profile.get("reasoning", false))
	var reasoning_mode := String(completed_result.get("reasoning_mode", "")).strip_edges().to_lower()
	if reasoning_mode == "on":
		return true
	if reasoning_mode == "off":
		return false
	var diagnostic: Dictionary = completed_result.get("diagnostic", {}) if completed_result.get("diagnostic", {}) is Dictionary else {}
	return bool(diagnostic.get("reasoning_enabled", false))


func _bot_completed_has_reasoning_output(completed_result: Dictionary) -> bool:
	if bool(completed_result.get("has_reasoning_output", false)):
		return true
	if String(completed_result.get("reasoning_text", "")).strip_edges() != "":
		return true
	var diagnostic: Dictionary = completed_result.get("diagnostic", {}) if completed_result.get("diagnostic", {}) is Dictionary else {}
	if bool(diagnostic.get("has_reasoning_output", false)):
		return true
	return String(diagnostic.get("reasoning_output", "")).strip_edges() != ""


func _halt_werewolf_bot_game(title: String, error: String = "", details: Dictionary = {}) -> bool:
	_waiting_bot_action = _bot_request_tracker.has_pending_actions()
	_waiting_bot_speech = _bot_request_tracker.has_pending_speech()
	var reason := error.strip_edges()
	if reason == "":
		reason = String(details.get("error", "")).strip_edges()
	if reason == "":
		reason = "模型输出无法提交"
	var actor_index := int(details.get("actor_index", details.get("speaker_index", -1)))
	var actor_text := ""
	if actor_index >= 0 and actor_index < _players.size():
		actor_text = "%s：" % _player_title(actor_index)
	_bot_flow_halted = true
	_bot_flow_halt_error = {
		"title": title,
		"reason": reason,
		"actor_index": actor_index,
		"action_key": String(details.get("action_key", "")),
		"at": Time.get_unix_time_from_system(),
	}
	if not _werewolf.is_empty():
		_werewolf["bot_error_halted"] = true
		_werewolf["bot_error"] = _bot_flow_halt_error.duplicate(true)
	_bot_request_tracker.clear()
	_auto_resolving = false
	_waiting_bot_action = false
	_waiting_bot_speech = false
	_auto_resolve_waiting_for_tts = false
	_auto_resolve_deferred_pending = false
	if actor_index >= 0 and actor_index < _players.size() and _players[actor_index] is Dictionary:
		(_players[actor_index] as Dictionary)["motion"] = SeatMotion.IDLE
		(_players[actor_index] as Dictionary)["speech_progress"] = 0.0
	_system_message = "%s%s：%s，游戏已中止" % [actor_text, title, reason]
	_bot_debug(_system_message)
	if has_method("_show_system_progress_toast"):
		call("_show_system_progress_toast", _system_message, 10.0)
	_open_model_error_overlay("游戏已中止：%s" % title, reason, actor_index)
	_refresh_all_seats()
	_refresh_room_controls()
	_refresh_center_panel()
	_commit_state()
	_flash_effect("skip")
	return false


func _on_model_wolf_chat_completed(request: Dictionary, ok: bool, content: String, error: String, completed_result: Dictionary = {}) -> void:
	var phase := String(_werewolf.get("phase", ""))
	if phase != "wolf_chat" and phase != "wolf_action":
		_schedule_auto_resolve_bot_turns()
		return
	var actor_index := int(request.get("actor_index", -1))
	_warn_bot_unexpected_reasoning(request, completed_result)
	var context: Dictionary = request.get("context", {})
	var decision: Dictionary = _bot_runtime.parse_decision(content, context) if ok else {}
	if not ok or not bool(decision.get("ok", false)):
		_log_bot_model_failure_output("机器人狼聊失败", request, ok, content, error, decision)
		_halt_werewolf_bot_game("机器人狼聊失败", _bot_failure_reason(error, decision), {"speaker_index": actor_index})
		return
	var speech := String(decision.get("speech_text", "")).strip_edges()
	if speech == "":
		_log_bot_model_failure_output("机器人狼聊失败", request, ok, content, "模型返回空狼聊", decision)
		_halt_werewolf_bot_game("机器人狼聊失败", "模型返回空狼聊", {"speaker_index": actor_index})
		return
	_record_bot_wolf_chat(actor_index, speech)
	if phase == "wolf_chat" and actor_index == _speech_prompt_index:
		var result: Dictionary = _engine.submit_speech(_werewolf, _players, speech, _local_player_index)
		if not _apply_engine_result_without_auto(result):
			return
	_schedule_auto_resolve_bot_turns()


func _on_model_wolf_target_vote_completed(request: Dictionary, ok: bool, content: String, error: String, completed_result: Dictionary = {}) -> void:
	if String(_werewolf.get("phase", "")) != "wolf_action":
		_schedule_auto_resolve_bot_turns()
		return
	var actor_index := int(request.get("actor_index", -1))
	_warn_bot_unexpected_reasoning(request, completed_result)
	var context: Dictionary = request.get("context", {})
	var decision: Dictionary = _bot_runtime.parse_decision(content, context) if ok else {}
	if not bool(decision.get("ok", false)):
		var repaired_decision := _repair_bot_target_decision_if_possible(request, decision, "wolf_kill")
		if not repaired_decision.is_empty():
			_log_bot_target_repair("机器人狼队目标票目标修复", request, repaired_decision)
			decision = repaired_decision
		else:
			_log_bot_model_failure_output("机器人狼队目标票失败", request, ok, content, error, decision)
			_halt_werewolf_bot_game("机器人狼队目标票失败", _bot_failure_reason(error, decision), {"actor_index": actor_index, "action_key": "wolf_kill"})
			return
	var normalized := _normalized_wolf_target_vote_decision(actor_index, decision)
	if int(normalized.get("target_index", -1)) < 0:
		_log_bot_model_failure_output("机器人狼队目标票失败", request, ok, content, "模型返回非法目标", decision)
		_halt_werewolf_bot_game("机器人狼队目标票失败", "模型返回非法目标", {"actor_index": actor_index, "action_key": "wolf_kill"})
		return
	_record_bot_wolf_target_vote(actor_index, normalized)
	_schedule_auto_resolve_bot_turns()


func _on_model_action_completed(request_id: int, ok: bool, content: String, error: String, completed_result: Dictionary = {}) -> void:
	var request: Dictionary = _bot_request_tracker.pop_action(request_id)
	if request.is_empty():
		return
	request["request_id"] = request_id
	_waiting_bot_action = _bot_request_tracker.has_pending_actions()
	if _mode != Mode.TABLE:
		return
	_sync_werewolf_view_state_without_auto()
	var request_kind := String(request.get("kind", "action"))
	if request_kind == "wolf_chat":
		_on_model_wolf_chat_completed(request, ok, content, error, completed_result)
		return
	if request_kind == "wolf_target_vote":
		_on_model_wolf_target_vote_completed(request, ok, content, error, completed_result)
		return
	var actor_index := int(request.get("actor_index", -1))
	if actor_index != _pending_actor_index:
		_log_bot_stale_result("action", request_id, actor_index, _pending_actor_index, request)
		_schedule_auto_resolve_bot_turns()
		return
	var action_key := String(request.get("action_key", ""))
	_warn_bot_unexpected_reasoning(request, completed_result)
	var context: Dictionary = request.get("context", {})
	var decision: Dictionary = _bot_runtime.parse_decision(content, context) if ok else {}
	if not bool(decision.get("ok", false)):
		var repaired_decision := _repair_bot_target_decision_if_possible(request, decision, action_key)
		if not repaired_decision.is_empty():
			_log_bot_target_repair("机器人行动目标修复", request, repaired_decision)
			decision = repaired_decision
		else:
			_log_bot_model_failure_output("机器人行动失败", request, ok, content, error, decision)
			_halt_werewolf_bot_game("机器人行动失败", _bot_failure_reason(error, decision), {"actor_index": actor_index, "action_key": action_key})
			return
	var model_action := String(decision.get("action", ""))
	var target := int(decision.get("target_index", -1))
	var label := String(request.get("label", _pending_action))
	var wolf_target_vote := {}
	if action_key == "wolf_kill":
		wolf_target_vote = _normalized_wolf_target_vote_decision(actor_index, decision)
		target = int(wolf_target_vote.get("target_index", -1))
	var result: Dictionary = {}
	if model_action == "skip" or model_action == "witch_skip" or model_action == "sheriff_badge_destroy":
		result = _engine.skip_current_action(_werewolf, _players, _local_player_index)
	elif model_action == "witch_save":
		target = _current_witch_save_target_index()
		if target < 0:
			_log_bot_model_failure_output("机器人行动失败", request, ok, content, "当前没有可救目标", decision)
			_halt_werewolf_bot_game("机器人行动失败", "当前没有可救目标", {"actor_index": actor_index, "action_key": action_key})
			return
		result = _engine.apply_target(_werewolf, _players, target, _local_player_index)
	elif action_key == "sheriff_speech_order":
		if target < 0:
			_log_bot_model_failure_output("机器人行动失败", request, ok, content, "模型返回目标为空", decision)
			_halt_werewolf_bot_game("机器人行动失败", "模型返回目标为空", {"actor_index": actor_index, "action_key": action_key})
			return
		result = _engine.apply_target(_werewolf, _players, target, _local_player_index, model_action)
	elif action_key == "sheriff_badge_action":
		if target < 0:
			_log_bot_model_failure_output("机器人行动失败", request, ok, content, "模型返回目标为空", decision)
			_halt_werewolf_bot_game("机器人行动失败", "模型返回目标为空", {"actor_index": actor_index, "action_key": action_key})
			return
		result = _engine.apply_target(_werewolf, _players, target, _local_player_index, model_action)
	else:
		if target < 0:
			_log_bot_model_failure_output("机器人行动失败", request, ok, content, "模型返回目标为空", decision)
			_halt_werewolf_bot_game("机器人行动失败", "模型返回目标为空", {"actor_index": actor_index, "action_key": action_key})
			return
		result = _engine.apply_target(_werewolf, _players, target, _local_player_index)
	if not bool(result.get("ok", false)):
		_log_bot_model_failure_output("机器人行动失败", request, ok, content, String(result.get("message", "模型返回目标非法")), decision)
		_halt_werewolf_bot_game("机器人行动失败", String(result.get("message", "模型返回目标非法")), {"actor_index": actor_index, "action_key": action_key})
		return
	if bool(result.get("ok", false)) and target >= 0:
		if action_key == "wolf_kill":
			if wolf_target_vote.is_empty():
				wolf_target_vote = {"action": "wolf_kill", "target_index": target, "targetSeatNumber": target + 1}
			_record_bot_wolf_target_vote(actor_index, wolf_target_vote)
		else:
			_record_bot_decision(actor_index, target, action_key)
	var accepted := _apply_engine_result(result)
	if accepted and target >= 0 and target < _seat_cards.size():
		_seat_cards[target].play_action_effect(_action_effect_kind(label))


func _log_bot_stale_result(kind: String, request_id: int, result_actor_index: int, pending_index: int, request: Dictionary) -> void:
	var action: Dictionary = _werewolf.get("current_action", {}) if _werewolf.get("current_action", {}) is Dictionary else {}
	var post: Dictionary = _werewolf.get("post_game", {}) if _werewolf.get("post_game", {}) is Dictionary else {}
	var summary_pending: Array = post.get("summary_pending", []) if post.get("summary_pending", []) is Array else []
	_bot_debug("[WerewolfBot][debug] stale %s result id=%d result_index=%d pending_index=%d phase=%s speech_index=%d action_actor=%d action_key=%s summary_pending=%s tracker=%s request=%s" % [
		kind,
		request_id,
		result_actor_index,
		pending_index,
		String(_werewolf.get("phase", "")),
		int(_werewolf.get("speech_index", -1)),
		int(action.get("actor_index", -1)),
		String(action.get("key", "")),
		JSON.stringify(summary_pending),
		JSON.stringify(_bot_request_tracker.snapshot()),
		JSON.stringify(request),
	])


func _open_model_error_overlay(title: String, reason: String, actor_index: int = -1) -> void:
	var clean_title := title.strip_edges()
	if clean_title == "":
		clean_title = "模型错误"
	var clean_reason := reason.strip_edges()
	if clean_reason == "":
		clean_reason = "模型输出无法提交"
	var signature := "%s|%d|%s" % [clean_title, actor_index, clean_reason]
	var now := Time.get_ticks_msec()
	if signature == _last_model_error_popup_signature and now - _last_model_error_popup_msec < 1200:
		return
	_last_model_error_popup_signature = signature
	_last_model_error_popup_msec = now
	if not has_method("_overlay_card") or _mode != Mode.TABLE:
		return
	var actor_text := _player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else "机器人"
	var card := _overlay_card("游戏已中止", Vector2(460, 280))
	card.name = "ModelErrorOverlay"
	var body := _overlay_body(card)
	body.add_child(_label("%s · %s" % [actor_text, clean_title], 15, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	var reason_label := _label(clean_reason, 12, INK, false)
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	reason_label.clip_text = false
	reason_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reason_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(reason_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(actions)
	actions.add_child(_small_button("关闭", true, func(): _clear_modal()))


func _repair_bot_target_decision_if_possible(request: Dictionary, decision: Dictionary, action_key_override: String = "") -> Dictionary:
	if String(decision.get("error", "")) != "模型返回了非法目标":
		return {}
	var context: Dictionary = request.get("context", {}) if request.get("context", {}) is Dictionary else {}
	var action_key := action_key_override.strip_edges()
	if action_key == "":
		action_key = String(request.get("action_key", "")).strip_edges()
	if action_key == "":
		action_key = String(decision.get("action", "")).strip_edges()
	if action_key == "":
		return {}
	var target_action := _target_action_for_repair(action_key, decision)
	var target_index := _first_legal_target_index_for_context(context, target_action)
	if target_index < 0:
		return {}
	var requested_seat := int(decision.get("target_seat_number", -1))
	var requested_index := requested_seat - 1 if requested_seat > 0 else -1
	requested_index = int(decision.get("target_index", requested_index))
	return {
		"ok": true,
		"action": target_action,
		"target_index": target_index,
		"target_seat_number": target_index + 1,
		"speech_text": "",
		"repaired": true,
		"repair_reason": String(decision.get("error", "模型返回了非法目标")),
		"requested_target_index": requested_index,
		"requested_target_seat_number": requested_seat,
	}


func _target_action_for_repair(action_key: String, decision: Dictionary) -> String:
	if action_key == "sheriff_speech_order":
		var model_action := String(decision.get("action", "")).strip_edges()
		if model_action in ["sheriff_speech_order_clockwise", "sheriff_speech_order_counterclockwise"]:
			return model_action
		return "sheriff_speech_order_clockwise"
	if action_key == "sheriff_badge_action":
		return "sheriff_badge_pass"
	return action_key


func _first_legal_target_index_for_context(context: Dictionary, action_key: String) -> int:
	var target_options := _bot_runtime.target_options_for_context(context)
	for option_value in target_options:
		if not (option_value is Dictionary):
			continue
		var option: Dictionary = option_value
		var seat_number := int(option.get("targetSeatNumber", -1))
		if seat_number <= 0:
			continue
		var target_actions = option.get("targetActions", [])
		if target_actions is Array:
			var actions: Array = target_actions
			if not actions.is_empty() and not actions.has(action_key):
				continue
		return seat_number - 1
	return -1


func _log_bot_target_repair(title: String, request: Dictionary, decision: Dictionary) -> void:
	var actor_index := int(request.get("actor_index", request.get("speaker_index", request.get("player_index", -1))))
	var context: Dictionary = request.get("context", {}) if request.get("context", {}) is Dictionary else {}
	var visible_state: Dictionary = context.get("visible_state", {}) if context.get("visible_state", {}) is Dictionary else {}
	var meta := {
		"title": title,
		"request_id": int(request.get("request_id", -1)),
		"kind": String(request.get("kind", "")),
		"action_key": String(request.get("action_key", decision.get("action", ""))),
		"actor_index": actor_index,
		"actor": _player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else "",
		"repair_reason": String(decision.get("repair_reason", "")).strip_edges(),
		"requested_target_seat_number": int(decision.get("requested_target_seat_number", -1)),
		"target_seat_number": int(decision.get("target_seat_number", -1)),
		"current_question": String(context.get("current_question", "")),
		"allowed_actions": context.get("allowed_actions", []),
		"day": visible_state.get("dayNumber", _werewolf.get("day", 0)),
		"phase": visible_state.get("phase", _werewolf.get("phase", "")),
	}
	_bot_debug("[WerewolfBotModel][repair] %s" % JSON.stringify(meta))


func _log_bot_model_failure_output(title: String, request: Dictionary, ok: bool, content: String, error: String = "", decision: Dictionary = {}) -> void:
	var actor_index := int(request.get("actor_index", request.get("speaker_index", request.get("player_index", -1))))
	var context: Dictionary = request.get("context", {}) if request.get("context", {}) is Dictionary else {}
	var visible_state: Dictionary = context.get("visible_state", {}) if context.get("visible_state", {}) is Dictionary else {}
	var meta := {
		"title": title,
		"request_id": int(request.get("request_id", -1)),
		"kind": String(request.get("kind", "")),
		"action_key": String(request.get("action_key", "")),
		"actor_index": actor_index,
		"actor": _player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else "",
		"ok": ok,
		"error": error.strip_edges(),
		"parser_error": String(decision.get("error", "")).strip_edges(),
		"model_output_chars": content.length(),
		"current_question": String(context.get("current_question", "")),
		"allowed_actions": context.get("allowed_actions", []),
		"day": visible_state.get("dayNumber", _werewolf.get("day", 0)),
		"phase": visible_state.get("phase", _werewolf.get("phase", "")),
	}
	_bot_debug("[WerewolfBotModel][failure] %s" % JSON.stringify(meta))
	if not decision.is_empty():
		_bot_debug("[WerewolfBotModel][failure][parser_decision] %s" % JSON.stringify(decision))
	var messages = request.get("messages", [])
	var prompt_text := JSON.stringify(messages, "\t") if messages is Array else "[]"
	_print_werewolf_bot_log_chunks("[WerewolfBotModel][failure][input_prompt] request_id=%d actor=%s" % [
		int(request.get("request_id", -1)),
		String(meta.get("actor", "")),
	], prompt_text)
	var request_options = request.get("request_options", {})
	var response_schema = (request_options as Dictionary).get("response_schema", (request_options as Dictionary).get("schema", {})) if request_options is Dictionary else {}
	var schema_text := JSON.stringify(response_schema, "\t") if response_schema is Dictionary and not (response_schema as Dictionary).is_empty() else "<empty>"
	_print_werewolf_bot_log_chunks("[WerewolfBotModel][failure][input_schema] request_id=%d actor=%s" % [
		int(request.get("request_id", -1)),
		String(meta.get("actor", "")),
	], schema_text)
	_print_werewolf_bot_log_chunks("[WerewolfBotModel][failure][raw_model_output] request_id=%d actor=%s" % [
		int(request.get("request_id", -1)),
		String(meta.get("actor", "")),
	], content)


func _print_werewolf_bot_log_chunks(prefix: String, text: String, chunk_size: int = 1800) -> void:
	var clean_prefix := prefix.strip_edges()
	if clean_prefix == "":
		clean_prefix = "[WerewolfBotModel][output]"
	if text == "":
		_bot_debug("%s <empty>" % clean_prefix)
		return
	var size := maxi(256, chunk_size)
	var total := int(ceil(float(text.length()) / float(size)))
	for i in range(total):
		var start := i * size
		_bot_debug("%s chunk=%d/%d\n%s" % [clean_prefix, i + 1, total, text.substr(start, size)])


func _bot_failure_reason(error: String, details: Dictionary = {}) -> String:
	var reason := error.strip_edges()
	if reason == "":
		reason = String(details.get("error", "")).strip_edges()
	if reason == "":
		reason = "模型输出无法提交"
	return reason


func _target_from_model_decision(content: String, actor_index: int, action_key: String) -> int:
	return _werewolf_turn_context_builder.target_from_decision(_bot_runtime, content, _ai_turn_input(), actor_index, action_key)


func _current_witch_save_target_index() -> int:
	var action: Dictionary = _werewolf.get("current_action", {})
	if String(action.get("key", "")) != "witch_act":
		return -1
	if not bool(_werewolf.get("witch_antidote", true)):
		return -1
	var night: Dictionary = _werewolf.get("night", {})
	var target := int(night.get("wolf_target_index", -1))
	if target < 0 or target >= _players.size():
		return -1
	if not bool(_players[target].get("alive", true)):
		return -1
	return target
