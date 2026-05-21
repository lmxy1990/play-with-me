extends RefCounted
class_name QrScanJoinUi

const MUTED := Color(0.48, 0.38, 0.23)
const TEAL := Color(0.12, 0.46, 0.43)
const RED := Color(0.84, 0.23, 0.18)

var _page
var _active := false
var _waiting_network := false
var _status_base := ""
var _anim_elapsed := 0.0
var _payload_input: LineEdit
var _status_label: Label


func setup(page) -> void:
	_page = page


func open_manual_join(start_scan_callback: Callable, join_callback: Callable, cancel_callback: Callable) -> Dictionary:
	var card := _overlay_card("扫描加入", Vector2(470, 420))
	var body := _overlay_body(card)
	var payload_input := LineEdit.new()
	payload_input.placeholder_text = "扫描结果"
	payload_input.custom_minimum_size = Vector2(0, 34)
	_page.call("_style_input", payload_input)
	var status := _label("", 12, MUTED, false)

	var scanner := PanelContainer.new()
	scanner.custom_minimum_size = Vector2(0, 170)
	scanner.add_theme_stylebox_override("panel", _style_box(Color(0.90, 0.96, 0.90, 0.86), Color(0.12, 0.46, 0.43, 0.44), 8, 1))
	body.add_child(scanner)
	var scanner_body := VBoxContainer.new()
	scanner_body.alignment = BoxContainer.ALIGNMENT_CENTER
	scanner_body.add_theme_constant_override("separation", 8)
	scanner.add_child(scanner_body)
	var scan_label := _label("扫码加入", 22, TEAL, true, HORIZONTAL_ALIGNMENT_CENTER)
	scan_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scanner_body.add_child(scan_label)
	var scan_button := _small_button("启动扫码", true, func(): start_scan_callback.call(payload_input, status))
	scan_button.custom_minimum_size = Vector2(110, 34)
	scanner_body.add_child(scan_button)
	body.add_child(_dense_form_label("加入码"))
	body.add_child(payload_input)
	body.add_child(status)
	body.add_child(_spacer())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	row.add_child(_small_button("取消", false, cancel_callback))
	row.add_child(_small_button("加入", true, func(): join_callback.call(payload_input, status)))
	return {"payload_input": payload_input, "status_label": status}


func open_processing_page(cancel_callback: Callable, retry_callback: Callable) -> Dictionary:
	var card := _overlay_card("加入房间", Vector2(410, 245))
	var body := _overlay_body(card)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 132)
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.90, 0.96, 0.90, 0.88), Color(0.12, 0.46, 0.43, 0.44), 8, 1))
	body.add_child(panel)
	var panel_body := VBoxContainer.new()
	panel_body.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_body.add_theme_constant_override("separation", 8)
	panel.add_child(panel_body)
	var title := _label("正在加入房间", 22, TEAL, true, HORIZONTAL_ALIGNMENT_CENTER)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel_body.add_child(title)
	var status := _label("正在加入", 14, TEAL, false, HORIZONTAL_ALIGNMENT_CENTER)
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_body.add_child(status)
	var payload_input := LineEdit.new()
	payload_input.visible = false
	body.add_child(payload_input)
	body.add_child(_spacer())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	row.add_child(_small_button("取消", false, cancel_callback))
	row.add_child(_small_button("重新扫码", true, retry_callback))
	activate(payload_input, status)
	return {"payload_input": payload_input, "status_label": status}


func activate(payload_input: LineEdit, status_label: Label) -> void:
	_active = true
	_waiting_network = false
	_payload_input = payload_input
	_status_label = status_label
	_status_base = ""
	_anim_elapsed = 0.0


func clear() -> void:
	_active = false
	_waiting_network = false
	_status_base = ""
	_anim_elapsed = 0.0
	_payload_input = null
	_status_label = null


func is_active() -> bool:
	return _active


func is_waiting_network() -> bool:
	return _waiting_network


func payload_input() -> LineEdit:
	return _payload_input


func status_label() -> Label:
	return _status_label


func has_status_label() -> bool:
	return _status_label != null and is_instance_valid(_status_label)


func set_payload_text(payload: String) -> void:
	if _payload_input != null and is_instance_valid(_payload_input):
		_payload_input.text = payload


func set_status(text: String, color: Color) -> bool:
	if not has_status_label():
		return false
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	return true


func set_waiting(text: String) -> void:
	_waiting_network = true
	_status_base = text.strip_edges()
	if _status_base == "":
		_status_base = "正在加入"
	_anim_elapsed = 0.0
	set_status(_status_base, TEAL)


func stop_waiting() -> void:
	_waiting_network = false


func tick(delta: float) -> void:
	if not _active or not _waiting_network:
		return
	if not has_status_label():
		return
	_anim_elapsed += delta
	var dot_count := int(floor(_anim_elapsed * 2.5)) % 4
	var dots := ""
	for _i in range(dot_count):
		dots += "."
	_status_label.text = "%s%s" % [_status_base, dots]


func _overlay_card(title: String, size: Vector2) -> PanelContainer:
	return _page.call("_overlay_card", title, size) as PanelContainer


func _overlay_body(card: Node) -> VBoxContainer:
	return _page.call("_overlay_body", card) as VBoxContainer


func _small_button(text: String, primary: bool, callback: Callable) -> Button:
	return _page.call("_small_button", text, primary, callback) as Button


func _label(text: String, size: int, color: Color, bold: bool, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return _page.call("_label", text, size, color, bold, align) as Label


func _dense_form_label(text: String) -> Label:
	return _page.call("_dense_form_label", text) as Label


func _style_box(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	return _page.call("_style_box", bg, border, radius, width) as StyleBoxFlat


func _spacer() -> Control:
	return _page.call("_spacer") as Control
