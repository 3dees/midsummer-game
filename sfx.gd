# sfx.gd
# Sound-effects player (autoload "Sfx"). Preloads res://assets/audio/sfx/*.{wav,ogg,mp3}
# into a name -> AudioStream map and plays them on the "SFX" audio bus through a small
# round-robin pool so overlapping one-shots (clicks, score ticks) don't cut each other.
# Every call no-ops when Settings.sfx_enabled is false. Missing files are skipped (load
# defensively) so sounds can be dropped in one at a time.
extends Node

const SFX_DIR := "res://assets/audio/sfx/"
const BUS := "SFX"
const POOL := 6
const LOOP_FADE := 0.1           # reel-loop fade-out (s) so it doesn't click off

var _streams := {}               # name -> AudioStream
var _players: Array = []         # one-shot pool (round-robin)
var _next := 0
var _loop_player: AudioStreamPlayer = null
var _loop_tween: Tween = null

func _ready() -> void:
	_ensure_bus()
	_load_streams()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)
	_loop_player = AudioStreamPlayer.new()
	_loop_player.bus = BUS
	add_child(_loop_player)
	Settings.apply_audio()       # set the SFX bus volume now that the bus exists

# Create the SFX bus at runtime if the layout didn't define it (defensive).
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, "Master")

func _load_streams() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		return                   # no folder yet — every play() will simply no-op
	for f in dir.get_files():
		var ext := f.get_extension().to_lower()
		if ext not in ["wav", "ogg", "mp3"]:
			continue             # skip .import sidecars and anything else
		var path := SFX_DIR + f
		if not ResourceLoader.exists(path):
			continue
		var s = load(path)
		if s is AudioStream:
			_streams[f.get_basename()] = s

# Play a one-shot. pitch shifts playback rate (used for the rising score tally).
func play(key: String, pitch := 1.0) -> void:
	if not Settings.sfx_enabled:
		return
	if not _streams.has(key):
		return                   # missing file — no-op
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.pitch_scale = pitch
	p.play()

# Looping bed (reel spin). Starts the loop; stop_loop() fades it out.
func start_loop(key: String, pitch := 1.0) -> void:
	if not Settings.sfx_enabled:
		return
	if not _streams.has(key):
		return
	if _loop_tween and _loop_tween.is_valid():
		_loop_tween.kill()
	var s: AudioStream = _streams[key]
	_set_looping(s)
	_loop_player.stream = s
	_loop_player.pitch_scale = pitch
	_loop_player.volume_db = 0.0
	_loop_player.play()

func stop_loop() -> void:
	if _loop_player == null or not _loop_player.playing:
		return
	if _loop_tween and _loop_tween.is_valid():
		_loop_tween.kill()
	_loop_tween = create_tween()
	_loop_tween.tween_property(_loop_player, "volume_db", -40.0, LOOP_FADE)
	_loop_tween.tween_callback(_loop_player.stop)

func _set_looping(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		# Loop the whole clip. Forcing loop_mode alone leaves loop_end at 0, which is an
		# empty [0,0] loop region — the stream then plays silence. Set the full region.
		s.loop_begin = 0
		s.loop_end = int(round(s.get_length() * s.mix_rate))
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif s is AudioStreamOggVorbis:
		s.loop = true
	elif s is AudioStreamMP3:
		s.loop = true
