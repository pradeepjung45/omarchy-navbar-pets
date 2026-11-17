#!/usr/bin/env python3
"""Generate crisp, transparent-sky 480x32 pixel-art navbar backdrop strips.

By keeping the upper sky 100% transparent (alpha=0), the user's native Omarchy
bar background and text stay razor-sharp while vibrant, full-opacity pixel-art
landscapes sit cleanly along the navbar floor behind the pets.
"""

import math
import os
import struct
import zlib

W = 480
H = 32


def write_rgba_png(path, width, height, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend((
                max(0, min(255, int(r))),
                max(0, min(255, int(g))),
                max(0, min(255, int(b))),
                max(0, min(255, int(a))),
            ))

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def new_canvas():
    return [[(0, 0, 0, 0) for _ in range(W)] for _ in range(H)]


def set_px(canvas, x, y, color):
    if 0 <= y < H:
        canvas[y][x % W] = color


def blend_px(canvas, x, y, color):
    if y < 0 or y >= H:
        return
    x = x % W
    sr, sg, sb, sa = color
    if sa <= 0:
        return
    if sa >= 255:
        canvas[y][x] = (sr, sg, sb, 255)
        return
    dr, dg, db, da = canvas[y][x]
    sa_f = sa / 255.0
    da_f = da / 255.0
    out_a = sa_f + da_f * (1.0 - sa_f)
    if out_a <= 1e-5:
        canvas[y][x] = (0, 0, 0, 0)
        return
    out_r = (sr * sa_f + dr * da_f * (1.0 - sa_f)) / out_a
    out_g = (sg * sa_f + dg * da_f * (1.0 - sa_f)) / out_a
    out_b = (sb * sa_f + db * da_f * (1.0 - sa_f)) / out_a
    canvas[y][x] = (int(out_r), int(out_g), int(out_b), int(out_a * 255))


def lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, float(t)))
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(4))


def hash2d(x, y, seed=1):
    n = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


# ---------------------------------------------------------------------------
# 1. MOUNTAIN THEME (Celeste / Alpine pixel-art style on transparent sky)
# ---------------------------------------------------------------------------
def build_mountain():
    c = new_canvas()

    # Distant blue-indigo mountain range silhouette (clean opaque pixel art)
    for x in range(W):
        theta = (x / W) * 2.0 * math.pi
        far_h = (
            10.5
            + 4.5 * math.sin(theta * 4.0 + 0.5)
            + 2.5 * math.cos(theta * 9.0 - 0.7)
            + 1.2 * math.sin(theta * 17.0 + 1.1)
        )
        far_top = int(round(H - 4 - far_h))
        for y in range(max(3, far_top), H - 3):
            dy = y - far_top
            if dy == 0:
                set_px(c, x, y, (147, 197, 253, 220))
            elif dy < 3:
                set_px(c, x, y, (96, 165, 250, 210))
            else:
                set_px(c, x, y, (59, 130, 246, 195))

    # Hero Alpine peaks with crisp ridgelines, bright snow caps, and deep slate shadows
    peaks = [
        # (center_x, height_px, left_span, right_span, skew)
        (36, 25, 30, 32, -2),
        (92, 18, 22, 24, 2),
        (154, 27, 36, 34, -3),
        (216, 20, 25, 26, 2),
        (278, 26, 33, 31, -2),
        (342, 19, 24, 25, 2),
        (412, 27, 35, 33, -2),
    ]

    for px, ph, lspan, rspan, skew in peaks:
        summit_y = H - 3 - ph
        for dx in range(-lspan, rspan + 1):
            x = (px + dx) % W
            dist_norm = abs(dx) / (lspan if dx < 0 else rspan)
            if dist_norm >= 1.0:
                continue
            jag = 1.1 * math.sin(dx * 0.42 + px) + 0.6 * math.cos(dx * 0.85 - px * 0.4)
            slope_drop = (dist_norm ** 1.15) * ph + jag * (1.0 - dist_norm * 0.5)
            top_y = int(round(summit_y + max(0.0, slope_drop)))

            for y in range(max(1, top_y), H - 3):
                depth = y - top_y
                alt_frac = 1.0 - ((y - summit_y) / max(1.0, float(ph)))
                rx = px + skew * ((y - summit_y) / max(1, ph)) * 3.0 + 1.4 * math.sin((y - summit_y) * 0.55 + px)
                is_sunlit = (px + dx) <= rx

                gully = math.sin(dx * 0.6 + px * 0.3) * 0.14
                snow_threshold = (0.38 if is_sunlit else 0.46) + gully

                if depth == 0:
                    # Crisp dark-ink or snow-white pixel outline
                    edge_col = (255, 255, 255, 255) if alt_frac > 0.35 else (30, 41, 59, 255)
                    set_px(c, x, y, edge_col)
                    continue

                if alt_frac > snow_threshold:
                    if is_sunlit:
                        col = (255, 255, 255, 255) if hash2d(x, y, 2) > 0.2 else (224, 242, 254, 255)
                    else:
                        col = (186, 230, 253, 255) if abs((px + dx) - rx) <= 1.5 else (125, 211, 252, 250)
                else:
                    striation = ((x + y * 2) % 5 == 0)
                    if is_sunlit:
                        col = (148, 163, 184, 255) if striation else (100, 116, 139, 255)
                        if abs((px + dx) - rx) <= 1.3:
                            col = (203, 213, 225, 255)
                    else:
                        col = (30, 41, 59, 255) if striation else (51, 65, 85, 255)

                set_px(c, x, y, col)

    # Sparkling waterfall at x=155 cascading into an alpine lake
    for wy in range(13, H - 3):
        wx = 155 + (1 if wy > 19 else 0)
        set_px(c, wx, wy, (224, 242, 254, 255))
        set_px(c, wx + 1, wy, (56, 189, 248, 255))
    for lx in range(146, 166):
        set_px(c, lx, H - 4, (125, 211, 252, 255))
        set_px(c, lx, H - 3, (14, 165, 233, 255))
        set_px(c, lx, H - 2, (2, 132, 199, 255))
        set_px(c, lx, H - 1, (12, 74, 110, 255))

    # Crisp emerald spruce treeline along the mountain base
    for tx in range(4, W, 7):
        if 144 <= tx <= 167:
            continue
        tree_h = 4 + int(hash2d(tx, 0, 31) * 6)
        base_y = H - 3
        for ty in range(base_y - tree_h, base_y):
            row_from_top = ty - (base_y - tree_h)
            half_w = max(0, int((row_from_top + 1) * 0.52))
            for dx in range(-half_w, half_w + 1):
                col = (16, 185, 129, 255) if dx < 0 else ((5, 150, 105, 255) if dx == 0 else (6, 78, 59, 255))
                set_px(c, tx + dx, ty, col)

    # Alpine stone & moss trail floor (bottom 3px)
    for x in range(W):
        if 146 <= x <= 165:
            continue
        n = hash2d(x, 30, 99)
        set_px(c, x, H - 3, (52, 211, 153, 255) if n > 0.45 else (148, 163, 184, 255))
        set_px(c, x, H - 2, (71, 85, 105, 255) if n > 0.5 else (51, 65, 85, 255))
        set_px(c, x, H - 1, (30, 41, 59, 255))

    return c


# ---------------------------------------------------------------------------
# 2. FOREST THEME (Lush emerald woodland on transparent sky)
# ---------------------------------------------------------------------------
def build_forest():
    c = new_canvas()

    # Background silhouette pines
    for tx in range(6, W, 16):
        th = 10 + int(hash2d(tx, 1, 14) * 8)
        top_y = H - 3 - th
        for y in range(top_y, H - 3):
            rel = y - top_y
            hw = int(1 + rel * 0.38)
            for dx in range(-hw, hw + 1):
                set_px(c, tx + dx, y, (6, 78, 59, 210))

    # Foreground trees: varied pines and spreading oaks with rich highlights
    for i, tx in enumerate(range(14, W, 28)):
        kind = "pine" if (i % 2 == 1) else "oak"
        top_y = 3 + (i * 3) % 6
        trunk_w = 3 if kind == "pine" else 4

        for y in range(top_y + 5, H - 3):
            for dx in range(trunk_w):
                bark = (146, 64, 14, 255) if dx == 0 else ((120, 53, 15, 255) if dx < trunk_w - 1 else (69, 26, 3, 255))
                set_px(c, tx + dx, y, bark)

        cx = tx + trunk_w // 2
        if kind == "pine":
            for y in range(top_y, H - 6):
                rel = y - top_y
                tier = rel % 5
                hw = int(1 + rel * 0.46 + (1 if tier >= 3 else 0))
                for dx in range(-hw, hw + 1):
                    if dx < -hw * 0.2:
                        leaf = (110, 231, 183, 255) if tier == 0 else (52, 211, 153, 255)
                    elif dx > hw * 0.3:
                        leaf = (6, 78, 59, 255)
                    else:
                        leaf = (16, 185, 129, 255)
                    set_px(c, cx + dx, y, leaf)
        else:
            tiers = [(top_y + 2, 8, 4), (top_y + 6, 11, 5), (top_y + 9, 9, 4)]
            for cy, rx, ry in tiers:
                for dy in range(-ry, ry + 1):
                    for dx in range(-rx, rx + 1):
                        dist = (dx * dx) / float(rx * rx) + (dy * dy) / float(ry * ry)
                        if dist <= 1.0 + (hash2d(cx + dx, cy + dy, 5) - 0.5) * 0.3:
                            if dy < -ry * 0.3 or (dx < -rx * 0.25 and dy < 0):
                                leaf = (134, 239, 172, 255) if hash2d(cx + dx, cy + dy, 6) > 0.4 else (74, 222, 128, 255)
                            elif dy > ry * 0.35:
                                leaf = (20, 83, 45, 255)
                            else:
                                leaf = (34, 197, 94, 255) if hash2d(cx + dx, cy + dy, 8) > 0.35 else (22, 163, 74, 255)
                            set_px(c, cx + dx, cy + dy, leaf)

    # Lush emerald turf floor & red toadstool mushrooms
    for x in range(W):
        n = hash2d(x, 28, 77)
        if n > 0.55:
            set_px(c, x, H - 4, (134, 239, 172, 255))
        set_px(c, x, H - 3, (74, 222, 128, 255) if n > 0.3 else (34, 197, 94, 255))
        set_px(c, x, H - 2, (22, 163, 74, 255))
        set_px(c, x, H - 1, (20, 83, 45, 255))

    for mx in (28, 86, 152, 218, 284, 356, 428):
        set_px(c, mx, H - 4, (254, 243, 199, 255))
        set_px(c, mx + 1, H - 4, (254, 243, 199, 255))
        for dx in range(-1, 3):
            set_px(c, mx + dx, H - 5, (239, 68, 68, 255))
        set_px(c, mx, H - 6, (239, 68, 68, 255))
        set_px(c, mx + 1, H - 6, (255, 255, 255, 255))
        set_px(c, mx - 1, H - 5, (255, 255, 255, 255))

    return c


# ---------------------------------------------------------------------------
# 3. SPACE THEME (Crisp planets, galaxy, moon & stars on transparent sky)
# ---------------------------------------------------------------------------
def build_space():
    c = new_canvas()

    # Soft localized nebula clouds (leaving most of the sky clean & transparent)
    nebulae = [
        (110, 12, 34, 8, (168, 85, 247, 95)),
        (260, 11, 38, 9, (14, 165, 233, 90)),
        (395, 12, 32, 8, (236, 72, 153, 90)),
    ]
    for ncx, ncy, nrx, nry, ncol in nebulae:
        for dy in range(-nry, nry + 1):
            for dx in range(-nrx, nrx + 1):
                d = (dx * dx) / float(nrx * nrx) + (dy * dy) / float(nry * nry)
                if d < 1.0:
                    a = int(ncol[3] * ((1.0 - d) ** 1.5))
                    blend_px(c, ncx + dx, ncy + dy, (ncol[0], ncol[1], ncol[2], a))

    # Crisp 4-point stars & starfield
    for i in range(95):
        sx = int(hash2d(i, 1, 101) * W)
        sy = int(hash2d(i, 2, 101) * (H - 7)) + 2
        bright = hash2d(i, 3, 101)
        if bright > 0.84:
            set_px(c, sx, sy, (255, 255, 255, 255))
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                blend_px(c, sx + dx, sy + dy, (253, 224, 71, 220))
        elif bright > 0.5:
            set_px(c, sx, sy, (125, 211, 252, 245))
        else:
            set_px(c, sx, sy, (226, 232, 240, 200))

    # Crescent Moon at x=58, y=11
    mcx, mcy, mr = 58, 11, 6.5
    for dy in range(-8, 9):
        for dx in range(-8, 9):
            if dx * dx + dy * dy <= mr * mr:
                if (dx - 3.0) ** 2 + (dy + 1.2) ** 2 > (mr * 0.78) ** 2:
                    set_px(c, mcx + dx, mcy + dy, (254, 249, 195, 255))

    # Spiral Galaxy at x=165, y=10
    gcx, gcy = 165, 10
    for step in range(65):
        ang = step * 0.21
        r = step * 0.13
        for arm in (0.0, math.pi):
            gx = int(round(gcx + math.cos(ang + arm) * r * 1.6))
            gy = int(round(gcy + math.sin(ang + arm) * r * 0.7))
            set_px(c, gx, gy, (244, 114, 182, 245) if r > 2.8 else (254, 240, 138, 255))

    # Ringed Saturn at x=292, y=12
    scx, scy, sr = 292, 12, 6.0
    for rx_off in range(-14, 15):
        for ry_off in range(-6, 7):
            u = rx_off * 0.92 + ry_off * 0.38
            v = -rx_off * 0.38 + ry_off * 0.92
            ell = (u / 13.5) ** 2 + (v / 3.2) ** 2
            if 0.42 <= ell <= 1.0 and v < 0:
                set_px(c, scx + rx_off, scy + ry_off, (253, 224, 71, 245) if ell < 0.72 else (196, 181, 253, 235))

    for dy in range(-7, 8):
        for dx in range(-7, 8):
            if dx * dx + dy * dy <= sr * sr:
                band = int((dy + 7) // 2) % 3
                pcol = (251, 191, 36, 255) if band == 0 else ((217, 119, 6, 255) if band == 1 else (245, 158, 11, 255))
                set_px(c, scx + dx, scy + dy, pcol)

    for rx_off in range(-14, 15):
        for ry_off in range(-6, 7):
            u = rx_off * 0.92 + ry_off * 0.38
            v = -rx_off * 0.38 + ry_off * 0.92
            ell = (u / 13.5) ** 2 + (v / 3.2) ** 2
            if 0.42 <= ell <= 1.0 and v >= 0:
                set_px(c, scx + rx_off, scy + ry_off, (254, 243, 199, 255) if ell < 0.72 else (216, 180, 254, 245))

    # Blue-and-green Earth globe at x=412, y=11
    ecx, ecy, er = 412, 11, 5.5
    for dy in range(-6, 7):
        for dx in range(-6, 7):
            if dx * dx + dy * dy <= er * er:
                is_land = math.sin(dx * 0.55 + dy * 0.35) > 0.15
                set_px(c, ecx + dx, ecy + dy, (52, 211, 153, 255) if is_land else (56, 189, 248, 255))

    # Lunar crater ridge floor (bottom 4px)
    for x in range(W):
        theta = (x / W) * 2.0 * math.pi
        ridge = int(round(1.0 * math.sin(theta * 8.0) + 0.6 * math.cos(theta * 18.0)))
        top_y = H - 3 - max(0, ridge)
        for y in range(top_y, H):
            set_px(c, x, y, (165, 180, 252, 255) if y == top_y else ((99, 102, 241, 255) if y < H - 1 else (49, 46, 129, 255)))

    return c


# ---------------------------------------------------------------------------
# 4. BEACH THEME (Tropical ocean, sunset sun, palms & golden sand)
# ---------------------------------------------------------------------------
def build_beach():
    c = new_canvas()

    # Setting golden sun at x=108
    sun_x, sun_y, sun_r = 108, H - 8, 7.0
    for dy in range(-8, 2):
        for dx in range(-8, 9):
            if dx * dx + dy * dy <= sun_r * sun_r:
                scol = (254, 240, 138, 255) if dx * dx + dy * dy <= 18 else (251, 146, 60, 255)
                set_px(c, sun_x + dx, sun_y + dy, scol)

    #Lush green tropical island at x=230
    for dx in range(-24, 25):
        ih = int(round(6.5 * max(0.0, 1.0 - (abs(dx) / 24.0) ** 1.25)))
        for y in range(H - 8 - ih, H - 8):
            set_px(c, 230 + dx, y, (16, 185, 129, 255) if y == H - 8 - ih else (5, 150, 105, 255))

    # White sailboat at x=356
    for dx in range(-4, 5):
        set_px(c, 356 + dx, H - 8, (180, 83, 9, 255))
    for sy in range(H - 15, H - 8):
        w = (sy - (H - 15)) // 2 + 1
        for dx in range(w):
            set_px(c, 356 + dx, sy, (255, 255, 255, 255))

    # Vibrant turquoise ocean band (H-8 to H-4)
    for y in range(H - 8, H - 3):
        ocol = (14, 165, 233, 255) if y < H - 6 else (34, 211, 238, 255)
        for x in range(W):
            set_px(c, x, y, ocol)
            if abs(x - sun_x) <= (6 - (y - (H - 8))) and (x + y) % 2 == 0:
                set_px(c, x, y, (254, 240, 138, 255))
            if y == H - 4 and (x + int(math.sin(x * 0.22) * 3)) % 4 != 0:
                set_px(c, x, y, (255, 255, 255, 255))

    # Golden sand shoreline (bottom 3px)
    for x in range(W):
        n = hash2d(x, 29, 55)
        set_px(c, x, H - 3, (253, 224, 71, 255) if n > 0.3 else (251, 191, 36, 255))
        set_px(c, x, H - 2, (245, 158, 11, 255))
        set_px(c, x, H - 1, (217, 119, 6, 255))

    for sx in (36, 148, 268, 396):
        set_px(c, sx, H - 2, (244, 63, 94, 255))
        set_px(c, sx + 1, H - 2, (251, 113, 133, 255))

    # Curved tropical palm trees
    for px, lean, trunk_h in ((44, 1, 16), (58, -1, 12), (168, -1, 15), (304, 1, 16), (432, -1, 15)):
        for h_step in range(trunk_h):
            ty = H - 3 - h_step
            tx = px + int(round(lean * (h_step / 4.2) ** 1.45))
            set_px(c, tx, ty, (180, 83, 9, 255))
            set_px(c, tx + 1, ty, (120, 53, 15, 255))
        top_x = px + int(round(lean * ((trunk_h - 1) / 4.2) ** 1.45))
        top_y = H - 2 - trunk_h
        for angle in (-2.4, -1.7, -0.9, -0.2, 0.4, 1.1, 1.9, 2.5):
            for r in range(1, 9):
                fx = int(round(top_x + math.cos(angle) * r * 1.15))
                fy = int(round(top_y - math.sin(abs(angle)) * r * 0.45 + (r * r) * 0.08))
                set_px(c, fx, fy, (74, 222, 128, 255) if r < 5 else (22, 163, 74, 255))

    return c


# ---------------------------------------------------------------------------
# 5. CASTLE THEME (Royal towers with blue roofs, battlements & banners)
# ---------------------------------------------------------------------------
def build_castle():
    c = new_canvas()

    for x in range(W):
        tx_local = x % 96
        in_tower = tx_local < 24
        in_merlon = (x % 16) < 10
        wall_top = 9 if in_tower else (15 if in_merlon else 19)

        # Conical royal-blue slate roof on top of each tower (y=2..8)
        if in_tower:
            center_t = 11.5
            for y in range(2, 9):
                half_w = (y - 1) * 1.65
                if abs(tx_local - center_t) <= half_w:
                    rcol = (59, 130, 246, 255) if tx_local < center_t else (29, 78, 216, 255)
                    set_px(c, x, y, rcol)
            if tx_local in (11, 12):
                set_px(c, x, 1, (250, 204, 21, 255))

        for y in range(wall_top, H):
            brick_row = y // 4
            brick_col = (x + (brick_row % 2) * 4) % 8
            is_mortar = (y % 4 == 0) or (brick_col == 0)
            if y == wall_top:
                scol = (214, 211, 209, 255)
            elif is_mortar:
                scol = (41, 37, 36, 255)
            else:
                shade = hash2d(x // 8, brick_row, 88)
                scol = (168, 162, 158, 255) if shade > 0.5 else (120, 113, 108, 255)
            set_px(c, x, y, scol)

        # Glowing arched window & crimson-gold royal banner
        if 9 <= tx_local <= 14:
            for y in range(12, 19):
                if y == 12 and (tx_local in (9, 14)):
                    continue
                set_px(c, x, y, (254, 240, 138, 255) if tx_local in (11, 12) else (245, 158, 11, 255))
        if 46 <= tx_local <= 50:
            for y in range(19, 27):
                set_px(c, x, y, (250, 204, 21, 255) if tx_local in (46, 50) or y == 26 else (220, 38, 38, 255))

    for x in range(W):
        set_px(c, x, H - 3, (168, 162, 158, 255))
        set_px(c, x, H - 2, (120, 113, 108, 255))
        set_px(c, x, H - 1, (68, 64, 60, 255))

    return c


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    asset_dir = os.path.join(root, "assets")
    os.makedirs(asset_dir, exist_ok=True)

    themes = {
        "mountain": build_mountain(),
        "forest": build_forest(),
        "space": build_space(),
        "beach": build_beach(),
        "castle": build_castle(),
    }
    for name, canvas in themes.items():
        out = os.path.join(asset_dir, f"theme-{name}.png")
        write_rgba_png(out, W, H, canvas)
        print(f"Wrote {out}")


if __name__ == "__main__":
    main()
