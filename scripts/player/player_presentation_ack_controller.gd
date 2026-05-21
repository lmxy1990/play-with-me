extends RefCounted

const TEXT_SECONDS_PER_CHAR := 0.5
const TEXT_MIN_SECONDS := 5.0

var _gates := {}
var _serial := 0
var _pending_local := {}


func ensure_history_presentation_id(item: Dictionary, room_id: String) -> String:
	var existing := history_presentation_id(item)
	if existing != "":
		item["presentation_id"] = existing
		item["presentationId"] = existing
		return existing
	_serial += 1
	var clean_room_id := room_id.strip_edges()
	if clean_room_id == "":
		clean_room_id = "local_room"
	var presentation_id := "%s:%d:%d" % [clean_room_id, Time.get_ticks_msec(), _serial]
	item["presentation_id"] = presentation_id
	item["presentationId"] = presentation_id
	return presentation_id


func history_presentation_id(item: Dictionary) -> String:
	return String(item.get("presentation_id", item.get("presentationId", ""))).strip_edges()


func register_gate_for_history_item(item: Dictionary, room_id: String, expected: Array, device_debug: Array, debug_enabled: bool) -> Dictionary:
	var presentation_id := ensure_history_presentation_id(item, room_id)
	if presentation_id == "":
		return {"ok": false, "opened": false}
	if expected.is_empty():
		_gates.erase(presentation_id)
		if debug_enabled:
			print("[PlayerPresentationAck][debug] gate skipped id=%s reason=no_visible_devices speaker=%s devices=%s" % [
				presentation_id,
				String(item.get("speaker", "")),
				JSON.stringify(device_debug),
			])
		return {"ok": true, "created": false, "id": presentation_id}
	var gate := {
		"id": presentation_id,
		"speaker": String(item.get("speaker", "")),
		"text_chars": text_for_item(item).length(),
		"expected": expected.duplicate(),
		"acked": {},
		"created_at_msec": Time.get_ticks_msec(),
	}
	_gates[presentation_id] = gate
	if debug_enabled:
		print("[PlayerPresentationAck][debug] gate created id=%s expected=%s speaker=%s text_chars=%d devices=%s" % [
			presentation_id,
			JSON.stringify(expected),
			String(item.get("speaker", "")),
			text_for_item(item).length(),
			JSON.stringify(device_debug),
		])
	return {"ok": true, "created": true, "id": presentation_id}


func gate_blocks_auto_advance() -> bool:
	return not _gates.is_empty()


func has_pending_presentation_id(presentation_id: String) -> bool:
	var clean := presentation_id.strip_edges()
	return clean != "" and (_pending_local.has(clean) or _gates.has(clean))


func has_gate(presentation_id: String) -> bool:
	var clean := presentation_id.strip_edges()
	return clean != "" and _gates.has(clean)


func gate(presentation_id: String) -> Dictionary:
	var clean := presentation_id.strip_edges()
	if clean == "" or not _gates.has(clean):
		return {}
	return (_gates[clean] as Dictionary).duplicate(true)


func clear_gates() -> void:
	_gates.clear()


func begin_local_ack(item: Dictionary, participant_id: String, debug_enabled: bool) -> void:
	var presentation_id := history_presentation_id(item)
	if presentation_id == "" or _pending_local.has(presentation_id):
		return
	_pending_local[presentation_id] = {
		"item": item.duplicate(true),
		"created_at_msec": Time.get_ticks_msec(),
	}
	if debug_enabled:
		print("[PlayerPresentationAck][debug] local pending id=%s participant=%s speaker=%s" % [
			presentation_id,
			participant_id,
			String(item.get("speaker", "")),
		])


func local_ack_pending(presentation_id: String) -> bool:
	var clean := presentation_id.strip_edges()
	return clean != "" and _pending_local.has(clean)


func consume_local_ack_payload(item: Dictionary, participant_id: String, room_id: String, source: String) -> Dictionary:
	var presentation_id := history_presentation_id(item)
	if presentation_id == "" or not _pending_local.has(presentation_id):
		return {}
	_pending_local.erase(presentation_id)
	return {
		"presentationId": presentation_id,
		"presentation_id": presentation_id,
		"participantId": participant_id,
		"source": source,
		"roomId": room_id,
	}


func apply_host_ack(presentation_id: String, participant_id: String, source: String, debug_enabled: bool) -> Dictionary:
	var clean_id := presentation_id.strip_edges()
	var clean_participant := participant_id.strip_edges()
	if clean_id == "" or clean_participant == "":
		return {"applied": false, "opened": false, "reason": "empty"}
	if not _gates.has(clean_id):
		if debug_enabled:
			print("[PlayerPresentationAck][debug] ack ignored id=%s participant=%s reason=no_gate" % [clean_id, clean_participant])
		return {"applied": false, "opened": false, "reason": "no_gate"}
	var gate: Dictionary = (_gates[clean_id] as Dictionary).duplicate(true)
	var expected: Array = gate.get("expected", [])
	if not expected.has(clean_participant):
		if debug_enabled:
			print("[PlayerPresentationAck][debug] ack ignored id=%s participant=%s reason=not_expected expected=%s" % [
				clean_id,
				clean_participant,
				JSON.stringify(expected),
			])
		return {"applied": false, "opened": false, "reason": "not_expected"}
	var acked: Dictionary = gate.get("acked", {})
	acked[clean_participant] = {
		"at_msec": Time.get_ticks_msec(),
		"source": source,
	}
	gate["acked"] = acked
	_gates[clean_id] = gate
	if debug_enabled:
		print("[PlayerPresentationAck][debug] ack accepted id=%s participant=%s acked=%d/%d source=%s" % [
			clean_id,
			clean_participant,
			acked.size(),
			expected.size(),
			source,
		])
	if gate_is_open(gate):
		_gates.erase(clean_id)
		if debug_enabled:
			print("[PlayerPresentationAck][debug] gate open id=%s" % clean_id)
		return {"applied": true, "opened": true, "id": clean_id}
	return {"applied": true, "opened": false, "id": clean_id}


func drop_participant(participant_id: String, debug_enabled: bool) -> Array:
	var clean := participant_id.strip_edges()
	if clean == "":
		return []
	var opened := []
	for gate_id in _gates.keys():
		var gate: Dictionary = (_gates[gate_id] as Dictionary).duplicate(true)
		var expected: Array = gate.get("expected", [])
		if not expected.has(clean):
			continue
		expected.erase(clean)
		gate["expected"] = expected
		_gates[gate_id] = gate
		if debug_enabled:
			print("[PlayerPresentationAck][debug] participant dropped id=%s participant=%s expected_left=%d" % [
				String(gate_id),
				clean,
				expected.size(),
			])
		if gate_is_open(gate):
			opened.append(String(gate_id))
	for gate_id in opened:
		_gates.erase(gate_id)
	return opened


func gate_is_open(gate: Dictionary) -> bool:
	var expected: Array = gate.get("expected", [])
	var acked: Dictionary = gate.get("acked", {})
	for participant_id in expected:
		if not acked.has(String(participant_id)):
			return false
	return true


func text_delay_seconds_for_item(item: Dictionary) -> float:
	return text_delay_seconds_for_text(text_for_item(item))


func text_delay_seconds_for_text(text: String) -> float:
	var chars := text.strip_edges().length()
	return maxf(TEXT_MIN_SECONDS, float(maxi(1, chars)) * TEXT_SECONDS_PER_CHAR)


func text_for_item(item: Dictionary) -> String:
	var display_text := String(item.get("display_text", "")).strip_edges()
	if display_text != "":
		return display_text
	return String(item.get("text", "")).strip_edges()


func debug_snapshot() -> Dictionary:
	var gates := []
	for gate_id in _gates.keys():
		var gate: Dictionary = (_gates[gate_id] as Dictionary).duplicate(true)
		var expected: Array = gate.get("expected", [])
		var acked: Dictionary = gate.get("acked", {})
		var missing := []
		for participant_id in expected:
			if not acked.has(String(participant_id)):
				missing.append(String(participant_id))
		gate["missing"] = missing
		gate["ackCount"] = acked.size()
		gate["expectedCount"] = expected.size()
		gates.append(gate)
	return {
		"gateCount": gates.size(),
		"gates": gates,
		"pendingLocal": _pending_local.keys(),
		"textSecondsPerChar": TEXT_SECONDS_PER_CHAR,
		"textMinSeconds": TEXT_MIN_SECONDS,
	}


func clear() -> void:
	_gates.clear()
	_pending_local.clear()
	_serial = 0
