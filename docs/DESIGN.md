# Crown Conquest: Game Design & Build Prompts

Oct 6, 2026 · @Ben

Crown Conquest (working title) is a real-time territory game for phones: grow troops, grab land, and capture enemy Crowns while protecting your own. A match lasts about 7–12 minutes against up to 11 bots.

## Overview

Every player has one resource, **troops**, and spends it on everything: grabbing land, attacking, building and powers. Holding more land grows troops faster, so the core decision is always the same: spend now to grow, or save to defend.

**How a match plays**

1. Everyone taps a spot to place their **Crown** (capital). A small circle of land appears around it.
2. For the first minute nobody can attack. Everyone races to grab free land.
3. Borders meet and wars start. You attack neighbours, build forts, use powers, and make truces.
4. Players are knocked out when their Crown is captured. Their land turns into cheap "Ruins" that everyone scrambles for.
5. After 10 minutes the **Final Siege** begins: Crowns get weaker, so the match ends soon.

**How you win:**

- Be the last player with a Crown, or
- Own 60% of all usable land (a **Dominion** win), or
- If the 15-minute limit is reached, own the most land.

**How you lose:** an enemy captures the centre tile of your Crown.

**What makes it different from territorial.io:** the Crown gives every match a target to protect and a target to hunt. Defense buildings, powers with cooldowns, truces, and comeback rules add choices, while short matches suit phones.

## Match flow

&#91;embedded content: match flow · 5 phases\]

The first minute is a peaceful land rush, new tools unlock as borders meet, and the Final Siege at 10:00 forces an ending.

## Core rules and numbers

Troops grow fastest when you're about half full, so the best players keep spending instead of sitting at the cap. All numbers below are starting values. They live in one balance file so they can be tuned (see "How balance gets tested").

The game updates 10 times per second (a "tick"). Each per-second number below is divided by 10 each tick.

### Troops

| Rule | Starting value |
| --- | --- |
| Starting troops | 150 |
| Starting land | a circle of radius 4 around the Crown (49 tiles) |
| Troop cap | 200 + 3 × land tiles |
| Growth per second | 2 + 0.06 × land + 0.05 × troops × (1 − troops ÷ cap) |
| Over the cap (after losing land) | the extra troops shrink by 2% per second |

The last part of the growth formula is "interest": it's biggest at half the cap and zero when full. The HUD shows this with a troop bar that glows green between 35% and 65% of the cap.

### Grabbing free land (expanding)

- Pick a percentage on the send slider (10–100%) and tap free land touching your border. Those troops leave your pool.
- Each free tile costs **2 troops × the terrain's claim cost**. Ruins cost half (1 × claim cost).
- Your border spreads one ring every 0.3 seconds until the sent troops run out. Any troops left over return to your pool.

### Attacking

- Tap enemy land to send troops at that player. You can run up to 3 attacks at once.
- The attack eats one ring of their border tiles every 0.4 seconds, starting from where your lands touch.
- No attacks are allowed during the first 60 seconds of a match.
- Tap an active attack's icon to retreat. 75% of what's left comes back.

Each enemy tile costs the attacker:

```latex
\text{tile cost} = 2 + 1.5 \times D \times \text{terrain defense} \times \text{building defense}
```

Here D is the defender's troops per tile (their troops ÷ their land). Building defense is capped at ×4 (the Crown has its own rules). The defender also loses 0.5 × D troops for every tile they lose, and their troop cap shrinks with their land.

Example: a defender with 2,000 troops on 1,000 tiles has D = 2. A plains tile costs 2 + 1.5 × 2 = 5 troops. A hill tile inside a Fort's range costs 2 + 1.5 × 2 × 1.5 × 1.6 = 9.2 troops.

### Terrain

| Terrain | Share of map | Claim cost | Defense | Notes |
| --- | --- | --- | --- | --- |
| Plains | \~55% | ×1 | ×1 | The default |
| Forest | \~20% | ×1.5 | ×1.25 | Slows attackers a little |
| Hills | \~10% | ×2 | ×1.5 | Best spots for Forts and Crowns |
| Mountains | \~5% | Blocked | Blocked | Can't be owned; natural walls |
| Water | \~10% | Blocked | Blocked | Crossed only with a Port |
| Gem field | \~1%, in clusters of 6–12 | ×3 | ×1 | Each gem tile you own: +0.5% troop growth (max +15%) |

## The Crown

Your Crown is your life: lose its centre tile and you're out. It's well defended, but everyone can see where it is, so the biggest player can get ganged up on.

**Placing it**

- A match starts with a 10-second placement phase. Tap any plains, forest or hill tile at least 12 tiles from the map edge and 24 tiles from another Crown. If you don't tap, a valid spot is picked for you.
- The Crown is a 3×3 block with a crown icon. It's always shown on the map and minimap for everyone.

**Defending it**

- Crown tiles have ×3 defense, and the **Crown zone** (all your tiles within 6 tiles of the centre) has ×1.5.
- Crown tiles use their own defense and ignore the ×4 building cap. The zone bonus counts as building defense, so it stacks with Forts up to the cap.
- When an enemy attack reaches your Crown zone, you get a banner, a vibration, and a "Crown under attack" alert. Tap it to jump the camera there.

**Keep upgrades** (tap your Crown to buy them)

| Level | Cost (troops) | Unlocks at | Crown tiles | Crown zone | Bonus |
| --- | --- | --- | --- | --- | --- |
| Base | Free | Start | ×3 | ×1.5, radius 6 | — |
| Keep 1 | 300 | Start | ×4 | ×1.6, radius 8 | — |
| Keep 2 | 700 | 3:00 | ×5 | ×1.8, radius 10 | Crown Shield cooldown −30 s |
| Keep 3 | 1,500 | 6:00 | ×6 | ×2, radius 12 | +5% troop cap |

**Moving it.** Once per match, from 3:00, you can move your Crown for 20% of your troops. The new spot must be your own land, at least 10 tiles from any enemy border. The move takes 5 seconds, and your Crown has no special defense during that time. Keep levels carry over.

**When a Crown falls**

- Its owner is eliminated and can watch or leave.
- The capturer takes **plunder**: 30% of the loser's troops.
- The loser's land turns into **Ruins** (free land that costs half to claim), and their buildings are destroyed.
- A big announcement plays for everyone: "Blue has taken Red's Crown!"

**Final Siege (from 10:00):** Crown tiles drop to ×1.5, the Crown zone bonus and Keep upgrades stop working, Crown Shield is disabled, and plunder doubles to 60%.

## Buildings and defenses

Buildings cost troops, so every Fort is land you didn't grab. Limits and rising prices stop anyone from becoming an untouchable turtle.

**Rules for all buildings**

- Long-press your own land to open the build menu.
- You can't build within 3 tiles of an enemy border, so you can't drop a Fort in the middle of a fight.
- If an enemy captures a building's tile, the building is destroyed and the attacker gets 25% of its cost back as loot.
- Building defense multiplies together (Fort × Wall × Crown zone) and is capped at ×4. Terrain defense multiplies on top, so the toughest normal tile is a walled hill inside Fort II range: 1.5 × 4 = ×6.

| Building | Cost (troops) | Effect | Limit | Notes |
| --- | --- | --- | --- | --- |
| Fort | 300, then +150 for each Fort you own | Your tiles within 8 tiles get ×1.6 defense | 6 | Upgrade to Fort II for 400: radius 10, ×2.0 |
| Wall | 4 per tile | Drag a line on your own land; each wall tile gets ×2.5 defense | 400 tiles | Drawn as a thick dark border line |
| Barracks | 400, then +200 each | Troop cap +10% | 4 | Unlocks at 1:00 |
| Port | 250 | Launch boat attacks from this coast | 3 | Must touch water |

**Boats.** Tap one of your Ports, then tap a free or enemy coast tile across the water (up to 60 tiles away). A boat carries the troops from your send slider at 8 tiles per second along a water path. When it lands, it claims the landing tile and continues as a normal expansion or attack from there. If the troops can't pay for the landing tile, the boat is lost. Ports matter most on Archipelago maps.

## Abilities

Four powers on cooldowns give short "skill moments" that are easy to use with a thumb. Each one answers a specific situation, so none is always the right choice.

| Ability | Unlocks | Cost | Cooldown | Effect | Best for |
| --- | --- | --- | --- | --- | --- |
| Swift March | Start | Free | 45 s | For 8 s, grabbing free land is 2× faster and 25% cheaper | The opening land rush and racing for Ruins |
| Crown Shield | Start | Free | 120 s (90 s with Keep 2) | For 8 s, your Crown and Crown zone can't be captured. Disabled in Final Siege | Surviving a surprise Crown attack |
| Rally | 1:30 | 10% of troops | 60 s | For 10 s, your attacks pay 30% less per tile | Finishing a big push |
| Bombard | 3:00 | 15% of troops | 75 s | Pick an enemy spot within 20 tiles of your border. For 12 s, tiles within 5 tiles of it have half defense, and the owner loses 2 troops per tile hit | Breaking Forts, Walls and Crown zones |

The ability bar shows 4 buttons along the bottom edge, each with a cooldown ring and a lock icon until it unlocks. The troop cost is paid when you press it.

## Fair play

The biggest risk in territory games is snowballing: whoever gets big early wins every time, and everyone else stops having fun. These rules slow the leader down and give small players a real chance, without stopping a skilled player from winning.

| Rule | When it applies | Effect |
| --- | --- | --- |
| Peace period | 0:00 to 1:00 | Nobody can attack |
| Underdog | Your land is under 50% of the average land of players still alive | Troop growth +25%; free land and Ruins cost 25% less |
| Empire upkeep | You own over 20% of the map | Troop growth −15% (−30% over 35%) |
| Rising Empire | One player owns over 30% of the map | Everyone else's attacks on them pay 15% less per tile; bots target them; they get a "Rising Empire" icon |
| Ruins | A Crown falls | The loser's land becomes cheap land for everyone, not a free gift to the capturer |
| Final Siege | From 10:00 | Crowns weaken, so matches can't stall forever |

Growth bonuses and penalties add together. For example, +10% from gems and +25% from Underdog makes growth ×1.35.

### Truces

- Long-press an enemy's land to open their info panel, then tap **Offer truce**.
- Bots answer within 2 seconds. They're more likely to accept if they're already fighting someone else, or if you're bigger than them.
- A truce lasts 90 seconds. Neither side can attack the other. You can have 2 truces at once.
- Attacking during a truce makes you an **Oathbreaker**: your attacks pay 20% more for 45 seconds, and every bot refuses your truces for the rest of the match. Bots can break truces too, and get the same penalty.

## Bots

Bots follow exactly the same rules and costs as you, with no hidden bonuses. Difficulty only changes how fast and how smartly they think, so beating a Hard bot always feels earned.

| Difficulty | Thinks every | Sends per move | Uses | Special rules |
| --- | --- | --- | --- | --- |
| Easy | 2.5 s | 20–40% | Forts, rarely | Won't attack your Crown before 4:00; makes a random move 20% of the time |
| Normal | 1.5 s | 30–60% | Forts, Barracks, Keep 1, Swift March, Crown Shield | Looks for weak borders |
| Hard | 0.8 s | 40–80% | Everything | Keeps troops near the sweet spot; combines Bombard + Rally on Crowns; retreats from losing attacks |

Each bot also gets a personality, so matches feel different:

| Personality | Plays like | Weakness |
| --- | --- | --- |
| Expander | Grabs free land fast; attacks once free land runs out | Thin defenses |
| Raider | Attacks its weakest neighbour; races for Ruins | Overextends and runs low on troops |
| Turtle | Builds Forts, Walls and Keep upgrades early; counterattacks | Grows slowly |
| Opportunist | Attacks whoever is busy fighting someone else; breaks truces 20% of the time | Other bots stop trusting it |

Bots get fantasy names built from a title and a name, like "Duke Ashford" or "Lady Vex". The default match has 7 bots with a mix of personalities. Skirmish setup offers Easy, Normal, Hard, or Mixed (3 Easy, 3 Normal, 1 Hard).

## Modes, maps and progression

Variety comes from modes and map types, and the reason to keep playing comes from cosmetic unlocks and achievements. Nothing you unlock makes you stronger.

### Modes

| Mode | How it works |
| --- | --- |
| Skirmish | You vs bots. Choose map size, map type, number of bots, and difficulty |
| Teams | 4 teams of 2: you and a bot ally vs 3 bot pairs. Allies can't attack each other and can send each other 20% of their troops. The last team with a Crown wins |
| Daily Challenge | Everyone gets the same map and settings each day (the date sets the map seed). Score = peak land % + a time bonus for winning fast. Your best score is saved |
| Online multiplayer | Planned for after launch |

### Maps

| Size | Grid | Players |
| --- | --- | --- |
| Small | 160 × 96 | 5 |
| Medium (default) | 200 × 120 | 8 |
| Large | 260 × 156 | 12 |

Map types: **Continent** (one big landmass with lakes), **Archipelago** (islands with about 35% water, so Ports are essential), **Highlands** (lots of hills and mountain passes), and **Random**.

### Progression

- **XP per match:** 100 for playing, +10 per 1% of peak land, +150 per Crown captured, +300 for a win. Hard matches give ×1.5.
- **Levels:** level n needs 500 + 100 × n XP.
- **Unlocks:** 16 territory colours, 6 patterns (stripes, dots, checks, waves, scales, bricks), 8 Crown icons, titles, and victory effects like fireworks.
- **Achievements**, for example: Kingslayer (take 3 Crowns in one match), Underdog (win after being the smallest player at 3:00), Island King (win on Archipelago using 3 Ports), Speedrun (win in under 6 minutes), Dominion (win by owning 60% of the land).
- **Stats screen:** matches, wins, win rate, Crowns captured, fastest win, best Daily score.

If you ever earn money from the game, sell only cosmetics and "remove ads". Never sell troops, powers or upgrades, because pay-to-win ruins balance.

## Mobile controls and game feel

Everything works with one thumb: tap to act, long-press for menus, and a slider for how many troops to send. Feedback (flashes, sounds, vibration) makes every capture feel satisfying.

| Action | Gesture |
| --- | --- |
| Expand | Tap free land touching your border |
| Attack | Tap enemy land touching your border |
| Choose how many troops | Send slider, plus quick buttons for 25%, 50%, 75% and 100% |
| Build | Long-press your own land |
| Enemy info and truces | Long-press enemy land |
| Boat attack | Tap your Port, then a coast across the water |
| Retreat | Tap an active attack's icon |
| Move the camera | Drag with one finger, pinch to zoom, double-tap the Crown button to jump home |
| Use a power | Tap one of the 4 ability buttons |

**Screen layout**

- **Top:** troop bar (glows green in the sweet spot), troops per second, land %, match timer.
- **Top right:** leaderboard of the top 5 players by land, with Crown icons for players still alive.
- **Bottom:** send slider and the ability bar. Buttons are at least 56 pixels tall so thumbs don't miss.
- **Corner:** a minimap. Tap it to jump the camera there.

**Game feel**

- Captured tiles flash briefly, and active attack fronts pulse.
- When any Crown falls: screen shake, a short slow-motion moment, and a fanfare. It's bigger if it's your Crown or you took it.
- Vibration when your Crown is attacked, when a Crown falls, and when an ability is ready.
- Floating numbers for rewards, like "+1,240 plunder" and "+75 loot".
- Sounds: soft ticks while expanding, drums during attacks, a horn for the Crown alarm. Music gets more intense in the Final Siege.
- Settings: sound, music, vibration, a colour-blind palette, and a left-handed layout that mirrors the controls.

## How balance gets tested

The numbers in this doc are a careful starting point, but no game is balanced on paper. Balance is proven with a **simulator** that plays hundreds of bot-only matches at high speed, plus your own playtests. Prompt 7 builds the simulator, and Prompt 17 uses it for a full balance pass.

**Three rules that make tuning easy**

1. Every number lives in one file, `scripts/balance.gd`. Tuning means changing numbers there, never rewriting code.
2. Change one number at a time, then rerun the simulator and compare.
3. If a bot strategy wins too often, make that strategy cost more. Never give bots secret bonuses.

**Simulator targets** (Medium map, 8 bots, Mixed difficulty, 100 matches)

| Check | Target | If it's off |
| --- | --- | --- |
| Median match length | 7–11 minutes | Too long: lower Crown defense or start Final Siege earlier. Too short: raise Crown defense |
| Wins per personality | No personality above 35% | Make the winning strategy cost more (for example, raise Fort cost if Turtles win) |
| Land leader at 3:00 goes on to win | Under 55% of matches | Strengthen Underdog and Rising Empire |
| Matches decided by the 15:00 time limit | Under 5% | Weaken Crowns in Final Siege |
| Crowns captured per match | At least 5 of 7 | Lower Crown or Fort defense |
| Each building and ability used | In at least 30% of matches | Make the unused one cheaper or stronger |
| 1 Hard bot vs 7 Easy bots | Hard wins at least 40% | Improve the Hard bot's thinking, don't buff its numbers |

**Playtest checks** (by you and friends)

- A brand-new player beats Easy bots within 3 tries.
- A practised player wins about 70% vs Easy, 40% vs Normal and 15% vs Hard.
- There's never a stretch of 30+ seconds where nothing interesting happens.
- Losing your Crown feels like your mistake, not bad luck.

## How to use the build prompts

The 18 prompts below build the whole game in order, one stage at a time. Each one points Claude at this design, so first you save this doc into your project.

**Before Prompt 1: put this design in your project**

1. At the top of this doc, click its name, choose **Export**, then **Markdown**. The file goes to your Downloads folder.
2. Start Claude Code in your project folder and type: `There's a Markdown file in my Downloads folder about Crown Conquest. Copy it into this project as docs/DESIGN.md.` Approve when it asks.

**For every prompt**

1. Type `/clear` first. This gives Claude a fresh start, and the files from Prompt 1 keep it on track.
2. Copy the whole grey box and paste it into Claude Code. A long paste shows as "\[Pasted text\]", which is fine. Press Enter.
3. Answer any questions Claude asks, and approve its changes.
4. When it's done, press **F5** in Godot and play. If something looks wrong, describe what you see: "When I tap free land, nothing happens."
5. When you're happy, make sure it committed (each prompt asks it to). If a stage goes badly wrong, say `Go back to the last commit` and try again.

For the bigger prompts, you can press **Shift + Tab** until Claude Code shows plan mode before pasting. Claude then explains its plan first and waits for your OK.

If you change any numbers later, ask Claude to update docs/DESIGN.md too, so the design and the game stay in sync.

### Prompt 1: Foundation

If you already ran the earlier "stage 2" prompt from chat, that's fine: these prompts update what's there.

```text
Read docs/DESIGN.md, our full game design. We'll build it step by step.

1. Create CLAUDE.md in the project root with a 5-line summary of the game (a landscape mobile game), the rule "Always follow docs/DESIGN.md", and these coding rules:
- Godot 4, GDScript with typed variables.
- Map data lives in packed arrays (PackedByteArray / PackedInt32Array), never one node per tile.
- The map is drawn as one Image texture; only changed pixels are updated, once per frame.
- Game logic runs on a fixed 10 ticks per second, separate from drawing.
- All game rules live in plain scripts under scripts/sim/ that never touch nodes or the screen, so a match can run without graphics for the balance simulator.
- Every balance number comes from scripts/balance.gd, never typed into other scripts.
- Random numbers come from one seeded RandomNumberGenerator, so a match can be replayed from its seed.
- Keep scripts under about 400 lines; split them when bigger.
- After every change: run the project, read the debug output, and fix all errors and warnings.

2. Create scripts/balance.gd as an autoload named Balance containing every number from docs/DESIGN.md (troops, terrain, combat, Crown, Keep, buildings, abilities, fair play, bots, XP), grouped with comments.

3. Restructure the existing code to follow these rules: a GameState class in scripts/sim/ that owns the map arrays and players, a Simulation that ticks it 10 times per second, and a Map node that only draws.

Run the project, fix any errors, tell me what to check, then commit as "Foundation".
```

### Prompt 2: Troops and expansion

```text
Following docs/DESIGN.md "Core rules and numbers", build (or update, if parts already exist) troops and expansion for the player:
- Troop cap, growth formula and over-cap shrink exactly as designed, using Balance values.
- HUD at the top: a troop bar showing troops / cap that glows green between 35% and 65%, troops per second, and land %.
- At the bottom: a send slider (10-100%) with quick buttons for 25/50/75/100%, big enough for a thumb.
- Tapping free land touching my border sends the chosen % of troops. The border spreads one ring every 0.3 s, each tile costs 2 x the terrain claim cost (everything is plains for now), and leftover troops return.
- Keep a set of border tiles per player, updated as tiles change, instead of scanning the whole map.

Run it, fix errors, tell me what to test, then commit as "Troops and expansion".
```

### Prompt 3: Terrain and maps

```text
Following docs/DESIGN.md "Terrain" and "Maps", add map generation:
- Generate terrain with FastNoiseLite from the match seed: plains, forest, hills, mountains, water, and gem field clusters, close to the shares in the terrain table.
- Map types Continent, Archipelago, Highlands and Random; sizes Small, Medium and Large. Default: Medium Continent.
- Give each terrain its own colour. Owned land shows the owner's colour with a hint of the terrain, so hills and forests stay visible.
- Apply terrain claim costs, blocked tiles, and the gem growth bonus.
- Camera: drag to pan, pinch to zoom (mouse wheel on PC), kept inside the map.
- Add a temporary "New map" debug button that regenerates with a new seed.

Run it, fix errors, tell me what to test, then commit as "Terrain and maps".
```

### Prompt 4: Players, Crowns and basic bots

```text
Following docs/DESIGN.md ("The Crown: Placing it", "Bots", "Fair play"), add multiple players:
- Support up to 12 players with distinct colours and generated fantasy names.
- A 10-second placement phase with a countdown: I tap a valid spot (rules in the design), bots pick valid spots spread apart, and if I don't tap, pick one for me.
- Draw each Crown as a 3x3 block with a crown icon, visible to everyone.
- Basic bots that only expand into free land for now, using exactly the same rules as me.
- Peace period: no attacks until 1:00, with a "Peace ends in" timer.
- A leaderboard in the top right showing the top 5 players by land, and a match timer at the top.

Run it, fix errors, tell me what to test, then commit as "Players and bots".
```

### Prompt 5: Combat

```text
Following docs/DESIGN.md "Attacking", add combat:
- Tapping enemy land touching my border attacks that player with the slider %. Allow up to 3 attacks at once, each shown as an icon with its remaining troops. Tapping the icon retreats (75% returns).
- Use the exact tile cost formula and defender losses from the design, including terrain defense. Building defense is x1 for now, but put it in one function we can extend later.
- Attacks advance one ring every 0.4 s from where our lands touch.
- Players who lose land and end up over their cap shrink by 2% per second.
- Bots attack too: once free land runs out near them, they attack their weakest neighbour.
- When an enemy attacks me, flash my border where it's happening.

Run it, fix errors, tell me what to test, then commit as "Combat".
```

### Prompt 6: Crowns and winning

```text
Following docs/DESIGN.md "The Crown" and "How you win", add:
- Crown defense: Crown tiles x3, and the Crown zone x1.5 within radius 6 (Keep upgrades come later).
- Capturing a Crown's centre tile eliminates that player: 30% plunder to the capturer, all their land becomes Ruins (half claim cost, with its own greyish look), and a big announcement for everyone.
- A "Crown under attack" alert with vibration (Input.vibrate_handheld) and tap-to-jump.
- Win conditions: last Crown standing, 60% of usable land (Dominion), or most land at 15:00.
- Final Siege at 10:00 with weakened Crowns and 60% plunder, plus an on-screen announcement.
- Victory and defeat screens with stats (time, peak land %, Crowns taken) and Play again / Watch buttons. After defeat I can keep watching.

Run it, fix errors, tell me what to test, then commit as "Crowns and winning".
```

### Prompt 7: Balance simulator

```text
Following docs/DESIGN.md "How balance gets tested", build a balance simulator:
- A script that runs without graphics (headless) and plays N bot-only matches at full speed, using the same scripts/sim code as the real game, with random seeds.
- Settings at the top: number of matches, map size and type, number of bots, difficulty mix.
- For each match, record: length, winner and their personality/difficulty, how it ended, the land leader at 3:00, Crowns captured, and which buildings and abilities were used (some don't exist yet; handle that).
- At the end, print a report comparing the results with the targets table in the design (PASS / FAIL) and save it as reports/balance_<date>.md.
- Explain the exact command I can use to run it myself.

Then run 20 matches, show me the report, and suggest which Balance numbers to change first, without changing them yet. Commit as "Balance simulator".
```

### Prompt 8: Buildings and Keep upgrades

```text
Following docs/DESIGN.md "Buildings and defenses" and the Keep upgrades table, add:
- Long-press my land to open a build menu showing each building's cost, effect and how many I have left. Grey out options I can't afford, or that are within 3 tiles of an enemy border.
- Fort and Fort II, Wall (drag along my land to draw it, showing the cost while I drag), Barracks and Port, with costs, limits and unlock times from Balance.
- Building defense multiplies Fort x Wall x Crown zone, capped at x4, applied in the combat cost function.
- Captured buildings are destroyed and give the attacker 25% of their cost as loot, shown as a floating "+loot" number.
- Keep upgrades: tap my Crown to buy Keep 1-3 with their unlock times and effects.
- Boats: tap my Port, then a coast across water within 60 tiles. The boat follows a water path at 8 tiles/s, lands, and continues as an expansion or attack.
- Normal and Hard bots build Forts and Barracks sensibly.

Run it, fix errors, tell me what to test, then commit as "Buildings".
```

### Prompt 9: Abilities

```text
Following docs/DESIGN.md "Abilities", add Swift March, Crown Shield, Rally and Bombard:
- An ability bar along the bottom: 4 buttons with icons, cooldown rings, the troop cost, and lock icons until each unlocks.
- Bombard asks me to tap a target in range and shows the area before I confirm.
- A clear visual for each active effect: a shield bubble on the Crown, glowing attack fronts during Rally, cracked tiles under Bombard.
- Normal bots use Swift March and Crown Shield; Hard bots use all four.

Run it, fix errors, tell me what to test, then commit as "Abilities".
```

### Prompt 10: Fair play and truces

```text
Following docs/DESIGN.md "Fair play", add:
- The Underdog, Empire upkeep and Rising Empire rules using Balance values, with small icons next to my troop bar that explain any bonus or penalty affecting me.
- A Rising Empire icon next to that player on the map and leaderboard.
- Long-pressing enemy land opens their info panel: name, land, troops, a personality hint, and an Offer truce button.
- Truces with the duration, limit and Oathbreaker penalty from the design. Show truce partners with a white-flag icon and a countdown.
- Bots accept, refuse and sometimes break truces as the design describes.

Run it, fix errors, tell me what to test, then commit as "Fair play and truces".
```

### Prompt 11: Smarter bots

```text
Following docs/DESIGN.md "Bots", upgrade the bot AI:
- Easy, Normal and Hard difficulties exactly as in the difficulty table (thinking speed, send amounts, what they use, special rules).
- Expander, Raider, Turtle and Opportunist personalities as in the personality table.
- Bots score their possible moves (expand, whom to attack, what to build, which ability, whether to offer a truce) and pick the best one. Difficulty controls how often they pick a worse move.
- Keep all bot code in scripts/sim/ so the simulator uses it. Bots must never get bonuses the player doesn't have.

Then run the simulator for 50 matches and show me wins by personality and difficulty. Commit as "Smarter bots".
```

### Prompt 12: Mobile controls and HUD

```text
Following docs/DESIGN.md "Mobile controls and game feel", polish the controls and HUD for phones:
- Set the project to landscape. Lay out the screen exactly as in "Screen layout", using anchors and containers so nothing overlaps on any phone shape. Buttons at least 56 px tall.
- A minimap in the corner (tap to jump there) and a Crown button (double-tap to jump home).
- Make tap vs long-press reliable on touch screens, and show a short hint the first time I do each action.
- Alerts appear as a queue of banners at the top that never cover the controls.
- A left-handed layout option.

Test with the window at phone sizes (2400x1080 and 1920x1080), fix anything that overlaps or is too small, then commit as "Mobile UI".
```

### Prompt 13: Game feel, sound and vibration

```text
Following docs/DESIGN.md "Game feel", add:
- Capture flashes, pulsing attack fronts, and floating numbers for plunder and loot.
- When a Crown falls: screen shake, a short slow-motion moment, and a fanfare, stronger if it involves me.
- Vibration when my Crown is attacked, when any Crown falls, and when an ability is ready, respecting the vibration setting.
- Sound effects and music. Use clearly named placeholder files in assets/audio/ that I can replace with free sounds later. Music gets more intense in Final Siege.
- Settings for sound, music, vibration and a colour-blind palette.

Make sure none of this slows the game down. Run it, fix errors, then commit as "Game feel".
```

### Prompt 14: Menus and modes

```text
Following docs/DESIGN.md "Modes" and "Maps", add:
- Main menu: Play (Skirmish), Teams, Daily Challenge, Customize, Stats, Settings.
- Skirmish setup: map size, map type, number of bots, difficulty (Easy/Normal/Hard/Mixed), optional seed.
- Teams mode: 4 teams of 2 with a bot ally. Allies can't attack each other, there's a "Send 20% to ally" button, and the team wins together.
- Daily Challenge: seed from today's date, fixed settings, the score from the design, best score saved.
- A pause menu (resume, restart, settings, quit). The game pauses when the app goes to the background.

Run it, fix errors, tell me what to test, then commit as "Menus and modes".
```

### Prompt 15: Progression and cosmetics

```text
Following docs/DESIGN.md "Progression", add:
- XP and levels as designed, shown after each match with a level-up animation.
- A Customize screen to choose unlocked territory colours, patterns, Crown icons and titles, with a live preview.
- Achievements: the ones in the design plus about 7 more that fit the game, with an achievements screen and a pop-up when one is earned.
- A Stats screen.
- Save everything to user://save.json safely (write to a temp file, then rename it), so a crash can't wipe progress.

Run it, fix errors, tell me what to test, then commit as "Progression".
```

### Prompt 16: Tutorial

```text
Add a short interactive tutorial that starts the first time the game opens and can be replayed from Settings:
- A small map with 1 Easy bot and no timer.
- Steps with arrows and short text: place your Crown, expand, watch the troop bar's sweet spot, attack the bot, build a Fort, use Crown Shield, capture the bot's Crown.
- Each step waits until I do it, and there's a Skip button.

Run it, fix errors, tell me what to test, then commit as "Tutorial".
```

### Prompt 17: Balance pass

```text
Run the balance simulator for 100 matches on default settings (Medium map, 8 bots, Mixed difficulty) and compare the results with the targets in docs/DESIGN.md.

For each failing target, change ONE Balance number at a time, rerun 50 matches, and keep the change only if it helps without breaking another target. Repeat until every target passes or you've made 8 changes.

Then show me a table of every number you changed (old -> new, and why), update the tables in docs/DESIGN.md to match, and commit as "Balance pass 1".
```

### Prompt 18: Performance and Android

```text
Prepare the game for phones:
- Profile a Large map with 12 bots at the busiest moment of a match. Make sure each game tick takes under 10 ms, and fix anything slower.
- Set up Android export: landscape, app name "Crown Conquest", a placeholder icon, and keep the screen on during matches.
- I'm a beginner: walk me step by step through installing what Godot needs for Android export (Android SDK, Java, debug keystore) and installing the game on my own phone.

Commit as "Ready for Android".
```

### After Prompt 18

Play it on your phone and give it to a few friends. Write down what felt unfair or boring, and describe it to Claude in plain words: "Turtle bots are too hard to kill" or "Nothing happens between minutes 4 and 6." Then rerun Prompt 17. Online multiplayer is the next big step after that, and it's easier because the game logic is already separate from the graphics.
