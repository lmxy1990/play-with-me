extends Control

var kind := ""
var progress := 1.0


func play(next_kind: String) -> void:
	kind = next_kind
	progress = 0.0
	queue_redraw()


func tick(delta: float) -> void:
	if progress < 1.0:
		progress = min(1.0, progress + delta * 1.8)
		queue_redraw()


func _draw() -> void:
	if progress >= 1.0:
		return
	var c: Vector2 = size * 0.5
	var alpha: float = 1.0 - progress
	var radius: float = min(size.x, size.y) * (0.08 + progress * 0.42)
	if kind == "death":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.02, 0.02, 0.20 * alpha), true)
		draw_circle(c, radius, Color(0.95, 0.12, 0.10, 0.18 * alpha))
		draw_arc(c, radius, 0, TAU, 96, Color(0.95, 0.12, 0.10, alpha), 5.0, true)
	elif kind == "phase":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.12, 0.25, 0.24 * alpha), true)
		draw_circle(Vector2(size.x * 0.82, size.y * 0.16), radius * 0.8, Color(0.82, 0.92, 1.0, 0.24 * alpha))
	elif kind == "inspect":
		var inspect_center := Vector2(size.x * 0.5, size.y * 0.5)
		draw_arc(inspect_center, radius * 0.62, -0.35, TAU - 0.35, 128, Color(0.25, 0.78, 0.69, alpha), 5.0, true)
		draw_line(inspect_center + Vector2(radius * 0.32, radius * 0.32), inspect_center + Vector2(radius * 0.62, radius * 0.62), Color(0.25, 0.78, 0.69, alpha), 6.0, true)
	elif kind == "vote":
		draw_rect(Rect2(c - Vector2(radius * 0.36, radius * 0.28), Vector2(radius * 0.72, radius * 0.56)), Color(0.95, 0.68, 0.28, 0.10 * alpha), false, 4.0)
		draw_line(c + Vector2(-radius * 0.22, radius * 0.02), c + Vector2(-radius * 0.05, radius * 0.20), Color(0.42, 0.78, 0.42, alpha), 6.0, true)
		draw_line(c + Vector2(-radius * 0.05, radius * 0.20), c + Vector2(radius * 0.28, -radius * 0.22), Color(0.42, 0.78, 0.42, alpha), 6.0, true)
	elif kind == "kill":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.02, 0.02, 0.12 * alpha), true)
		draw_line(c + Vector2(-radius * 0.40, radius * 0.34), c + Vector2(radius * 0.42, -radius * 0.42), Color(0.88, 0.16, 0.13, alpha), 8.0, true)
	elif kind == "guard":
		draw_arc(c, radius * 0.55, 0.2, TAU - 0.2, 128, Color(0.42, 0.78, 0.42, alpha), 7.0, true)
		draw_circle(c, radius * 0.48, Color(0.42, 0.78, 0.42, 0.09 * alpha))
	elif kind == "potion":
		for i in range(7):
			var angle: float = TAU * float(i) / 7.0 + progress * TAU
			var bubble_center := c + Vector2(cos(angle), sin(angle)) * radius * 0.34
			draw_circle(bubble_center, 4.0 + float(i % 3), Color(0.80, 0.48, 0.94, alpha))
	else:
		draw_circle(c, radius, Color(0.95, 0.68, 0.28, 0.16 * alpha))
		draw_arc(c, radius, 0, TAU, 96, Color(0.95, 0.68, 0.28, alpha), 4.0, true)
