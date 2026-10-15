#!/usr/bin/env python3
"""Renders docs/states.gif: every mascot state, animated with the manifest's frame counts and speeds.

    python3 scripts/make_preview.py
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "Claudenotchi" / "Sprites"
OUT = ROOT / "docs" / "states.gif"

SCALE = 8          # art pixels -> GIF pixels
CELL_W, CELL_H = 16 * SCALE + 56, 16 * SCALE + 44
COLS = 4
TICK_MS = 50
DURATION_MS = 12000
BG = (0, 0, 0)

LABELS = {
    "waiting": "waiting", "thinking": "thinking", "coding": "writing code", "reading": "reading",
    "bash": "running a command", "web": "searching the web", "alert": "needs you",
    "celebrating": "done", "error": "error", "videogame": "idle: gaming", "tennis": "idle: tennis",
    "sleeping": "asleep",
}

manifest = json.loads((SPRITES / "manifest.json").read_text())
states = [k for k in LABELS if k in manifest["states"]]
strips = {}
for name in states:
    entry = manifest["states"][name]
    strip = Image.open(SPRITES / entry["size16"]).convert("RGBA")
    strips[name] = [strip.crop((i * 16, 0, i * 16 + 16, 16)) for i in range(entry["frames"])]

font = ImageFont.load_default(size=15)
rows = (len(states) + COLS - 1) // COLS
width, height = COLS * CELL_W, rows * CELL_H


def render(t_ms: int) -> Image.Image:
    canvas = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(canvas)
    for index, name in enumerate(states):
        entry = manifest["states"][name]
        frame = strips[name][int(t_ms * entry["fps"] / 1000) % entry["frames"]]
        x, y = (index % COLS) * CELL_W, (index // COLS) * CELL_H
        sprite = frame.resize((16 * SCALE, 16 * SCALE), Image.NEAREST)
        canvas.paste(sprite, (x + (CELL_W - 16 * SCALE) // 2, y + 12), sprite)
        text = LABELS[name]
        w = draw.textlength(text, font=font)
        draw.text((x + (CELL_W - w) / 2, y + 16 * SCALE + 18), text, fill=(190, 190, 190), font=font)
    return canvas


frames = [render(t) for t in range(0, DURATION_MS, TICK_MS)]
OUT.parent.mkdir(exist_ok=True)
frames[0].save(OUT, save_all=True, append_images=frames[1:], duration=TICK_MS, loop=0, optimize=True)
print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB, {len(frames)} frames)")
