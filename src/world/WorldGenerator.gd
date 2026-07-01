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

# DEV-ONLY: number of TestDummy combat targets placed per non-Core-Hollow layer,
# spread across the layer for kill-count testing. Remove with the dummies once
# networked players exist.
const DUMMIES_PER_LAYER := 6


## Returns an Array of Vector2 world-space positions for TestDummy spawning
## (DUMMIES_PER_LAYER per non-Core-Hollow layer).
func generate(terrain_manager: TerrainManager, layer_manager: LayerManager, seed_value: int) -> Array:
	_terrain_manager = terrain_manager
	_layer_manager   = layer_manager
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

	# Build the full world layout into a per-column dict WITHOUT touching TileMap.
	# Avoids ~360k tile_map.set_cell() calls on startup which block the main thread.
	var world_data: Dictionary = {}   # col_int -> { row_int: TerrainType }
	var dummy_positions: Array = []   # Vector2 world-space positions

	for layer in Constants.Layer.values():
		if layer == Constants.Layer.CORE_HOLLOW:
			_compute_core_hollow(world_data)
		else:
			_compute_layer(layer, _rng, world_data, dummy_positions)

	_compute_bedrock_border(world_data)

	var width := _world_width_tiles()
	terrain_manager.init_streaming_lazy(world_data, width)

	# Place only the columns visible at spawn; PlayerController streams the rest.
	terrain_manager.stream_columns(width / 2, 48)

	return dummy_positions


func _compute_layer(layer: Constants.Layer, rng: RandomNumberGenerator, world_data: Dictionary, dummy_positions: Array) -> void:
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

	# Column-outer: fetch this column's air set and destination dict once, then
	# fill its rows. Avoids a Vector2i allocation and two dict lookups per tile.
	for col in range(width):
		var col_air = air_cells.get(col, null)
		var wd_col = world_data.get(col, null)
		for row in range(top_tile, bottom_tile):
			if col_air != null and col_air.has(row):
				continue
			var terrain: Constants.TerrainType
			if band_rows.has(row):
				terrain = band_type
			else:
				terrain = _pick_terrain(layer, rng)
			if wd_col == null:
				wd_col = {}
				world_data[col] = wd_col
			wd_col[row] = terrain

	_append_dummy_positions(air_cells, world_data, top_tile, bottom_tile, dummy_positions)


# ---------------------------------------------------------------------------
# Core Hollow — circular bedrock-walled chamber, open interior, zero gravity.
# ---------------------------------------------------------------------------
func _compute_core_hollow(world_data: Dictionary) -> void:
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
				if not world_data.has(col):
					world_data[col] = {}
				world_data[col][row] = Constants.TerrainType.BEDROCK


# ---------------------------------------------------------------------------
# Dummy spawn positions — DUMMIES_PER_LAYER floor positions per layer for
# TestDummy placement. A floor position is an air cell (carved by caves) that
# has a solid tile directly below it in world_data. Picks are spread evenly
# across the candidate list so dummies scatter across the layer instead of
# clustering at one end.
# ---------------------------------------------------------------------------
func _append_dummy_positions(air_cells: Dictionary, world_data: Dictionary, top_tile: int, bottom_tile: int, out: Array) -> void:
	# air_cells is column-keyed: { col -> { row -> true } }.
	var candidates: Array = []
	for col: int in air_cells:
		var col_air: Dictionary = air_cells[col]
		var col_data: Dictionary = world_data.get(col, {})
		for row: int in col_air:
			# Skip 3 tiles from each edge of the layer to avoid spawning in inaccessible spots.
			if row < top_tile + 3 or row >= bottom_tile - 3:
				continue
			if col_data.has(row + 1):  # solid floor directly below this air cell
				candidates.append(Vector2i(col, row))
	if candidates.is_empty():
		return
	# Spread up to DUMMIES_PER_LAYER picks evenly across the candidate list.
	# Sorting by column first keeps the even spacing meaningful across the width.
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var count := mini(DUMMIES_PER_LAYER, candidates.size())
	var used := {}
	for i in range(count):
		# Even fractions of the list: (i+1)/(count+1) avoids both extreme ends.
		var idx := int(round(float(i + 1) / float(count + 1) * float(candidates.size() - 1)))
		idx = clampi(idx, 0, candidates.size() - 1)
		# If two picks land on the same index (short list), nudge to the next free one.
		while used.has(idx) and idx < candidates.size() - 1:
			idx += 1
		if used.has(idx):
			continue
		used[idx] = true
		var cell: Vector2i = candidates[idx]
		out.append(Vector2(
			(cell.x + 0.5) * float(Constants.TILE_SIZE),
			cell.y * float(Constants.TILE_SIZE),
		))


# ---------------------------------------------------------------------------
# Cave carver — wrapping horizontal tunnels + vertical shafts.
# Tunnels use col % width so they continue seamlessly across the seam.
# Returns a column-keyed set: { col:int -> { row:int -> true } }. Column-keying
# (rather than a Vector2i-keyed dict) lets _compute_layer fetch a column's air
# set once and skip per-tile Vector2i allocation across the 312k-iteration fill.
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
					_mark_air(air, col, row + dy)
				col = (col + 1) % width
				travelled += 1
		row += rng.randi_range(4, 8)

	# Vertical shafts — guaranteed descent paths, one may straddle the seam.
	var shaft_count: int = rng.randi_range(4, 6)
	for _i in range(shaft_count):
		var sx: int = rng.randi_range(0, width - 1)
		for sr in range(top_tile + 2, bottom_tile - 1):
			_mark_air(air, sx,               sr)
			_mark_air(air, (sx + 1) % width, sr)

	return air


# Marks (col, row) as air in the column-keyed set, creating the column entry on demand.
func _mark_air(air: Dictionary, col: int, row: int) -> void:
	var col_air = air.get(col, null)
	if col_air == null:
		col_air = {}
		air[col] = col_air
	col_air[row] = true


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
func _compute_bedrock_border(world_data: Dictionary) -> void:
	var width: int = _world_width_tiles()
	if width == 0:
		return

	var world_h = _layer_manager.world_height_px()
	if world_h == null:
		return

	var total_rows: int = int(world_h) / Constants.TILE_SIZE

	for col in range(width):
		if not world_data.has(col):
			world_data[col] = {}
		world_data[col][total_rows - 1] = Constants.TerrainType.BEDROCK


func _world_width_tiles() -> int:
	return GameManager.data.get("world_width_tiles", 0) if GameManager.data != null else 0
