extends SceneTree

const ResolverScript := preload("res://scripts/player/player_presentation_ack_participant_resolver.gd")


func _initialize() -> void:
	var resolver = ResolverScript.new()
	var public_plan: Dictionary = resolver.build_plan("", true, [
		{"peerId": 11, "participantId": "host", "visible": true},
		{"peerId": 12, "participantId": "peer_human", "visible": true},
		{"peerId": 13, "participantId": "peer_private", "visible": false},
		{"peerId": 21, "participantId": "", "visible": true},
		{"peerId": 22, "participantId": "", "visible": false},
	])
	var expected: Array = public_plan.get("expected", [])
	if not _expect(expected == ["host", "peer_human", "peer:21"], "expected ACK list deduplicates local participant and includes visible pending peer"):
		return
	var devices: Array = public_plan.get("devices", [])
	if not _expect(devices.size() == 6, "debug devices include local and all peers"):
		return
	if not _expect(String((devices[0] as Dictionary).get("ackId", "")) == "host", "empty local participant defaults to host"):
		return
	if not _expect(String((devices[4] as Dictionary).get("ackId", "")) == "peer:21", "pending peer gets stable ack id"):
		return
	if not _expect(not expected.has("peer_private"), "invisible participant is not expected"):
		return
	if not _expect(not expected.has("peer:22"), "invisible pending peer is not expected"):
		return

	var private_plan: Dictionary = resolver.build_plan("viewer_a", false, [
		{"peerId": 31, "participantId": "viewer_b", "visible": true},
	])
	var private_expected: Array = private_plan.get("expected", [])
	if not _expect(private_expected == ["viewer_b"], "local device is skipped when local view cannot see item"):
		return
	if not _expect(resolver.ack_id_for_peer(41, "") == "peer:41", "peer id fallback is stable"):
		return
	if not _expect(resolver.ack_id_for_peer(0, "") == "", "invalid peer without participant has no ack id"):
		return
	if not _expect(resolver.participant_id_for_ack(0, {"participantId": "host_payload"}, "") == "host_payload", "local ack uses payload participant"):
		return
	if not _expect(resolver.participant_id_for_ack(0, {}, "") == "host", "local ack without payload falls back to host"):
		return
	if not _expect(resolver.participant_id_for_ack(42, {}, "") == "peer:42", "remote ack without participant falls back to peer ack id"):
		return
	if not _expect(resolver.participant_id_for_ack(43, {"participantId": "payload_ignored"}, "session_peer") == "session_peer", "remote ack trusts session participant"):
		return
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("player_presentation_ack_participant_resolver_check failed: %s" % message)
	quit(1)
	return false
