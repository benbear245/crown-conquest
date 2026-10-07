# Crown Conquest: what to build next

Oct 7, 2026

## Where the game stands

- **All 18 build prompts are done.** The game has Skirmish, Teams, Daily Challenge, four map types and three sizes, Crowns with Keep upgrades, Forts/Walls/Barracks/Ports and boats, four abilities, fair-play rules and truces, Easy/Normal/Hard bots with four personalities, the phone HUD, XP and cosmetics, a tutorial and an Android preset. All smoke and flow checks pass.
- **The balance targets all pass, but the matches all play out the same way.** In the last 100 simulated matches the median length was 7:44. 87 of 100 ended by Dominion (65% of the land), only 10 by taking the last Crown, and 3 at the 15:00 limit. The whole map is claimed by about 2:00 and Crowns start falling around 2:00–2:45. In the default Mixed lobby the single Hard bot wins 53% and Easy bots win 5%. Boats were used in only 10% of matches.
- **The reports don't show two stalls.** When only two players are left, they spend 63% of that time in truces. 27 of 60 test matches had a stretch of 30 seconds or more where almost nothing happened. Archipelago hits the 15:00 limit in 5 of 24 matches (target: under 5%), because only Hard bots ever build Ports. The reports only ever ran Continent, so neither problem appeared there.
- **The phone experience needs work.** The export fails (ETC2/ASTC). The Back button quits the app mid-match. At the starting zoom one tile is smaller than 1 mm. Buttons come out around 20 dp (Android recommends 48 dp) and text around 6–9 sp (12 sp is the usual minimum). New players are never shown the 65% Dominion target, even though Dominion ends most matches.
- **The code and tests have some risks.** Three scripts are over 400 lines (`combat_ops.gd` 493, `simulation.gd` 426, `balance.gd` 416). The smoke and flow tests write to your real save while they run. A corrupt save is silently wiped. Troops vanish in four edge cases. There is no Google Play (.aab) build, no About or privacy page, and no match history, replays or resume.

## Fix this first: the Android export error

Godot 4.7.2 needs ETC2/ASTC texture compression switched on for Android, and this project never turned it on. To fix it now:

1. In Godot, open **Project → Project Settings…**
2. Turn on the **Advanced Settings** switch at the top right.
3. In the left list, open **Rendering → Textures**. Under **VRAM Compression**, tick **Import ETC2 ASTC**.
4. Close the window. If Godot asks to restart, click **Save & Restart**. It re-imports the textures, which takes a few seconds.
5. Click **Remote Deploy** again (top right, just right of the square Stop button; its icon is a small screen with a play arrow).

**The "project name doesn't fit the package-name format" warning is harmless.** The Android preset sets the package name to `com.crownconquest.game` itself. To check, open **Project → Export… → Android → Package → Unique Name**. If your PC made its own preset with another name, change it back to `com.crownconquest.game`.

**Java:** your PC has JDK 25. It already passed Godot's Java check (your error came from the next step), and the normal APK export works with it. Godot recommends JDK 17, though, and the Google Play build in Prompt 20 uses Gradle, which may refuse a Java that new. If an error mentions Java or "Unsupported class file major version", install Temurin JDK 17 (step 1 of `docs/ANDROID_SETUP.md`) and set **Editor → Editor Settings → Export → Android → Java SDK Path** to its folder. You can keep JDK 25 installed for anything else.

Prompt 19 makes the export fix permanent and adds a check so it can't silently break again.

## Feature suggestions

### Before you share the game

| Feature | What the player gets | Effort | Impact | Prompt # |
| --- | --- | --- | --- | --- |
| Android phone fixes: ETC2 export, Back button, notch, themed icon, 60 fps cap | The game installs. Back pauses instead of closing the app mid-match | S | High | 19 |
| Google Play build: .aab preset, upload key, version number | A build Google Play accepts, signed with a key that is backed up | M | High | 20 |
| About screen and privacy policy | Version, credits, licences and a privacy link (Google Play requires the link) | S | High | 20 |
| One-command checks, and tests that never touch your save | `tools\check.ps1` prints one PASS/FAIL. Your PC progress is safe | M | High | 21 |
| Versioned save file and Android backup | Updates never wipe XP or cosmetics, and a new phone restores progress | S | Medium | 21 |
| Code cleanup with proof: split big scripts, typed numbers into Balance, fix doc drift | Nothing visible. Later prompts edit smaller files more safely | M | Medium | 22 |
| Balance comparison check and a "Definition of done" | Every prompt shows it didn't make balance worse | S | High | 22 |
| Forgiving taps, and reasons for failed taps | Tap roughly next to your land and it works. A failed tap says why | S | High | 23 |
| Camera assist | The camera starts zoomed on your Crown, and arrows point to off-screen fights | M | Medium | 23 |
| UI size for real phones | Text and buttons big enough to read and hit | L | High | 24 |
| Dev panel (test builds only) | Jump to 9:50 or run at ×8, so late-match tests take minutes | M | High | 25 |
| Error log, "Copy debug info" and feedback email | Testers send you version, phone, seed and errors in one tap | S | Medium | 25 |
| Playtest kit: one-tap survey, playtest log, PLAYTEST.md | Friends' opinions become numbers you can act on | M | High | 25 |
| Google Play launch checklist | One ordered list. The 14-day closed test starts early | S | High | 25 |

### Biggest gameplay wins

| Feature | What the player gets | Effort | Impact | Prompt # |
| --- | --- | --- | --- | --- |
| First-match ramp and the Dominion target on the HUD | New players face 3 Easy bots first and always see "23% / 65%" | M | High | 26 |
| How-to-Play Codex, with all rule text in one file | 12 short cards whose numbers always match the game | M | Medium | 26 |
| Pacing numbers in the simulator | You can see stalls and how long knocked-out players wait, and prove a fix worked | S | High | 27 |
| Showdown: no truces when two players remain | Endgames finish with a fight instead of 90-second truces | S | High | 27 |
| Stranded Normal bots build Ports (Archipelago) | Island maps stop running to the 15:00 limit | S | High | 27 |
| Troops never vanish (boats, fallen Crowns, truces), and allies count as friendly when building | Troops you send always arrive or come back. Teams allies don't block your Forts | M | Medium | 28 |
| Dominion countdown: hold 65% for 20 s to win | A visible last stand instead of a silent win | M | Medium | 30 |
| Balance pass 2: rebalance attack cost | Hills, Forts and Crown defense start to matter | S | High | 30 |
| Riverlands map type | Rivers you cross only at fords, so holding a ford matters | M | Medium | — |
| Weekly Royal Decrees | One rule twist per week for everyone, bots included | L | Medium | — |
| Quick Undo for attacks | Take back a mis-tapped attack within 0.75 s | S | Medium | — |

### Reasons to keep playing

| Feature | What the player gets | Effort | Impact | Prompt # |
| --- | --- | --- | --- | --- |
| Watch faster or "Skip to result" | After your Crown falls, watch at ×4/×8 or skip straight to the winner | S | Medium | 29 |
| Match history with "Play this map again" | Your last 30 matches, with the seed to replay a great map | S | Medium | 29 |
| War Report | A land graph, key moments and 3 tips after every match | M | Medium | 29 |
| Daily Challenge 2.0 | The same map worldwide (UTC day), streaks, medals and share text | S | Medium | 33 |
| Conquest Ladder, with star goals | 12 ranks from Hamlet to High Throne, giving goals after level 15 | M | High | 33 |
| Daily quests, achievement tiers, levels to 30 | 3 small goals a day | M | Medium | — |

### Polish and feel

| Feature | What the player gets | Effort | Impact | Prompt # |
| --- | --- | --- | --- | --- |
| Art direction sheet, shared Theme and boot splash | One consistent look, and your own splash instead of Godot's | M | Medium | 31 |
| Real CC0 sounds, music and fonts, plus volume sliders | Real drums, horns and fanfares, and music that loops without a gap | M | Medium | 31 |
| Comfort settings: reduce motion, vibration strength, colour-blind borders | Turn off shake and slow-mo, choose a lighter buzz, see thicker borders | S | Low | 31, 32 |
| Battery and heat | 60 fps cap, a 30 fps battery saver, and the screen sleeps while paused | S | Medium | 19, 31 |
| Map readability art pass | Crisp borders, a glow on your border, visible Forts, hatched Ruins | L | High | 32 |

### Later: online multiplayer

| Feature | What the player gets | Effort | Impact | Prompt # |
| --- | --- | --- | --- | --- |
| Match recorder (the seed plus your commands) | The base that resume, replays and multiplayer are built on | M | High | 34 |
| Resume after Android closes the app | A phone call no longer ends your match | M | High | 34 |
| Replays | Watch recent matches at ×1/×4/×16, take clean screenshots, send replay files | M | Medium | 34 |
| Same-Wi-Fi party | 2–8 phones in one room play together, with bots in empty seats | L | Medium | 35 |
| Online rooms with codes | Friends anywhere join with a code, and bots take over dropped players | XL | High | 36 |
| Global Daily leaderboard | "You are #38 of 1,204 today" | L | Medium | — |

**Not now**

- **Riverlands:** wait until Balance pass 2 shows Archipelago and Highlands passing. More chokepoints could add 15:00 endings.
- **Royal Decrees:** each Decree needs its own balance run. Add them after the Ladder, if players ask for variety. Start with Decrees that change a single number, such as peace length or Port cost.
- **Quests, tiers and levels to 30:** the Ladder covers goals after level 15 first. Add these if players run out of goals, and add the new cosmetic types only after the map art pass.
- **Attack Undo:** forgiving taps, the camera zoom and the bigger UI should remove most misclicks. Add Undo if testers keep picking "Mis-tap" in the survey. It needs a balance rerun because bots retreat too.
- **Global Daily leaderboard:** needs internet, a server, and proof that PC and phone simulate identically (Prompt 35). Add it after launch, once people play the Daily every day.
- **Director camera for trailers, and a playtest summary tool:** the first after replays exist and you want a store video, the second if reading tester logs by hand gets slow.

**Ideas we looked at and dropped for now:**
- Heir Fort weakens the rule that losing your Crown ends your game.
- Treasure Isles and Neutral Holds cost a lot for problems the fixes above solve more cheaply.
- War Pacts and ability loadouts add phone clutter and fix nothing that's broken.
- Quick Match needs a player base that doesn't exist yet.
- Ads and purchases would need internet and consent screens before there are any players.

## How to use these prompts

Use the same routine as `docs/DESIGN.md`:

1. Type `/clear` first.
2. Paste the whole grey box into Claude Code and press Enter.
3. Answer questions and approve changes.
4. Press **F5** in Godot and play.
5. Make sure it committed. If a stage goes badly wrong, say `Go back to the last commit`.

On top of that:

- **Use plan mode for the big ones.** Prompts marked "Big one" are long. Press **Shift + Tab** until Claude Code shows plan mode before pasting, so you see the plan first.
- **Prompts with parts.** When Claude stops after Part A, test it, then type `Continue with Part B of Prompt NN`.
- **Manual steps.** Some prompts need your hands (installing Java, making a key, uploading to Google Play). Those prompts tell Claude to stop and wait for you.
- **The balance check runs inside the prompt.** Any prompt that changes match rules runs the balance simulator itself and checks every target. You don't need to do anything extra.
- **Rerun Prompt 17 now and then.** Prompt 30 includes a balance pass. Paste Prompt 17 again after Prompt 33 and after Prompt 35, and add: `Run it on Continent, Archipelago and Highlands, and include the pacing targets.`
- **Test on the phone after every prompt.** Plug it in, click **Remote Deploy**, and play one full match on the phone. Some problems only show up there: tap size, text size, heat and the Back button.
- **Start two slow things today.** Create your Google Play developer account now, because identity checks take days. Also pick the game's final name before the first upload: "Crown & Conquest" already exists, and the package name can't change after that upload.

## The prompts

### Prompt 19: Android release setup (part 1: your phone)

```text
Read docs/DESIGN.md, docs/ANDROID_SETUP.md, docs/PROGRESS.md (Prompt 18), project.godot, export_presets.cfg, scripts/tools/checks_android.gd, scripts/game.gd, scripts/menu/menu_root.gd and scripts/hud.gd. I moved to my Windows PC (Godot 4.7.2, JDK 25 installed) and the Android export failed with "ETC2/ASTC texture compression is required for Android export". Fix the phone build and the Android problems below. No game rules change.

1. Export: set rendering/textures/vram_compression/import_etc2_astc=true in project.godot (it may already be on if I ticked it in the editor).
2. Back button: on Android, Back and the back swipe arrive as NOTIFICATION_WM_GO_BACK_REQUEST, not ui_cancel, and application/config/quit_on_go_back is true by default, so Back quits the app mid-match. Set quit_on_go_back=false. In a match, Back opens the pause menu and Back again resumes. In menus, Back goes to the main screen. On the main screen it asks "Quit Crown Conquest?" (Yes / No). Escape keeps working on PC.
3. Notch: the HUD only re-lays out when the window size changes, so turning the phone 180° may leave the safe-area margin on the wrong side. Re-read DisplayServer.get_display_safe_area() every SAFE_AREA_POLL_SEC = 0.5 and on NOTIFICATION_APPLICATION_FOCUS_IN, and re-lay out if it changed.
4. Battery: set application/run/max_fps=60. While the pause menu is open, let the screen sleep (screen_set_keep_on(false)), and turn it back on when I resume.
5. Themed icon: launcher_icons/adaptive_monochrome_432x432 is empty, so Android 13+ themed icons show Godot's logo. Make a white-on-transparent 432x432 crown with tools/make_placeholder_icon.py and use it.
6. Don't ship test code: add scripts/tools/*, scenes/tools/* and scenes/balance_sim.tscn to the preset's exclude_filter. Check first that no game script loads them.
7. Checks in checks_android.gd: import_etc2_astc is on; quit_on_go_back is off; max_fps is 60; package/unique_name matches ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$; version/code is at least 1; the monochrome icon exists at 432 px; the test folders are excluded. In checks_mobile.gd, send NOTIFICATION_WM_GO_BACK_REQUEST during a match and check the pause menu opens.
8. Fix these stale parts of docs/ANDROID_SETUP.md for Godot 4.7.2:
   - Step 1: Godot recommends JDK 17. A newer Java (my JDK 25) works for the normal APK export, but Gradle builds may not accept it, so say to install 17 next to it and point Godot at 17 if Java errors appear.
   - Step 2: tick Android 16 (API 36) and Build-Tools 36.x, because Godot 4.7.2 targets API 36 (it says "35 or higher" now).
   - Step 3: there is no "Download and Install" button. The window has "Install Selected Templates" / "Install All Templates".
   - Step 4: the keytool line uses $env:JAVA_HOME, which may be empty or point at JDK 25. Use the full JDK 17 path, and say Godot usually makes the debug keystore itself.
   - Step 6: the button is called "Remote Deploy" (with a "Deploy with Remote Debug" option). The command-line export needs `mkdir export` first on a fresh clone.
   - Troubleshooting: add rows for the ETC2/ASTC error; the "project name / package name" warning (harmless because the preset sets com.crownconquest.game; check Project → Export → Android → Package → Unique Name); and "Unsupported class file major version" (Java too new, use JDK 17).
9. Fix the Prompt 18 line in docs/PROGRESS.md that says the exporter only complained about templates and the SDK.

All smoke and flow checks must pass. Add "## Prompt 19: Android release setup (phone)" to docs/PROGRESS.md with "Built" and "What to test". Then walk me through installing on my phone with Remote Deploy. Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Android phone build".
```

### Prompt 20: Android release setup (part 2: Google Play build)

Your hands are needed here: installing the build template, making the key and backing it up.

```text
Read docs/DESIGN.md, docs/ANDROID_SETUP.md, export_presets.cfg, project.godot, .gitignore, scripts/menu/settings_screen.gd, scripts/menu/menu_root.gd, scripts/menu/main_screen.gd and scripts/tools/checks_android.gd. Set up the release path to Google Play. I'm a beginner: whenever I must do something by hand (install, click, type a password), stop, tell me exactly what to do, and wait until I say it's done.

1. Play preset: keep "Android" as the runnable test APK preset. Add a second preset "Android (Play AAB)" (not runnable) with gradle_build/use_gradle_build=true, gradle_build/export_format=1 (AAB), export_path "export/CrownConquest.aab", and the same package, icons and filters. Leave target_sdk and min_sdk blank. Godot 4.7.2 targets API 36, which Google Play requires for new apps from Aug 31, 2026; tell me to confirm that in the Play Console. Walk me through Project → Install Android Build Template… and pointing Java SDK Path at JDK 17 (Gradle may fail on JDK 25).
2. Upload key: give me the keytool command (with the full JDK 17 path) to make %USERPROFILE%\keys\crownconquest-upload.jks (alias upload, RSA 2048, validity 10000), outside the project. Show me where to enter it (Export → Android (Play AAB) → Keystore → Release / Release User / Release Password). Explain that Godot keeps those in .godot/export_credentials.cfg, which is never committed. Tell me to back up the .jks file and its passwords twice: in a password manager and on a USB stick. Explain Play App Signing: Google holds the real app key, so a lost upload key can be reset. Add *.jks, *.keystore and export_credentials.cfg to .gitignore.
3. Version: add application/config/version="0.1.0" to project.godot and show it small on the main screen. Add tools/release.ps1, which:
   - runs the smoke and flow checks and stops on any failure;
   - adds 1 to version/code in the Play preset;
   - exports the signed .aab using the GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD environment variables;
   - tags the commit v<version>+<code>.
4. About screen (new scripts/menu/about_screen.gd, opened from Settings): version, credits, Godot's licence (Engine.get_license_text()) and a "Privacy policy" button. Write docs/privacy.md: the game collects no data, works offline and has no ads. Explain how to publish it with GitHub Pages and where to paste the URL.
5. Replace "Later: a release build" in docs/ANDROID_SETUP.md with a "Release to Google Play" chapter: build template, JDK 17, upload key and backups, release.ps1, where the .aab lands, and a warning that com.crownconquest.game can never change after the first upload, so I must settle the final name first ("Crown & Conquest" already exists on Steam and itch.io).
6. checks_android.gd: the Play preset exists, uses Gradle with export_format 1 and the same unique_name; target_sdk is blank or at least 36; the version shown in game matches version/name. Add a checks_menus.gd case that the About screen opens and fits at 1920x1080 and 2400x1080.

All smoke and flow checks must pass. Add "## Prompt 20: Android release setup (Google Play)" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Google Play build".
```

### Prompt 21: Safe tests and safe saves

```text
Read docs/DESIGN.md, README.md, scripts/save_data.gd, scripts/settings.gd, scripts/audio.gd, scripts/tutorial.gd, scripts/tools/smoke_test.gd, scripts/tools/flow_test.gd, scripts/tools/balance_sim.gd, scripts/tools/checks_progression.gd and export_presets.cfg. Make testing one command on Windows, and make sure tests and updates can never damage my progress. No game rules change.

1. tools\check.ps1, plus tools\check.bat that calls it: runs the import, the smoke test and the flow test with the console Godot ($env:GODOT, default C:\Users\benbe\Desktop\Godot_v4.7.2-stable_win64_console.exe). It fails on any FAIL, ERROR or WARNING line and prints one PASS/FAIL summary. Optional: -Balance 20 -Jobs 4 runs a short balance check. Update README.md, because the "godot" command doesn't exist on Windows.
2. Tests must never touch my real save. Today smoke_test and flow_test swap SaveData.data, call save() during the run and restore it only at the end, so a crashed run overwrites my progress. Make SaveData.PATH and Settings.PATH variables, and have a --test-profile argument switch them to user://test_save.json and user://test_settings.cfg.
3. flow_test passes but exits with "4 ObjectDB instances were leaked" and "2 resources still in use" (the music and tap sounds cached in audio.gd). Fix them so the output is clean.
4. balance_sim.gd: add --fail-on-target, which exits with code 1 if any target FAILs. --merge must skip a missing or broken part file with a message instead of crashing.
5. Save versions: SaveData.VERSION is written but never read.
   - Add _migrate(from_version) steps.
   - If the file is from a newer game version, keep a copy and don't overwrite it.
   - If save.json can't be read, rename it to user://save.corrupt-<unixtime>.json and show a one-line notice instead of silently starting fresh.
   - Add profile.tutorial_done to defaults().
   - Set user_data_backup/allow=true in both Android presets so Android backs up progress.
6. checks_progression.gd: a corrupt save is set aside and the notice shows; an old version migrates; a newer version is kept; the tests' save path is not the real one.

tools\check.ps1 must pass with no warnings. Add "## Prompt 21: Safe tests and saves" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Safe tests and saves".
```

### Prompt 22: Code cleanup with proof

Big one: use plan mode.

```text
Read docs/DESIGN.md, CLAUDE.md, docs/PROGRESS.md, scripts/tools/balance_sim.gd, scripts/tools/balance_report.gd and every file named below. Clean up the code without changing how any match plays, and prove it.

1. Proof tools first, in a new scripts/tools/balance_compare.gd so balance_sim.gd stays under 400 lines:
   - --expect-same PATH replays the same seeds and fails unless every match fingerprint is identical.
   - --compare PATH prints old -> new for every target row. It fails if the median length moves more than 30 s, any personality share or the "leader at 3:00 wins" share moves more than 8 points, 15:00 endings move more than 3 points, Crowns per match move more than 0.5, or any building or ability use moves more than 10 points.
   - Run 100 Continent matches and 50 each on Archipelago and Highlands (Medium, 8 bots, Mixed). Save them as reports/baseline/continent.json, archipelago.json and highlands.json, and commit them.
   - Add -Gate same|quick to tools\check.ps1.
2. Split the three scripts over 400 lines:
   - the attack ring engine in scripts/sim/combat_ops.gd (attack_tile_budget, start_ring, advance_ring, the Fort cache) → new scripts/sim/attack_rings.gd;
   - the win and Final Siege checks in scripts/sim/simulation.gd → new scripts/sim/victory_ops.gd;
   - colours and names in scripts/balance.gd (player and terrain colours, bot names and titles, team names) → new data files. Every tuning number stays in balance.gd.
3. Delete dead code, after searching to confirm nothing uses it: game_state.gd get_owner_at, get_owner_idx, set_owner, get_terrain_at, set_terrain, alive_player_count; boat.gd current_tile_idx, is_done; simulation.gd start_default_match; territory_ops.gd tile_is_border; ui/tutorial_arrow.gd target_on_screen.
4. Move typed-in numbers into Balance with the exact same values:
   - progression.gd achievement thresholds (3 Crowns, 360 s, 8 buildings, 3 truces, 1,000 troops);
   - match_tracker.gd 180.0;
   - bots.gd 1.0-2.0 and the 0.85-1.15 send jitter;
   - bot_moves.gd 300.0, 15.0, 60.0 and 0.9;
   - bot_abilities.gd 180.0, 150.0 and 0.15;
   - bot_places.gd ±6, ±30, 8 and 2.0;
   - simulation.gd 0.5-2.0;
   - abilities_ops.gd 10.0;
   - combat_ops.gd CROWN_ALERT_HOLD_SEC;
   - map_gen.gd noise settings and map-type shares.
5. bots.gd act_threshold checks Balance.FINAL_SIEGE_START_SEC directly. Make it use state.is_final_siege(), so it respects the tutorial's no-siege rule and any future early siege.
6. Old prompt text in docs/DESIGN.md has drifted from the rules: Prompt 6 says Dominion is 60% (it's 65%), and Prompt 8 says building defense is capped at x4 (it's 3.5) and boats reach 60 tiles (it's 120). Replace hard numbers in Prompts 1-18 with "the Balance value (see the tables above)". Update "After Prompt 18" to point at Prompts 19+.
7. Add a "Definition of done" section to CLAUDE.md:
   (1) tools\check.ps1 passes with no warnings;
   (2) a refactor passes -Gate same. A rule change runs the balance simulator (100 Continent + 50 Archipelago + 50 Highlands, Medium, 8 bots, Mixed), every target in DESIGN.md passes, --compare is shown, and the new baseline is committed in the same commit;
   (3) a checks_*.gd case covers the new behaviour;
   (4) DESIGN.md and PROGRESS.md are updated;
   (5) commit.
   Add .claude/commands/done.md so typing /done runs this list.

balance_sim --expect-same against the new baseline must pass with 100% identical fingerprints, and tools\check.ps1 must pass with no warnings. Add "## Prompt 22: Code cleanup" to docs/PROGRESS.md with "Built" and "What to test", including the new line counts. Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Code cleanup".
```

### Prompt 23: Phone controls

```text
Read docs/DESIGN.md ("Mobile controls and game feel"), CLAUDE.md, scripts/game.gd, scripts/touch_input.gd, scripts/camera_rig.gd, scripts/hud.gd, scripts/world_overlay.gd, scripts/ui/attack_list.gd, scripts/ui/tutorial_arrow.gd, scripts/ui/hints.gd and scripts/sim/territory_ops.gd. On my phone one tile is smaller than 1 mm at the starting zoom, so taps miss and nothing says why. Make taps forgiving and the camera helpful. This is input and drawing only: the sim rules and bots stay exactly the same.

1. Forgiving taps: when I tap free land that doesn't touch my border, or an invalid spot during Crown placement, use the nearest valid tile within TAP_SNAP_RADIUS_MM = 4.5 mm of my finger (convert with DisplayServer.screen_get_dpi(); fallback TAP_SNAP_RADIUS_PX = 72), and at most TAP_SNAP_MAX_TILES = 12 tiles away. It still goes through the same player_expand / placement call. Never snap onto enemy land, so a tap never turns into an accidental attack.
2. Say why a tap failed: a small red ping on the map (TAP_FAIL_PING_SEC = 0.6) and a short reason near my thumb, at most once every TAP_FAIL_MESSAGE_COOLDOWN_SEC = 2.0. Examples: "Too far from your border", "Peace for 0:23", "3 attacks already running", "Too close to another Crown".
3. Camera: when Crown placement ends, glide in until the view is CAMERA_START_ZOOM_FACTOR = 2.5 x the fit zoom, centred on my Crown. Minimap, Crown button and alert jumps glide over CAMERA_JUMP_TWEEN_SEC = 0.35 instead of teleporting.
4. Edge arrows (new scripts/ui/edge_pointers.gd, reusing tutorial_arrow.gd's off-screen code): up to EDGE_POINTER_MAX = 3 arrows, EDGE_POINTER_MARGIN_PX = 90 from the edge, pointing to off-screen attacks on me (red) and my own fronts (my colour). Tapping one flies there. Long-pressing an attack row looks at that front; a tap still retreats.
5. The hint "Tap the attack on the left to retreat" is wrong in the left-handed layout. Use the correct side.

Put every new number in scripts/balance.gd. Extend checks_mobile.gd and checks_tutorial.gd in the same style as the others:
- a tap 3 tiles from my border expands;
- a tap near enemy land never attacks;
- a failed tap shows its reason;
- the camera zooms in after placement;
- the tutorial still completes.
tools\check.ps1 must pass with no warnings, and balance_sim must pass -Gate same. Add "## Prompt 23: Phone controls" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Phone controls".
```

### Prompt 24: Readable on a phone

Big one: use plan mode.

```text
Read docs/DESIGN.md ("Screen layout"), docs/ANDROID_SETUP.md, project.godot [display], scripts/ui/ui_style.gd, scripts/hud.gd, scripts/ui/top_bar.gd, scripts/ui/ability_button.gd, scripts/ui/send_slider.gd, scripts/ui/alert_queue.gd, scripts/settings.gd, scripts/ui/settings_list.gd and scripts/tools/checks_mobile.gd. The UI is laid out for a 1920x1080 monitor. On a phone, buttons come out about 20 dp tall (Android asks for 48 dp) and text about 6-9 sp (12 sp is the usual minimum). Make the UI readable and easy to hit on real phones. Presentation only.

1. A "UI size" setting: Auto / 100% / 125% / 150% (UI_SCALE_OPTIONS = [1.0, 1.25, 1.5]). Auto uses UI_SCALE_AUTO_PHONE = 1.35 when the screen's short side is under 600 dp, otherwise UI_SCALE_AUTO_TABLET = 1.0. Apply it in one place (content_scale_factor or a shared theme scale), not control by control.
2. Bigger base text: FONT_SMALL 15 -> 18 and FONT_NORMAL 18 -> 20.
3. Compact bottom bar so 1.5x still fits on 16:9: when the scale is 1.4 or more, ability buttons go from 150 to 120 px wide and the slider from 220 to 160. If something still doesn't fit, redesign that part of the HUD rather than shrinking text.
4. Alert banners time themselves with Time.get_ticks_msec, so they run out while the game is paused. Use game time instead.
5. In docs/DESIGN.md, change "Buttons are at least 56 pixels tall" to "at least 56 px at 1080p, scaled by UI size".
6. checks_mobile.gd and checks_menus.gd: test 1920x1080, 2400x1080, 2340x1080, 2520x1080, 2560x1600 and 2048x1536, each at 1.0 / 1.25 / 1.5, plus a fake 80 px notch on the left and on the right. Nothing may overlap, everything stays inside the safe area, and every button is at least 56 px x scale. Save screenshots at 2400x1080 for each scale (smoke_test --shots) and tell me where they are.

Put every new number in scripts/balance.gd. tools\check.ps1 must pass with no warnings. Add "## Prompt 24: Readable on a phone" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "UI size".
```

### Prompt 25: Tester tools and the closed test

Big one: use plan mode.

```text
Read docs/DESIGN.md ("Playtest checks"), CLAUDE.md, scripts/game.gd, scripts/hud.gd, scripts/ui/top_bar.gd, scripts/ui/pause_menu.gd, scripts/ui/end_overlay.gd, scripts/match_tracker.gd, scripts/save_data.gd, scripts/settings.gd, scripts/menu/about_screen.gd, export_presets.cfg and tools/make_placeholder_icon.py. Friends are about to test the game through a Google Play closed test. Build the tools that make their testing useful. No game rules change.

1. First add a "Testing tools" section to docs/DESIGN.md with these rules.
2. Dev panel, test builds only: add custom_features="dev" to the "Android" test preset, never the Play AAB preset. With the "dev" feature or in the editor, tapping the match timer 5 times within 2 s opens a Dev panel with:
   - speed x1 / x2 / x4 / x8;
   - jump to 2:00 / 5:00 / 9:00 / 9:50 (simulated quickly behind a progress label);
   - +1,000 troops, knock out the nearest bot, start the Final Siege now;
   - let a Hard bot play my seat (soak test for heat and memory on Large with 11 bots);
   - a readout of the seed, a hash of the map terrain, FPS and tick time (p50/p99).
   Cheats that change the match live in a new scripts/sim/dev_ops.gd, and bots never call them. Any match touched by the panel sets state.dev_tainted and gives no XP, stats, achievements or Daily score.
3. Error log (new scripts/error_log.gd): keep the last ERROR_RING_SIZE = 50 errors and warnings in memory using Godot's OS.add_logger / Logger, and in user://logs/errors.txt. Turn on debug/file_logging/enable_file_logging with max_log_files = 5.
4. On the About screen:
   - "Copy debug info" copies version, phone model, Android version, the last match's seed and settings, and the last errors to the clipboard (DisplayServer.clipboard_set).
   - "Send feedback" opens an email to me with the same info (OS.shell_open with mailto:, so no internet permission is needed).
5. Tester survey: a Settings switch "I'm a tester" (off by default; on when the "dev" feature is on). When it's on, after each match ask one tap: Fun / Unfair / Boring / Confusing, with optional tags: "Lost to Dominion I didn't see", "Mis-tap", "Too slow", "Bots ganged up", "Didn't know what to do". Save each match's seed, mode, settings, result, length and answer in user://playtest_log.json (PLAYTEST_LOG_MAX_MATCHES = 200). "Copy debug info" includes it.
6. docs/PLAYTEST.md (new): what to tell testers (turn on "I'm a tester"), a 5-match plan (tutorial, Small with Easy bots, Medium Mixed, Archipelago, Teams), 5 questions, and how I turn their notes into a prompt.
7. docs/RELEASE.md (new): the Google Play checklist in order, slow steps first:
   - developer account and identity check;
   - settle the final name;
   - upload the first .aab with tools/release.ps1;
   - closed test with at least 12 testers opted in for 14 days in a row (recruit 15);
   - store listing (512 px icon, a placeholder 1024x500 feature graphic from tools/make_placeholder_icon.py, 4-8 landscape screenshots from smoke_test --shots);
   - content rating questionnaire, target audience 13+, ads: No, Data safety: no data collected or shared, privacy policy URL;
   - then production.
   Tell me to confirm each rule in the Play Console, because they change.
8. New scripts/tools/checks_dev.gd: no Dev panel without the "dev" feature; a tainted match never reaches SaveData; a survey answer is saved; Copy debug info contains the seed.

Put every new number in scripts/balance.gd. tools\check.ps1 must pass with no warnings, and balance_sim must pass -Gate same. Add "## Prompt 25: Tester tools" to docs/PROGRESS.md with "Built" and "What to test". Then tell me the next steps to start the closed test today. Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Tester tools".
```

### Prompt 26: Learn to win

```text
Read docs/DESIGN.md, CLAUDE.md, scripts/tutorial.gd, scripts/session.gd, scripts/menu/main_screen.gd, scripts/menu/skirmish_screen.gd, scripts/menu/menu_root.gd, scripts/menu/teams_screen.gd, scripts/ui/top_bar.gd, scripts/ui/hints.gd, scripts/ui/keep_panel.gd, scripts/ui/modifier_badges.gd, scripts/ui/ability_button.gd, scripts/ui/pause_menu.gd, scripts/hud.gd and scripts/save_data.gd. New players never learn how matches are really won. The tutorial turns Dominion off, yet 87 of 100 simulated matches end by Dominion (65% of the land), and the HUD never shows that target. After the tutorial, players land in a Medium map with 7 Mixed bots, where the Hard bot wins over half the time. Fix the first hour. Presentation only: no rule changes, and bots get no handicaps, just fewer and easier opponents.

1. First add a "First matches and the Codex" section to docs/DESIGN.md with these rules and numbers.
2. First steps: after the tutorial, the big button says "Your first real match" and starts FIRST_STEP_1 = Small Continent with 3 Easy bots. A win moves me to FIRST_STEP_2 = Medium Continent with 5 Easy bots, then to the normal default (Medium, 7 bots, Mixed). The main screen shows "First steps 1/3" until done. Skirmish setup stays free to change. Save progress in SaveData.
3. Show the target: the top bar's land reads "23% / 65%". When a rival reaches DOMINION_WARNING_FRACTION = 0.50, a banner says "Lady Vex is close to Dominion (52%)", once per rival and again at 60%. In Teams, show team land against 80%.
4. Coach tips, at most COACH_TIPS_MAX_PER_MATCH = 3 per match (reset by "Show tips again"):
   - troops at 95% or more of cap (COACH_TROOPS_FULL_RATIO) for 20 s (COACH_TROOPS_FULL_SEC) → "Your troops are full: spend them";
   - no Port by 2:00 on Archipelago (COACH_NO_PORT_ARCHIPELAGO_SEC = 120) → "Build a Port to reach other islands";
   - a rival over 50% while I'm not attacking them → "Attack the leader: they're close to Dominion".
5. Royal Codex: a "?" button in a corner of the main screen and "How to play" in the pause menu open CODEX_CARDS = 12 cards (How you win, Troops and the sweet spot, Expanding, Attacking, Terrain, Crown and Keep, Buildings, Boats, Abilities, Fair play, Truces, Final Siege). Each has at most 60 words and the cards swipe sideways. Long-pressing an ability button or a modifier badge opens its card.
6. One place for rule text: move every player-facing sentence that contains a rule number (hints.gd, tutorial.gd, teams_screen.gd, keep_panel.gd and the Codex) into a new scripts/ui/rules_text.gd. Make them templates filled from Balance and wrapped in tr(). Add to CLAUDE.md's Definition of done: "a rule change updates its Codex card in rules_text.gd".
7. Tutorial: add a last card that explains Dominion (65%) and the 15:00 limit.
8. Extend checks_tutorial.gd and checks_menus.gd: the first-steps ladder advances only on a win; the Dominion warning fires; no rules_text template contains a typed digit; every Codex card fits at 1920x1080 and 2400x1080 at every UI size.

Put every new number in scripts/balance.gd. tools\check.ps1 must pass with no warnings, and balance_sim must pass -Gate same. Add "## Prompt 26: Learn to win" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Learn to win".
```

### Prompt 27: Fix slow endings

```text
Read docs/DESIGN.md ("Truces", "How you win", "How balance gets tested"), CLAUDE.md (Definition of done), reports/balance_2026-10-06_final.md, scripts/tools/balance_sim.gd, scripts/tools/balance_compare.gd, scripts/tools/balance_report.gd, scripts/sim/truces_ops.gd, scripts/sim/bot_moves.gd, scripts/sim/bots.gd, scripts/sim/teams_ops.gd, scripts/sim/boats_ops.gd, scripts/ui/enemy_panel.gd and scripts/ui/rules_text.gd. Research found two stalls the reports hide:
- When only two rulers are left, Hard bots offer truces to their only neighbour, so the last two spend 63% of their head-to-head time in truces (seed 14 spent 299 of 414 s and ended at 13:22). 27 of 60 Continent matches have a 30 s+ stretch where almost nothing happens.
- On Archipelago only Hard bots build Ports, so Easy and Normal bots alone on an island can never attack again. 5 of 24 matches hit the 15:00 limit (target: under 5%). The reports only ever run Continent.
Commit after each step.

Step 1, measure (no rule change):
- Add pacing numbers in a new scripts/tools/pacing_stats.gd, sampled every PACING_SAMPLE_EVERY_TICKS = 10: quiet stretches (fewer than QUIET_TILES_PER_SEC = 10 owner changes per second for QUIET_STRETCH_SEC = 30 s or more), first Crown fall, players alive at 3:00 / 5:00 / 7:00, how long knocked-out players wait until the end, the share of two-player time spent in truce, and time from the winner reaching 50% to the end.
- Add --types all (one targets table each for Continent, Archipelago and Highlands). Label "You" as "Seat 1 (Easy bot)" in Mixed reports.
- Add targets to the DESIGN.md table: 30 s+ quiet stretch in under 20% of matches; median wait after elimination under 2:30; two-player time in truce under 5%; 15:00 endings under 5% on every map type.
- Fingerprints must stay identical (-Gate same). Commit the new baseline.

Step 2, Showdown (rule change). First add it to the "Truces" section of DESIGN.md:
- TRUCE_MIN_ALIVE_PLAYERS = 3. When only two players are left (in Teams: two teams), all truces end, new offers are refused, and the truce button says "Only two remain".
- A banner for everyone: "Only two remain, no more truces!".
- Bots follow the same rule.
- Don't move the Final Siege yet.
- Update the Truces Codex card.

Step 3, stranded Normal bots (bot behaviour change): a Normal bot with no land neighbour and nothing left to expand into builds a Port and sends boats, using the same rules and costs as Hard bots. Keep it this narrow: Prompt 17 saw Turtle wins jump to 51-54% when Ports got easier.

After Step 2 and again after Step 3: run the balance simulator for 100 matches (Medium, 8 bots, Mixed), plus 50 Archipelago and 50 Highlands. Confirm every target in DESIGN.md passes and show --compare against the baseline. If one fails, change ONE Balance number at a time. If the median match drops below 7:00, stop and tell me before changing anything else. Commit the new baseline.

Put every new number in scripts/balance.gd and keep rules in scripts/sim/, scripts under about 400 lines, randomness only from the match's seeded RNG. Extend checks_fairplay.gd: with 2 alive, truces end and offers are refused; a stranded Normal bot builds a Port. tools\check.ps1 must pass with no warnings. Add "## Prompt 27: Fix slow endings" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Fix slow endings".
```

### Prompt 28: Troops never vanish

```text
Read docs/DESIGN.md ("Attacking", "Buildings and defenses", "Truces", Teams in "Modes"), CLAUDE.md, scripts/sim/boats_ops.gd, scripts/sim/combat_ops.gd, scripts/sim/attack_rings.gd, scripts/sim/truces_ops.gd, scripts/sim/buildings_ops.gd, scripts/sim/crowns_ops.gd, scripts/sim/teams_ops.gd and scripts/ui/rules_text.gd. Fix four places where troops silently vanish or allies are treated as enemies. First update DESIGN.md: "Troops you send always arrive or come back."

1. A boat that lands on enemy land while its owner already has 3 attacks running, or whose target died while it was at sea, loses all its troops. Instead it turns around and returns BOAT_BLOCKED_REFUND_FRACTION = 0.75, with a message "Boat returned: 3 attacks already running". Also refuse the launch with that reason if 3 attacks are already running.
2. When a Crown falls, every attack on that player ends with no refund, including the capturer's leftovers and other players' attacks. Refund ELIMINATION_ATTACK_REFUND_FRACTION = 0.75 of what's left, the same as a retreat. Do the same when an attack's front runs out of tiles.
3. Accepting a truce retreats attacks but not boats at sea, so a boat that lands later breaks the truce and makes its owner an Oathbreaker. Turn those boats around (75% back) when the truce starts.
4. In Teams, my ally's land counts as an enemy border for building and for moving the Crown. Ignore ally land in those spacing checks.

The same rules apply to bots. Update the Codex cards these touch. This changes match rules: run the balance simulator for 100 matches (Medium, 8 bots, Mixed) plus 50 Archipelago and 50 Highlands, confirm every target in DESIGN.md passes, and show --compare against the baseline. If one fails, change ONE Balance number at a time, then commit the new baseline.

Put every new number in scripts/balance.gd and keep rules in scripts/sim/, scripts under about 400 lines, randomness only from the match's seeded RNG. Add one test per case to checks_buildings.gd and checks_fairplay.gd. tools\check.ps1 must pass with no warnings. Add "## Prompt 28: Troops never vanish" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Troops never vanish".
```

### Prompt 29: After the match

Big one: use plan mode.

```text
Read docs/DESIGN.md ("Modes", "Progression"), CLAUDE.md, scripts/game.gd, scripts/game_feel.gd, scripts/map.gd, scripts/ui/end_overlay.gd, scripts/ui/xp_panel.gd, scripts/match_tracker.gd, scripts/save_data.gd, scripts/sim/match_config.gd, scripts/menu/stats_screen.gd and scripts/menu/menu_root.gd. Improve everything after my Crown falls or the match ends. Match rules don't change. First add an "After the match" section to docs/DESIGN.md.

1. Watch faster: after my Crown falls, the Watch view gets x1 / x4 / x8 buttons (SPECTATE_SPEEDS, up to SPECTATE_MAX_TICKS_PER_FRAME = 20) and "Skip to result". Skip runs the rest at SKIP_TICKS_PER_FRAME = 60 behind a progress bar, with the map repaint budget raised to MAP_PIXELS_PER_FRAME_FAST = 4000, then shows who won. No slow-mo or shake above x1.
2. Bugs:
   - The end screen's Time keeps counting after defeat because it shows state.match_time. Use the time I was knocked out.
   - Quitting or restarting mid-match records nothing. Record it as a loss marked "Left".
   - In Teams, if my Crown falls while my ally lives and I tap Main menu, skip to the result first so the team result is recorded.
3. Match history: a new user://history.json, written with the same temp-file-then-rename pattern as save.json, holding my last HISTORY_MAX_MATCHES = 30 matches: date, mode, map, bots, seed, result ("Victory by Dominion 7:12", "Crown taken by Duke Vex at 4:05", "Left") and XP. A History screen, opened from Stats, has "Play this map again" (same seed and settings) and "Report". Stats also shows my win rate per map type and per difficulty. Add MatchConfig.to_dict() / from_dict().
4. War Report: a "Report" tab on the end screen. It shows:
   - a land-over-time graph of every player in their colour, mine thicker (sampled every REPORT_SAMPLE_SEC = 5), with markers where Crowns fell and a line at the Final Siege, drawn with Control._draw in a new scripts/ui/land_graph.gd;
   - up to REPORT_MAX_MOMENTS = 10 key moments ("2:41 You took Duke Vex's Crown (+1,240 plunder)");
   - up to REPORT_TIPS_MAX = 3 plain tips ("Your troops sat full for 1:50", "You never used Rally"; only for idle stretches of REPORT_TIP_MIN_IDLE_SEC = 45 or more).
   MatchTracker does the sampling, on the presentation side; scripts/sim stays untouched. The report must fit next to the XP panel at 2400x1080. Keep the report data for the history entries.

Put every new number in scripts/balance.gd. Extend checks_progression.gd and flow_test.gd: a quit is recorded as "Left"; history keeps 30; "Play this map again" rebuilds the same config; Skip finishes the match and records the right winner; the report draws. tools\check.ps1 must pass with no warnings, and balance_sim must pass -Gate same. Add "## Prompt 29: After the match" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "After the match".
```

### Prompt 30: Dominion countdown and Balance pass 2

```text
Read docs/DESIGN.md ("How you win", "How balance gets tested"), CLAUDE.md, docs/PROGRESS.md (Prompts 17, 27, 28), the latest reports, scripts/sim/victory_ops.gd, scripts/sim/teams_ops.gd, scripts/sim/bot_moves.gd, scripts/sim/fair_play_ops.gd, scripts/sim/attack_rings.gd, scripts/progression.gd, scripts/ui/top_bar.gd, scripts/world_overlay.gd and scripts/ui/rules_text.gd. Two parts; commit after each.

Part 1, Dominion countdown (rule change). Today a match ends silently on the tick someone reaches 65%. First update "How you win" in DESIGN.md, then:
- Reaching DOMINION_WIN_FRACTION (65%) starts a DOMINION_HOLD_SEC = 20 countdown. It shows as a golden ring around that player's Crown and a banner for everyone: "Duke Ashford claims Dominion: 20 s". Everyone else gets a "Stop them!" alert.
- Dropping below DOMINION_RESET_BELOW_FRACTION = 0.62 stops the countdown. Reaching 65% again starts it over.
- Bots score attacking the claimant higher: BOT_SCORES "attack_claimant" = 35. This is a move-scoring weight only, never a stat bonus.
- Teams: the 80% team win uses the same hold (TEAMS_DOMINION_HOLD_SEC = 20).
- The win reason still starts with "Dominion", so the Dominion achievement keeps working. Update the "How you win" Codex card.
Run the balance simulator for 100 matches (Medium, 8 bots, Mixed) plus 50 Archipelago and 50 Highlands. Every target in DESIGN.md must pass and the median must stay within 7-11 minutes. If one fails, change ONE Balance number at a time. Commit the new baseline.

Part 2, Balance pass 2. Use Prompt 17's method on all three map types, against every target including the pacing ones. Research found that an attacked tile costs 6 + 1.5 x D x terrain x defense, where D (defender troops per tile) is about 0.8-0.9 during minutes 2-4. So the flat 6 is about 82% of the cost, and hills, Forts and Crown defense barely matter. Try moving cost from ATTACK_TILE_COST_BASE into ATTACK_TILE_COST_SCALE, one number at a time. Rerun 50 matches per map type after each change and keep it only if it helps without breaking another target. Stop at 8 changes. Show me a table of every number changed (old -> new, and why), update the DESIGN.md tables and Codex text, and commit the new baseline.

Put every new number in scripts/balance.gd and keep rules in scripts/sim/, scripts under about 400 lines, randomness only from the match's seeded RNG. Extend checks_fairplay.gd: the countdown starts at 65%, resets below 62%, and wins after 20 s; Teams works the same. tools\check.ps1 must pass with no warnings. Add "## Prompt 30: Dominion countdown and Balance pass 2" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Balance pass 2".
```

### Prompt 31: Look, sound and comfort

You'll download free asset packs during this one; Claude gives you the list first.

```text
Read docs/DESIGN.md ("Game feel"), CLAUDE.md, project.godot, export_presets.cfg, scripts/ui/ui_style.gd, scripts/ui/icons.gd, scripts/audio.gd, assets/audio/README.md, scripts/settings.gd, scripts/ui/settings_list.gd, scripts/game_feel.gd, scripts/camera_rig.gd, scripts/world_overlay.gd, scripts/ui/minimap.gd, scripts/ui/ability_button.gd, scripts/menu/about_screen.gd and tools/make_placeholder_icon.py. Replace the placeholder look and sound and add comfort settings. No rule changes.

Before coding, give me a short shopping list of free assets and where to put them: CC0 sound packs from kenney.nl (Interface Sounds, Impact Sounds, RPG Audio, Music Jingles) or freesound.org with the CC0 filter; CC0 or CC-BY medieval music loops from opengameart.org; and two OFL fonts from Google Fonts (for example Cinzel for titles and Nunito for text). Stop and wait until I say they're in place.

1. docs/ART.md (new): palette roles, outline width, icon style, the font pair, sound mood, and phone rules (48 dp touch targets, 12 sp text, never colour alone). Add to CLAUDE.md: "Follow docs/ART.md for any visual change."
2. One shared Theme (new scripts/ui/ui_theme.gd, built from UIStyle) with the new fonts, used by the menus and HUD and scaled by the UI size setting.
3. A Crown Conquest boot splash instead of Godot's logo (application/boot_splash/image and bg_color), and a new 1024x500 Play feature graphic, both made by the icon script.
4. Sound: wire in the new files (audio.gd already prefers .ogg). Music is .ogg with loop turned on in its import settings, so it no longer has a gap. Add audio buses Master, SFX and Music (new default_bus_layout.tres), and Sound and Music volume sliders (SFX_VOLUME_DEFAULT = 0.8, MUSIC_VOLUME_DEFAULT = 0.6). Write CREDITS.md and show it on the About screen.
5. Comfort settings:
   - "Reduce motion": no shake, no slow-mo, softer capture flashes;
   - "Vibration: Off / Light / Strong": Input.vibrate_handheld amplitude HAPTIC_AMPLITUDE_LIGHT = 0.35 / HAPTIC_AMPLITUDE_STRONG = 1.0, longest buzz HAPTIC_MAX_MS = 200;
   - "Battery saver (30 fps)": FPS_CAP_SAVER = 30.
   Also turn on low-processor mode in the menus, redraw the minimap at most MINIMAP_REDRAW_HZ = 10 times a second, and redraw the overlay and ability buttons only when something changed.

Put every new number in scripts/balance.gd. Extend checks_feel.gd: Reduce motion disables shake and slow-mo; the vibration level passes the right amplitude; the music import loops; the battery saver sets 30 fps. tools\check.ps1 must pass with no warnings, and balance_sim must pass -Gate same. Add "## Prompt 31: Look, sound and comfort" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Look and sound".
```

### Prompt 32: A clearer map

Big one: use plan mode.

```text
Read docs/DESIGN.md, docs/ART.md, CLAUDE.md, scripts/map.gd, scripts/world_overlay.gd, scripts/ui/minimap.gd, scripts/ui/icons.gd, scripts/ui/palette.gd, scripts/balance.gd (terrain and Ruins colours) and scripts/tools/checks_feel.gd. On a phone, neighbouring empires blur together, Forts are a single 9-pixel tile, and Ruins look like hills. Make the map readable while keeping CLAUDE.md's rule: one Image texture, and only changed pixels are updated. Presentation only.

1. Put each tile's owner id in the map image's unused alpha channel and add a CanvasItem shader (new shaders/map.gdshader) that always draws at full opacity and adds:
   - a dark line between different owners (MAP_BORDER_WIDTH_TEXELS = 0.14, MAP_BORDER_DARKEN = 0.45);
   - a bright line along my own outer border (OWN_BORDER_COLOR = white at 85%), so I can see where to tap;
   - diagonal hatching on Ruins (RUINS_HATCH_SHADE = 0.18);
   - subtle terrain texture (TERRAIN_NOISE_STRENGTH = 0.06).
   The minimap uses the same image with borders off.
2. Icons for Fort, Fort II, Barracks, Port and the Crown, drawn in world_overlay.gd in the icons.gd style, that never get smaller than MIN_ICON_SCREEN_PX = 36 on screen.
3. Colour-blind mode: thicker borders (COLORBLIND_BORDER_WIDTH_TEXELS = 0.22) and my own pattern always on, so empires never differ by colour alone.
If this gets big, commit the shader as "Map borders" before starting the icons.

Put every new number in scripts/balance.gd. Extend checks_feel.gd: the map still repaints at most 1,200 changed pixels per frame; owner ids survive in the alpha channel; icons keep their minimum size at every zoom. Save before/after screenshots at 2400x1080 for me. tools\check.ps1 must pass with no warnings, and balance_sim must pass -Gate same. Add "## Prompt 32: A clearer map" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Clearer map".
```

### Prompt 33: Daily Challenge 2.0 and the Conquest Ladder

Big one: use plan mode.

```text
Read docs/DESIGN.md ("Modes", "Progression", "How balance gets tested"), CLAUDE.md, scripts/menu/daily_screen.gd, scripts/menu/main_screen.gd, scripts/menu/menu_root.gd, scripts/menu/skirmish_screen.gd, scripts/sim/match_config.gd, scripts/sim/simulation.gd, scripts/save_data.gd, scripts/progression.gd, scripts/match_tracker.gd, scripts/ui/end_overlay.gd, scripts/ui/land_graph.gd and scripts/tools/balance_sim.gd. Give players a reason to come back each day and goals after level 15. Bots never get bonuses: difficulty comes only from the number of bots, their difficulty and personality, and the map. Rewards are cosmetic or XP only. First add "Daily Challenge 2.0" and "Conquest Ladder" sections to DESIGN.md with these rules and numbers.

Part A, Daily Challenge 2.0:
- Use the UTC date (DAILY_USE_UTC_DATE = true), so everyone gets the same map on the same day, with Daily #1 = DAILY_EPOCH_DATE "2026-10-01". Show a one-time note saying when the day now changes in my local time.
- Tell me to compare the Dev panel's terrain hash for today's Daily on my PC and my phone. If they differ, say so in PROGRESS.md and don't promise "same map for everyone" in the game text.
- The Daily screen shows my streak in days, the last 7 days as medals (DAILY_MEDAL_BRONZE = 40, DAILY_MEDAL_SILVER = 80, DAILY_MEDAL_GOLD = 120) and my tries today.
- Share copies to the clipboard: "Crown Conquest Daily #12 · Highlands · 131 (68% land + 63 speed) · Won 5:33 · 4 Crowns · try 2", plus DAILY_SHARE_STRIP_CELLS = 10 small squares showing my land each minute (from the War Report samples).
- DAILY_GOLDS_FOR_SUN_CROWN = 10 Gold days unlock a "Sun Crown" icon.

Part B, Conquest Ladder:
- MatchConfig gets a lineup: a list of {difficulty, personality} per bot seat. When given, Simulation uses it instead of random personalities.
- LADDER_RANKS = 12 in a new scripts/sim/ladder.gd, named from Hamlet to High Throne:
  - rank 1: Small Continent, 2 Easy;
  - rank 4: Medium Continent, 7 Easy;
  - rank 6: Medium Continent, 7 Normal;
  - rank 7: Medium Highlands, 6 Normal + 1 Hard;
  - rank 8: Medium Archipelago, 5 Normal + 2 Hard;
  - rank 10: Medium Continent, 4 Normal + 3 Hard (2 of them Turtles);
  - rank 11: Medium Continent, 7 Hard;
  - rank 12: Large Random, 11 Hard.
  Fill in ranks 2, 3, 5 and 9 between these.
- A win climbs one rank; a loss never drops me; quitting counts as a loss. The first win at each rank gives LADDER_FIRST_WIN_XP_BONUS = 200 and a banner or Crown frame. Each rank has 2 optional star goals checked from MatchTracker results (for example "Win by taking the last Crown", "Land a boat attack", "Win before 8:00").
- Calibrate with the simulator: add --ladder N, where a Normal bot plays seat 1 in my place. Its win rate should fall smoothly from about 70% at rank 1 (LADDER_PROXY_WIN_TARGET_FIRST = 0.70) to about 5% at rank 12 (LADDER_PROXY_WIN_TARGET_LAST = 0.05). Show me the table and fix bumps by changing lineups, never bot numbers.
- The main menu is a full 3x2 grid. Regroup it with a Play hub (Skirmish, Teams, Daily, Ladder). Show my best rank on the main screen.

Put every new number in scripts/balance.gd and keep rules in scripts/sim/, scripts under about 400 lines, randomness only from the match's seeded RNG. Extend checks_menus.gd and checks_progression.gd: the UTC date is used; the streak and medals compute from saved scores; the share text is right; a lineup is applied seat by seat; a ladder win advances and a quit counts as a loss. tools\check.ps1 must pass with no warnings, and balance_sim must pass -Gate same for normal matches. Add "## Prompt 33: Daily 2.0 and Ladder" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Daily 2.0 and Ladder".
```

### Prompt 34: Online multiplayer, step 1 of 3: match recorder, replays and resume

Big one: use plan mode.

```text
Read docs/DESIGN.md, CLAUDE.md, scripts/sim/simulation.gd, scripts/sim/victory_ops.gd, scripts/sim/match_config.gd, scripts/sim/bots.gd, scripts/game.gd, scripts/targeting.gd, scripts/ui/attack_list.gd, scripts/ui/truce_panel.gd, scripts/ui/ally_panel.gd, scripts/ui/end_overlay.gd, scripts/session.gd, scripts/menu/main_screen.gd, scripts/menu/ (the History screen), scripts/save_data.gd and scripts/tools/balance_sim.gd. Online multiplayer starts here: record every match as its seed plus my commands. On its own this already gives replays and resume after Android closes the app. Same device only for now. First add a "Recording, replays and resume" section to DESIGN.md.

1. Commands: every action of mine (place Crown, expand, attack, retreat, build, ability, truce, send to ally, boat) becomes a small Command (new scripts/sim/command.gd). Commands are queued and applied at the start of the next tick by a new scripts/sim/commands_ops.gd, so the log knows exactly which tick each happened on. Store send fractions as whole per-mille numbers (COMMAND_FRACTION_STEPS = 1000), and retreat by attack id instead of list position. Bots keep calling the sim directly and are never logged; they replay from the seed.
2. Recorder: a new scripts/sim/replay_log.gd keeps [tick, command] plus a header: REPLAY_FORMAT_VERSION = 1, game version, Godot version, a hash of balance.gd and the MatchConfig. Every REPLAY_CHECKSUM_EVERY_TICKS = 300 it stores a checksum (land per player). Keep the last REPLAY_KEEP_LAST = 20 matches in user://replays/.
3. Resume: write user://resume.json (seed, config, commands) every RESUME_AUTOSAVE_SEC = 10, and at once on NOTIFICATION_APPLICATION_PAUSED. If Android closed the app, the main screen offers "Resume match (Skirmish · 6:12)" for RESUME_MAX_AGE_HOURS = 24. Resuming replays the match headless behind a "Restoring…" progress bar (it can take 15-25 s on a phone for a long match) and then I carry on. Not for the tutorial. Delete the file when the match ends or I quit.
4. Replays: "Watch replay" in History and on the end screen plays a match at REPLAY_SPEEDS = [1, 4, 16] (reuse the Watch speed buttons) with a free camera, pause, jumps to Crown falls and the Final Siege, and a "Clean" toggle that hides the HUD for store screenshots. "Export replay" saves a file I can send. Refuse replays from another game version politely, and stop with a message if a checksum doesn't match.
5. Keep simulation.gd under 400 lines with one-line hooks into the new files.

Put every new number in scripts/balance.gd. New scripts/tools/checks_replay.gd: play 3 minutes of scripted commands, replay them headless, and the fingerprint must match bit for bit; resume reaches the same state; an old-version replay is refused. Bot-only matches must not change: balance_sim must pass -Gate same. tools\check.ps1 must pass with no warnings. Add "## Prompt 34: Recorder, replays and resume" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Replays and resume".
```

### Prompt 35: Online multiplayer, step 2 of 3: same-Wi-Fi party

Two parts: Claude stops after Part A.

```text
Read docs/DESIGN.md, CLAUDE.md, docs/privacy.md, scripts/sim/ (especially map_gen.gd, crowns_ops.gd, bot_places.gd, bots.gd, truces_ops.gd, boats_ops.gd, teams_ops.gd, simulation.gd, commands_ops.gd, replay_log.gd), scripts/game.gd, scripts/game_feel.gd, scripts/ui/pause_menu.gd and export_presets.cfg. Next step to online play: 2-8 phones on the same Wi-Fi play one match. Every device runs the same sim, and only commands travel over the network (lockstep). First add a "Party mode" section to DESIGN.md. Do Part A, commit, then stop and wait for me.

Part A, the same results on every device:
- Floating-point code can give different results on my Windows PC (x86) and an ARM phone. Fix each case:
  - the host sends the generated terrain bytes in the start message, so FastNoiseLite never has to match;
  - replace sin/cos in crowns_ops.gd with an integer offset table;
  - replace Vector2 lerp/distance in bot_places.gd with integer steps;
  - replace rng.randf_range with a GDScript helper over rng.randi() (SIM_RAND_RESOLUTION = 1000000).
  This changes every seed's matches, so run the balance simulator for 100 matches (Medium, 8 bots, Mixed) plus 50 Archipelago and 50 Highlands, confirm every target in DESIGN.md passes (change ONE Balance number at a time if not), and commit a new baseline.
- Several human seats: MatchConfig lists which seats are human, and local_player_id comes from the device. Messages that depend on local_player_id stay out of the state hash.
- Slow-motion only slows the drawing, never the sim clock. In a multiplayer match, pausing or going to the background shows an overlay while the match keeps running.
- State hash every STATE_HASH_EVERY_TICKS = 10 ticks (owners plus whole troops, HashingContext).
- New scripts/tools/checks_lockstep.gd: two sims in one process, fed the same turns, stay hash-identical for a whole match.

Part B, the network:
- New scripts/net/lockstep.gd and scripts/net/lan_host.gd using the built-in ENetMultiplayerPeer. The host only keeps the clock and relays commands; it has no rules advantage.
  - NET_TURN_TICKS = 1: one turn per tick, even when empty;
  - NET_INPUT_DELAY_TICKS = 2 (200 ms);
  - compare hashes every NET_HASH_EVERY_TICKS = 10 ticks; on a mismatch, stop with "Out of sync" and save both replays;
  - NET_PORT = 24560, NET_MAX_HUMANS = 8, NET_STALL_TIMEOUT_SEC = 10.
- Party screen in the Play hub (new scripts/menu/party_screen.gd): "Host Party" shows the host's address; "Join" lists hosts found on the Wi-Fi or takes a typed address. Everyone picks a colour, empty seats become bots, and Skirmish or Teams settings apply.
- Any network socket on Android needs permissions/internet=true. Update docs/privacy.md (local play only, nothing is sent to a server) and tell me what changes in the Play Data safety form.
- Walk me through a PC-vs-phone match on my Wi-Fi, including the Windows firewall prompt.

Put every new number in scripts/balance.gd and keep rules in scripts/sim/, scripts under about 400 lines, randomness only from the match's seeded RNG. tools\check.ps1 must pass with no warnings. Add "## Prompt 35: Same-Wi-Fi party" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Wi-Fi party".
```

### Prompt 36: Online multiplayer, step 3 of 3: online rooms

Only start this after at least 10 PC-vs-phone party matches finish without "Out of sync", and after launch, once enough people play. Three parts, one session each.

```text
Read docs/DESIGN.md, CLAUDE.md, docs/privacy.md, scripts/net/, scripts/sim/commands_ops.gd, scripts/sim/replay_log.gd, scripts/sim/simulation.gd, scripts/menu/party_screen.gd, scripts/game.gd and export_presets.cfg. Final step: friends anywhere play together using a room code. First add an "Online rooms" section to DESIGN.md. Do one part per session: commit, stop, and wait for me to say "Continue with Part B" (then C).

Part A, relay server: a headless Godot export (new server/relay.gd) using WebSocketMultiplayerPeer, which works through mobile networks. It holds no game rules: it hands out room codes (ROOM_CODE_LENGTH = 6, for example KNG427), stamps and forwards commands in turns, keeps each room's turn log, and closes idle rooms after ROOM_IDLE_CLOSE_SEC = 300. Write docs/SERVER.md: renting a small Linux server, uploading the relay, running it as a service, what it costs each month, and how to update it. Stop and walk me through it.

Part B, rooms: "Create Room" and "Join Room" in the Play hub (new scripts/menu/rooms_screen.gd and scripts/net/online_client.gd), up to ROOM_MAX_HUMANS = 8. Bots fill empty seats and always show a bot icon. Reconnect within NET_RECONNECT_WINDOW_SEC = 120: the phone fetches the turn log, re-simulates from the start behind a progress bar, then takes over again.

Part C, dropped players and chat: if a phone is gone for NET_BOT_TAKEOVER_AFTER_SEC = 10, a Normal bot (NET_TAKEOVER_DIFFICULTY, labelled with a bot icon, no bonuses) plays that empire until they return. Quick chat only, no free text: QUICK_CHAT = ["Truce?", "Help!", "Watch out", "Thanks", "GG"]. Player names come from the bot name generator. Add a Report button that saves the room code and the replay. Update docs/privacy.md and tell me which Data safety answers change.

Put every new number in scripts/balance.gd and keep rules in scripts/sim/ (the relay never runs game rules), scripts under about 400 lines, randomness only from the match's seeded RNG. Extend checks_lockstep.gd: a relayed match stays in sync; a reconnect reaches the same hash; a bot takeover keeps the match deterministic. tools\check.ps1 must pass with no warnings. Add "## Prompt 36: Online rooms" to docs/PROGRESS.md with "Built" and "What to test". Run it, fix errors, tell me what to test (on PC and on my phone), then commit as "Online rooms".
```

## After these prompts

- **Run the closed test with friends.** Start it right after Prompt 25 and keep building while the 14-day clock runs. Have testers turn on "I'm a tester", and collect their "Copy debug info" pastes each week.
- **Turn feedback into numbers.** Match it against the playtest checks in `docs/DESIGN.md`: does a new player beat Easy within 3 tries, and does "Unfair" rarely follow a Crown loss? Describe the problems to Claude in plain words, then rerun Prompt 17.
- **Go to production** once the closed test has run 14 days, the art and map prompts (31–32) are in, and you have screenshots from replay "Clean" mode.
- **Revisit the "Not now" list after launch.** Riverlands and Decrees fit when players ask for variety. Quests and levels to 30 fit when they run out of goals. Undo fits if testers keep picking "Mis-tap". The leaderboard fits once the Wi-Fi party proves your PC and phone stay in sync.