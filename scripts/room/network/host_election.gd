extends RefCounted
class_name HostElection


func elect(replicas: Array) -> Dictionary:
	var eligible: Array = []
	for item in replicas:
		if not (item is Dictionary):
			continue
		var replica: Dictionary = item
		if bool(replica.get("canHost", false)) and String(replica.get("deviceId", "")).strip_edges() != "":
			eligible.append(replica.duplicate(true))
	if eligible.is_empty():
		return {"ok": false, "error": "No eligible host replica"}
	eligible.sort_custom(_compare_replica_priority)
	return {
		"ok": true,
		"host": eligible[0],
		"nextElectionTerm": _next_election_term(replicas),
	}


static func compare_replica_priority(left: Dictionary, right: Dictionary) -> int:
	var event_compare := int(right.get("appliedEventSerial", 0)) - int(left.get("appliedEventSerial", 0))
	if event_compare != 0:
		return event_compare
	var snapshot_compare := int(right.get("snapshotVersion", 0)) - int(left.get("snapshotVersion", 0))
	if snapshot_compare != 0:
		return snapshot_compare
	var order_compare := int(left.get("participantOrder", 1 << 30)) - int(right.get("participantOrder", 1 << 30))
	if order_compare != 0:
		return order_compare
	return String(left.get("deviceId", "")).naturalnocasecmp_to(String(right.get("deviceId", "")))


static func _compare_replica_priority(left: Dictionary, right: Dictionary) -> bool:
	return compare_replica_priority(left, right) < 0


func _next_election_term(replicas: Array) -> int:
	var max_term := 0
	for item in replicas:
		if item is Dictionary:
			max_term = max(max_term, int((item as Dictionary).get("electionTerm", 0)))
	return max_term + 1
