# test_scene.gd
# Click-path regression for the Phase 3b toolkit (reroll spend + bag removal).
# The headless --quit-after boot only catches parse/_ready errors; it never
# exercises the button handlers. This drives them directly. Run headless:
#
#   godot --headless --script res://tests/test_scene.gd
#
# Exit 0 = all pass, 1 = a failure.
extends SceneTree

var _passed := 0
var _failed := 0

func _initialize() -> void:
	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame               # let _ready() fire on the scene nodes

	await _test_reroll(scene)
	_test_bag_removal(scene)
	_test_removal_floor(scene)

	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s" % label)


func _test_reroll(scene: Control) -> void:
	scene.reroll_orbs = 2
	scene._open_draft()
	_ok(scene.draft_cards.get_child_count() == 3, "reroll: draft offers 3 cards")
	_ok(not scene.reroll_button.disabled, "reroll: button enabled at 2 orbs")
	scene._on_reroll()
	_ok(scene.reroll_orbs == 1, "reroll: spends one orb (2->1)")
	await process_frame               # flush the deferred queue_free of the old cards
	_ok(scene.draft_cards.get_child_count() == 3, "reroll: re-picks a fresh 3")
	scene.reroll_orbs = 0
	scene._open_draft()
	_ok(scene.reroll_button.disabled, "reroll: button greyed at 0 orbs")
	scene._close_draft()


func _test_bag_removal(scene: Control) -> void:
	_ok(scene.pool.size() > 3, "bag: starting pool above the floor")
	scene.removal_orbs = 1
	var n: int = scene.pool.size()
	var uid: String = String(scene.pool[0]["uid"])
	scene._on_remove_tile(uid)
	_ok(scene.pool.size() == n - 1, "bag: pool shrinks by one")
	_ok(scene.removal_orbs == 0, "bag: spends one removal orb")
	var still_present := false
	for t in scene.pool:
		if String(t["uid"]) == uid:
			still_present = true
	_ok(not still_present, "bag: the targeted uid is gone")


func _test_removal_floor(scene: Control) -> void:
	scene.pool = scene.pool.slice(0, 3)   # exactly the 3-tile floor
	scene.removal_orbs = 1
	var uid: String = String(scene.pool[0]["uid"])
	scene._on_remove_tile(uid)
	_ok(scene.pool.size() == 3, "floor: removal blocked at 3 tiles")
	_ok(scene.removal_orbs == 1, "floor: orb not spent when blocked")
