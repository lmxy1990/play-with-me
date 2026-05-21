extends Control

var mood := "day"


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.30
	var table_color := Color(0.63, 0.42, 0.20, 0.42)
	var rim := Color(0.94, 0.68, 0.28, 0.36)
	var inner := Color(1.0, 0.88, 0.54, 0.075)
	if mood == "night":
		table_color = Color(0.12, 0.16, 0.26, 0.50)
		rim = Color(0.52, 0.72, 1.0, 0.32)
		inner = Color(0.54, 0.82, 1.0, 0.055)
	draw_circle(c + Vector2(0, radius * 0.06), radius * 1.24, Color(0.18, 0.10, 0.03, 0.14))
	draw_circle(c, radius * 1.08, Color(0.70, 0.50, 0.26, 0.16))
	draw_circle(c, radius, table_color)
	draw_arc(c, radius, 0, TAU, 192, rim, 4.0, true)
	draw_arc(c, radius * 0.72, 0, TAU, 192, inner, 2.0, true)
	draw_arc(c, radius * 0.42, 0, TAU, 160, inner, 1.5, true)
	for i in range(16):
		var angle: float = TAU * float(i) / 16.0
		var a: Vector2 = c + Vector2(cos(angle), sin(angle)) * radius * 0.22
		var b: Vector2 = c + Vector2(cos(angle), sin(angle)) * radius * 0.92
		draw_line(a, b, Color(1, 0.84, 0.48, 0.038), 1.0, true)
