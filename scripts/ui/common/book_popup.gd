extends Control

signal close_requested

const CLOSE_ICON := "res://assets/images/werewolf/actions/close.svg"
const FRAME_TEXTURE := "res://assets/images/werewolf/ui/create_room_popup_frame.png"
const BackdropScript := preload("res://scripts/ui/common/book_popup_backdrop.gd")

var _left_page: VBoxContainer
var _right_page: VBoxContainer
var _shade: Control
var _book: Control
var _book_art: TextureRect
var _book_size := Vector2.ZERO
var _target_position := Vector2.ZERO
var _fly_position := Vector2.ZERO
var _content_root: Control
var _floating_close: Button
var _close_callback := Callable()
var _closing := false


func setup(title: String, close_callback: Callable = Callable(), size: Vector2 = Vector2(880, 500)) -> void:
	_close_callback = close_callback
	_build(title, size)
	call_deferred("_play_open_animation")


func _exit_tree() -> void:
	_close_callback = Callable()
	_left_page = null
	_right_page = null
	_shade = null
	_book = null
	_book_art = null
	_content_root = null
	_floating_close = null


func left_page() -> VBoxContainer:
	return _left_page


func right_page() -> VBoxContainer:
	return _right_page


func close() -> void:
	_request_close()


func _gui_input(event: InputEvent) -> void:
	if _closing or not _outside_close_event(event):
		return
	var event_position := _outside_close_position(event)
	if _book != null and _book.get_rect().has_point(event_position):
		return
	accept_event()
	_request_close()


func _outside_close_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _outside_close_position(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	return Vector2.ZERO


func _build(title: String, size: Vector2) -> void:
	for child in get_children():
		child.queue_free()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_book_size = size
	var viewport_size := Vector2(1280, 720)
	if is_inside_tree():
		viewport_size = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(1280, 720)
	_target_position = (viewport_size - size) * 0.5
	_fly_position = Vector2(viewport_size.x - size.x * 0.20, -size.y * 0.58)

	_shade = BackdropScript.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.modulate.a = 0.0
	add_child(_shade)

	_book = Control.new()
	_book.name = "Book"
	_book.mouse_filter = Control.MOUSE_FILTER_STOP
	_book.custom_minimum_size = size
	_book.size = size
	_book.position = _fly_position
	_book.pivot_offset = size * 0.5
	_book.scale = Vector2(0.34, 0.74)
	_book.rotation = -0.16
	_book.modulate.a = 0.0
	add_child(_book)

	_book_art = TextureRect.new()
	_book_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_book_art.texture = load(FRAME_TEXTURE)
	_book_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_book_art.stretch_mode = TextureRect.STRETCH_SCALE
	_book_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book_art.modulate = Color(1.14, 1.03, 0.82, 0.72)
	_book.add_child(_book_art)

	_content_root = Control.new()
	_content_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content_root.modulate.a = 0.0
	_book.add_child(_content_root)

	var cover_margin := MarginContainer.new()
	cover_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin_each(cover_margin, 84, 86, 84, 82)
	_content_root.add_child(cover_margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	cover_margin.add_child(root)

	if title.strip_edges() != "":
		var head := HBoxContainer.new()
		head.custom_minimum_size = Vector2(0, 34)
		head.add_theme_constant_override("separation", 8)
		root.add_child(head)
		var title_label := Label.new()
		title_label.text = title
		title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_label.clip_text = true
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title_label.add_theme_color_override("font_color", Color(0.55, 0.31, 0.09))
		title_label.add_theme_font_size_override("font_size", 20)
		title_label.add_theme_color_override("font_shadow_color", Color(1.0, 0.90, 0.58, 0.34))
		title_label.add_theme_constant_override("shadow_offset_x", 0)
		title_label.add_theme_constant_override("shadow_offset_y", 1)
		head.add_child(title_label)

	var pages := HBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_theme_constant_override("separation", 0)
	root.add_child(pages)

	var left_panel := _page_panel(true)
	pages.add_child(left_panel)
	_left_page = _page_body(left_panel)

	var spine := PanelContainer.new()
	spine.custom_minimum_size = Vector2(42, 0)
	spine.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	pages.add_child(spine)

	var right_panel := _page_panel(false)
	pages.add_child(right_panel)
	_right_page = _page_body(right_panel)

	_floating_close = _close_button()
	_floating_close.name = "FloatingClose"
	_floating_close.size = _floating_close.custom_minimum_size
	_floating_close.position = Vector2(size.x - 122.0, 80.0)
	_floating_close.z_index = 30
	_floating_close.modulate.a = 0.0
	_book.add_child(_floating_close)


func _page_panel(left_side: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var page_tint := Color(0.98, 0.90, 0.66, 0.93) if left_side else Color(0.97, 0.88, 0.63, 0.93)
	panel.add_theme_stylebox_override("panel", _style_box(page_tint, Color(0.58, 0.36, 0.12, 0.28), 10, 1))
	return panel


func _page_body(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin_each(margin, 18, 12, 18, 12)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	margin.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	return body


func _close_button() -> Button:
	var button := Button.new()
	button.tooltip_text = "关闭"
	button.custom_minimum_size = Vector2(44, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.icon = load(CLOSE_ICON)
	button.expand_icon = true
	button.add_theme_stylebox_override("normal", _style_box(Color(0.80, 0.30, 0.20, 0.92), Color(0.98, 0.70, 0.42, 0.58), 8, 2))
	button.add_theme_stylebox_override("hover", _style_box(Color(0.90, 0.38, 0.24, 0.96), Color(1.0, 0.78, 0.42, 0.80), 8, 2))
	button.add_theme_stylebox_override("pressed", _style_box(Color(0.68, 0.22, 0.16, 0.96), Color(0.90, 0.50, 0.16, 0.76), 8, 2))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_request_close)
	return button


func _request_close() -> void:
	if _closing:
		return
	_closing = true
	_play_close_animation()


func _play_open_animation() -> void:
	if _book == null:
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_shade, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_book, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_book, "position", _target_position, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_book, "scale", Vector2(0.46, 0.82), 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_book, "rotation", 0.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_book, "scale", Vector2.ONE, 0.58).set_delay(0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_content_root, "modulate:a", 1.0, 0.26).set_delay(0.86).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_floating_close, "modulate:a", 1.0, 0.20).set_delay(0.78).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _play_close_animation() -> void:
	if _book == null:
		_finish_close()
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_content_root, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _floating_close != null:
		tween.tween_property(_floating_close, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_book, "scale", Vector2(0.46, 0.82), 0.46).set_delay(0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_fly_out_after_close)


func _fly_out_after_close() -> void:
	if _book == null:
		_finish_close()
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_shade, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_book, "position", _fly_position, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_book, "rotation", 0.16, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_book, "scale", Vector2(0.28, 0.58), 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_book, "modulate:a", 0.0, 0.20).set_delay(0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(_finish_close)


func _finish_close() -> void:
	if _close_callback.is_valid():
		_close_callback.call()
	else:
		close_requested.emit()
		queue_free()


func _style_box(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color(0.18, 0.10, 0.03, 0.16)
	box.shadow_size = 5
	box.shadow_offset = Vector2(0, 1)
	return box


func _margin_each(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)
