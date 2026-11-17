#!/usr/bin/env python3
"""Build all spritesheets and Frames.js for Navbar Cat.

Theme-tinted characters (neko, tora, dog) come from oneko's XBM bitmaps and
emit alpha-only *-fill.png and *-ink.png sheets so they take Omarchy's active
bar colours at runtime.

Colorful characters (cats, dogs, rats, pandas, horses) emit full-RGBA
*-color.png sheets at both 32px and 16px, built via tools/animal_sprites.py.

Uses only Python's standard library (zlib + struct) so it runs with zero
external dependencies on any Omarchy installation.
"""

import json
import struct
import sys
import zlib
from pathlib import Path

from animal_sprites import build_character_frames, downsample_16, read_xbm

REPO = Path(__file__).resolve().parent.parent
VENDOR = REPO / "vendor" / "oneko"
ASSETS = REPO / "assets"

SIZE = 32

# Theme-tinted oneko characters (alpha-only fill + ink layers).
TINTED_CHARACTERS = {
    "neko": {"suffix": "", "masks": "neko", "mask_suffix": ""},
    "tora": {"suffix": "_tora", "masks": "neko", "mask_suffix": ""},
    "dog": {"suffix": "_dog", "masks": "dog", "mask_suffix": "_dog"},
}

# Full catalog in menu display order.
CATALOG = [
    {"id": "neko",        "label": "Neko",       "group": "Themed", "colorful": False},
    {"id": "tora",        "label": "Tora",       "group": "Themed", "colorful": False},
    {"id": "dog",         "label": "Dog",        "group": "Themed", "colorful": False},
    {"id": "cat-ginger",  "label": "Ginger",     "group": "Cats",   "colorful": True},
    {"id": "cat-calico",  "label": "Calico",     "group": "Cats",   "colorful": True},
    {"id": "cat-tuxedo",  "label": "Tuxedo",     "group": "Cats",   "colorful": True},
    {"id": "dog-golden",  "label": "Golden",     "group": "Dogs",   "colorful": True},
    {"id": "dog-husky",   "label": "Husky",      "group": "Dogs",   "colorful": True},
    {"id": "dog-corgi",   "label": "Corgi",      "group": "Dogs",   "colorful": True},
    {"id": "rat-gray",    "label": "Gray Rat",   "group": "Rats",   "colorful": True},
    {"id": "rat-white",   "label": "White Rat",  "group": "Rats",   "colorful": True},
    {"id": "panda",       "label": "Panda",      "group": "Pandas", "colorful": True},
    {"id": "panda-red",   "label": "Red Panda",  "group": "Pandas", "colorful": True},
    {"id": "horse-brown", "label": "Brown",      "group": "Horses",      "colorful": True},
    {"id": "horse-white", "label": "White",      "group": "Horses",      "colorful": True},
    {"id": "bird-blue",   "label": "Bluebird",   "group": "Birds",       "colorful": True},
    {"id": "bird-parrot", "label": "Parrot",     "group": "Birds",       "colorful": True},
    {"id": "fairy-pixie",   "label": "Fairy",    "group": "Fairy Tales", "colorful": True},
    {"id": "fairy-unicorn", "label": "Unicorn",  "group": "Fairy Tales", "colorful": True},
    {"id": "fairy-dragon",  "label": "Dragon",   "group": "Fairy Tales", "colorful": True},
]

FRAMES = [
    "mati2", "jare2", "kaki1", "kaki2", "mati3", "sleep1", "sleep2", "awake",
    "up1", "up2", "down1", "down2", "left1", "left2", "right1", "right2",
    "upleft1", "upleft2", "upright1", "upright2",
    "dwleft1", "dwleft2", "dwright1", "dwright2",
    "utogi1", "utogi2", "dtogi1", "dtogi2", "ltogi1", "ltogi2", "rtogi1", "rtogi2",
]

POSES = {
    "stop":    ["mati2", "mati2"],
    "wash":    ["jare2", "mati2"],
    "scratch": ["kaki1", "kaki2"],
    "yawn":    ["mati3", "mati3"],
    "sleep":   ["sleep1", "sleep2"],
    "awake":   ["awake", "awake"],
    "up":      ["up1", "up2"],
    "down":    ["down1", "down2"],
    "left":    ["left1", "left2"],
    "right":   ["right1", "right2"],
    "upleft":  ["upleft1", "upleft2"],
    "upright": ["upright1", "upright2"],
    "dwleft":  ["dwleft1", "dwleft2"],
    "dwright": ["dwright1", "dwright2"],
    "utogi":   ["utogi1", "utogi2"],
    "dtogi":   ["dtogi1", "dtogi2"],
    "ltogi":   ["ltogi1", "ltogi2"],
    "rtogi":   ["rtogi1", "rtogi2"],
}


def png_chunk(chunk_type, data):
    return (
        struct.pack(">I", len(data))
        + chunk_type
        + data
        + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    )


def write_png_rgba(path, width, height, rows_rgba):
    """Write an RGBA PNG from a height x width matrix of (r, g, b, a) tuples."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        row = rows_rgba[y]
        for x in range(width):
            r, g, b, a = row[x]
            raw.extend((r, g, b, a))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), level=9)
    png = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", idat) + png_chunk(b"IEND", b"")
    path.write_bytes(png)
    return path


def load_xbm_frame(character, name):
    spec = TINTED_CHARACTERS[character]
    image = read_xbm(VENDOR / "bitmaps" / character / f"{name}{spec['suffix']}.xbm")
    mask = read_xbm(
        VENDOR / "bitmasks" / spec["masks"] / f"{name}{spec['mask_suffix']}_mask.xbm"
    )
    ink = [[image[y][x] & mask[y][x] for x in range(SIZE)] for y in range(SIZE)]
    return mask, ink


def halve_mask(grid):
    return [
        [
            1 if any(grid[y + dy][x + dx] for dy in (0, 1) for dx in (0, 1)) else 0
            for x in range(0, SIZE, 2)
        ]
        for y in range(0, SIZE, 2)
    ]


def write_alpha_sheet(path, grids, cell):
    width = cell * len(grids)
    rows = []
    for y in range(cell):
        row = []
        for grid in grids:
            for x in range(cell):
                row.append((255, 255, 255, 255 if grid[y][x] else 0))
        rows.append(row)
    return write_png_rgba(path, width, cell, rows)


def write_color_sheet(path, tagged_grids, cell):
    width = cell * len(tagged_grids)
    rows = []
    for y in range(cell):
        row = []
        for grid in tagged_grids:
            for x in range(cell):
                row.append(grid[y][x][0])
        rows.append(row)
    return write_png_rgba(path, width, cell, rows)


def main():
    ASSETS.mkdir(exist_ok=True)
    written = []

    for character, spec in TINTED_CHARACTERS.items():
        missing = [
            n for n in FRAMES
            if not (VENDOR / "bitmaps" / character / f"{n}{spec['suffix']}.xbm").exists()
        ]
        if missing:
            sys.exit(f"{character}: missing vendored frames: {', '.join(missing)}")

        loaded = [load_xbm_frame(character, name) for name in FRAMES]
        written += [
            write_alpha_sheet(ASSETS / f"{character}32-fill.png", [m for m, _ in loaded], 32),
            write_alpha_sheet(ASSETS / f"{character}32-ink.png", [i for _, i in loaded], 32),
            write_alpha_sheet(ASSETS / f"{character}16-fill.png", [halve_mask(m) for m, _ in loaded], 16),
            write_alpha_sheet(ASSETS / f"{character}16-ink.png", [halve_mask(i) for _, i in loaded], 16),
        ]

    for entry in CATALOG:
        if not entry["colorful"]:
            continue
        cid = entry["id"]
        frames32 = build_character_frames(VENDOR, cid, FRAMES)
        frames16 = [downsample_16(g) for g in frames32]
        written += [
            write_color_sheet(ASSETS / f"{cid}32-color.png", frames32, 32),
            write_color_sheet(ASSETS / f"{cid}16-color.png", frames16, 16),
        ]

    characters = [entry["id"] for entry in CATALOG]
    colorful_map = {entry["id"]: True for entry in CATALOG if entry["colorful"]}
    index_map = {name: i for i, name in enumerate(FRAMES)}
    poses_map = {pose: [FRAMES.index(a), FRAMES.index(b)] for pose, (a, b) in POSES.items()}

    frames_js = REPO / "Frames.js"
    frames_js.write_text(
        "// GENERATED by tools/build-sprites.py -- do not edit by hand.\n"
        ".pragma library\n\n"
        f"var CELL = {SIZE}\n"
        f"var COUNT = {len(FRAMES)}\n"
        f"var INDEX = {json.dumps(index_map, indent=2)}\n\n"
        f"var CHARACTERS = {json.dumps(characters)}\n\n"
        f"var COLORFUL = {json.dumps(colorful_map)}\n\n"
        f"var CATALOG = {json.dumps(CATALOG, indent=2)}\n\n"
        f"var POSES = {json.dumps(poses_map, indent=2)}\n"
    )

    for path in written:
        print(f"wrote {path.relative_to(REPO)} ({path.stat().st_size} bytes)")
    print(f"wrote {frames_js.relative_to(REPO)} ({len(characters)} characters, {len(FRAMES)} frames, {len(POSES)} poses)")


if __name__ == "__main__":
    main()
