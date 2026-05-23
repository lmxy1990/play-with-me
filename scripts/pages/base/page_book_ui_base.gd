extends "res://scripts/pages/base/page_scan_join_flow_base.gd"

const QrCodeGeneratorScript := preload("res://scripts/ui/qr/qr_code_generator.gd")
const BookPopupScene := preload("res://scenes/common/book_popup.tscn")

var _hud_layer: Control
var _modal_layer: Control
var _toast_tween: Tween
var _modal_outside_close_guard_until_msec := 0


func _book_status(status: Label, text: String, color: Color) -> void:
	if status == null or not is_instance_valid(status):
		return
	status.text = text
	status.add_theme_color_override("font_color", color)


func _show_toast(text: String, color: Color = BOOK_GREEN) -> void:
	var message := text.strip_edges()
	if message == "":
		return
	if _hud_layer == null:
		return
	for child in _hud_layer.get_children():
		if child.name == "Toast":
			child.queue_free()
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null
	var toast := PanelContainer.new()
	toast.name = "Toast"
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 0.0
	toast.anchor_bottom = 0.0
	toast.offset_left = -250
	toast.offset_right = 250
	toast.offset_top = 24
	toast.offset_bottom = 68
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_stylebox_override("panel", _style_box(Color(1.0, 0.94, 0.76, 0.94), Color(color.r, color.g, color.b, 0.56), 8, 1))
	var margin := MarginContainer.new()
	_margin_each(margin, 16, 6, 16, 6)
	toast.add_child(margin)
	var label := _book_label(message, 12, color, true, HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(label)
	_hud_layer.add_child(toast)
	toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.12)
	_toast_tween.tween_interval(1.65)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.22)
	_toast_tween.tween_callback(toast.queue_free)


func _modal_backdrop(color: Color, close_callback: Callable = Callable(), close_on_outside: bool = true) -> ColorRect:
	var shade := ColorRect.new()
	shade.name = "ModalOutsideCloseArea"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = color
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event: InputEvent):
		if not _modal_outside_close_event(event):
			return
		shade.accept_event()
		if not close_on_outside:
			return
		if _modal_outside_close_guard_active():
			if OS.is_debug_build():
				print("[ModalLayer][debug] outside_close ignored reason=open_guard")
			return
		call("_play_click")
		if close_callback.is_valid():
			close_callback.call()
		else:
			call("_clear_modal")
	)
	return shade


func _modal_outside_close_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _begin_modal_outside_close_guard(duration_msec: int = 260) -> void:
	_modal_outside_close_guard_until_msec = Time.get_ticks_msec() + maxi(0, duration_msec)


func _modal_outside_close_guard_active() -> bool:
	return Time.get_ticks_msec() < _modal_outside_close_guard_until_msec


func _overlay_card(title: String, size: Vector2, close_on_outside: bool = true, show_close_button: bool = true) -> PanelContainer:
	call("_clear_modal")
	_begin_modal_outside_close_guard()
	_modal_layer.add_child(_modal_backdrop(Color(0.42, 0.28, 0.10, 0.055), Callable(), close_on_outside))

	var card := _panel(Color(0.97, 0.88, 0.66, 0.94), Color(0.56, 0.34, 0.12, 0.42), 8)
	card.name = "OverlayCard"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size = size
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -size.x * 0.5
	card.offset_right = size.x * 0.5
	card.offset_top = -size.y * 0.5
	card.offset_bottom = size.y * 0.5
	_modal_layer.add_child(card)

	var margin := MarginContainer.new()
	_margin(margin, 14)
	card.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	head.add_child(_label(title, 18, INK, true))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	if show_close_button:
		head.add_child(_close_icon_button(func(): call("_clear_modal"), true))

	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 9)
	root.add_child(body)
	return card


func _config_drawer(title: String, close_callback: Callable) -> VBoxContainer:
	_begin_modal_outside_close_guard()
	_modal_layer.add_child(_modal_backdrop(Color(0.42, 0.28, 0.10, 0.055), close_callback))

	var card := _panel(Color(0.97, 0.88, 0.66, 0.95), Color(0.56, 0.34, 0.12, 0.42), 8)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.anchor_top = 0.0
	card.anchor_bottom = 1.0
	card.offset_left = -520
	card.offset_right = -16
	card.offset_top = 16
	card.offset_bottom = -16
	_modal_layer.add_child(card)

	var margin := MarginContainer.new()
	_margin(margin, 14)
	card.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	head.add_child(_label(title, 18, INK, true))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	head.add_child(_close_icon_button(close_callback, true))

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 9)
	root.add_child(body)
	return body


func _book_popup(title: String, size: Vector2, close_callback: Callable = Callable()) -> Dictionary:
	call("_clear_modal")
	_begin_modal_outside_close_guard()
	var callback := func():
		call("_play_click")
		if close_callback.is_valid():
			close_callback.call()
		else:
			call("_clear_modal")
	var popup := BookPopupScene.instantiate() as Control
	_modal_layer.add_child(popup)
	popup.call("setup", title, callback, size)
	return {
		"popup": popup,
		"left": popup.call("left_page") as VBoxContainer,
		"right": popup.call("right_page") as VBoxContainer,
	}


func _book_label(text: String, size: int = 13, color: Color = BOOK_TEXT, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", _ui_font_size(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", -1)
	if bold and color == BOOK_GOLD:
		label.add_theme_color_override("font_shadow_color", Color(1.0, 0.85, 0.42, 0.18))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _book_section_label(text: String) -> Label:
	var label := _book_label(text, 15, BOOK_GOLD, true)
	label.custom_minimum_size = Vector2(0, 28)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _book_form_label(text: String) -> Label:
	return _book_label(text, 12, BOOK_MUTED, true)


func _book_line(parent: VBoxContainer, title: String, value: String, secret: bool = false) -> LineEdit:
	parent.add_child(_book_form_label(title))
	var line := LineEdit.new()
	line.text = value
	line.secret = secret
	line.custom_minimum_size = Vector2(0, 35)
	_style_book_input(line)
	parent.add_child(line)
	return line


func _book_action_row(parent: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	return row


func _book_button(text: String, primary: bool, callback: Callable, danger: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(92, 36)
	button.focus_mode = Control.FOCUS_NONE
	_style_book_button(button, primary, danger)
	button.pressed.connect(func():
		call("_play_click")
		callback.call()
	)
	return button


func _style_book_input(control: Control) -> void:
	control.add_theme_stylebox_override("normal", _style_box(Color(1.0, 0.95, 0.78, 0.92), Color(0.46, 0.28, 0.10, 0.34), 7, 1))
	control.add_theme_stylebox_override("focus", _style_box(Color(1.0, 0.97, 0.84, 0.98), Color(0.74, 0.44, 0.12, 0.70), 7, 1))
	control.add_theme_color_override("font_color", BOOK_TEXT)
	control.add_theme_color_override("font_focus_color", BOOK_TEXT)
	control.add_theme_color_override("font_selected_color", Color(1.0, 0.98, 0.90))
	control.add_theme_color_override("font_uneditable_color", Color(0.38, 0.27, 0.14))
	control.add_theme_color_override("font_placeholder_color", BOOK_MUTED)
	control.add_theme_color_override("selection_color", Color(0.52, 0.30, 0.08, 0.84))
	control.add_theme_color_override("caret_color", BOOK_GOLD)
	control.add_theme_font_size_override("font_size", _ui_font_size(12))


func _style_book_button(button: Button, primary: bool, danger: bool = false) -> void:
	var bg := Color(0.93, 0.80, 0.55, 0.74)
	var border := Color(0.46, 0.27, 0.10, 0.40)
	var font := BOOK_TEXT
	if primary:
		bg = Color(0.84, 0.51, 0.15, 0.94)
		border = Color(0.52, 0.28, 0.08, 0.72)
		font = Color(0.16, 0.08, 0.03)
	if danger:
		bg = Color(0.62, 0.15, 0.10, 0.92)
		border = Color(0.86, 0.36, 0.24, 0.64)
		font = Color(1.0, 0.88, 0.74)
	button.add_theme_stylebox_override("normal", _style_box(bg, border, 7, 1))
	button.add_theme_stylebox_override("hover", _style_box(bg.lightened(0.06), border.lightened(0.08), 7, 1))
	button.add_theme_stylebox_override("pressed", _style_box(bg.darkened(0.10), border, 7, 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", font)
	button.add_theme_color_override("font_pressed_color", font)
	button.add_theme_font_size_override("font_size", _ui_font_size(12))


func _style_book_checkbox(checkbox: CheckBox) -> void:
	checkbox.add_theme_font_size_override("font_size", _ui_font_size(12))
	checkbox.add_theme_color_override("font_color", BOOK_TEXT)
	checkbox.add_theme_color_override("font_hover_color", BOOK_TEXT)
	checkbox.add_theme_color_override("font_pressed_color", BOOK_TEXT)


func _lobby_overlay_card(title: String, size: Vector2) -> PanelContainer:
	call("_clear_modal")
	_begin_modal_outside_close_guard()
	_modal_layer.add_child(_modal_backdrop(Color(0.42, 0.28, 0.10, 0.055)))

	var card := _panel(Color(0.92, 0.82, 0.60, 0.94), Color(0.54, 0.34, 0.13, 0.44), 8)
	card.name = "OverlayCard"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size = size
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -size.x * 0.5
	card.offset_right = size.x * 0.5
	card.offset_top = -size.y * 0.5
	card.offset_bottom = size.y * 0.5
	_modal_layer.add_child(card)

	var margin := MarginContainer.new()
	_margin(margin, 14)
	card.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	head.add_child(_label(title, 18, FRESH_TEXT, true))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	head.add_child(_close_icon_button(func(): call("_clear_modal"), true))

	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 9)
	root.add_child(body)
	return card


func _side_overlay(title: String) -> PanelContainer:
	call("_clear_modal")
	_begin_modal_outside_close_guard()
	_modal_layer.add_child(_modal_backdrop(Color(0.42, 0.28, 0.10, 0.055)))

	var card := _panel(Color(0.97, 0.88, 0.66, 0.95), Color(0.56, 0.34, 0.12, 0.42), 8)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.anchor_top = 0.0
	card.anchor_bottom = 1.0
	card.offset_left = -380
	card.offset_right = -14
	card.offset_top = 14
	card.offset_bottom = -14
	_modal_layer.add_child(card)

	var margin := MarginContainer.new()
	_margin(margin, 12)
	card.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 9)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(_label(title, 18, INK, true))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	head.add_child(_close_icon_button(func(): call("_clear_modal"), true))
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)
	return card


func _overlay_body(card: Node) -> VBoxContainer:
	return card.find_child("Body", true, false) as VBoxContainer


func _fake_qr(seed: String = "") -> Control:
	const QR_DISPLAY_SIZE := 320
	var texture := TextureRect.new()
	texture.custom_minimum_size = Vector2(QR_DISPLAY_SIZE, QR_DISPLAY_SIZE)
	texture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var generator = QrCodeGeneratorScript.new()
	texture.texture = generator.make_texture(seed, 6, 4, Color.BLACK, Color.WHITE)
	if texture.texture == null:
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(QR_DISPLAY_SIZE, QR_DISPLAY_SIZE)
		placeholder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		placeholder.color = Color.WHITE
		return placeholder
	return texture


func _history_line(speaker: String, text: String) -> PanelContainer:
	var row := _panel(Color(0.99, 0.92, 0.72, 0.82), Color(0.62, 0.40, 0.16, 0.22), 7)
	var margin := MarginContainer.new()
	_margin_each(margin, 8, 6, 8, 6)
	row.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	margin.add_child(line)
	line.add_child(_stat_badge("•", speaker, GOLD if speaker == "主持人" else TEAL, 82))
	var content := _nowrap_label(text, 12, INK, false)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(content)
	return row


func _config_row(title: String, detail: String, active: bool) -> PanelContainer:
	var row := _panel(Color(0.99, 0.92, 0.72, 0.84), TEAL if active else Color(0.62, 0.40, 0.16, 0.22), 7)
	var margin := MarginContainer.new()
	_margin(margin, 8)
	row.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 1)
	margin.add_child(body)
	body.add_child(_label(title, 13, INK, true))
	body.add_child(_label(detail, 11, MUTED))
	return row


func _choice_button(text: String, active: bool) -> Button:
	var button := _small_button(text, active, func(): pass)
	button.toggle_mode = true
	button.button_pressed = active
	return button


func _fresh_choice_button(text: String, active: bool) -> Button:
	var button := _fresh_button(text, active, func(): pass)
	button.toggle_mode = true
	button.button_pressed = active
	return button


func _dense_line(text: String) -> LineEdit:
	var line := LineEdit.new()
	line.text = text
	line.custom_minimum_size = Vector2(0, 32)
	_style_input(line)
	return line


func _mini_slider(title: String, value: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := _label(title, 12, MUTED, true)
	label.custom_minimum_size = Vector2(36, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	return row
