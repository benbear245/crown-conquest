# Audio placeholders

Every file here is a simple generated placeholder (made by
`tools/make_placeholder_audio.py`). Replace any of them with a real sound:
keep the **same name** and drop in a `.ogg`, `.wav` or `.mp3` (if both an
`.ogg` and a `.wav` exist, the `.ogg` wins). Delete the old placeholder so
there's no confusion. Good free sources: freesound.org (CC0 filter),
kenney.nl (public domain), opengameart.org.

| File | When it plays |
| --- | --- |
| `sfx_expand_tick` | Soft tick while your land grows (rate-limited) |
| `sfx_attack_drum` | Drum beat each time your attack (or one against you) pushes a ring |
| `sfx_capture` | Quiet click when your attack takes tiles |
| `sfx_crown_alarm_horn` | Horn when your Crown comes under attack; also announces the Final Siege |
| `sfx_crown_fall` | Fanfare when someone else's Crown falls |
| `sfx_crown_fall_big` | Bigger fanfare when your Crown falls or you take a Crown |
| `sfx_ability_ready` | Chime when one of your abilities is ready |
| `sfx_ability_use` | Whoosh when you use an ability |
| `sfx_build` | Thunk when you build (Fort, Barracks, Port, Wall, Keep) |
| `sfx_loot` | Coins when you capture an enemy building |
| `sfx_truce` | When a truce you're part of starts |
| `sfx_ui_tap` | Settings toggles |
| `sfx_victory` / `sfx_defeat` | End of match |
| `music_calm_loop` | Music for most of the match (loops) |
| `music_siege_loop` | Faster, more intense music once the Final Siege starts (loops) |

Music should loop cleanly. Sound and music can be switched off in Settings.
