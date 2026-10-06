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

## Prompt 8: Buildings and Keep upgrades

**Built**
- `scripts/sim/building.gd` (`Building`): one record per Fort / Fort II / Barracks / Port with centre tile, type and defense/radius/cost helpers.
- `scripts/sim/boat.gd` (`Boat`): one in-flight sea unit — owner, troops, water-path, progress, send-fraction, landing tile.
- `scripts/sim/buildings_ops.gd` (`BuildingsOps`): pure-sim helpers for `build_fort / upgrade_fort / build_barracks / build_port / build_wall / buy_keep` and `tile_is_buildable` (owner check, no-blocked-terrain, no stacking buildings/walls/Crown tiles, and the 3-tile enemy-border buffer).
- `scripts/sim/boats_ops.gd` (`BoatsOps`): launches a boat (BFS over water tiles from the Port to a water tile adjacent to the target coast, capped at `BOAT_RANGE_TILES`), ticks progress at `BOAT_SPEED_TILES_PER_SEC`, and calls `Simulation.boat_land` when the path finishes.
- `GameState` extended with `buildings`, `wall_tiles` (tile_idx → owner_id), `building_at_tile` (tile_idx → Building for fast lookup), `boats`, and `loot_popups` (floating "+N loot" numbers for the HUD).
- `Player` extended with `fort_count`, `fort_tiles`, `barracks_count`, `port_count`, `wall_count`, `keep_level`, plus `troop_cap()` now folds in Barracks (+10% per instance) and Keep 3 (+5%). New helpers `crown_tile_defense()`, `crown_zone_defense()`, `crown_zone_radius()` read from the `KEEP_*` tables.
- `Simulation.combined_defense_at` now returns the full Fort × Wall × Crown-zone product, capped at ×4, with the Crown-tile defense (ignoring the cap) coming from the owner's Keep level. Final Siege still weakens Crown tiles and disables both the zone bonus and Keep upgrades.
- Capturing a building/wall tile destroys it immediately, gives the attacker 25 % of the cost as loot, and queues a `loot_popups` entry for the HUD. Eliminating a player wipes all of their buildings/walls/boats so the Ruins field is clean.
- Thin `Simulation.player_build_fort / upgrade_fort / build_barracks / build_port / build_wall / buy_keep / launch_boat` commands validate the match phase and delegate to the ops helpers (bots call these same methods).
- `scripts/sim/bots.gd`: Normal/Hard bots occasionally spend troops on Barracks, Forts, and the next Keep upgrade when they have 1.3–1.5× the cost and a safe interior tile (picked near the Crown). Easy bots still only expand/attack.
- `scripts/map.gd`: Walls paint a dark stripe, Fort/Fort II darken the owner tint (II darker), Barracks tint toward brown, Ports toward white — all overlaid on top of the usual owner/terrain lerp.
- `scripts/hud.gd`: long-press on your own land opens a build menu with Fort/Fort II (if a Fort is already here), Barracks, Port (when the tile touches water), a Wall-mode toggle and (on a Port tile) Launch boat. Tapping your Crown opens a Keep-upgrade panel (3 buttons, locked/owned/affordable states). Grey-out logic covers cost, limit, 3-tile enemy buffer, and unlock time.
- `scripts/game.gd`: 0.4 s long-press detection; wall mode routes taps and drags to `player_build_wall` (one tile per new tile dragged over); boat mode captures the next tap as a landing target; tapping on your Crown opens the Keep panel.

**What to check**
- Long-press your own land. A side panel shows Fort (cost 300), Barracks (if 1:00+ and tile is interior), Port (if the tile touches water), Wall mode toggle, Close. Grey rows mean "can't afford" or "limit reached" or "within 3 of enemy border".
- Build a Fort, then enemy tile cost near it goes from ~5 to ~8 (plains D=2: 2 + 1.5·2·1·1.6 = 7.8). Upgrade with the "Upgrade to Fort II" row on the same tile (long-press the Fort). Enemy cost jumps to ~8 → ~8.5 (Fort II = ×2.0).
- Toggle Wall mode and drag along your border — each new tile costs 4 troops and shows a dark stripe. Wall x Fort x Crown zone caps at ×4.
- Tap your Crown — the Keep panel opens. Buy Keep 1 for 300 (available immediately). Keep 2 unlocks at 3:00, Keep 3 at 6:00; owned shows "owned" and locked shows the unlock time.
- Build a Port next to the water, then long-press the Port and press Launch boat. The next tap on an unowned/enemy coast within 60 water-tiles sends a boat; the boat lands and either expands (free) or opens an attack (enemy) from the landing tile.
- Capture an enemy Fort/Wall tile — the loot (25% of cost) shows up in your troop pool; next tick the building is gone.
- Bots: at Normal/Hard, you should see them stand up Forts and Barracks near their Crowns during the midgame and buy Keep 1/2 when they can afford it.

### Prompt 8 follow-up (cloud session)

**Built / fixed**
- The project didn't start: `game.gd` connected a truce handler that didn't exist. Fixed, and every GDScript warning is gone (checked with Godot's own language server).
- Split the two giant scripts to follow the 400-line rule: `simulation.gd` now delegates to `territory_ops.gd`, `combat_ops.gd`, `crowns_ops.gd`, `buildings_ops.gd`, `boats_ops.gd`; the HUD panels live in `scripts/ui/`; the camera is `camera_rig.gd`.
- Build menu always lists Fort/Fort II, Barracks, Port and Walls with cost, effect and how many you have left. Options you can't use are greyed out with the reason ("Need 450 troops", "Within 3 tiles of an enemy", "Unlocks at 1:00", "Must touch water", "Limit reached").
- Walls: Wall mode now has a banner with a **Done** button and shows "This line: N tiles · cost" while you drag. Fast drags no longer leave gaps. Walls follow the "not within 3 tiles of an enemy" rule like other buildings.
- Floating "+N loot" numbers now actually appear when you capture a building or wall. Loot is 25% of what the owner really paid (a 3rd Fort pays more loot than a 1st).
- Boats: tap your Port, then tap a coast. Boats are drawn sailing along their route. Boat attacks are blocked during the peace period; landing on a truce partner breaks the truce.
- Tap your Crown: the Keep panel shows each level's effects and unlock time, plus **Move Crown** (from the design: once per match from 3:00, 20% of troops, 5 s with no Crown defense).
- Final Siege now switches off Keep 3's +5% troop cap too (design: "Keep upgrades stop working").
- Crowns get a gold crown icon on the map.
- Normal/Hard bots place Forts between their Crown and the nearest enemy border instead of at random.
- Bots' "Crown under attack" alert now also runs in the simulator (before, simulator bots never saw it, so they never used Crown Shield there).
- New automated smoke test: `godot --headless --path . res://scenes/tools/smoke_test.tscn` plays the real game scene and checks 38 things (all pass).

**What to test**
- Long-press your land near the front line: Fort/Barracks rows are grey with "Within 3 tiles of an enemy".
- Tap Draw walls, drag a quick line across your land: the banner counts tiles and troops, the line has no gaps, Done exits.
- Build a Port on an Archipelago map, tap it, tap a coast across the water: a boat sails there and grabs land.
- Let a bot's Fort fall to your attack: "+N loot" floats up.
- After 3:00 tap your Crown → Move Crown → tap safe land deep inside your territory.

## Prompt 9: Abilities

**Built**
- `scripts/sim/abilities_ops.gd` (`AbilitiesOps`): id/label constants, `is_*_active` / `cooldown_until` / `cost_now` / `unlock_sec` lookups, and `activate_*` functions for Swift March / Crown Shield / Rally / Bombard. All validation reads from Balance.
- `Player` extended with `swift_march_until`, `swift_march_cd_until`, `crown_shield_*`, `rally_*`, `bombard_cd_until` and an `ability_think_timer` so bots don't press buttons every tick.
- `GameState.bombards` holds active bombard records (owner_id, target_x, target_y, until, last_damage_at). `AbilitiesOps.tick` applies 2 troops/sec damage to each enemy tile inside the area (scaled by elapsed time, so a varying tick cadence stays correct), and marks the area dirty when the bombard starts and ends.
- `Simulation._attack_tile_cost`: now takes `attacker_id`. Rally multiplies the cost by `1 − 0.30` while active, and `AbilitiesOps.tile_in_any_bombard` halves `extra_def` for tiles inside the area.
- `Simulation._advance_attack`: skips tiles inside the defender's Crown zone when Crown Shield is active (and Final Siege disables the shield automatically).
- `Simulation._apply_expansions` + `_expand_one_ring`: Swift March halves the ring interval (effectively doubles speed) and discounts the per-tile claim cost by 25 %.
- Keep 2 reduces the Crown Shield cooldown by 30 s via `AbilitiesOps.crown_shield_cooldown_sec`.
- Thin `Simulation.player_activate_swift_march / crown_shield / rally / bombard(target)` commands validate the match phase and forward to the ops layer.
- `scripts/map.gd`: tiles inside an active bombard area now paint a dark "cracked" tint on top of the base colour; the dirty-tile marks around activation and expiry make it appear and disappear cleanly.
- `scripts/hud.gd`: a four-button ability bar sits above the slider. Each button shows the ability label plus one of ACTIVE / cd Ns / unlock M:SS / troop cost / ready, and auto-disables when the player can't use it. Pressing Bombard sets a target-selection mode; a hint banner tells the player to tap a target or outside to cancel.
- `scripts/game.gd`: pressing an ability dispatches to the matching Simulation command (Bombard enters target mode and the next in-bounds tap sends the activation).
- `scripts/sim/bots.gd`: Normal bots use Swift March in the first three minutes and pop Crown Shield when their Crown is under attack. Hard bots additionally cast Rally while they have an active attack and Bombard when an enemy Crown is within range.

**What to check**
- Press Swift March — the "Send 10 %" slider still works but expansion rings roll faster and plains cost `2 × 0.75 = 1.5` for the next 8 s. The button shows ACTIVE while running and then "cd Ns".
- Press Crown Shield when a bot is pressing your Crown — the attack's front freezes on the Crown zone boundary. Button goes ACTIVE, then cooldown. Not available in Final Siege.
- Press Rally while a bot of yours is running — their per-tile cost drops by 30 % for 10 s. The attack row's troop remainder visibly drains more slowly.
- Press Bombard, then tap an enemy spot within 20 tiles of your border. A dark cracked overlay appears for 12 s, enemy tiles inside the area lose 2 troops/sec, and attacking into the area pays half the extra defense.
- Hard bots eventually fire Bombard on your Crown; Normal bots will drop Swift March opening the match.

### Prompt 9 follow-up (cloud session)

**Built / fixed**
- New ability bar (`scripts/ui/ability_button.gd`): each button draws its own icon (chevrons, shield, banner, burst), a cooldown ring that empties as the cooldown runs out (with seconds left), a gold ring while the effect is active, a green ring when ready, the troop cost, and a padlock with "Unlocks 1:30 / 3:00" until it unlocks. Crown Shield says "Off in Final Siege" then.
- Bombard now previews: tap Bombard, tap a spot, and the blast circle appears with "Hits N enemy tiles … Costs X troops" plus **Fire!** / **Cancel**. Out-of-range or empty spots are shown in red and can't be fired. Tap elsewhere to move the preview.
- Effect visuals on the map: a pulsing shield bubble over the whole Crown zone during Crown Shield (for every player), glowing attack fronts while Rally is on, and cracked ground with a dark ring under Bombard.
- Bots: Easy use no abilities, Normal use Swift March + Crown Shield, Hard use all four (checked in a bot-only match). Crown Shield now actually fires in the simulator too.
- Balance simulator now records which buildings and abilities were used and fills in the "Each building and ability used ≥ 30%" target, plus a "1 Hard vs 7 Easy" row (`--hard-check N`). New options: `--seed`, `--tag` (so reports don't overwrite each other), `--json`/`--merge` (run several simulator windows in parallel and combine).

**What to test**
- Watch the Rally and Bombard buttons count down to their unlock (lock icon), then light up.
- Use Swift March: gold ring drains over 8 s, then a blue cooldown ring with seconds.
- Use Crown Shield while a bot attacks your Crown: blue bubble, the front stops at the bubble edge.
- Use Rally during an attack: your front glows gold.
- Bombard: tap a spot too far away (red, Fire! disabled), then a spot on enemy land near you, then Fire!.

## Prompt 10: Fair play and truces

**Built**
- Fair-play rules moved into `scripts/sim/fair_play_ops.gd`: Underdog (+25% growth, free land and Ruins 25% cheaper when your land is under half the alive average), Empire upkeep (−15% growth over 20% of the map, −30% over 35%), Rising Empire (over 30%: everyone's attacks on them cost 15% less and bots target them). Growth bonuses add together (gems + Underdog = ×1.35 etc.).
- Small badges under the troop bar for every bonus or penalty affecting you (Underdog ↑, gems, Empire upkeep ↓, Rising Empire ★, Oathbreaker). Tap one for a one-line explanation.
- Rising Empire: a star next to their name on the leaderboard and above their Crown on the map. The leaderboard also shows a crown icon for players still alive (skull when out).
- Long-press enemy land: name, land, troops, personality hint, tags (Rising Empire, Oathbreaker, your truce time left) and **Offer truce**. If you can't offer, the button says why ("Waiting for an answer", "You have 2 truces already", "Bots refuse truces from Oathbreakers").
- Truces: 90 s, 2 at a time, bots answer within 2 s (more likely if they're busy fighting someone else or you're bigger). When a truce starts, any attacks between the two of you are called off. Truce partners get a white flag + countdown in a panel on the left, on the leaderboard, and above their Crown.
- Bots now offer truces when two or more players attack them at once. Offers to you show **Accept / Decline** for 10 s.
- Tapping a truce partner's land asks "Break your truce?" first. Attack anyway → Oathbreaker: attacks +20% for 45 s and every bot refuses your truces for the rest of the match. Bombard can't target a truce partner.
- Fixed: the old code made the *breaker* refuse truces instead of bots refusing the breaker; Opportunists "broke" truces without attacking. Now an Opportunist plans to break 20% of its truces and does it by attacking its partner.
- All truce chances and timings live in `balance.gd`.

**What to test**
- Early on, before you expand, you should see the green "+25%" Underdog badge. Tap it.
- Long-press a neighbour → Offer truce → after 2 s they accept or refuse (banner). If accepted: white flag + countdown on the left, on the leaderboard and over their Crown.
- Tap their land while in a truce → confirmation banner. Cancel keeps the peace; Attack anyway shows the red Oathbreaker badge.
- Get attacked by two bots at once: one may offer you a truce (Accept / Decline on the left).
- Let one player grow past 30% of the map: star on the leaderboard and over their Crown, and your "−15%" attack badge.

## Simulator speed-up (before Prompt 11)

**What changed** (no game rules or bot behaviour changed)
- Profiled the simulator tick by tick (`scenes/tools/sim_profile.tscn`). Attacks were 73% of the time, then Crown-alert checks, bots and expansion.
- Attack rings now work out their per-ring constants once (defender's Crown/zone/Fort data, Rally/Oathbreaker/Rising Empire flags) instead of per tile, with the exact same arithmetic. Tile claiming, border bookkeeping and the expansion frontier use direct index maths in the same order as before. Crown-zone alerts are cached per attack until its front changes. Usable-tile count, player lookup and blocked-terrain checks are cached. Headless runs skip redraw bookkeeping.
- **Proof it's the same game:** the simulator now records a fingerprint of each match's exact end state (every tile's owner, every player's land and troops, the end tick). 14 seeded matches (12 Medium, 2 Large with 12 players) gave bit-for-bit identical fingerprints before and after.
- **Speed:** the slowest full 15-minute match went from 22.1 s to 7.5 s on the cloud machine (2.4–2.9x overall). For reference, the old Prompt 7 simulator took ~100 s per match on this same machine, close to your ~90 s, so expect roughly 7–8 s per full match on your PC.
- New `--jobs N` option runs the matches in N Godot processes at once and merges the results (identical output). With 4 cores: 8 matches in 14 s instead of 34 s.

**How to run**
```
godot --headless --path . res://scenes/balance_sim.tscn --matches 100 --jobs 4
```

**Found while profiling (fixed in Prompt 11, since it changes behaviour):** an attack whose remaining troops can't pay for any tile never ends. It keeps one of the 3 attack slots forever.

## Prompt 11: Smarter bots

**Built**
- New bot brain in `scripts/sim/`: `bot_scan.gd` (what the bot sees: a sample of its border, free land / Ruins, neighbours, threats, who is busy fighting), `bot_moves.gd` (every possible move with a score), `bot_places.gd` (where to put Forts, walls, Ports, boat landings, a moved Crown), `bot_abilities.gd` (when to press abilities), `bots.gd` (pick and carry out). All numbers and score weights live in `balance.gd` ("Bot AI" section).
- Each think a bot lists its moves (expand, attack each neighbour, Fort, Fort II, Barracks, Keep, walls, Port, boat, Crown move, offer a truce), scores them, and takes the best. **Easy** makes a random move 20% of the time, **Normal** takes its second-best 10% of the time, **Hard** always takes its best.
- Difficulty table, as designed: Easy thinks every 2.5 s and sends 20–40%, uses Forts rarely, and never attacks your Crown before 4:00 (checked every tick). Normal 1.5 s / 30–60%, Forts + Barracks + Keep 1 + Swift March + Crown Shield, looks for weak borders. Hard 0.8 s / 40–80%, uses everything (walls, Fort II, all Keeps, Ports and boats, Crown move, all four abilities), stays near the sweet spot, combines Bombard + Rally on Crowns, retreats from attacks that stopped making progress.
- Personalities: Expanders grab free land and only attack once it runs out; Raiders hit their weakest neighbour with the top of their send range and race for Ruins; Turtles keep more troops, build Forts / walls / Keeps early and counterattack whoever attacks them; Opportunists attack whoever is busy fighting someone else, break 20% of their truces, and other bots trust them less.
- Bots keep a defense: they only expand or attack once their troops reach a share of their cap (Easy lowest, Hard highest), and buildings can't take them below it. Without this, bots spent down to ~0.2 troops per tile and Crowns fell almost for free.
- Hard bots also avoid being the softest target around, hold their troops while their Crown is under attack, and offer truces to their strongest neighbour so they don't fight on two fronts.
- Fixed (found while profiling): an attack that couldn't pay for any tile on its front never ended and blocked one of your 3 attack slots forever. It now ends like a retreat (75% back), unless it's only waiting out a Crown Shield.

**Simulator: 50 matches, Medium map, 8 bots, Mixed** (full report: `reports/balance_2026-10-06_smarter_bots.md`)

| Personality | Wins | | Difficulty | Wins |
| --- | --- | --- | --- | --- |
| Expander | 14 (28%) | | Easy (3 bots/match) | 7 (14%) |
| Raider | 9 (18%) | | Normal (4 bots/match) | 24 (48%) |
| Turtle | 18 (36%) | | Hard (1 bot/match) | 19 (38%) |
| Opportunist | 9 (18%) | | | |

1 Hard bot vs 7 Easy bots: Hard wins **42% of 100** (target ≥ 40%). Matches are still short (median 5:01, target 7–11 min) and Ports are only used in 24% of matches: those are balance numbers for Prompt 17.

**What to test**
- Easy bots: they shouldn't push into your Crown zone before 4:00 even if you're weak.
- Hard bots: watch for Bombard + Rally on a Crown, walls appearing in front of their Crown, and truce offers to you while they fight someone else.
- Long-press bots of different personalities: Turtles have Forts and walls, Raiders throw big attacks at the weakest neighbour.

## Prompt 12: Mobile controls and HUD

**Built**
- New screen layout from the design, built with anchors and containers inside the phone's safe area (notches): top bar (Crown button, troop bar that glows green in the sweet spot, troops/s, land %, timer, Menu), bonus/penalty badges and truces top-left, leaderboard top-right, banners in the top centre, send slider + ability bar along the bottom, your attacks and the minimap just above it. Every button is at least 56 px tall.
- Minimap in the corner: the live map, a box for what you're looking at, and every Crown (yours in gold). Tap or drag on it to jump there.
- Crown button (top-left): double-tap jumps to your Crown; a single tap tells you that.
- Touch input rewritten (`scripts/touch_input.gd`): a press becomes a long-press after 0.45 s if your finger stays within 14 px, a drag if it moves further, and a tap otherwise. A second finger cancels the tap and pinches to zoom toward your fingers. Android's fake mouse clicks are ignored, so a tap can't fire twice. A ring fills under your finger while you hold, and the phone gives a short buzz when the long-press triggers.
- First-time tips (blue banners) the first time you place a Crown, expand, attack, long-press, pan, use an ability, draw walls, send a boat, Bombard, offer a truce, open the Keep, hit the sweet spot, tap the minimap or the Crown button. They're remembered; "Show tips again" in the Menu brings them back.
- Alerts are a queue of up to 3 banners at the top between the side panels, so they never cover controls. "Your Crown is under attack!" is a red banner with a **Jump** button.
- Left-handed layout (Menu → Layout): slider, abilities, attack list, minimap and the build / Keep / enemy panels swap sides. Saved in `user://settings.cfg` (new `Settings` autoload, which the sound/vibration settings will use too).
- The orientation is now "sensor landscape" (works both ways round).
- Tested at 1920x1080 and 2400x1080, right- and left-handed, with every panel full: automated check that nothing overlaps or leaves the screen and every button is ≥ 56 px. All pass (130 smoke checks in total).

**What to test (on your phone if you can)**
- Tap free land quickly, then hold on your own land: the ring fills and the build menu opens; a tap never does both.
- Pinch to zoom with two fingers; drag with one.
- Tap the minimap; double-tap the Crown button.
- Menu → Layout: Left-handed. Everything at the bottom swaps sides.
- Get attacked near your Crown: red banner with Jump, plus a buzz.


## Prompt 13: Game feel, sound and vibration

**Built**
- Captured tiles flash white for a moment, and every active attack front pulses in the attacker's colour (your own attacks and attacks on you pulse brighter; Rally turns a front gold). Fronts are rebuilt once per sim tick and drawn as one batched call per attack.
- Floating numbers for rewards: "+1,240 plunder" over a fallen Crown and "+75 loot" over a captured building (numbers now use thousands separators).
- When a Crown falls: screen shake, a short slow-motion moment (game clock at 55% for 0.35 s) and a fanfare. If it's your Crown or you took it: a much bigger shake, slower and longer slow-mo (25% for 0.9 s), a bigger fanfare and a longer buzz. Slow-mo only slows the simulation clock; nothing in the rules changes.
- Vibration (only if the Vibration setting is on) when your Crown comes under attack, when any Crown falls (longer if it involves you), and when one of your abilities is ready.
- Sounds: soft ticks while you expand, drums each time an attack ring pushes (yours or one against you), a click when your attack takes tiles, a horn for the Crown alarm and the Final Siege, build/ability/loot/truce sounds, victory/defeat stings. Busy sounds are rate-limited so fights don't become noise. Calm music loops during the match and crossfades to a faster, more intense track in the Final Siege.
- All sounds are placeholders generated by `tools/make_placeholder_audio.py`, named by what they do (`assets/audio/sfx_crown_alarm_horn.wav`, `music_siege_loop.wav`, …). `assets/audio/README.md` lists every file and when it plays; drop in a real `.ogg`/`.wav` with the same name to replace one.
- Settings (Menu): Layout, Sound, Music, Vibration and Colour-blind palette, each a one-tap toggle that's saved straight away. The colour-blind palette uses colours that stay distinct with the common types of colour blindness and lets less terrain show through owned land; the map, minimap, leaderboard and boats all switch instantly.
- Speed: the presentation events are skipped in headless runs, so the balance simulator is unaffected (still ~2.5 s per match). In the game, measured on a Large map mid-fight, all the game-feel work adds 0.02 ms per frame.
- Small fix: the balance simulator now also reads options written after `--`.
- New smoke suite `feel` (34 checks). All 164 smoke checks pass.

**What to test**
- Take a bot's Crown: big shake, a moment of slow motion, fanfare, "+N plunder" floats up, phone buzzes. Watch two bots fight to the end: smaller shake and slow-mo.
- Attack someone: the front pulses and you hear drums; captured tiles flash.
- Let a bot reach your Crown: horn + buzz + red banner.
- Wait for an ability cooldown: chime + short buzz.
- Reach the Final Siege (10:00): the music changes.
- Menu: switch Sound, Music, Vibration and Colour-blind palette on and off; they should apply instantly and still be set after restarting the game.
- Replace one file in `assets/audio/` with a real sound of the same name and check it plays.

## Prompt 14: Menus and modes

**Built**
- The game now opens on a **main menu** (`scenes/menu.tscn`) over a randomly generated map: Play (Skirmish), Teams, Daily Challenge, Customize, Stats, Settings. Android's back button (or Escape) goes back a screen.
- **Skirmish setup**: map size, map type, number of bots (− / +, capped by the map size: 4 / 7 / 11), difficulty (Easy / Normal / Hard / Mixed) and an optional seed (any word or number replays the same map). Your last choices are remembered. Mixed = about 3 in 8 Easy, 1 in 8 Hard (at least one), the rest Normal.
- **Teams**: 4 teams of 2 on a Medium map (Lions, Wolves, Eagles, Stags). You get a bot ally (Normal when Mixed) who waits for you to place your Crown and settles next to you; bot pairs also start together. Allies can't attack each other (a tap on your ally's land just tells you so), can't Bombard or land boats on each other, and don't offer each other truces. A panel on the left shows your ally and a **Send 20% to ally** button (10 s cooldown). Bot allies send 20% when their partner's Crown is under attack or they're low on troops. The leaderboard ranks teams by combined land, Crowns get a ring in their team's colour, and the long-press panel shows each player's team. The team wins together: last team with a Crown, or **80%** of the land together (new number, `TEAM_DOMINION_WIN_FRACTION`; with the solo 60% two allies won in about 3 minutes; now the median all-bot Teams match is ~4:40, same as solo matches before Prompt 17's balance pass). If your Crown falls while your ally lives, the match goes on and you can watch.
- **Daily Challenge**: the date picks the seed and the map type; fixed settings (Medium, 7 bots, Mixed). Score = peak land % (rounded) + a time bonus if you win: 100 × (15:00 − win time) / 15:00, so a win at 6:00 adds 60. Try as often as you like; the best score per day and the best ever are saved. The end screen shows your score and "New best today!".
- **Pause menu** (Menu button, or Android back): Resume, Restart, Settings, Quit to menu. Restart and Quit ask "Tap again" so you can't lose a match by accident. The game pauses itself when the app goes to the background or loses focus. The end screen got a "Main menu" button.
- New `SaveData` autoload saves to `user://save.json` safely (write a temp file, read it back, then rename; if the game dies between the two, the temp file is loaded next time). Progression will be stored there too.
- Fixed: the end-of-match screen and the floating numbers layer had zero size (their full-screen anchors were set after they were already on screen), so the end screen sat in the top-left corner without the dark backdrop. Now centred and dimmed.
- Customize and Stats are placeholder screens until Prompt 15.
- New smoke suite `menus` (60 checks) and a scene-flow test (`scenes/tools/flow_test.tscn`, 10 checks: menu → match → pause → quit → Daily). All 224 smoke checks pass. Solo matches play out exactly as before (same seeds give identical results).

**What to test**
- Launch the game: the main menu appears. Try every button; Back (and the phone's back button) returns.
- Skirmish: pick Small + 2 bots + Hard, and type a seed like `castle`. Play, then Restart from the pause menu: same map. Clear the seed: a new map each time.
- Teams: your ally's Crown appears next to yours. Try tapping your ally's land (nothing happens except a message), press Send 20% to ally, and watch your ally send you troops when you're under attack. Win as a team.
- Daily Challenge: play, finish (win or lose), check the score on the end screen and on the Daily screen; play again and see the best stay.
- Press Menu mid-match: the game freezes; Resume, Restart (tap twice) and Quit (tap twice) work. Switch to another app on your phone and come back: the game is paused.

## Prompt 15: Progression and cosmetics

**Built**
- **XP** after every finished match (win, loss, or your Crown falling): 100 for playing, +10 per 1% of peak land, +150 per Crown taken, +300 for a win, ×1.5 when you picked Hard bots. The tutorial gives none. **Levels**: going from level n to n+1 takes 500 + 100 × n XP (600 for level 2, 700 for level 3, …).
- The end screen now shows "+1,330 XP" with the breakdown, a bar that fills up level by level, a "LEVEL UP!" pop (with sound and a buzz), what you unlocked, and the achievements you earned this match. When you win, your victory effect plays over the screen.
- **Unlocks** (all cosmetic): 16 territory colours (4 free, then one per level up to 13), 6 patterns (Stripes 2, Dots 4, Checks 6, Waves 8, Scales 10, Bricks 14), 8 Crown icons (Classic free, then Tiara 3, Laurel 5, Star 7, Horned 9, Jewel 11, Circlet 13, Imperial 15), titles (Squire, Knight 3, Baron 6, Count 9, Duke 12, Monarch 15, Emperor 20, plus one per achievement) and victory effects (Fireworks free, Confetti 5, Golden rain 10). Every level from 2 to 15 unlocks something.
- **Customize** screen: tabs for Colour, Pattern, Crown, Title and Victory effect; locked choices show the level that unlocks them; a live preview shows a patch of land in your colour and pattern with your Crown and "Title · Level". Choices are saved immediately and used in your next match: your land gets your colour and pattern, your Crown its icon. A bot whose colour would clash with yours gets a different one. The colour-blind palette always wins over a custom colour.
- **Achievements** (12): the design's Kingslayer, Underdog, Island King, Speedrun, Dominion, plus First Victory, Hard Won (beat Hard bots), Untouchable (win without your Crown ever being attacked), Master Builder (8 buildings in a match, walls don't count), Peacemaker (3 truces in a match), Team Player (win a Teams match after sending your ally 1,000+ troops), Siege Lord (take a Crown during the Final Siege). Each unlocks a title. A gold banner pops up when you earn one (Kingslayer and Siege Lord pop the moment they happen). The Achievements screen (from Stats) shows each with the date you earned it.
- **Stats** screen: level and XP, matches, wins, win rate, Crowns captured, fastest win, best peak land, best Daily score, achievements, and played/won per mode. The main menu shows your title, level and an XP bar.
- Everything is saved in `user://save.json` (temp file → check → rename). A missing or corrupt save never crashes the game; the smoke tests back up your real save and put it back afterwards.
- Fixed: a floating "+N plunder" number could stay frozen on screen after it expired or after starting a new match.
- New smoke suite `progression` (53 checks). All 277 smoke checks + 10 flow checks pass.

**What to test**
- Finish a match: watch the XP bar fill and, the first time, the LEVEL UP pop with the list of unlocks. Win once to see the fireworks.
- Take 3 Crowns in one match: the Kingslayer banner appears straight away.
- Customize: pick a colour, pattern and Crown; check the preview, then start a match and find your land and Crown. Try the Title tab after earning an achievement.
- Stats and Achievements screens after a few matches; close and reopen the game to check everything was saved.

## Prompt 16: Tutorial

**Built**
- An interactive tutorial (`scripts/tutorial.gd`) on a Small map with 1 Easy bot and no timers: no placement countdown, no Final Siege, no 15:00 limit and no Dominion win — it ends when a Crown falls. The tutorial bot never goes for your Crown (it's a lesson, not a trap).
- 7 steps, each with a gold card at the top ("Tutorial · Step 3 of 7") and a bouncing arrow that points at exactly what to tap; arrows to things off screen sit at the screen edge pointing the way. Each step waits until you've done it:
  1. Place your Crown (the arrow suggests a spot near the bot so you meet sooner).
  2. Expand: tap free land; grow 25 tiles.
  3. Watch the troop bar's sweet spot (the arrow points at the bar; passes when it glows green).
  4. Attack the bot (says how long the peace period has left, and to grow towards the bot until your borders touch).
  5. Build a Fort: long-press your land facing the bot; with the build menu open the arrow moves to the Fort button.
  6. Use Crown Shield (arrow on the button).
  7. Take the bot's Crown (camera jumps to it, arrow on it).
- **Skip tutorial** is on the card the whole time. Finishing shows "Tutorial complete!" with Play a Skirmish / Main menu; losing your Crown shows Try again.
- It starts by itself the first time the game opens (until you finish or skip it once) and can be replayed from **Settings → Replay tutorial**. First-time tips stay quiet during the tutorial, and the tutorial gives no XP or stats.
- New smoke suite `tutorial` (34 checks: walks all 7 steps with real taps and long-presses, Try again, the no-timer rules) and 3 more flow checks (first launch starts the tutorial, Skip returns to the menu, the next launch opens the menu). All 311 smoke checks + 13 flow checks pass; solo matches still play out identically.

**What to test**
- Delete your save (or use a fresh install) and launch: the tutorial should start. Follow every step on your phone; check the arrow always points somewhere sensible, especially for the long-press Fort step.
- Skip it, restart the game: it shouldn't come back. Then Settings → Replay tutorial.
- Is anything confusing in the step texts? They're all in `scripts/tutorial.gd` (`_update_text`).

## Prompt 17: Balance pass 1

**Starting point** (100 matches, Medium, 8 bots, Mixed, + 100 "1 Hard vs 7 Easy"; `reports/balance_2026-10-06_p17_baseline.md`): median match **4:55** (target 7–11) and Ports used in **19%** of matches (target 30%) failed; Turtle wins (35%) and "leader at 3:00 wins" (53%) were right at their limits.

**Why matches were short.** I logged every match minute by minute: the whole map is claimed by 2:00 (75% free at 1:00, 0% at 2:00) and Crowns start falling at 2:00 (median Crown fall 2:45). A freshly expanded empire holds about 1 troop per tile, and Crown / zone / Fort defense all *multiply* that tiny number, so raising Crown defense multipliers barely changed anything (tested). The flat part of the attack cost is what makes conquest cost real troops.

**How I tested.** One number at a time. Candidates were first screened with quick 40–60-match runs (each applied alone, then reverted), then each real change was rerun on 50 matches + 50 Hard checks. From change 4 on I reran on the full **100 + 100**, because 50-match samples swung the Turtle share by ±7 points and these targets sit right at their limits. A change was kept only if it helped without breaking a passing target.

| # | Number (`scripts/balance.gd`) | Old → New | Why | Result | Kept? |
| --- | --- | --- | --- | --- | --- |
| 1 | `ATTACK_TILE_COST_BASE` | 2 → **6** | Crowns fell for almost nothing right after the land rush | 50 matches: median 5:01 → 6:50, Port 24% → 28%, Bombard 76% → 94%; Turtles 36% → 42% | Yes |
| 2 | `FORT_COST_BASE` | 300 → **400** | Turtles winning too often (the design's own fix: raise Fort cost) | 50: median 8:18, Port 32%, Turtles 40%, Hard vs Easy 60% | Yes |
| 3 | `BUILDING_DEFENSE_CAP` | ×4 → **×3.5** | Turtles still 40%: cap the Fort × Wall × Crown-zone stack | 50: Turtles 36%, median 7:15, Port 30%. Full 100: median 6:47, Turtles 38%, Port 28% | Yes |
| 4 | `DOMINION_WIN_FRACTION` | 60% → **65%** | Median 6:47 on 100 | 100: median 7:31; matches hitting 15:00 rose 4% → 6% (fixed by the bot fix below → 0%) | Yes |
| 5 | `DOMINION_WIN_FRACTION` | 65% → 70% | Port 28%, Turtles 37% | 100: Port 29%, Turtles 37%, 15:00 endings 0% → 4%. Too little gain for changing a headline rule again | **No** |
| 6 | `GROWTH_INTEREST_RATE_PER_SEC` | 0.05 → 0.035 | Turtles park their troops at the growth peak | 100: Turtles 40%, Port 17% | **No** |
| 7 | `BOAT_RANGE_TILES` | 60 → **120** | Bots only place a Port where a boat could reach free land or Ruins | 100: Port 28% → 42%, median 7:02 | Yes |
| 8 | `BOT_ACT_THRESHOLD_PERSONALITY` (Turtle) | +0.10 → **+0.05** | Turtle bots kept a bigger troop reserve than everyone else, sitting at the growth peak *and* at the strongest defense | 100: everything passes (below) | Yes |

**Bot fix (not one of the 8 numbers): the Final Siege push.** The matches that ran to 15:00 were two bots (mostly Easy) trading ~20 small attacks a minute with each other, never building a decisive push. In the Final Siege every bot now saves up to half its troop cap and then attacks with at least 70% of its troops (`BOT_SIEGE_ATTACK_THRESHOLD` 0.50, `BOT_SIEGE_SEND_MIN` 0.70). 15:00 endings went from 6% to 0% with nothing else changing.

**Tried and reverted (code, not a number):** letting Normal bots build Ports too ("teach the bots to use it"). Port use went to 37% but Turtle wins jumped to 51–54%, so I put the code back exactly as it was.

**Final result** (100 matches + 100 Hard checks, seeds 1–100; `reports/balance_2026-10-06_pass1.md`): **all 7 targets pass.**

| Check | Target | Before | After |
| --- | --- | --- | --- |
| Median match length | 7–11 min | 4:55 | **7:55** |
| Wins per personality | No personality above 35% | Turtle 35% | Turtle 35% (Expander 25, Raider 24, Opportunist 16) |
| Land leader at 3:00 wins | Under 55% | 53% | **39%** |
| Decided by the 15:00 limit | Under 5% | 0% | 2% |
| Crowns captured per match | At least 5 of 7 | 5.8 | 5.9 |
| Each building and ability used | ≥ 30% of matches | Port 19% | **Port 38%** (Fort 100, Wall 99, Barracks 91, Swift March 100, Crown Shield 100, Rally 100, Bombard 93) |
| 1 Hard bot vs 7 Easy | Hard wins ≥ 40% | 42% | **56%** |

**Honest caveats**
- Turtles are exactly at the 35% limit; on a different set of seeds they may land a few points either side. If your playtests say Turtles are hard to kill, the next lever is Turtles' Keep/Wall spending.
- In the default Mixed lobby the single Hard bot now wins 60% of matches (was 32%); Easy bots win 8%. Not a target, but Mixed lobbies will feel tougher; watch for it when you play.
- DESIGN.md is updated to match (Dominion 65%, attack cost formula and example, building cap ×3.5, Fort 400, boats up to 120 tiles, the Turtle row, the Final Siege push), and so is the one-line summary in CLAUDE.md.
- Also in this commit: `simulation.gd` had grown past the ~400-line limit, so Teams/Daily logic moved into `scripts/sim/teams_ops.gd` and Crown placement into `CrownsOps`. Results were bit-identical before and after the move. Smoke tests now read Fort costs from Balance instead of hard-coding 300.
- All 311 smoke checks and 13 flow checks pass.

**What to test**
- Play a few Skirmish matches on default settings: do matches last about 7–9 minutes? Does the 2:00–4:00 window feel less like a Crown massacre?
- Watch the endgame after 10:00: bots should make big pushes instead of small back-and-forth attacks.
- Build Forts (now 400) and Walls: do they still feel worth it?
- Try an Archipelago map: with boats reaching 120 tiles, Ports should matter a lot more.

## Prompt 18: Performance and Android

**Profiling** (`scenes/tools/sim_profile.tscn`, now with `--real` to run the way the game does, tick percentiles, how many ticks blow the 10 ms budget, and what the slowest ticks spent their time on). Large map, 12 players, whole matches:

| | Before | After |
| --- | --- | --- |
| Ticks over 10 ms | 96 of 17,616 | **0 of 39,736** |
| Worst tick | 98.8 ms | **9.2 ms** |
| p99 / median tick | 7.4 ms / 0.54 ms | **3.4 ms / 0.76 ms** |

(Numbers are this cloud machine's CPU; a phone is roughly 3–5× slower, which is why I left plenty of headroom. On rare occasions this machine itself stalls for 20–100 ms; those spikes didn't reproduce when the identical match was rerun, so they're not the game.)

What was slow, and the fix:
- **A Crown falling** scanned the whole map twice (turn the loser's land into Ruins, then rebuild every player's border from scratch): 45–60 ms. Now native `find()` jumps straight to the loser's tiles, and the border rebuild is gone (checked over 29 captures that it never changed a single border). The map repaints the new Ruins over ~20 frames instead of in one go.
- **Huge attack rings**: late on a Large map one ring can be 1,000–2,000 tiles, all captured in one tick. A ring is now eaten a slice per tick across its 0.4 s (a quarter per tick), and all attacks together take at most 300 tiles per tick on a Medium map, scaled down by map area (~180 on Large). Only fronts over ~1,000 tiles take a bit longer than 0.4 s. DESIGN.md mentions this.
- **Huge expansion rings** after a Crown falls (2,000 Ruins tiles in one ring): at most 300 tiles per ring and 400 per tick for everyone together; the rest is taken on the next rings.
- **Bots thinking all at once**: at most 2 bot "thinks" per tick (the next bot goes next tick; the starting bot rotates so nobody always waits). Starting an attack walked the attacker's whole border with slow helper calls (7–9 ms on a Large empire); rewritten with inline maths, same result.
- First match tick: the usable-land count is now worked out during map generation (was a full-map scan, 15 ms). Smaller savings in the attack loop (skip Crown and Wall lookups that can't match, Forts in a packed array). The map caches land colours and repaints at most 1,200 changed pixels per frame.
- These change the timing of big fights a little, so I reran the balance check: **all 7 targets still pass** (below).

**Android**
- `export_presets.cfg`: an "Android" preset: app label **Crown Conquest**, package `com.crownconquest.game`, 64-bit and 32-bit ARM, immersive full screen, vibration permission, debug-signed with the editor's debug keystore, output `export/CrownConquest.apk` (git-ignored). The Godot exporter reads it and only complains about the missing templates and SDK, which is what the setup guide installs.
- Landscape: the project uses "sensor landscape" (landscape either way up, never portrait).
- Placeholder icon: a gold crown on a blue tile (`assets/icon/`, made by `tools/make_placeholder_icon.py`): 512 px for the app, 192 px legacy launcher icon, and 432 px adaptive-icon foreground/background layers. Replace the PNGs with real art any time.
- Keep the screen on: on during matches, off in the menus (`DisplayServer.screen_set_keep_on`).
- The project's name is now "Crown Conquest". On Windows, settings and saves now live in `%APPDATA%\CrownConquest` (your PC test progress starts fresh once; phones aren't affected).
- **`docs/ANDROID_SETUP.md`**: beginner, step-by-step for Windows: Java 17, Android Studio's SDK, Godot's export templates, Editor Settings paths, making a debug keystore if needed, developer mode + USB debugging, one-click deploy or an .apk + `adb install`, the command-line export, and a troubleshooting table.
- README rewritten (it was UTF-16 with only a title) with links and the tool commands.
- New smoke suite `android` (14 checks: settings, preset, icons, keep-screen-on, ring slicing, Ruins repaint, tick time on a busy Large match). All 323 smoke checks and 13 flow checks pass.

**Final balance check after the performance work** (`reports/balance_2026-10-06_final.md`, 100 matches + 100 Hard checks): median 7:44, Turtle 31% (Expander 26, Raider 24, Opportunist 19), leader at 3:00 wins 47%, 15:00 endings 3%, 5.9 Crowns per match, least-used item Port 37%, Hard beats 7 Easy 57%. All pass.

**What to test**
- Follow `docs/ANDROID_SETUP.md` and install on your phone. Check: it opens in landscape, the name and icon are right, the screen doesn't dim during a match but does in the menus, vibration works.
- Play a Large map with 11 bots on the phone and watch the busiest moments (several Crowns falling, big pushes after 10:00): does it stay smooth? If not, tell me the phone model and when it stuttered.
- When a Crown falls, the Ruins colour should sweep across the map in about a third of a second.
