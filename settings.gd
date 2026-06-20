# settings.gd
# Persistent player settings (autoload "Settings"). Loads/saves a ConfigFile at
# user://settings.cfg and applies audio on startup. Game code reads anim_scale() /
# animations_on() for timing, music_* for audio, vibration_enabled via vibrate().
extends Node

const PATH := "user://settings.cfg"
const SEC := "settings"

# --- settings (with defaults) ---
var animation_mode := "normal"   # "off" | "slow" | "normal" | "fast"
var music_enabled := true
var music_volume := 0.7          # 0.0 - 1.0
var sfx_enabled := true
var sfx_volume := 0.8            # 0.0 - 1.0
var vibration_enabled := true
var intro_enabled := true        # show the opening backstory at run start
var intro_seen := false          # set true once the intro has played (informational)

signal changed                   # emitted on any change so UI can refresh

func _ready() -> void:
	load_settings()
	apply_audio()

# Duration multiplier for spin/reveal timings: normal 1.0, slow 1.5, fast 0.5.
func anim_scale() -> float:
	match animation_mode:
		"slow": return 1.5
		"fast": return 0.5
		_: return 1.0            # "normal" (and "off", unused while animations_on() is false)

func animations_on() -> bool:
	return animation_mode != "off"

# --- mutators: apply, persist, notify ---
func set_animation_mode(mode: String) -> void:
	if mode not in ["off", "slow", "normal", "fast"]:
		return
	animation_mode = mode
	_changed()

func set_music_enabled(on: bool) -> void:
	music_enabled = on
	apply_audio()
	_changed()

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	_changed()

func set_sfx_enabled(on: bool) -> void:
	sfx_enabled = on
	_changed()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	_changed()

func set_vibration_enabled(on: bool) -> void:
	vibration_enabled = on
	_changed()

func set_intro_enabled(on: bool) -> void:
	intro_enabled = on
	_changed()

func set_intro_seen(seen: bool) -> void:
	intro_seen = seen
	_changed()

func _changed() -> void:
	save_settings()
	changed.emit()

# --- audio ---
func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, not music_enabled)
	# Map 0-1 linear to dB; floor avoids -inf at 0.
	AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(music_volume, 0.0001, 1.0)))
	# SFX bus (created by the Sfx autoload; may not exist yet on first call).
	var sbus := AudioServer.get_bus_index("SFX")
	if sbus >= 0:
		AudioServer.set_bus_volume_db(sbus, linear_to_db(clampf(sfx_volume, 0.0001, 1.0)))

# --- haptics ---
# No-op unless enabled and on a handheld OS, so the toggle is safe on desktop.
func vibrate(ms: int) -> void:
	if not vibration_enabled:
		return
	if OS.get_name() in ["Android", "iOS"]:
		Input.vibrate_handheld(ms)

# --- persistence ---
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return                   # no file yet — keep defaults
	animation_mode = String(cfg.get_value(SEC, "animation_mode", animation_mode))
	if animation_mode not in ["off", "slow", "normal", "fast"]:
		animation_mode = "normal"
	music_enabled = bool(cfg.get_value(SEC, "music_enabled", music_enabled))
	music_volume = clampf(float(cfg.get_value(SEC, "music_volume", music_volume)), 0.0, 1.0)
	sfx_enabled = bool(cfg.get_value(SEC, "sfx_enabled", sfx_enabled))
	sfx_volume = clampf(float(cfg.get_value(SEC, "sfx_volume", sfx_volume)), 0.0, 1.0)
	vibration_enabled = bool(cfg.get_value(SEC, "vibration_enabled", vibration_enabled))
	intro_enabled = bool(cfg.get_value(SEC, "intro_enabled", intro_enabled))
	intro_seen = bool(cfg.get_value(SEC, "intro_seen", intro_seen))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SEC, "animation_mode", animation_mode)
	cfg.set_value(SEC, "music_enabled", music_enabled)
	cfg.set_value(SEC, "music_volume", music_volume)
	cfg.set_value(SEC, "sfx_enabled", sfx_enabled)
	cfg.set_value(SEC, "sfx_volume", sfx_volume)
	cfg.set_value(SEC, "vibration_enabled", vibration_enabled)
	cfg.set_value(SEC, "intro_enabled", intro_enabled)
	cfg.set_value(SEC, "intro_seen", intro_seen)
	cfg.save(PATH)
