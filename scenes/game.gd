# game.gd
# Minimal playable Midsummer Slots loop: spin -> score -> draft -> tithe -> win/lose.
# Ported from the play.tsx reducer, trimmed to the v1 core (no inventory, reroll/
# removal spending, reveal animation, or polished overlays). Wired to
# MidsummerEngine (scoring) + Symbols (registry).
extends Control

const COLS := 5
const ROWS := 4
const SPRITE_DIR := "res://midsummer/assets/sprites/"

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

@onready var hud: Label = $Layout/Hud
@onready var grid_box: GridContainer = $Layout/Grid
@onready var spin_button: Button = $Layout/SpinButton
@onready var draft_panel: PanelContainer = $DraftPanel
@onready var draft_cards: HBoxContainer = $DraftPanel/DraftBox/DraftCards
@onready var skip_button: Button = $DraftPanel/DraftBox/SkipButton
@onready var message_label: Label = $MessageLabel

var _cells: Array = []               # the 20 TextureRect grid cells

func _ready() -> void:
	_build_cells()
	spin_button.pressed.connect(_on_spin)
	skip_button.pressed.connect(_on_skip)
	_start_run()

func _build_cells() -> void:
	grid_box.columns = COLS
	for i in COLS * ROWS:
		var cell := TextureRect.new()
		cell.custom_minimum_size = Vector2(110, 110)
		cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid_box.add_child(cell)
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
	draft_panel.hide()
	spin_button.disabled = false

func _on_spin() -> void:
	if not running:
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
	orbs += int(score["orbs"])                       # accumulate (carry-over)
	reroll_orbs += int(score["reroll_orbs_gained"])
	removal_orbs += int(score["removal_orbs_gained"])
	appearance_counts = score["appearance_counts_next"]
	total_spins += 1
	alternating_tick = not alternating_tick
	spin_in_cycle += 1
	_render_grid()
	_update_hud()

	# Tithe check: did this spin complete the cycle?
	if spin_in_cycle >= int(schedule[tithe_round]["spins"]):
		_resolve_tithe()
		if not running:
			return
	# Draft after every spin (uses the possibly-advanced tithe_round).
	_open_draft()

func _resolve_tithe() -> void:
	var cost := int(schedule[tithe_round]["orbs"])
	if orbs >= cost:
		orbs -= cost                                 # keep the surplus (carry-over)
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
	draft_panel.hide()
	message_label.text = "Crowned of Midsummer. The solstice fire is lit."
	message_label.show()
	_update_hud()

func _lose(cost: int) -> void:
	running = false
	spin_button.disabled = true
	draft_panel.hide()
	message_label.text = "The fire gutters — needed %d orbs, had %d.\nThe forest reclaims you." % [cost, orbs]
	message_label.show()

# --- draft ---------------------------------------------------------------

func _open_draft() -> void:
	spin_button.disabled = true
	_clear_cards()
	var offers: Array = MidsummerEngine.pick_draft(Symbols.DRAFT_POOL, tithe_round)
	for id in offers:
		draft_cards.add_child(_make_card(id))
	draft_panel.show()

func _make_card(id: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(120, 168)
	b.icon = _texture_for(id)
	b.text = String(Symbols.SYMBOLS[id]["name"])
	b.expand_icon = true
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(_on_pick.bind(id))
	return b

func _on_pick(id: String) -> void:
	pool.append(MidsummerEngine.make_tile(id))
	_close_draft()

func _on_skip() -> void:
	_close_draft()

func _close_draft() -> void:
	draft_panel.hide()
	_clear_cards()
	if running:
		spin_button.disabled = false

func _clear_cards() -> void:
	for c in draft_cards.get_children():
		c.queue_free()

# --- rendering -----------------------------------------------------------

func _render_grid() -> void:
	for i in _cells.size():
		var tile = grid[i] if i < grid.size() else null
		_cells[i].texture = _texture_for(tile["id"]) if tile != null else null

func _texture_for(id: String) -> Texture2D:
	return load(SPRITE_DIR + String(Symbols.SYMBOLS[id]["sprite"]))

func _update_hud() -> void:
	var idx: int = clampi(tithe_round, 0, 11)
	var cost := int(schedule[idx]["orbs"])
	var spins_total := int(schedule[idx]["spins"])
	var spins_left: int = spins_total - spin_in_cycle
	var round_disp: int = clampi(tithe_round + 1, 1, 12)
	hud.text = "Tithe %d/12 · %s · %d/%d · spins %d · ✨%d ↺%d ✕%d" % [
		round_disp, _season(tithe_round), orbs, cost, spins_left,
		orbs, reroll_orbs, removal_orbs,
	]

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
