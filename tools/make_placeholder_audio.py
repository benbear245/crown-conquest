#!/usr/bin/env python3
"""Generates the placeholder sounds and music in assets/audio/.

Pure standard library (no numpy). Every file is a simple synthesised sound so
the game has audio out of the box; replace any of them with a real sound of
the same name (.wav or .ogg) and the game picks it up.

    python3 tools/make_placeholder_audio.py
"""
import math, os, random, struct, wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
random.seed(7)


def write(name, samples, rate=RATE):
    path = os.path.join(OUT, name + ".wav")
    peak = max(1e-6, max(abs(s) for s in samples))
    gain = min(1.0, 0.9 / peak)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))
    print("wrote", path, len(samples) / rate, "s")


def env(i, n, attack=0.005, release=0.3):
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (n - i) / (release * RATE)) if release > 0 else 1.0
    return a * r


def tone(freq, dur, kind="sine", vol=1.0, attack=0.005, release=0.2, vibrato=0.0):
    n = int(dur * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        f = freq * (1.0 + vibrato * math.sin(2 * math.pi * 5.5 * i / RATE))
        phase += 2 * math.pi * f / RATE
        if kind == "sine":
            v = math.sin(phase)
        elif kind == "square":
            v = 0.6 if math.sin(phase) > 0 else -0.6
        elif kind == "saw":
            v = ((phase / math.pi) % 2.0) - 1.0
        else:
            v = math.sin(phase) + 0.3 * math.sin(2 * phase) + 0.15 * math.sin(3 * phase)
        out.append(v * vol * env(i, n, attack, release))
    return out


def mix(*tracks, offsets=None):
    offsets = offsets or [0.0] * len(tracks)
    n = max(int(o * RATE) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * n
    for t, o in zip(tracks, offsets):
        s = int(o * RATE)
        for i, v in enumerate(t):
            out[s + i] += v
    return out


def noise(dur, vol=1.0, decay=0.1):
    n = int(dur * RATE)
    return [random.uniform(-1, 1) * vol * math.exp(-i / (decay * RATE)) for i in range(n)]


def drum(dur=0.35, f0=130, f1=45, vol=1.0):
    n = int(dur * RATE)
    out, phase = [], 0.0
    for i in range(n):
        f = f1 + (f0 - f1) * math.exp(-i / (0.04 * RATE))
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase) * vol * math.exp(-i / (0.12 * RATE)))
    return mix(out, noise(0.05, 0.25 * vol, 0.01))


def note(n):  # MIDI note -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)


def arpeggio(notes, step, dur, kind="organ", vol=0.6):
    return mix(*[tone(note(n), dur, kind, vol, 0.01, dur * 0.6) for n in notes], offsets=[i * step for i in range(len(notes))])


def loop_music(chords, beat, beats_per_chord, pulse_kind, drums, vol=0.25):
    tracks, offs = [], []
    t = 0.0
    for chord in chords:
        length = beat * beats_per_chord
        for n in chord:
            tracks.append(tone(note(n), length, "sine", vol, 0.3, 0.3))
            offs.append(t)
        for b in range(beats_per_chord):
            tracks.append(tone(note(chord[0] + 12), beat * 0.45, pulse_kind, vol * 0.5, 0.005, beat * 0.3))
            offs.append(t + b * beat)
            if drums:
                tracks.append(drum(0.25, 110, 45, 0.7 if b % 2 == 0 else 0.4))
                offs.append(t + b * beat)
        t += length
    out = mix(*tracks, offsets=offs)
    return out[: int(t * RATE)]


def main():
    os.makedirs(OUT, exist_ok=True)
    write("sfx_expand_tick", tone(1400, 0.045, "sine", 0.35, 0.002, 0.035))
    write("sfx_attack_drum", drum(0.35))
    write("sfx_capture", mix(tone(660, 0.08, "square", 0.3, 0.002, 0.06), noise(0.05, 0.2, 0.015)))
    write("sfx_crown_alarm_horn", mix(tone(220, 0.9, "saw", 0.5, 0.05, 0.3, 0.01), tone(330, 0.9, "saw", 0.35, 0.05, 0.3, 0.01)))
    write("sfx_crown_fall", arpeggio([60, 64, 67, 72], 0.12, 0.6))
    write("sfx_crown_fall_big", mix(arpeggio([60, 64, 67, 72, 76, 79], 0.1, 0.9, vol=0.7),
                                   tone(note(48), 1.6, "organ", 0.5, 0.05, 0.8), drum(0.5, 120, 40), offsets=[0.0, 0.5, 0.5]))
    write("sfx_ability_ready", mix(tone(880, 0.25, "sine", 0.4, 0.003, 0.2), tone(1320, 0.25, "sine", 0.3, 0.003, 0.2), offsets=[0.0, 0.06]))
    write("sfx_ability_use", [v * (1 - i / 6615) for i, v in enumerate(noise(0.3, 0.5, 0.2))])
    write("sfx_build", mix(tone(140, 0.2, "square", 0.5, 0.002, 0.15), noise(0.04, 0.3, 0.01)))
    write("sfx_loot", mix(tone(1568, 0.09, "square", 0.25, 0.002, 0.06), tone(2093, 0.12, "square", 0.25, 0.002, 0.08), offsets=[0.0, 0.08]))
    write("sfx_truce", mix(tone(784, 0.7, "sine", 0.4, 0.005, 0.6), tone(1175, 0.7, "sine", 0.25, 0.005, 0.6)))
    write("sfx_ui_tap", tone(1000, 0.025, "sine", 0.25, 0.001, 0.02))
    write("sfx_victory", arpeggio([60, 64, 67, 72, 67, 72, 76, 84], 0.18, 1.0, vol=0.6))
    write("sfx_defeat", arpeggio([67, 63, 60, 55, 51], 0.28, 1.0, vol=0.6))
    calm = [[48, 55, 64], [45, 52, 60], [41, 48, 57], [43, 50, 59]]       # C  Am  F  G
    siege = [[45, 52, 57], [41, 48, 53], [43, 50, 55], [40, 47, 52]]      # Am F  G  Em
    write("music_calm_loop", loop_music(calm, 0.75, 4, "sine", False, 0.22))
    write("music_siege_loop", loop_music(siege * 2, 0.36, 4, "square", True, 0.25))


if __name__ == "__main__":
    main()
