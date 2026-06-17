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

@onready var hud: Label = $Layout/Hud
@onready var grid_box: GridContainer = $Layout/Grid
@onready var spin_button: Button = $Layout/SpinButton
@onready var bag_button: Button = $Layout/BagButton
@onready var background: TextureRect = $Background
@onready var draft_panel: PanelContainer = $DraftPanel
@onready var draft_cards: HBoxContainer = $DraftPanel/DraftBox/DraftCards
@onready var reroll_button: Button = $DraftPanel/DraftBox/RerollButton
@onready var skip_button: Button = $DraftPanel/DraftBox/SkipButton
@onready var bag_panel: PanelContainer = $BagPanel
@onready var bag_list: VBoxContainer = $BagPanel/BagBox/BagScroll/BagList
@onready var bag_close: Button = $BagPanel/BagBox/BagClose
@onready var message_label: Label = $MessageLabel

var _cells: Array = []               # the 20 TextureRect grid cells

func _ready() -> void:
	_build_cells()
	spin_button.pressed.connect(_on_spin)
	skip_button.pressed.connect(_on_skip)
	reroll_button.pressed.connect(_on_reroll)
	bag_button.pressed.connect(_on_bag_open)
	bag_close.pressed.connect(_on_bag_close)
	_start_run()

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
		slot.custom_minimum_size = Vector2(110, 110)
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
	draft_panel.hide()
	bag_panel.hide()
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
	draft_panel.hide()
	bag_panel.hide()
	message_label.text = "Crowned of Midsummer. The solstice fire is lit."
	message_label.show()
	_update_hud()

func _lose(cost: int) -> void:
	running = false
	spin_button.disabled = true
	bag_button.disabled = true
	draft_panel.hide()
	bag_panel.hide()
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
	reroll_button.text = "Reroll (↺%d)" % reroll_orbs
	draft_panel.show()

func _make_card(id: String) -> PanelContainer:
	var sym: Dictionary = Symbols.SYMBOLS[id]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(130, 0)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_pick(id)
	)

	var vbox := VBoxContainer.new()

	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(80, 80)
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

	var val_lbl := Label.new()
	val_lbl.text = "+%d ◐" % int(sym["base_value"])
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(val_lbl)

	var desc: String = _card_desc(sym)
	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc_lbl)

	panel.add_child(vbox)
	return panel


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
			return "%d%% chance ×%g" % [int(float(syn["chance"]) * 100), float(syn["multiplier"])]
		"alternating":
			return "×%g every other spin" % float(syn["multiplier"])
		"periodicReward":
			return "Every %d spins: +%d %s" % [int(syn["every"]), int(syn["amount"]), _reward_str(syn["reward"])]
		"globalCountReward":
			return "%d+ on grid: +%d %s" % [int(syn["threshold"]), int(syn["amount"]), _reward_str(syn["reward"])]
		"roundPenalty":
			return "×%g on %s rounds" % [float(syn["multiplier"]), String(syn["round_type"])]
		"globalMultiplier":
			return "×%g all %s" % [float(syn["multiplier"]), _targets_str(syn["targets"])]
		"adjacentMultiplier":
			return "×%g adj %s" % [float(syn["multiplier"]), _targets_str(syn["targets"])]
		"conditionalBonus":
			if syn.has("present_target"):
				return "+%d if %s present" % [int(syn["bonus"]), _target_str(String(syn["present_target"]))]
			return "+%d if %s absent" % [int(syn["bonus"]), _target_str(String(syn["absent_target"]))]
		"multipleBonus":
			return "×%g if %d+ %s" % [float(syn["multiplier"]), int(syn["requires"]), _targets_str(syn["targets"])]
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
	draft_panel.hide()
	_clear_cards()
	if running:
		spin_button.disabled = false
		bag_button.disabled = false

# --- bag / inventory + removal ------------------------------------------

func _on_bag_open() -> void:
	if not running:
		return
	_build_bag()
	bag_panel.show()
	spin_button.disabled = true
	bag_button.disabled = true

func _on_bag_close() -> void:
	bag_panel.hide()
	if running:
		spin_button.disabled = false
		bag_button.disabled = false

func _build_bag() -> void:
	for c in bag_list.get_children():
		c.queue_free()
	var can_remove := removal_orbs > 0 and pool.size() > 3
	for tile in pool:
		var id: String = String(tile["id"])
		var uid: String = String(tile["uid"])
		var sym: Dictionary = Symbols.SYMBOLS[id]
		var row := Button.new()
		row.icon = _texture_for(id)
		row.text = "  " + String(sym["name"])
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.expand_icon = true
		row.custom_minimum_size = Vector2(340, 56)
		row.disabled = not can_remove
		row.pressed.connect(_on_remove_tile.bind(uid))
		bag_list.add_child(row)

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
	var spins_left: int = spins_total - spin_in_cycle
	var round_disp: int = clampi(tithe_round + 1, 1, 12)
	hud.text = "Tithe %d/12 · %s · %d/%d · spins %d · ✨%d ↺%d ✕%d" % [
		round_disp, _season(tithe_round), orbs, cost, spins_left,
		orbs, reroll_orbs, removal_orbs,
	]
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
