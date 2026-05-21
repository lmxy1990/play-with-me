extends RefCounted


func begin_local_ack(controller, item: Dictionary, participant_id: String, debug_enabled: bool) -> void:
	controller.begin_local_ack(item, participant_id, debug_enabled)


func schedule_local_text_ack(controller, item: Dictionary, participant_id: String, schedule_callback: Callable, complete_callback: Callable, debug_enabled: bool) -> Dictionary:
	var presentation_id := String(controller.history_presentation_id(item)).strip_edges()
	if presentation_id == "":
		return {"scheduled": false, "reason": "empty_presentation_id"}
	if not schedule_callback.is_valid():
		return {"scheduled": false, "reason": "missing_scheduler", "presentationId": presentation_id}
	var delay_seconds := float(controller.text_delay_seconds_for_item(item))
	if debug_enabled:
		print("[PlayerPresentationAck][debug] local text wait id=%s participant=%s seconds=%.2f chars=%d" % [
			presentation_id,
			participant_id,
			delay_seconds,
			String(controller.text_for_item(item)).length(),
		])
	var ack_item := item.duplicate(true)
	var timeout_callback := func():
		if complete_callback.is_valid():
			complete_callback.call(ack_item, "text_delay")
	schedule_callback.call(delay_seconds, timeout_callback)
	return {
		"scheduled": true,
		"presentationId": presentation_id,
		"delaySeconds": delay_seconds,
	}


func complete_local_ack(controller, item: Dictionary, participant_id: String, room_id: String, source: String, network_client: bool, send_client_callback: Callable, host_apply_callback: Callable, debug_enabled: bool) -> Dictionary:
	var payload: Dictionary = controller.consume_local_ack_payload(item, participant_id, room_id, source)
	if payload.is_empty():
		return {"ok": false, "reason": "empty_payload"}
	var presentation_id := String(payload.get("presentationId", ""))
	if network_client:
		var sent := false
		if send_client_callback.is_valid():
			sent = bool(send_client_callback.call(payload))
		if debug_enabled:
			print("[PlayerPresentationAck][debug] client ack id=%s participant=%s source=%s sent=%s" % [
				presentation_id,
				participant_id,
				source,
				str(sent),
			])
		return {
			"ok": true,
			"networkClient": true,
			"sent": sent,
			"payload": payload,
		}
	if not host_apply_callback.is_valid():
		return {"ok": false, "reason": "missing_host_apply", "payload": payload}
	host_apply_callback.call(0, payload)
	return {
		"ok": true,
		"networkClient": false,
		"appliedToHost": true,
		"payload": payload,
	}


func apply_host_ack(controller, participant_resolver, peer_id: int, payload: Dictionary, session_participant_id: String, gate_open_callback: Callable, debug_enabled: bool) -> Dictionary:
	var presentation_id := String(payload.get("presentationId", payload.get("presentation_id", ""))).strip_edges()
	if presentation_id == "":
		return {"applied": false, "opened": false, "reason": "empty_presentation_id"}
	var participant_id := String(participant_resolver.participant_id_for_ack(peer_id, payload, session_participant_id)).strip_edges()
	var result: Dictionary = controller.apply_host_ack(presentation_id, participant_id, String(payload.get("source", "")), debug_enabled)
	if bool(result.get("opened", false)) and gate_open_callback.is_valid():
		gate_open_callback.call(presentation_id)
	return result


func drop_participant(controller, participant_id: String, gate_open_callback: Callable, debug_enabled: bool) -> Array:
	var opened: Array = controller.drop_participant(participant_id, debug_enabled)
	for gate_id in opened:
		if gate_open_callback.is_valid():
			gate_open_callback.call(String(gate_id))
	return opened


func clear(controller) -> void:
	controller.clear()
