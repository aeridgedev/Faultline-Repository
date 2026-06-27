## Faultline — places Chest nodes at valid surface positions after world generation.
## A "surface" tile is any solid tile whose tile directly above is empty air.
## Spawn chance per eligible tile: Constants.chest_spawn_chance(depth_factor).
## Core Hollow has no loot.
##
## Density limiter: the world is divided into 6×6-tile slots; at most one chest
## is placed per slot. This keeps chest counts reasonable even with a heavily
## caved terrain (where hundreds of surface tiles would otherwise all roll).
class_name ChestSpawner
extends RefCounted

const ChestScene := preload("res://src/systems/loot/Chest.tscn")

## Minimum tile-grid spacing: one chest per NxN block of cells.
const SLOT_SIZE := 6


## Call after WorldGenerator.generate() has run.
## `chest_parent` is the Node2D that will own all Chest children (e.g. World).
static func spawn(
		terrain_manager: TerrainManager,
		layer_manager: LayerManager,
		chest_parent: Node2D
) -> void:
	var registry: Dictionary = terrain_manager.get_tile_registry()

	# Collect candidate surface tiles grouped by 6×6 slot.
	# slot key = Vector2i(col / SLOT_SIZE, row / SLOT_SIZE)
	var slots: Dictionary = {}   # slot_key -> Array of {cell, layer}

	for cell in registry.keys():
		# Surface check: tile directly above must be empty air.
		var above := Vector2i(cell.x, cell.y - 1)
		if registry.has(above):
			continue

		var world_y: float = terrain_manager.cell_to_world(cell).y
		var layer: Constants.Layer = layer_manager.layer_at_y(world_y)
		if layer == Constants.Layer.CORE_HOLLOW:
			continue  # no loot in Core Hollow

		var slot_key := Vector2i(cell.x / SLOT_SIZE, cell.y / SLOT_SIZE)
		if not slots.has(slot_key):
			slots[slot_key] = []
		slots[slot_key].append({"cell": cell, "layer": layer})

	# One roll per slot — pick a random candidate from the slot, then apply
	# the layer spawn-chance formula. This distributes chests evenly without
	# flooding every tunnel floor.
	for slot_key in slots:
		var candidates: Array = slots[slot_key]
		if candidates.is_empty():
			continue
		# Pick a random candidate from this slot.
		var pick: Dictionary = candidates[randi() % candidates.size()]
		var layer: Constants.Layer = pick["layer"]
		var depth_factor: float = Constants.LAYER_DEPTH_FACTOR.get(layer, 0.0)
		var chance: float = Constants.chest_spawn_chance(depth_factor)
		if randf() > chance:
			continue
		_place_chest(pick["cell"], layer, terrain_manager, chest_parent)


static func _place_chest(
		cell: Vector2i,
		layer: Constants.Layer,
		terrain_manager: TerrainManager,
		chest_parent: Node2D
) -> void:
	var chest := ChestScene.instantiate() as Chest
	# Populate before add_child so Chest._ready() reads the correct item_data.
	chest.source_layer = layer
	chest.item_data = LootTable.roll(layer)
	chest_parent.add_child(chest)
	# Centre the chest in the air tile directly above the surface tile.
	var half := float(Constants.TILE_SIZE) * 0.5
	chest.global_position = terrain_manager.cell_to_world(cell) + Vector2(half, -half)
