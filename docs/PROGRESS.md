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
