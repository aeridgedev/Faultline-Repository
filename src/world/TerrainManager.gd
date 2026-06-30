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
]


func _ready() -> void:
	_build_dev_tileset()


func _build_dev_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)

	var half := Constants.TILE_SIZE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half,  half),  Vector2(-half, half),
	])

	for terrain_type in _TILE_TYPES:
		var tex := ImageTexture.create_from_image(_make_tile(terrain_type))
		var source := TileSetAtlasSource.new()
		source.texture = tex
		source.texture_region_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
		source.create_tile(Vector2i.ZERO)
		ts.add_source(source, terrain_type)
		var tile_data: TileData = source.get_tile_data(Vector2i.ZERO, 0)
		tile_data.add_collision_polygon(0)
		tile_data.set_collision_polygon_points(0, 0, square)
	tile_map.tile_set = ts


func _make_tile(type: Constants.TerrainType) -> Image:
	match type:
		Constants.TerrainType.SOIL:           return _tile_soil()
		Constants.TerrainType.CLAY:           return _tile_clay()
		Constants.TerrainType.LIMESTONE:      return _tile_limestone()
		Constants.TerrainType.ROCK:           return _tile_rock()
		Constants.TerrainType.BASALT:         return _tile_basalt()
		Constants.TerrainType.GRANITE:        return _tile_granite()
		Constants.TerrainType.OBSIDIAN:       return _tile_obsidian()
		Constants.TerrainType.IRON_FORMATION: return _tile_iron_formation()
		Constants.TerrainType.DENSE_CRYSTAL:  return _tile_dense_crystal()
		Constants.TerrainType.ULTRA_DENSE:    return _tile_ultra_dense()
		Constants.TerrainType.BEDROCK:        return _tile_bedrock()
		_:                                    return _tile_fallback()


# --- Terrain tile painters ---
# Each paints a 16×16 pixel-art image. Light source: top-left. Border: 1px dark outline.

func _tile_soil() -> Image:
	const S := 16
	var K  := Color(0.06, 0.04, 0.02)
	var D  := Color(0.25, 0.13, 0.04)
	var B  := Color(0.44, 0.27, 0.11)
	var M  := Color(0.52, 0.34, 0.16)
	var LT := Color(0.64, 0.44, 0.22)
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif y <= 2:
				img.set_pixel(x, y, LT)
			elif y >= S - 3:
				img.set_pixel(x, y, D)
			else:
				img.set_pixel(x, y, B if (x + y) % 3 != 0 else M)
	for gp in [[3,4],[7,3],[11,5],[5,9],[13,7],[2,12],[9,10],[14,4],[6,13]]:
		if gp[0] > 0 and gp[1] > 0 and gp[0] < S-1 and gp[1] < S-1:
			img.set_pixel(gp[0], gp[1], D)
	return img


func _tile_clay() -> Image:
	# Warm reddish-brown, compact, slight horizontal layering.
	const S := 16
	var K  := Color(0.06, 0.03, 0.01)
	var B  := Color(0.52, 0.27, 0.12)   # warm clay base
	var L  := Color(0.62, 0.35, 0.18)   # lighter stripe
	var D  := Color(0.40, 0.20, 0.08)   # darker stripe
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif y % 5 == 1:
				img.set_pixel(x, y, L)
			elif y % 5 == 4:
				img.set_pixel(x, y, D)
			else:
				img.set_pixel(x, y, B)
	# Subtle horizontal moisture crack
	for x in range(3, 13):
		img.set_pixel(x, 8, D)
	return img


func _tile_limestone() -> Image:
	# Light gray-tan sedimentary with strong horizontal strata.
	const S := 16
	var K  := Color(0.05, 0.05, 0.04)
	var B  := Color(0.68, 0.63, 0.50)   # warm gray base
	var L  := Color(0.76, 0.72, 0.60)   # light stratum
	var D  := Color(0.54, 0.50, 0.38)   # dark seam
	var HI := Color(0.85, 0.82, 0.72)   # highlight
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif y % 4 == 0:
				img.set_pixel(x, y, D)
			elif y % 4 == 1:
				img.set_pixel(x, y, L)
			else:
				img.set_pixel(x, y, B)
	img.set_pixel(2, 2, HI)
	img.set_pixel(3, 2, HI)
	return img


func _tile_rock() -> Image:
	const S := 16
	var K  := Color(0.06, 0.06, 0.07)
	var SH := Color(0.28, 0.28, 0.30)
	var B  := Color(0.44, 0.44, 0.47)
	var M  := Color(0.52, 0.52, 0.55)
	var LT := Color(0.66, 0.66, 0.70)
	var HI := Color(0.80, 0.80, 0.84)
	var CK := Color(0.22, 0.22, 0.24)
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif x < 6 and y < 6:
				img.set_pixel(x, y, LT)
			elif x > 10 or y > 10:
				img.set_pixel(x, y, SH)
			elif (x + y * 2) % 7 == 0:
				img.set_pixel(x, y, M)
			else:
				img.set_pixel(x, y, B)
	img.set_pixel(2, 2, HI)
	img.set_pixel(3, 2, HI)
	for i in range(5):
		var cx := 5 + i; var cy := 4 + i
		if cx < S-1 and cy < S-1:
			img.set_pixel(cx, cy, CK)
	img.set_pixel(9, 10, CK)
	return img


func _tile_basalt() -> Image:
	# Very dark blue-gray volcanic igneous rock with hexagonal crack pattern.
	const S := 16
	var K  := Color(0.02, 0.02, 0.03)
	var B  := Color(0.12, 0.14, 0.18)   # dark blue-gray base
	var CK := Color(0.06, 0.07, 0.10)   # crack (darker)
	var LT := Color(0.20, 0.23, 0.28)   # highlight patch
	var HI := Color(0.28, 0.32, 0.38)   # corner catch-light
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			else:
				img.set_pixel(x, y, B)
	# Hexagonal-ish crack network
	for p in [[2,5],[3,5],[4,5],[5,4],[5,3],[5,2],
			   [5,10],[6,10],[7,10],[8,11],[9,11],
			   [10,6],[10,7],[10,8],[11,8],[11,9],[11,10],
			   [2,10],[3,11],[3,12]]:
		if p[0] > 0 and p[1] > 0 and p[0] < S-1 and p[1] < S-1:
			img.set_pixel(p[0], p[1], CK)
	img.set_pixel(2, 2, HI)
	img.set_pixel(3, 2, LT)
	img.set_pixel(2, 3, LT)
	return img


func _tile_granite() -> Image:
	# Medium dark gray with pink feldspar and white quartz speckles.
	const S := 16
	var K  := Color(0.04, 0.04, 0.04)
	var B  := Color(0.38, 0.37, 0.37)   # gray base
	var PK := Color(0.58, 0.38, 0.36)   # pink feldspar
	var WH := Color(0.72, 0.72, 0.73)   # white quartz
	var DK := Color(0.20, 0.19, 0.20)   # dark mica
	var LT := Color(0.50, 0.49, 0.50)   # light patch
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			else:
				img.set_pixel(x, y, B)
	# Speckle pattern — feldspar (pink), quartz (white), mica (dark)
	for p in [[2,3],[6,2],[10,4],[13,2],[14,8]]:
		img.set_pixel(p[0], p[1], PK)
		if p[0]+1 < S-1: img.set_pixel(p[0]+1, p[1], PK)
	for p in [[4,6],[8,5],[12,7],[3,11],[9,13]]:
		img.set_pixel(p[0], p[1], WH)
	for p in [[2,8],[5,4],[7,9],[11,3],[13,11]]:
		img.set_pixel(p[0], p[1], DK)
	img.set_pixel(2, 2, LT)
	return img


func _tile_obsidian() -> Image:
	# Near-black with purple-violet glass sheen and sharp specular highlights.
	const S := 16
	var K  := Color(0.01, 0.01, 0.02)
	var B  := Color(0.05, 0.03, 0.08)   # very dark purple-black
	var PU := Color(0.12, 0.07, 0.20)   # subtle purple tint
	var SH := Color(0.22, 0.12, 0.38)   # specular patch
	var WH := Color(0.75, 0.65, 0.95)   # glass highlight
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif x + y < 6:
				img.set_pixel(x, y, SH)   # bright upper-left region
			elif (x + y) % 9 == 0:
				img.set_pixel(x, y, PU)
			else:
				img.set_pixel(x, y, B)
	# Glass specular highlights
	img.set_pixel(2, 2, WH)
	img.set_pixel(3, 2, SH)
	img.set_pixel(2, 3, SH)
	img.set_pixel(5, 1, WH)
	img.set_pixel(1, 5, SH)
	return img


func _tile_iron_formation() -> Image:
	# Dark rust-red base with horizontal gray metallic veins.
	const S := 16
	var K  := Color(0.04, 0.02, 0.01)
	var B  := Color(0.32, 0.14, 0.06)   # rust-red base
	var OR := Color(0.48, 0.24, 0.08)   # brighter orange-red
	var MG := Color(0.35, 0.34, 0.36)   # gray metallic vein
	var LM := Color(0.48, 0.46, 0.50)   # lighter metallic
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif y % 5 == 2:
				img.set_pixel(x, y, MG)   # horizontal metallic band
			elif y % 5 == 3:
				img.set_pixel(x, y, LM)
			elif (x + y) % 4 == 0:
				img.set_pixel(x, y, OR)
			else:
				img.set_pixel(x, y, B)
	# Metallic sheen catch-light
	img.set_pixel(2, 2, LM)
	img.set_pixel(3, 2, MG)
	return img


func _tile_dense_crystal() -> Image:
	# Deep teal with sharp angular facets — darker and more fractured than old Crystal.
	const S := 16
	var K  := Color(0.02, 0.08, 0.14)
	var D  := Color(0.04, 0.14, 0.24)   # very dark teal
	var B  := Color(0.08, 0.24, 0.40)   # base teal
	var LT := Color(0.16, 0.42, 0.58)   # brighter facet
	var WH := Color(0.60, 0.88, 0.95)   # specular
	var PU := Color(0.18, 0.16, 0.40)   # purple tint in shadow
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			else:
				var t := float(x + y) / float(S * 2)
				img.set_pixel(x, y, LT.lerp(D, t))
	# Angular facet lines (sharper than old Crystal)
	for i in range(3, 13):
		img.set_pixel(i, 15 - i, PU if (15 - i) > 0 and (15 - i) < S-1 else K)
	for i in range(1, 7):
		if i > 0 and i < S-1 and (3+i) < S-1:
			img.set_pixel(i, 3 + i, D)
	# Specular highlights
	img.set_pixel(2, 2, WH)
	img.set_pixel(3, 2, LT)
	img.set_pixel(2, 3, LT)
	return img


func _tile_ultra_dense() -> Image:
	# Near-black with faint gold-amber metallic sheen — extreme density.
	const S := 16
	var K  := Color(0.01, 0.01, 0.01)
	var B  := Color(0.06, 0.05, 0.04)   # near-black warm base
	var M  := Color(0.10, 0.08, 0.05)   # very subtle pattern
	var GD := Color(0.28, 0.22, 0.08)   # muted gold vein
	var HI := Color(0.45, 0.36, 0.12)   # gold highlight
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif (x * 3 + y * 5) % 11 == 0:
				img.set_pixel(x, y, GD)   # scattered gold veins
			elif (x + y * 2) % 7 == 0:
				img.set_pixel(x, y, M)
			else:
				img.set_pixel(x, y, B)
	# Faint gold catch-light — barely readable
	img.set_pixel(2, 2, HI)
	img.set_pixel(3, 2, GD)
	return img


func _tile_bedrock() -> Image:
	const S := 16
	var K  := Color(0.02, 0.02, 0.03)
	var B  := Color(0.08, 0.07, 0.11)
	var G  := Color(0.13, 0.12, 0.17)
	var HL := Color(0.16, 0.15, 0.21)
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif x % 8 == 0 or y % 8 == 0:
				img.set_pixel(x, y, G)
			elif x % 8 == 1 and y % 8 == 1:
				img.set_pixel(x, y, HL)
			else:
				img.set_pixel(x, y, B)
	return img


func _tile_fallback() -> Image:
	const S := 16
	var img := _blank(S)
	img.fill(Color(0.50, 0.20, 0.50))
	return img


func _blank(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


# --- Tile operations ---

func place_tile(cell: Vector2i, type: Constants.TerrainType) -> void:
	_tile_registry[cell] = type
	tile_map.set_cell(0, cell, type, Vector2i.ZERO)


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
