# Midsummer Game — session handoff

_Last updated: 2026-06-16._

## What this repo is
Godot 4.6 (GDScript) port of **Midsummer Slots**, a roguelite slot game.
Pure scoring logic ported from the TypeScript original. GitHub: `3dees/midsummer-game` (private).

- **Reference source** (TypeScript original): clone the sibling repo `3dees/midsummer-orb-spin`
  (private) alongside this repo. Read `src/routes/play.tsx` (game-loop reducer) and
  `src/lib/midsummer/{engine,symbols}.ts` when you need original behavior. Reference only.
- **Godot binary**: install Godot 4.6.3 (the console variant — `..._console.exe` on Windows —
  is required for headless stdout). Point `$GODOT` (see below) at your install.

## State: everything merged to `main`
PRs #1 (symbol registry + engine idiom fixes), #2 (sprite assets), #3 (playable scene)
are all **merged**. `main` is the complete, playable v1 core. No open PRs, no pending cleanup.

## Files that matter
- `midsummer/engine.gd` — pure scorer (`class_name MidsummerEngine`). No React/UI. Verified vs TS.
- `midsummer/symbols.gd` — registry (`class_name Symbols`), 44 symbols, each has a `sprite` PNG name.
- `assets/sprites/` — 48 PNGs + `.import`. Sprites load from `res://assets/sprites/`.
- `scenes/main.tscn` — portrait 9:16 main scene (720×1280, stretch canvas_items / keep).
- `scenes/game.gd` — game loop (spin → score → draft → tithe carry-over → win@round12 / lose).
- `spec/golden-cases.json` + `tests/test_engine.gd` — regression spec. **Do not edit expected values.**

## How to verify
```sh
# Set once per shell (update path to your install):
export GODOT="C:\Users\vsjam\Godot_v4.6.3-stable_win64_console.exe"

# golden test (must stay 20/20)
"$GODOT" --headless --path . --script res://tests/test_engine.gd

# scene click-path test (reroll / bag / removal floor — must stay 11/11)
"$GODOT" --headless --path . --script res://tests/test_scene.gd

# boot main scene a few frames, check for errors
"$GODOT" --headless --path . --quit-after 30
```

### SceneTree smoke-test pattern
Script-driven tests must use `_initialize()` + `await get_tree().process_frame` before `_ready`
fires on scene nodes (`_init` is too early). See `tests/test_engine.gd` for a working example:
```gdscript
func _initialize():
    await get_tree().process_frame  # nodes are ready after this
    # ... test code
```
The real game boots normally without this ceremony.

## Known guesses / deviations (flagged, not yet confirmed by user)
- Grid cells (20) and draft cards (3) are built in code, not authored as scene nodes.
- HUD format: `Tithe n/12 · <season> · orbs/cost · spins <remaining> · ✨orbs ↺reroll ✕removal`.
  `✨` repeats the orb count; `spins N` = spins left in the current tithe cycle.

## Phase 3b toolkit — DONE (this session, on `feat/playable-scene`)
- Bag / inventory panel + removal-orb spending (click a tile, floor of 3 enforced, match by uid).
- Reroll button on the draft (spend 1 reroll orb → re-pick 3; greyed at 0).
- Free removal orb granted per tithe paid (cap 3); spin-gained removal also capped at 3.
- Two new in-cycle removal sources in `symbols.gd`: **Snail** `periodicReward` every 4 spins,
  **Hedgehog** `globalCountReward` at 3+ forest_floor on grid. Golden stays 20/20 (removal channel
  is separate from score; neither fires in the 2 snail / 0 hedgehog golden cases).
- Framed grid cells (StyleBoxFlat), season-brightening background, bigger draft-desc font (14).
- New click-path test: `tests/test_scene.gd` (reroll spend, bag removal, 3-tile floor) — 11/11.

## Deferred (next work, per original scope)
- Sequential spin **reveal animation** (cells → rewards → total → done in play.tsx).
- Polished overlays (draft, tithe pass/fail, win/loss) — current ones are minimal.
- Restart flow (`RESTART` action exists in play.tsx).
- `green-man-upgrade` phase (transformCommon) — engine has it as a v2 no-op placeholder.

## Engine notes

### ⚠ Synergy no-ops — do not implement expecting them to fire
These synergy types exist in the scorer as **v2 placeholders** (no-ops). Tooltips display them
but the engine does nothing when they trigger. **Real footgun for anyone adding a new symbol.**
Do not wire UI/game logic expecting any of these to execute:

`transform` · `destroyAdjacent` · `destroyBonus` · `sacrifice` · `periodicSpawn` ·
`consumeOnTithe` · `copyAdjacent` · `treatAsAdjacent` · `transformCommon` ·
`titheReduction` · `exactTitheBonus` · `stealAdjacent` · `passive` · `note`

- `DIFFICULTY = 1.5` in `engine.gd` is the single tithe-economy knob (tithe 1 cost = round(25×1.5) = 38).
  Changing it rescales all 12 tithe costs; re-tune by playtest. Does not affect scoring or the golden tests.
- GDScript 4.6 gotcha: `:=` inferring from a Variant (Dictionary subscript, `and`/`or`, `min()`)
  is a hard error — use explicit types or `int()`/`str()`/`mini()`. The engine port hit this 11×.
