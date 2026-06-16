# symbols.gd
# Symbol registry for Midsummer Slots, ported from symbols.ts. Data-only.
# Synergy `type` strings are preserved verbatim from the TS engine; multi-word
# field names are snake_case (round_type, present_target, absent_target,
# transform_into, after_spins). Sprites/emoji/descriptions are presentation-only
# and intentionally dropped from the logic port.
class_name Symbols

# id -> { name, rarity, base_value, tags, synergies, easter_egg?, draftable? }
const SYMBOLS := {

	# ================= COMMONS =================
	"firefly": {
		"name": "Firefly", "rarity": "common", "base_value": 1, "tags": ["nocturnal"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["moth", "lantern"], "bonus": 2 },
		],
	},
	"fern": {
		"name": "Fern", "rarity": "common", "base_value": 1, "tags": ["forest_floor"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["forest_floor"], "bonus": 2 },
		],
	},
	"mushroom": {
		"name": "Mushroom", "rarity": "common", "base_value": 1, "tags": ["forest_floor"],
		"synergies": [
			{ "type": "globalCountReward", "targets": ["mushroom"], "threshold": 3, "reward": "reroll_orb", "amount": 1 },
		],
	},
	"acorn": {
		"name": "Acorn", "rarity": "common", "base_value": 1, "tags": ["forest_floor"],
		"synergies": [
			{ "type": "transform", "transform_into": "oak_leaf", "after_spins": 5 },
		],
	},
	"dewdrop": {
		"name": "Dewdrop", "rarity": "common", "base_value": 1, "tags": ["flower"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["flower"], "bonus": 4 },
		],
	},
	"moth": {
		"name": "Moth", "rarity": "common", "base_value": 2, "tags": ["nocturnal"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["firefly"], "bonus": 2 },
		],
	},
	"pebble": {
		"name": "Pebble", "rarity": "common", "base_value": 1, "tags": ["forest_floor"],
		"synergies": [
			{ "type": "note" },
		],
	},
	"clover": {
		"name": "Clover", "rarity": "common", "base_value": 1, "tags": [],
		"synergies": [
			{ "type": "selfChance", "chance": 0.10, "multiplier": 2 },
		],
	},
	"sparrow": {
		"name": "Sparrow", "rarity": "common", "base_value": 1, "tags": ["creature"],
		"synergies": [
			{ "type": "globalBonus", "targets": ["creature"], "bonus": 1 },
		],
	},
	"berry": {
		"name": "Berry", "rarity": "common", "base_value": 1, "tags": ["forest_floor"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["berry", "hedgehog"], "bonus": 2 },
		],
	},
	"dandelion": {
		"name": "Dandelion", "rarity": "common", "base_value": 1, "tags": ["flower"],
		"synergies": [
			{ "type": "periodicReward", "every": 4, "reward": "reroll_orb", "amount": 1 },
		],
	},
	"snail": {
		"name": "Snail", "rarity": "common", "base_value": 1, "tags": ["forest_floor"],
		"synergies": [
			{ "type": "alternating", "multiplier": 2 },
		],
	},
	"sunbeam": {
		"name": "Sunbeam", "rarity": "common", "base_value": 2, "tags": ["solar"],
		"synergies": [
			{ "type": "globalBonus", "targets": ["solar"], "bonus": 1 },
			{ "type": "roundPenalty", "round_type": "odd", "multiplier": 0.5 },
		],
	},
	"babys_breath": {
		"name": "Baby's Breath", "rarity": "common", "base_value": 1, "tags": ["flower"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["flower"], "bonus": 2 },
			{ "type": "adjacentBonus", "targets": ["dewdrop"], "bonus": 4 },
		],
	},
	"fairy_cloud": {
		"name": "Fairy Cloud", "rarity": "common", "base_value": 1, "tags": [],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["nocturnal", "fae_wings"], "bonus": 2 },
			{ "type": "passive", "effect": "row_adjacent" },
		],
	},

	# ================= UNCOMMONS =================
	"fox": {
		"name": "Fox", "rarity": "uncommon", "base_value": 3, "tags": ["creature"],
		"synergies": [
			{ "type": "globalBonus", "targets": ["rabbit"], "bonus": 1 },
			{ "type": "destroyAdjacent", "targets": ["pebble"], "bonus": 2 },
		],
	},
	"rabbit": {
		"name": "Rabbit", "rarity": "uncommon", "base_value": 2, "tags": ["creature"],
		"synergies": [
			{ "type": "conditionalBonus", "absent_target": "fox", "bonus": 2 },
			{ "type": "conditionalBonus", "present_target": "fox", "bonus": 1 },
		],
	},
	"honeybee": {
		"name": "Honeybee", "rarity": "uncommon", "base_value": 3, "tags": ["creature"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["flower"], "bonus": 4 },
		],
	},
	"lantern": {
		"name": "Lantern", "rarity": "uncommon", "base_value": 3, "tags": ["nocturnal"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["all"], "bonus": 1 },
			{ "type": "globalMultiplier", "targets": ["firefly"], "multiplier": 2 },
		],
	},
	"owl": {
		"name": "Owl", "rarity": "uncommon", "base_value": 3, "tags": ["creature", "nocturnal"],
		"synergies": [
			{ "type": "roundBonus", "round_type": "odd", "targets": ["nocturnal"], "bonus": 1 },
		],
	},
	"foxglove": {
		"name": "Foxglove", "rarity": "uncommon", "base_value": 2, "tags": ["flower"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["honeybee"], "bonus": 4 },
			{ "type": "globalReward", "requires": "beehive", "reward": "reroll_orb", "amount": 1 },
		],
	},
	"oak_leaf": {
		"name": "Oak Leaf", "rarity": "uncommon", "base_value": 3, "tags": ["forest_floor"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["forest_floor"], "bonus": 2 },
			{ "type": "transform", "transform_into": "ancient_oak", "after_spins": 8 },
		],
	},
	"crow": {
		"name": "Crow", "rarity": "uncommon", "base_value": 3, "tags": ["creature", "nocturnal"],
		"synergies": [
			{ "type": "runningTotal", "tracks": "destroyed_symbols", "bonus": 1, "cap": 6 },
		],
	},
	"hedgehog": {
		"name": "Hedgehog", "rarity": "uncommon", "base_value": 2, "tags": ["creature", "forest_floor"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["berry"], "bonus": 2 },
			{ "type": "passive", "effect": "destruction_immune" },
		],
	},
	"wild_rose": {
		"name": "Wild Rose", "rarity": "uncommon", "base_value": 2, "tags": ["flower"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["flower"], "bonus": 2 },
			{ "type": "adjacentBonus", "targets": ["antler_crown"], "bonus": 6 },
		],
	},
	"moon_elixir": {
		"name": "Moon Elixir", "rarity": "uncommon", "base_value": 3, "tags": [],
		"synergies": [
			{ "type": "periodicReward", "every": 1, "reward": "reroll_orb", "amount": 1 },
			{ "type": "adjacentBonus", "targets": ["glowing_wisp"], "bonus": 6 },
		],
	},
	"rowan_wand": {
		"name": "Rowan Wand", "rarity": "uncommon", "base_value": 3, "tags": [],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["flower", "nocturnal"], "bonus": 4 },
		],
	},
	"fae_wings": {
		"name": "Fae Wings", "rarity": "uncommon", "base_value": 2, "tags": ["nocturnal"],
		"synergies": [
			{ "type": "globalBonus", "targets": ["nocturnal"], "bonus": 1 },
			{ "type": "passive", "effect": "can_move" },
		],
	},
	"sundew": {
		"name": "Sundew", "rarity": "uncommon", "base_value": 3, "tags": ["flower", "solar"],
		"synergies": [
			{ "type": "adjacentBonus", "targets": ["flower"], "bonus": 2 },
			{ "type": "destroyAdjacent", "targets": ["creature"], "bonus": 4 },
		],
	},
	"bonfire": {
		"name": "Bonfire", "rarity": "uncommon", "base_value": 3, "tags": ["solar"],
		"synergies": [
			{ "type": "globalBonus", "targets": ["nocturnal"], "bonus": 1 },
		],
	},

	# ================= RARES =================
	"beehive": {
		"name": "Beehive", "rarity": "rare", "base_value": 5, "tags": [],
		"synergies": [
			{ "type": "globalBonus", "targets": ["honeybee", "foxglove"], "bonus": 1 },
			{ "type": "periodicSpawn", "every": 3, "spawns": "honey_jar" },
		],
	},
	"antler_crown": {
		"name": "Antler Crown", "rarity": "rare", "base_value": 6, "tags": [],
		"synergies": [
			{ "type": "globalBonus", "targets": ["creature"], "bonus": 2 },
			{ "type": "sacrifice", "reward": "light_orbs", "amount": 5 },
		],
	},
	"standing_stone": {
		"name": "Standing Stone", "rarity": "rare", "base_value": 5, "tags": [],
		"synergies": [
			{ "type": "destroyBonus", "targets": ["pebble"], "bonus": 1 },
			{ "type": "multipleBonus", "requires": 2, "targets": ["standing_stone"], "multiplier": 2 },
		],
	},
	"honey_jar": {
		"name": "Honey Jar", "rarity": "rare", "base_value": 4, "tags": [],
		"synergies": [
			{ "type": "globalBonus", "targets": ["flower", "honeybee"], "bonus": 1 },
			{ "type": "consumeOnTithe", "reward": "light_orbs", "amount": 8 },
		],
	},
	"glowing_wisp": {
		"name": "Glowing Wisp", "rarity": "rare", "base_value": 5, "tags": ["nocturnal"],
		"synergies": [
			{ "type": "copyAdjacent", "count": 1, "priority": "highest" },
		],
	},
	"fairy_ring": {
		"name": "Fairy Ring", "rarity": "rare", "base_value": 5, "tags": ["forest_floor"],
		"synergies": [
			{ "type": "globalMultiplier", "targets": ["forest_floor"], "multiplier": 2, "requires": 3 },
		],
	},
	"golden_stag": {
		"name": "Golden Stag", "rarity": "rare", "base_value": 6, "tags": ["creature", "solar"],
		"synergies": [
			{ "type": "globalBonus", "targets": ["solar"], "bonus": 2 },
			{ "type": "globalBonus", "targets": ["creature"], "bonus": 1 },
		],
	},
	"solstice_coin": {
		"name": "Solstice Coin", "rarity": "rare", "base_value": 4, "tags": ["solar"],
		"synergies": [
			{ "type": "periodicReward", "every": 3, "reward": "removal_orb", "amount": 1 },
			{ "type": "globalBonus", "targets": ["solar"], "bonus": 1 },
		],
	},
	"may_queen_crown": {
		"name": "May Queen Crown", "rarity": "rare", "base_value": 5, "tags": ["flower"], "easter_egg": true,
		"synergies": [
			{ "type": "globalBonus", "targets": ["flower"], "bonus": 2 },
			{ "type": "passive", "effect": "tithe_tie_wins" },
		],
	},

	# ================= VERY RARE =================
	"solstice_flame": {
		"name": "Solstice Flame", "rarity": "very_rare", "base_value": 10, "tags": [],
		"synergies": [
			{ "type": "globalBonus", "targets": ["all"], "bonus": 1 },
			{ "type": "exactTitheBonus", "multiplier": 2 },
		],
	},
	"green_man": {
		"name": "The Green Man", "rarity": "very_rare", "base_value": 12, "tags": [],
		"synergies": [
			{ "type": "treatAsAdjacent", "targets": ["forest_floor", "flower"] },
			{ "type": "transformCommon", "count": 3, "transform_into": "uncommon" },
		],
	},

	# ================= EASTER EGGS =================
	"corn_dolly": {
		"name": "Corn Dolly", "rarity": "rare", "base_value": 4, "tags": [], "easter_egg": true,
		"synergies": [
			{ "type": "stealAdjacent" },
			{ "type": "passive", "effect": "folk_curse" },
		],
	},
	"othala_rune": {
		"name": "Othala Rune", "rarity": "uncommon", "base_value": 3, "tags": [], "easter_egg": true,
		"synergies": [
			{ "type": "spinCounter", "bonus": 1, "cap": 8 },
		],
	},

	# ============ V2 TRANSFORM TARGETS (not draftable) ============
	"ancient_oak": {
		"name": "Ancient Oak", "rarity": "very_rare", "base_value": 8, "tags": ["forest_floor"], "draftable": false,
		"synergies": [
			{ "type": "globalBonus", "targets": ["forest_floor"], "bonus": 1 },
		],
	},
}

const COMMON_IDS := [
	"firefly", "fern", "mushroom", "acorn", "dewdrop", "moth", "pebble", "clover",
	"sparrow", "berry", "dandelion", "snail", "sunbeam", "babys_breath", "fairy_cloud",
]

const UNCOMMON_IDS := [
	"fox", "rabbit", "honeybee", "lantern", "owl", "foxglove", "hedgehog", "wild_rose",
	"oak_leaf", "crow", "moon_elixir", "rowan_wand", "fae_wings", "sundew", "bonfire",
]

# The bag the player starts with — 5 exact tile instances.
const STARTING_POOL := [
	"firefly", "fern", "mushroom", "dewdrop", "sparrow",
]

# Symbols offered in the draft. Excludes starters, transform-only, easter eggs, very_rare.
const DRAFT_POOL := [
	# commons (non-starter)
	"acorn", "dewdrop", "moth", "pebble", "clover", "sparrow", "berry",
	"dandelion", "snail", "sunbeam", "babys_breath", "fairy_cloud",
	# uncommons
	"fox", "rabbit", "honeybee", "lantern", "owl", "foxglove", "oak_leaf",
	"crow", "hedgehog", "wild_rose", "moon_elixir", "rowan_wand", "fae_wings",
	"sundew", "bonfire",
	# rares
	"beehive", "antler_crown", "standing_stone", "honey_jar", "glowing_wisp",
	"fairy_ring", "golden_stag", "solstice_coin",
]

# Named symbol clusters for tooltips/highlights. group id -> { name, members }.
const SYNERGY_GROUPS := {
	"nocturnal_web": { "name": "Nocturnal Web", "members": ["moth", "firefly", "owl", "lantern", "fae_wings"] },
	"forest_floor": { "name": "Forest Floor", "members": ["mushroom", "fern", "snail", "hedgehog", "pebble", "fairy_ring", "acorn", "oak_leaf", "berry", "ancient_oak"] },
	"pollinator": { "name": "Pollinator Chain", "members": ["honeybee", "foxglove", "beehive", "honey_jar"] },
	"predator_prey": { "name": "Predator & Prey", "members": ["fox", "rabbit"] },
	"ancient_circle": { "name": "Ancient Circle", "members": ["standing_stone", "antler_crown"] },
	"wild_garden": { "name": "Wild Garden", "members": ["wild_rose", "foxglove", "dewdrop", "dandelion", "babys_breath"] },
	"murder_of_crows": { "name": "Murder of Crows", "members": ["crow"] },
	"green_blessing": { "name": "Green Man Blessing", "members": ["green_man", "fern", "mushroom", "acorn", "oak_leaf", "dewdrop", "foxglove", "wild_rose", "dandelion", "babys_breath", "sundew"] },
	"last_light": { "name": "Last Light", "members": ["golden_stag", "sundew", "sunbeam", "bonfire", "solstice_coin"] },
}

# Resolve whether `target` matches a given symbol id (or "all").
static func symbol_matches(target: String, id: String) -> bool:
	if target == "all":
		return true
	if target == id:
		return true
	if not SYMBOLS.has(id):
		return false
	return SYMBOLS[id]["tags"].has(target)

# Group ids whose members include `id`.
static func groups_for_symbol(id: String) -> Array:
	var out: Array = []
	for key in SYNERGY_GROUPS.keys():
		if SYNERGY_GROUPS[key]["members"].has(id):
			out.append(key)
	return out
