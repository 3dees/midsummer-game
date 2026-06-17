# engine.gd
# Pure game logic for Midsummer Slots, ported from engine.ts. No Godot/UI deps.
# Drop into res://midsummer/. Verify with test_engine.gd (golden cases) BEFORE any UI.
#
# Data shapes (kept Dictionary-based to mirror the data-driven TS engine):
#   tile  : { "uid": String, "id": String, "age": int }
#   grid  : Array of (tile | null), length GRID_SIZE, reading order (row*5 + col)
#   ctx   : { "total_spins": int, "round_number": int,
#             "appearance_counts": Dictionary, "destroyed_this_run": int,
#             "alternating_tick": bool }
#
# Symbol defs + symbol_matches() live in Symbols (symbols.gd, class_name Symbols).
# A symbol def: { "name", "rarity", "base_value": int, "tags": Array[String],
#                 "synergies": Array[Dictionary] }.  Synergy dicts use snake_case
# keys: type, targets, bonus, multiplier, requires, threshold, reward, amount,
#       every, chance, round_type, tracks, cap, present_target, absent_target.
class_name MidsummerEngine

const GRID_COLS := 5
const GRID_ROWS := 4
const GRID_SIZE := 20

const BASE_TITHE_COSTS := [25, 50, 100, 150, 225, 300, 375, 450, 575, 650, 700, 777]
const TITHE_SPINS := [5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10]
const DIFFICULTY := 1.5  # playtest value — restore to 3.2 once reroll/removal spending are in
const REMOVAL_ORB_CAP := 3

static var _uid := 0

# Per-tithe schedule: [{ "spins": int, "orbs": int }, ...]  (cost = base * DIFFICULTY)
static func tithe_schedule() -> Array:
	var out: Array = []
	for i in BASE_TITHE_COSTS.size():
		out.append({ "spins": TITHE_SPINS[i], "orbs": int(round(BASE_TITHE_COSTS[i] * DIFFICULTY)) })
	return out

static func make_tile(id: String) -> Dictionary:
	_uid += 1
	return { "uid": "t%d-%s" % [_uid, str(randi()).substr(0, 5)], "id": id, "age": 0 }

# --- helpers -------------------------------------------------------------

static func _neighbors(index: int) -> Array:
	var r := index / GRID_COLS
	var c := index % GRID_COLS
	var out: Array = []
	if r > 0: out.append(index - GRID_COLS)
	if r < GRID_ROWS - 1: out.append(index + GRID_COLS)
	if c > 0: out.append(index - 1)
	if c < GRID_COLS - 1: out.append(index + 1)
	return out

static func _ids_of(grid: Array) -> Array:
	var out: Array = []
	for t in grid:
		out.append(t["id"] if t != null else null)
	return out

static func _matches_any(targets: Array, id: String) -> bool:
	for t in targets:
		if Symbols.symbol_matches(t, id):
			return true
	return false

static func _grid_has(ids: Array, target: String) -> bool:
	for id in ids:
		if id != null and Symbols.symbol_matches(target, id):
			return true
	return false

static func _grid_count(ids: Array, targets: Array) -> int:
	var n := 0
	for id in ids:
		if id != null and _matches_any(targets, id):
			n += 1
	return n

# Place exact pool tiles into random cells, leaving the rest null.
static func roll_grid(pool: Array) -> Array:
	var grid: Array = []
	grid.resize(GRID_SIZE)
	for i in GRID_SIZE: grid[i] = null
	var indexes: Array = []
	for i in GRID_SIZE: indexes.append(i)
	indexes.shuffle()
	var tiles := pool.duplicate()
	tiles.shuffle()
	var fill_count: int = min(tiles.size(), GRID_SIZE)
	for k in fill_count:
		grid[indexes[k]] = tiles[k]
	return grid

# --- the scorer ----------------------------------------------------------
# Returns: { "orbs": int, "reroll_orbs_gained": int, "removal_orbs_gained": int,
#            "per_cell": Array[int], "contributing_cells": Array[int],
#            "appearance_counts_next": Dictionary, "events": Array }
static func score_grid(tile_grid: Array, ctx: Dictionary) -> Dictionary:
	var ids := _ids_of(tile_grid)
	var per_cell: Array = []
	var mult_cell: Array = []
	per_cell.resize(GRID_SIZE)
	mult_cell.resize(GRID_SIZE)
	for i in GRID_SIZE:
		per_cell[i] = 0
		mult_cell[i] = 1.0

	var contributing := {}            # set: Dictionary[int -> true]
	var events: Array = []
	var green_man_on := _grid_has(ids, "green_man")
	var green_man_tags := { "forest_floor": true, "flower": true }
	var rewards := { "light_orbs": 0, "reroll_orb": 0, "removal_orb": 0 }
	var fired := {}                   # dedup one-shot globals, key = id + ":" + type

	# 1. base values
	for i in GRID_SIZE:
		var id = ids[i]
		if id == null: continue
		per_cell[i] = Symbols.SYMBOLS[id]["base_value"]
		if per_cell[i] > 0:
			contributing[i] = true
			events.append({ "kind": "base", "cell": i, "id": id, "orbs": per_cell[i] })

	# 2. synergies
	for i in GRID_SIZE:
		var id = ids[i]
		if id == null: continue
		for syn in Symbols.SYMBOLS[id]["synergies"]:
			match syn["type"]:
				"adjacentBonus":
					if syn["targets"].has("all"):
						for n in _neighbors(i):
							if ids[n] == null: continue
							per_cell[n] += syn["bonus"]
							contributing[n] = true
							events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "orbs_delta": syn["bonus"], "cells": [i, n] })
						contributing[i] = true
					else:
						var use_global := green_man_on and _targets_hit_tags(syn["targets"], green_man_tags)
						var scan: Array = []
						if use_global:
							for k in GRID_SIZE:
								if k != i: scan.append(k)
						else:
							scan = _neighbors(i)
						var matches := 0
						for n in scan:
							var nid = ids[n]
							if nid != null and _matches_any(syn["targets"], nid):
								matches += 1
						if matches > 0:
							per_cell[i] += syn["bonus"] * matches
							contributing[i] = true
							events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "orbs_delta": syn["bonus"] * matches, "green_man_boost": use_global, "cells": [i] })
				"globalBonus":
					if syn["targets"].has("all"):
						var affected: Array = [i]
						for j in GRID_SIZE:
							if j == i or ids[j] == null: continue
							per_cell[j] += syn["bonus"]
							contributing[j] = true
							affected.append(j)
						contributing[i] = true
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "orbs_delta": syn["bonus"], "cells": affected })
					else:
						var matches := 0
						for j in GRID_SIZE:
							if j == i or ids[j] == null: continue
							if _matches_any(syn["targets"], ids[j]):
								matches += 1
						if matches > 0:
							per_cell[i] += syn["bonus"] * matches
							contributing[i] = true
							events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "orbs_delta": syn["bonus"] * matches, "cells": [i] })
				"globalMultiplier":
					var count := _grid_count(ids, syn["targets"])
					if not (syn.has("requires") and count < syn["requires"]):
						var touched := false
						var mult_cells: Array = [i]
						for j in GRID_SIZE:
							if ids[j] == null: continue
							if _matches_any(syn["targets"], ids[j]):
								mult_cell[j] *= syn["multiplier"]
								contributing[j] = true
								touched = true
								if j != i: mult_cells.append(j)
						if touched:
							events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "multiplier": syn["multiplier"], "cells": mult_cells })
				"multipleBonus":
					if _grid_count(ids, syn["targets"]) >= syn["requires"]:
						mult_cell[i] *= syn["multiplier"]
						contributing[i] = true
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "multiplier": syn["multiplier"], "cells": [i] })
				"conditionalBonus":
					var present: bool = (not syn.has("present_target")) or _grid_has(ids, syn["present_target"])
					var absent: bool = (not syn.has("absent_target")) or (not _grid_has(ids, syn["absent_target"]))
					if present and absent:
						per_cell[i] += syn["bonus"]
						contributing[i] = true
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "orbs_delta": syn["bonus"], "cells": [i] })
				"selfChance":
					if randf() < syn["chance"]:
						mult_cell[i] *= syn["multiplier"]
						contributing[i] = true
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "multiplier": syn["multiplier"], "cells": [i] })
				"globalCountReward":
					var key: String = str(id) + ":globalCountReward"
					if _grid_count(ids, syn["targets"]) >= syn["threshold"] and not fired.has(key):
						fired[key] = true
						rewards[syn["reward"]] += syn["amount"]
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "reward_kind": syn["reward"], "reward_amount": syn["amount"], "cells": [i] })
				"globalReward":
					var key2: String = str(id) + ":globalReward"
					if _grid_has(ids, syn["requires"]) and not fired.has(key2):
						fired[key2] = true
						rewards[syn["reward"]] += syn["amount"]
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "reward_kind": syn["reward"], "reward_amount": syn["amount"], "cells": [i] })
				"periodicReward":
					# dedup per symbol id per spin (matches the engine.ts fix)
					var key3: String = str(id) + ":periodicReward"
					if not fired.has(key3):
						fired[key3] = true
						var before: int = ctx["appearance_counts"].get(id, 0)
						var after := before + 1
						var crossings := int(after / syn["every"]) - int(before / syn["every"])
						if crossings > 0:
							rewards[syn["reward"]] += syn["amount"] * crossings
							contributing[i] = true
							events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "reward_kind": syn["reward"], "reward_amount": syn["amount"] * crossings, "cells": [i] })
				"alternating":
					if ctx["alternating_tick"]:
						mult_cell[i] *= syn["multiplier"]
						contributing[i] = true
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "multiplier": syn["multiplier"], "cells": [i] })
				"roundBonus":
					var is_odd: bool = (int(ctx["round_number"]) % 2) == 1
					var match_round: bool = is_odd if syn["round_type"] == "odd" else not is_odd
					if match_round:
						var n := _grid_count(ids, syn["targets"])
						if n > 0:
							per_cell[i] += syn["bonus"] * n
							contributing[i] = true
							events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "orbs_delta": syn["bonus"] * n, "cells": [i] })
				"roundPenalty":
					var is_odd2: bool = (int(ctx["round_number"]) % 2) == 1
					var match_round2: bool = is_odd2 if syn["round_type"] == "odd" else not is_odd2
					if match_round2:
						mult_cell[i] *= syn["multiplier"]
						contributing[i] = true
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "multiplier": syn["multiplier"], "cells": [i] })
				"spinCounter":
					# age-based, capped (matches the Othala fix)
					var age: int = tile_grid[i]["age"] if tile_grid[i] != null else 0
					var steps: int = (min(age, int(syn["cap"])) if syn.has("cap") else age)
					if steps > 0:
						per_cell[i] += syn["bonus"] * steps
						contributing[i] = true
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "orbs_delta": syn["bonus"] * steps, "cells": [i] })
				"runningTotal":
					var tracked: int = (int(ctx["destroyed_this_run"]) if syn["tracks"] == "destroyed_symbols" else 0)
					var capped: int = min(tracked, syn["cap"])
					per_cell[i] += syn["bonus"] * capped
					if capped > 0:
						contributing[i] = true
						events.append({ "kind": "synergy", "cell": i, "id": id, "synergy_type": syn["type"], "orbs_delta": syn["bonus"] * capped, "cells": [i] })
				_:
					# v2 placeholders (transform, destroyAdjacent, sacrifice, etc.)
					# are intentionally no-ops, exactly like engine.ts.
					pass

	# 3. fold multipliers, clamp at 0
	for i in GRID_SIZE:
		per_cell[i] = max(0, int(round(per_cell[i] * mult_cell[i])))

	# 4. advance per-id appearance counts (one tick per id present this spin)
	var appearance_next: Dictionary = ctx["appearance_counts"].duplicate()
	var seen := {}
	for id in ids:
		if id != null: seen[id] = true
	for id in seen.keys():
		appearance_next[id] = appearance_next.get(id, 0) + 1

	var total: int = rewards["light_orbs"]
	for v in per_cell:
		total += v

	return {
		"orbs": total,
		"reroll_orbs_gained": rewards["reroll_orb"],
		"removal_orbs_gained": rewards["removal_orb"],
		"per_cell": per_cell,
		"contributing_cells": contributing.keys(),
		"appearance_counts_next": appearance_next,
		"events": events,
	}

static func _targets_hit_tags(targets: Array, tag_set: Dictionary) -> bool:
	for t in targets:
		if tag_set.has(t):
			return true
	return false

# Rarity-weighted, season-gated draft. titheIndex is 0-based.
static func pick_draft(candidates: Array, tithe_index: int) -> Array:
	var by_rarity := { "common": [], "uncommon": [], "rare": [] }
	for id in candidates:
		var r: String = Symbols.SYMBOLS[id]["rarity"]
		if by_rarity.has(r):
			by_rarity[r].append(id)

	var common_threshold := 0.65
	var uncommon_threshold := 1.0
	if tithe_index <= 2:
		common_threshold = 0.65; uncommon_threshold = 1.0
	elif tithe_index <= 5:
		common_threshold = 0.64; uncommon_threshold = 0.94
	elif tithe_index <= 8:
		common_threshold = 0.57; uncommon_threshold = 0.86
	else:
		common_threshold = 0.51; uncommon_threshold = 0.80

	var picked := {}
	var result: Array = []
	while result.size() < 3:
		var roll := randf()
		var rarity := "common"
		if roll < common_threshold: rarity = "common"
		elif roll < uncommon_threshold: rarity = "uncommon"
		else: rarity = "rare"
		var pool: Array = []
		for id in by_rarity[rarity]:
			if not picked.has(id): pool.append(id)
		if pool.is_empty():
			var fallback: Array = []
			for id in candidates:
				if not picked.has(id): fallback.append(id)
			if fallback.is_empty(): break
			var fid: String = fallback[randi() % fallback.size()]
			picked[fid] = true
			result.append(fid)
		else:
			var id: String = pool[randi() % pool.size()]
			picked[id] = true
			result.append(id)
	return result
