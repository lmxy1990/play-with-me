extends Control

signal seat_pressed(index: int)
signal name_edit_pressed(index: int)
signal voice_toggle_pressed(index: int)

const CircularTextureMaskScript := preload("res://scripts/ui/common/circular_texture_mask.gd")

enum SeatMotion { IDLE, THINKING, SPEAKING, DEAD }

const INK := Color(0.97, 0.91, 0.78)
const MUTED := Color(0.70, 0.76, 0.72)
const DIM := Color(0.41, 0.50, 0.48)
const GOLD := Color(0.96, 0.70, 0.32)
const GREEN := Color(0.51, 0.78, 0.44)
const UI_FONT_BOOST := 2
const INFO_PANEL_BG := Color(0.010, 0.016, 0.020, 0.72)
const INFO_PANEL_BORDER := Color(0.96, 0.70, 0.32, 0.24)
const AVATAR_BADGE_SIZE := 22.0

var index := 0
var data := {}
var texture_provider: Callable
var dead_avatar_path := ""
var edit_icon_path := ""
var voice_icon_path := ""

var _time := 0.0
var _death_progress := 0.0
var _target_flash := 1.0
var _action_kind := "action"
var _avatar_texture: Texture2D
var _avatar_mask = CircularTextureMaskScript.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_children()
		queue_redraw()


func tick(delta: float) -> void:
	_time += delta
	if int(data.get("motion", SeatMotion.IDLE)) == SeatMotion.DEAD:
		_death_progress = min(1.0, _death_progress + delta * 1.6)
	if _target_flash < 1.0:
		_target_flash = min(1.0, _target_flash + delta * 2.2)
	queue_redraw()


func start_motion(motion: int) -> void:
	data["motion"] = motion
	_death_progress = 0.0
	_rebuild()
	queue_redraw()


func play_action_effect(kind: String) -> void:
	_action_kind = kind
	_target_flash = 0.0
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if OS.is_debug_build():
			print("[WerewolfSeatClick][debug] card_pressed index=%d owner=%s name=%s pos=%s" % [index, String(data.get("owner", "")), _display_name(), _debug_input_position(event)])
		accept_event()
		seat_pressed.emit(index)
	elif event is InputEventScreenTouch and event.pressed:
		if OS.is_debug_build():
			print("[WerewolfSeatClick][debug] card_pressed index=%d owner=%s name=%s pos=%s" % [index, String(data.get("owner", "")), _display_name(), _debug_input_position(event)])
		accept_event()
		seat_pressed.emit(index)


func _on_edit_pressed() -> void:
	name_edit_pressed.emit(index)


func _on_voice_toggle_pressed() -> void:
	if OS.is_debug_build():
		print("[WerewolfSeatClick][debug] voice_toggle_pressed index=%d owner=%s name=%s" % [index, String(data.get("owner", "")), _display_name()])
	voice_toggle_pressed.emit(index)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var avatar_path: String = String(data.get("avatar", ""))
	var alive := bool(data.get("alive", true))
	var owner := String(data.get("owner", ""))
	var occupied := owner != ""
	var editable := owner == "self"
	_avatar_texture = null
	if not alive and dead_avatar_path != "" and texture_provider.is_valid():
		_avatar_texture = texture_provider.call(dead_avatar_path)
	elif avatar_path != "" and texture_provider.is_valid():
		_avatar_texture = texture_provider.call(avatar_path)

	if avatar_path == "" and alive:
		var num := _seat_label(str(index + 1), 20, DIM, true)
		num.name = "AvatarNumber"
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(num)

	var badge := _seat_label("%d号" % [index + 1], 9, INK, true)
	badge.name = "SeatNumberBadge"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)

	var info_panel := Panel.new()
	info_panel.name = "SeatInfoPanel"
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.add_theme_stylebox_override("panel", _info_panel_style())
	add_child(info_panel)

	var title_text := "%d号 · %s" % [index + 1, _visible_role_title()]
	var title := _seat_label(title_text, 11, INK if occupied else MUTED, true)
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var name_text := "点击落座 / AI"
	var role_color := MUTED
	if occupied:
		name_text = _display_name()
		role_color = Color(0.92, 0.20, 0.16) if not alive else GREEN if bool(data.get("ready", false)) else GOLD
	var name_label := _seat_label(name_text, 10, role_color, true)
	name_label.name = "NameLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(name_label)

	if occupied and bool(data.get("show_vote_count", false)):
		var vote_count := maxi(0, int(data.get("vote_count", 0)))
		var vote_badge := _seat_label("%d票" % vote_count, 9, GOLD, true)
		vote_badge.name = "VoteCountBadge"
		vote_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vote_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vote_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(vote_badge)

	if editable and edit_icon_path != "" and texture_provider.is_valid():
		var edit := TextureButton.new()
		edit.name = "EditButton"
		edit.texture_normal = texture_provider.call(edit_icon_path)
		edit.texture_hover = edit.texture_normal
		edit.texture_pressed = edit.texture_normal
		edit.ignore_texture_size = true
		edit.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		edit.custom_minimum_size = Vector2(18, 18)
		edit.focus_mode = Control.FOCUS_NONE
		edit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		edit.pressed.connect(_on_edit_pressed)
		add_child(edit)
	if occupied and voice_icon_path != "" and texture_provider.is_valid():
		var voice := TextureButton.new()
		var enabled := bool(data.get("tts_enabled", true))
		voice.name = "SeatCardVoiceToggleButton"
		voice.texture_normal = texture_provider.call(voice_icon_path)
		voice.texture_hover = voice.texture_normal
		voice.texture_pressed = voice.texture_normal
		voice.ignore_texture_size = true
		voice.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		voice.custom_minimum_size = Vector2(22, 22)
		voice.focus_mode = Control.FOCUS_NONE
		voice.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		voice.modulate = GREEN if enabled else Color(0.70, 0.76, 0.72, 0.46)
		voice.tooltip_text = "关闭头像旁白" if enabled else "开启头像旁白"
		voice.pressed.connect(_on_voice_toggle_pressed)
		add_child(voice)
	_add_avatar_badges()
	_layout_children()


func _add_avatar_badges() -> void:
	var badges_value = data.get("avatar_badges", [])
	if not (badges_value is Array) or not texture_provider.is_valid():
		return
	var badge_index := 0
	for badge_value in badges_value:
		if not (badge_value is Dictionary):
			continue
		var badge_data: Dictionary = badge_value
		var icon_path := String(badge_data.get("icon", "")).strip_edges()
		if icon_path == "":
			continue
		var badge := TextureRect.new()
		var badge_id := String(badge_data.get("id", "badge")).strip_edges()
		badge.name = _avatar_badge_node_name(badge_id, badge_index)
		badge.texture = texture_provider.call(icon_path)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.custom_minimum_size = Vector2(AVATAR_BADGE_SIZE, AVATAR_BADGE_SIZE)
		badge.tooltip_text = String(badge_data.get("tooltip", "")).strip_edges()
		badge.set_meta("avatar_badge", true)
		add_child(badge)
		badge_index += 1


func _layout_children() -> void:
	var avatar_size := _avatar_size()
	var avatar_center := _avatar_center()
	var voice_button := get_node_or_null("SeatCardVoiceToggleButton") as TextureButton
	var num := get_node_or_null("AvatarNumber") as Label
	if num != null:
		num.position = avatar_center - Vector2(avatar_size, avatar_size) * 0.5
		num.size = Vector2(avatar_size, avatar_size)
	var info_height := 43.0
	var info_top := minf(avatar_center.y + avatar_size * 0.5 + 3.0, maxf(0.0, size.y - info_height))
	var info_panel := get_node_or_null("SeatInfoPanel") as Panel
	if info_panel != null:
		info_panel.position = Vector2(0.0, info_top)
		info_panel.size = Vector2(size.x, info_height)
	var title := get_node_or_null("Title") as Label
	if title != null:
		title.position = Vector2(5.0, info_top + 2.0)
		title.size = Vector2(maxf(0.0, size.x - 10.0), 20.0)
	var name_label := get_node_or_null("NameLabel") as Label
	if name_label != null:
		var edit := get_node_or_null("EditButton") as TextureButton
		var vote_badge := get_node_or_null("VoteCountBadge") as Label
		var vote_badge_width := 34.0 if vote_badge != null else 0.0
		var right_x := size.x - 5.0
		if voice_button != null:
			right_x -= 22.0
			voice_button.position = Vector2(right_x, info_top + 20.0)
			voice_button.size = Vector2(22, 22)
			right_x -= 4.0
		if edit != null:
			right_x -= 20.0
			edit.position = Vector2(right_x, info_top + 20.0)
			edit.size = Vector2(20, 20)
			right_x -= 4.0
		if vote_badge != null:
			right_x -= vote_badge_width
			vote_badge.position = Vector2(right_x, info_top + 21.0)
			vote_badge.size = Vector2(vote_badge_width, 19.0)
			right_x -= 4.0
		var label_width := maxf(0.0, right_x - 5.0)
		name_label.position = Vector2(5.0, info_top + 21.0)
		name_label.size = Vector2(label_width, 19.0)
	var badge := get_node_or_null("SeatNumberBadge") as Label
	if badge != null:
		var badge_size := Vector2(32.0, 18.0)
		badge.position = avatar_center + Vector2(-avatar_size * 0.48, avatar_size * 0.20)
		badge.size = badge_size
	_layout_avatar_badges(avatar_center, avatar_size)


func _draw() -> void:
	var motion: int = int(data.get("motion", SeatMotion.IDLE))
	var avatar_size := _avatar_size()
	var radius := avatar_size * 0.5
	var c := _avatar_center()
	var alive := bool(data.get("alive", true))
	var occupied := String(data.get("owner", "")) != ""
	var ring := Color(0.95, 0.72, 0.34, 0.54)
	if not occupied:
		ring = Color(0.70, 0.76, 0.72, 0.30)
	elif motion == SeatMotion.THINKING:
		ring = Color(0.38, 0.86, 0.78, 0.76)
	elif motion == SeatMotion.SPEAKING:
		ring = Color(0.96, 0.70, 0.32, 0.86)
	elif not alive:
		ring = Color(0.42, 0.43, 0.42, 0.74)

	draw_circle(c + Vector2(0, 4), radius + 6.0, Color(0, 0, 0, 0.32))
	draw_circle(c, radius + 5.0, Color(0.010, 0.016, 0.020, 0.96))
	if _avatar_texture != null:
		var rect := Rect2(c - Vector2(avatar_size, avatar_size) * 0.5, Vector2(avatar_size, avatar_size))
		var masked := _avatar_mask.masked(_avatar_texture, maxi(1, int(round(avatar_size))))
		if masked != null:
			draw_texture_rect(masked, rect, false)
	else:
		draw_circle(c, radius - 3.0, Color(0.028, 0.044, 0.044, 0.95))
	draw_arc(c, radius + 4.0, 0, TAU, 96, Color(0, 0, 0, 0.36), 5.0, true)
	draw_arc(c, radius + 4.0, 0, TAU, 96, ring, 3.0, true)
	var badge := get_node_or_null("SeatNumberBadge") as Label
	if badge != null:
		var badge_rect := Rect2(badge.position, badge.size)
		draw_rect(badge_rect.grow(1.0), Color(0.010, 0.016, 0.020, 0.84), false, 1.0)
		draw_rect(badge_rect, Color(0.010, 0.016, 0.020, 0.80), true)
		draw_rect(badge_rect, Color(0.96, 0.70, 0.32, 0.48), false, 1.0)
	var vote_badge := get_node_or_null("VoteCountBadge") as Label
	if vote_badge != null:
		var vote_rect := Rect2(vote_badge.position, vote_badge.size)
		draw_rect(vote_rect.grow(1.0), Color(0.010, 0.016, 0.020, 0.88), false, 1.0)
		draw_rect(vote_rect, Color(0.010, 0.016, 0.020, 0.82), true)
		draw_rect(vote_rect, Color(0.96, 0.70, 0.32, 0.54), false, 1.0)
	var voice := get_node_or_null("SeatCardVoiceToggleButton") as TextureButton
	if voice != null:
		var enabled := bool(data.get("tts_enabled", true))
		var vc := voice.position + voice.size * 0.5
		var voice_radius := minf(voice.size.x, voice.size.y) * 0.50
		draw_circle(vc, voice_radius, Color(0.010, 0.016, 0.020, 0.88))
		draw_arc(vc, maxf(1.0, voice_radius - 1.0), 0, TAU, 36, Color(0.96, 0.70, 0.32, 0.72 if enabled else 0.26), 1.5, true)
		if not enabled:
			draw_line(vc + Vector2(-5.5, 5.5), vc + Vector2(5.5, -5.5), Color(0.92, 0.20, 0.16, 0.92), 2.0, true)
	for badge_value in _avatar_badge_nodes():
		var avatar_badge := badge_value as TextureRect
		if avatar_badge == null:
			continue
		var bc := avatar_badge.position + avatar_badge.size * 0.5
		draw_circle(bc + Vector2(0, 1), AVATAR_BADGE_SIZE * 0.52, Color(0, 0, 0, 0.34))
		draw_circle(bc, AVATAR_BADGE_SIZE * 0.50, Color(0.010, 0.016, 0.020, 0.76))
		draw_arc(bc, AVATAR_BADGE_SIZE * 0.50, 0, TAU, 36, Color(0.97, 0.91, 0.78, 0.46), 1.2, true)

	if motion == SeatMotion.THINKING:
		var pulse: float = (sin(_time * 4.0) + 1.0) * 0.5
		draw_arc(c, radius + 9.0 + pulse * 4.0, 0.2, TAU - 0.2, 96, Color(0.38, 0.86, 0.78, 0.34 + pulse * 0.22), 2.0, true)
		for i in range(3):
			var dot_angle: float = -1.4 + float(i) * 0.32
			var dot_pos := c + Vector2(cos(dot_angle), sin(dot_angle)) * (radius + 13.0 + sin(_time * 5.0 + float(i)) * 2.0)
			draw_circle(dot_pos, 2.3, Color(0.38, 0.86, 0.78, 0.82))
	elif motion == SeatMotion.SPEAKING:
		var speech_progress := clampf(float(data.get("speech_progress", 0.0)), 0.0, 1.0)
		if speech_progress > 0.0:
			draw_arc(c, radius + 4.0, -PI * 0.5, -PI * 0.5 + TAU * speech_progress, 96, GREEN, 5.0, true)
		for i in range(3):
			var wave: float = fmod(_time * 2.8 + float(i) * 0.26, 1.0)
			draw_arc(c, radius + 8.0 + wave * 18.0, -0.75, 0.75, 24, Color(0.96, 0.70, 0.32, (1.0 - wave) * 0.52), 2.0, true)
	elif motion == SeatMotion.DEAD:
		var a: float = 0.16 + _death_progress * 0.22
		draw_circle(c, radius + 8.0, Color(0.42, 0.43, 0.42, a))
		draw_arc(c, radius + 10.0, 0, TAU, 96, Color(0.92, 0.20, 0.16, 0.46 * _death_progress), 2.0, true)

	if _target_flash < 1.0:
		var alpha := 1.0 - _target_flash
		var effect := _action_color(_action_kind)
		if _action_kind == "inspect":
			draw_arc(c, radius + 14.0 + _target_flash * 18.0, -0.55, TAU - 0.55, 96, Color(effect.r, effect.g, effect.b, alpha), 4.0, true)
			draw_line(c + Vector2(radius * 0.35, radius * 0.35), c + Vector2(radius * 0.82, radius * 0.82), Color(effect.r, effect.g, effect.b, alpha), 4.0, true)
		elif _action_kind == "kill":
			draw_line(c + Vector2(-radius * 0.85, radius * 0.65), c + Vector2(radius * 0.78, -radius * 0.78), Color(effect.r, effect.g, effect.b, alpha), 5.0, true)
		elif _action_kind == "guard":
			draw_arc(c, radius + 12.0, 0.25, TAU - 0.25, 96, Color(effect.r, effect.g, effect.b, alpha), 5.0, true)
			draw_circle(c, radius + 8.0, Color(effect.r, effect.g, effect.b, 0.10 * alpha))
		elif _action_kind == "potion":
			for i in range(5):
				var angle: float = TAU * float(i) / 5.0 + _target_flash * TAU
				draw_circle(c + Vector2(cos(angle), sin(angle)) * (radius + 12.0), 3.0 + float(i % 2), Color(effect.r, effect.g, effect.b, alpha))
		else:
			draw_arc(c, radius + 14.0 + _target_flash * 26.0, 0, TAU, 96, Color(effect.r, effect.g, effect.b, alpha), 4.0, true)
			draw_circle(c, radius + 10.0, Color(effect.r, effect.g, effect.b, 0.13 * alpha))


func _avatar_size() -> float:
	return clamp(size.y * 0.54, 54.0, 66.0)


func _avatar_center() -> Vector2:
	return Vector2(size.x * 0.5, _avatar_size() * 0.5 + 4.0)


func _layout_avatar_badges(avatar_center: Vector2, avatar_size: float) -> void:
	var badges := _avatar_badge_nodes()
	for i in range(badges.size()):
		var badge := badges[i] as TextureRect
		if badge == null:
			continue
		var badge_size := maxf(18.0, minf(AVATAR_BADGE_SIZE, avatar_size * 0.36))
		var badge_position := avatar_center + Vector2(avatar_size * 0.29, -avatar_size * 0.55 + float(i) * (badge_size + 2.0))
		badge.position = badge_position
		badge.size = Vector2(badge_size, badge_size)


func _avatar_badge_nodes() -> Array:
	var badges := []
	for child in get_children():
		if child is TextureRect and bool(child.get_meta("avatar_badge", false)):
			badges.append(child)
	return badges


func _avatar_badge_node_name(badge_id: String, badge_index: int) -> String:
	match badge_id:
		"sheriff":
			return "SheriffAvatarBadge"
		"guard":
			return "GuardAvatarBadge"
		"mvp":
			return "MvpAvatarBadge"
		"self":
			return "SelfAvatarBadge"
		_:
			return "AvatarBadge%d" % badge_index


func _avatar_source_rect(texture: Texture2D, dest_size: Vector2) -> Rect2:
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0 or dest_size.x <= 0.0 or dest_size.y <= 0.0:
		return Rect2(Vector2.ZERO, source_size)
	var source_aspect := source_size.x / source_size.y
	var dest_aspect := dest_size.x / dest_size.y
	if source_aspect > dest_aspect:
		var width := source_size.y * dest_aspect
		return Rect2(Vector2((source_size.x - width) * 0.5, 0.0), Vector2(width, source_size.y))
	var height := source_size.x / dest_aspect
	return Rect2(Vector2(0.0, (source_size.y - height) * 0.5), Vector2(source_size.x, height))


func _cover_avatar_corners(rect: Rect2, center: Vector2, radius: float, color: Color) -> void:
	_cover_avatar_corner(rect.position, Vector2(center.x, rect.position.y), center, radius, -PI * 0.5, -PI, color)
	_cover_avatar_corner(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, center.y), center, radius, 0.0, -PI * 0.5, color)
	_cover_avatar_corner(rect.end, Vector2(center.x, rect.end.y), center, radius, PI * 0.5, 0.0, color)
	_cover_avatar_corner(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, center.y), center, radius, PI, PI * 0.5, color)


func _cover_avatar_corner(corner: Vector2, edge_point: Vector2, center: Vector2, radius: float, from_angle: float, to_angle: float, color: Color) -> void:
	var points := PackedVector2Array()
	points.append(corner)
	points.append(edge_point)
	var steps := 12
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := lerpf(from_angle, to_angle, t)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)


func _visible_role() -> String:
	var owner := String(data.get("owner", ""))
	if owner == "":
		return "空位"
	if bool(data.get("role_visible", false)) or owner == "self":
		var role := String(data.get("role", "未知")).strip_edges()
		return "未知" if role == "" else role
	return "未知"


func _visible_role_title() -> String:
	var role := _visible_role()
	if role in ["未知", "空位"]:
		return role
	var title := String(data.get("role_title", data.get("roleTitle", ""))).strip_edges()
	if title == "":
		return role
	return "%s · %s" % [role, title]


func _display_name() -> String:
	var name := String(data.get("name", data.get("displayName", ""))).strip_edges()
	return name if name != "" else "%d号位" % [index + 1]


func _debug_input_position(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		return str((event as InputEventMouseButton).position)
	if event is InputEventScreenTouch:
		return str((event as InputEventScreenTouch).position)
	return "-"


func _info_panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = INFO_PANEL_BG
	box.border_color = INFO_PANEL_BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 5
	box.content_margin_right = 5
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


func _action_color(kind: String) -> Color:
	match kind:
		"inspect":
			return Color(0.38, 0.86, 0.78)
		"vote":
			return Color(0.96, 0.70, 0.32)
		"kill":
			return Color(0.88, 0.18, 0.14)
		"guard":
			return Color(0.42, 0.78, 0.42)
		"potion":
			return Color(0.80, 0.48, 0.94)
		"skip":
			return Color(0.66, 0.69, 0.63)
		_:
			return Color(0.96, 0.70, 0.32)


func _seat_label(text: String, size_px: int, color: Color, bold: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", size_px + UI_FONT_BOOST)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", -2)
	if bold:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.56))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	return label
