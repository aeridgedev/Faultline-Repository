## Faultline — owns and mutates the TileMap; single interface for terrain state.
class_name TerrainManager
extends Node

signal tile_destroyed(cell: Vector2i, type: Constants.TerrainType)

@onready var tile_map: TileMap = $TileMap

var _tile_registry: Dictionary = {}

# All terrain types that receive tiles. Bedrock and any future types auto-registered here.
const _TILE_TYPES: Array[Constants.TerrainType] = [
	Constants.TerrainType.SOIL,
	Constants.TerrainType.ROCK,
	Constants.TerrainType.DENSE_ROCK,
	Constants.TerrainType.CRYSTAL,
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
		Constants.TerrainType.SOIL:       return _tile_soil()
		Constants.TerrainType.ROCK:       return _tile_rock()
		Constants.TerrainType.DENSE_ROCK: return _tile_dense_rock()
		Constants.TerrainType.CRYSTAL:    return _tile_crystal()
		Constants.TerrainType.BEDROCK:    return _tile_bedrock()
		_:                                return _tile_fallback()


# --- Terrain tile painters ---
# Each paints a 16×16 image. Light source: top-left. Border: 1px dark outline.

func _tile_soil() -> Image:
	const S := 16
	var K  := Color(0.06, 0.04, 0.02)   # border
	var D  := Color(0.25, 0.13, 0.04)   # dark grain
	var B  := Color(0.44, 0.27, 0.11)   # base
	var M  := Color(0.52, 0.34, 0.16)   # mid
	var LT := Color(0.64, 0.44, 0.22)   # lit top
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
	# Deterministic grain scatter — gives organic earthy look
	for gp in [[3,4],[7,3],[11,5],[5,9],[13,7],[2,12],[9,10],[14,4],[6,13]]:
		if gp[0] > 0 and gp[1] > 0 and gp[0] < S-1 and gp[1] < S-1:
			img.set_pixel(gp[0], gp[1], D)
	return img


func _tile_rock() -> Image:
	const S := 16
	var K  := Color(0.06, 0.06, 0.07)
	var SH := Color(0.28, 0.28, 0.30)   # shadow
	var B  := Color(0.44, 0.44, 0.47)   # base
	var M  := Color(0.52, 0.52, 0.55)   # mid
	var LT := Color(0.66, 0.66, 0.70)   # lit
	var HI := Color(0.80, 0.80, 0.84)   # highlight pixel
	var CK := Color(0.22, 0.22, 0.24)   # crack
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif x < 6 and y < 6:
				img.set_pixel(x, y, LT)  # lit quadrant
			elif x > 10 or y > 10:
				img.set_pixel(x, y, SH)  # shadow quadrant
			elif (x + y * 2) % 7 == 0:
				img.set_pixel(x, y, M)
			else:
				img.set_pixel(x, y, B)
	# Highlight corner pixel
	img.set_pixel(2, 2, HI)
	img.set_pixel(3, 2, HI)
	# Diagonal crack
	for i in range(5):
		var cx := 5 + i; var cy := 4 + i
		if cx < S-1 and cy < S-1:
			img.set_pixel(cx, cy, CK)
	img.set_pixel(9, 10, CK)
	return img


func _tile_dense_rock() -> Image:
	const S := 16
	var K  := Color(0.04, 0.04, 0.05)
	var B  := Color(0.16, 0.15, 0.20)   # very dark base
	var M  := Color(0.21, 0.20, 0.26)   # crosshatch
	var LT := Color(0.28, 0.27, 0.34)   # corner highlight
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif (x % 4 == 0) or (y % 4 == 0):
				img.set_pixel(x, y, M)  # subtle crosshatch
			else:
				img.set_pixel(x, y, B)
	# Single bright corner — just barely readable
	img.set_pixel(2, 2, LT)
	img.set_pixel(3, 2, M)
	img.set_pixel(2, 3, M)
	return img


func _tile_crystal() -> Image:
	const S := 16
	var K  := Color(0.05, 0.18, 0.28)   # dark teal border
	var D  := Color(0.10, 0.36, 0.50)   # dark inner
	var B  := Color(0.22, 0.62, 0.78)   # base
	var LT := Color(0.40, 0.82, 0.90)   # bright
	var SH := Color(0.08, 0.42, 0.58)   # shine gradient start
	var WH := Color(0.82, 0.97, 1.00)   # specular highlight
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			else:
				var t := float(x + y) / float(S * 2 - 2)
				var c := LT.lerp(D, t)
				img.set_pixel(x, y, c)
	# Inner facet shape — diamond of brighter pixels
	for y in range(4, 12):
		for x in range(4, 12):
			var dx: int = abs(x - 7) + abs(y - 7)
			if dx < 4:
				var cur := img.get_pixel(x, y)
				img.set_pixel(x, y, cur.lightened(0.15))
	# Specular highlights — 3 bright pixels upper-left
	img.set_pixel(2, 2, WH)
	img.set_pixel(3, 2, SH.lerp(WH, 0.6))
	img.set_pixel(2, 3, SH.lerp(WH, 0.6))
	img.set_pixel(4, 3, LT)
	return img


func _tile_bedrock() -> Image:
	const S := 16
	var K  := Color(0.02, 0.02, 0.03)
	var B  := Color(0.08, 0.07, 0.11)   # near-black base
	var G  := Color(0.13, 0.12, 0.17)   # block seam lines
	var HL := Color(0.16, 0.15, 0.21)   # seam highlight
	var img := _blank(S)
	for y in S:
		for x in S:
			if x == 0 or y == 0 or x == S-1 or y == S-1:
				img.set_pixel(x, y, K)
			elif x % 8 == 0 or y % 8 == 0:
				img.set_pixel(x, y, G)   # block grid seams
			elif x % 8 == 1 and y % 8 == 1:
				img.set_pixel(x, y, HL)  # seam corner catch-light
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
