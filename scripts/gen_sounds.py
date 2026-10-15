#!/usr/bin/env python3
"""Generate Claudenotchi's 8-bit chimes (square waves with a quick decay).

Outputs, mono 16-bit PCM at 22.05 kHz:
  Claudenotchi/Sounds/needs-input.wav   two rising notes, an attention "ding-ding"
  Claudenotchi/Sounds/done.wav          a short rising arpeggio

Run from the repo root:  python3 -I scripts/gen_sounds.py
"""
import math
import os
import struct
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Claudenotchi", "Sounds")
RATE = 22050
VOLUME = 0.30  # fraction of full scale; leaves headroom and stays polite

NOTE = {"C5": 523.25, "E5": 659.25, "G5": 783.99, "B5": 987.77, "C6": 1046.50, "E6": 1318.51}


def tone(freq, seconds, duty=0.5):
    """One square-wave note with a short attack and an exponential decay, so it never clicks."""
    count = int(RATE * seconds)
    attack = max(1, int(RATE * 0.004))
    samples = []
    for i in range(count):
        phase = (i * freq / RATE) % 1.0
        value = 1.0 if phase < duty else -1.0
        envelope = math.exp(-4.0 * i / count)
        if i < attack:
            envelope *= i / attack
        if i > count - attack:
            envelope *= max(0.0, (count - i) / attack)
        samples.append(value * envelope * VOLUME)
    return samples


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def write(name, parts):
    samples = [s for part in parts for s in part]
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print(f"wrote {path} ({len(samples) / RATE:.2f}s)", file=sys.stderr)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write("needs-input.wav", [tone(NOTE["C6"], 0.10), silence(0.03), tone(NOTE["E6"], 0.20)])
    write("done.wav", [tone(NOTE["C5"], 0.07), tone(NOTE["E5"], 0.07), tone(NOTE["G5"], 0.07), tone(NOTE["C6"], 0.22)])


if __name__ == "__main__":
    main()
