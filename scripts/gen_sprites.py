#!/usr/bin/env python3
"""Generate Claudenotchi sprite assets from pixel maps.

Source of truth for the mascot art (mirrors the Figma file "Claudenotchi").
Outputs:
  art/sprites.json                         pixel maps (16px for every state, 32px for key states)
  Claudenotchi/Sprites/<state>@16.png      horizontal strip, 16N x 16, transparent RGBA
  Claudenotchi/Sprites/<state>@32.png      horizontal strip, 32N x 32 (every frame, used by the expanded view)
  Claudenotchi/Sprites/manifest.json       state -> frames, fps, files

Run from the repo root:  python3 -I scripts/gen_sprites.py
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Claudenotchi", "Sprites")
ART_DIR = os.path.join(ROOT, "art")

PALETTE = {
    "O": (0xD9, 0x77, 0x57), "D": (0xB0, 0x5A, 0x3C), "L": (0xEB, 0xA5, 0x8B),
    "K": (0x1A, 0x1A, 0x1A), "W": (0xFF, 0xFF, 0xFF), "B": (0x5A, 0xA0, 0xE8),
    "G": (0x5B, 0xC2, 0x7A), "R": (0xE5, 0x48, 0x4D), "Y": (0xF5, 0xC5, 0x42),
    "E": (0x8A, 0x8A, 0x8A),
}

BASE = [
    "................", "................", "..OOOOOOOOOOOO..", "..OOOOOOOOOOOO..",
    "..OOKOOOOOOKOO..", "..OOKOOOOOOKOO..", "OOOOOOOOOOOOOOOO", "OOOOOOOOOOOOOOOO",
    "..OOOOOOOOOOOO..", "..OOOOOOOOOOOO..", "..DDDDDDDDDDDD..", "................",
    "..OO.OO..OO.OO..", "..OO.OO..OO.OO..", "..DD.DD..DD.DD..", "................",
]


def R(x0, y0, x1, y1, ch):
    return ("rect", x0, y0, x1, y1, ch)


def P(x, y, ch):
    return (x, y, ch)


def apply(g, patches):
    for p in patches:
        if p[0] == "rect":
            _, x0, y0, x1, y1, ch = p
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    if 0 <= y < len(g) and 0 <= x < len(g[y]):
                        g[y][x] = ch
        else:
            x, y, ch = p
            if 0 <= y < len(g) and 0 <= x < len(g[y]):
                g[y][x] = ch


def mk(patches=(), dx=0, dy=0, after=()):
    g = [list(r) for r in BASE]
    apply(g, patches)
    if dx or dy:
        s = [["."] * 16 for _ in range(16)]
        for y in range(16):
            for x in range(16):
                ny, nx = y + dy, x + dx
                if 0 <= ny < 16 and 0 <= nx < 16:
                    s[ny][nx] = g[y][x]
        g = s
    apply(g, after)
    return ["".join(r) for r in g]


NOEYES = [R(4, 4, 4, 5, "O"), R(11, 4, 11, 5, "O")]


def eyes(y0, h, dx=0):
    return NOEYES + [R(4 + dx, y0, 4 + dx, y0 + h - 1, "K"), R(11 + dx, y0, 11 + dx, y0 + h - 1, "K")]


NOARMS = [R(0, 6, 1, 7, "."), R(14, 6, 15, 7, ".")]
ARMSUP = NOARMS + [R(0, 1, 1, 3, "O"), R(14, 1, 15, 3, "O")]
BLINK = NOEYES + [P(4, 5, "K"), P(11, 5, "K")]

S = {}

# waiting: a crab-style scuttle. The body faces front (eyes never turn toward the direction of travel) and
# slides sideways one pixel at a time while the legs skitter in alternating pairs. It rests on each side for
# over a second (with a leg twitch and a blink) before scuttling across.
LEGS_A = [R(2, 13, 3, 13, "D"), R(2, 14, 3, 14, "."), R(9, 13, 10, 13, "D"), R(9, 14, 10, 14, ".")]
LEGS_B = [R(5, 13, 6, 13, "D"), R(5, 14, 6, 14, "."), R(12, 13, 13, 13, "D"), R(12, 14, 13, 14, ".")]


def scuttle(legs, dx, eyes_patch=None):
    """Body at sideways offset `dx`, legs lifted in pair `legs`; the side arms are single nubs so they never clip."""
    return mk((eyes_patch or eyes(4, 2, 0)) + NOARMS + legs, dx,
              after=[P(1 + dx, 6, "O"), P(1 + dx, 7, "O"), P(14 + dx, 6, "O"), P(14 + dx, 7, "O")])


STAND = mk()


def step(position):
    """One pixel of travel takes two frames (legs A, then legs B), so the scuttle is quick on the legs
    but covers ground slowly."""
    return [scuttle(LEGS_A, position), scuttle(LEGS_B, position)]


def dwell(position, frames, twitch_at=(), blink_at=()):
    """Stay put at `position`, with a leg twitch and a blink now and then so he is not frozen."""
    out = []
    for i in range(frames):
        if i in blink_at:
            out.append(scuttle([], position, BLINK) if position else mk(BLINK))
        elif i in twitch_at:
            out.append(scuttle(LEGS_A if i % 2 else LEGS_B, position))
        else:
            out.append(scuttle([], position) if position else STAND)
    return out


# Centre, scuttle right, rest on the right for over a second, scuttle across to the left, rest there,
# scuttle home. About 4.6 s per loop at 10 fps.
S["waiting"] = (10,
    dwell(0, 6, blink_at=(4,))
    + step(1) + step(2)
    + dwell(2, 12, twitch_at=(3, 8), blink_at=(6,))
    + step(1) + step(0) + step(-1) + step(-2)
    + dwell(-2, 12, twitch_at=(3, 9), blink_at=(7,))
    + step(-1) + step(0))


def thinking(dots, dx=0):
    return mk(eyes(3, 2, dx), 0, 0, [P(x, 1, "W") for x in dots])


S["thinking"] = (4, [thinking([11]), thinking([11, 13]), thinking([11, 13, 15]), thinking([11, 13, 15], 1)])

LAP = NOARMS + [R(3, 9, 12, 11, "E"), R(4, 9, 11, 10, "B"), R(2, 12, 13, 12, "E")]


def coding(chars, hand):
    return mk(LAP + [P(x, y, "W") for x, y in chars] + [P(hand[0], 12, "D"), P(hand[1], 12, "D")])


S["coding"] = (6, [
    coding([(5, 9), (6, 9)], (5, 10)),
    coding([(5, 9), (6, 9), (7, 9), (5, 10)], (4, 11)),
    coding([(5, 9), (6, 9), (7, 9), (8, 9), (5, 10), (6, 10), (7, 10)], (6, 9)),
    coding([(5, 9), (6, 9), (7, 9), (8, 9), (9, 9), (5, 10), (6, 10), (7, 10), (8, 10)], (5, 11)),
])

BOOK = NOARMS + [R(1, 10, 2, 11, "O"), R(13, 10, 14, 11, "O"), R(3, 10, 12, 12, "W"), R(7, 10, 8, 12, "E"), R(4, 11, 6, 11, "E")]
S["reading"] = (3, [
    mk(eyes(5, 1, -1) + BOOK),
    mk(eyes(5, 1, 0) + BOOK),
    mk(eyes(5, 1, 1) + BOOK + [R(9, 11, 11, 11, "E")]),
    mk(eyes(5, 1, 0) + BOOK + [R(9, 10, 12, 12, "W"), R(10, 10, 10, 12, "E"), R(11, 11, 12, 11, "E")]),
])

TERM = [R(3, 9, 12, 13, "K"), R(3, 9, 12, 9, "E"), P(4, 10, "G"), P(5, 11, "G"), P(4, 12, "G")]
S["bash"] = (4, [
    mk(TERM + [R(7, 11, 7, 12, "W")]),
    mk(TERM + [P(7, 11, "G"), P(8, 11, "G")]),
    mk(TERM + [R(7, 11, 10, 11, "G"), R(11, 11, 11, 12, "W")]),
    mk(TERM + [R(7, 11, 10, 11, "G"), R(4, 13, 9, 13, "G")]),
])

GL = [R(13, 0, 14, 0, "B"), R(12, 1, 15, 2, "B"), R(13, 3, 14, 3, "B")]
S["web"] = (6, [
    mk(eyes(3, 2, 1) + GL + [P(13, 1, "G"), P(13, 2, "G")]),
    mk(eyes(3, 2, 1) + GL + [P(14, 1, "G"), P(14, 2, "G")]),
    mk(eyes(3, 2, 1) + GL + [P(15, 1, "G"), P(12, 2, "G"), P(13, 2, "G")]),
    mk(eyes(3, 2, 1) + GL + [P(12, 1, "G"), P(13, 1, "G"), P(14, 2, "G")]),
])

AE = NOEYES + [R(4, 4, 5, 5, "K"), R(10, 4, 11, 5, "K")]


def bang(c):
    return [R(7, 0, 8, 1, c), R(7, 3, 8, 3, c)]


S["alert"] = (8, [mk(AE + bang("R") + ARMSUP), mk(AE + bang("Y")), mk(AE + bang("R") + ARMSUP), mk(AE + bang("Y"))])

HE = NOEYES + [P(3, 5, "K"), P(4, 4, "K"), P(5, 5, "K"), P(10, 5, "K"), P(11, 4, "K"), P(12, 5, "K")]
CS = [[(3, 0, "Y"), (12, 0, "R"), (8, 0, "G")], [(4, 0, "R"), (10, 0, "Y"), (7, 0, "G")], [(5, 0, "G"), (11, 0, "R"), (3, 0, "Y")]]
S["celebrating"] = (8, [mk(HE + ARMSUP, 0, -1 if i % 2 else 0, [P(x, y, c) for x, y, c in CS[i % 3]]) for i in range(6)])

XE = NOEYES + [P(3, 4, "K"), P(5, 4, "K"), P(4, 5, "K"), P(3, 6, "K"), P(5, 6, "K"),
               P(10, 4, "K"), P(12, 4, "K"), P(11, 5, "K"), P(10, 6, "K"), P(12, 6, "K")]
STARS = [[(4, 1), (11, 0)], [(6, 0), (9, 1)], [(8, 0), (12, 1)], [(5, 1), (10, 0)]]
S["error"] = (8, [mk(XE, [0, -1, 0, 1][i], 0, [P(x, y, "Y") for x, y in STARS[i]]) for i in range(4)])


def gear(btn):
    return NOARMS + [R(1, 9, 2, 10, "O"), R(13, 9, 14, 10, "O"), R(3, 10, 12, 12, "E"),
                     P(5, 10, "K"), P(4, 11, "K"), P(6, 11, "K"), P(5, 12, "K")] + [P(x, y, c) for x, y, c in btn]


S["videogame"] = (6, [
    mk(eyes(4, 2, -1) + gear([(10, 11, "R"), (11, 10, "G")])),
    mk(eyes(4, 2, -1) + gear([(10, 11, "W"), (11, 10, "G")])),
    mk(eyes(4, 2, 1) + gear([(10, 11, "R"), (11, 10, "W")])),
    mk(eyes(4, 2, 1) + gear([(11, 12, "Y"), (10, 11, "R")])),
])


def racket(r0):
    return NOARMS + [R(0, r0, 1, r0 + 3, "W"), P(1, r0 + 4, "E"), P(1, r0 + 5, "E")]


S["tennis"] = (6, [
    mk(eyes(4, 2, 1) + racket(2), 0, 0, [P(14, 1, "Y")]),
    mk(eyes(4, 2, 1) + racket(2), 0, 0, [P(10, 0, "Y")]),
    mk(eyes(4, 2, 0) + racket(2), 0, 0, [P(6, 0, "Y")]),
    mk(eyes(4, 2, -1) + racket(2), 0, 0, [P(3, 1, "Y")]),
    mk(eyes(4, 2, -1) + racket(0), 0, 0, [P(5, 0, "Y")]),
    mk(eyes(4, 2, 1) + racket(2), 0, 0, [P(10, 0, "Y")]),
])

SE = NOEYES + [R(3, 5, 5, 5, "K"), R(10, 5, 12, 5, "K")]
Z = [R(13, 0, 15, 0, "W"), P(14, 1, "W"), R(13, 2, 15, 2, "W")]
S["sleeping"] = (2, [
    mk(SE, 0, 0, [P(13, 1, "W")]),
    mk(SE, 0, 1, Z),
    mk(SE, 0, 1, Z + [P(11, 1, "W")]),
    mk(SE, 0, 0, Z + [P(11, 1, "W"), P(9, 0, "W")]),
])


def big(m, glint):
    """32px art: 16px map upscaled 2x + top highlight, right-edge shade, eye glint."""
    up = []
    for r in m:
        rr = "".join(c + c for c in r)
        up += [list(rr), list(rr)]
    h, w = len(up), len(up[0])
    for y in range(h):
        if sum(1 for c in up[y] if c == "O") >= 20:
            for x in range(6, 26):
                if up[y][x] == "O":
                    up[y][x] = "L"
            break
    for y in range(h):
        for x in range(w - 1):
            if up[y][x] == "O" and up[y][x + 1] == ".":
                up[y][x] = "D"
    if glint:
        # decide from the original grid so the glint does not cascade
        orig = [r[:] for r in up]
        for y in range(1, h):
            for x in range(1, w):
                if orig[y][x] == "K" and orig[y - 1][x] != "K" and orig[y][x - 1] != "K":
                    up[y][x] = "W"
    return ["".join(r) for r in up]


# States whose eyes are not plain dark bars (happy ^ ^, X X, closed lines) get no eye glint.
NO_GLINT = {"celebrating", "error", "sleeping"}


def to_strip(maps, size):
    img = Image.new("RGBA", (size * len(maps), size), (0, 0, 0, 0))
    px = img.load()
    for i, m in enumerate(maps):
        for y, row in enumerate(m):
            for x, ch in enumerate(row):
                if ch != ".":
                    px[i * size + x, y] = PALETTE[ch] + (255,)
    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(ART_DIR, exist_ok=True)
    manifest = {"states": {}, "idle": ["waiting", "videogame", "tennis"]}
    maps_json = {}
    for name, (fps, frames) in S.items():
        entry = {"frames": len(frames), "fps": fps, "size16": f"{name}@16.png", "size32": None}
        to_strip(frames, 16).save(os.path.join(OUT_DIR, f"{name}@16.png"))
        maps_json[name] = {"16": frames}
        b = [big(frame, name not in NO_GLINT) for frame in frames]
        to_strip(b, 32).save(os.path.join(OUT_DIR, f"{name}@32.png"))
        entry["size32"] = f"{name}@32.png"
        entry["frames32"] = len(b)
        maps_json[name]["32"] = b
        manifest["states"][name] = entry
    with open(os.path.join(OUT_DIR, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    with open(os.path.join(ART_DIR, "sprites.json"), "w") as f:
        json.dump(maps_json, f, indent=1)
        f.write("\n")
    print(f"wrote {len(S)} states to {OUT_DIR}", file=sys.stderr)


if __name__ == "__main__":
    main()
