# Crown Conquest build progress

## Prompt 1: Foundation

**Built**
- Git repo initialized (branch `main`); `.gitignore` extended for Godot 4 export/editor junk.
- `CLAUDE.md` with the 5-line game summary and the full coding rules from Prompt 1.
- `scripts/balance.gd` autoload (`Balance`) holding every number from `docs/DESIGN.md`: ticks, map sizes, troops, expansion, attack, terrain (plus terrain colours and the Ruins colour), Crown, Keep upgrades, buildings, abilities, fair play, truces, bots, teams, XP, and player colours. `static var` is used for `Packed*Array` tables because constructor calls aren't valid const expressions in GDScript.
- Pure-sim layer under `scripts/sim/`:
  - `game_state.gd` (`GameState`) — owns `terrain` and `owners` as `PackedByteArray`s on a configurable grid, players array, dirty-tile set, seeded RNG. Owner id `255` is reserved for Ruins.
  - `player.gd` (`Player`) — id, name, colour, troops, land, is_alive, bot fields, Crown position, border set, peak_land.
  - `simulation.gd` (`Simulation`) — starts a default 200x120 match, fills plains, adds the local blue player with a radius-4 claim at `(10, height/2)`, and advances the tick count. Ticks only; no node access.
- `scripts/map.gd` (`Map`) — only draws. Builds one `Image` + `ImageTexture` from the `GameState`, repaints only the dirty tiles each frame, lerps owner colour with terrain colour so terrain shows through claimed land.
- `scripts/game.gd` — root `Node2D` script that owns the `Simulation`, drives it at a fixed 10 ticks per second (with a 5-tick spiral-of-death cap), then calls `Map.render()` once per frame.
- `scenes/main.tscn` wires the Map child under the Game root.
- `project.godot` sets landscape orientation, 1920x1080 viewport, `canvas_items`/`expand` stretch, Balance autoload, and `res://scenes/main.tscn` as the main scene.

**What to check**
- Press F5. The window should open landscape and show a plains-coloured 200x120 map scaled to fit, with a blue circle (49 tiles) on the left-centre of the map.
- No parse errors or warnings in the Output panel. The game runs at the project's refresh rate; the sim ticks at 10 Hz regardless.

## Prompt 2: Troops and expansion

**Built**
- Growth formula on tick: `2 + 0.06·land + 0.05·troops·(1 − troops/cap)` per second, capped at `200 + 3·land`. Over-cap troops shrink by 2% per second (`troops = cap + extra·(1 − 0.02·dt)`). Everything comes from Balance.
- `Player.troops_per_second_at(cap)` returns the current growth or negative shrink; HUD reads it directly.
- Per-player `border` set, maintained incrementally by `Simulation._update_borders_on_change` whenever an owner flips. No full-map scans in the hot path.
- Expansion engine: tap free land touching your border → `floor(troops · slider)` moves from `troops` into `expansion_troops` and the timer starts. Every `EXPANSION_RING_INTERVAL_SEC` (0.3 s) one ring of free/ruins tiles adjacent to the border is claimed; each costs `2 × terrain claim cost`, Ruins cost half. When the bucket cannot afford any remaining frontier tile, whatever is left is refunded to `troops`.
- Taps only expand into unowned/ruins land for now (attack hooks go in Prompt 5).
- HUD built in code (`scripts/hud.gd`):
  - Top panel: troop bar (dark track + fill rect, label), troops/sec, land %.
  - Fill colour: red when over cap, green between 35 % and 65 % of cap (sweet spot), yellow otherwise.
  - Bottom panel: HSlider from 10 to 100 %, "Send X%" label, and four thumb-sized quick buttons (25/50/75/100 %). Buttons are at least `Balance.MIN_BUTTON_PX` (56 px) tall.
  - Decorative Controls use `MOUSE_FILTER_IGNORE` so taps on empty HUD area pass through to the map.
- `Map.screen_to_tile(pos)` converts viewport coordinates to a tile for the tap handler.

**What to check**
- Troop bar fills over time; label matches "troops / cap".
- Bar turns green between about 70 and 130 troops at start (35–65 % of the starting cap of ~347), and the troops/sec reading peaks there (interest term maximises at half cap).
- Dragging the slider updates the label; the quick buttons snap the slider and change the label.
- Tapping free land that touches the blue circle makes the circle grow outward one ring at a time, and the troop count drops by `2 × new_tiles` per ring. Taps far from the border do nothing.
- Tapping inside the circle or on nothing does nothing.
- Over-cap check: push troops way over the cap (not easy yet without more land), and watch them drift back down.

## Prompt 3: Terrain and maps

**Built**
- `scripts/sim/map_gen.gd` (`MapGen`): pure-sim generator keyed to `state.seed`. One FastNoiseLite for elevation (frequency 0.025, 4 octaves) and a second for biomes. The elevation is shaped by map type (Continent subtracts a radial falloff; Archipelago biases down; Highlands up) and then quantiled with a sorted copy so the actual terrain shares match the design within a tile or two. Thresholds come from `Balance.TERRAIN_SHARE_*` adjusted per map type.
- Terrain: Plains, Forest (biome noise > 0.15 on non-highland land), Hills, Mountains, Water, and Gem fields placed as 6–12-tile random-walk clusters until the ~1 % target is hit.
- Map types and sizes live in `Balance` (`MAP_TYPE_*`, `MAP_SIZE_*`). `Simulation.start_match(size, map_type, seed)` is the single entry point; `start_default_match` now calls it with Medium + Continent.
- Gem growth bonus: `Player.gem_tiles` tracked incrementally in `_update_borders_on_change`; `_apply_growth` multiplies the per-second growth by `1 + min(0.5 % per gem, 15 %)`. Underdog and Empire upkeep land in Prompt 10.
- Starting location: `_find_starting_tile` spirals outward from the preferred x to find a tile whose radius-4 neighbourhood is mostly non-blocked, so a water strip at the left edge no longer starves the local player.
- `scripts/map.gd` draws the ImageTexture at world (0, 0)–(width, height) with `TEXTURE_FILTER_NEAREST`, so terrain stays crisp when zoomed. Owner colour still lerps with terrain colour (`OWNER_TERRAIN_TINT`) so hills, forest and gems show through claimed land.
- Camera2D under `Main`: fits to the full map on load; pan by dragging (mouse or finger — distance-threshold separates tap from drag); zoom with mouse wheel or pinch gesture (`InputEventMagnifyGesture`); clamped so the camera centre can't fly off the map.
- `game.gd` converts screen taps to world coords via `get_canvas_transform().affine_inverse()` so taps work at every zoom level.
- HUD has a "New map" button in the top panel that regenerates terrain with a fresh seed and re-centres the camera.

**What to check**
- The map opens with a brown/green landmass surrounded by water, scattered dark forest and lighter hill patches, grey mountain spines, and purple gem clusters. Tap "New map" a few times — each layout is different.
- Drag anywhere on the map to pan; wheel to zoom in and out. The camera clamps so you can't scroll past the edges.
- Tapping free land next to your blue circle still expands into it, and the troop count drops by the correct per-tile cost (plains ×1, forest ×1.5, hills ×2). Taps on mountains or water do nothing.
- If you claim a gem cluster, your troops/sec reading creeps up a bit (0.5 %/gem up to 15 %).
