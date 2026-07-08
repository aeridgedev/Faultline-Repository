#!/usr/bin/env python3
"""Faultline terrain tileset generator (Part A — visual polish).

Produces one 16x16 PNG per terrain type into assets/tilesets/, named per
TerrainManager._tile_file(). TerrainManager._load_tile_png() picks them up
automatically (16x16 hard requirement, Nearest filter — enforced by the
.import files this project already ships / by Godot's default for the folder).

Palette is the FINAL approved per-layer family from the visual-polish brief:
    Crust  warm earth      soil #6b5842 clay #8a7050 stone #4a3d2a
    Mantle warming rock     rust #8f3b20 ochre #b06a2e grey #5a4a42
    Outer  hot / hazardous  magma #d9491f dark-iron #201512 scorch #5c1e12
    Inner  extreme          white-hot #f2d9c9 obsidian #140a0c deep-red #6e1013
    Hollow alien violet     shell #241a4a fog #a78bfa

Design pillars honoured:
  * 2-4 colours per tile, drawn from that layer's family.
  * base fill + seeded dither/noise (never flat single colour).
  * soft terrain (soil/clay) = organic blotchy noise;
    dense terrain (stone/ultra-dense/shell) = angular/crystalline + dark outline.
  * bedrock = darkest, near-black, diagonal hatch ("do not dig").
  * core_hollow_shell = violet-black crystalline, BRIGHTEST outline of any tile.

Run once; commit output + this script so palettes can be re-rolled.
    python tools/gen_tileset.py
"""
import os
import random
from PIL import Image

S = 16
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "tilesets")


def h(hexstr):
    hexstr = hexstr.lstrip("#")
    return (int(hexstr[0:2], 16), int(hexstr[2:4], 16), int(hexstr[4:6], 16), 255)


def shade(c, f):
    return (max(0, min(255, int(c[0] * f))),
            max(0, min(255, int(c[1] * f))),
            max(0, min(255, int(c[2] * f))), 255)


def mix(a, b, t):
    return (int(a[0] + (b[0] - a[0]) * t),
            int(a[1] + (b[1] - a[1]) * t),
            int(a[2] + (b[2] - a[2]) * t), 255)


# 4x4 Bayer matrix (0..15) for ordered dithering texture.
BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def base_texture(px, rng, base, dark, light, dither=0.20):
    """Fill the tile interior with a dithered base + a soft top-left light band."""
    for y in range(S):
        for x in range(S):
            # top-left light source, bottom-right shadow
            d = (x + y) / (2.0 * (S - 1))          # 0 top-left .. 1 bottom-right
            c = mix(light, dark, d)
            c = mix(c, base, 0.55)                  # keep base dominant
            # ordered dither speckle so it never reads flat
            b = BAYER[y % 4][x % 4] / 15.0
            n = (rng.random() * 0.5 + b * 0.5)
            if n < dither:
                c = shade(c, 0.86)
            elif n > 1.0 - dither:
                c = shade(c, 1.14)
            px[x, y] = c


def blobs(px, rng, color, count, rmax=3):
    """Organic darker/lighter blotches for soft terrain."""
    for _ in range(count):
        cx = rng.randint(2, S - 3)
        cy = rng.randint(2, S - 3)
        r = rng.randint(1, rmax)
        for y in range(max(1, cy - r), min(S - 1, cy + r + 1)):
            for x in range(max(1, cx - r), min(S - 1, cx + r + 1)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + rng.randint(0, 1):
                    px[x, y] = color


def strata(px, rng, base, dark, light, bands=4):
    """Horizontal sedimentary layering."""
    step = S / bands
    for y in range(1, S - 1):
        band = int(y / step)
        c = light if band % 2 == 0 else base
        if y % max(2, int(step)) == 0:
            c = dark
        # jitter the seam so bands aren't ruler-straight
        for x in range(1, S - 1):
            cc = c
            if rng.random() < 0.15:
                cc = shade(c, 0.9 if rng.random() < 0.5 else 1.1)
            px[x, y] = cc


def facets(px, rng, dark, light, n=5):
    """Angular crystalline facet lines for hard terrain."""
    for _ in range(n):
        x0 = rng.randint(1, S - 2)
        y0 = rng.randint(1, S - 2)
        dx = rng.choice((-1, 1))
        dy = rng.choice((-1, 1))
        length = rng.randint(3, 7)
        col = light if rng.random() < 0.5 else dark
        x, y = x0, y0
        for _ in range(length):
            if 1 <= x < S - 1 and 1 <= y < S - 1:
                px[x, y] = col
            x += dx
            y += dy


def speckle(px, rng, colors, count):
    for _ in range(count):
        x = rng.randint(1, S - 2)
        y = rng.randint(1, S - 2)
        px[x, y] = rng.choice(colors)


def outline(px, color):
    for i in range(S):
        px[i, 0] = color
        px[i, S - 1] = color
        px[0, i] = color
        px[S - 1, i] = color


def catchlight(px, color):
    px[2, 2] = color
    px[3, 2] = color
    px[2, 3] = color


def diagonal_seams(px, seam, hot):
    """The two crossing molten diagonals used by core_hollow_shell."""
    for i in range(1, S - 1):
        px[i, i] = seam
        j = (S - 1) - i
        if 0 < j < S - 1:
            px[i, j] = seam
    for pt in ((7, 7), (8, 8), (4, 11), (11, 4)):
        px[pt] = hot


def make(name, seed, build):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    rng = random.Random(seed)
    build(px, rng)
    img.save(os.path.join(OUT, name + ".png"))
    return img


# ---- per-tile builders -----------------------------------------------------

def soil(px, rng):
    base, dark, light = h("6b5842"), h("4a3d2a"), h("8a7355")
    base_texture(px, rng, base, dark, light, dither=0.26)
    blobs(px, rng, shade(dark, 0.9), 6, rmax=2)      # pebbles / clumps
    blobs(px, rng, shade(light, 1.05), 3, rmax=1)    # dry grit
    outline(px, h("2e2416"))
    catchlight(px, shade(light, 1.1))


def clay(px, rng):
    base, dark, light = h("8a7050"), h("6b5842"), h("a08466")
    base_texture(px, rng, base, dark, light, dither=0.18)
    strata(px, rng, base, dark, light, bands=5)
    blobs(px, rng, dark, 3, rmax=2)
    outline(px, h("3a2e1e"))
    catchlight(px, light)


def limestone(px, rng):
    base, dark, light = h("4a3d2a"), h("2f2718"), h("6f5f42")
    base_texture(px, rng, base, dark, light, dither=0.16)
    strata(px, rng, base, dark, light, bands=4)      # strong sedimentary strata
    outline(px, h("1f1810"))
    catchlight(px, shade(light, 1.15))


def rock(px, rng):
    base, dark, light = h("5a4a42"), h("3a2f2a"), h("786257")
    base_texture(px, rng, base, dark, light, dither=0.22)
    facets(px, rng, shade(dark, 0.85), light, n=4)
    blobs(px, rng, shade(dark, 0.85), 2, rmax=2)
    outline(px, h("241d19"))
    catchlight(px, shade(light, 1.1))


def basalt(px, rng):
    base, dark, light = h("42342e"), h("241b18"), h("59463d")
    base_texture(px, rng, base, dark, light, dither=0.14)
    facets(px, rng, h("2a211d"), h("8f3b20"), n=6)   # faint rust hairline cracks
    outline(px, h("140f0d"))
    catchlight(px, light)


def granite(px, rng):
    base, dark, light = h("5a4a42"), h("372c26"), h("7a6455")
    base_texture(px, rng, base, dark, light, dither=0.12)
    speckle(px, rng, [h("b06a2e"), h("b06a2e"), h("cdbfae"), h("2c221d")], 22)
    facets(px, rng, dark, light, n=2)
    outline(px, h("1e1712"))
    catchlight(px, h("cdbfae"))


def obsidian(px, rng):
    base, dark, light = h("201512"), h("120a09"), h("3a221c")
    base_texture(px, rng, base, dark, light, dither=0.10)
    facets(px, rng, h("0d0706"), h("d9491f"), n=5)   # magma glints in the glass
    speckle(px, rng, [h("ff8a4d"), h("d9491f")], 4)
    outline(px, h("0a0605"))
    px[2, 2] = h("ffb489"); px[5, 1] = h("ff8a4d"); px[1, 5] = h("d9491f")


def iron_formation(px, rng):
    base, dark, light = h("5c1e12"), h("2a1109"), h("8f3b20")
    base_texture(px, rng, base, dark, light, dither=0.12)
    strata(px, rng, base, dark, light, bands=5)
    for _ in range(3):                                # bright magma veins
        y = rng.randint(3, S - 4)
        for x in range(1, S - 1):
            if rng.random() < 0.7:
                px[x, y] = h("d9491f") if rng.random() < 0.5 else h("ff8a4d")
    outline(px, h("180a06"))
    catchlight(px, h("f0a070"))


def dense_crystal(px, rng):
    base, dark, light = h("5c1e12"), h("2a1109"), h("d9491f")
    base_texture(px, rng, base, dark, light, dither=0.10)
    facets(px, rng, dark, h("ffb080"), n=8)          # sharp magma facets
    speckle(px, rng, [h("ffd9b0"), h("ff8a4d")], 6)
    outline(px, h("140804"))
    px[2, 2] = h("ffe6cc"); px[3, 2] = h("ffb080"); px[2, 3] = h("ff8a4d")


def ultra_dense(px, rng):
    base, dark, light = h("140a0c"), h("080405"), h("2a1013")
    base_texture(px, rng, base, dark, light, dither=0.10)
    # cooling-magma glowing cracks: deep red core, white-hot centres
    for _ in range(4):
        x0 = rng.randint(2, S - 3); y0 = rng.randint(2, S - 3)
        dx = rng.choice((-1, 1)); dy = rng.choice((-1, 1))
        x, y = x0, y0
        for k in range(rng.randint(3, 6)):
            if 1 <= x < S - 1 and 1 <= y < S - 1:
                px[x, y] = h("f2d9c9") if k == 0 else h("6e1013")
            x += dx; y += dy
    speckle(px, rng, [h("6e1013"), h("6e1013"), h("f2d9c9")], 6)
    outline(px, h("060304"))
    px[2, 2] = h("f2d9c9")


def bedrock(px, rng):
    base, dark, light = h("0a0a0e"), h("050508"), h("16161c")
    base_texture(px, rng, base, dark, light, dither=0.08)
    for y in range(1, S - 1):                         # diagonal "do not dig" hatch
        for x in range(1, S - 1):
            if (x + y) % 4 == 0:
                px[x, y] = h("16161c")
    outline(px, h("030305"))


def core_hollow_shell(px, rng):
    base, dark, light = h("241a4a"), h("150f2e"), h("3d2f6e")
    base_texture(px, rng, base, dark, light, dither=0.10)
    facets(px, rng, h("150f2e"), h("6f57c0"), n=6)    # violet crystalline facets
    diagonal_seams(px, h("5b46b0"), h("c9b6ff"))      # molten violet energy seams
    outline(px, h("8a5cff"))                          # BRIGHTEST outline of any tile
    px[2, 2] = h("c9b6ff")


TILES = [
    ("soil", 101, soil),
    ("clay", 102, clay),
    ("limestone", 103, limestone),
    ("rock", 104, rock),
    ("basalt", 105, basalt),
    ("granite", 106, granite),
    ("obsidian", 107, obsidian),
    ("iron_formation", 108, iron_formation),
    ("dense_crystal", 109, dense_crystal),
    ("ultra_dense", 110, ultra_dense),
    ("bedrock", 111, bedrock),
    ("core_hollow_shell", 112, core_hollow_shell),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGBA", (S * len(TILES), S), (30, 30, 30, 255))
    for i, (name, seed, fn) in enumerate(TILES):
        img = make(name, seed, fn)
        assert img.size == (S, S), name
        sheet.paste(img, (i * S, 0))
        print("wrote", name + ".png")
    # 8x contact sheet for eyeballing
    prev = sheet.resize((sheet.width * 8, sheet.height * 8), Image.NEAREST)
    prev.save(os.path.join(os.path.dirname(__file__), "_preview_tileset.png"))
    print("wrote tools/_preview_tileset.png (%dx%d)" % prev.size)


if __name__ == "__main__":
    main()
