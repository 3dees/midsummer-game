# test_engine.gd
# Golden-case runner for the GDScript engine port. Proves engine.gd scores
# identically to the TypeScript engine. Run headless from the project root:
#
#   godot --headless --script res://tests/test_engine.gd
#
# Loads res://spec/golden-cases.json (copied from harness/spec/golden-cases.json).
# Exit code 0 = all pass, 1 = a failure. Prints any mismatches.
extends SceneTree

func _init() -> void:
	var path := "res://spec/golden-cases.json"
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("Could not read %s (copy it from harness/spec/)" % path)
		quit(1)
		return
	var data = JSON.parse_string(text)
	if data == null or not data.has("cases"):
		push_error("Bad golden-cases.json")
		quit(1)
		return

	var passed := 0
	var failed := 0
	for c in data["cases"]:
		var grid := _build_grid(c["grid"])
		var ctx := _build_ctx(c.get("ctx", {}))
		var r := MidsummerEngine.score_grid(grid, ctx)
		var exp: Dictionary = c["expect"]
		var msgs: Array = []

		if r["orbs"] != int(exp["orbs"]):
			msgs.append("orbs %d != %d" % [r["orbs"], int(exp["orbs"])])
		if r["reroll_orbs_gained"] != int(exp.get("reroll", 0)):
			msgs.append("reroll %d != %d" % [r["reroll_orbs_gained"], int(exp.get("reroll", 0))])
		if r["removal_orbs_gained"] != int(exp.get("removal", 0)):
			msgs.append("removal %d != %d" % [r["removal_orbs_gained"], int(exp.get("removal", 0))])
		if exp.has("perCell"):
			for k in exp["perCell"].keys():
				var idx := int(k)
				if r["per_cell"][idx] != int(exp["perCell"][k]):
					msgs.append("perCell[%d] %d != %d" % [idx, r["per_cell"][idx], int(exp["perCell"][k])])

		if msgs.is_empty():
			passed += 1
		else:
			failed += 1
			print("FAIL  %s  ->  %s" % [c["name"], ", ".join(msgs)])

	print("\n%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _build_grid(grid_map: Dictionary) -> Array:
	var grid: Array = []
	grid.resize(MidsummerEngine.GRID_SIZE)
	for i in MidsummerEngine.GRID_SIZE:
		grid[i] = null
	for k in grid_map.keys():
		grid[int(k)] = MidsummerEngine.make_tile(grid_map[k])
	return grid


# Golden cases use camelCase ctx keys; the engine uses snake_case. Map them here.
func _build_ctx(raw: Dictionary) -> Dictionary:
	return {
		"total_spins": int(raw.get("totalSpins", 0)),
		"round_number": int(raw.get("roundNumber", 0)),
		"appearance_counts": raw.get("appearanceCounts", {}),
		"destroyed_this_run": int(raw.get("destroyedThisRun", 0)),
		"alternating_tick": bool(raw.get("alternatingTick", false)),
	}
