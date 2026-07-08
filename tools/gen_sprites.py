#!/usr/bin/env python3
"""Faultline character & loot sprite generator (Part C — visual polish).

Outputs (transparent PNG, no upscale — Nearest filter in engine):
  assets/sprites/player.png  6 frames x 32px  [idle0 idle1 walk0 walk1 walk2 walk3]
  assets/sprites/dummy.png   2 frames x 32px  [idle alert]  (engine tints modulate)
  assets/sprites/loot.png    7 icons x 16px   [drill weapon armor relic throwable
                                               consumable scanner]  (tinted per tier)

First-pass procedural art — a human artist refines later. Silhouettes are the
priority: the player reads as a blue-grey diver/miner, the dummy as a bulkier
steel hulk (never confused mid-fight), loot icons as clean category glyphs that
take a tier-colour modulate cleanly (light neutral fills).

Run: python tools/gen_sprites.py
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")


def h(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def rect(px, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < px.width and 0 <= y < px.height:
                px.putpixel((x, y), c)


class P:
    """Tiny pixel canvas with .width/.height and putpixel/getpixel."""
    def __init__(self, w, h_):
        self.img = Image.new("RGBA", (w, h_), (0, 0, 0, 0))
        self.width, self.height = w, h_

    def putpixel(self, xy, c):
        self.img.putpixel(xy, c)

    def getpixel(self, xy):
        return self.img.getpixel(xy)


def outline_alpha(p, col):
    """1px dark outline around every opaque cluster (4-neighbour)."""
    src = p.img.copy()
    w, hh = p.width, p.height
    for y in range(hh):
        for x in range(w):
            if src.getpixel((x, y))[3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < hh and src.getpixel((nx, ny))[3] != 0:
                    p.putpixel((x, y), col)
                    break


# ---------------- PLAYER (miner / diver, side view, faces right) ------------
SUIT = h("4a5a6e")
SUIT_D = h("313d4d")
SUIT_L = h("6a7d92")
GLASS = h("6fe6ff")
GLASS_D = h("2a8a9a")
BOOT = h("2a323d")
TANK = h("3a4652")
TANK_L = h("55677a")
OUTL = h("161c24")


def player_frame(bob, leg):
    """bob: vertical body offset (idle). leg: 0..3 walk pose (or -1 idle stand)."""
    p = P(32, 32)
    px = p
    oy = bob

    # backpack drill tank (on the back / left since facing right)
    rect(px, 6, 11 + oy, 10, 20 + oy, TANK)
    rect(px, 6, 11 + oy, 7, 20 + oy, TANK_L)
    px.putpixel((8, 10 + oy), TANK_L)

    # torso (suit)
    rect(px, 10, 12 + oy, 20, 22 + oy, SUIT)
    rect(px, 10, 12 + oy, 11, 22 + oy, SUIT_D)     # back shade
    rect(px, 18, 12 + oy, 20, 22 + oy, SUIT_L)     # chest catch-light
    rect(px, 12, 13 + oy, 17, 14 + oy, SUIT_L)     # shoulder line

    # helmet / head
    rect(px, 11, 4 + oy, 20, 11 + oy, SUIT)
    rect(px, 12, 3 + oy, 19, 3 + oy, SUIT)          # dome top
    rect(px, 11, 4 + oy, 12, 11 + oy, SUIT_D)
    rect(px, 18, 4 + oy, 20, 6 + oy, SUIT_L)
    # visor (front / right)
    rect(px, 16, 6 + oy, 21, 9 + oy, GLASS)
    rect(px, 16, 9 + oy, 21, 9 + oy, GLASS_D)
    px.putpixel((21, 6 + oy), GLASS_D)
    # headlamp glint
    px.putpixel((21, 5 + oy), h("d8fbff"))

    # forward arm holding tool
    rect(px, 19, 14 + oy, 24, 16 + oy, SUIT)
    rect(px, 19, 16 + oy, 24, 16 + oy, SUIT_D)
    rect(px, 23, 13 + oy, 24, 17 + oy, BOOT)        # glove / tool grip

    # legs
    if leg < 0:  # idle stance
        rect(px, 12, 22 + oy, 15, 29 + oy, SUIT_D)
        rect(px, 16, 22 + oy, 19, 29 + oy, SUIT)
        rect(px, 12, 29 + oy, 16, 30 + oy, BOOT)
        rect(px, 16, 29 + oy, 20, 30 + oy, BOOT)
    else:
        # front/back leg swing by phase
        swing = (-2, 0, 2, 0)[leg]
        # back leg
        rect(px, 12, 22 + oy, 15, 28 + oy, SUIT_D)
        rect(px, 12 - max(0, -swing), 28 + oy, 16, 30 + oy, BOOT)
        # front leg
        rect(px, 16, 22 + oy, 19, 28 + oy, SUIT)
        rect(px, 16 + max(0, swing), 28 + oy, 20 + max(0, swing), 30 + oy, BOOT)

    outline_alpha(p, OUTL)
    return p.img


def build_player():
    frames = [
        player_frame(0, -1),   # idle 0
        player_frame(1, -1),   # idle 1 (1px bob)
        player_frame(0, 0),    # walk
        player_frame(0, 1),
        player_frame(0, 2),
        player_frame(0, 3),
    ]
    sheet = Image.new("RGBA", (32 * len(frames), 32), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, (i * 32, 0))
    sheet.save(os.path.join(OUT, "player.png"))
    return sheet


# ---------------- DUMMY (bulky steel hulk, faces right) ---------------------
STEEL = h("8a8f96")
STEEL_D = h("565b63")
STEEL_L = h("b6bcc4")
EYE = h("ff5a4a")
DOUTL = h("20242a")


def dummy_frame(alert):
    p = P(32, 32)
    px = p
    core = h("c8703a") if alert else h("6a7078")   # chest core warms when alert

    # broad legs
    rect(px, 8, 24, 14, 31, STEEL_D)
    rect(px, 18, 24, 24, 31, STEEL_D)
    rect(px, 8, 30, 15, 31, h("3a3e44"))
    rect(px, 18, 30, 25, 31, h("3a3e44"))

    # bulky torso (wider than player)
    rect(px, 6, 11, 26, 25, STEEL)
    rect(px, 6, 11, 8, 25, STEEL_D)
    rect(px, 24, 11, 26, 25, STEEL_L)
    rect(px, 6, 11, 26, 12, STEEL_L)               # shoulder plate highlight
    # chest core light
    rect(px, 14, 16, 18, 20, core)
    rect(px, 15, 17, 17, 19, h("ffd0a0") if alert else h("9aa2ac"))

    # heavy arms
    rect(px, 3, 13, 6, 24, STEEL_D)
    rect(px, 26, 13, 29, 24, STEEL_D)
    rect(px, 3, 23, 7, 26, h("3a3e44"))            # fists
    rect(px, 25, 23, 29, 26, h("3a3e44"))

    # blocky head
    rect(px, 11, 3, 21, 12, STEEL)
    rect(px, 11, 3, 13, 12, STEEL_D)
    rect(px, 19, 3, 21, 6, STEEL_L)
    rect(px, 13, 6, 19, 8, h("2a2e34"))            # visor slit
    px.putpixel((15, 7), EYE)
    px.putpixel((17, 7), EYE)

    outline_alpha(p, DOUTL)
    return p.img


def build_dummy():
    frames = [dummy_frame(False), dummy_frame(True)]
    sheet = Image.new("RGBA", (32 * len(frames), 32), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, (i * 32, 0))
    sheet.save(os.path.join(OUT, "dummy.png"))
    return sheet


# ---------------- LOOT icons (16px, neutral fill, tinted per tier) ----------
# Light neutral palette so a tier-colour modulate reads cleanly.
IC = h("e6e9ee")     # icon light
ICM = h("b9c0c9")    # icon mid
ICD = h("7d8590")    # icon dark
IOUT = h("2a2f36")


def _finish(p):
    outline_alpha(p, IOUT)
    return p.img


def icon_drill():
    p = P(16, 16); px = p
    rect(px, 6, 2, 9, 5, ICM)               # motor
    rect(px, 7, 5, 8, 8, IC)                # shaft
    # triangular bit
    for i in range(5):
        rect(px, 6 - i // 2, 8 + i, 9 + i // 2, 8 + i, IC if i % 2 else ICM)
    px.putpixel((7, 13), ICD); px.putpixel((8, 13), ICD)
    return _finish(p)


def icon_weapon():
    p = P(16, 16); px = p
    for i in range(9):                      # diagonal blade
        rect(px, 3 + i, 12 - i, 4 + i, 12 - i, IC)
        px.putpixel((5 + i, 12 - i), ICM)
    rect(px, 3, 11, 6, 13, ICM)             # guard/hilt
    rect(px, 2, 12, 4, 14, ICD)             # grip
    return _finish(p)


def icon_armor():
    p = P(16, 16); px = p
    rect(px, 4, 2, 11, 3, ICM)              # shoulders
    for y in range(3, 13):                  # tapering chestplate
        inset = (y - 3) // 3
        rect(px, 3 + inset, y, 12 - inset, y, IC if y < 8 else ICM)
    rect(px, 7, 4, 8, 11, ICD)              # centre seam
    return _finish(p)


def icon_relic():
    p = P(16, 16); px = p
    pts = [(8, 2), (12, 6), (11, 11), (8, 14), (5, 11), (4, 6)]  # gem facets
    rect(px, 5, 5, 10, 10, IC)
    rect(px, 6, 4, 9, 11, ICM)
    for (x, y) in pts:
        px.putpixel((x, y), ICM)
    rect(px, 7, 6, 8, 9, h("ffffff"))       # bright core
    return _finish(p)


def icon_throwable():
    p = P(16, 16); px = p
    rect(px, 5, 6, 10, 12, IC)              # round flask body
    rect(px, 5, 8, 6, 11, ICD)
    rect(px, 9, 6, 10, 9, ICM)
    rect(px, 7, 2, 8, 6, ICM)               # neck
    rect(px, 6, 1, 9, 2, ICD)               # cap
    return _finish(p)


def icon_consumable():
    p = P(16, 16); px = p
    rect(px, 5, 3, 10, 13, IC)              # vial
    rect(px, 5, 3, 6, 13, ICM)
    rect(px, 5, 8, 10, 13, ICD)             # liquid fill
    rect(px, 6, 1, 9, 3, ICM)               # cap
    px.putpixel((8, 5), h("ffffff"))
    return _finish(p)


def icon_scanner():
    p = P(16, 16); px = p
    rect(px, 7, 10, 8, 13, ICM)             # stand
    rect(px, 4, 13, 11, 14, ICD)
    for r, c in ((2, ICD), (4, ICM), (6, IC)):   # concentric ping arcs
        for a in range(-r, r + 1):
            y = 8 - int((r * r - a * a) ** 0.5)
            if 0 <= 8 + a < 16 and 0 <= y < 16:
                px.putpixel((8 + a, y), c)
    px.putpixel((8, 8), h("ffffff"))
    return _finish(p)


LOOT = [icon_drill, icon_weapon, icon_armor, icon_relic,
        icon_throwable, icon_consumable, icon_scanner]


def build_loot():
    sheet = Image.new("RGBA", (16 * len(LOOT), 16), (0, 0, 0, 0))
    for i, fn in enumerate(LOOT):
        sheet.paste(fn(), (i * 16, 0))
    sheet.save(os.path.join(OUT, "loot.png"))
    return sheet


def main():
    os.makedirs(OUT, exist_ok=True)
    p = build_player(); print("player.png", p.size)
    d = build_dummy(); print("dummy.png", d.size)
    l = build_loot(); print("loot.png", l.size)
    # previews (8x)
    tdir = os.path.dirname(__file__)
    for name, im in (("player", p), ("dummy", d), ("loot", l)):
        im.resize((im.width * 8, im.height * 8), Image.NEAREST).save(
            os.path.join(tdir, "_preview_%s.png" % name))
    print("wrote previews")


if __name__ == "__main__":
    main()
