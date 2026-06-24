## Faultline — owns and mutates the TileMap; single interface for terrain state.
class_name TerrainManager
extends Node

signal tile_destroyed(cell: Vector2i, type: Constants.TerrainType)

@onready var tile_map: TileMap = $TileMap

var _tile_registry: Dictionary = {}

# Placeholder colors per terrain type for dev visibility. Replaced by real art assets.
var _DEV_COLORS: Dictionary


func _ready() -> void:
	_DEV_COLORS = {
		Constants.TerrainType.SOIL:       Color(0.55, 0.40, 0.25),
		Constants.TerrainType.ROCK:       Color(0.45, 0.45, 0.45),
		Constants.TerrainType.DENSE_ROCK: Color(0.30, 0.30, 0.32),
		Constants.TerrainType.CRYSTAL:    Color(0.40, 0.70, 0.85),
		Constants.TerrainType.BEDROCK:    Color(0.15, 0.15, 0.15),
	}
	_build_dev_tileset()


func _build_dev_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
	# Physics layer so the TileMap is solid — players collide with terrain.
	# Explicitly place it on collision layer/mask 1 (the player's default) so the
	# generated static body actually blocks the player.
	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)

	var half := Constants.TILE_SIZE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])

	# One atlas source per terrain type, each a shaded 16×16 block tile.
	# IMPORTANT: the source must be added to the TileSet *before* configuring tile
	# collision — only then does the tile data know physics layer 0 exists.
	for terrain_type in _DEV_COLORS:
		var tex := ImageTexture.create_from_image(_make_block_image(_DEV_COLORS[terrain_type]))
		var source := TileSetAtlasSource.new()
		source.texture = tex
		source.texture_region_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
		source.create_tile(Vector2i.ZERO)
		ts.add_source(source, terrain_type)
		var tile_data: TileData = source.get_tile_data(Vector2i.ZERO, 0)
		tile_data.add_collision_polygon(0)
		tile_data.set_collision_polygon_points(0, 0, square)
	tile_map.tile_set = ts


# Builds a 16×16 block: a lit top edge, a shaded bottom edge, and a darker
# 1px border so adjacent tiles read as distinct blocks instead of one flat slab.
func _make_block_image(base: Color) -> Image:
	var size := Constants.TILE_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var lit := base.lightened(0.18)
	var shaded := base.darkened(0.22)
	var border := base.darkened(0.40)
	for y in range(size):
		for x in range(size):
			var c := base
			if x == 0 or y == 0 or x == size - 1 or y == size - 1:
				c = border
			elif y <= 2:
				c = lit
			elif y >= size - 3:
				c = shaded
			img.set_pixel(x, y, c)
	return img


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
	return Vector2i(world_pos / Constants.TILE_SIZE)


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * Constants.TILE_SIZE)


func get_tile_registry() -> Dictionary:
	return _tile_registry


func clear_all() -> void:
	_tile_registry.clear()
	tile_map.clear()
