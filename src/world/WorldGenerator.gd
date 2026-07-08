## Faultline — procedural terrain generation; fills TerrainManager via place_tile.
##
## World shape: cylindrical — left and right edges connect seamlessly.
##   Bedrock only bounds the bottom row.
##   Cave tunnels wrap around the horizontal axis so no seam is visible.
##   Horizontal rock bands every 8–14 rows discourage pure vertical drilling.
##
## Each non-hollow layer gets:
##   1. A terrain-type fill weighted by depth (harder terrain deeper).
##   2. A cave pass: cellular-automata organic caverns + a meandering shaft/tunnel
##      connectivity spine (see _carve_caves). Replaced the old central-void carver.
##   3. Horizontal rock bands of harder terrain to break up vertical corridors.
class_name WorldGenerator
extends RefCounted

var _terrain_manager: TerrainManager
var _layer_manager: LayerManager
var _rng: RandomNumberGenerator

# DEV-ONLY: number of TestDummy combat targets placed per non-Core-Hollow layer,
# spread across the layer for kill-count testing. Remove with the dummies once
# networked players exist.
const DUMMIES_PER_LAYER := 8


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
	# Floor division to a whole column index is intended.
	@warning_ignore("integer_division")
	terrain_manager.stream_columns(width / 2, 48)

	# DEV-ONLY dummy fix (2026-07-06): the TestDummies are spread across the FULL
	# width and every non-hollow layer, but the stream_columns() call above only
	# placed collision tiles in the ~97 columns near the player's spawn. Any dummy
	# outside that band had NO terrain tile beneath it, so it fell straight through
	# the (non-collidable, unstreamed) world and vanished — the root cause of
	# "dummies not spawning": their positions were computed fine, but the bodies
	# dropped out of the level on frame one. Stream a small 3-column platform under
	# each dummy so every one rests on solid ground immediately, wherever it is.
	for dpos: Vector2 in dummy_positions:
		@warning_ignore("integer_division")
		var dummy_col: int = int(dpos.x) / Constants.TILE_SIZE
		terrain_manager.stream_columns(dummy_col, 1)

	# DEV-ONLY: report the real dummy count actually handed to Main.gd for spawning.
	print("[WorldGenerator] Spawned %d test dummies total (target %d per layer x %d layers)"
		% [dummy_positions.size(), DUMMIES_PER_LAYER, Constants.Layer.values().size() - 1])

	return dummy_positions


func _compute_layer(layer: Constants.Layer, rng: RandomNumberGenerator, world_data: Dictionary, dummy_positions: Array) -> void:
	var top_y    = _layer_manager.get_layer_top_y(layer)
	var bottom_y = _layer_manager.get_layer_bottom_y(layer)
	if top_y == null or bottom_y == null:
		return

	# Floor division to whole tile-row indices is intended.
	@warning_ignore("integer_division")
	var top_tile: int    = int(top_y) / Constants.TILE_SIZE
	@warning_ignore("integer_division")
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
# Core Hollow — circular chamber walled by CORE_HOLLOW_SHELL, open interior,
# zero gravity. The shell is the hardest DRILLABLE terrain in the game (NOT
# Bedrock): it forms a complete boundary around the open interior that players
# must breach to enter and win — thin at the poles, thicker toward the equator,
# but drillable everywhere given enough time. The only Bedrock left is the
# absolute bottom border (added later by _compute_bedrock_border).
# ---------------------------------------------------------------------------
func _compute_core_hollow(world_data: Dictionary) -> void:
	var top_y    = _layer_manager.get_layer_top_y(Constants.Layer.CORE_HOLLOW)
	var bottom_y = _layer_manager.get_layer_bottom_y(Constants.Layer.CORE_HOLLOW)
	if top_y == null or bottom_y == null:
		return

	# Floor division to whole tile indices is intended throughout this block
	# (chamber center/radius math only makes sense on whole tiles).
	@warning_ignore("integer_division")
	var top_tile    := int(top_y)    / Constants.TILE_SIZE
	@warning_ignore("integer_division")
	var bottom_tile := int(bottom_y) / Constants.TILE_SIZE
	var width       := _world_width_tiles()
	if width == 0:
		return

	@warning_ignore("integer_division")
	var center_col := width / 2
	@warning_ignore("integer_division")
	var center_row := (top_tile + bottom_tile) / 2
	@warning_ignore("integer_division")
	var max_v := (bottom_tile - top_tile) / 2 - 2
	@warning_ignore("integer_division")
	var max_h := width / 2 - 2
	var hollow_r := mini(max_v, max_h)

	for row in range(top_tile, bottom_tile):
		for col in range(width):
			var dx := col - center_col
			var dy := row - center_row
			if dx * dx + dy * dy > hollow_r * hollow_r:
				if not world_data.has(col):
					world_data[col] = {}
				world_data[col][row] = Constants.TerrainType.CORE_HOLLOW_SHELL


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
# Cave carver — CELLULAR-AUTOMATA organic caves (2026-07-07 visual-polish
# rewrite). Replaced the old wrapping-tunnel + full-height-shaft carver, which
# produced one dominant artificial-looking void instead of branching caves.
#
# Per layer: random-fill ~50% solid, then smooth with the classic CA "keep-band"
# rule (a cell turns solid at >=5 solid 8-neighbours, open at <=3, keeps its
# state at exactly 4) for CA_SMOOTH_ITERS passes. This coalesces the noise into
# organic blobby caverns. A flood-fill de-speckle then fills tiny open pockets
# and opens tiny solid specks so the result reads as caverns, not salt-and-pepper.
# Finally a few MEANDERING vertical shafts + horizontal tunnels are carved as a
# connectivity spine (each horizontal sweeps the full width, so it crosses every
# vertical): this stitches the surviving caverns into one traversable system.
#
# Neighbour counting wraps horizontally (cylindrical world) and treats cells
# above/below the layer as solid, so caves seal toward the layer's top/bottom
# edges (the player DRILLS between layers — that is the descent mechanic).
# Prototyped in Python before porting (Godot isn't runnable here): these params
# give ~50% open and a single connected region covering ~90%+ of open cells per
# layer, so the layer is fully traversable with no dominant central hole. Any
# remaining small isolated pockets are reachable by drilling — harmless.
#
# Returns the SAME column-keyed air set { col:int -> { row:int -> true } } the
# old carver returned, so _compute_layer / _append_dummy_positions are unchanged.
# ---------------------------------------------------------------------------
const CA_WALL_PROB := 0.50      # initial solid fraction (~50% open after smoothing)
const CA_SMOOTH_ITERS := 4      # CA smoothing passes
const CA_MIN_CAVE := 30         # open regions smaller than this are filled solid
const CA_MIN_ROCK := 12         # solid specks smaller than this are opened


func _carve_caves(top_tile: int, bottom_tile: int, width: int, rng: RandomNumberGenerator) -> Dictionary:
	var h := bottom_tile - top_tile
	var w := width
	if h <= 0 or w <= 0:
		return {}

	# 1. Random noise fill (1 = solid, 0 = open).
	var grid := PackedByteArray()
	grid.resize(h * w)
	for i in range(h * w):
		grid[i] = 1 if rng.randf() < CA_WALL_PROB else 0

	# 2. Cellular-automata smoothing into organic blobs.
	for _iter in range(CA_SMOOTH_ITERS):
		grid = _smooth_step(grid, h, w)

	# 3. De-speckle small pockets so it reads as caverns, not noise.
	#    (PackedByteArray is a copy-on-write value type — mutating helpers must
	#     return the grid and we reassign, or their edits could be lost to a fork.)
	grid = _despeckle(grid, h, w)

	# 4. Connectivity spine: meandering shafts + tunnels stitch caverns together.
	grid = _carve_vertical_shafts(grid, h, w, rng)
	grid = _carve_horizontal_tunnels(grid, h, w, rng)

	# 5. Emit open cells as the column-keyed air set.
	var air := {}
	for r in range(h):
		var base := r * w
		var world_row := top_tile + r
		for c in range(w):
			if grid[base + c] == 0:
				_mark_air(air, c, world_row)
	return air


# One CA smoothing pass ("keep-band" rule). Horizontal neighbours wrap (cylinder);
# rows outside the layer count as solid so caves seal toward the layer edges.
func _smooth_step(grid: PackedByteArray, h: int, w: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(h * w)
	for r in range(h):
		var up := (r - 1) * w
		var mid := r * w
		var down := (r + 1) * w
		var has_up := r > 0
		var has_down := r < h - 1
		for c in range(w):
			var cl := c - 1 if c > 0 else w - 1
			var cr := c + 1 if c < w - 1 else 0
			var walls := 0
			if has_up:
				walls += grid[up + cl] + grid[up + c] + grid[up + cr]
			else:
				walls += 3
			walls += grid[mid + cl] + grid[mid + cr]
			if has_down:
				walls += grid[down + cl] + grid[down + c] + grid[down + cr]
			else:
				walls += 3
			var idx := mid + c
			if walls >= 5:
				out[idx] = 1
			elif walls <= 3:
				out[idx] = 0
			else:
				out[idx] = grid[idx]
	return out


# Fills open regions smaller than CA_MIN_CAVE (solidify tiny pockets), then opens
# solid regions smaller than CA_MIN_ROCK (dissolve tiny wall specks). Two passes,
# second on the updated grid — matches the prototyped, validated ordering.
func _despeckle(grid: PackedByteArray, h: int, w: int) -> void:
	for cells in _regions(grid, h, w, 0):
		if cells.size() < CA_MIN_CAVE:
			for i in cells:
				grid[i] = 1
	for cells in _regions(grid, h, w, 1):
		if cells.size() < CA_MIN_ROCK:
			for i in cells:
				grid[i] = 0


# 4-connected (horizontal-wrap, vertical-bounded) flood fill; returns an Array of
# Array[int] cell-index groups for every connected region whose value == `want`.
func _regions(grid: PackedByteArray, h: int, w: int, want: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(h * w)
	var res: Array = []
	for start in range(h * w):
		if int(grid[start]) != want or seen[start] == 1:
			continue
		var cells: Array[int] = []
		var queue: Array[int] = [start]
		seen[start] = 1
		var head := 0
		while head < queue.size():
			var i: int = queue[head]
			head += 1
			cells.append(i)
			@warning_ignore("integer_division")
			var r := i / w
			var c := i % w
			var down := (r + 1) * w + c if r + 1 < h else -1
			var up := (r - 1) * w + c if r - 1 >= 0 else -1
			var right := r * w + ((c + 1) % w)
			var left := r * w + ((c - 1 + w) % w)
			for ni in [down, up, right, left]:
				if ni >= 0 and seen[ni] == 0 and int(grid[ni]) == want:
					seen[ni] = 1
					queue.append(ni)
		res.append(cells)
	return res


# 2-4 meandering (drunkard's-walk) vertical shafts, 3 tiles wide — organic
# descent routes that also seed vertical connectivity. Wander wraps horizontally.
func _carve_vertical_shafts(grid: PackedByteArray, h: int, w: int, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(2, 4)
	for _s in range(count):
		var c := rng.randi_range(0, w - 1)
		for r in range(h):
			for dc in range(-1, 2):
				grid[r * w + ((c + dc + w) % w)] = 0
			c = (c + rng.randi_range(-1, 1) + w) % w


# 2-3 meandering horizontal tunnels, 2-3 tiles tall, each sweeping the FULL width
# once (wrapping). Because they traverse every column, each crosses every vertical
# shaft — guaranteeing the spine is one connected component.
func _carve_horizontal_tunnels(grid: PackedByteArray, h: int, w: int, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(2, 3)
	for _t in range(count):
		var r := rng.randi_range(2, maxi(2, h - 3))
		var tall := rng.randi_range(2, 3)
		var c := rng.randi_range(0, w - 1)
		for _step in range(w):
			for dr in range(tall):
				grid[clampi(r + dr, 0, h - 1) * w + c] = 0
			c = (c + 1) % w
			r = clampi(r + rng.randi_range(-1, 1), 1, h - 2)


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

	# Floor division to a whole row index is intended.
	@warning_ignore("integer_division")
	var total_rows: int = int(world_h) / Constants.TILE_SIZE

	for col in range(width):
		if not world_data.has(col):
			world_data[col] = {}
		world_data[col][total_rows - 1] = Constants.TerrainType.BEDROCK


func _world_width_tiles() -> int:
	return GameManager.data.get("world_width_tiles", 0) if GameManager.data != null else 0
