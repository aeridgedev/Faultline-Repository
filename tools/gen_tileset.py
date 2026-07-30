#!/usr/bin/env python3
"""Faultline terrain tileset generator.

Writes one PNG per terrain type into ``assets/tilesets/`` as a HORIZONTAL STRIP
of N 16x16 art variants (image size = 16*N x 16). Filenames match
``TerrainManager._tile_file()``; the painters here are a deliberate 1:1 mirror of
``TerrainManager._make_tile_codegen()`` so the imported art and the procedural
fallback look the same.

Why a strip: a single stamped tile makes a solid mass of one terrain read as an
obvious 16px grid. ``TerrainManager.place_tile()`` picks a variant by hashing the
cell coordinate, so identical neighbours get different art. This is flat per-cell
variant selection, NOT autotiling -- there are no terrain sets and no neighbour
lookups anywhere in the pipeline.

Rules the art must keep (see the de-gridding notes in TerrainManager.gd):
  * No 1px dark perimeter on the ten natural fill terrains -- outlining every
    cell draws the grid in ink. BEDROCK and CORE_HOLLOW_SHELL keep theirs on
    purpose: those two are engineered plates, not fill.
  * No feature pinned to a constant coordinate (the old ``set_pixel(2, 2, HI)``
    catch-light) and no per-tile gradient -- both repeat into a visible lattice.
  * Modulo patterns must have a period that DIVIDES 16 (2/4/8/16), otherwise the
    pattern jumps at every cell boundary and re-draws the grid.

Dependencies: Python 3 standard library only (``zlib`` + ``struct`` write a valid
PNG). Pillow is NOT required and is not used even when installed.

Usage:
    python tools/gen_tileset.py                 # write PNGs + drop stale .import
    python tools/gen_tileset.py --keep-imports  # write PNGs only
    python tools/gen_tileset.py --out DIR       # write somewhere else

Stale ``.import`` files MUST go when the PNGs change shape: ``.import`` is
gitignored but its ``.godot/imported/*.ctex`` payload is not regenerated unless
Godot sees the import as missing, and ``ResourceLoader.exists()`` happily
resolves a deleted PNG through a leftover ``.import`` to the OLD texture data.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
import zlib

S = 16  # one cell is S x S

# --------------------------------------------------------------------------
# tiny stdlib PNG writer
# --------------------------------------------------------------------------


def _chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_png(path: str, width: int, height: int, pixels: list[list[tuple]]) -> None:
    """pixels[y][x] = (r, g, b, a) with 0..255 components. 8-bit RGBA, no filter."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        for x in range(width):
            r, g, b, a = pixels[y][x]
            raw += bytes((r, g, b, a))
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _chunk(b"IEND", b"")
    )
    with open(path, "wb") as fh:
        fh.write(png)


def read_png_size(path: str) -> tuple[int, int]:
    """Re-read a written file's IHDR so the generator verifies its own output."""
    with open(path, "rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise ValueError("%s is not a PNG" % path)
    return struct.unpack(">II", head[16:24])


# --------------------------------------------------------------------------
# canvas + helpers (mirrors of the GDScript ones)
# --------------------------------------------------------------------------


def C(r: float, g: float, b: float) -> tuple:
    """Godot Color(float, float, float) -> opaque 8-bit RGBA."""
    return (
        max(0, min(255, int(round(r * 255.0)))),
        max(0, min(255, int(round(g * 255.0)))),
        max(0, min(255, int(round(b * 255.0)))),
        255,
    )


def pxhash(x: int, y: int, salt: int) -> int:
    """Mirror of TerrainManager._pxhash(). Every intermediate is masked
    non-negative so GDScript and Python produce identical values."""
    h = ((x * 374761393) + (y * 668265263) + (salt * 2654435761)) & 0x7FFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
    return (h ^ (h >> 16)) & 0x7FFFFFFF


class Cell:
    """A single variant band of the strip; clamps writes so a feature near x=15
    cannot bleed into the next variant (mirror of TerrainManager._px)."""

    def __init__(self, pixels: list[list[tuple]], ox: int) -> None:
        self.pixels = pixels
        self.ox = ox

    def px(self, x: int, y: int, c: tuple) -> None:
        if x < 0 or y < 0 or x >= S or y >= S:
            return
        self.pixels[y][self.ox + x] = c

    def run(self, x: int, y: int, length: int, c: tuple) -> None:
        for i in range(length):
            self.px(x + i, y, c)


# --------------------------------------------------------------------------
# painters -- 1:1 with TerrainManager._tile_*()
# --------------------------------------------------------------------------


def tile_soil(cell: Cell, v: int) -> None:
    B, M, D, LT = C(0.44, 0.27, 0.11), C(0.52, 0.34, 0.16), C(0.30, 0.17, 0.06), C(0.60, 0.41, 0.20)
    PB, DK = C(0.38, 0.25, 0.12), C(0.20, 0.11, 0.03)
    salt = 11 + v * 7
    for y in range(S):
        for x in range(S):
            r = pxhash(x, y, salt) % 100
            c = B
            if r < 16:
                c = M
            elif r < 26:
                c = D
            elif r < 30:
                c = LT
            cell.px(x, y, c)
    pebbles = [
        [(3, 4), (10, 9), (6, 12)],
        [(12, 3), (2, 8), (8, 13)],
        [(5, 2), (13, 10), (9, 5)],
    ]
    for px_, py in pebbles[v]:
        cell.px(px_, py, LT)
        cell.px(px_ + 1, py, PB)
        cell.px(px_, py + 1, PB)
        cell.px(px_ + 1, py + 1, DK)


def tile_clay(cell: Cell, v: int) -> None:
    B, L, D = C(0.52, 0.27, 0.12), C(0.60, 0.34, 0.17), C(0.42, 0.21, 0.09)
    BD, DK, LP = C(0.47, 0.24, 0.10), C(0.31, 0.14, 0.05), C(0.66, 0.40, 0.22)
    salt = 31 + v * 7
    for y in range(S):
        for x in range(S):
            r = pxhash(x, y, salt) % 100
            c = BD if y % 8 == 0 else B
            if r < 13:
                c = L
            elif r < 22:
                c = D
            elif r < 26:
                c = LP
            cell.px(x, y, c)
    cracks = [(3, 3, 9), (9, 7, 13), (13, 2, 7)]
    row, x0, x1 = cracks[v]
    for x in range(x0, x1 + 1):
        cell.px(x, row, DK)
        if x % 3 == 0:
            cell.px(x, row + 1, LP)


def tile_limestone(cell: Cell, v: int) -> None:
    B, L, D = C(0.68, 0.63, 0.50), C(0.76, 0.72, 0.60), C(0.54, 0.50, 0.38)
    CH, SD = C(0.84, 0.81, 0.71), C(0.46, 0.42, 0.32)
    salt = 53 + v * 7
    for y in range(S):
        for x in range(S):
            c = B
            if y % 8 == 0:
                c = D
            elif y % 8 == 1:
                c = L
            r = pxhash(x, y, salt) % 100
            if r < 10:
                c = CH
            elif r < 16:
                c = SD
            cell.px(x, y, c)
    light = [
        [(4, 6), (5, 6), (11, 10)],
        [(10, 5), (11, 5), (3, 12)],
        [(7, 11), (8, 11), (13, 6)],
    ]
    dark = [
        [(9, 3), (13, 13)],
        [(6, 9), (14, 2)],
        [(2, 5), (10, 14)],
    ]
    for x, y in light[v]:
        cell.px(x, y, CH)
    for x, y in dark[v]:
        cell.px(x, y, SD)


def tile_rock(cell: Cell, v: int) -> None:
    B, M, SH = C(0.44, 0.44, 0.47), C(0.52, 0.52, 0.55), C(0.34, 0.34, 0.37)
    CK, LT = C(0.22, 0.22, 0.24), C(0.62, 0.62, 0.66)
    salt = 71 + v * 7
    for y in range(S):
        for x in range(S):
            r = pxhash(x, y, salt) % 100
            c = B
            if r < 18:
                c = M
            elif r < 30:
                c = SH
            elif r < 34:
                c = LT
            cell.px(x, y, c)
    cracks = [
        [[(2, 3), (3, 4), (4, 4), (5, 5), (6, 6), (7, 6), (8, 7), (9, 8), (10, 8)]],
        [
            [(12, 2), (11, 3), (11, 4), (10, 5), (9, 6), (9, 7), (8, 8), (7, 9)],
            [(2, 11), (3, 12), (4, 12), (5, 13)],
        ],
        [
            [(1, 8), (2, 8), (3, 9), (4, 10), (5, 10), (6, 11), (7, 12)],
            [(10, 2), (11, 3), (12, 3), (13, 4)],
        ],
    ]
    for line in cracks[v]:
        for i, (x, y) in enumerate(line):
            cell.px(x, y, CK)
            if i % 3 == 0:
                cell.px(x, y - 1, LT)


def tile_basalt(cell: Cell, v: int) -> None:
    B, M, CK, LT = C(0.12, 0.14, 0.18), C(0.16, 0.19, 0.24), C(0.07, 0.08, 0.11), C(0.23, 0.27, 0.33)
    salt = 97 + v * 7
    for y in range(S):
        for x in range(S):
            r = pxhash(x, y, salt) % 100
            c = B
            if r < 14:
                c = M
            elif r < 20:
                c = CK
            elif r < 23:
                c = LT
            cell.px(x, y, c)
    columns = [[3, 10], [6, 13], [2, 8, 13]]
    for cx in columns[v]:
        for y in range(S):
            jx = cx + (pxhash(cx, y, salt) % 3) - 1
            cell.px(jx, y, CK)
            if pxhash(cx, y, salt + 1) % 2 == 0:
                cell.px(jx + 1, y, LT)
    rows = [[7], [4, 11], [9]]
    for cy in rows[v]:
        for x in range(S):
            jy = cy + (pxhash(x, cy, salt + 2) % 3) - 1
            cell.px(x, jy, CK)


def tile_granite(cell: Cell, v: int) -> None:
    B, LT = C(0.38, 0.37, 0.37), C(0.46, 0.45, 0.46)
    PK, WH, DK = C(0.58, 0.38, 0.36), C(0.74, 0.74, 0.75), C(0.19, 0.18, 0.19)
    salt = 131 + v * 7
    for y in range(S):
        for x in range(S):
            r = pxhash(x, y, salt) % 100
            c = B
            if r < 9:
                c = PK
            elif r < 17:
                c = WH
            elif r < 26:
                c = DK
            elif r < 40:
                c = LT
            cell.px(x, y, c)
    for y in range(S):
        for x in range(S):
            r = pxhash(x, y, salt) % 100
            if r < 9 and pxhash(x, y, salt + 2) % 2 == 0:
                cell.px(x + 1, y, PK)
            elif 9 <= r < 17 and pxhash(x, y, salt + 3) % 3 == 0:
                cell.px(x, y + 1, WH)


def tile_obsidian(cell: Cell, v: int) -> None:
    B, PU, SH = C(0.05, 0.04, 0.08), C(0.11, 0.07, 0.18), C(0.20, 0.12, 0.33)
    HI, DK = C(0.52, 0.45, 0.76), C(0.02, 0.02, 0.04)
    salt = 157 + v * 7
    for y in range(S):
        for x in range(S):
            r = pxhash(x, y, salt) % 100
            c = B
            if r < 8:
                c = PU
            elif r < 12:
                c = DK
            cell.px(x, y, c)
    arcs = [
        [[(3, 10), (4, 9), (5, 8), (6, 8), (7, 7), (8, 7), (9, 8), (10, 9)]],
        [
            [(10, 3), (11, 4), (12, 5), (12, 6), (11, 7), (10, 8), (9, 9)],
            [(2, 3), (3, 2), (4, 2), (5, 3)],
        ],
        [
            [(6, 13), (7, 12), (8, 12), (9, 11), (10, 10), (11, 10)],
            [(1, 7), (2, 6), (3, 6), (4, 5), (5, 5)],
        ],
    ]
    for arc in arcs[v]:
        for i, (x, y) in enumerate(arc):
            cell.px(x, y, SH)
            cell.px(x, y + 1, PU)
            if i in (2, 3):
                cell.px(x, y, HI)


def tile_iron_formation(cell: Cell, v: int) -> None:
    B, OR, DK = C(0.32, 0.14, 0.06), C(0.45, 0.22, 0.08), C(0.21, 0.09, 0.03)
    MG, LM = C(0.35, 0.34, 0.36), C(0.47, 0.46, 0.50)
    salt = 181 + v * 7
    for y in range(S):
        for x in range(S):
            if y % 8 == 2:
                c = MG
            elif y % 8 == 3:
                c = LM
            else:
                r = pxhash(x, y, salt) % 100
                c = B
                if r < 16:
                    c = OR
                elif r < 24:
                    c = DK
            cell.px(x, y, c)
    breaks = [[5], [12], [2, 11]]
    for bx in breaks[v]:
        for by in (2, 3, 10, 11):
            cell.px(bx, by, OR)
    flecks = [
        [(9, 6), (3, 14)],
        [(4, 7), (13, 13)],
        [(8, 15), (14, 6)],
    ]
    for x, y in flecks[v]:
        cell.px(x, y, LM)


def tile_dense_crystal(cell: Cell, v: int) -> None:
    D, MD, LT = C(0.06, 0.17, 0.27), C(0.10, 0.28, 0.42), C(0.17, 0.44, 0.60)
    PU, WH = C(0.18, 0.16, 0.40), C(0.58, 0.86, 0.93)
    salt = 211 + v * 7
    for y in range(S):
        for x in range(S):
            r = pxhash(x, y, salt) % 100
            c = D
            if r < 18:
                c = MD
            elif r < 26:
                c = PU
            elif r < 30:
                c = LT
            cell.px(x, y, c)
    # Every variant has at least one facet running off a cell edge -- see the note
    # in TerrainManager._tile_dense_crystal().
    facets = [
        [
            [(3, 2, 5), (1, 3, 7), (0, 4, 8), (0, 5, 7), (1, 6, 5), (3, 7, 2)],
            [(10, 9, 6), (9, 10, 7), (9, 11, 6), (10, 12, 4)],
            [(4, 13, 5), (5, 14, 4), (5, 15, 4)],
        ],
        [
            [(2, 0, 5), (2, 1, 6), (3, 2, 5), (4, 3, 3)],
            [(9, 5, 5), (8, 6, 7), (8, 7, 6), (9, 8, 4), (10, 9, 2)],
            [(0, 11, 5), (1, 12, 4)],
        ],
        [
            [(6, 1, 5), (5, 2, 7), (5, 3, 6), (6, 4, 4), (7, 5, 2)],
            [(0, 8, 5), (0, 9, 6), (1, 10, 4), (2, 11, 2)],
            [(11, 7, 5), (11, 8, 5), (12, 9, 4)],
        ],
    ]
    for runs in facets[v]:
        for i, (rx, ry, rl) in enumerate(runs):
            cell.run(rx, ry, rl, LT)
            if i < 2:
                cell.px(rx, ry, WH)
            if i >= len(runs) - 2:
                cell.px(rx + rl - 1, ry, PU)


def tile_ultra_dense(cell: Cell, v: int) -> None:
    B, M, DK = C(0.06, 0.05, 0.04), C(0.09, 0.08, 0.06), C(0.03, 0.03, 0.03)
    GD, HI = C(0.26, 0.20, 0.07), C(0.42, 0.33, 0.11)
    salt = 241 + v * 7
    for y in range(S):
        for x in range(S):
            r = pxhash(x, y, salt) % 100
            c = B
            if r < 20:
                c = M
            elif r < 28:
                c = DK
            cell.px(x, y, c)
    veins = [
        [[(3, 11), (4, 10), (5, 10), (6, 9), (7, 9)], [(11, 3), (12, 4), (13, 4)]],
        [[(2, 4), (3, 4), (4, 5), (5, 5), (6, 6)], [(9, 12), (10, 12), (11, 11)]],
        [[(7, 2), (8, 3), (9, 3), (10, 4)], [(3, 13), (4, 13), (5, 12)], [(13, 8), (13, 9)]],
    ]
    for vein in veins[v]:
        for i, (x, y) in enumerate(vein):
            cell.px(x, y, HI if i == 1 else GD)


def tile_bedrock(cell: Cell, v: int) -> None:
    # KEEPS its 1px plate perimeter on purpose -- engineered plating, not fill.
    K, B, G = C(0.02, 0.02, 0.03), C(0.08, 0.07, 0.11), C(0.13, 0.12, 0.17)
    HL, SC = C(0.16, 0.15, 0.21), C(0.10, 0.09, 0.13)
    for y in range(S):
        for x in range(S):
            seam = (x % 8 == 0 or y % 8 == 0) if v == 0 else (x % 8 == 4 or y % 8 == 4)
            rivet = (x % 8 == 1 and y % 8 == 1) if v == 0 else (x % 8 == 5 and y % 8 == 5)
            c = B
            if x == 0 or y == 0 or x == S - 1 or y == S - 1:
                c = K
            elif seam:
                c = G
            elif rivet:
                c = HL
            cell.px(x, y, c)
    scuffs = [
        [(10, 11), (11, 11), (12, 12)],
        [(3, 11), (4, 10), (5, 9), (11, 4), (12, 5)],
    ]
    for x, y in scuffs[v]:
        cell.px(x, y, SC)


def tile_core_hollow_shell(cell: Cell, v: int) -> None:
    # KEEPS its 1px plate perimeter on purpose -- armoured shell, not fill.
    K, B, M = C(0.01, 0.02, 0.03), C(0.04, 0.06, 0.09), C(0.07, 0.10, 0.15)
    PL, SM, HI = C(0.11, 0.15, 0.22), C(0.10, 0.55, 0.62), C(0.55, 0.95, 1.00)
    for y in range(S):
        for x in range(S):
            speckle = ((x + y * 2) % 8 == 0) if v == 0 else ((x * 2 + y) % 8 == 0)
            c = B
            if x == 0 or y == 0 or x == S - 1 or y == S - 1:
                c = K
            elif speckle:
                c = M
            cell.px(x, y, c)
    for i in range(1, S - 1):
        cell.px(i, 1, PL)
        cell.px(1, i, PL)
    if v == 0:
        for i in range(1, S - 1):
            cell.px(i, i, SM)
            j = (S - 1) - i
            if 0 < j < S - 1:
                cell.px(i, j, SM)
        for x, y in ((7, 7), (8, 8), (4, 11), (11, 4)):
            cell.px(x, y, HI)
    else:
        for i in range(1, S - 1):
            cell.px(8, i, SM)
            cell.px(i, 8, SM)
        for x, y in ((8, 8), (8, 3), (3, 8), (13, 8), (8, 13)):
            cell.px(x, y, HI)


# name -> (painter, variant count). Names MUST match TerrainManager._tile_file().
TERRAINS = [
    ("soil", tile_soil, 3),
    ("clay", tile_clay, 3),
    ("limestone", tile_limestone, 3),
    ("rock", tile_rock, 3),
    ("basalt", tile_basalt, 3),
    ("granite", tile_granite, 3),
    ("obsidian", tile_obsidian, 3),
    ("iron_formation", tile_iron_formation, 3),
    ("dense_crystal", tile_dense_crystal, 3),
    ("ultra_dense", tile_ultra_dense, 3),
    ("bedrock", tile_bedrock, 2),
    ("core_hollow_shell", tile_core_hollow_shell, 2),
]


def build_strip(painter, variants: int) -> list[list[tuple]]:
    width = S * variants
    pixels = [[(0, 0, 0, 0)] * width for _ in range(S)]
    pixels = [list(row) for row in pixels]
    for v in range(variants):
        painter(Cell(pixels, v * S), v)
    return pixels


def main(argv: list[str]) -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(os.path.dirname(here), "assets", "tilesets")

    ap = argparse.ArgumentParser(description="Generate Faultline terrain tile strips.")
    ap.add_argument("--out", default=default_out, help="output directory (default: assets/tilesets)")
    ap.add_argument(
        "--keep-imports",
        action="store_true",
        help="do not delete stale <name>.png.import files (default: delete them)",
    )
    args = ap.parse_args(argv)

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    try:
        import PIL  # noqa: F401
        note = "Pillow present but unused (stdlib zlib/struct writer)"
    except ImportError:
        note = "Pillow absent (not needed -- stdlib zlib/struct writer)"
    print("[gen_tileset] %s" % note)
    print("[gen_tileset] out: %s" % out_dir)

    total_tiles = 0
    removed = []
    for name, painter, variants in TERRAINS:
        pixels = build_strip(painter, variants)
        path = os.path.join(out_dir, name + ".png")
        write_png(path, S * variants, S, pixels)
        w, h = read_png_size(path)
        assert (w, h) == (S * variants, S), "%s wrote %dx%d" % (name, w, h)
        total_tiles += variants
        print("  %-20s %2dx%-2d  (%d variant%s)" % (name + ".png", w, h, variants, "" if variants == 1 else "s"))

        imp = path + ".import"
        if os.path.exists(imp) and not args.keep_imports:
            os.remove(imp)
            removed.append(os.path.basename(imp))

    print("[gen_tileset] %d files, %d atlas tiles total" % (len(TERRAINS), total_tiles))
    if removed:
        print("[gen_tileset] removed %d stale .import file(s) -> Godot will reimport cleanly on next editor open" % len(removed))
    elif not args.keep_imports:
        print("[gen_tileset] no stale .import files found")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
