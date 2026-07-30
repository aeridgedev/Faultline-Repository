## Faultline — owns and mutates the TileMap; single interface for terrain state.
class_name TerrainManager
extends Node

signal tile_destroyed(cell: Vector2i, type: Constants.TerrainType)

@onready var tile_map: TileMap = $TileMap

var _tile_registry: Dictionary = {}

# Infinite horizontal streaming — canonical world is cols 0..(world_width-1).
# As the player moves left or right, columns outside that range are filled on
# demand by mirroring the canonical column at (col % world_width).
var _canonical_tiles: Dictionary = {}     # snapshot taken after generation
var _canonical_by_col: Dictionary = {}    # col_int -> { row_int: TerrainType }
var _world_width: int = 0
var _streamed_cols: Dictionary = {}       # set of col ints that have been placed

# How many art variants each terrain source actually holds, keyed by TerrainType.
# Filled by _build_dev_tileset() from the REAL image width (16*N), so a drop-in
# PNG with a different variant count than the code art still works. Read by
# _variant_for() on every place_tile(), hence a plain Dictionary lookup.
var _variant_count: Dictionary = {}

# Physics bits the terrain TileSet is built with. The player body (Player.tscn:
# collision_layer = 5 → bits 1 and 3, collision_mask = 1 → bit 1) must have bit 1
# in its MASK for terrain to be solid to it. Named here so the startup diagnostic
# in Main.gd can report the real configured value instead of a hardcoded guess.
const TERRAIN_PHYSICS_LAYER: int = 1   # terrain lives on physics layer bit 1
const TERRAIN_PHYSICS_MASK: int = 1    # terrain scans physics layer bit 1

# Upper bound on art variants per terrain. Purely a sanity clamp for drop-in PNGs
# (a 16*N strip); the code art uses 3 for natural fill and 2 for the two
# engineered-plate terrains.
const MAX_VARIANTS: int = 3

# All terrain types that receive tiles. Order must match enum values so source IDs align.
const _TILE_TYPES: Array[Constants.TerrainType] = [
	Constants.TerrainType.SOIL,
	Constants.TerrainType.CLAY,
	Constants.TerrainType.LIMESTONE,
	Constants.TerrainType.ROCK,
	Constants.TerrainType.BASALT,
	Constants.TerrainType.GRANITE,
	Constants.TerrainType.OBSIDIAN,
	Constants.TerrainType.IRON_FORMATION,
	Constants.TerrainType.DENSE_CRYSTAL,
	Constants.TerrainType.ULTRA_DENSE,
	Constants.TerrainType.BEDROCK,
	Constants.TerrainType.CORE_HOLLOW_SHELL,
]


func _ready() -> void:
	_build_dev_tileset()


## Builds the terrain TileSet in code and installs it on the TileMap.
##
## Each terrain gets ONE atlas source (source ID == terrain enum value) whose
## texture is a horizontal strip of N 16×16 art variants, registered as N atlas
## tiles at coords (0,0)…(N-1,0). place_tile() picks the variant by hashing the
## cell position, which is what stops a solid mass of one terrain reading as a
## repeating stamp. Autotiling is deliberately NOT used (no terrain sets, no
## set_cells_terrain_connect) — variant choice is per-cell and neighbour-blind,
## so placement and destruction both stay O(1) at 100-player scale.
##
## COLLISION ORDERING IS LOAD-BEARING — read before touching this loop.
## A TileData sizes its physics-layer array from the TileSet that OWNS it. A
## TileSetAtlasSource that has not been added to a TileSet yet has tile_set ==
## null, so every TileData it creates has ZERO physics layers, and
## add_collision_polygon(0) fails its bounds check (silent no-op + engine error).
## Worse, a later add_source() re-runs TileData.set_tile_set(), which RESIZES
## that array and wipes anything written beforehand.
##
## THE INVARIANT: every add_collision_polygon() / set_collision_polygon_points()
## call must happen AFTER ts.add_source() for that source — for EVERY variant
## tile, not just the first. Getting this backwards produces terrain that RENDERS
## NORMALLY BUT HAS NO COLLISION — the player falls straight through the world
## from spawn. That is exactly the 2026-07-30 regression (a multi-variant tileset
## refactor moved add_source() below the collision writes). Note the two separate
## `for v in n` loops below: create_tile() before add_source(), collision after.
## _report_tileset_collision() re-reads the FINISHED TileSet and turns that silent
## failure into a loud startup error, so it can never ship again no matter how
## this loop is later restructured.
func _build_dev_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, TERRAIN_PHYSICS_LAYER)
	ts.set_physics_layer_collision_mask(0, TERRAIN_PHYSICS_MASK)

	var half := Constants.TILE_SIZE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half,  half),  Vector2(-half, half),
	])

	_variant_count.clear()
	for terrain_type in _TILE_TYPES:
		var img := _make_tile(terrain_type)
		# Variant count comes from the ACTUAL image, never from an assumption, so
		# a hand-authored PNG strip with fewer/more variants than the code art
		# still registers (and hashes) correctly.
		var n: int = clampi(img.get_width() / Constants.TILE_SIZE, 1, MAX_VARIANTS)
		_variant_count[terrain_type] = n

		var source := TileSetAtlasSource.new()
		source.texture = ImageTexture.create_from_image(img)
		source.texture_region_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
		for v in n:
			source.create_tile(Vector2i(v, 0))
		# add_source() must come BEFORE every collision call below — see the
		# invariant in the docstring. Source ID stays == terrain enum value, so
		# get_cell_source_id → type is unchanged.
		ts.add_source(source, terrain_type)
		for v in n:
			var tile_data: TileData = source.get_tile_data(Vector2i(v, 0), 0)
			tile_data.add_collision_polygon(0)
			tile_data.set_collision_polygon_points(0, 0, square)

	tile_map.tile_set = ts
	_report_tileset_collision(ts)


# Startup self-check for terrain solidity, run against the FINISHED TileSet so it
# is independent of how _build_dev_tileset() is structured internally. The failure
# mode being guarded is silent — a tile with no collision polygon still renders
# perfectly, so the only symptom is bodies falling through the map. Always prints
# a one-line summary; push_error()s (red in the Output panel) naming the offending
# terrains if any tile came out non-solid. Walks every atlas tile of every source,
# so it covers all N variants of a multi-variant tileset — a terrain counts as OK
# only when EVERY one of its variant tiles has a collision polygon.
func _report_tileset_collision(ts: TileSet) -> void:
	if ts.get_physics_layers_count() < 1:
		push_error("[Faultline][Collision] TileSet has NO physics layer — ALL terrain is non-solid.")
		return
	var tiles_total := 0
	var tiles_solid := 0
	var types_ok := 0
	var broken: Array[String] = []
	for terrain_type in _TILE_TYPES:
		var source := ts.get_source(terrain_type) as TileSetAtlasSource
		if source == null:
			broken.append("%s(no source)" % _tile_file(terrain_type))
			continue
		var src_missing := 0
		for i in source.get_tiles_count():
			var coord := source.get_tile_id(i)
			var tile_data: TileData = source.get_tile_data(coord, 0)
			tiles_total += 1
			if tile_data != null and tile_data.get_collision_polygons_count(0) > 0:
				tiles_solid += 1
			else:
				src_missing += 1
		if src_missing > 0:
			broken.append("%s(%d of %d variants)" % [
				_tile_file(terrain_type), src_missing, source.get_tiles_count()])
		else:
			types_ok += 1

	if not broken.is_empty():
		push_error("[Faultline][Collision] %d/%d terrain tiles have NO collision polygon — terrain is NOT solid (bodies will fall through). Affected: %s" % [
			tiles_total - tiles_solid, tiles_total, ", ".join(broken)])
	print("[Faultline][Collision] TileSet built: %d/%d terrain types have collision [%s]  (%d/%d atlas tiles)" % [
		types_ok, _TILE_TYPES.size(),
		"OK" if broken.is_empty() else "BROKEN",
		tiles_solid, tiles_total])


# Physics configuration actually installed on the TileMap, for the startup
# collision diagnostic in Main.gd. Reports live values (not the constants above)
# so the printout reflects reality even if something reassigns the TileSet.
func get_physics_config() -> Dictionary:
	var ts: TileSet = tile_map.tile_set if tile_map != null else null
	var has_layer: bool = ts != null and ts.get_physics_layers_count() > 0
	return {
		"tile_set_assigned": ts != null,
		"layer_0_enabled": tile_map.is_layer_enabled(0) if tile_map != null else false,
		"physics_layers": ts.get_physics_layers_count() if ts != null else 0,
		"collision_layer": ts.get_physics_layer_collision_layer(0) if has_layer else 0,
		"collision_mask": ts.get_physics_layer_collision_mask(0) if has_layer else 0,
	}


## Representative mid-tone colour for a terrain type, taken from that terrain's
## art palette. Public so VFX (break debris particles, dust puffs) can tint
## themselves to the terrain that actually broke without duplicating the palette.
## Total over the enum — any unmapped value returns a neutral gray.
func base_color_for(type: Constants.TerrainType) -> Color:
	match type:
		Constants.TerrainType.SOIL:              return Color(0.46, 0.29, 0.13)
		Constants.TerrainType.CLAY:              return Color(0.52, 0.27, 0.12)
		Constants.TerrainType.LIMESTONE:         return Color(0.68, 0.63, 0.50)
		Constants.TerrainType.ROCK:              return Color(0.45, 0.45, 0.48)
		Constants.TerrainType.BASALT:            return Color(0.13, 0.15, 0.19)
		Constants.TerrainType.GRANITE:           return Color(0.40, 0.39, 0.39)
		Constants.TerrainType.OBSIDIAN:          return Color(0.07, 0.05, 0.11)
		Constants.TerrainType.IRON_FORMATION:    return Color(0.34, 0.16, 0.07)
		Constants.TerrainType.DENSE_CRYSTAL:     return Color(0.10, 0.28, 0.42)
		Constants.TerrainType.ULTRA_DENSE:       return Color(0.08, 0.07, 0.05)
		Constants.TerrainType.BEDROCK:           return Color(0.10, 0.09, 0.13)
		Constants.TerrainType.CORE_HOLLOW_SHELL: return Color(0.09, 0.16, 0.22)
		_:                                       return Color(0.50, 0.50, 0.50)


# --- Terrain art source: imported PNG first, procedural dev art as fallback ---
# Drop a PNG in assets/tilesets/ named per _tile_file() (e.g. soil.png) and it
# automatically replaces the code-drawn tile — nothing else changes, because
# place_tile() keys the TileSet source purely by the terrain enum value
# (source ID = TerrainType). The file is a HORIZONTAL STRIP of N 16×16 variants
# (width 16*N, height 16, N in 1..MAX_VARIANTS); the atlas registers one tile per
# variant and place_tile() hashes the cell to pick one. A missing / unimported /
# wrong-shape PNG falls back to the code art below (wrong shape warns), so tiles
# can be migrated to real art one at a time.
const _TILESET_DIR := "res://assets/tilesets/"


func _make_tile(type: Constants.TerrainType) -> Image:
	var png := _load_tile_png(type)
	return png if png != null else _make_tile_codegen(type)


# Loads assets/tilesets/<name>.png as an Image, or null if absent / not yet
# imported / not a valid variant strip. Accepted shape: height == TILE_SIZE and
# width == TILE_SIZE * N with 1 <= N <= MAX_VARIANTS. Anything else warns and
# falls back so a bad drop-in is obvious rather than silently sliced wrong by the
# atlas region.
#
# The FileAccess.file_exists() check is deliberate and must stay: ResourceLoader
# .exists() resolves an imported texture through its .import remap, so it returns
# TRUE for a source PNG that has been deleted while a stale .import (and its
# .godot/imported/*.ctex) is left behind — load() then hands back the OLD texture
# data. Testing the real source file makes "no PNG on disk" mean "use the code art".
func _load_tile_png(type: Constants.TerrainType) -> Image:
	var path := _TILESET_DIR + _tile_file(type) + ".png"
	if not FileAccess.file_exists(path):
		return null
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	var w := img.get_width()
	var h := img.get_height()
	var n := w / Constants.TILE_SIZE
	if h != Constants.TILE_SIZE or w % Constants.TILE_SIZE != 0 or n < 1 or n > MAX_VARIANTS:
		push_warning("[TerrainManager] %s is %d×%d, expected %d×%d strips (width = %d × 1..%d variants) — using code art." % [
			path, w, h, Constants.TILE_SIZE, Constants.TILE_SIZE, Constants.TILE_SIZE, MAX_VARIANTS])
		return null
	return img


# Filename (without extension) expected in assets/tilesets/ for each terrain type.
func _tile_file(type: Constants.TerrainType) -> String:
	match type:
		Constants.TerrainType.SOIL:              return "soil"
		Constants.TerrainType.CLAY:              return "clay"
		Constants.TerrainType.LIMESTONE:         return "limestone"
		Constants.TerrainType.ROCK:              return "rock"
		Constants.TerrainType.BASALT:            return "basalt"
		Constants.TerrainType.GRANITE:           return "granite"
		Constants.TerrainType.OBSIDIAN:          return "obsidian"
		Constants.TerrainType.IRON_FORMATION:    return "iron_formation"
		Constants.TerrainType.DENSE_CRYSTAL:     return "dense_crystal"
		Constants.TerrainType.ULTRA_DENSE:       return "ultra_dense"
		Constants.TerrainType.BEDROCK:           return "bedrock"
		Constants.TerrainType.CORE_HOLLOW_SHELL: return "core_hollow_shell"
		_:                                       return "fallback"


# Variants the CODE art draws for a terrain. Natural fill terrains get 3 (the
# repeat is what makes a mass of them read as a grid); the two engineered-plate
# terrains get 2 (Bedrock is a one-row border and the Shell is a thin wall, so
# they are never seen as a large field).
func _codegen_variants(type: Constants.TerrainType) -> int:
	match type:
		Constants.TerrainType.BEDROCK, Constants.TerrainType.CORE_HOLLOW_SHELL:
			return 2
		_:
			return 3


# Builds the full horizontal variant strip for one terrain (width 16*N, height 16).
func _make_tile_codegen(type: Constants.TerrainType) -> Image:
	var n := _codegen_variants(type)
	var img := _blank(Constants.TILE_SIZE * n, Constants.TILE_SIZE)
	for v in n:
		_paint_variant(img, v * Constants.TILE_SIZE, type, v)
	return img


func _paint_variant(img: Image, ox: int, type: Constants.TerrainType, v: int) -> void:
	match type:
		Constants.TerrainType.SOIL:              _tile_soil(img, ox, v)
		Constants.TerrainType.CLAY:              _tile_clay(img, ox, v)
		Constants.TerrainType.LIMESTONE:         _tile_limestone(img, ox, v)
		Constants.TerrainType.ROCK:              _tile_rock(img, ox, v)
		Constants.TerrainType.BASALT:            _tile_basalt(img, ox, v)
		Constants.TerrainType.GRANITE:           _tile_granite(img, ox, v)
		Constants.TerrainType.OBSIDIAN:          _tile_obsidian(img, ox, v)
		Constants.TerrainType.IRON_FORMATION:    _tile_iron_formation(img, ox, v)
		Constants.TerrainType.DENSE_CRYSTAL:     _tile_dense_crystal(img, ox, v)
		Constants.TerrainType.ULTRA_DENSE:       _tile_ultra_dense(img, ox, v)
		Constants.TerrainType.BEDROCK:           _tile_bedrock(img, ox, v)
		Constants.TerrainType.CORE_HOLLOW_SHELL: _tile_core_hollow_shell(img, ox, v)
		_:                                       _tile_fallback(img, ox, v)


# --- Terrain tile painters ---
#
# DE-GRIDDING RULES (2026-07-30) — the terrain used to read as an obvious 16px
# checkerboard. Two causes, both removed here, and both easy to reintroduce:
#   1. NO 1px dark perimeter on the ten natural FILL terrains. Outlining every
#      cell draws the tile grid in ink. The perimeter is KEPT on exactly two
#      terrains — BEDROCK and CORE_HOLLOW_SHELL — where reading as a discrete
#      engineered/armoured plate is the intended look.
#   2. NO fixed catch-light pixel (the old `set_pixel(2, 2, HI)` in most
#      painters) and no edge-anchored corner block or per-tile gradient: any
#      feature at a constant coordinate repeats into a regular dot lattice.
# Everything is therefore a flat base + interior detail. Modulo patterns must
# have a period that DIVIDES 16 (2/4/8/16) or the pattern jumps at the cell
# boundary and re-draws the grid — e.g. `y % 5` and `(x + y) % 3` were both
# offenders. Detail placement is per-variant, so N cells of the same terrain do
# not stamp identically.
#
# Painters write into a horizontal strip at x offset `ox`; `v` is the variant
# index. Light source: top-left. Highlights stay a step below pure white — the
# TileMap gets a per-layer modulate tint (roughly 0.75–1.0 per channel), so
# legibility must come from base-tone contrast, not from a white pixel.
const _S: int = 16   # one cell is _S × _S; the strip is (_S * N) × _S


# Deterministic per-pixel hash → 0..0x7FFFFFFF. Every intermediate is masked
# non-negative so the result is identical in the Python tile generator
# (tools/gen_tileset.py), which must reproduce these painters byte-for-byte.
func _pxhash(x: int, y: int, salt: int) -> int:
	var h: int = ((x * 374761393) + (y * 668265263) + (salt * 2654435761)) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return (h ^ (h >> 16)) & 0x7FFFFFFF


# Bounds-checked cell-local plot. The clamp is load-bearing: a feature drawn near
# x=15 must NOT bleed into the next variant's band of the strip.
func _px(img: Image, ox: int, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= _S or y >= _S:
		return
	img.set_pixel(ox + x, y, c)


# Horizontal run of `length` pixels starting at (x, y), cell-local.
func _run(img: Image, ox: int, x: int, y: int, length: int, c: Color) -> void:
	for i in length:
		_px(img, ox, x + i, y, c)


func _tile_soil(img: Image, ox: int, v: int) -> void:
	# Granular loam: flat base + fine grit noise + a few rounded pebbles.
	var B  := Color(0.44, 0.27, 0.11)
	var M  := Color(0.52, 0.34, 0.16)
	var D  := Color(0.30, 0.17, 0.06)
	var LT := Color(0.60, 0.41, 0.20)
	var PB := Color(0.38, 0.25, 0.12)
	var DK := Color(0.20, 0.11, 0.03)
	var salt := 11 + v * 7
	for y in _S:
		for x in _S:
			var r := _pxhash(x, y, salt) % 100
			var c := B
			if r < 16:
				c = M
			elif r < 26:
				c = D
			elif r < 30:
				c = LT
			_px(img, ox, x, y, c)
	var pebbles := [
		[[3, 4], [10, 9], [6, 12]],
		[[12, 3], [2, 8], [8, 13]],
		[[5, 2], [13, 10], [9, 5]],
	]
	for p in pebbles[v]:
		var px: int = int(p[0])
		var py: int = int(p[1])
		_px(img, ox, px,     py,     LT)
		_px(img, ox, px + 1, py,     PB)
		_px(img, ox, px,     py + 1, PB)
		_px(img, ox, px + 1, py + 1, DK)


func _tile_clay(img: Image, ox: int, v: int) -> void:
	# Warm reddish-brown, compact. Bedding every 8 rows (period divides 16 → the
	# layering continues across cells instead of restarting at each border). Kept
	# low-contrast and sparse on purpose: a strong dark row every 4 rows, broken
	# up by the speckle, reads as brickwork rather than packed clay.
	var B  := Color(0.52, 0.27, 0.12)
	var L  := Color(0.60, 0.34, 0.17)
	var D  := Color(0.42, 0.21, 0.09)
	var BD := Color(0.47, 0.24, 0.10)
	var DK := Color(0.31, 0.14, 0.05)
	var LP := Color(0.66, 0.40, 0.22)
	var salt := 31 + v * 7
	for y in _S:
		for x in _S:
			var r := _pxhash(x, y, salt) % 100
			var c := BD if y % 8 == 0 else B
			if r < 13:
				c = L
			elif r < 22:
				c = D
			elif r < 26:
				c = LP
			_px(img, ox, x, y, c)
	# Per-variant desiccation crack (a fixed row in every cell would itself be a
	# lattice — the row differs per variant and never spans the full width).
	var cracks := [[3, 3, 9], [9, 7, 13], [13, 2, 7]]
	var row: int = int(cracks[v][0])
	for x in range(int(cracks[v][1]), int(cracks[v][2]) + 1):
		_px(img, ox, x, row, DK)
		if x % 3 == 0:
			_px(img, ox, x, row + 1, LP)


func _tile_limestone(img: Image, ox: int, v: int) -> void:
	# Pale sedimentary strata. The band phase is IDENTICAL in every variant on
	# purpose: 16 % 8 == 0, so the bands run continuously through a whole cliff
	# face. Only the mottle and fossil specks change per variant. (Period 8, not
	# 4 — a seam every 4 rows makes the surface read as woven fabric.)
	var B  := Color(0.68, 0.63, 0.50)
	var L  := Color(0.76, 0.72, 0.60)
	var D  := Color(0.54, 0.50, 0.38)
	var CH := Color(0.84, 0.81, 0.71)
	var SD := Color(0.46, 0.42, 0.32)
	var salt := 53 + v * 7
	for y in _S:
		for x in _S:
			var c := B
			if y % 8 == 0:
				c = D
			elif y % 8 == 1:
				c = L
			var r := _pxhash(x, y, salt) % 100
			if r < 10:
				c = CH
			elif r < 16:
				c = SD
			_px(img, ox, x, y, c)
	var light := [
		[[4, 6], [5, 6], [11, 10]],
		[[10, 5], [11, 5], [3, 12]],
		[[7, 11], [8, 11], [13, 6]],
	]
	var dark := [
		[[9, 3], [13, 13]],
		[[6, 9], [14, 2]],
		[[2, 5], [10, 14]],
	]
	for p in light[v]:
		_px(img, ox, int(p[0]), int(p[1]), CH)
	for p in dark[v]:
		_px(img, ox, int(p[0]), int(p[1]), SD)


func _tile_rock(img: Image, ox: int, v: int) -> void:
	# Mid-gray fractured stone. The old painter lit a fixed 6×6 top-left block and
	# shadowed the bottom-right — a per-cell shading ramp, i.e. a printed grid.
	# Replaced with flat noise + per-variant crack polylines.
	var B  := Color(0.44, 0.44, 0.47)
	var M  := Color(0.52, 0.52, 0.55)
	var SH := Color(0.34, 0.34, 0.37)
	var CK := Color(0.22, 0.22, 0.24)
	var LT := Color(0.62, 0.62, 0.66)
	var salt := 71 + v * 7
	for y in _S:
		for x in _S:
			var r := _pxhash(x, y, salt) % 100
			var c := B
			if r < 18:
				c = M
			elif r < 30:
				c = SH
			elif r < 34:
				c = LT
			_px(img, ox, x, y, c)
	var cracks := [
		[[[2, 3], [3, 4], [4, 4], [5, 5], [6, 6], [7, 6], [8, 7], [9, 8], [10, 8]]],
		[[[12, 2], [11, 3], [11, 4], [10, 5], [9, 6], [9, 7], [8, 8], [7, 9]],
		 [[2, 11], [3, 12], [4, 12], [5, 13]]],
		[[[1, 8], [2, 8], [3, 9], [4, 10], [5, 10], [6, 11], [7, 12]],
		 [[10, 2], [11, 3], [12, 3], [13, 4]]],
	]
	for line: Array in cracks[v]:
		for i in line.size():
			var p: Array = line[i]
			_px(img, ox, int(p[0]), int(p[1]), CK)
			if i % 3 == 0:
				_px(img, ox, int(p[0]), int(p[1]) - 1, LT)


func _tile_basalt(img: Image, ox: int, v: int) -> void:
	# Very dark blue-gray volcanic rock with columnar jointing. Joints are jittered
	# procedurally per row so no two variants share a column position.
	var B  := Color(0.12, 0.14, 0.18)
	var M  := Color(0.16, 0.19, 0.24)
	var CK := Color(0.07, 0.08, 0.11)
	var LT := Color(0.23, 0.27, 0.33)
	var salt := 97 + v * 7
	for y in _S:
		for x in _S:
			var r := _pxhash(x, y, salt) % 100
			var c := B
			if r < 14:
				c = M
			elif r < 20:
				c = CK
			elif r < 23:
				c = LT
			_px(img, ox, x, y, c)
	var columns := [[3, 10], [6, 13], [2, 8, 13]]
	for col in columns[v]:
		var cx: int = int(col)
		for y in _S:
			var jx: int = cx + (_pxhash(cx, y, salt) % 3) - 1
			_px(img, ox, jx, y, CK)
			if _pxhash(cx, y, salt + 1) % 2 == 0:
				_px(img, ox, jx + 1, y, LT)
	var rows := [[7], [4, 11], [9]]
	for row in rows[v]:
		var cy: int = int(row)
		for x in _S:
			var jy: int = cy + (_pxhash(x, cy, salt + 2) % 3) - 1
			_px(img, ox, x, jy, CK)


func _tile_granite(img: Image, ox: int, v: int) -> void:
	# Speckled gray with pink feldspar, white quartz and dark mica. Pure noise —
	# no hand-placed specks, so the three variants share nothing but the palette.
	var B  := Color(0.38, 0.37, 0.37)
	var LT := Color(0.46, 0.45, 0.46)
	var PK := Color(0.58, 0.38, 0.36)
	var WH := Color(0.74, 0.74, 0.75)
	var DK := Color(0.19, 0.18, 0.19)
	var salt := 131 + v * 7
	for y in _S:
		for x in _S:
			var r := _pxhash(x, y, salt) % 100
			var c := B
			if r < 9:
				c = PK
			elif r < 17:
				c = WH
			elif r < 26:
				c = DK
			elif r < 40:
				c = LT
			_px(img, ox, x, y, c)
	# Second pass grows some crystals to 2px so the grain is not uniformly fine.
	for y in _S:
		for x in _S:
			var r := _pxhash(x, y, salt) % 100
			if r < 9 and _pxhash(x, y, salt + 2) % 2 == 0:
				_px(img, ox, x + 1, y, PK)
			elif r >= 9 and r < 17 and _pxhash(x, y, salt + 3) % 3 == 0:
				_px(img, ox, x, y + 1, WH)


func _tile_obsidian(img: Image, ox: int, v: int) -> void:
	# Near-black volcanic glass. The old painter brightened the whole x+y<6 corner
	# and pinned three specular pixels — a bright dot at the same spot in every
	# cell. Now: flat black + per-variant conchoidal fracture arcs.
	var B  := Color(0.05, 0.04, 0.08)
	var PU := Color(0.11, 0.07, 0.18)
	var SH := Color(0.20, 0.12, 0.33)
	var HI := Color(0.52, 0.45, 0.76)
	var DK := Color(0.02, 0.02, 0.04)
	var salt := 157 + v * 7
	for y in _S:
		for x in _S:
			var r := _pxhash(x, y, salt) % 100
			var c := B
			if r < 8:
				c = PU
			elif r < 12:
				c = DK
			_px(img, ox, x, y, c)
	var arcs := [
		[[[3, 10], [4, 9], [5, 8], [6, 8], [7, 7], [8, 7], [9, 8], [10, 9]]],
		[[[10, 3], [11, 4], [12, 5], [12, 6], [11, 7], [10, 8], [9, 9]],
		 [[2, 3], [3, 2], [4, 2], [5, 3]]],
		[[[6, 13], [7, 12], [8, 12], [9, 11], [10, 10], [11, 10]],
		 [[1, 7], [2, 6], [3, 6], [4, 5], [5, 5]]],
	]
	for arc: Array in arcs[v]:
		for i in arc.size():
			var p: Array = arc[i]
			var x: int = int(p[0])
			var y: int = int(p[1])
			_px(img, ox, x, y, SH)
			_px(img, ox, x, y + 1, PU)
			if i == 2 or i == 3:
				_px(img, ox, x, y, HI)


func _tile_iron_formation(img: Image, ox: int, v: int) -> void:
	# Rust-red banded ironstone. Bands moved from a 5-row period (which jumped at
	# every cell edge) to 8 rows, so they run unbroken through the whole seam.
	var B  := Color(0.32, 0.14, 0.06)
	var OR := Color(0.45, 0.22, 0.08)
	var DK := Color(0.21, 0.09, 0.03)
	var MG := Color(0.35, 0.34, 0.36)
	var LM := Color(0.47, 0.46, 0.50)
	var salt := 181 + v * 7
	for y in _S:
		for x in _S:
			var c: Color
			if y % 8 == 2:
				c = MG
			elif y % 8 == 3:
				c = LM
			else:
				var r := _pxhash(x, y, salt) % 100
				c = B
				if r < 16:
					c = OR
				elif r < 24:
					c = DK
			_px(img, ox, x, y, c)
	# Rust interruptions through the metallic bands — the bands stay continuous
	# overall but never look stamped from the same die.
	var breaks := [[5], [12], [2, 11]]
	for bx in breaks[v]:
		for by in [2, 3, 10, 11]:
			_px(img, ox, int(bx), int(by), OR)
	var flecks := [
		[[9, 6], [3, 14]],
		[[4, 7], [13, 13]],
		[[8, 15], [14, 6]],
	]
	for p in flecks[v]:
		_px(img, ox, int(p[0]), int(p[1]), LM)


func _tile_dense_crystal(img: Image, ox: int, v: int) -> void:
	# Deep teal with angular facets. The old painter lerped a gradient across
	# (x + y) / 32, so every cell went light-corner → dark-corner: the single
	# worst grid offender. Now a flat base with per-variant faceting.
	var D  := Color(0.06, 0.17, 0.27)
	var MD := Color(0.10, 0.28, 0.42)
	var LT := Color(0.17, 0.44, 0.60)
	var PU := Color(0.18, 0.16, 0.40)
	var WH := Color(0.58, 0.86, 0.93)
	var salt := 211 + v * 7
	for y in _S:
		for x in _S:
			var r := _pxhash(x, y, salt) % 100
			var c := D
			if r < 18:
				c = MD
			elif r < 26:
				c = PU
			elif r < 30:
				c = LT
			_px(img, ox, x, y, c)
	# Every variant has at least one facet running off a cell edge. Keeping all the
	# bright faceting strictly inside the 16×16 box would leave a darker rim around
	# each cell — the same visible lattice a 1px border draws, just softer.
	var facets := [
		[[[3, 2, 5], [1, 3, 7], [0, 4, 8], [0, 5, 7], [1, 6, 5], [3, 7, 2]],
		 [[10, 9, 6], [9, 10, 7], [9, 11, 6], [10, 12, 4]],
		 [[4, 13, 5], [5, 14, 4], [5, 15, 4]]],
		[[[2, 0, 5], [2, 1, 6], [3, 2, 5], [4, 3, 3]],
		 [[9, 5, 5], [8, 6, 7], [8, 7, 6], [9, 8, 4], [10, 9, 2]],
		 [[0, 11, 5], [1, 12, 4]]],
		[[[6, 1, 5], [5, 2, 7], [5, 3, 6], [6, 4, 4], [7, 5, 2]],
		 [[0, 8, 5], [0, 9, 6], [1, 10, 4], [2, 11, 2]],
		 [[11, 7, 5], [11, 8, 5], [12, 9, 4]]],
	]
	for runs: Array in facets[v]:
		for i in runs.size():
			var rx: int = int(runs[i][0])
			var ry: int = int(runs[i][1])
			var rl: int = int(runs[i][2])
			_run(img, ox, rx, ry, rl, LT)
			if i < 2:
				_px(img, ox, rx, ry, WH)              # lit top-left facet edge
			if i >= runs.size() - 2:
				_px(img, ox, rx + rl - 1, ry, PU)     # shadowed bottom-right edge


func _tile_ultra_dense(img: Image, ox: int, v: int) -> void:
	# Near-black, extreme density, faint gold-amber veining. The old modulo
	# patterns (%11 and %7) did not divide 16, so they visibly reset every cell.
	var B  := Color(0.06, 0.05, 0.04)
	var M  := Color(0.09, 0.08, 0.06)
	var DK := Color(0.03, 0.03, 0.03)
	var GD := Color(0.26, 0.20, 0.07)
	var HI := Color(0.42, 0.33, 0.11)
	var salt := 241 + v * 7
	for y in _S:
		for x in _S:
			var r := _pxhash(x, y, salt) % 100
			var c := B
			if r < 20:
				c = M
			elif r < 28:
				c = DK
			_px(img, ox, x, y, c)
	var veins := [
		[[[3, 11], [4, 10], [5, 10], [6, 9], [7, 9]], [[11, 3], [12, 4], [13, 4]]],
		[[[2, 4], [3, 4], [4, 5], [5, 5], [6, 6]], [[9, 12], [10, 12], [11, 11]]],
		[[[7, 2], [8, 3], [9, 3], [10, 4]], [[3, 13], [4, 13], [5, 12]], [[13, 8], [13, 9]]],
	]
	for vein: Array in veins[v]:
		for i in vein.size():
			var p: Array = vein[i]
			_px(img, ox, int(p[0]), int(p[1]), HI if i == 1 else GD)


func _tile_bedrock(img: Image, ox: int, v: int) -> void:
	# INDESTRUCTIBLE PLATE — the 1px perimeter is KEPT here on purpose. Bedrock is
	# a single bottom border row of engineered plating, not a natural fill, so
	# reading as discrete riveted panels is the intended look (same for the Core
	# Hollow shell below). Do not "de-grid" these two.
	var K  := Color(0.02, 0.02, 0.03)
	var B  := Color(0.08, 0.07, 0.11)
	var G  := Color(0.13, 0.12, 0.17)
	var HL := Color(0.16, 0.15, 0.21)
	var SC := Color(0.10, 0.09, 0.13)
	for y in _S:
		for x in _S:
			# The two variants subdivide the plate differently (2×2 panels vs
			# 3×3) so a run of bedrock is not one repeated stamp. Both periods
			# divide 16, so panel lines still meet across cells.
			var seam: bool = (x % 8 == 0 or y % 8 == 0) if v == 0 else (x % 8 == 4 or y % 8 == 4)
			var rivet: bool = (x % 8 == 1 and y % 8 == 1) if v == 0 else (x % 8 == 5 and y % 8 == 5)
			var c := B
			if x == 0 or y == 0 or x == _S - 1 or y == _S - 1:
				c = K
			elif seam:
				c = G
			elif rivet:
				c = HL
			_px(img, ox, x, y, c)
	var scuffs := [
		[[10, 11], [11, 11], [12, 12]],
		[[3, 11], [4, 10], [5, 9], [11, 4], [12, 5]],
	]
	for p in scuffs[v]:
		_px(img, ox, int(p[0]), int(p[1]), SC)


func _tile_core_hollow_shell(img: Image, ox: int, v: int) -> void:
	# Core Hollow boundary wall — the hardest DRILLABLE terrain. Armoured
	# obsidian-black plate laced with molten cyan seams, visually distinct from
	# indestructible Bedrock. The 1px plate perimeter is KEPT (see _tile_bedrock);
	# only the old fixed white-hot pixel at (2,2) and the 6×6 lit corner block are
	# gone, replaced by a proper 1px inner bevel that belongs to the plate read.
	var K  := Color(0.01, 0.02, 0.03)
	var B  := Color(0.04, 0.06, 0.09)
	var M  := Color(0.07, 0.10, 0.15)
	var PL := Color(0.11, 0.15, 0.22)
	var SM := Color(0.10, 0.55, 0.62)
	var HI := Color(0.55, 0.95, 1.00)
	for y in _S:
		for x in _S:
			# Plate speckle period 8 (divides 16 → continues across cells);
			# the two variants use transposed diagonals so they don't twin.
			var speckle: bool = ((x + y * 2) % 8 == 0) if v == 0 else ((x * 2 + y) % 8 == 0)
			var c := B
			if x == 0 or y == 0 or x == _S - 1 or y == _S - 1:
				c = K
			elif speckle:
				c = M
			_px(img, ox, x, y, c)
	# 1px inner bevel (top + left), the plate's lit edge.
	for i in range(1, _S - 1):
		_px(img, ox, i, 1, PL)
		_px(img, ox, 1, i, PL)
	if v == 0:
		for i in range(1, _S - 1):
			_px(img, ox, i, i, SM)
			var j: int = (_S - 1) - i
			if j > 0 and j < _S - 1:
				_px(img, ox, i, j, SM)
		for p in [[7, 7], [8, 8], [4, 11], [11, 4]]:
			_px(img, ox, int(p[0]), int(p[1]), HI)
	else:
		for i in range(1, _S - 1):
			_px(img, ox, 8, i, SM)
			_px(img, ox, i, 8, SM)
		for p in [[8, 8], [8, 3], [3, 8], [13, 8], [8, 13]]:
			_px(img, ox, int(p[0]), int(p[1]), HI)


func _tile_fallback(img: Image, ox: int, _v: int) -> void:
	for y in _S:
		for x in _S:
			_px(img, ox, x, y, Color(0.50, 0.20, 0.50))


func _blank(width: int, height: int) -> Image:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


# --- Tile operations ---

# Which art variant a cell uses. MUST stay a pure function of (cell, type): the
# world streams columns in and out constantly, so the same cell is re-placed many
# times per match and has to come back identical every time — an RNG or a
# placement counter here would make terrain visibly shimmer as you walk. Cell
# coordinates go negative (streaming wraps left of column 0), hence the mask
# rather than a modulo that could return a negative index.
func _variant_for(cell: Vector2i, type: Constants.TerrainType) -> int:
	var n: int = _variant_count.get(type, 1)
	if n <= 1:
		return 0
	var h: int = ((cell.x * 73856093) ^ (cell.y * 19349663) ^ (int(type) * 83492791)) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return h % n


func place_tile(cell: Vector2i, type: Constants.TerrainType) -> void:
	_tile_registry[cell] = type
	tile_map.set_cell(0, cell, type, Vector2i(_variant_for(cell, type), 0))


func destroy_tile(cell: Vector2i) -> bool:
	if not _tile_registry.has(cell):
		return false
	var type: Constants.TerrainType = _tile_registry[cell]
	if not TerrainTypes.is_destructible(type):
		return false
	_tile_registry.erase(cell)
	tile_map.erase_cell(0, cell)
	tile_destroyed.emit(cell, type)
	return true


func get_tile_type(cell: Vector2i) -> Variant:
	return _tile_registry.get(cell, null)


func has_tile(cell: Vector2i) -> bool:
	return _tile_registry.has(cell)


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i((world_pos / float(Constants.TILE_SIZE)).floor())


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * Constants.TILE_SIZE)


func get_tile_registry() -> Dictionary:
	return _tile_registry


func clear_all() -> void:
	_tile_registry.clear()
	tile_map.clear()


# Called once by WorldGenerator after the canonical world (cols 0..width-1) is
# fully placed. Snapshots the tile data and builds a per-column index for fast
# streaming later.
func init_streaming(world_width: int) -> void:
	_world_width = world_width
	_canonical_tiles = _tile_registry.duplicate()
	for cell: Vector2i in _canonical_tiles:
		var col: int = cell.x
		if not _canonical_by_col.has(col):
			_canonical_by_col[col] = {}
		_canonical_by_col[col][cell.y] = _canonical_tiles[cell]
	for col in range(_world_width):
		_streamed_cols[col] = true


# Lazy variant: accepts pre-computed world data directly from WorldGenerator.
# Tiles are NOT placed into TileMap here — stream_columns() places them on demand.
func init_streaming_lazy(world_data: Dictionary, world_width: int) -> void:
	_world_width = world_width
	_canonical_by_col = world_data


# Returns the canonical world as a nested per-column dict: { col:int -> { row:int -> type } }.
# ChestSpawner scans this directly. Previously a flat Vector2i-keyed dict was built here
# (360k struct allocations + hash inserts every startup) — eliminated by exposing the
# already-built column index by reference instead.
func get_canonical_by_col() -> Dictionary:
	return _canonical_by_col


# Ensures all columns within [center_col - half_range, center_col + half_range]
# exist in the TileMap. Missing columns are filled by repeating the canonical
# column at (col % world_width). O(1) per already-streamed column.
func stream_columns(center_col: int, half_range: int) -> void:
	if _world_width <= 0:
		return
	for col in range(center_col - half_range, center_col + half_range + 1):
		if _streamed_cols.has(col):
			continue
		_streamed_cols[col] = true
		var canonical_col: int = ((col % _world_width) + _world_width) % _world_width
		if not _canonical_by_col.has(canonical_col):
			continue
		var col_data: Dictionary = _canonical_by_col[canonical_col]
		for row: int in col_data:
			place_tile(Vector2i(col, row), col_data[row])
