## Faultline — procedural terrain generation; fills TerrainManager via place_tile.
##
## World shape: cylindrical — left and right edges connect seamlessly.
##   Bedrock only bounds the bottom row.
##   Cave tunnels wrap around the horizontal axis so no seam is visible.
##   Horizontal rock bands every 8–14 rows discourage pure vertical drilling.
##
## Each non-hollow layer gets:
##   1. A terrain-type fill weighted by depth (harder terrain deeper).
##   2. A cave pass: wrapping horizontal tunnels + vertical shafts.
##   3. Horizontal rock bands of harder terrain to break up vertical corridors.
class_name WorldGenerator
extends RefCounted

var _terrain_manager: TerrainManager
var _layer_manager: LayerManager
var _rng: RandomNumberGenerator


func generate(terrain_manager: TerrainManager, layer_manager: LayerManager, seed_value: int) -> void:
	_terrain_manager = terrain_manager
	_layer_manager   = layer_manager
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

	for layer in Constants.Layer.values():
		if layer == Constants.Layer.CORE_HOLLOW:
			_generate_core_hollow()
		else:
			_generate_layer(layer, _rng)

	_place_bedrock_border()
	_terrain_manager.init_streaming(_world_width_tiles())


func _generate_layer(layer: Constants.Layer, rng: RandomNumberGenerator) -> void:
	var top_y    = _layer_manager.get_layer_top_y(layer)
	var bottom_y = _layer_manager.get_layer_bottom_y(layer)
	if top_y == null or bottom_y == null:
		return

	var top_tile: int    = int(top_y) / Constants.TILE_SIZE
	var bottom_tile: int = int(bottom_y) / Constants.TILE_SIZE
	var width: int = _world_width_tiles()
	if width == 0:
		return

	var air_cells: Dictionary = _carve_caves(top_tile, bottom_tile, width, rng)
	var band_rows: Dictionary = _compute_rock_bands(top_tile, bottom_tile, rng)
	var band_type: Constants.TerrainType = _band_terrain_for_layer(layer)

	for row in range(top_tile, bottom_tile):
		for col in range(width):
			var cell := Vector2i(col, row)
			if air_cells.has(cell):
				continue
			var terrain: Constants.TerrainType
			if band_rows.has(row):
				terrain = band_type
			else:
				terrain = _pick_terrain(layer, rng)
			_terrain_manager.place_tile(cell, terrain)


# ---------------------------------------------------------------------------
# Core Hollow — circular bedrock-walled chamber, open interior, zero gravity.
# ---------------------------------------------------------------------------
func _generate_core_hollow() -> void:
	var top_y    = _layer_manager.get_layer_top_y(Constants.Layer.CORE_HOLLOW)
	var bottom_y = _layer_manager.get_layer_bottom_y(Constants.Layer.CORE_HOLLOW)
	if top_y == null or bottom_y == null:
		return

	var top_tile    := int(top_y)    / Constants.TILE_SIZE
	var bottom_tile := int(bottom_y) / Constants.TILE_SIZE
	var width       := _world_width_tiles()
	if width == 0:
		return

	var center_col := width / 2
	var center_row := (top_tile + bottom_tile) / 2
	var max_v := (bottom_tile - top_tile) / 2 - 2
	var max_h := width / 2 - 2
	var hollow_r := mini(max_v, max_h)

	for row in range(top_tile, bottom_tile):
		for col in range(width):
			var dx := col - center_col
			var dy := row - center_row
			if dx * dx + dy * dy > hollow_r * hollow_r:
				_terrain_manager.place_tile(Vector2i(col, row), Constants.TerrainType.BEDROCK)


# ---------------------------------------------------------------------------
# Cave carver — wrapping horizontal tunnels + vertical shafts.
# Tunnels use col % width so they continue seamlessly across the seam.
# ---------------------------------------------------------------------------
func _carve_caves(top_tile: int, bottom_tile: int, width: int, rng: RandomNumberGenerator) -> Dictionary:
	var air := {}

	# Horizontal tunnels that wrap around the cylinder.
	var row: int = top_tile + 3
	while row < bottom_tile - 2:
		var tunnel_h: int = 2 + (1 if rng.randf() < 0.3 else 0)
		# Start at a random column and traverse the full width once.
		var col: int = rng.randi_range(0, width - 1)
		var travelled := 0
		while travelled < width:
			# Solid pillar segment.
			var pillar := rng.randi_range(3, 7)
			col = (col + pillar) % width
			travelled += pillar
			if travelled >= width:
				break
			# Open passage segment (wraps if it crosses col=0/width boundary).
			var open_len: int = mini(rng.randi_range(8, 24), width - travelled)
			for _i in range(open_len):
				for dy in range(tunnel_h):
					air[Vector2i(col, row + dy)] = true
				col = (col + 1) % width
				travelled += 1
		row += rng.randi_range(4, 8)

	# Vertical shafts — guaranteed descent paths, one may straddle the seam.
	var shaft_count: int = rng.randi_range(4, 6)
	for _i in range(shaft_count):
		var sx: int = rng.randi_range(0, width - 1)
		for sr in range(top_tile + 2, bottom_tile - 1):
			air[Vector2i(sx,               sr)] = true
			air[Vector2i((sx + 1) % width, sr)] = true

	return air


# ---------------------------------------------------------------------------
# Rock bands — horizontal rows of harder terrain every 8–14 rows.
# ---------------------------------------------------------------------------
func _compute_rock_bands(top_tile: int, bottom_tile: int, rng: RandomNumberGenerator) -> Dictionary:
	var bands := {}
	var row := top_tile + 6
	while row < bottom_tile - 4:
		for dy in 2:
			bands[row + dy] = true
		row += rng.randi_range(8, 14)
	return bands


func _band_terrain_for_layer(layer: Constants.Layer) -> Constants.TerrainType:
	match layer:
		Constants.Layer.CRUST:      return Constants.TerrainType.LIMESTONE
		Constants.Layer.MANTLE:     return Constants.TerrainType.GRANITE
		Constants.Layer.OUTER_CORE: return Constants.TerrainType.OBSIDIAN
		Constants.Layer.INNER_CORE: return Constants.TerrainType.ULTRA_DENSE
		_:                          return Constants.TerrainType.ROCK


# ---------------------------------------------------------------------------
# Terrain picker — layer-appropriate type distribution.
# ---------------------------------------------------------------------------
func _pick_terrain(layer: Constants.Layer, rng: RandomNumberGenerator) -> Constants.TerrainType:
	if GameManager.data != null:
		var key: String = "terrain_weights_" + Constants.LAYER_NAMES[layer].to_lower().replace(" ", "_")
		var weights = GameManager.data.get(key, null)
		if weights != null:
			return _pick_terrain_type(weights, rng)

	var r := rng.randf()
	match layer:
		Constants.Layer.CRUST:
			if r < 0.50: return Constants.TerrainType.SOIL
			if r < 0.78: return Constants.TerrainType.CLAY
			return Constants.TerrainType.LIMESTONE

		Constants.Layer.MANTLE:
			if r < 0.10: return Constants.TerrainType.CLAY
			if r < 0.35: return Constants.TerrainType.LIMESTONE
			if r < 0.68: return Constants.TerrainType.ROCK
			if r < 0.88: return Constants.TerrainType.BASALT
			return Constants.TerrainType.GRANITE

		Constants.Layer.OUTER_CORE:
			if r < 0.08: return Constants.TerrainType.ROCK
			if r < 0.22: return Constants.TerrainType.BASALT
			if r < 0.42: return Constants.TerrainType.GRANITE
			if r < 0.60: return Constants.TerrainType.OBSIDIAN
			if r < 0.78: return Constants.TerrainType.IRON_FORMATION
			return Constants.TerrainType.DENSE_CRYSTAL

		Constants.Layer.INNER_CORE:
			if r < 0.06: return Constants.TerrainType.GRANITE
			if r < 0.20: return Constants.TerrainType.OBSIDIAN
			if r < 0.38: return Constants.TerrainType.IRON_FORMATION
			if r < 0.55: return Constants.TerrainType.DENSE_CRYSTAL
			return Constants.TerrainType.ULTRA_DENSE

		_:
			return Constants.TerrainType.SOIL


func _pick_terrain_type(weights: Dictionary, rng: RandomNumberGenerator) -> Constants.TerrainType:
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var roll := rng.randf() * total
	var cumulative := 0.0
	for type_key in weights:
		cumulative += float(weights[type_key])
		if roll < cumulative:
			return type_key as Constants.TerrainType
	return Constants.TerrainType.SOIL


# ---------------------------------------------------------------------------
# Bedrock border — cylindrical world: only the bottom row is bounded.
# No left/right bedrock walls; terrain wraps seamlessly.
# ---------------------------------------------------------------------------
func _place_bedrock_border() -> void:
	var width: int = _world_width_tiles()
	if width == 0:
		return

	var world_h = _layer_manager.world_height_px()
	if world_h == null:
		return

	var total_rows: int = int(world_h) / Constants.TILE_SIZE

	for col in range(width):
		_terrain_manager.place_tile(Vector2i(col, total_rows - 1), Constants.TerrainType.BEDROCK)


func _world_width_tiles() -> int:
	return GameManager.data.get("world_width_tiles", 0) if GameManager.data != null else 0
