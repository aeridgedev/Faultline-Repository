## Faultline — places LootDrop nodes at valid chest positions after world generation.
## Spawn chance per tile: Constants.chest_spawn_chance(depth_factor).
## Chests only spawn on solid ground tiles; Core Hollow has no loot.
class_name ChestSpawner
extends RefCounted

const LootDropScene := preload("res://src/systems/loot/LootDrop.tscn")

## Call after WorldGenerator.generate() has run.
## `drop_parent` is the Node2D that will own all LootDrop children (e.g. World).
static func spawn(
		terrain_manager: TerrainManager,
		layer_manager: LayerManager,
		drop_parent: Node2D
) -> void:
	var registry: Dictionary = terrain_manager.get_tile_registry()
	for cell in registry.keys():
		var terrain_type: Constants.TerrainType = registry[cell]
		# Only spawn on the surface of solid tiles (tile above must be empty air).
		var above := Vector2i(cell.x, cell.y - 1)
		if registry.has(above):
			continue  # tile above is also solid — no chest here
		var layer: Constants.Layer = layer_manager.layer_at_y(
				terrain_manager.cell_to_world(cell).y
		)
		if layer == Constants.Layer.CORE_HOLLOW:
			continue  # Core Hollow has no loot
		var depth_factor: float = Constants.LAYER_DEPTH_FACTOR.get(layer, 0.0)
		var chance: float = Constants.chest_spawn_chance(depth_factor)
		if randf() > chance:
			continue
		_place_drop(cell, layer, terrain_manager, drop_parent)


static func _place_drop(
		cell: Vector2i,
		layer: Constants.Layer,
		terrain_manager: TerrainManager,
		drop_parent: Node2D
) -> void:
	var drop := LootDropScene.instantiate() as LootDrop
	drop.source_layer = layer
	drop.item_data = LootTable.roll(layer)
	# Add to tree first so global_position resolves correctly against drop_parent's transform.
	drop_parent.add_child(drop)
	# Center the drop in the empty tile directly above the surface tile.
	var half: float = Constants.TILE_SIZE / 2.0
	drop.global_position = terrain_manager.cell_to_world(cell) + Vector2(half, -half)
