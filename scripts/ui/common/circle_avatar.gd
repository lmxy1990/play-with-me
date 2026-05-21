extends Control
class_name CircleAvatar

const CircularTextureMaskScript := preload("res://scripts/ui/common/circular_texture_mask.gd")

var _texture: Texture2D
var _fill_color := Color(0.028, 0.044, 0.044, 0.95)
var _ring_color := Color(0.96, 0.70, 0.32, 0.72)
var _shadow_color := Color(0, 0, 0, 0.26)
var _texture_mask = CircularTextureMaskScript.new()

var texture: Texture2D:
	get:
		return _texture
	set(value):
		_texture = value
		queue_redraw()

var fill_color: Color:
	get:
		return _fill_color
	set(value):
		_fill_color = value
		queue_redraw()

var ring_color: Color:
	get:
		return _ring_color
	set(value):
		_ring_color = value
		queue_redraw()

var shadow_color: Color:
	get:
		return _shadow_color
	set(value):
		_shadow_color = value
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 0.0:
		return
	var radius := side * 0.5
	var center := size * 0.5
	draw_circle(center + Vector2(0, maxf(1.0, side * 0.035)), radius, _shadow_color)
	draw_circle(center, radius, Color(0.010, 0.016, 0.020, 0.94))
	var inner_radius := maxf(1.0, radius - maxf(2.0, side * 0.055))
	if _texture != null:
		var rect := Rect2(center - Vector2(inner_radius, inner_radius), Vector2(inner_radius * 2.0, inner_radius * 2.0))
		var masked := _texture_mask.masked(_texture, maxi(1, int(round(inner_radius * 2.0))))
		if masked != null:
			draw_texture_rect(masked, rect, false)
	else:
		draw_circle(center, inner_radius, _fill_color)
	draw_arc(center, inner_radius + 1.0, 0, TAU, 96, Color(0, 0, 0, 0.34), 2.0, true)
	draw_arc(center, inner_radius + 1.0, 0, TAU, 96, _ring_color, 2.0, true)


func _source_rect(source_texture: Texture2D, dest_size: Vector2) -> Rect2:
	var source_size := source_texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0 or dest_size.x <= 0.0 or dest_size.y <= 0.0:
		return Rect2(Vector2.ZERO, source_size)
	var source_aspect := source_size.x / source_size.y
	var dest_aspect := dest_size.x / dest_size.y
	if source_aspect > dest_aspect:
		var width := source_size.y * dest_aspect
		return Rect2(Vector2((source_size.x - width) * 0.5, 0.0), Vector2(width, source_size.y))
	var height := source_size.x / dest_aspect
	return Rect2(Vector2(0.0, (source_size.y - height) * 0.5), Vector2(source_size.x, height))
