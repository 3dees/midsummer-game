# game.gd
# Minimal playable Midsummer Slots loop: spin -> score -> draft -> tithe -> win/lose.
# Ported from the play.tsx reducer, trimmed to the v1 core (no inventory, reroll/
# removal spending, reveal animation, or polished overlays). Wired to
# MidsummerEngine (scoring) + Symbols (registry).
extends Control

const COLS := 5
const ROWS := 4
const SPRITE_DIR := "res://assets/sprites/"

# --- run state (mirrors the play.tsx GameState) ---
var pool: Array = []                 # Array of tiles (MidsummerEngine.make_tile)
var grid: Array = []                 # last rolled grid
var orbs := 0                        # banked Light Orbs (carries over across tithes)
var reroll_orbs := 0
var removal_orbs := 0
var spin_in_cycle := 0
var tithe_round := 0                 # 0-based index into the schedule
var total_spins := 0
var alternating_tick := false
var appearance_counts := {}
var destroyed_this_run := 0
var running := true

var schedule: Array = MidsummerEngine.tithe_schedule()

# Grid window placement over the cabinet frame, as fractions of the frame image.
# Calibrated from the web SlotFrame (cabinet_clean.png, 1024x1536): grid origin
# (238, 436), 5x4 cells of 108.2px. Tweak in the Inspector then F6 to eyeball.
@export var grid_left_frac: float = 0.2324219    # 238 / 1024
@export var grid_top_frac: float = 0.2838542     # 436 / 1536
@export var grid_right_frac: float = 0.7607422   # (238 + 5*108.2) / 1024
@export var grid_bottom_frac: float = 0.5656250  # (436 + 4*108.2) / 1536

@onready var grid_box: GridContainer = $Layout/CabinetAspect/Cabinet/Grid
@onready var orb_chip: Label = $Layout/HudPanel/HudBox/HudTop/ChipsRow/OrbChipBox/OrbChip
@onready var reroll_chip: Label = $Layout/HudPanel/HudBox/HudTop/ChipsRow/RerollChipBox/RerollChip
@onready var removal_chip: Label = $Layout/HudPanel/HudBox/HudTop/ChipsRow/RemovalChipBox/RemovalChip
@onready var orb_chip_box: HBoxContainer = $Layout/HudPanel/HudBox/HudTop/ChipsRow/OrbChipBox
@onready var reroll_chip_box: HBoxContainer = $Layout/HudPanel/HudBox/HudTop/ChipsRow/RerollChipBox
@onready var removal_chip_box: HBoxContainer = $Layout/HudPanel/HudBox/HudTop/ChipsRow/RemovalChipBox
@onready var gear_button: Button = $Layout/HudPanel/HudBox/HudTop/GearButton
@onready var settings_layer: Control = $SettingsLayer
@onready var settings_close: Button = $SettingsLayer/Panel/SettingsBox/SettingsClose
@onready var music_toggle: Button = $SettingsLayer/Panel/SettingsBox/MusicRow/MusicToggle
@onready var music_slider: HSlider = $SettingsLayer/Panel/SettingsBox/MusicRow/MusicSlider
@onready var sfx_toggle: Button = $SettingsLayer/Panel/SettingsBox/SfxToggle
@onready var vibration_toggle: Button = $SettingsLayer/Panel/SettingsBox/VibrationToggle
@onready var anim_buttons := {
	"off": $SettingsLayer/Panel/SettingsBox/AnimRow/AnimOff,
	"slow": $SettingsLayer/Panel/SettingsBox/AnimRow/AnimSlow,
	"normal": $SettingsLayer/Panel/SettingsBox/AnimRow/AnimNormal,
	"fast": $SettingsLayer/Panel/SettingsBox/AnimRow/AnimFast,
}
@onready var music: AudioStreamPlayer = $Music
@onready var sub_line: Label = $Layout/HudPanel/HudBox/SubLine
@onready var season_round: Label = $Layout/CabinetAspect/Cabinet/StatusBox/SeasonRound
@onready var spins_to_bell: Label = $Layout/CabinetAspect/Cabinet/StatusBox/SpinsToBell
@onready var tithe_bar: ProgressBar = $Layout/CabinetAspect/Cabinet/StatusBox/ProgressRow/TitheBar
@onready var spin_button: Button = $Layout/SpinButton
@onready var bag_button: Button = $Layout/BagButton
@onready var background: TextureRect = $Background
@onready var draft_layer: Control = $DraftLayer
@onready var draft_cards: HBoxContainer = $DraftLayer/Panel/DraftBox/DraftCards
@onready var draft_bag_button: Button = $DraftLayer/Panel/DraftBox/ButtonRow/DraftBagButton
@onready var reroll_button: Button = $DraftLayer/Panel/DraftBox/ButtonRow/RerollButton
@onready var skip_button: Button = $DraftLayer/Panel/DraftBox/ButtonRow/SkipButton
@onready var bag_layer: Control = $BagLayer
@onready var bag_grid: GridContainer = $BagLayer/Panel/BagBox/BagScroll/BagGrid
@onready var bag_close: Button = $BagLayer/Panel/BagBox/BagClose
@onready var bag_tab_symbols: Button = $BagLayer/Panel/BagBox/TabRow/TabSymbols
@onready var bag_removal_label: Label = $BagLayer/Panel/BagBox/RemovalBar/RemovalRow/RemovalLabel
@onready var bag_helper: Label = $BagLayer/Panel/BagBox/HelperText
@onready var symbol_popup_layer: Control = $SymbolPopupLayer
@onready var popup_detail: VBoxContainer = $SymbolPopupLayer/Panel/PopupBox/DetailHolder
@onready var popup_discard: Button = $SymbolPopupLayer/Panel/PopupBox/DiscardButton
@onready var popup_hint: Label = $SymbolPopupLayer/Panel/PopupBox/DiscardHint
@onready var popup_close: Button = $SymbolPopupLayer/Panel/PopupBox/TopRow/CloseX
@onready var message_label: Label = $MessageLabel
@onready var log_lines: VBoxContainer = $Layout/SpinLog/LogScroll/LogLines

# --- Score-reveal timing (two macro-phases: choreography, then tally) ---
const REVEAL_FLOAT_LINGER := 0.78   # "+N" float rise + fade duration (~780ms)
const CHOREO_GAP := 0.10            # Phase 1: gap between adjacency pair beats (100ms)
const PHASE_BEAT := 0.25            # beat between Phase 1 (choreo) and Phase 2 (tally)
const TALLY_BASE_CADENCE := 0.06    # Phase 2: base-value sweep cadence (60ms)
const TALLY_SYN_CADENCE := 0.10     # Phase 2: synergy float cadence (100ms)
const TALLY_GLOBAL_PAUSE := 0.18    # Phase 2: pause before the global apply
const BANK_PAUSE := 0.30            # pause once the tally reaches the spin total
const BANK_DUR := 0.45              # count-up / fly-into-Light bank animation
const BOUNCE_COUNT := 3             # hops per synergy group (settling bounce)
const BOUNCE_HOP := 14.0            # first hop height (px); decays each hop
const BOUNCE_DECAY := 0.62          # amplitude multiplier per hop (~14 -> 9 -> 5px)
const BOUNCE_HOP_DUR := 0.15        # duration of one hop (~150ms); 3 hops ~= 450ms
const DRAFT_PAUSE := 0.35           # beat after the tally banks before the draft opens
var _revealing := false
var _skip := false                  # tap-to-skip: jump to the final committed state
var _spin_total_label: Label = null # transient "+this spin" counter (created lazily)
var _reveal_tweens: Array = []      # active reveal tweens, killed on skip/finalize
var _cell_base_y := {}              # bounced cells' rest Y, to restore on skip


# --- Tier 5 slot-reel spin timing ---
const SPIN_SPEED := 1800.0          # constant reel scroll speed, px/s (same for every column)
const SPIN_BASE_DURATION := 0.42    # column 0 stop time; later columns spin longer at the same speed
const SPIN_COL_STAGGER := 0.10      # stagger between column stops, left -> right (100ms)
const SPIN_DECEL := 0.22            # smooth ease-out tail that glides the reel onto the finals
const SPIN_DECEL_CELLS := 0.7       # how many cells the deceleration tail spans (short = crisp)
const SPIN_BLUR := 0.0              # vertical-blur strength (0 = off; 9-tap shader ghosted on pixel art)
var _spinning := false
var _reel_mats: Array = []          # one ShaderMaterial per column (vertical blur)
var _spin_textures: Array = []      # filler textures cycled on the reels

# Rarity → small-caps label color for draft cards.
const RARITY_COLORS := {
	"common": Color(0.62, 0.64, 0.66),
	"uncommon": Color(0.4, 0.8, 0.45),
	"rare": Color(0.4, 0.6, 0.95),
	"very_rare": Color(0.7, 0.45, 0.9),
}

var _cells: Array = []               # the 20 TextureRect grid cells
var _popup_uid := ""                 # uid the bag detail popup would discard
var _flash_labels: Array = []        # transient reward "+N" labels (top-level; freed on skip)

func _ready() -> void:
	_apply_grid_rect()
	_build_cells()
	spin_button.pressed.connect(_on_spin)
	skip_button.pressed.connect(_on_skip)
	reroll_button.pressed.connect(_on_reroll)
	bag_button.pressed.connect(_on_bag_open)
	draft_bag_button.pressed.connect(_on_bag_open)
	bag_close.pressed.connect(_on_bag_close)
	gear_button.pressed.connect(_on_settings_open)
	settings_close.pressed.connect(_on_settings_close)
	popup_close.pressed.connect(_close_symbol_popup)
	popup_discard.pressed.connect(_on_popup_discard)
	$SymbolPopupLayer/Backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_symbol_popup())
	$SettingsLayer/Backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_on_settings_close())
	for mode in anim_buttons:
		(anim_buttons[mode] as Button).pressed.connect(_on_anim_mode.bind(mode))
	music_toggle.pressed.connect(_on_toggle_music)
	music_slider.value_changed.connect(_on_music_volume)
	sfx_toggle.pressed.connect(_on_toggle_sfx)
	vibration_toggle.pressed.connect(_on_toggle_vibration)
	_refresh_settings_ui()
	# mp3 streams don't carry a loop flag from import; set it so the theme loops.
	if music.stream is AudioStreamMP3:
		music.stream.loop = true
	_start_run()

# Tap/click anywhere (incl. over the Spin button), a touch, or Enter/Space during the
# spin/reveal skips straight to the final committed state. The event is consumed so it
# can't also land as a draft pick or trigger another spin.
func _input(event: InputEvent) -> void:
	if not (_spinning or _revealing) or _skip:
		return
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]))
	if pressed:
		_skip = true
		get_viewport().set_input_as_handled()

# Per-frame timing divisor derived from the persistent animation setting. Reveal/spin
# code keeps its historical `/ _aspeed()` form: normal 1.0, slow 0.667 (longer hops),
# fast 2.0 (shorter). The "off" case is handled separately via Settings.animations_on().
func _aspeed() -> float:
	return 1.0 / Settings.anim_scale()

# --- settings panel ------------------------------------------------------

func _on_settings_open() -> void:
	_refresh_settings_ui()
	settings_layer.visible = true

func _on_settings_close() -> void:
	settings_layer.visible = false

func _on_anim_mode(mode: String) -> void:
	Settings.set_animation_mode(mode)
	_refresh_settings_ui()

func _on_toggle_music() -> void:
	Settings.set_music_enabled(not Settings.music_enabled)
	_refresh_settings_ui()

func _on_music_volume(v: float) -> void:
	Settings.set_music_volume(v)
	# don't re-sync the slider mid-drag; just keep the on/off label honest
	music_toggle.text = "Music: %s" % ("On" if Settings.music_enabled else "Off")

func _on_toggle_sfx() -> void:
	Settings.set_sfx_enabled(not Settings.sfx_enabled)
	_refresh_settings_ui()

func _on_toggle_vibration() -> void:
	Settings.set_vibration_enabled(not Settings.vibration_enabled)
	_refresh_settings_ui()

# Reflect persisted settings onto the panel controls.
func _refresh_settings_ui() -> void:
	for mode in anim_buttons:
		var btn: Button = anim_buttons[mode]
		# Active mode = primary button; others = SecondaryButton variation.
		btn.theme_type_variation = &"" if Settings.animation_mode == mode else &"SecondaryButton"
	music_toggle.text = "Music: %s" % ("On" if Settings.music_enabled else "Off")
	music_toggle.button_pressed = Settings.music_enabled
	if not music_slider.has_focus():
		music_slider.value = Settings.music_volume
	music_slider.editable = Settings.music_enabled
	sfx_toggle.text = "Sound: %s" % ("On" if Settings.sfx_enabled else "Off")
	sfx_toggle.button_pressed = Settings.sfx_enabled
	vibration_toggle.text = "Vibration: %s" % ("On" if Settings.vibration_enabled else "Off")
	vibration_toggle.button_pressed = Settings.vibration_enabled

# Place the grid container over the cabinet frame's window opening, as fractions
# of the (aspect-locked) frame rect. Offsets stay 0 so it scales with the frame.
func _apply_grid_rect() -> void:
	grid_box.anchor_left = grid_left_frac
	grid_box.anchor_top = grid_top_frac
	grid_box.anchor_right = grid_right_frac
	grid_box.anchor_bottom = grid_bottom_frac
	grid_box.offset_left = 0.0
	grid_box.offset_top = 0.0
	grid_box.offset_right = 0.0
	grid_box.offset_bottom = 0.0

func _build_cells() -> void:
	grid_box.columns = COLS
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.07, 0.09, 0.06, 0.55)
	frame.border_color = Color(0.45, 0.55, 0.35, 0.7)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(6)
	frame.set_content_margin_all(4)
	for i in COLS * ROWS:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(0, 0)   # cells size to the frame window
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.add_theme_stylebox_override("panel", frame)
		var cell := TextureRect.new()
		cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.add_child(cell)
		grid_box.add_child(slot)
		_cells.append(cell)

# --- run lifecycle -------------------------------------------------------

func _start_run() -> void:
	pool.clear()
	for id in Symbols.STARTING_POOL:
		pool.append(MidsummerEngine.make_tile(id))
	orbs = 0
	reroll_orbs = 0
	removal_orbs = 0
	spin_in_cycle = 0
	tithe_round = 0
	total_spins = 0
	alternating_tick = false
	appearance_counts = {}
	destroyed_this_run = 0
	running = true
	# Show the starting symbols before the first spin.
	grid = MidsummerEngine.roll_grid(pool)
	_render_grid()
	_update_hud()
	message_label.hide()
	draft_layer.hide()
	bag_layer.hide()
	spin_button.disabled = false
	bag_button.disabled = false
	_revealing = false
	_spinning = false
	for line in log_lines.get_children():
		line.queue_free()
	var hint := Label.new()
	hint.theme_type_variation = &"CaptionLabel"
	hint.text = "Spin to begin — synergies will appear here"
	log_lines.add_child(hint)

func _on_spin() -> void:
	if not running or _revealing or _spinning:
		return
	_skip = false
	grid = MidsummerEngine.roll_grid(pool)
	var ctx := {
		"total_spins": total_spins,
		"round_number": tithe_round + 1,
		"appearance_counts": appearance_counts,
		"destroyed_this_run": destroyed_this_run,
		"alternating_tick": alternating_tick,
	}
	var score := MidsummerEngine.score_grid(grid, ctx)
	spin_button.disabled = true
	bag_button.disabled = true

	# Tier 5: spin the reels and land them on the already-scored grid (no re-roll),
	# then Tier 4: play the sequential reveal before committing orbs / opening draft.
	await _play_spin(grid)
	await _play_reveal(score)

	orbs += int(score["orbs"])                       # accumulate (carry-over)
	reroll_orbs += int(score["reroll_orbs_gained"])
	removal_orbs = mini(removal_orbs + int(score["removal_orbs_gained"]), 3)  # cap 3
	appearance_counts = score["appearance_counts_next"]
	total_spins += 1
	alternating_tick = not alternating_tick
	spin_in_cycle += 1
	_update_hud()

	# Tithe check: did this spin complete the cycle?
	if spin_in_cycle >= int(schedule[tithe_round]["spins"]):
		_resolve_tithe()
		if not running:
			return
	# Draft after every spin (uses the possibly-advanced tithe_round).
	_open_draft()

# --- Tier 5: slot-reel spin ----------------------------------------------

# Spin the 5 columns as true vertical reels: hide the static cells, scroll a tall
# strip per column (random filler ending in that column's final 4 symbols), blur
# while moving, then stop left -> right with a TRANS_BACK overshoot. As each column
# rests, reveal its real cell sprites and drop the reel — clean handoff, no doubles.
# No re-roll: the strips end on exactly `final_grid`, which `_play_reveal` scores.
func _play_spin(final_grid: Array) -> void:
	_spinning = true
	await get_tree().process_frame              # ensure the grid cells have laid-out rects
	await get_tree().process_frame              # second frame: containers settle their final rects
	# Geometry taken from the REAL settled cells so the reel lands pixel-identical
	# (no shift/size-pop on handoff). Row pitch = distance between stacked cell tops.
	# layer overlays grid_box exactly (same parent, same position), so cells map into
	# layer space by subtracting grid_box's own global position — NOT the parent's.
	var layer_gp: Vector2 = grid_box.global_position
	# Capture every cell's global rect NOW, while still visible and container-constrained.
	# (Reading size after hiding releases the constraint and the TextureRect reverts to its
	# native 64px texture size — that mismatch was the spin "shift".)
	var cell_rects: Array = []
	for cell in _cells:
		cell_rects.append((cell as TextureRect).get_global_rect())
	var ch: float = cell_rects[COLS].position.y - cell_rects[0].position.y
	if ch <= 0.0 or not Settings.animations_on() or _skip:  # no layout / off / skipped — apply instantly
		_render_grid()
		_spinning = false
		return

	_ensure_reel_mats()
	_spin_textures = _build_spin_textures()
	for cell in _cells:                          # hide statics so nothing ghosts underneath
		cell.visible = false

	var layer := Control.new()
	layer.name = "ReelLayer"
	layer.position = grid_box.position
	layer.size = grid_box.size
	layer.z_index = 4
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_box.get_parent().add_child(layer)

	# Every reel moves at the same constant speed; later columns scroll farther (more
	# filler) so they stop later. Stop time per column = base + c*stagger.
	var max_dur := 0.0
	for c in COLS:
		var top_rect: Rect2 = cell_rects[c]      # row 0 of this column (pre-hide, real size)
		var cw := top_rect.size.x
		var cell_h := top_rect.size.y
		var origin: Vector2 = top_rect.position - layer_gp   # column origin in layer space

		# Clip exactly to this column's real extent (row 0 top -> last row bottom) so the
		# reel can never spill past the grid window, even if pitch != cell height.
		var last_rect: Rect2 = cell_rects[(ROWS - 1) * COLS + c]
		var col_h: float = (last_rect.position.y + last_rect.size.y) - top_rect.position.y
		var colctrl := Control.new()
		colctrl.position = origin
		colctrl.size = Vector2(cw, col_h)
		colctrl.clip_contents = true
		colctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(colctrl)

		var strip := Control.new()
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat: ShaderMaterial = null
		if SPIN_BLUR > 0.0:                       # blur off by default — avoids the pixel-art ghosting
			mat = _reel_mats[c]
			mat.set_shader_parameter("strength", SPIN_BLUR)
			strip.material = mat
		colctrl.add_child(strip)

		# Filler count sized so a constant-speed scroll lasts this column's stop time.
		var stop_t := SPIN_BASE_DURATION + c * SPIN_COL_STAGGER
		var n_filler: int = maxi(ROWS + 6, int(round(SPIN_SPEED * stop_t / ch)))
		for f in n_filler:
			_add_reel_cell(strip, _spin_textures[randi() % _spin_textures.size()], f, cw, cell_h, ch)
		for r in ROWS:
			var idx: int = r * COLS + c
			var tile = final_grid[idx] if idx < final_grid.size() else null
			var tex: Texture2D = _texture_for(String(tile["id"])) if tile != null else null
			_add_reel_cell(strip, tex, n_filler + r, cw, cell_h, ch)
		strip.position.y = 0.0                   # start with fillers in view

		# Constant-speed linear scroll for the bulk, then a smooth cubic ease-out tail that
		# glides the reel onto the (centered) finals — no overshoot, no snap. _aspeed()
		# scales the whole spin (fast = shorter); animations-off handled above.
		var rest: float = -n_filler * ch
		var decel_dist: float = ch * SPIN_DECEL_CELLS
		var lin_dur: float = maxf(0.0, n_filler * ch - decel_dist) / SPIN_SPEED / _aspeed()
		var decel_dur: float = SPIN_DECEL / _aspeed()
		var tw := create_tween()
		tw.tween_property(strip, "position:y", rest + decel_dist, lin_dur).set_trans(Tween.TRANS_LINEAR)
		tw.tween_property(strip, "position:y", rest, decel_dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var dur := lin_dur + decel_dur
		max_dur = max(max_dur, dur)
		if mat != null:                          # ease the blur off over the back half
			var mtw := create_tween()
			mtw.tween_interval(dur * 0.55)
			mtw.tween_property(mat, "shader_parameter/strength", 0.0, dur * 0.45)
		tw.finished.connect(_on_column_settled.bind(c, layer))

	await get_tree().create_timer(max_dur + 0.05).timeout

	if is_instance_valid(layer):
		layer.queue_free()
	_render_grid()                               # guarantee exact final textures + visibility
	_spinning = false

# Reveal a settled column's real cell sprites and hide its reel strip.
func _on_column_settled(c: int, layer: Control) -> void:
	for r in ROWS:
		var idx: int = r * COLS + c
		var tile = grid[idx] if idx < grid.size() else null
		_cells[idx].texture = _texture_for(String(tile["id"])) if tile != null else null
		_cells[idx].visible = true
	if is_instance_valid(layer) and c < layer.get_child_count():
		layer.get_child(c).visible = false

func _add_reel_cell(strip: Control, tex: Texture2D, row: int, cell_w: float, cell_h: float, pitch: float) -> void:
	var rc := TextureRect.new()
	# expand_mode MUST be set before size: with the default KEEP_SIZE, the texture's
	# native 64px becomes the min size and clamps size up to 64 (the spin oversize bug).
	rc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rc.texture = tex
	# Match the real cell's draw rect exactly (origin already carries the inset);
	# stack by row pitch so the final row lands pixel-identical to the settled sprite.
	rc.position = Vector2(0.0, row * pitch)
	rc.size = Vector2(cell_w, cell_h)
	rc.use_parent_material = true                # render through the strip's blur shader
	rc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(rc)

func _ensure_reel_mats() -> void:
	if not _reel_mats.is_empty():
		return
	var shader: Shader = load("res://ui/reel_blur.gdshader")
	for c in COLS:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("strength", 0.0)
		_reel_mats.append(mat)

# A handful of distinct sprites to cycle through while spinning (pool first, then
# fill from the registry) so the reels look varied without loading every frame.
func _build_spin_textures() -> Array:
	var out: Array = []
	var seen := {}
	for tile in pool:
		var id: String = String(tile["id"])
		if not seen.has(id):
			seen[id] = true
			out.append(_texture_for(id))
	var keys: Array = Symbols.SYMBOLS.keys()
	while out.size() < 12 and seen.size() < keys.size():
		var id: String = String(keys[randi() % keys.size()])
		if not seen.has(id):
			seen[id] = true
			out.append(_texture_for(id))
	return out

# --- Tier 4: sequential score reveal -------------------------------------

# Two macro-phases (LBaL-style):
#   PHASE 1 — Choreography: bounces only, no numbers, score frozen.
#   PHASE 2 — Tally: a transient "+this spin" counter climbs as cells pay in
#             (no bounces), then banks into the persistent Light total.
# Tap-to-skip / animations-off jump straight to the final committed state.
func _play_reveal(score: Dictionary) -> void:
	_revealing = true
	_reset_reveal()

	# Bucket events.
	var pairs: Array = []           # adjacentBonus — pair beats (bounce)
	var locals: Array = []          # self/local effects — float only, never bounce
	var globals: Array = []         # globalBonus / globalMultiplier — finale
	var rewards: Array = []         # reward-orb triggers — chip flash
	for ev in score["events"]:
		if String(ev["kind"]) != "synergy":
			continue
		var t := String(ev.get("synergy_type", ""))
		if ev.has("reward_amount"):
			rewards.append(ev)
		elif t == "globalBonus" or t == "globalMultiplier":
			globals.append(ev)
		elif t == "adjacentBonus":
			pairs.append(ev)
		else:
			locals.append(ev)

	_log_header(score)
	orb_chip.text = "%d" % orbs                # score frozen through Phases 1-2

	# Off / already-skipped: apply the final state instantly.
	if not Settings.animations_on() or _skip:
		_finalize_reveal(score)
		_revealing = false
		return

	# Let the landed reel settle visibly still before any choreography bounce, so a
	# synergy cell doesn't appear to "hop" the instant it lands.
	await _sleep(PHASE_BEAT)
	if _skip:
		_finalize_reveal(score); _revealing = false; return

	# ---------- PHASE 1 — Choreography (bounces only, no numbers) ----------
	pairs.sort_custom(_phase2_before)          # reading order, anchored at the later cell
	for ev in pairs:
		for ci in ev.get("cells", [int(ev["cell"])]):
			_bounce_cell(int(ci))
		await _sleep(BOUNCE_COUNT * BOUNCE_HOP_DUR)
		if _skip: break
		await _sleep(CHOREO_GAP)
		if _skip: break
	if not _skip and not globals.is_empty():   # global finale: all involved cells, once
		var gcells := {}
		for ev in globals:
			for ci in ev.get("cells", [int(ev["cell"])]):
				gcells[int(ci)] = true
		for ci in gcells.keys():
			_bounce_cell(int(ci))
		await _sleep(BOUNCE_COUNT * BOUNCE_HOP_DUR)
	if _skip:
		_finalize_reveal(score); _revealing = false; return

	await _sleep(PHASE_BEAT)

	# ---------- PHASE 2 — Tally (numbers count up, no bounces) ----------
	_show_spin_total()
	var run := 0
	# Base sweep, reading order.
	for i in _cells.size():
		var tile = grid[i] if i < grid.size() else null
		if tile == null:
			continue
		var base := int(Symbols.SYMBOLS[String(tile["id"])]["base_value"])
		if base <= 0:
			continue
		run += base
		_set_spin_total(run)
		_spawn_float(i, base)
		await _sleep(TALLY_BASE_CADENCE)
		if _skip: break
	# Synergy bonuses (pairs + locals), reading order; multipliers float but don't add.
	if not _skip:
		var syn := pairs + locals
		syn.sort_custom(_phase2_before)
		for ev in syn:
			var anchor := _anchor_cell(ev)
			if ev.has("orbs_delta"):
				run += int(ev["orbs_delta"])
				_set_spin_total(run)
				_spawn_float(anchor, int(ev["orbs_delta"]))
			elif ev.has("multiplier"):
				_spawn_text(anchor, "×%s" % _fmt_num(float(ev["multiplier"])))
			_add_log_line(ev)
			await _sleep(TALLY_SYN_CADENCE)
			if _skip: break
	# Reward-orb flashes on the reroll/removal chips.
	for ev in rewards:
		_flash_reward(ev)
		_add_log_line(ev)
	# Globals last (multipliers land last); snap the transient to the authoritative total.
	if not _skip and not globals.is_empty():
		await _sleep(TALLY_GLOBAL_PAUSE)
		for ev in globals:
			var anchor := _anchor_cell(ev)
			if ev.has("orbs_delta"):
				_spawn_float(anchor, int(ev["orbs_delta"]))
			elif ev.has("multiplier"):
				_spawn_text(anchor, "×%s" % _fmt_num(float(ev["multiplier"])))
			_add_log_line(ev)
	_set_spin_total(int(score["orbs"]))

	if _skip:
		_finalize_reveal(score); _revealing = false; return

	# ---------- Bank the spin total into the persistent Light chip ----------
	await _sleep(BANK_PAUSE)
	_bank_spin_total(int(score["orbs"]), orbs)
	await _sleep(BANK_DUR)
	await _sleep(DRAFT_PAUSE)
	_revealing = false

# --- reveal helpers ------------------------------------------------------

# Scaled, skippable wait. _aspeed() scales every Phase 1/2 timing; a pending skip
# (or animations-off) returns immediately so the loops blast through to the finalize.
func _sleep(sec: float) -> void:
	if _skip or not Settings.animations_on():
		return
	await get_tree().create_timer(sec / _aspeed()).timeout

# Jump to the final committed visual state: drop animations, fill the log, hide the
# transient counter, and set the Light chip to its post-bank value.
func _finalize_reveal(score: Dictionary) -> void:
	for tw in _reveal_tweens:
		if tw is Tween and tw.is_valid():
			tw.kill()
	_reveal_tweens.clear()
	for cell in _cells:
		cell.scale = Vector2.ONE
		for child in cell.get_children():
			if child is Label:
				child.queue_free()
	for i in _cell_base_y:                      # restore any cell frozen mid-hop
		_cells[i].position.y = _cell_base_y[i]
	_cell_base_y.clear()
	for f in _flash_labels:                      # killed tweens never fire their free callback
		if is_instance_valid(f):
			f.queue_free()
	_flash_labels.clear()
	_fill_log(score)
	if is_instance_valid(_spin_total_label):
		_spin_total_label.visible = false
	orb_chip.text = "%d" % (orbs + int(score["orbs"]))

func _log_header(score: Dictionary) -> void:
	var head := Label.new()
	head.theme_type_variation = &"CurrencyLabel"
	head.add_theme_font_size_override("font_size", 14)
	head.text = "Spin %d · +%d Light" % [total_spins + 1, int(score["orbs"])]
	log_lines.add_child(head)

# Rebuild the whole log (used on skip/off so no synergy line is missed).
func _fill_log(score: Dictionary) -> void:
	for line in log_lines.get_children():
		line.queue_free()
	_log_header(score)
	for ev in score["events"]:
		if String(ev["kind"]) == "synergy":
			_add_log_line(ev)

# Transient "+this spin" counter, floating just below the Light chip, green to read
# as distinct from the gold persistent total.
func _show_spin_total() -> void:
	if not is_instance_valid(_spin_total_label):
		_spin_total_label = Label.new()
		_spin_total_label.theme_type_variation = &"CurrencyLabel"
		_spin_total_label.add_theme_color_override("font_color", Color(0.45, 0.92, 0.55))
		_spin_total_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spin_total_label.z_index = 25
		add_child(_spin_total_label)
		_spin_total_label.set_as_top_level(true)
	_spin_total_label.modulate = Color(1, 1, 1, 1)
	_spin_total_label.visible = true
	_spin_total_label.text = "+0"
	_spin_total_label.global_position = orb_chip_box.global_position + Vector2(0.0, orb_chip_box.size.y + 2.0)

func _set_spin_total(n: int) -> void:
	if is_instance_valid(_spin_total_label):
		_spin_total_label.text = "+%d" % n

# Count the Light chip up by the spin amount while the transient counter flies into
# the chip and fades.
func _bank_spin_total(spin_amount: int, start_orbs: int) -> void:
	var dur := BANK_DUR / maxf(_aspeed(), 0.001)
	var ct := create_tween()
	ct.tween_method(func(v: float) -> void: orb_chip.text = "%d" % int(round(v)),
		float(start_orbs), float(start_orbs + spin_amount), dur)
	_reveal_tweens.append(ct)
	if is_instance_valid(_spin_total_label):
		var target := orb_chip_box.global_position
		var fly := create_tween()
		fly.set_parallel(true)
		fly.tween_property(_spin_total_label, "global_position", target, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fly.tween_property(_spin_total_label, "modulate:a", 0.0, dur)
		fly.chain().tween_callback(func() -> void:
			if is_instance_valid(_spin_total_label):
				_spin_total_label.visible = false
		)
		_reveal_tweens.append(fly)

# Phase ordering: anchor = max(cells) (pair lands on its later cell), tiebreak min(cells).
func _phase2_before(a: Dictionary, b: Dictionary) -> bool:
	var amax := _anchor_cell(a)
	var bmax := _anchor_cell(b)
	if amax != bmax:
		return amax < bmax
	return _min_cell(a) < _min_cell(b)

# Anchor cell of an event = the max (latest reading-order) index in its cells.
func _anchor_cell(ev: Dictionary) -> int:
	var m := int(ev["cell"])
	for c in ev.get("cells", [int(ev["cell"])]):
		m = max(m, int(c))
	return m

func _min_cell(ev: Dictionary) -> int:
	var m := int(ev["cell"])
	for c in ev.get("cells", [int(ev["cell"])]):
		m = min(m, int(c))
	return m

# Reward-orb trigger (reroll/removal): pop "+N" beside the matching HUD chip instead
# of on the symbol — symbols only ever show point deltas.
func _flash_reward(ev: Dictionary) -> void:
	var kind := String(ev.get("reward_kind", ""))
	var box: Control = removal_chip_box if kind == "removal_orb" else reroll_chip_box
	_flash_chip(box, "+%d" % int(ev.get("reward_amount", 1)))

func _flash_chip(box: Control, txt: String) -> void:
	var f := Label.new()
	f.text = txt
	f.theme_type_variation = &"CurrencyLabel"
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 30
	add_child(f)
	f.set_as_top_level(true)
	f.global_position = box.global_position + Vector2(box.size.x * 0.5 - 8.0, -6.0)
	_flash_labels.append(f)
	var linger := REVEAL_FLOAT_LINGER / maxf(_aspeed(), 0.001)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(f, "global_position:y", f.global_position.y - 22.0, linger)
	tw.tween_property(f, "modulate:a", 0.0, linger).set_delay(linger * 0.4)
	tw.finished.connect(func() -> void:
		_flash_labels.erase(f)
		if is_instance_valid(f):
			f.queue_free()
	)
	_reveal_tweens.append(tw)

func _spawn_float(i: int, v: int) -> void:
	_spawn_text(i, "+%d" % v)

func _spawn_text(i: int, txt: String) -> void:
	var cell: TextureRect = _cells[i]
	var f := Label.new()
	f.text = txt
	f.theme_type_variation = &"CurrencyLabel"
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 20
	cell.add_child(f)
	f.position = cell.size * 0.5 - Vector2(10, 12)
	var linger := REVEAL_FLOAT_LINGER / maxf(_aspeed(), 0.001)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(f, "position:y", f.position.y - 26.0, linger)
	tw.tween_property(f, "modulate:a", 0.0, linger).set_delay(linger * 0.45)
	tw.finished.connect(func() -> void:
		if is_instance_valid(f):
			f.queue_free()
	)
	_reveal_tweens.append(tw)

# Vertical hop with squash-and-stretch. Animates the cell sprite's own offset/
# scale (not its GridContainer slot) so the container doesn't fight the motion.
func _bounce_cell(i: int) -> void:
	var cell: TextureRect = _cells[i]
	cell.pivot_offset = cell.size * 0.5
	var base_y := cell.position.y
	if not _cell_base_y.has(i):
		_cell_base_y[i] = base_y
	var up_t := BOUNCE_HOP_DUR * 0.42 / _aspeed()
	var down_t := BOUNCE_HOP_DUR * 0.58 / _aspeed()
	var pt := create_tween()
	var st := create_tween()
	_reveal_tweens.append(pt)
	_reveal_tweens.append(st)
	# A settling bounce: BOUNCE_COUNT quick hops with decaying amplitude. Position
	# and scale run as parallel chained tweens; squash-and-stretch scales with each
	# hop's amplitude so the motion eases out as it settles.
	var amp := BOUNCE_HOP
	for h in BOUNCE_COUNT:
		var s := amp / BOUNCE_HOP                 # 1.0 -> smaller, scales the squash/stretch
		pt.tween_property(cell, "position:y", base_y - amp, up_t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pt.tween_property(cell, "position:y", base_y, down_t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		st.tween_property(cell, "scale", Vector2(1.0 - 0.08 * s, 1.0 + 0.12 * s), up_t).set_ease(Tween.EASE_OUT)
		st.tween_property(cell, "scale", Vector2(1.0 + 0.12 * s, 1.0 - 0.10 * s), down_t)
		amp *= BOUNCE_DECAY
	st.tween_property(cell, "scale", Vector2.ONE, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _reset_reveal() -> void:
	for tw in _reveal_tweens:
		if tw is Tween and tw.is_valid():
			tw.kill()
	_reveal_tweens.clear()
	_cell_base_y.clear()
	for f in _flash_labels:                          # leftover reward "+N" from a prior spin
		if is_instance_valid(f):
			f.queue_free()
	_flash_labels.clear()
	for cell in _cells:
		cell.scale = Vector2.ONE
		for child in cell.get_children():
			if child is Label:                       # leftover floats from a prior spin
				child.queue_free()
	for line in log_lines.get_children():
		line.queue_free()

func _add_log_line(ev: Dictionary) -> void:
	var id := String(ev["id"])
	var sym: Dictionary = Symbols.SYMBOLS[id]
	var suffix := ""
	if ev.has("orbs_delta"):
		suffix = " (+%d)" % int(ev["orbs_delta"])
	elif ev.has("multiplier"):
		suffix = " (×%s)" % _fmt_num(float(ev["multiplier"]))
	elif ev.has("reward_amount"):
		suffix = " (+%d %s)" % [int(ev["reward_amount"]), _reward_str(ev.get("reward_kind", ""))]
	var line := Label.new()
	line.theme_type_variation = &"CaptionLabel"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	line.text = "%s: %s%s" % [String(sym["name"]), _desc_for_event(ev), suffix]
	log_lines.add_child(line)

# Rebuild the human description for a fired synergy event by finding the matching
# synergy on its symbol (events carry only the type, not the full synergy dict).
func _desc_for_event(ev: Dictionary) -> String:
	var id := String(ev["id"])
	var typ := String(ev.get("synergy_type", ""))
	for syn in Symbols.SYMBOLS[id].get("synergies", []):
		if String(syn.get("type", "")) == typ:
			return _synergy_desc(syn)
	return typ

func _resolve_tithe() -> void:
	var cost := int(schedule[tithe_round]["orbs"])
	if orbs >= cost:
		orbs -= cost                                 # keep the surplus (carry-over)
		removal_orbs = mini(removal_orbs + 1, 3)      # free removal orb per tithe paid (cap 3)
		spin_in_cycle = 0
		tithe_round += 1
		Settings.vibrate(30)                          # short pulse on a tithe pass
		if tithe_round >= 12:
			_win()
		else:
			_update_hud()
	else:
		_lose(cost)

func _win() -> void:
	running = false
	Settings.vibrate(120)                            # longer pulse on a win
	spin_button.disabled = true
	bag_button.disabled = true
	draft_layer.hide()
	bag_layer.hide()
	message_label.text = "Crowned of Midsummer. The solstice fire is lit."
	message_label.show()
	_update_hud()

func _lose(cost: int) -> void:
	running = false
	spin_button.disabled = true
	bag_button.disabled = true
	draft_layer.hide()
	bag_layer.hide()
	message_label.text = "The fire gutters — needed %d orbs, had %d.\nThe forest reclaims you." % [cost, orbs]
	message_label.show()

# --- draft ---------------------------------------------------------------

func _open_draft() -> void:
	spin_button.disabled = true
	bag_button.disabled = true
	_clear_cards()
	var offers: Array = MidsummerEngine.pick_draft(Symbols.DRAFT_POOL, tithe_round)
	for id in offers:
		draft_cards.add_child(_make_card(id))
	reroll_button.disabled = reroll_orbs <= 0
	reroll_button.text = "Reroll (%d)" % reroll_orbs
	draft_layer.show()

func _make_card(id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_pick(id)
	)
	panel.add_child(_make_detail_body(id))
	return panel


# Symbol detail body: sprite, name, rarity, base value, description, group pills.
# Shared by draft cards and the bag detail popup. All children ignore mouse so the
# parent (card panel / popup) owns the gesture.
func _make_detail_body(id: String) -> VBoxContainer:
	var sym: Dictionary = Symbols.SYMBOLS[id]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(96, 96)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture = _texture_for(id)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sprite)

	var name_lbl := Label.new()
	name_lbl.text = String(sym["name"])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var rarity := String(sym.get("rarity", "common"))
	var rarity_lbl := Label.new()
	rarity_lbl.text = rarity.replace("_", " ").to_upper()
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_lbl.add_theme_font_size_override("font_size", 11)
	rarity_lbl.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, RARITY_COLORS["common"]))
	rarity_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rarity_lbl)

	var val_row := HBoxContainer.new()
	val_row.alignment = BoxContainer.ALIGNMENT_CENTER
	val_row.add_theme_constant_override("separation", 4)
	val_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var val_lbl := Label.new()
	val_lbl.text = "+%d" % int(sym["base_value"])
	val_lbl.theme_type_variation = &"CurrencyLabel"
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val_row.add_child(val_lbl)
	var val_icon := TextureRect.new()
	val_icon.texture = load(SPRITE_DIR + "orb.png")
	val_icon.custom_minimum_size = Vector2(20, 20)
	val_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	val_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	val_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	val_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val_row.add_child(val_icon)
	vbox.add_child(val_row)

	var desc: String = _card_desc(sym)
	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc_lbl)

	var pills := _make_group_pills(id)
	if pills != null:
		vbox.add_child(pills)

	return vbox


# Synergy-group tag pills (small rounded). Returns null when the symbol has no groups.
func _make_group_pills(id: String) -> Control:
	var gids: Array = Symbols.groups_for_symbol(id)
	if gids.is_empty():
		return null
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(0.2, 0.6, 0.6, 0.22)
	pill_style.border_color = Color(0.2, 0.6, 0.6, 0.6)
	pill_style.set_border_width_all(1)
	pill_style.set_corner_radius_all(10)
	pill_style.content_margin_left = 8
	pill_style.content_margin_right = 8
	pill_style.content_margin_top = 2
	pill_style.content_margin_bottom = 2
	for gid in gids:
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", pill_style)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pl := Label.new()
		pl.text = String(Symbols.SYNERGY_GROUPS[gid]["name"])
		pl.add_theme_font_size_override("font_size", 11)
		pl.add_theme_color_override("font_color", Color(0.6, 0.86, 0.86))
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(pl)
		flow.add_child(pill)
	return flow


func _card_desc(sym: Dictionary) -> String:
	var lines := PackedStringArray()
	for syn in sym.get("synergies", []):
		var d: String = _synergy_desc(syn)
		if d != "":
			lines.append(d)
	return "\n".join(lines)


func _synergy_desc(syn: Dictionary) -> String:
	match String(syn.get("type", "")):
		"adjacentBonus":
			return "+%d adj %s" % [int(syn["bonus"]), _targets_str(syn["targets"])]
		"globalBonus":
			return "+%d per %s" % [int(syn["bonus"]), _targets_str(syn["targets"])]
		"selfChance":
			return "%d%% chance ×%s" % [int(float(syn["chance"]) * 100), _fmt_num(float(syn["multiplier"]))]
		"alternating":
			return "×%s every other spin" % _fmt_num(float(syn["multiplier"]))
		"periodicReward":
			return "Every %d spins: +%d %s" % [int(syn["every"]), int(syn["amount"]), _reward_str(syn["reward"])]
		"globalCountReward":
			return "%d+ on grid: +%d %s" % [int(syn["threshold"]), int(syn["amount"]), _reward_str(syn["reward"])]
		"roundPenalty":
			return "×%s on %s rounds" % [_fmt_num(float(syn["multiplier"])), String(syn["round_type"])]
		"globalMultiplier":
			return "×%s all %s" % [_fmt_num(float(syn["multiplier"])), _targets_str(syn["targets"])]
		"adjacentMultiplier":
			return "×%s adj %s" % [_fmt_num(float(syn["multiplier"])), _targets_str(syn["targets"])]
		"conditionalBonus":
			if syn.has("present_target"):
				return "+%d if %s present" % [int(syn["bonus"]), _target_str(String(syn["present_target"]))]
			return "+%d if %s absent" % [int(syn["bonus"]), _target_str(String(syn["absent_target"]))]
		"multipleBonus":
			return "×%s if %d+ %s" % [_fmt_num(float(syn["multiplier"])), int(syn["requires"]), _targets_str(syn["targets"])]
		"roundBonus":
			return "+%d on %s rounds" % [int(syn["bonus"]), String(syn["round_type"])]
		"spinCounter":
			return "+%d per spin" % int(syn["bonus"])
		"runningTotal":
			return "+%d per destroyed (max %d)" % [int(syn["bonus"]), int(syn["cap"])]
		"globalReward":
			return "While %s present: +%d %s/spin" % [
				_target_str(String(syn["requires"])), int(syn["amount"]), _reward_str(syn["reward"])
			]
	return ""


# Godot's String format has no %g; trim a float to a clean display string
# (3 -> "3", 1.5 -> "1.5") for the synergy multiplier lines on draft cards.
func _fmt_num(x: float) -> String:
	if x == floor(x):
		return str(int(x))
	return String.num(x, 2).trim_suffix("0").trim_suffix(".")


func _targets_str(targets) -> String:
	var parts := PackedStringArray()
	for tgt in targets:
		parts.append(_target_str(String(tgt)))
	return "/".join(parts)


func _target_str(tgt: String) -> String:
	if tgt == "all":
		return "all"
	if Symbols.SYMBOLS.has(tgt):
		return String(Symbols.SYMBOLS[tgt]["name"])
	return _title_case(tgt)


func _reward_str(reward) -> String:
	match String(reward):
		"reroll_orb": return "Reroll Orb"
		"removal_orb": return "Removal Orb"
	return String(reward)


func _title_case(s: String) -> String:
	var words: PackedStringArray = s.replace("_", " ").split(" ")
	var out := PackedStringArray()
	for w in words:
		if w.length() > 0:
			out.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(out)

func _on_pick(id: String) -> void:
	pool.append(MidsummerEngine.make_tile(id))
	_close_draft()

func _on_skip() -> void:
	_close_draft()

func _on_reroll() -> void:
	if reroll_orbs <= 0:
		return
	reroll_orbs -= 1
	_update_hud()
	_open_draft()                                    # re-picks 3 fresh cards, refreshes button

func _close_draft() -> void:
	draft_layer.hide()
	_clear_cards()
	if running:
		spin_button.disabled = false
		bag_button.disabled = false

# --- bag / inventory + removal ------------------------------------------

func _on_bag_open() -> void:
	if not running:
		return
	_build_bag()
	bag_layer.show()
	spin_button.disabled = true
	bag_button.disabled = true

func _on_bag_close() -> void:
	bag_layer.hide()
	if running:
		spin_button.disabled = false
		bag_button.disabled = false

func _build_bag() -> void:
	for c in bag_grid.get_children():
		c.queue_free()
	bag_tab_symbols.text = "SYMBOLS (%d)" % pool.size()
	bag_removal_label.text = "%d Removal Orbs" % removal_orbs
	bag_helper.text = "Tap a symbol for details. Discard from there (costs 1 Removal Orb)."

	# Group identical symbols (shared id, unique uid) into one ×N tile. Removal
	# spends one uid of that id; the floor check stays on total pool size.
	var counts := {}                # id -> count
	var first_uid := {}             # id -> uid to discard when tapped
	var order: Array = []           # ids in first-seen order
	for tile in pool:
		var id: String = String(tile["id"])
		if not counts.has(id):
			counts[id] = 0
			first_uid[id] = String(tile["uid"])
			order.append(id)
		counts[id] += 1

	for id in order:
		bag_grid.add_child(_make_bag_tile(id, int(counts[id]), String(first_uid[id])))


func _make_bag_tile(id: String, count: int, uid: String) -> PanelContainer:
	var sym: Dictionary = Symbols.SYMBOLS[id]
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(104, 116)
	# Tap = open the detail popup (never destructive). Desktop hover shows the same
	# description as a lightweight built-in tooltip.
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.tooltip_text = _card_desc(sym)
	tile.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_open_symbol_popup(id, uid)
	)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(64, 64)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture = _texture_for(id)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sprite)

	if count > 1:
		var badge := Label.new()
		badge.text = "×%d" % count
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.theme_type_variation = &"CurrencyLabel"
		badge.add_theme_font_size_override("font_size", 14)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(badge)

	var name_lbl := Label.new()
	name_lbl.text = String(sym["name"])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	tile.add_child(vbox)
	return tile

func _on_remove_tile(uid: String) -> void:
	if removal_orbs <= 0 or pool.size() <= 3:        # keep at least 3 tiles
		return
	for i in pool.size():
		if String(pool[i]["uid"]) == uid:
			pool.remove_at(i)
			removal_orbs -= 1
			break
	_update_hud()
	_build_bag()                                     # refresh (and re-evaluate disabled state)

# --- bag symbol detail popup ---------------------------------------------

# Tap a bag tile to inspect it. The detail body reuses the draft-card rendering;
# discard happens only via the Discard button below (a plain tap is non-destructive).
func _open_symbol_popup(id: String, uid: String) -> void:
	_popup_uid = uid
	for c in popup_detail.get_children():
		c.queue_free()
	popup_detail.add_child(_make_detail_body(id))
	# Discard availability mirrors _on_remove_tile's guards (orbs first, then floor).
	if removal_orbs <= 0:
		popup_discard.disabled = true
		popup_hint.text = "No Removal Orbs"
	elif pool.size() <= 3:
		popup_discard.disabled = true
		popup_hint.text = "Can't go below 3"
	else:
		popup_discard.disabled = false
		popup_hint.text = "Spend 1 Removal Orb to discard."
	symbol_popup_layer.show()

func _close_symbol_popup() -> void:
	symbol_popup_layer.hide()

func _on_popup_discard() -> void:
	_on_remove_tile(_popup_uid)                      # spends orb + rebuilds bag (guards re-checked)
	_close_symbol_popup()

func _clear_cards() -> void:
	for c in draft_cards.get_children():
		c.queue_free()

# --- rendering -----------------------------------------------------------

func _render_grid() -> void:
	for i in _cells.size():
		var tile = grid[i] if i < grid.size() else null
		_cells[i].texture = _texture_for(tile["id"]) if tile != null else null
		_cells[i].visible = true                 # restore after a reel spin hid them

func _texture_for(id: String) -> Texture2D:
	return load(SPRITE_DIR + String(Symbols.SYMBOLS[id]["sprite"]))

func _update_hud() -> void:
	var idx: int = clampi(tithe_round, 0, 11)
	var cost := int(schedule[idx]["orbs"])
	var spins_total := int(schedule[idx]["spins"])
	var spins_left: int = maxi(spins_total - spin_in_cycle, 0)
	var round_disp: int = clampi(tithe_round + 1, 1, 12)

	# HUD (above the cabinet): three currency chips + a sub-line.
	orb_chip.text = "%d" % orbs
	reroll_chip.text = "%d" % reroll_orbs
	removal_chip.text = "%d" % removal_orbs
	sub_line.text = "Spin %d/%d · Tithe %d/12: %d/%d" % [
		spin_in_cycle, spins_total, round_disp, orbs, cost,
	]

	# In-frame status (below the grid, inside the frame).
	season_round.text = "%s · ROUND %d" % [_season(tithe_round).to_upper(), round_disp]
	spins_to_bell.text = "%d spins to the bell" % spins_left
	tithe_bar.max_value = maxi(cost, 1)
	tithe_bar.value = clampi(orbs, 0, cost)

	_update_background()

func _update_background() -> void:
	# Dim at First Light, brightest/warmest at Midnight Sun (tithes 10-12).
	var t: float = clampf(float(tithe_round) / 11.0, 0.0, 1.0)
	var b: float = lerpf(0.55, 1.2, t)               # >1 brightens past midsummer
	background.modulate = Color(b, b * 0.99, b * 0.9)  # subtle warm shift

func _season(round_idx: int) -> String:
	var t := round_idx + 1                           # 1-based tithe number
	if t <= 3:
		return "First Light"
	elif t <= 6:
		return "Sun's Climb"
	elif t <= 9:
		return "Golden Sun"
	else:
		return "Midnight Sun"
