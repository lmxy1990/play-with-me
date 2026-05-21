extends Control

var title := ""
var open_amount := 0.0:
	set(value):
		open_amount = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rect := Rect2(Vector2(34, 24), size - Vector2(68, 48))
	if rect.size.x <= 10.0 or rect.size.y <= 10.0:
		return
	_draw_shadow(rect)
	_draw_metal_frame(rect)
	_draw_plate(rect, true)
	_draw_plate(rect, false)
	_draw_center_lock(rect)
	_draw_energy_lines(rect)


func _draw_shadow(rect: Rect2) -> void:
	draw_set_transform(rect.get_center() + Vector2(18, 32), -0.02, Vector2(2.15, 0.34))
	draw_circle(Vector2.ZERO, rect.size.x * 0.27, Color(0, 0, 0, 0.36))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_metal_frame(rect: Rect2) -> void:
	var a := smoothstep(0.0, 0.36, open_amount)
	var compact := 1.0 - a
	var gap := lerpf(-rect.size.x * 0.22, 22.0, a)
	var half_w := (rect.size.x - gap) * 0.5
	var left := Rect2(rect.position.x + compact * rect.size.x * 0.25, rect.position.y, half_w, rect.size.y)
	var right := Rect2(rect.position.x + rect.size.x - half_w - compact * rect.size.x * 0.25, rect.position.y, half_w, rect.size.y)
	_draw_rounded_rect(left.grow(10), Color(0.18, 0.10, 0.030, 0.94), Color(0.88, 0.55, 0.16, 0.50), 18.0, 2.0)
	_draw_rounded_rect(right.grow(10), Color(0.18, 0.10, 0.030, 0.94), Color(0.88, 0.55, 0.16, 0.50), 18.0, 2.0)


func _draw_plate(rect: Rect2, left_side: bool) -> void:
	var a := smoothstep(0.0, 0.36, open_amount)
	var compact := 1.0 - a
	var gap := lerpf(-rect.size.x * 0.22, 22.0, a)
	var half_w := (rect.size.x - gap) * 0.5
	var x := rect.position.x if left_side else rect.position.x + rect.size.x - half_w
	if left_side:
		x += compact * rect.size.x * 0.25
	else:
		x -= compact * rect.size.x * 0.25
	var plate := Rect2(x, rect.position.y, half_w, rect.size.y)
	var base := Color(0.78, 0.50, 0.14, 0.96)
	var bright := Color(1.0, 0.78, 0.28, 0.96)
	var dark := Color(0.34, 0.18, 0.045, 0.96)
	_draw_rounded_rect(plate, base, Color(1.0, 0.84, 0.36, 0.74), 16.0, 2.4)
	for i in range(8):
		var t := float(i) / 7.0
		var y := plate.position.y + plate.size.y * t
		var color := bright.lerp(dark, t)
		color.a = 0.18
		draw_line(Vector2(plate.position.x + 18, y), Vector2(plate.position.x + plate.size.x - 18, y + sin(t * PI) * 8.0), color, 3.0)
	_draw_inner_panel(plate, left_side)
	_draw_corner_plate(plate.position + Vector2(26, 24), Vector2(1, 1))
	_draw_corner_plate(plate.position + Vector2(plate.size.x - 26, 24), Vector2(-1, 1))
	_draw_corner_plate(plate.position + Vector2(26, plate.size.y - 24), Vector2(1, -1))
	_draw_corner_plate(plate.position + Vector2(plate.size.x - 26, plate.size.y - 24), Vector2(-1, -1))


func _draw_inner_panel(rect: Rect2, left_side: bool) -> void:
	var inner := rect.grow(-38)
	_draw_rounded_rect(inner, Color(0.88, 0.62, 0.22, 0.42), Color(0.42, 0.23, 0.07, 0.38), 12.0, 1.5)
	var shine_x := inner.position.x + inner.size.x * (0.28 if left_side else 0.72)
	draw_line(Vector2(shine_x, inner.position.y + 12), Vector2(shine_x - 34, inner.position.y + inner.size.y - 12), Color(1.0, 0.92, 0.48, 0.18), 8.0)


func _draw_center_lock(rect: Rect2) -> void:
	var a := smoothstep(0.0, 0.28, open_amount)
	var center := rect.get_center()
	var h := rect.size.y - 58
	draw_line(Vector2(center.x, center.y - h * 0.5), Vector2(center.x, center.y + h * 0.5), Color(0.15, 0.075, 0.022, 0.68), 8.0)
	draw_line(Vector2(center.x, center.y - h * 0.5), Vector2(center.x, center.y + h * 0.5), Color(1.0, 0.76, 0.25, 0.34), 2.0)
	var lock_alpha := 1.0 - a
	if lock_alpha > 0.02:
		draw_circle(center, 42.0, Color(0.26, 0.12, 0.035, 0.86 * lock_alpha))
		draw_arc(center, 44.0, 0.0, TAU, 48, Color(1.0, 0.78, 0.30, 0.80 * lock_alpha), 3.0)
		draw_circle(center, 14.0, Color(1.0, 0.78, 0.30, 0.72 * lock_alpha))


func _draw_energy_lines(rect: Rect2) -> void:
	var alpha := smoothstep(0.24, 0.70, open_amount)
	if alpha <= 0.01:
		return
	var y1 := rect.position.y + 34
	var y2 := rect.position.y + rect.size.y - 34
	draw_line(Vector2(rect.position.x + 72, y1), Vector2(rect.position.x + rect.size.x - 72, y1), Color(1.0, 0.90, 0.45, 0.22 * alpha), 2.0)
	draw_line(Vector2(rect.position.x + 72, y2), Vector2(rect.position.x + rect.size.x - 72, y2), Color(1.0, 0.90, 0.45, 0.18 * alpha), 2.0)


func _draw_corner_plate(origin: Vector2, dir: Vector2) -> void:
	var gold := Color(1.0, 0.84, 0.36, 0.74)
	draw_line(origin, origin + Vector2(36 * dir.x, 0), gold, 4.0)
	draw_line(origin, origin + Vector2(0, 36 * dir.y), gold, 4.0)
	draw_circle(origin + Vector2(7 * dir.x, 7 * dir.y), 3.2, gold)


func _draw_rounded_rect(rect: Rect2, fill: Color, border: Color, radius: float, border_width: float) -> void:
	draw_rect(rect, fill)
	draw_rect(rect.grow(-radius * 0.35), Color(fill.r + 0.05, fill.g + 0.04, fill.b + 0.02, fill.a * 0.34))
	draw_rect(rect, border, false, border_width)
