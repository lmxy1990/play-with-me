extends SceneTree

const IdentityScript := preload("res://scripts/core/device_identity.gd")
const ReplicaScript := preload("res://scripts/room/network/room_replica.gd")
const ElectionScript := preload("res://scripts/room/network/host_election.gd")


func _initialize() -> void:
	var identity = IdentityScript.new()
	identity.persistence_enabled = false
	identity.load_or_create()
	var store = ReplicaScript.new()
	store.persistence_enabled = false
	var frame: Dictionary = store.make_frame(
		"room_1",
		identity.device_id,
		identity.public_key,
		2,
		8,
		3,
		"roster_hash",
		{"room": {"phase": "wolfAction"}}
	)
	var signed: Dictionary = store.sign_frame(frame, identity.to_stored_json())
	assert(not signed.is_empty())
	assert(store.verify_signed_frame(signed))
	assert(store.accept(signed))
	var status: Dictionary = store.status_for_election(identity.device_id, identity.public_key, true, 1)
	assert(int(status.get("electionTerm", 0)) == 2)
	assert(int(status.get("appliedEventSerial", 0)) == 8)
	assert(int(status.get("snapshotVersion", 0)) == 3)

	var tampered := signed.duplicate(true)
	var tampered_frame: Dictionary = (tampered["frame"] as Dictionary).duplicate(true)
	tampered_frame["snapshotVersion"] = 99
	tampered["frame"] = tampered_frame
	assert(not store.verify_signed_frame(tampered))

	var older_frame: Dictionary = store.make_frame(
		"room_1",
		identity.device_id,
		identity.public_key,
		2,
		7,
		9,
		"roster_hash",
		{"state": "older"}
	)
	assert(store.accept(store.sign_frame(older_frame, identity.to_stored_json())))
	assert(int((store.latest()["frame"] as Dictionary).get("appliedEventSerial", 0)) == 8)

	var election = ElectionScript.new()
	var result: Dictionary = election.elect([
		status,
		{
			"deviceId": "device_b",
			"publicKey": "key_b",
			"electionTerm": 5,
			"appliedEventSerial": 8,
			"snapshotVersion": 3,
			"canHost": true,
			"participantOrder": 0,
		},
	])
	assert(bool(result.get("ok", false)))
	assert(String((result["host"] as Dictionary).get("deviceId", "")) == "device_b")
	assert(int(result.get("nextElectionTerm", 0)) == 6)

	var persisted = ReplicaScript.new()
	persisted.save_path = "user://room_replica_check.json"
	persisted.accept(signed)
	var reloaded = ReplicaScript.new()
	reloaded.save_path = "user://room_replica_check.json"
	reloaded.load_or_create()
	var latest: Dictionary = reloaded.latest_for_room("room_1")
	assert(not latest.is_empty())
	assert(int((latest["frame"] as Dictionary).get("appliedEventSerial", 0)) == 8)
	assert((reloaded.list_room_ids() as Array).has("room_1"))
	reloaded.delete_room("room_1")
	assert(reloaded.latest_for_room("room_1").is_empty())
	quit()
