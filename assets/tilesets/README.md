# Terrain tileset art — drop-in spec

`TerrainManager` loads a PNG from this folder for each terrain type automatically
(`_load_tile_png` / `_tile_file` in `src/world/TerrainManager.gd`). Drop a correctly
named file here and it replaces the procedural dev-art tile on the next run — no code
change needed. A missing file falls back to the code-drawn tile, so you can migrate
one tile at a time. A wrong-size file is ignored (with a console warning) rather than
stretched.

## Hard requirements
- **Exactly 16×16 px** (matches `Constants.TILE_SIZE`). Anything else is rejected + warned.
- **PNG**, RGBA. Terrain tiles are opaque squares (the Core Hollow *interior* is empty
  space with no tile — you never draw it).
- **Import filter = Nearest.** Project default already is; just don't override it per-file
  in the Import dock, or the tile blurs.
- Filename must match exactly (lowercase, below). Source ID is keyed by the terrain
  enum value, so the *name* is how you target a type.

## Filenames (12)
| File | Terrain | Layer | Suggested look |
|------|---------|-------|----------------|
| `soil.png` | Soil | Crust | soft brown, granular |
| `clay.png` | Clay | Crust | orange-tan, smooth |
| `limestone.png` | Limestone | Crust | pale gray, chalky |
| `rock.png` | Rock | Mantle | mid-gray, cracked |
| `basalt.png` | Basalt | Mantle | dark gray, angular |
| `granite.png` | Granite | Mantle | speckled gray-pink |
| `obsidian.png` | Obsidian | Outer Core | black, glassy sheen |
| `iron_formation.png` | Iron Formation | Outer Core | dark w/ metallic bands |
| `dense_crystal.png` | Dense Crystal | Outer Core | faceted, translucent |
| `ultra_dense.png` | Ultra Dense | Inner Core | near-black, heavy |
| `bedrock.png` | Bedrock | bounds | flat dull gray (bottom border only) |
| `core_hollow_shell.png` | Core Hollow Shell | Core Hollow | armored blue-black, molten-cyan seams |

`fallback.png` (optional) covers any unmapped type.

## Style tips (match the existing dev art for cohesion)
- 1px dark outline, light source top-left.
- Keep a consistent shared palette across all 12 so layers read as one world.
- These are currently **flat** tiles (one per type). Edge/corner autotiling is a
  separate, larger upgrade — see the visual-polish notes in `CLAUDE.md`.
