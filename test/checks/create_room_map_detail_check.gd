extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.model_configs = [{
		"id": 1,
		"provider": "openai_api",
		"endpoint": "https://example.com/v1",
		"model": "glm-5.1",
		"max_context": 262144,
		"context_window_tokens": 8192,
		"max_output": 4096,
	}]
	var packed := load("res://scenes/lobby.tscn") as PackedScene
	var lobby := packed.instantiate() as Control
	lobby.set_app_state(state)
	root.add_child(lobby)
	await process_frame
	lobby._open_create_room()
	await process_frame
	var catalog: Array = lobby._engine.get_map_list()
	_expect(not catalog.is_empty(), "map catalog is empty")
	_check_count_specific_rules(catalog)
	var slot := lobby.find_child("MapSlot", true, false) as Control
	_expect(slot != null, "map slot was not created")
	var role_counts := lobby.find_child("MapRoleCounts", true, false)
	_expect(role_counts != null, "role count row was not created")
	_expect(_has_label_containing(role_counts, "6人局"), "role count row does not show selected player count")
	_expect(_has_label_containing(role_counts, "狼人 2"), "role count row does not show wolf count")
	_expect(_has_label_containing(role_counts, "平民 2"), "role count row does not show villager count")
	var compression_check := lobby.find_child("TimelineCompressionCheck", true, false) as CheckBox
	var compression_model := lobby.find_child("TimelineCompressionModel", true, false) as OptionButton
	var compression_interval := lobby.find_child("TimelineCompressionInterval", true, false) as LineEdit
	var max_output_tokens := lobby.find_child("RoomMaxOutputTokens", true, false) as LineEdit
	_expect(compression_check != null, "timeline compression checkbox missing")
	_expect(compression_model != null, "timeline compression model dropdown missing")
	_expect(compression_interval != null, "timeline compression interval input missing")
	_expect(max_output_tokens != null, "room max output input missing")
	_expect(not compression_check.button_pressed, "timeline compression should be off by default")
	_expect(String(compression_interval.text) == "8", "timeline compression interval default mismatch")
	_expect(String(max_output_tokens.text) == "2000", "room max output default mismatch")
	_expect(compression_model.item_count >= 2, "timeline compression model list did not include configured model")
	var click_down := InputEventMouseButton.new()
	click_down.button_index = MOUSE_BUTTON_LEFT
	click_down.pressed = true
	click_down.position = Vector2(220, 130)
	slot.emit_signal("gui_input", click_down)
	var click_up := InputEventMouseButton.new()
	click_up.button_index = MOUSE_BUTTON_LEFT
	click_up.pressed = false
	click_up.position = Vector2(220, 130)
	slot.emit_signal("gui_input", click_up)
	await process_frame
	_expect(lobby._modal_layer.find_child("MapDetailOverlay", false, false) == null, "map detail opened on tap")
	if catalog.size() > 1:
		var swipe_down := InputEventMouseButton.new()
		swipe_down.button_index = MOUSE_BUTTON_LEFT
		swipe_down.pressed = true
		swipe_down.position = Vector2(260, 130)
		slot.emit_signal("gui_input", swipe_down)
		var swipe_up := InputEventMouseButton.new()
		swipe_up.button_index = MOUSE_BUTTON_LEFT
		swipe_up.pressed = false
		swipe_up.position = Vector2(90, 130)
		slot.emit_signal("gui_input", swipe_up)
		await process_frame
		_expect(_has_label_text(lobby, String((catalog[1] as Dictionary).get("name", ""))), "map did not switch after swipe")
		var refreshed_role_counts := lobby.find_child("MapRoleCounts", true, false)
		var next_counts: Array = (catalog[1] as Dictionary).get("supported_player_counts", [])
		var next_count := int(next_counts[0])
		_expect(_has_label_containing(refreshed_role_counts, "%d人局" % next_count), "role count row did not refresh selected player count after map switch")
	lobby._clear_modal()
	await process_frame
	await process_frame
	lobby.queue_free()
	await process_frame
	await process_frame
	await process_frame
	slot = null
	role_counts = null
	lobby = null
	packed = null
	catalog.clear()
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _check_count_specific_rules(catalog: Array) -> void:
	for item_value in catalog:
		var item: Dictionary = item_value
		var map_name := String(item.get("name", ""))
		var counts: Array = item.get("supported_player_counts", [])
		var rules: Dictionary = item.get("rule_text_by_count", {})
		var win_rules: Dictionary = item.get("wolf_win_condition_by_count", {})
		for count_value in counts:
			var count := int(count_value)
			_expect(rules.has(count), "%s missing rule text for %d players" % [map_name, count])
			var text := String(rules.get(count, ""))
			_expect(text.contains("%d人局" % count), "%s %d players rule title is not count-specific" % [map_name, count])
			if count >= 6 and count <= 9:
				_expect(text.contains("所有好人全部出局"), "%s %d players wolf win text is not all-good-dead" % [map_name, count])
				_expect(not text.contains("村民或神职全部出局"), "%s %d players still uses slaughter-side wording" % [map_name, count])
				_expect(not text.contains("村民全部出局或神职全部出局"), "%s %d players still uses slaughter-side wording" % [map_name, count])
				_expect(String(win_rules.get(count, "")) == "all_good_dead", "%s %d players win condition key is not all_good_dead" % [map_name, count])
			elif count >= 10:
				_expect(text.contains("村民全部出局或神职全部出局"), "%s %d players wolf win text is not slaughter-side" % [map_name, count])
				_expect(String(win_rules.get(count, "")) == "slaughter_side", "%s %d players win condition key is not slaughter_side" % [map_name, count])


func _has_label_text(node: Node, text: String) -> bool:
	if node is Label and String((node as Label).text) == text:
		return true
	for child in node.get_children():
		if _has_label_text(child, text):
			return true
	return false


func _has_label_containing(node: Node, text: String) -> bool:
	if node is Label and String((node as Label).text).contains(text):
		return true
	for child in node.get_children():
		if _has_label_containing(child, text):
			return true
	return false
