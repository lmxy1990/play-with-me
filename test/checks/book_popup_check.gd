extends SceneTree


func _initialize() -> void:
	var packed := load("res://scenes/common/book_popup.tscn") as PackedScene
	var popup := packed.instantiate()
	root.add_child(popup)
	popup.call("setup", "测试弹窗", Callable(), Vector2(820, 460))
	await process_frame
	assert(popup.call("left_page") != null)
	assert(popup.call("right_page") != null)
	popup.queue_free()
	await process_frame
	quit()
