extends SceneTree


class FakeClientSession:
	var sent_results := []

	func is_client() -> bool:
		return true

	func is_host() -> bool:
		return false

	func local_participant_id() -> String:
		return "host"

	func send_client(type: String, payload: Dictionary = {}, _message_id: String = "") -> bool:
		if type == "device_task_result":
			sent_results.append(payload.duplicate(true))
		return true


class FakeModelChatClient:
	extends RefCounted

	signal completed(request_id: int, ok: bool, content: String, error: String)
	signal protocol_event(request_id: int, event: Dictionary)

	var next_request_id := 200
	var requests := []

	func complete_request(request: Dictionary) -> int:
		next_request_id += 1
		requests.append(request.duplicate(true))
		return next_request_id

	func take_completed_result(_request_id: int) -> Dictionary:
		return {}

	func take_completed_diagnostic(_request_id: int) -> Dictionary:
		return {}

	func build_request_debug_payload(request: Dictionary) -> Dictionary:
		return {
			"model": String(request.get("model", "")),
			"endpoint": String(request.get("endpoint", "")),
			"api_key": String(request.get("api_key", "")),
			"output_adapter": String(request.get("output_adapter", "")),
			"reason_adapter": String(request.get("reason_adapter", "")),
			"response_schema": (request.get("response_schema", {}) as Dictionary).duplicate(true) if request.get("response_schema", {}) is Dictionary else {},
		}


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.model_configs = [{
		"model": "remote-test-model",
		"provider": "openai_api",
		"endpoint": "https://example.invalid/v1",
		"api_key": "sk-test",
		"max_context": 8192,
		"max_output": 1024,
		"formt_adapter": "openai_json_schema",
		"reason_adapter": "native",
	}]
	state.bot_profiles = [{
		"id": "remote_bot_profile",
		"name": "远程机器人",
		"model": "remote-test-model",
		"voice": "系统默认",
		"enabled": true,
		"memory": {},
	}]
	var page = load("res://scenes/werewolf_room.tscn").instantiate()
	page.set_app_state(state)
	root.add_child(page)
	await process_frame
	await process_frame
	page._model_configs = state.model_configs.duplicate(true)
	page._bot_profile_repository.load_or_seed(state.bot_profiles)
	page._bot_profiles = page._bot_profile_repository.list_profiles()
	page._room_network_session = FakeClientSession.new()
	page._model_chat_client = FakeModelChatClient.new()
	page._players = [
		{
			"id": "player_1",
			"name": "远程机器人",
			"owner": "human",
			"participant_id": "",
			"controller_participant_id": "host",
			"role_key": "wolf",
			"role": "狼人",
			"alive": true,
		},
		{
			"id": "human_2",
			"name": "2号玩家",
			"owner": "human",
			"participant_id": "peer_2",
			"role_key": "villager",
			"role": "村民",
			"alive": true,
		},
	]
	page._cache_local_private_bot_profile_for_seat(0, state.bot_profiles[0] as Dictionary)
	page._werewolf = {
		"started": true,
		"phase": "day_vote",
		"day": 1,
		"speech_index": -1,
		"current_action": {"key": "vote", "label": "投票", "actor_index": 0},
	}
	page._initialize_controlled_bot_model_profiles("test_init", true)
	_check_profile_initializes_from_local_bot_profile(page)
	_check_player_task_has_no_model_context(page)
	_check_player_task_uses_runtime_cached_model_config(page)
	_check_legacy_bot_task_is_rejected(page)
	page.queue_free()
	await process_frame
	quit(0)


func _check_profile_initializes_from_local_bot_profile(page) -> void:
	if not _expect(not page._players[0].has("model"), "public local bot does not store model"):
		return
	if not _expect(not page._players[0].has("voice"), "public local bot does not store voice"):
		return
	if not _expect(String(page._local_private_bot_profile_id_for_seat(0)) == "remote_bot_profile", "local bot profile is kept in private seat cache"):
		return
	var profile: Dictionary = page._controlled_bot_model_profile_for_actor(0, "test")
	if not _expect(not profile.is_empty(), "device task uses initialized runtime cache"):
		return
	if not _expect(String(profile.get("api_key", "")) == "sk-test", "local profile keeps local api key"):
		return
	if not _expect(String(profile.get("formt_adapter", "")) == "openai_json_schema", "local profile keeps saved formt adapter"):
		return


func _check_player_task_has_no_model_context(page) -> void:
	var task: Dictionary = page._create_device_task_for_actor("player_action", 0, {
		"action": {"key": "vote", "label": "投票", "actor_index": 0},
		"question": "请投票",
		"modelName": "host-should-strip",
		"messages": [{"role": "user", "content": "bad"}],
		"requestOptions": {"output_type": "json"},
		"schema": {"type": "object"},
		"formt_adapter": "openai_json_schema",
		"formtAdapter": "openai_json_schema",
		"output_adapter": "openai_json_schema",
		"outputAdapter": "openai_json_schema",
		"reason_adapter": "native",
		"reasonAdapter": "native",
		"max_output": 4096,
		"maxOutput": 4096,
		"temperature": 0.6,
	})
	if not _expect(not task.is_empty(), "player task is created"):
		return
	if not _expect(String(task.get("type", "")) == "player_action", "task type is generic player_action"):
		return
	var task_payload: Dictionary = task.get("payload", {})
	for key in ["model", "modelName", "model_name", "messages", "requestOptions", "request_options", "schema", "response_schema", "endpoint", "api_key", "formt_adapter", "formtAdapter", "output_adapter", "outputAdapter", "reason_adapter", "reasonAdapter", "max_output", "maxOutput", "temperature"]:
		if not _expect(not _contains_key_recursive(task_payload, key), "player task strips private key %s" % key):
			return
	var frame: Dictionary = task_payload.get("taskFrame", {})
	if not _expect(String(frame.get("api", "")) == "werewolf_device_task_frame.v1", "task keeps public frame"):
		return


func _check_player_task_uses_runtime_cached_model_config(page) -> void:
	page._model_configs = [{
		"model": "remote-test-model",
		"provider": "openai_api",
		"endpoint": "https://changed.invalid/v1",
		"api_key": "sk-changed",
		"max_context": 4096,
		"max_output": 256,
		"formt_adapter": "openai_json_object",
		"reason_adapter": "openai_reasoning_effort",
	}]
	var task: Dictionary = page._create_device_task_for_actor("player_action", 0, {
		"action": {"key": "vote", "label": "投票", "actor_index": 0},
		"question": "请投票",
	})
	page._on_device_task_received(task)
	var fake_client = page._model_chat_client
	if not _expect(fake_client.requests.size() == 1, "player task creates one local model request"):
		return
	var request: Dictionary = fake_client.requests[0]
	if not _expect(String(request.get("endpoint", "")) == "https://example.invalid/v1", "model request uses cached endpoint"):
		return
	if not _expect(String(request.get("api_key", "")) == "sk-test", "model request uses cached api key"):
		return
	if not _expect(String(request.get("output_adapter", "")) == "openai_json_schema", "model request uses cached formt adapter"):
		return
	if not _expect(String(request.get("reason_adapter", "")) == "native", "model request uses cached reason adapter"):
		return


func _check_legacy_bot_task_is_rejected(page) -> void:
	page._room_network_session.sent_results.clear()
	var task := {
		"id": "legacy_bot_task",
		"type": "bot_action",
		"taskType": "bot_action",
		"actor_index": 0,
		"actorIndex": 0,
		"controllerParticipantId": "host",
		"payload": {},
	}
	page._on_device_task_received(task)
	if not _expect(page._room_network_session.sent_results.size() == 1, "legacy bot task sends one failure"):
		return
	var result: Dictionary = page._room_network_session.sent_results[0]
	if not _expect(not bool(result.get("ok", true)), "legacy bot task result is failure"):
		return
	if not _expect(String(result.get("error", "")).contains("bot_*"), "legacy bot task failure explains disabled bot task"):
		return


func _contains_key_recursive(value, key: String) -> bool:
	if value is Dictionary:
		for key_value in (value as Dictionary).keys():
			if String(key_value) == key:
				return true
			if _contains_key_recursive((value as Dictionary).get(key_value), key):
				return true
	if value is Array:
		for item in value as Array:
			if _contains_key_recursive(item, key):
				return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_device_task_remote_bot_context_check failed: %s" % message)
	quit(1)
	return false
