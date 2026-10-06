# Crown Conquest

**Crown Conquest** is a landscape real-time territory game for phones. Grow troops, grab land, and capture enemy Crowns while protecting your own. One match lasts 7-12 minutes against up to 11 bots. You win by being the last with a Crown, owning 60% of usable land (Dominion), or holding the most land when the 15-minute limit hits.

## Always follow docs/DESIGN.md

The full design lives in `docs/DESIGN.md`. Treat it as the source of truth. If anything in this file conflicts with the design, the design wins.

## Coding rules

- Godot 4, GDScript with typed variables.
- Map data lives in packed arrays (`PackedByteArray` / `PackedInt32Array`), never one node per tile.
- The map is drawn as one `Image` texture; only changed pixels are updated, once per frame.
- Game logic runs on a fixed 10 ticks per second, separate from drawing.
- All game rules live in plain scripts under `scripts/sim/` that never touch nodes or the screen, so a match can run without graphics for the balance simulator.
- Every balance number comes from `scripts/balance.gd`, never typed into other scripts.
- Random numbers come from one seeded `RandomNumberGenerator`, so a match can be replayed from its seed.
- Keep scripts under about 400 lines; split them when bigger.
- After every change: run the project, read the debug output, and fix all errors and warnings.
