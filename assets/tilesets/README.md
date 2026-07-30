# Terrain tileset art — drop-in spec

`TerrainManager` loads a PNG from this folder for each terrain type automatically
(`_load_tile_png` / `_tile_file` in `src/world/TerrainManager.gd`). Drop a correctly
named file here and it replaces the procedural dev-art tile on the next run — no code
change needed. A missing file falls back to the code-drawn tile, so you can migrate
one tile at a time. A wrong-shaped file is ignored (with a console warning) rather than
stretched or sliced wrong.

The PNGs currently in this folder were written by `tools/gen_tileset.py`, which is a
1:1 mirror of the procedural painters in `TerrainManager`. Re-run it after changing
those painters (`python tools/gen_tileset.py` — Python 3 stdlib only, no Pillow), or
just overwrite a file by hand with real art.

## Hard requirements

- **Horizontal variant strip: 16×16 px per variant, height exactly 16, width `16 × N`
  with N between 1 and 3.** So `48×16` = 3 variants, `32×16` = 2, `16×16` = 1. Any
  other shape is rejected + warned.
- **PNG**, RGBA. Terrain tiles are opaque squares (the Core Hollow *interior* is empty
  space with no tile — you never draw it).
- **Import filter = Nearest.** Project default already is; just don't override it per-file
  in the Import dock, or the tile blurs.
- Filename must match exactly (lowercase, below). Source ID is keyed by the terrain
  enum value, so the *name* is how you target a type.

## Why a strip of variants

Every cell of a terrain used to be the same 16×16 image, so a wall of soil read as an
obvious repeating stamp. `TerrainManager.place_tile()` now picks one of the N variants
by hashing the **cell coordinate** — deterministic (a cell re-placed by column streaming
always gets the same variant back) and neighbour-blind.

This is flat per-cell variant selection, **not autotiling**. There are no terrain sets,
no `set_cells_terrain_connect()`, and no neighbour re-evaluation anywhere: edge/corner
transitions are a separate, much larger upgrade that is deliberately out of scope at
100-player scale. Variants must therefore be interchangeable — any variant has to look
correct next to any other variant of the same terrain, in any direction.

## Filenames (12)

| File | Terrain | Variants | Layer | Suggested look |
|------|---------|----------|-------|----------------|
| `soil.png` | Soil | 3 | Crust | soft brown, granular |
| `clay.png` | Clay | 3 | Crust | orange-tan, faint bedding |
| `limestone.png` | Limestone | 3 | Crust | pale gray, horizontal strata |
| `rock.png` | Rock | 3 | Mantle | mid-gray, cracked |
| `basalt.png` | Basalt | 3 | Mantle | dark gray, columnar joints |
| `granite.png` | Granite | 3 | Mantle | speckled gray-pink |
| `obsidian.png` | Obsidian | 3 | Outer Core | black, conchoidal glass fractures |
| `iron_formation.png` | Iron Formation | 3 | Outer Core | rust-red w/ metallic bands |
| `dense_crystal.png` | Dense Crystal | 3 | Outer Core | faceted teal |
| `ultra_dense.png` | Ultra Dense | 3 | Inner Core | near-black, faint gold veins |
| `bedrock.png` | Bedrock | 2 | bounds | riveted plate (bottom border only) |
| `core_hollow_shell.png` | Core Hollow Shell | 2 | Core Hollow | armoured blue-black, molten-cyan seams |

`fallback.png` (optional) covers any unmapped type.

## Style rules — read before drawing

These are what stop the world reading as a 16px checkerboard. They are enforced by eye,
not by code, so breaking them silently reintroduces the grid.

1. **No 1px dark border on the ten natural fill terrains.** Outlining a cell draws the
   tile grid in ink. **Exception: `bedrock` and `core_hollow_shell` KEEP their perimeter**
   — those two are meant to read as discrete engineered/armoured plates.
2. **No feature at a fixed coordinate.** The old art put a catch-light highlight at pixel
   (2, 2) of nearly every tile; repeated across a wall that is a regular dot lattice. Same
   for a lit corner block or a light→dark gradient across the tile.
3. **Repeating patterns must have a period that divides 16** (2/4/8/16). `y % 5` or
   `(x + y) % 3` jump at the cell boundary and redraw the grid. Horizontal strata that
   obey this (limestone, iron formation) run continuously through a whole cliff face —
   keep the band phase the SAME in every variant of that terrain, and vary only the
   speckle/detail, or the bands will visibly step between neighbours.
4. **Let some detail touch the cell edge.** If all the bright detail sits in the middle,
   each cell gets a darker rim and the grid comes back softly.
5. Light source top-left; keep a shared palette across all 12 so the layers read as one
   world. Highlights should stay a step below pure white: the TileMap is tinted per layer
   (roughly 0.75–1.0 per channel), so legibility must come from base-tone contrast.
6. Variants should differ in **placement of detail** (different speckle/crack/vein), not
   just brightness.
