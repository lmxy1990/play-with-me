extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.46, 0.31, 0.11, 0.055))
	draw_set_transform(Vector2(size.x * 0.52, size.y * 0.48), -0.08, Vector2(2.3, 0.86))
	draw_circle(Vector2.ZERO, maxf(size.x, size.y) * 0.22, Color(1.0, 0.72, 0.30, 0.045))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(0, 0, size.x, 18), Color(0.40, 0.24, 0.06, 0.035))
	draw_rect(Rect2(0, size.y - 18, size.x, 18), Color(0.40, 0.24, 0.06, 0.035))
