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
@onready var mute_button: Button = $Layout/HudPanel/HudBox/HudTop/MuteButton
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
@onready var message_label: Label = $MessageLabel
@onready var log_lines: VBoxContainer = $Layout/SpinLog/LogScroll/LogLines

# --- Tier 4 score-reveal timing (ported from play.tsx reveal logic) ---
const REVEAL_FLOAT_LINGER := 0.78   # "+N" float rise + fade duration (~780ms)
const PASS1_CADENCE := 0.07         # Pass 1 base-score sweep cadence (70ms)
const PASS_PAUSE := 0.25            # pause between Pass 1 and Pass 2 (250ms)
const PASS2_CADENCE := 0.16         # Pass 2 synergy sweep cadence (160ms)
const BOUNCE_HOP := 14.0            # vertical hop height (px) for the synergy bounce
const BOUNCE_DUR := 0.32            # total hop duration (~320ms)
const DRAFT_PAUSE := 0.35          # beat after the last bounce settles before the draft opens
var _revealing := false

# --- Tier 5 slot-reel spin timing ---
const SPIN_SPEED := 1800.0          # constant reel scroll speed, px/s (same for every column)
const SPIN_BASE_DURATION := 0.42    # column 0 stop time; later columns spin longer at the same speed
const SPIN_COL_STAGGER := 0.10      # stagger between column stops, left -> right (100ms)
const SPIN_SETTLE := 0.16           # final overshoot-settle segment per column (TRANS_BACK)
const SPIN_CELL_INSET := 4.0        # inset reel symbols to match the settled sprite (slot content margin)
const SPIN_BLUR := 0.018            # vertical-blur strength while spinning (eased to 0)
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

func _ready() -> void:
	_apply_grid_rect()
	_build_cells()
	spin_button.pressed.connect(_on_spin)
	skip_button.pressed.connect(_on_skip)
	reroll_button.pressed.connect(_on_reroll)
	bag_button.pressed.connect(_on_bag_open)
	draft_bag_button.pressed.connect(_on_bag_open)
	bag_close.pressed.connect(_on_bag_close)
	mute_button.pressed.connect(_on_toggle_music)
	# mp3 streams don't carry a loop flag from import; set it so the theme loops.
	if music.stream is AudioStreamMP3:
		music.stream.loop = true
	_start_run()

func _on_toggle_music() -> void:
	var bus := AudioServer.get_bus_index("Music")
	var muted := not AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus, muted)
	mute_button.text = "Music: Off" if muted else "Music: On"

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
	await get_tree().process_frame              # ensure the grid has a laid-out size
	var cw := grid_box.size.x / float(COLS)
	var ch := grid_box.size.y / float(ROWS)
	if cw <= 0.0 or ch <= 0.0:                   # no layout (e.g. headless) — skip cleanly
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
		var colctrl := Control.new()
		colctrl.position = Vector2(c * cw, 0.0)
		colctrl.size = Vector2(cw, ch * ROWS)
		colctrl.clip_contents = true
		colctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(colctrl)

		var strip := Control.new()
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat: ShaderMaterial = _reel_mats[c]
		mat.set_shader_parameter("strength", SPIN_BLUR)
		strip.material = mat
		colctrl.add_child(strip)

		# Filler count sized so a constant-speed scroll lasts this column's stop time.
		var stop_t := SPIN_BASE_DURATION + c * SPIN_COL_STAGGER
		var n_filler: int = maxi(ROWS + 6, int(round(SPIN_SPEED * stop_t / ch)))
		for f in n_filler:
			_add_reel_cell(strip, _spin_textures[randi() % _spin_textures.size()], f, cw, ch)
		for r in ROWS:
			var idx: int = r * COLS + c
			var tile = final_grid[idx] if idx < final_grid.size() else null
			var tex: Texture2D = _texture_for(String(tile["id"])) if tile != null else null
			_add_reel_cell(strip, tex, n_filler + r, cw, ch)
		strip.position.y = 0.0                   # start with fillers in view

		# Constant-speed linear scroll, then a short overshoot settle onto the finals.
		var rest := -n_filler * ch
		var settle_d := ch * 0.5
		var lin_dur: float = (n_filler * ch - settle_d) / SPIN_SPEED
		var tw := create_tween()
		tw.tween_property(strip, "position:y", rest + settle_d, lin_dur).set_trans(Tween.TRANS_LINEAR)
		tw.tween_property(strip, "position:y", rest, SPIN_SETTLE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var dur := lin_dur + SPIN_SETTLE
		max_dur = max(max_dur, dur)
		var mtw := create_tween()                # ease the blur off over the back half
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

func _add_reel_cell(strip: Control, tex: Texture2D, row: int, cw: float, ch: float) -> void:
	var rc := TextureRect.new()
	rc.texture = tex
	# Inset to match the settled sprite (slot content margin) — no size-pop on handoff.
	rc.position = Vector2(SPIN_CELL_INSET, row * ch + SPIN_CELL_INSET)
	rc.size = Vector2(cw - 2.0 * SPIN_CELL_INSET, ch - 2.0 * SPIN_CELL_INSET)
	rc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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

# Two-pass (LBaL-style) reveal. Pass 1: float each cell's printed base value in
# reading order (fast, no bounce). Pass 2: walk the synergy events in anchor-cell
# order, bouncing each synergy's cells together and floating its bonus. Running
# total shows on the HUD Light chip; snapped to the authoritative score at the end.
func _play_reveal(score: Dictionary) -> void:
	_revealing = true
	_reset_reveal()
	var events: Array = score["events"]
	var syn_events: Array = []
	for ev in events:
		if String(ev["kind"]) == "synergy":
			syn_events.append(ev)

	# Header line for the log.
	var head := Label.new()
	head.theme_type_variation = &"CurrencyLabel"
	head.add_theme_font_size_override("font_size", 14)
	head.text = "Spin %d · +%d Light" % [total_spins + 1, int(score["orbs"])]
	log_lines.add_child(head)

	var run := 0

	# --- Pass 1: base scores, reading order, fast, no bounce ---
	for i in _cells.size():
		var tile = grid[i] if i < grid.size() else null
		if tile == null:
			continue
		var base := int(Symbols.SYMBOLS[String(tile["id"])]["base_value"])
		if base <= 0:
			continue
		run += base
		orb_chip.text = "%d" % (orbs + run)
		_spawn_float(i, base)
		await get_tree().create_timer(PASS1_CADENCE).timeout

	# --- Pass 2: synergies, ordered by anchor (earliest cell), bounce + bonus ---
	if not syn_events.is_empty():
		await get_tree().create_timer(PASS_PAUSE).timeout
		syn_events.sort_custom(func(a, b): return _anchor_cell(a) < _anchor_cell(b))
		for ev in syn_events:
			var anchor := _anchor_cell(ev)
			# Score synergies bounce their whole group; plain reward-orb triggers
			# (reroll/removal) only flash their float — no bounce.
			var is_score_synergy: bool = ev.has("orbs_delta") or ev.has("multiplier")
			if is_score_synergy:
				for ci in ev.get("cells", [int(ev["cell"])]):
					_bounce_cell(int(ci))
			if ev.has("orbs_delta"):
				run += int(ev["orbs_delta"])
				orb_chip.text = "%d" % (orbs + run)
				_spawn_float(anchor, int(ev["orbs_delta"]))
			elif ev.has("multiplier"):
				_spawn_text(anchor, "×%s" % _fmt_num(float(ev["multiplier"])))
			elif ev.has("reward_amount"):
				_spawn_text(anchor, "+%d %s" % [int(ev["reward_amount"]), _reward_str(ev.get("reward_kind", ""))])
			_add_log_line(ev)
			await get_tree().create_timer(PASS2_CADENCE).timeout

	# Snap to the authoritative total (absorbs multiplier / rounding) before commit.
	orb_chip.text = "%d" % (orbs + int(score["orbs"]))
	# Let the final bounce fully settle, then a slight beat, before the draft opens.
	if not syn_events.is_empty():
		await get_tree().create_timer(BOUNCE_DUR).timeout
	await get_tree().create_timer(DRAFT_PAUSE).timeout
	_revealing = false

# Earliest (reading-order) cell of a synergy event — its anchor for ordering.
func _anchor_cell(ev: Dictionary) -> int:
	var cells: Array = ev.get("cells", [int(ev["cell"])])
	var m := int(ev["cell"])
	for c in cells:
		m = min(m, int(c))
	return m

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
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(f, "position:y", f.position.y - 26.0, REVEAL_FLOAT_LINGER)
	tw.tween_property(f, "modulate:a", 0.0, REVEAL_FLOAT_LINGER).set_delay(REVEAL_FLOAT_LINGER * 0.45)
	tw.finished.connect(func() -> void:
		if is_instance_valid(f):
			f.queue_free()
	)

# Vertical hop with squash-and-stretch. Animates the cell sprite's own offset/
# scale (not its GridContainer slot) so the container doesn't fight the motion.
func _bounce_cell(i: int) -> void:
	var cell: TextureRect = _cells[i]
	cell.pivot_offset = cell.size * 0.5
	var base_y := cell.position.y
	# Position: rise (sine out), then fall + overshoot settle (back out).
	var pt := create_tween()
	pt.tween_property(cell, "position:y", base_y - BOUNCE_HOP, BOUNCE_DUR * 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pt.tween_property(cell, "position:y", base_y, BOUNCE_DUR * 0.68).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Scale: stretch tall on the way up, squash wide on landing, recover.
	var st := create_tween()
	st.tween_property(cell, "scale", Vector2(0.92, 1.12), BOUNCE_DUR * 0.32).set_ease(Tween.EASE_OUT)
	st.tween_property(cell, "scale", Vector2(1.12, 0.9), BOUNCE_DUR * 0.30)
	st.tween_property(cell, "scale", Vector2.ONE, BOUNCE_DUR * 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _reset_reveal() -> void:
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
		if tithe_round >= 12:
			_win()
		else:
			_update_hud()
	else:
		_lose(cost)

func _win() -> void:
	running = false
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
	var sym: Dictionary = Symbols.SYMBOLS[id]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_pick(id)
	)

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

	panel.add_child(vbox)
	return panel


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
	bag_helper.text = ("Tap a symbol to discard it (costs 1 Removal Orb)." if removal_orbs > 0
		else "Earn Removal Orbs from spins to discard symbols from your bag.")

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

	var can_remove := removal_orbs > 0 and pool.size() > 3
	for id in order:
		bag_grid.add_child(_make_bag_tile(id, int(counts[id]), String(first_uid[id]), can_remove))


func _make_bag_tile(id: String, count: int, uid: String, can_remove: bool) -> PanelContainer:
	var sym: Dictionary = Symbols.SYMBOLS[id]
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(104, 116)
	if can_remove:
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_remove_tile(uid)
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
