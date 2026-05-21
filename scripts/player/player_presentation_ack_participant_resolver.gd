extends RefCounted


func build_plan(local_participant_id: String, local_visible: bool, peer_records: Array) -> Dictionary:
	var local_ack_id := local_participant_id.strip_edges()
	if local_ack_id == "":
		local_ack_id = "host"
	var devices := [{
		"peerId": 0,
		"participantId": local_ack_id,
		"ackId": local_ack_id,
		"visible": local_visible,
	}]
	var expected := []
	if local_visible:
		expected.append(local_ack_id)
	for record_value in peer_records:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var peer_id := int(record.get("peerId", record.get("peer_id", 0)))
		var participant_id := String(record.get("participantId", record.get("participant_id", ""))).strip_edges()
		var ack_id := ack_id_for_peer(peer_id, participant_id)
		var visible := bool(record.get("visible", false))
		devices.append({
			"peerId": peer_id,
			"participantId": participant_id,
			"ackId": ack_id,
			"visible": visible,
		})
		if ack_id == "" or not visible or expected.has(ack_id):
			continue
		expected.append(ack_id)
	return {
		"expected": expected,
		"devices": devices,
	}


func expected_participants(local_participant_id: String, local_visible: bool, peer_records: Array) -> Array:
	return build_plan(local_participant_id, local_visible, peer_records).get("expected", [])


func connected_device_debug(local_participant_id: String, local_visible: bool, peer_records: Array) -> Array:
	return build_plan(local_participant_id, local_visible, peer_records).get("devices", [])


func ack_id_for_peer(peer_id: int, participant_id: String) -> String:
	var clean := participant_id.strip_edges()
	if clean != "":
		return clean
	if peer_id > 0:
		return "peer:%d" % peer_id
	return ""


func participant_id_for_ack(peer_id: int, payload: Dictionary, session_participant_id: String) -> String:
	var participant_id := session_participant_id.strip_edges()
	if peer_id <= 0 and participant_id == "":
		participant_id = String(payload.get("participantId", payload.get("participant_id", ""))).strip_edges()
	if participant_id == "":
		return "host" if peer_id <= 0 else ack_id_for_peer(peer_id, "")
	return participant_id
