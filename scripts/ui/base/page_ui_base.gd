extends Control

const ACTION_CLOSE := "res://assets/images/werewolf/actions/close.svg"

const INK := Color(0.16, 0.11, 0.055)
const MUTED := Color(0.48, 0.38, 0.23)
const DIM := Color(0.66, 0.55, 0.36)
const GOLD := Color(0.69, 0.41, 0.11)
const TEAL := Color(0.12, 0.46, 0.43)
const RED := Color(0.84, 0.23, 0.18)
const GREEN := Color(0.18, 0.48, 0.25)
const PANEL := Color(0.96, 0.88, 0.66, 0.82)
const PANEL_DARK := Color(0.93, 0.80, 0.56, 0.90)
const PANEL_SOFT := Color(0.98, 0.91, 0.70, 0.70)
const LINE := Color(0.62, 0.39, 0.14, 0.32)
const FRESH_BG := Color(0.89, 0.84, 0.70)
const FRESH_PANEL := Color(0.98, 0.92, 0.74, 0.94)
const FRESH_TEXT := Color(0.15, 0.22, 0.20)
const FRESH_MUTED := Color(0.42, 0.49, 0.43)
const FRESH_SKY := Color(0.34, 0.62, 0.82)
const FRESH_MINT := Color(0.34, 0.70, 0.58)
const FRESH_CORAL := Color(0.77, 0.28, 0.22)
const FRESH_LILAC := Color(0.49, 0.45, 0.74)
const FRESH_GOLD := Color(0.75, 0.48, 0.18)
const BOOK_TEXT := Color(0.18, 0.11, 0.045)
const BOOK_MUTED := Color(0.43, 0.30, 0.16)
const BOOK_LINE := Color(0.55, 0.34, 0.13, 0.46)
const BOOK_GOLD := Color(0.62, 0.35, 0.09)
const BOOK_GREEN := Color(0.17, 0.42, 0.28)
const BOOK_RED := Color(0.62, 0.15, 0.10)
const UI_FONT_BOOST := 2

var _texture_cache := {}
var _bg: TextureRect
var _tint: ColorRect


func _play_click() -> void:
	pass


func _dense_form_label(text: String) -> Label:
	return _label(text, 12, MUTED, true)


func _fresh_form_label(text: String) -> Label:
	return _label(text, 12, FRESH_MUTED, true)


func _compact_status(text: String, color: Color) -> PanelContainer:
	var status := _panel(Color(0.98, 0.91, 0.70, 0.76), Color(color.r, color.g, color.b, 0.34), 999)
	var margin := MarginContainer.new()
	_margin_each(margin, 10, 4, 10, 4)
	status.add_child(margin)
	margin.add_child(_label(text, 11, color, true))
	return status


func _chip(text: String, color: Color) -> PanelContainer:
	var chip := _panel(Color(0.98, 0.91, 0.70, 0.74), Color(color.r, color.g, color.b, 0.40), 999)
	var margin := MarginContainer.new()
	_margin_each(margin, 7, 2, 7, 2)
	chip.add_child(margin)
	margin.add_child(_nowrap_label(text, 10, color, true))
	return chip


func _room_meta(text: String, color: Color) -> Label:
	var label := _nowrap_label(text, 12, color, true)
	label.custom_minimum_size = Vector2(0, 18)
	return label


func _stat_badge(mark: String, value: String, color: Color, min_width: float = 0.0) -> PanelContainer:
	var badge := _panel(Color(0.98, 0.90, 0.68, 0.78), Color(color.r, color.g, color.b, 0.36), 7)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var width := min_width
	if width <= 0.0:
		width = max(58.0, 34.0 + float(mark.length() + value.length()) * 8.0)
	badge.custom_minimum_size = Vector2(width, 28)
	var margin := MarginContainer.new()
	_margin_each(margin, 7, 2, 7, 2)
	badge.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)
	var icon := _nowrap_label(mark, 11, color, true, HORIZONTAL_ALIGNMENT_CENTER)
	icon.custom_minimum_size = Vector2(16, 0)
	row.add_child(icon)
	var text := _nowrap_label(value, 11, INK, true)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	return badge


func _fresh_badge(mark: String, value: String, color: Color, min_width: float = 0.0) -> PanelContainer:
	var badge := _panel(Color(color.r, color.g, color.b, 0.16), Color(color.r, color.g, color.b, 0.34), 999)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var width := min_width
	if width <= 0.0:
		width = max(58.0, 34.0 + float(mark.length() + value.length()) * 8.0)
	badge.custom_minimum_size = Vector2(width, 27)
	var margin := MarginContainer.new()
	_margin_each(margin, 7, 2, 7, 2)
	badge.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)
	var icon := _nowrap_label(mark, 11, color.darkened(0.18), true, HORIZONTAL_ALIGNMENT_CENTER)
	icon.custom_minimum_size = Vector2(16, 0)
	row.add_child(icon)
	var text := _nowrap_label(value, 11, FRESH_TEXT, true)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	return badge


func _shimmer_title(text: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(190, 50)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.clip_contents = false

	var glow := Label.new()
	glow.text = text
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -1
	glow.offset_top = 1
	glow.autowrap_mode = TextServer.AUTOWRAP_OFF
	glow.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	glow.clip_text = true
	glow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glow.add_theme_font_size_override("font_size", _ui_font_size(27))
	glow.add_theme_color_override("font_color", Color(1.0, 0.66, 0.20, 0.46))
	glow.add_theme_color_override("font_shadow_color", Color(0.42, 0.88, 0.76, 0.18))
	glow.add_theme_constant_override("shadow_offset_x", 0)
	glow.add_theme_constant_override("shadow_offset_y", 0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)

	var title := Label.new()
	title.text = text
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _ui_font_size(27))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.60))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.material = _shimmer_text_material()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(title)

	return holder


func _shimmer_text_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.62, 0.33, 0.08, 1.0);
uniform vec4 edge_color : source_color = vec4(0.26, 0.14, 0.05, 1.0);
uniform vec4 shine_color : source_color = vec4(0.98, 0.68, 0.22, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float sweep = fract((FRAGCOORD.x + FRAGCOORD.y * 0.55) / 230.0 - TIME * 0.58);
	float band = smoothstep(0.18, 0.0, abs(sweep - 0.50));
	float rim = smoothstep(0.50, 0.0, UV.y) * 0.22;
	vec3 color = mix(edge_color.rgb, base_color.rgb, 0.72 + rim);
	color = mix(color, shine_color.rgb, band);
	COLOR = vec4(color, tex.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _small_button(text: String, primary: bool, callback: Callable, danger: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(86, 36)
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, primary, danger)
	button.pressed.connect(func():
		_play_click()
		callback.call()
	)
	return button


func _fresh_button(text: String, primary: bool, callback: Callable, danger: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(80, 36)
	button.focus_mode = Control.FOCUS_NONE
	_style_fresh_button(button, primary, danger)
	button.pressed.connect(func():
		_play_click()
		callback.call()
	)
	return button


func _icon_button(text: String, callback: Callable) -> Button:
	var button := _small_button(text, false, callback)
	button.custom_minimum_size = Vector2(54, 34)
	return button


func _toolbar_button(text: String, tooltip: String, callback: Callable, primary: bool = false, fresh: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(44, 38)
	button.focus_mode = Control.FOCUS_NONE
	if fresh:
		_style_fresh_button(button, primary)
	else:
		_style_button(button, primary)
	_style_toolbar_icon_button(button, primary, fresh)
	button.pressed.connect(func():
		_play_click()
		callback.call()
	)
	return button


func _toolbar_texture_button(icon_path: String, tooltip: String, callback: Callable, fresh: bool = true, primary: bool = false) -> Button:
	var button := Button.new()
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(62, 54)
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.icon = _texture(icon_path)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 44)
	button.add_theme_constant_override("icon_separation", 0)
	if fresh:
		_style_fresh_button(button, primary)
	else:
		_style_button(button, primary)
	_style_toolbar_icon_button(button, primary, fresh)
	button.pressed.connect(func():
		_play_click()
		callback.call()
	)
	return button


func _mini_icon_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(48, 32)
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, false)
	button.pressed.connect(func():
		_play_click()
		callback.call()
	)
	return button


func _close_icon_button(callback: Callable, fresh: bool = false) -> Button:
	var button := Button.new()
	button.tooltip_text = "关闭"
	button.custom_minimum_size = Vector2(32, 32)
	button.focus_mode = Control.FOCUS_NONE
	button.icon = _texture(ACTION_CLOSE)
	button.expand_icon = true
	_style_close_button(button, fresh)
	button.pressed.connect(func():
		_play_click()
		callback.call()
	)
	return button


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer


func _divider() -> HSeparator:
	var div := HSeparator.new()
	div.add_theme_color_override("separator", Color(1, 0.78, 0.34, 0.20))
	return div


func _panel(bg: Color = PANEL, border: Color = LINE, radius: int = 8) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(bg, border, radius, 1))
	return panel


func _panel_body(panel: PanelContainer, padding: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	_margin(margin, padding)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(body)
	return body


func _ui_font_size(size: int) -> int:
	return max(8, size + UI_FONT_BOOST)


func _label(text: String, size: int = 13, color: Color = INK, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", _ui_font_size(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", -1)
	if bold and not _is_fresh_text_color(color):
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.62))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _is_fresh_text_color(color: Color) -> bool:
	return color == INK or color == MUTED or color == DIM or color == GOLD or color == TEAL or color == RED or color == GREEN or color == FRESH_TEXT or color == FRESH_MUTED or color == FRESH_SKY or color == FRESH_MINT or color == FRESH_CORAL or color == FRESH_LILAC or color == FRESH_GOLD or color == BOOK_TEXT or color == BOOK_MUTED or color == BOOK_GOLD or color == BOOK_GREEN or color == BOOK_RED


func _nowrap_label(text: String, size: int = 13, color: Color = INK, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := _label(text, size, color, bold, align)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	return label


func _style_input(control: Control) -> void:
	control.add_theme_stylebox_override("normal", _style_box(Color(0.99, 0.93, 0.76, 0.88), Color(0.56, 0.36, 0.14, 0.34), 7, 1))
	control.add_theme_stylebox_override("focus", _style_box(Color(1.0, 0.96, 0.82, 0.96), Color(0.76, 0.47, 0.13, 0.70), 7, 1))
	control.add_theme_color_override("font_color", INK)
	control.add_theme_color_override("font_focus_color", INK)
	control.add_theme_color_override("font_selected_color", Color(1.0, 0.98, 0.90))
	control.add_theme_color_override("font_uneditable_color", Color(0.34, 0.25, 0.15))
	control.add_theme_color_override("font_placeholder_color", DIM)
	control.add_theme_color_override("selection_color", Color(0.54, 0.31, 0.09, 0.82))
	control.add_theme_color_override("caret_color", GOLD)
	control.add_theme_font_size_override("font_size", _ui_font_size(12))


func _style_fresh_input(control: Control) -> void:
	control.add_theme_stylebox_override("normal", _style_box(Color(0.98, 0.92, 0.76, 0.92), Color(0.48, 0.32, 0.14, 0.34), 7, 1))
	control.add_theme_stylebox_override("focus", _style_box(Color(1.0, 0.96, 0.82, 0.98), FRESH_GOLD, 7, 1))
	control.add_theme_color_override("font_color", FRESH_TEXT)
	control.add_theme_color_override("font_focus_color", FRESH_TEXT)
	control.add_theme_color_override("font_selected_color", Color(1.0, 0.98, 0.90))
	control.add_theme_color_override("font_uneditable_color", Color(0.38, 0.42, 0.36))
	control.add_theme_color_override("font_placeholder_color", FRESH_MUTED)
	control.add_theme_color_override("selection_color", Color(0.38, 0.34, 0.15, 0.82))
	control.add_theme_color_override("caret_color", FRESH_GOLD)
	control.add_theme_font_size_override("font_size", _ui_font_size(12))


func _style_button(button: Button, primary: bool, danger: bool = false) -> void:
	var bg := Color(0.94, 0.82, 0.56, 0.70)
	var border := Color(0.54, 0.34, 0.12, 0.38)
	var font := INK
	if primary:
		bg = Color(0.83, 0.53, 0.17, 0.94)
		border = Color(0.47, 0.27, 0.08, 0.72)
		font = Color(0.13, 0.075, 0.026)
	if danger:
		bg = Color(0.62, 0.13, 0.10, 0.94)
		border = Color(1, 0.38, 0.30, 0.62)
		font = INK
	button.add_theme_stylebox_override("normal", _style_box(bg, border, 8, 1))
	button.add_theme_stylebox_override("hover", _style_box(bg.lightened(0.08), border.lightened(0.10), 8, 1))
	button.add_theme_stylebox_override("pressed", _style_box(bg.darkened(0.14), border, 8, 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", font)
	button.add_theme_color_override("font_pressed_color", font)
	button.add_theme_font_size_override("font_size", _ui_font_size(12))


func _style_fresh_button(button: Button, primary: bool, danger: bool = false) -> void:
	var bg := Color(0.92, 0.82, 0.55, 0.34)
	var border := Color(0.42, 0.28, 0.12, 0.32)
	var font := FRESH_TEXT
	if primary:
		bg = Color(0.78, 0.50, 0.17, 0.92)
		border = Color(0.44, 0.25, 0.08, 0.66)
		font = Color(0.12, 0.070, 0.026)
	if danger:
		bg = Color(0.80, 0.30, 0.22, 0.90)
		border = FRESH_CORAL
		font = Color(1.0, 0.88, 0.74)
	button.add_theme_stylebox_override("normal", _style_box(bg, border, 8, 1))
	button.add_theme_stylebox_override("hover", _style_box(bg.lightened(0.05), border.lightened(0.08), 8, 1))
	button.add_theme_stylebox_override("pressed", _style_box(bg.darkened(0.08), border, 8, 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", font)
	button.add_theme_color_override("font_pressed_color", font)
	button.add_theme_font_size_override("font_size", _ui_font_size(12))


func _style_toolbar_icon_button(button: Button, primary: bool, fresh: bool = true) -> void:
	if not fresh:
		return
	var bg := Color(0.91, 0.76, 0.43, 0.86)
	var border := Color(0.40, 0.23, 0.07, 0.58)
	var icon := Color(0.36, 0.20, 0.06)
	if primary:
		bg = Color(0.80, 0.43, 0.12, 0.96)
		border = Color(0.35, 0.18, 0.045, 0.76)
		icon = Color(0.16, 0.075, 0.025)
	button.add_theme_stylebox_override("normal", _style_box(bg, border, 8, 2))
	button.add_theme_stylebox_override("hover", _style_box(bg.lightened(0.08), border.lightened(0.10), 8, 2))
	button.add_theme_stylebox_override("pressed", _style_box(bg.darkened(0.10), border, 8, 2))
	button.add_theme_color_override("icon_normal_color", icon)
	button.add_theme_color_override("icon_hover_color", icon.lightened(0.10))
	button.add_theme_color_override("icon_pressed_color", icon.darkened(0.08))
	button.add_theme_color_override("icon_focus_color", icon)
	button.add_theme_color_override("font_color", icon)
	button.add_theme_color_override("font_hover_color", icon)
	button.add_theme_color_override("font_pressed_color", icon)


func _style_close_button(button: Button, fresh: bool = false) -> void:
	var bg := Color(0.80, 0.30, 0.22, 0.88)
	var border := Color(0.98, 0.70, 0.42, 0.58)
	if fresh:
		bg = Color(0.78, 0.30, 0.22, 0.88)
		border = Color(0.98, 0.70, 0.42, 0.58)
	button.add_theme_stylebox_override("normal", _style_box(bg, border, 999, 1))
	button.add_theme_stylebox_override("hover", _style_box(bg.lightened(0.08), border.lightened(0.08), 999, 1))
	button.add_theme_stylebox_override("pressed", _style_box(bg.darkened(0.10), border, 999, 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _style_transparent_button(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", _style_box(Color(1.0, 0.90, 0.62, 0.18), Color(0.64, 0.40, 0.14, 0.24), 8, 1))
	button.add_theme_stylebox_override("pressed", _style_box(Color(0.86, 0.64, 0.32, 0.18), Color(0.64, 0.40, 0.14, 0.34), 8, 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _style_box(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color(0.18, 0.10, 0.03, 0.18)
	box.shadow_size = 5
	box.shadow_offset = Vector2(0, 1)
	return box


func _set_backdrop(path: String, tint: Color) -> void:
	_bg.texture = _texture(path)
	_tint.color = tint


func _texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	if ResourceLoader.exists(path):
		var loaded := ResourceLoader.load(path)
		if loaded is Texture2D:
			_texture_cache[path] = loaded
			return loaded
	var image := Image.new()
	if image.load(path) == OK:
		var texture := ImageTexture.create_from_image(image)
		_texture_cache[path] = texture
		return texture
	return null


func _margin(container: MarginContainer, value: int) -> void:
	_margin_each(container, value, value, value, value)


func _margin_each(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)
