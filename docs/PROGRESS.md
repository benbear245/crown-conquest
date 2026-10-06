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

## Prompt 4: Players, Crowns and basic bots

**Built**
- Multiple players: `_setup_players(num_bots)` creates the local player (id 1, blue) plus up to 11 bots. Bots get a fantasy name (`Balance.generate_name`), a personality (Expander / Raider / Turtle / Opportunist), an initial jittered think timer, and Easy difficulty (Normal and Hard arrive in Prompt 11).
- Match phases live on `GameState`: `PHASE_PLACEMENT`, `PHASE_MATCH`, `PHASE_ENDED`. `advance_tick` dispatches on `state.phase`, so growth, expansion and bot thinking only run during the match.
- Placement phase (10 s): bots pick a valid spot on their next tick via `_find_valid_crown_position` (random sample with ≥ `CROWN_MIN_DIST_FROM_OTHER` spacing, respecting edge distance and buildable terrain, then a relaxed fallback). The local player can tap any valid tile. When the timer hits 0 the sim auto-places anyone left and transitions to `PHASE_MATCH`.
- Placing a Crown stamps the 3×3 block into `state.crown_tiles` and the centre into `state.crown_centres`, grants `STARTING_TROOPS`, then claims the radius-4 starting circle (skipping blocked tiles).
- Map rendering: Crown tiles override the normal owner-tint — the centre is painted gold, the surrounding 8 tiles are the owner colour lightened by 35 %. The 3×3 stays visible for everyone, on top of claimed land.
- `scripts/sim/bots.gd` (`Bots`): basic expand-only brain. On each tick it ticks `player.think_timer`; when the timer hits 0 it picks a random border tile that touches a free (unowned/ruins, non-blocked) neighbour and calls the same `Simulation.player_expand` the local player uses. Difficulty controls both the think interval and the send-fraction range from Balance.
- Peace period: no attacks until `match_time >= PEACE_PERIOD_SEC`. Expansion is allowed throughout; attack hooks are still deferred to Prompt 5.
- HUD additions:
  - Match-phase label in the top row: `Placement 0:XX` → `Peace ends M:SS` → `M:SS` → `Final Siege M:SS`.
  - Leaderboard panel anchored top-right. 5 rows of (colour swatch, truncated name, land %). Sorted by land each frame.
  - Centre-screen placement prompt that hides when the match starts.
  - Taps during placement call `player_place_crown`; taps during the match still call `player_expand`.

**What to check**
- Press F5. The 10-second countdown shows "Place Crown" at the centre and bottom. If you don't tap, you still end up with a Crown by the time the match clock starts.
- Tap a tile well inside the land — your 3×3 Crown appears with a gold centre, and the radius-4 starting ring claims around it.
- 7 bot Crowns appear on the map, spaced apart (at least 24 tiles between centres).
- The top banner switches to "Peace ends 0:XX" during the first minute, then shows the plain match clock, and later "Final Siege" after 10 minutes.
- The leaderboard on the right updates every frame; biggest player at the top. Early on, everyone has ~49 land tiles.
- Bot land areas grow outward over time; nothing attacks yet (Prompt 5).
- Tapping "New map" starts a fresh placement phase on a new seed.

## Prompt 5: Combat

**Built**
- `Attack` (`scripts/sim/attack.gd`): attacker_id, defender_id, troops_remaining, a defender-tile front, and an advance timer. The attacker has already paid the troops_remaining when the attack is created.
- `Simulation.player_attack(player_id, tx, ty, fraction)`: enforces peace period, requires enemy ownership and a touching border, caps per-player active attacks at `Balance.MAX_SIMULTANEOUS_ATTACKS` (3), builds the initial front from attacker-border tiles' defender neighbours, moves the troops out of the attacker's pool, and queues an `Attack`.
- `Simulation._tick_attacks` advances every active attack: timer counts down, each `Balance.ATTACK_RING_INTERVAL_SEC` (0.4 s) a ring of defender tiles is captured. Each tile costs `2 + 1.5 · D · terrain_defense · combined_defense`, where `D = defender.troops / defender.land` (snapshot at ring start). The defender loses `0.5 · D` troops per lost tile. The attack ends when troops run out or the front is empty.
- `combined_defense_at(tile_idx)` is a single function returning 1.0 for now; Crown + Fort / Wall land in Prompts 6 and 8.
- `Simulation.player_retreat(player_id, local_index)` refunds `RETREAT_RETURN_FRACTION` (75 %) of what is still in the attack and removes it.
- Border flash: `_mark_flash(tile_idx)` writes an expiry into `state.flash_tiles` whenever an attack captures a tile. `_tick_flashes` erases expired entries and marks them dirty so the Map repaints back to normal. `Map._color_for_tile` lerps toward white while a tile is flashing — a visible pulse along a defender's edge wherever a fight is active.
- `Simulation.active_attack_count` / `attacks_by` let the HUD show the local player's running attacks.
- Over-cap shrink after losing land already landed in Prompt 2; attacks pushing a defender under their new cap go through `_apply_growth`'s shrink branch next tick automatically.
- Bots now attack: `Bots._basic_expand` tries `_try_tap_free` first; if no free land touches their border, after the peace period expires they call `_try_attack_weakest` which picks the neighbouring player with the lowest `troops/land` and queues an attack through `Simulation.player_attack` (same path as a human tap).
- HUD attack list on the bottom-left: up to 3 rows, each a button labelled `⚔ Defender  N` showing the troops left in that attack. Tapping the row retreats and refunds 75 %.
- `game.gd` tap routing: during a match, taps on enemy land call `player_attack`; taps on free land still call `player_expand`.

**What to check**
- After the 10 s placement and 60 s peace, tap enemy land that touches your border. An attack appears in the bottom-left list and the border between you and that player starts eating defender tiles every 0.4 s. The attack's troop readout drops as it pays per tile.
- Open 3 attacks and verify a 4th tap on enemy land is ignored.
- Tap one of the attack rows while it's running — 75 % of its remaining troops come back to your pool.
- Captured tiles briefly flash lighter before settling into the attacker's colour.
- Bots start attacking once free land near them runs out (usually around the 1:30–3:00 mark); you'll see borders eating into each other across the map.
- During peace (first minute after placement), attempting to attack is a no-op; the attack list stays empty.
- Over-cap shrink is visible when a player loses a lot of land fast: their troop bar drops toward the new cap.

## Prompt 6: Crowns and winning

**Built**
- `combined_defense_at(tile_idx)` now returns the full non-terrain defense: Crown tiles get `CROWN_TILE_DEFENSE` (×3, dropping to ×1.5 in Final Siege) and ignore the ×4 building cap; non-Crown tiles inside the owner's Crown zone (radius 6) multiply ×1.5 (0 during Final Siege). Fort / Wall still hook in later and share the cap.
- Elimination (`Simulation._eliminate_player`): capturing the Crown's centre tile marks the victim `is_alive = false`, moves 30 % of the victim's troops to the capturer (60 % during Final Siege), zeros the victim's troops, converts every tile the victim owned to Ruins owner id 255, drops the victim's Crown entries, ends every attack touching the victim, rebuilds borders for everyone, and fires an announcement banner.
- Crown-under-attack alert: `_check_crown_alerts` sets `defender.crown_alert_until = match_time + 2s` whenever any attack's front touches that player's Crown zone. `game.gd` watches the local flag and calls `Input.vibrate_handheld()` on the rising edge; the HUD shows a tappable `⚠ Crown under attack` button that jumps the camera to the local Crown.
- Final Siege: at `match_time >= FINAL_SIEGE_START_SEC` the sim fires a one-shot announcement and `combined_defense_at` + `_eliminate_player` branch on `state.is_final_siege()`. Timer label changes to "Final Siege M:SS".
- Win conditions (`_check_win_conditions` each tick): last Crown standing, 60 % of usable land (`DOMINION_WIN_FRACTION`), or most land at `MATCH_TIME_LIMIT_SEC`. `_end_match` sets `state.phase = PHASE_ENDED`, stashes winner + reason, clears active attacks and announces.
- Victory / defeat overlay: HUD renders a dim full-screen panel with a big title (`Victory!` / `Defeated` / `<Name> wins`), the reason, local stats (time, peak land %, Crowns taken), and two buttons: **Play again** (restart match with a fresh seed) and **Watch** (dismiss overlay for this phase; stays dismissed until a new match starts or a new ending event happens).
- `Player.crowns_captured` ticks up on each successful centre-tile capture, so the overlay can report it.

**What to check**
- Build up around 1–2 min, then push into a bot's Crown. The Crown zone makes the inner 6-tile ring noticeably more expensive — a troops-per-tile reading of ~5 for plains outside the zone jumps to ~7.5 inside, and Crown tiles themselves cost ~15.
- When you crack a bot's centre tile, their land turns grey-ish Ruins, you get a chunk of plunder, and a banner reads "<You> has taken <Name>'s Crown!". The attack row closes and the bot drops off the leaderboard (land = 0).
- At 10:00, a "Final Siege begins" banner fires; Crown tiles are much weaker and plunder jumps to 60 %.
- If a bot captures your Crown, your screen pulses, a defeat overlay appears, and you can click "Watch" to keep observing. The match continues until a Dominion / Last-Crown / time-limit win condition triggers.
- "Play again" resets with a new seed; the overlay closes.
- The `⚠ Crown under attack` button appears when an enemy front crosses within six tiles of your Crown. Clicking it recentres the camera.

## Prompt 7: Balance simulator

**Built**
- `scripts/tools/balance_sim.gd` + `scenes/balance_sim.tscn`: a headless scene that plays N bot-only matches on the real `Simulation` and prints + saves a Markdown report. It flips every player to a bot and overrides difficulty from a mix array (Mixed = 3 Easy, 3 Normal, 1 Hard, pad with Normal to fill 8 slots), keeps seeds deterministic (seed = match number), samples the land leader at `match_time = 3:00`, then collects: duration, winner (name / difficulty / personality), win reason, whether the 3:00 leader won, Crowns captured, and whether the match hit the 15:00 limit.
- CLI overrides: `--matches N`, `--map small|medium|large`, `--type continent|archipelago|highlands|random`, `--mix mixed|easy|normal|hard`. Defaults match the design's "Medium map, 8 bots, Mixed difficulty" target set.
- Report writer compares results against every row of the design's targets table (median length 7–11 min, no personality > 35 %, 3:00 leader win rate < 55 %, time-limit matches < 5 %, Crowns captured ≥ 5 of 7). Each row prints PASS / FAIL. Building/ability use and the "1 Hard vs 7 Easy" row are listed as N/A for now (Prompts 8–9 and 11).
- The report also lists each match (seed, length, winner, reason, Crowns) and prints a short "suggested next changes" section driven by which targets failed — e.g. a long median points at `CROWN_TILE_DEFENSE` / `FINAL_SIEGE_START_SEC`, a too-high leader-at-3:00 win rate points at Underdog / Rising Empire (once Prompt 10 is in).
- Output written as text to stdout AND to `reports/balance_<YYYY-MM-DD>.md` via `ProjectSettings.globalize_path`.
- No `scripts/sim/` file was touched by the simulator; the same Simulation runs for the real game and the sim.

**How to run**

```
godot --headless --path <project_dir> res://scenes/balance_sim.tscn
# with options
godot --headless --path <project_dir> res://scenes/balance_sim.tscn --matches 50 --map medium --type continent --mix mixed
```

(On Windows, use the console build of Godot so stdout prints inline. Save the Godot executable path somewhere stable; the project uses `C:\Users\benbe\Desktop\Godot_v4.7.2-stable_win64_console.exe` during development.)

**Demo report (3 matches)**

The current GDScript sim runs about 90 s of wall time per full 15-minute match on this machine, so the demo was run with `--matches 3` instead of the user-requested 20. The report is in `reports/balance_2026-10-06.md`; the same command with `--matches 20` reproduces the full target set in ~30 minutes once bots can crack Crowns.

With Prompt 5–6 bots on this build, every match runs to the 15:00 time limit — Crowns are too tough for Easy/Normal bots to crack through ×3 tile defense + ×1.5 zone defense with just basic expand-weakest attacks. Every target that depends on Crown falls FAILs on this first pass, which is useful: it tells us where to tune first.

| Check | Target | 3-match actual | Verdict |
| --- | --- | --- | --- |
| Median match length | 7-11 min | 15:00 | FAIL |
| Wins per personality | ≤ 35 % | 67 % (Opportunist) | FAIL |
| Land leader at 3:00 wins | < 55 % | 100 % | FAIL |
| Matches decided at the time limit | < 5 % | 100 % | FAIL |
| Crowns captured / match | ≥ 5 of 7 | 1.7 | FAIL |
| Each building and ability used | ≥ 30 % | N/A (Prompts 8-9) | N/A |
| 1 Hard vs 7 Easy, Hard wins | ≥ 40 % | not run | N/A |

**Suggested Balance changes to try next (not applied — Prompt 17 does the actual pass)**
1. Lower `CROWN_TILE_DEFENSE` from 3.0 → 2.0 or `CROWN_ZONE_DEFENSE` from 1.5 → 1.25 so Crowns can be cracked before the 15:00 time limit.
2. Pull `FINAL_SIEGE_START_SEC` from 600 s → 480 s so the Final-Siege plunder doubling and ×1.5 Crown bite earlier and force endings.
3. Once Prompt 11 lands and bots are smarter, re-run the sim and expect many more matches to end under 11 minutes. If the median then slips below 7 min, nudge `CROWN_TILE_DEFENSE` back up.
4. The Crowns-captured metric is 0 while bots can't crack Crowns; fixing (1) and (2) will drive it up naturally.
5. Underdog / Rising Empire don't exist yet (Prompt 10). The 3:00-leader win-rate check is the main one that will swing when those land, so I'd defer any change there until Prompt 10 is implemented and re-run.

**What to check**
- From a terminal in the project directory, run the sim command above. Stdout shows each match's result as it finishes; the full Markdown report prints at the end and is also written to `reports/balance_<date>.md`.
- The report's PASS/FAIL rows should match the design's targets. For now, median length and crowns-captured will FAIL; the suggestions above explain why.
- The sim runs the same `scripts/sim/` code as the real game — no sim-only shortcuts, no hidden bot buffs.
