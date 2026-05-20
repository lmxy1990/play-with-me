extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")
const LobbyScene := preload("res://scenes/lobby.tscn")


func _initialize() -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.rooms = [
		{"id": "room_reconnect", "name": "普通重复房间", "state": "等待中", "type": "狼人杀", "players": "1/6", "lock": "公开", "address": "127.0.0.1:42871", "bg": "res://assets/images/werewolf/backgrounds/lobby.png"},
		{"id": "room_other", "name": "其他房间", "state": "等待中", "type": "狼人杀", "players": "0/6", "lock": "公开", "address": "127.0.0.1:42872", "bg": "res://assets/images/werewolf/backgrounds/lobby.png"},
	]
	var lobby := LobbyScene.instantiate()
	lobby.set_app_state(state)
	root.add_child(lobby)
	lobby._room_session_store.save({
		"host": "127.0.0.1",
		"port": 42871,
		"participantId": "peer_check",
		"reconnectToken": "token_check",
		"roomId": "room_reconnect",
		"savedAtMs": Time.get_ticks_msec(),
	})
	await process_frame
	lobby._show_lobby()
	await process_frame
	var cards: Array = lobby._lobby_room_cards()
	assert(cards.size() == 2)
	assert(bool((cards[0] as Dictionary).get("reconnect", false)))
	assert(String((cards[0] as Dictionary).get("id", "")) == "room_reconnect")
	assert(String((cards[1] as Dictionary).get("id", "")) == "room_other")
	assert(_count_tooltips(lobby, "重连上次房间") == 0)
	lobby.queue_free()
	quit()


func _count_tooltips(node: Node, tooltip: String) -> int:
	var count := 0
	if node is Control and String((node as Control).tooltip_text) == tooltip:
		count += 1
	for child in node.get_children():
		count += _count_tooltips(child, tooltip)
	return count
