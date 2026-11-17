#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Martin Bjørndal
#
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Makes Hanne Chat's sounds (lib/gruppechat/sounds.dart): the chat sounds,
the notification sounds a chat can have, and the sounds of message effects.
They are made from scratch, so they are our own, except the cats: those are
cut from a real recording in recordings/ (CC BY 4.0, see its README.md).

    python scripts/gruppechat_sounds.py

Writes each as a WAV file to assets/sounds/ for the app, and the
notification sounds also to android/app/src/main/res/raw/, where Android
takes a notification's sound from. Only the standard library.
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
CLIENT = Path(__file__).resolve().parents[1]


def silence(seconds: float) -> list[float]:
    return [0.0] * int(RATE * seconds)


def tone(freq, seconds, decay=6.0, partials=((1, 1.0),), attack=0.004, glide=None, vibrato=0.0):
    """A note: partials as (frequency ratio, loudness), fading out."""
    n = int(RATE * seconds)
    out = []
    phase = [0.0] * len(partials)
    for i in range(n):
        t = i / RATE
        f = freq if glide is None else freq + (glide - freq) * min(1.0, t / seconds)
        if vibrato:
            f *= 1 + vibrato * math.sin(2 * math.pi * 5.5 * t)
        envelope = min(1.0, t / attack) * math.exp(-decay * t)
        sample = 0.0
        for k, (ratio, loudness) in enumerate(partials):
            phase[k] += 2 * math.pi * f * ratio / RATE
            sample += loudness * math.sin(phase[k]) * math.exp(-decay * ratio * 0.3 * t)
        out.append(sample * envelope)
    return out


def noise(seconds, decay=8.0, seed=1, brightness=0.5):
    rng = random.Random(seed)
    out, last = [], 0.0
    for i in range(int(RATE * seconds)):
        # A simple low-pass: brightness 1 keeps all of it
        last += brightness * (rng.uniform(-1, 1) - last)
        out.append(last * math.exp(-decay * i / RATE))
    return out


def mix(*parts):
    """(start in seconds, samples) pairs, added together."""
    length = max(int(start * RATE) + len(samples) for start, samples in parts)
    out = [0.0] * length
    for start, samples in parts:
        offset = int(start * RATE)
        for i, s in enumerate(samples):
            out[offset + i] += s
    return out


BELL = ((1, 1.0), (2.0, 0.5), (2.76, 0.35), (5.4, 0.15))
SOFT = ((1, 1.0), (2, 0.25), (3, 0.08))


def note(name):
    # Equal temperament from A4 = 440 Hz
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    return 440 * 2 ** ((names[name[0]] + 12 * (int(name[1]) - 4)) / 12)


def chime(names, step, seconds=0.6, decay=5.0, partials=BELL, loudness=0.5):
    return mix(*[(i * step, [s * loudness for s in tone(note(n), seconds, decay, partials)]) for i, n in enumerate(names)])


def sparkles(count, seconds, seed):
    rng = random.Random(seed)
    return mix(
        *[
            (rng.uniform(0, seconds), [s * 0.18 for s in tone(rng.uniform(2200, 4200), 0.25, 14, ((1, 1.0), (2.3, 0.3)))])
            for _ in range(count)
        ]
    )


# A real cat, since 1.1.30: five meows of a British Shorthair asking for
# food, cut from a recording on Wikimedia Commons (see recordings/README.md,
# CC BY 4.0). Where each meow starts and ends in the excerpt, in seconds.
RECORDING = Path(__file__).resolve().parent / "recordings" / "kortharkatt.wav"
# Meows 3 and 4 are no longer used since 1.1.40: 4 is by far the brightest,
# and sped up for the kitten it was shrill, "litt skummel"; 3 went with the
# fourth cat of the effect, so the others don't overlap.
MEOWS = [(0.0, 1.2), (1.45, 3.2), (3.45, 4.8), (5.05, 6.65), (6.9, 8.2)]


def recording() -> list[float]:
    with wave.open(str(RECORDING)) as file:
        assert (file.getnchannels(), file.getsampwidth(), file.getframerate()) == (1, 2, RATE)
        frames = file.readframes(file.getnframes())
    return [s / 32768 for (s,) in struct.iter_unpack("<h", frames)]


def faded(samples, rise=0.05, release=0.4):
    """Fades in and out on a raised cosine. The recorded meows swell towards
    their end, and some were cut while at their loudest, so they stopped like
    a shout; the long fade-out lets each die away instead (1.1.40)."""
    out = list(samples)
    n_in = min(int(RATE * rise), len(out) // 2)
    n_out = min(int(RATE * release), len(out) // 2)
    for k in range(n_in):
        out[k] *= 0.5 - 0.5 * math.cos(math.pi * k / n_in)
    for k in range(n_out):
        out[-1 - k] *= 0.5 - 0.5 * math.cos(math.pi * k / n_out)
    return out


def lowpass(samples, cutoff):
    """A windowed-sinc low-pass filter, cutoff in Hz."""
    taps = 63
    fc = cutoff / RATE
    kernel = []
    for i in range(taps):
        m = i - taps // 2
        sinc = 2 * fc if m == 0 else math.sin(2 * math.pi * fc * m) / (math.pi * m)
        kernel.append(sinc * (0.54 - 0.46 * math.cos(2 * math.pi * i / (taps - 1))))
    total = sum(kernel)
    kernel = [k / total for k in kernel]
    half = taps // 2
    padded = [0.0] * half + list(samples) + [0.0] * half
    return [sum(k * padded[i + j] for j, k in enumerate(kernel)) for i in range(len(samples))]


# From here up the meows are filtered away, so they are warm rather than
# shrill (1.1.40). With lowpass's 63 taps it is a slope, not a cut: about
# 1 kHz wide, more so for a meow that is sped up.
MEOW_CUTOFF = 1800


def meow(index, pitch=1.0, loudness=1.0):
    """Meow number index of the recording; pitch above 1 plays it faster,
    so higher and shorter, like a kitten."""
    start, end = MEOWS[index]
    # Filtered before it is sped up, so the filter lands at MEOW_CUTOFF
    # after, and nothing goes above half the rate and folds back
    samples = lowpass(CAT[int(start * RATE) : int(end * RATE)], MEOW_CUTOFF / pitch)
    if pitch != 1.0:
        n = int(len(samples) / pitch)
        out = []
        for i in range(n):
            x = i * pitch
            j = int(x)
            nxt = samples[j + 1] if j + 1 < len(samples) else 0.0
            out.append(samples[j] + (x - j) * (nxt - samples[j]))
        samples = out
    return [loudness * s for s in faded(samples)]


CAT = recording()


SOUNDS = {
    # In a chat that is open: what you send, and what comes in
    "gc_sent": tone(520, 0.12, 22, SOFT, glide=1100),
    "gc_received": mix((0, tone(note("E6"), 0.18, 16, SOFT)), (0.08, tone(note("A6"), 0.25, 14, SOFT))),
    # Notification sounds a chat can have
    "gc_bjelle": tone(880, 1.2, 3.5, BELL),
    "gc_pling": tone(note("G6"), 0.6, 8, ((1, 1.0), (2, 0.35), (4.1, 0.1))),
    "gc_klokkespill": chime(["C6", "E6", "G6", "C7"], 0.11, 0.8),
    "gc_boble": mix((0, tone(300, 0.09, 18, SOFT, glide=900)), (0.13, tone(380, 0.09, 18, SOFT, glide=1100))),
    "gc_floyte": tone(700, 0.55, 3, ((1, 1.0), (2, 0.12)), attack=0.06, glide=1050, vibrato=0.01),
    "gc_dobbeltpip": mix(*[(i * 0.16, tone(1000, 0.1, 10, ((1, 1.0), (3, 0.2), (5, 0.07)), attack=0.008)) for i in range(2)]),
    "gc_mjau": meow(0),
    "gc_kattunge": mix((0, meow(2, 1.5)), (0.65, meow(1, 1.5))),
    # Message effects
    "gc_effect_konfetti": mix((0, noise(0.25, 18, 3, 0.9)), (0.05, tone(180, 0.12, 25, SOFT)), (0.1, sparkles(22, 1.4, 4))),
    "gc_effect_hjerter": mix(
        (0, chime(["C5", "E5", "G5", "C6", "E6"], 0.16, 1.2, 2.5, SOFT, 0.35)),
        (0.15, [s * 0.15 for s in tone(note("C4"), 1.6, 1.5, SOFT, attack=0.3)]),
    ),
    "gc_effect_ballonger": mix(
        *[(i * 0.28, [s * 0.4 for s in tone(220 + 60 * i, 0.35, 6, SOFT, glide=520 + 80 * i, vibrato=0.04)]) for i in range(4)]
    ),
    "gc_effect_fyrverkeri": mix(
        (0, [s * 0.25 for s in tone(800, 0.6, 1, ((1, 1.0),), attack=0.05, glide=2400)]),
        (0.6, noise(0.9, 4.5, 7, 0.35)),
        (0.62, [s * 0.5 for s in tone(70, 0.5, 6, SOFT)]),
        (0.8, sparkles(30, 1.0, 8)),
    ),
    # Each cat starts as the one before fades out, rather than up to three
    # wailing over each other (1.1.40)
    "gc_effect_katter": mix(
        (0, meow(1, 1.0, 0.8)),
        (1.4, meow(2, 1.5, 0.6)),
        (2.1, meow(0, 1.5, 0.7)),
    ),
}

NOTIFICATION_SOUNDS = {
    "gc_bjelle",
    "gc_pling",
    "gc_klokkespill",
    "gc_boble",
    "gc_floyte",
    "gc_dobbeltpip",
    "gc_mjau",
    "gc_kattunge",
}


# How loud each sound is written, as a part of full scale. A meow holds its
# loudness over a second, in the 0.5-4 kHz the ear hears best, so at the
# tones' 0.8 the cats were "helt ekstremt høyt" (1.1.39): A-weighted, over
# their loudest 0.37 s, 21-22 dB against 15.6 for the app's usual
# notification sound (notification.mp3) and 16.7 for the bell. At half of
# that they measure 15.2-15.9, as loud as the usual sound, and still "kan
# gjerne være lågare" (1.1.40): since then about 4 dB below it. Low-passed
# and faded (MEOW_CUTOFF, faded), their peak is lower against their
# loudness, so 0.22 rather than 0.25 keeps them as loud, A-weighted, within
# 1 dB.
LEVEL = 0.8
CAT_LEVEL = 0.22
CATS = {"gc_mjau", "gc_kattunge", "gc_effect_katter"}


def write(path: Path, samples: list[float], level: float) -> None:
    peak = max(abs(s) for s in samples) or 1.0
    # Normalised, then a short fade-out so nothing clicks at the end
    fade = int(RATE * 0.02)
    frames = bytearray()
    for i, s in enumerate(samples):
        gain = min(1.0, (len(samples) - i) / fade)
        frames += struct.pack("<h", int(32767 * level * gain * s / peak))
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(bytes(frames))


def main() -> None:
    for name, samples in SOUNDS.items():
        level = CAT_LEVEL if name in CATS else LEVEL
        write(CLIENT / "assets" / "sounds" / f"{name}.wav", samples, level)
        if name in NOTIFICATION_SOUNDS:
            write(CLIENT / "android" / "app" / "src" / "main" / "res" / "raw" / f"{name}.wav", samples, level)
    print(f"Wrote {len(SOUNDS)} sounds")


if __name__ == "__main__":
    main()
