#!/usr/bin/env python3
"""Render preview.png (1200x630) — the marketplace & social preview card.

Uses ImageMagick (`magick`) and the shipped spritesheets in `assets/` so it runs
without requiring third-party Python packages like Pillow.
"""

from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parent.parent
ASSETS = REPO / "assets"
OUT = REPO / "preview.png"

CELL = 32
INDEX = {
    "mati2": 0, "jare2": 1, "kaki1": 2, "mati3": 4, "sleep1": 5,
    "left1": 12, "right1": 14, "right2": 15, "upright1": 18,
}

SHOWCASE = [
    ("cat-ginger",    "Ginger Cat",   "right1"),
    ("cat-calico",    "Calico Cat",   "mati2"),
    ("cat-tuxedo",    "Tuxedo Cat",   "jare2"),
    ("dog-golden",    "Golden Dog",   "right1"),
    ("dog-husky",     "Husky",        "mati2"),
    ("dog-corgi",     "Corgi",        "right2"),
    ("rat-gray",      "Gray Rat",     "right1"),
    ("rat-white",     "White Rat",    "mati2"),
    ("panda",         "Panda",        "jare2"),
    ("panda-red",     "Red Panda",    "right1"),
    ("horse-brown",   "Brown Horse",  "right1"),
    ("horse-white",   "White Horse",  "mati2"),
    ("bird-blue",     "Bluebird",     "right1"),
    ("bird-parrot",   "Parrot",       "right2"),
    ("fairy-pixie",   "Fairy",        "mati2"),
    ("fairy-unicorn", "Unicorn",      "right1"),
    ("fairy-dragon",  "Dragon",       "jare2"),
]


def crop_frame(tmp_dir, char_id, frame_name, scale):
    idx = INDEX[frame_name]
    out_path = tmp_dir / f"{char_id}_{frame_name}_{scale}.png"
    sheet = ASSETS / f"{char_id}32-color.png"
    subprocess.run([
        "magick", str(sheet),
        "-crop", f"{CELL}x{CELL}+{idx * CELL}+0", "+repage",
        "-filter", "Point", "-resize", f"{scale * 100}%",
        str(out_path),
    ], check=True)
    return out_path


def main():
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        font_path = Path("/usr/share/fonts/TTF/CaskaydiaMonoNerdFont-Regular.ttf")
        font_args = ["-font", str(font_path)] if font_path.exists() else []
        cmd = [
            "magick", "-size", "1200x630", "xc:#101315",
            # Top bar strip
            "-fill", "#181c1f", "-draw", "rectangle 0,148 1200,196",
            "-fill", "#262c32", "-draw", "rectangle 0,196 1200,197",
            # Food dot + treat on bar
            "-fill", "#562812", "-draw", "circle 240,172 246,172",
            "-fill", "#F49238", "-draw", "circle 240,172 245,172",
            "-fill", "#FFE2B2", "-draw", "circle 238,170 240,170",
            # Header text
            *font_args,
            "-fill", "#eef2f6", "-pointsize", "42",
            "-annotate", "+56+68", "Navbar Pets",
            "-fill", "#8c96a2", "-pointsize", "20",
            "-annotate", "+56+108",
            "20 colourful pixel-art pets for the Omarchy bar  -  multi-pet  -  feed & play",
            "-fill", "#6c7682", "-pointsize", "15",
            "-annotate", "+56+178", "live bar",
        ]

        # Paste active pets along the top bar strip at 1x (32px)
        bar_pets = [
            ("dog-golden", "right1", 310),
            ("cat-ginger", "right2", 420),
            ("panda", "jare2", 560),
            ("bird-blue", "right1", 720),
            ("fairy-unicorn", "right1", 860),
            ("fairy-dragon", "jare2", 1010),
        ]
        for cid, pose, x in bar_pets:
            sp = crop_frame(tmp, cid, pose, 1)
            cmd += [str(sp), "-geometry", f"+{x}+156", "-composite"]

        # Grid of 17 colorful characters in 2 rows (9 on row 1, 8 on row 2) at 2.5x (80px)
        for i, (cid, label, pose) in enumerate(SHOWCASE):
            row = 0 if i < 9 else 1
            col = i if i < 9 else i - 9
            x = 48 + col * 124 + (60 if row == 1 else 0)
            y = 235 if row == 0 else 415
            sp = crop_frame(tmp, cid, pose, 2)
            cmd += [
                str(sp), "-geometry", f"+{x + 16}+{y}", "-composite",
                "-fill", "#c8d0d8", "-pointsize", "14",
                "-annotate", f"+{x}+{y + 88}", label,
            ]

        cmd.append(str(OUT))
        subprocess.run(cmd, check=True)
        print(f"wrote {OUT.relative_to(REPO)} (1200x630)")


if __name__ == "__main__":
    main()
