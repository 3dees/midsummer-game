# story.gd
# Canonical narrative text for the run loop, data-driven so it can be rewritten freely.
# Plain const holder (class_name Story, like Symbols / MidsummerEngine) — not an autoload.
#   Story.INTRO            -> 4 opening backstory beats (paced)
#   Story.SEASONS[key]     -> beat shown on entering each season
#   Story.TITHE[n]         -> {"line", "note"} shown after paying tithe n (1-11)
#   Story.WIN / Story.LOSS -> end-screen text (fed into the win/loss overlays)
# The TITHE entry carries an optional "note" so per-tithe mechanical announcements
# (e.g. "Free reroll this tithe") can be added later without restructuring.
# Accessed via `const Story = preload("res://story.gd")` in game.gd.
extends RefCounted

# Four seasons, three tithes each. Keys used by SEASONS and season_after().
const SEASON_ORDER := ["first_light", "suns_climb", "golden_sun", "midnight_sun"]

const INTRO := [
	"The light is going out of the world. A little more each year, the dark drinks it from the edges in.",
	"In the firefly hollow, you keep the last of it: a lantern, a handful of glowing things, and the will to not let them fade.",
	"Gather enough glow each season and the dark holds at the treeline. Reach the longest day, light the great Midsummer fire, and the light returns, bright enough to last another year.",
	"Let the lantern gutter, and the hollow goes dark. So begin, keeper. The first season is already turning.",
]

const SEASONS := {
	"first_light": "First Light. The world wakes thin and pale. The dark sits close, but the fireflies are stirring, and so are you. Gather what glow you can. The long climb to Midsummer starts here.",
	"suns_climb": "Sun's Climb. The ferns shake off the frost and the meadow hums awake. Good. But the shadows under the far trees sit a little deeper than they should. The sun is rising, keeper. Climb with it.",
	"golden_sun": "Golden Sun. The wood is bright and heavy with warmth now, every leaf lit gold. You are winning. The dark knows it too, and it is not done with you yet. Keep the lantern high.",
	"midnight_sun": "Midnight Sun. The longest days. The sun barely dips before it climbs again, and the solstice fire waits unlit on the hill. Three more tithes. Hold the light to the longest day, and end this.",
}

# Quick line shown after each tithe is paid (1-11). Tithe 12 triggers the win screen.
const TITHE := {
	1: {"line": "The bell rings true. The dark eases back, and the hollow glows on.", "note": ""},
	2: {"line": "Paid. A firefly winks its thanks.", "note": ""},
	3: {"line": "The lantern holds, and First Light gives way to warmer days.", "note": ""},
	4: {"line": "The bell again. The treeline stays where it should.", "note": ""},
	5: {"line": "Glow enough, for now. Keep gathering, keeper.", "note": ""},
	6: {"line": "Paid in light. The sun stands higher than it has in months.", "note": ""},
	7: {"line": "The bell rings out across the warm and golden wood.", "note": ""},
	8: {"line": "Held. The dark grumbles, and waits.", "note": ""},
	9: {"line": "The lantern blazes. The long days are coming.", "note": ""},
	10: {"line": "The bell tolls under the midnight sun. So close now.", "note": ""},
	11: {"line": "Paid. One tithe stands between you and the fire.", "note": ""},
}

const WIN := "Midsummer. The great fire catches, and the whole wood blazes gold. Somewhere past the trees, the dark lets go its breath and retreats. You kept the light alive to the longest day. Rest now, keeper. You earned the warmth."

const LOSS := "The last ember dims, and the cold comes in soft and patient, the way it always meant to. The fireflies wink out one by one, and the hollow forgets it was ever warm. Maybe next season. Maybe next keeper."

# Season entered after paying tithe `paid` (3 -> Sun's Climb, 6 -> Golden Sun, 9 ->
# Midnight Sun). Returns "" when the paid tithe doesn't complete a season.
static func season_after(paid: int) -> String:
	match paid:
		3: return "suns_climb"
		6: return "golden_sun"
		9: return "midnight_sun"
	return ""
