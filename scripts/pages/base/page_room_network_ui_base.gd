extends "res://scripts/pages/base/page_identity_ui_base.gd"

const RoomNetworkSessionScript := preload("res://scripts/room/network/room_network_session.gd")

var _room_network_port := 42871
var _owns_room_network_session := false


func set_network_session(session) -> void:
	_room_network_session = session
	_ensure_device_identity_loaded()
	_apply_network_identity()
	_connect_room_network_signals()
	if _room_network_session != null and _room_network_session.has_method("port") and int(_room_network_session.call("port")) > 0:
		_room_network_port = int(_room_network_session.call("port"))


func _ensure_room_network_session() -> void:
	if _room_network_session != null:
		_apply_network_identity()
		return
	_room_network_session = RoomNetworkSessionScript.new()
	_owns_room_network_session = true
	add_child(_room_network_session)
	_apply_network_identity()
	_connect_room_network_signals()


func _connect_room_network_signals() -> void:
	if _room_network_session == null:
		return
	var client_message_received := Callable(self, "_on_network_client_message_received")
	var snapshot_received := Callable(self, "_on_network_snapshot_received")
	var join_accepted := Callable(self, "_on_network_join_accepted")
	var join_rejected := Callable(self, "_on_network_join_rejected")
	var server_message_received := Callable(self, "_on_network_server_message_received")
	var status_changed := Callable(self, "_on_network_status_changed")
	var peer_disconnected := Callable(self, "_on_network_peer_disconnected")
	if _room_network_session.has_signal("client_message_received") and not _room_network_session.client_message_received.is_connected(client_message_received):
		_room_network_session.client_message_received.connect(client_message_received)
	if _room_network_session.has_signal("snapshot_received") and not _room_network_session.snapshot_received.is_connected(snapshot_received):
		_room_network_session.snapshot_received.connect(snapshot_received)
	if _room_network_session.has_signal("join_accepted") and not _room_network_session.join_accepted.is_connected(join_accepted):
		_room_network_session.join_accepted.connect(join_accepted)
	if _room_network_session.has_signal("join_rejected") and not _room_network_session.join_rejected.is_connected(join_rejected):
		_room_network_session.join_rejected.connect(join_rejected)
	if _room_network_session.has_signal("server_message_received") and not _room_network_session.server_message_received.is_connected(server_message_received):
		_room_network_session.server_message_received.connect(server_message_received)
	if _room_network_session.has_signal("status_changed") and not _room_network_session.status_changed.is_connected(status_changed):
		_room_network_session.status_changed.connect(status_changed)
	if _room_network_session.has_signal("peer_disconnected") and not _room_network_session.peer_disconnected.is_connected(peer_disconnected):
		_room_network_session.peer_disconnected.connect(peer_disconnected)


func _disconnect_room_network_signals() -> void:
	if _room_network_session == null:
		return
	var client_message_received := Callable(self, "_on_network_client_message_received")
	var snapshot_received := Callable(self, "_on_network_snapshot_received")
	var join_accepted := Callable(self, "_on_network_join_accepted")
	var join_rejected := Callable(self, "_on_network_join_rejected")
	var server_message_received := Callable(self, "_on_network_server_message_received")
	var status_changed := Callable(self, "_on_network_status_changed")
	var peer_disconnected := Callable(self, "_on_network_peer_disconnected")
	if _room_network_session.has_signal("client_message_received") and _room_network_session.client_message_received.is_connected(client_message_received):
		_room_network_session.client_message_received.disconnect(client_message_received)
	if _room_network_session.has_signal("snapshot_received") and _room_network_session.snapshot_received.is_connected(snapshot_received):
		_room_network_session.snapshot_received.disconnect(snapshot_received)
	if _room_network_session.has_signal("join_accepted") and _room_network_session.join_accepted.is_connected(join_accepted):
		_room_network_session.join_accepted.disconnect(join_accepted)
	if _room_network_session.has_signal("join_rejected") and _room_network_session.join_rejected.is_connected(join_rejected):
		_room_network_session.join_rejected.disconnect(join_rejected)
	if _room_network_session.has_signal("server_message_received") and _room_network_session.server_message_received.is_connected(server_message_received):
		_room_network_session.server_message_received.disconnect(server_message_received)
	if _room_network_session.has_signal("status_changed") and _room_network_session.status_changed.is_connected(status_changed):
		_room_network_session.status_changed.disconnect(status_changed)
	if _room_network_session.has_signal("peer_disconnected") and _room_network_session.peer_disconnected.is_connected(peer_disconnected):
		_room_network_session.peer_disconnected.disconnect(peer_disconnected)


func _is_network_host() -> bool:
	return _room_network_session != null and _room_network_session.has_method("is_host") and bool(_room_network_session.call("is_host"))


func _is_network_client() -> bool:
	return _room_network_session != null and _room_network_session.has_method("is_client") and bool(_room_network_session.call("is_client"))


func _current_network_participant_id() -> String:
	if _room_network_session != null and _room_network_session.has_method("local_participant_id"):
		var id := String(_room_network_session.call("local_participant_id")).strip_edges()
		if id != "":
			return id
	return "host"


func _send_network_rejection(peer_id: int, message: String) -> void:
	if _room_network_session != null:
		_room_network_session.call("send_to_peer", peer_id, "action_rejected", {"message": message})
