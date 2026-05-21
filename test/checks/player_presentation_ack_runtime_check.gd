extends SceneTree

const ControllerScript := preload("res://scripts/player/player_presentation_ack_controller.gd")
const ResolverScript := preload("res://scripts/player/player_presentation_ack_participant_resolver.gd")
const RuntimeScript := preload("res://scripts/player/player_presentation_ack_runtime.gd")

var _scheduled_delay := -1.0
var _scheduled_completed := []
var _host_apply_calls := []
var _client_payloads := []
var _opened_gate_ids := []


func _initialize() -> void:
	var controller = ControllerScript.new()
	var resolver = ResolverScript.new()
	var runtime = RuntimeScript.new()

	var item := {
		"speaker": "主持人",
		"text": "需要确认。",
		"visibility": "public",
	}
	controller.register_gate_for_history_item(item, "room_test", ["host"], [], false)
	var presentation_id: String = controller.history_presentation_id(item)
	runtime.begin_local_ack(controller, item, "host", false)
	if not _expect(controller.local_ack_pending(presentation_id), "runtime begins local pending ACK"):
		return
	var schedule_result: Dictionary = runtime.schedule_local_text_ack(
		controller,
		item,
		"host",
		Callable(self, "_schedule_immediate"),
		Callable(self, "_record_scheduled_completion"),
		false
	)
	if not _expect(bool(schedule_result.get("scheduled", false)), "runtime schedules text ACK through callback"):
		return
	if not _expect(_scheduled_delay >= 5.0, "runtime uses controller text delay"):
		return
	if not _expect(_scheduled_completed.size() == 1 and String((_scheduled_completed[0] as Dictionary).get("source", "")) == "text_delay", "scheduler completion callback is invoked"):
		return

	var complete_result: Dictionary = runtime.complete_local_ack(
		controller,
		item,
		"host",
		"room_test",
		"unit",
		false,
		Callable(self, "_record_client_ack"),
		Callable(self, "_record_host_apply"),
		false
	)
	if not _expect(bool(complete_result.get("ok", false)), "runtime completes local host ACK"):
		return
	if not _expect(_host_apply_calls.size() == 1, "runtime routes host local ACK to host apply callback"):
		return
	var host_call: Dictionary = _host_apply_calls[0]
	if not _expect(int(host_call.get("peer_id", -1)) == 0, "host apply uses local peer id"):
		return
	var host_payload: Dictionary = host_call.get("payload", {})
	var apply_result: Dictionary = runtime.apply_host_ack(
		controller,
		resolver,
		0,
		host_payload,
		"",
		Callable(self, "_record_gate_open"),
		false
	)
	if not _expect(bool(apply_result.get("opened", false)), "host ACK opens gate"):
		return
	if not _expect(_opened_gate_ids.has(presentation_id), "runtime calls gate-open callback"):
		return

	var client_item := {
		"speaker": "主持人",
		"text": "客户端确认。",
	}
	controller.ensure_history_presentation_id(client_item, "room_test")
	runtime.begin_local_ack(controller, client_item, "peer_client", false)
	var client_result: Dictionary = runtime.complete_local_ack(
		controller,
		client_item,
		"peer_client",
		"room_test",
		"unit_client",
		true,
		Callable(self, "_record_client_ack"),
		Callable(self, "_record_host_apply"),
		false
	)
	if not _expect(bool(client_result.get("networkClient", false)) and bool(client_result.get("sent", false)), "client ACK is sent through callback"):
		return
	if not _expect(_client_payloads.size() == 1 and String((_client_payloads[0] as Dictionary).get("participantId", "")) == "peer_client", "client payload preserves participant id"):
		return

	var drop_item := {
		"speaker": "主持人",
		"text": "等待远端。",
	}
	controller.register_gate_for_history_item(drop_item, "room_test", ["peer_drop"], [], false)
	var drop_id: String = controller.history_presentation_id(drop_item)
	var opened: Array = runtime.drop_participant(controller, "peer_drop", Callable(self, "_record_gate_open"), false)
	if not _expect(opened == [drop_id], "dropping last participant opens gate"):
		return
	if not _expect(_opened_gate_ids.has(drop_id), "drop participant calls gate-open callback"):
		return
	runtime.clear(controller)
	if not _expect(not controller.gate_blocks_auto_advance(), "runtime clear removes ACK gates"):
		return
	quit(0)


func _schedule_immediate(delay_seconds: float, timeout_callback: Callable) -> void:
	_scheduled_delay = delay_seconds
	if timeout_callback.is_valid():
		timeout_callback.call()


func _record_scheduled_completion(item: Dictionary, source: String) -> void:
	_scheduled_completed.append({
		"item": item.duplicate(true),
		"source": source,
	})


func _record_host_apply(peer_id: int, payload: Dictionary) -> void:
	_host_apply_calls.append({
		"peer_id": peer_id,
		"payload": payload.duplicate(true),
	})


func _record_client_ack(payload: Dictionary) -> bool:
	_client_payloads.append(payload.duplicate(true))
	return true


func _record_gate_open(presentation_id: String) -> void:
	_opened_gate_ids.append(presentation_id)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("player_presentation_ack_runtime_check failed: %s" % message)
	quit(1)
	return false
