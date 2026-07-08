# Character & loot sprite sheets — drop-in spec

Three sheets are loaded automatically at runtime and replace the old code-drawn
`Image`/`Sprite2D` art. Each loader falls back to the procedural art if the PNG
is missing / not yet imported / the wrong size, so you can migrate incrementally.
Regenerate all three with `python tools/gen_sprites.py`.

| File | Loaded by | Grid | Frames (left → right) |
|------|-----------|------|-----------------------|
| `player.png` | `PlayerController._load_body_sheet` | 32×32 | `idle0 idle1 walk0 walk1 walk2 walk3` |
| `dummy.png`  | `TestDummy._load_dummy_sheet`      | 32×32 | `idle alert` |
| `loot.png`   | `LootDrop._load_loot_sheet`        | 16×16 | `drill weapon armor relic throwable consumable scanner` |

## Hard requirements
- **PNG, RGBA, transparent background, no upscale** (native pixel size).
- **Height fixed** (32 for player/dummy, 16 for loot); **width must be an exact
  multiple** of the frame size — the loaders reject anything else with a console
  warning and fall back to code art.
- **Import filter = Nearest.** Project default (`default_texture_filter=0`) already
  is; don't override per-file in the Import dock or the sprite blurs.

## Notes on how the engine uses them
- **player.png** — the body faces right; the code sets `flip_h` for left. The walk
  cycle plays while moving, the idle bob while still. The in-hand drill/sword is a
  separate sprite drawn on top and aimed at the cursor — it is NOT on this sheet.
  Keep the feet near the bottom of the 32px frame so they align with the collision
  box; the sprite is drawn centered on the body origin.
- **dummy.png** — frame 0 is the resting pose, frame 1 the "alert" pose shown while
  it is targeting/attacking the player. The engine ALSO tints `modulate` red on each
  hit, so keep the base fills mid-value (a steel grey) so the red flash reads.
  Silhouette must stay bulkier than the player so the two never confuse mid-fight.
- **loot.png** — one neutral (light-grey) glyph per item **category**. The engine
  tints it to the item's tier colour (gray/blue/purple/gold) via `modulate`, so do
  NOT bake tier colours in. One icon per category is enough for v1 (≈140 per-item
  icons are out of scope); the column order above is fixed — it maps to the item
  `type` string in `LootDrop._icon_index`.
