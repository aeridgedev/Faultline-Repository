## Faultline — world-space visual-effects manager: drilling/destruction impact feel.
##
## ============================================================================
## ENTIRELY CLIENT-LOCAL. ZERO SERVER / NETWORKING COST. READ THIS FIRST.
## ============================================================================
## Nothing in src/systems/vfx/ is replicated, RPC'd, authoritative, or persisted.
## There are no multiplayer API calls here and no state any peer would ever need
## to agree on. Every effect this manager produces is derived purely from the
## `TerrainManager.tile_destroyed` event, which is ALREADY an authoritative,
## already-replicated fact about the world — so when step 9 (networking) lands,
## each client reproduces its own debris and its own screen shake from the tile
## updates it is receiving anyway. Nothing extra goes on the wire, and a client
## that drops a burst (pool saturated, off-screen cull) diverges from other
## clients only cosmetically, which is correct and intended.
##
## Consequently: do NOT add gameplay consequences here (damage, item spawns, tile
## edits). The moment an effect in this file changes match state it stops being
## reproducible-from-replicated-events and becomes a desync.
## ============================================================================
##
## What it does:
##   - Listens to TerrainManager.tile_destroyed and, per destroyed tile, fires a
##     pooled DebrisBurst tinted by that tile's terrain type, plus a small
##     distance-attenuated camera-shake impulse on every local CameraShake.
##   - Owns the burst POOL. Bursts are built once at startup and recycled forever;
##     nothing is allocated per destroyed tile.
##
## Lives in World.tscn as a Node2D (not a plain Node like its siblings) because
## debris is drawn in world space alongside the terrain — a plain Node has no
## transform and its children would have nowhere to render.
##
## All numbers below are pure VFX-FEEL / budget constants. They are not balance
## values and deliberately do NOT live in data/*.json — same rule TestDummy's dev
## constants follow.
class_name VFXManager
extends Node2D

# --- Pool + cap --------------------------------------------------------------
# Hard cap on simultaneously-active bursts. Sizing: a dig takes >= ~0.4s and a
# burst lives <= ~0.48s, so sustained drilling (even Burst class, 2 tiles per dig)
# never gets near this. The cap exists for the spike case: a Seismic Charge
# destroys a whole radius (29 tiles at the default radius 3) inside ONE frame.
const MAX_ACTIVE_BURSTS := 12

# CAP POLICY: RECYCLE THE OLDEST ACTIVE BURST (we do not skip the new one).
# Why: this system's primary job is direct feedback for the tile the player just
# broke, so the newest impact must always be the one shown — skipping would make
# rapid drilling silently stop responding the moment the pool filled. The oldest
# burst is also the cheapest thing to lose: it is the most faded and closest to
# expiring, so cutting it short is the least visible option available.
# (The recycle itself is cheap — re-seeding <=10 particles into arrays that are
# already allocated. No node is created or freed at any point during a match.)

# Above the terrain TileMap (z 0), below the dig highlight (50) and the throwable
# effects (90+). Set on this node; the pooled bursts inherit it (z_as_relative).
const DEBRIS_Z_INDEX := 20
const DEBRIS_CULL_MARGIN := 48.0  # px past the screen edge still worth drawing

# --- Camera shake ------------------------------------------------------------
# Beyond this distance a destroyed tile contributes no shake at all. Tuned against
# the default 1280x720 / zoom 2.5 view (visible half-extents 256 x 144 px, half
# diagonal ~294 px), so an event just off screen still registers faintly and one
# well off screen registers not at all.
const SHAKE_FALLOFF_RADIUS := 340.0

# --- Debris colour readability ----------------------------------------------
# Debris is drawn by THIS node, not by the TileMap, so it is unaffected by the
# per-layer modulate tint LayerVisuals applies to terrain — and it must not depend
# on matching the tile it came from. Chips keep the terrain's HUE but are lifted in
# HSV value to a guaranteed floor, so debris off near-black terrain (Obsidian,
# Ultra Dense, Bedrock, Core Hollow Shell) still reads against a darkened tile
# while staying recognisably "that rock".
const DEBRIS_MIN_VALUE := 0.42
const DEBRIS_VALUE_LIFT := 0.14
const DEBRIS_MAX_SATURATION := 0.85

# Used when TerrainManager has no base_color_for() (see _debris_color_for).
const FALLBACK_DEBRIS_COLOR := Color(0.55, 0.55, 0.58)

var _terrain: TerrainManager = null
var _idle: Array[DebrisBurst] = []      # ready to be emitted
var _active: Array[DebrisBurst] = []    # in flight, OLDEST FIRST


func _ready() -> void:
	z_index = DEBRIS_Z_INDEX
	_build_pool()
	init(_find_terrain_manager())


## Wires this manager to the TerrainManager whose destruction it should visualise.
## Called automatically from _ready() with the sibling found in World.tscn; exposed
## publicly so a future bootstrap can hand it over explicitly instead.
func init(terrain: TerrainManager) -> void:
	if terrain == null:
		push_warning("[VFXManager] No TerrainManager found — debris and destruction shake are disabled.")
		return
	if _terrain == terrain:
		return
	if _terrain != null and _terrain.tile_destroyed.is_connected(_on_tile_destroyed):
		_terrain.tile_destroyed.disconnect(_on_tile_destroyed)
	_terrain = terrain
	if not _terrain.tile_destroyed.is_connected(_on_tile_destroyed):
		_terrain.tile_destroyed.connect(_on_tile_destroyed)


# VFXManager is declared as a sibling of TerrainManager inside World.tscn, so the
# node is guaranteed to exist in the tree by the time this runs.
func _find_terrain_manager() -> TerrainManager:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("TerrainManager") as TerrainManager


# The entire pool is built once, here. After this point a match performs no node
# allocation for debris at all, regardless of how much terrain is destroyed.
func _build_pool() -> void:
	for i in MAX_ACTIVE_BURSTS:
		var burst := DebrisBurst.new()
		burst.name = "DebrisBurst%d" % i
		burst.finished.connect(_on_burst_finished)
		add_child(burst)
		_idle.append(burst)


# --- Terrain destruction -----------------------------------------------------

func _on_tile_destroyed(cell: Vector2i, type: Constants.TerrainType) -> void:
	if _terrain == null:
		return
	# cell_to_world() returns the cell's TOP-LEFT corner; add half a tile so the
	# burst originates from the middle of the tile that just vanished.
	var half := float(Constants.TILE_SIZE) * 0.5
	var origin := _terrain.cell_to_world(cell) + Vector2(half, half)

	# Shake first: it is distance-attenuated and applies even for a burst we cull,
	# because a tile breaking just off screen should still be felt.
	_shake_local_cameras(origin, CameraShake.TRAUMA_TILE_DESTROY)

	if not _is_on_screen(origin):
		return  # off-screen debris would never be seen — skip the work entirely
	var burst := _acquire_burst()
	if burst == null:
		return
	burst.play(origin, _debris_color_for(type))


## Spawns a debris burst directly, for effects that destroy terrain by some route
## other than TerrainManager.tile_destroyed (nothing does today). Same pool, same cap.
func spawn_debris(world_pos: Vector2, color: Color) -> void:
	if not _is_on_screen(world_pos):
		return
	var burst := _acquire_burst()
	if burst != null:
		burst.play(world_pos, color)


# Returns a burst to emit, or null if the pool is somehow empty. See the CAP POLICY
# comment at the top: when every burst is in flight we take the OLDEST one back.
func _acquire_burst() -> DebrisBurst:
	var burst: DebrisBurst = null
	if not _idle.is_empty():
		burst = _idle.pop_back() as DebrisBurst
	elif not _active.is_empty():
		# oldest = most faded = cheapest to cut short
		burst = _active.pop_front() as DebrisBurst
	if burst != null:
		_active.append(burst)
	return burst


func _on_burst_finished(burst: DebrisBurst) -> void:
	_active.erase(burst)
	if not _idle.has(burst):
		_idle.append(burst)


# --- Helpers -----------------------------------------------------------------

func _shake_local_cameras(world_pos: Vector2, trauma: float) -> void:
	# Group lookup rather than a player reference: the world has no business
	# knowing which node owns the local camera, and on death SpectatorView moves
	# that camera onto another body without the shake driver caring.
	for node in get_tree().get_nodes_in_group(CameraShake.GROUP):
		var shake := node as CameraShake
		if shake != null:
			shake.add_trauma_at(world_pos, trauma, SHAKE_FALLOFF_RADIUS)


# Cheap visibility test against the ACTIVE camera (works while spectating too,
# since get_camera_2d() always reports whichever Camera2D is current). Computed
# from the real viewport size and zoom rather than a hardcoded radius so it stays
# correct if either changes.
func _is_on_screen(world_pos: Vector2) -> bool:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return true  # no camera yet (startup) — never cull on a missing camera
	var zoom := cam.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return true
	var half_view := (get_viewport_rect().size * 0.5) / zoom
	var away := (world_pos - cam.get_screen_center_position()).abs()
	return away.x <= half_view.x + DEBRIS_CULL_MARGIN and away.y <= half_view.y + DEBRIS_CULL_MARGIN


# Terrain-typed chip colour, lifted for readability (see DEBRIS_MIN_VALUE above).
#
# base_color_for() is being added to TerrainManager by a parallel change and may
# not exist yet — this file does not own TerrainManager.gd and must not add it.
# The has_method() guard makes this correct either way: with the method present
# chips match their terrain, without it they fall back to neutral gray.
#
# DO NOT "simplify" this into _terrain.base_color_for(type). `_terrain` is
# statically typed as TerrainManager, so a direct call is resolved at PARSE time
# and would fail to compile the whole script the moment that method is absent
# (reverted, renamed, or not landed yet). has_method() + call() is what keeps this
# file independent of a file it does not own.
func _debris_color_for(type: Constants.TerrainType) -> Color:
	var base := FALLBACK_DEBRIS_COLOR
	if _terrain != null and _terrain.has_method("base_color_for"):
		var result: Variant = _terrain.call("base_color_for", type)
		if result is Color:
			base = result
	return _readable(base)


func _readable(c: Color) -> Color:
	# Lift HSV value (not toward white) so the terrain's hue survives: brightening
	# a near-black obsidian tile toward white produces gray sludge, while lifting
	# its value keeps it recognisably purple.
	var value := maxf(c.v + DEBRIS_VALUE_LIFT, DEBRIS_MIN_VALUE)
	return Color.from_hsv(c.h, minf(c.s, DEBRIS_MAX_SATURATION), minf(value, 1.0), 1.0)
