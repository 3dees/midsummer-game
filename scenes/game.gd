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
@onready var orb_chip: Label = $Layout/HudPanel/HudBox/ChipsRow/OrbChip
@onready var reroll_chip: Label = $Layout/HudPanel/HudBox/ChipsRow/RerollChip
@onready var removal_chip: Label = $Layout/HudPanel/HudBox/ChipsRow/RemovalChip
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
@onready var bag_removal_label: Label = $BagLayer/Panel/BagBox/RemovalBar/RemovalLabel
@onready var bag_helper: Label = $BagLayer/Panel/BagBox/HelperText
@onready var message_label: Label = $MessageLabel

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
	_start_run()

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
	removal_orbs = mini(removal_orbs + int(score["removal_orbs_gained"]), 3)  # cap 3
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

	var val_lbl := Label.new()
	val_lbl.text = "+%d Light" % int(sym["base_value"])
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.theme_type_variation = &"CurrencyLabel"
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(val_lbl)

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
	bag_removal_label.text = "✕ %d Removal Orbs" % removal_orbs
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

func _texture_for(id: String) -> Texture2D:
	return load(SPRITE_DIR + String(Symbols.SYMBOLS[id]["sprite"]))

func _update_hud() -> void:
	var idx: int = clampi(tithe_round, 0, 11)
	var cost := int(schedule[idx]["orbs"])
	var spins_total := int(schedule[idx]["spins"])
	var spins_left: int = maxi(spins_total - spin_in_cycle, 0)
	var round_disp: int = clampi(tithe_round + 1, 1, 12)

	# HUD (above the cabinet): three currency chips + a sub-line.
	orb_chip.text = "Light %d" % orbs
	reroll_chip.text = "Reroll %d" % reroll_orbs
	removal_chip.text = "Removal %d" % removal_orbs
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
