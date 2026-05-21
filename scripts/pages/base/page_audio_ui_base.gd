extends "res://scripts/pages/base/page_route_ui_base.gd"

var _click_player: AudioStreamPlayer


func _setup_click_sound() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_click_player = AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050
	stream.buffer_length = 0.08
	_click_player.stream = stream
	add_child(_click_player)
	_click_player.play()


func _play_click() -> void:
	if _click_player == null:
		return
	if not _click_player.playing:
		_click_player.play()
	var playback := _click_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var available: int = playback.get_frames_available()
	var frames: int = mini(available, 900)
	for i in range(frames):
		var t: float = float(i) / 22050.0
		var fade: float = 1.0 - float(i) / float(frames)
		var sample: float = sin(t * TAU * 720.0) * 0.12 * fade
		playback.push_frame(Vector2(sample, sample))
