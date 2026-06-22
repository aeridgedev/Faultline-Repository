## Faultline — owns and mutates the TileMap; single interface for terrain state.
class_name TerrainManager
extends Node

signal tile_destroyed(cell: Vector2i, type: Constants.TerrainType)

@onready var tile_map: TileMap = $TileMap

var _tile_registry: Dictionary = {}


func place_tile(cell: Vector2i, type: Constants.TerrainType) -> void:
	_tile_registry[cell] = type
	# TBD(art): set correct source_id and atlas_coords per terrain type
	tile_map.set_cell(0, cell, 0, Vector2i.ZERO)


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
