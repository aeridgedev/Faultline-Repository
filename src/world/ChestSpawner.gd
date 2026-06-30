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
	# Scan the canonical world by column. Working directly on the nested
	# { col -> { row -> type } } index avoids allocating a 360k-element keys()
	# array and a Vector2i per tile — surface tiles (the only ones we keep) are
	# a tiny fraction of the world.
	var by_col: Dictionary = terrain_manager.get_canonical_by_col()

	# Collect candidate surface tiles grouped by 6×6 slot.
	# slot key = Vector2i(col / SLOT_SIZE, row / SLOT_SIZE)
	var slots: Dictionary = {}   # slot_key -> Array of {cell, layer}
	var tile_total := 0

	for col in by_col:
		var col_data: Dictionary = by_col[col]
		tile_total += col_data.size()
		for row in col_data:
			# Surface check: tile directly above must be empty air (absent here).
			if col_data.has(row - 1):
				continue

			var world_y: float = float(row * Constants.TILE_SIZE)
			var layer: Constants.Layer = layer_manager.layer_at_y(world_y)
			if layer == Constants.Layer.CORE_HOLLOW:
				continue  # no loot in Core Hollow

			var slot_key := Vector2i(col / SLOT_SIZE, row / SLOT_SIZE)
			if not slots.has(slot_key):
				slots[slot_key] = []
			slots[slot_key].append({"cell": Vector2i(col, row), "layer": layer})

	print("[ChestSpawner] registry=%d tiles, slots=%d" % [tile_total, slots.size()])

	# One roll per slot — pick a random candidate from the slot, then apply
	# the layer spawn-chance formula. This distributes chests evenly without
	# flooding every tunnel floor.
	var placed := 0
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
		placed += 1
	print("[ChestSpawner] placed %d chests" % placed)


static func _place_chest(
		cell: Vector2i,
		layer: Constants.Layer,
		terrain_manager: TerrainManager,
		chest_parent: Node2D
) -> void:
	var chest := ChestScene.instantiate() as Chest
	if chest == null:
		push_error("[ChestSpawner] Chest.tscn failed to instantiate as Chest at %s — check Chest.gd for parse errors" % str(cell))
		return
	# Populate before add_child so Chest._ready() reads the correct item_data.
	chest.source_layer = layer
	chest.item_data = LootTable.roll(layer)
	chest_parent.add_child(chest)
	# Centre the chest in the air tile directly above the surface tile.
	var half := float(Constants.TILE_SIZE) * 0.5
	chest.global_position = terrain_manager.cell_to_world(cell) + Vector2(half, -half)
