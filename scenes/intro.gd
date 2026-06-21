# intro.gd
# Boot scene: plays the intro video, then routes to the game. The 4 backstory beats
# are NOT here — game.gd's _begin_narrative still shows them on first load (gated by
# Settings.intro_enabled), so the flow is video -> beats -> game with no duplication.
# If intro is disabled, or the video can't play, route straight to main.tscn.
extends Control

const MAIN := "res://scenes/main.tscn"

@onready var video: VideoStreamPlayer = $Video

var _done := false

func _ready() -> void:
	# Gate: web has no Theora playback, intro disabled, or no usable stream -> straight
	# to the game (no video, no black-screen wait).
	if OS.has_feature("web") or not Settings.intro_enabled or video.stream == null:
		_go_main()
		return
	video.finished.connect(_go_main)
	if not video.is_playing():
		video.play()
	# Boot-hang guard: if `finished` never fires (decode/import issue), route anyway.
	var secs := video.get_stream_length()
	if secs <= 0.0:
		secs = 60.0
	get_tree().create_timer(secs + 3.0).timeout.connect(_go_main)

# Tap / click / touch / Enter / Space skips the video.
func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]))
	if pressed:
		get_viewport().set_input_as_handled()
		_go_main()

# Stop the video (kills its audio) and hand off to the game. Idempotent.
func _go_main() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(video):
		video.stop()
	get_tree().change_scene_to_file(MAIN)
