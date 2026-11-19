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
        font_candidates = [
            Path("/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"),
            Path("/usr/share/fonts/TTF/CaskaydiaMonoNerdFont-Regular.ttf"),
            Path("/usr/share/fonts/liberation/LiberationSans-Bold.ttf"),
        ]
        font_path = next((p for p in font_candidates if p.exists()), None)
        font_args = ["-font", str(font_path)] if font_path else []
        # Build a tiled 1200x48 mountain-forest panorama backdrop for the live bar preview
        bar_bg = tmp / "bar_bg.png"
        subprocess.run([
            "magick", "-size", "1200x32", f"tile:{ASSETS / 'theme-mountain.png'}",
            "-filter", "Point", "-resize", "1200x48!",
            "-alpha", "set", "-channel", "A", "-evaluate", "multiply", "0.52", "+channel",
            str(bar_bg),
        ], check=True)

        cmd = [
            "magick", "-size", "1200x630", "xc:#101315",
            # Top bar strip
            "-fill", "#161b22", "-draw", "rectangle 0,144 1200,196",
            str(bar_bg), "-geometry", "+0+148", "-composite",
            "-fill", "#262c32", "-draw", "rectangle 0,196 1200,197",
            # Food dot + bouncing tennis ball on bar
            "-fill", "#562812", "-draw", "circle 210,172 216,172",
            "-fill", "#F49238", "-draw", "circle 210,172 215,172",
            "-fill", "#FFE2B2", "-draw", "circle 208,170 210,170",
            "-fill", "#365314", "-draw", "circle 516,164 523,164",
            "-fill", "#A3E635", "-draw", "circle 516,164 522,164",
            "-fill", "#FFFFFF", "-draw", "circle 514,162 515,162",
            # Header text
            *font_args,
            "-fill", "#eef2f6", "-pointsize", "42",
            "-annotate", "+56+68", "Navbar Pets",
            "-fill", "#8c96a2", "-pointsize", "19",
            "-annotate", "+56+108",
            "20 colourful pets for Omarchy  -  bouncing ball  -  species treats  -  5 pixel themes",
            "-fill", "#94a3b8", "-pointsize", "14",
            "-annotate", "+56+176", "1  2  3",
        ]

        # Paste active pets along the top bar strip at 1.5x (48px):
        # grounded horses/cats/dogs/pandas on the floor, bluebird flying high!
        bar_pets = [
            ("dog-golden",    "right1", 260, 149),
            ("cat-ginger",    "right2", 380, 149),
            ("horse-brown",   "right1", 560, 149),
            ("bird-blue",     "right1", 695, 142),
            ("panda",         "sleep1", 815, 149),
            ("fairy-unicorn", "right1", 935, 149),
            ("fairy-dragon",  "jare2",  1065, 149),
        ]
        for cid, pose, x, y in bar_pets:
            sp = crop_frame(tmp, cid, pose, 1)
            cmd += [str(sp), "-geometry", f"+{x}+{y + 15}", "-composite"]

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
