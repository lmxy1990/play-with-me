extends RefCounted
class_name CircularTextureMask

var _cache := {}


func masked(source_texture: Texture2D, diameter: int) -> Texture2D:
	if source_texture == null or diameter <= 0:
		return null
	var key := "%s|%d" % [str(source_texture.get_rid()), diameter]
	if _cache.has(key):
		return _cache[key]
	var source_image := source_texture.get_image()
	if source_image == null or source_image.get_width() <= 0 or source_image.get_height() <= 0:
		return source_texture
	var region := _center_square_region(source_image.get_size())
	var image := source_image.get_region(region)
	if image.get_width() <= 0 or image.get_height() <= 0:
		return source_texture
	image.convert(Image.FORMAT_RGBA8)
	image.resize(diameter, diameter, Image.INTERPOLATE_LANCZOS)
	_apply_circle_alpha(image)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


func clear() -> void:
	_cache.clear()


func _center_square_region(source_size: Vector2i) -> Rect2i:
	var side := mini(source_size.x, source_size.y)
	var x := int((source_size.x - side) * 0.5)
	var y := int((source_size.y - side) * 0.5)
	return Rect2i(Vector2i(x, y), Vector2i(side, side))


func _apply_circle_alpha(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var radius := minf(float(width), float(height)) * 0.5
	var center := Vector2(float(width) * 0.5, float(height) * 0.5)
	for y in range(height):
		for x in range(width):
			var distance := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center)
			var alpha := clampf(radius + 0.75 - distance, 0.0, 1.0)
			if alpha >= 1.0:
				continue
			var color := image.get_pixel(x, y)
			color.a *= alpha
			image.set_pixel(x, y, color)
