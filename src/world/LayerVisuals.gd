## Faultline — per-layer ambient tint for the terrain, and ONLY the terrain.
##
## Descending should feel like the rock itself changes character: near-neutral crust,
## dustier mantle, heat-shifted cores, cold blue Core Hollow shell. This applies that
## as a plain `modulate` colour on the TerrainManager's TileMap node, cross-faded when
## the player crosses a layer boundary.
##
## WHY NOT A CanvasModulate — do not "simplify" this back into one.
## A CanvasModulate multiplies EVERY canvas item on the canvas: the player, the
## TestDummies, the LootDrop gems and Main.gd's background gradient included. Pushing
## the same ambient colour through all of them collapses figure/ground — actors and
## loot stop reading as distinct silhouettes against the terrain, and the backdrop's
## authored gradient gets muddied. Tinting the one TileMap node achieves the same
## ambient read and leaves everything else true-colour for free: nothing has to opt
## out, and no node ever changes parent, layer or z_index for this to work.
##
## Values are VISUAL, not balance — data/layer_visuals.json. They are MULTIPLIED onto
## the terrain art so they stay near white (~0.75-1.0 per channel); a heavy tint
## crushes the tile art's own detail. Absent/null/malformed data leaves the terrain at
## Color.WHITE (no tint) — this never invents a colour.
class_name LayerVisuals
extends Node

## Terrain tint used when a layer has no usable data: art exactly as authored.
const NO_TINT := Color.WHITE

## Null-safety fallback for `transition_seconds` only. The tunable value lives in
## data/layer_visuals.json — this is not the source of truth for it.
const _DEFAULT_TRANSITION_SECONDS := 1.2

const _DATA_KEY := "layer_visuals"

var _tile_map: TileMap = null
var _stats: PlayerStats = null

var _from_tint: Color = NO_TINT
var _target_tint: Color = NO_TINT
var _elapsed: float = 0.0
var _transition_seconds: float = _DEFAULT_TRANSITION_SECONDS


func _ready() -> void:
	# Idle only while a cross-fade is running (see _on_layer_changed / _process).
	set_process(false)


## Wires the tint onto the terrain and starts tracking the player's depth.
##
## `stats` is the local player's PlayerStats: its `layer_changed` signal is the same
## one DescentTracker and DepthHazard react to, so the tint flips at exactly the moment
## the rest of the game agrees the layer changed (and only ever downward — set_layer()
## refuses to go back up).
func init(terrain_manager: TerrainManager, stats: PlayerStats) -> void:
	set_process(false)

	if terrain_manager == null or terrain_manager.tile_map == null:
		push_warning("LayerVisuals: no TerrainManager TileMap — terrain stays untinted.")
		return
	_tile_map = terrain_manager.tile_map
	_stats = stats
	_transition_seconds = _read_transition_seconds()

	if _stats == null:
		push_warning("LayerVisuals: no PlayerStats — terrain holds the Crust tint for the match.")

	# Snap to the starting layer so frame one is already correct — a cross-fade here
	# would read as an unexplained fade-in from white at match start.
	var start_layer: int = _stats.get_layer() if _stats != null else int(Constants.Layer.CRUST)
	_from_tint = _tint_for_layer(start_layer)
	_target_tint = _from_tint
	_apply(_from_tint)

	if _stats != null:
		_stats.layer_changed.connect(_on_layer_changed)


func _on_layer_changed(new_layer: int) -> void:
	if _tile_map == null:
		return
	var next: Color = _tint_for_layer(new_layer)
	if next == _target_tint:
		return  # same tint (or already heading there) — nothing to fade

	# Fade from wherever the terrain actually is, so back-to-back layer changes
	# pick up mid-transition instead of snapping back to the previous layer's tint.
	_from_tint = _tile_map.modulate
	_target_tint = next
	_elapsed = 0.0
	_transition_seconds = _read_transition_seconds()

	if _transition_seconds <= 0.0:
		_apply(_target_tint)  # transition disabled in data — snap
		return
	set_process(true)


func _process(delta: float) -> void:
	if _tile_map == null:
		set_process(false)
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / _transition_seconds, 0.0, 1.0)
	# Ease in/out so the shift reads as a drift rather than a linear ramp.
	_apply(_from_tint.lerp(_target_tint, smoothstep(0.0, 1.0, t)))
	if t >= 1.0:
		set_process(false)


func _apply(tint: Color) -> void:
	if _tile_map == null:
		return
	# The ONLY node this system ever writes to. Alpha is always 1.0 (see
	# _tint_for_layer): a translucent TileMap would show the background gradient
	# through solid rock. Nothing here touches parenting, layers or z_index.
	_tile_map.modulate = tint


## Reads the layer's tint from data/layer_visuals.json, or NO_TINT when the entry is
## absent, null, or malformed. Deliberately never guesses a colour from a partial
## entry — a half-specified tint is data to fix, not a value to invent.
func _tint_for_layer(layer: int) -> Color:
	var tints: Dictionary = _section("ambient_tint")
	if tints.is_empty():
		return NO_TINT

	var entry: Variant = tints.get(_layer_key(layer), null)
	if entry == null or typeof(entry) != TYPE_DICTIONARY:
		return NO_TINT

	var channels: Dictionary = entry
	var r: Variant = channels.get("r", null)
	var g: Variant = channels.get("g", null)
	var b: Variant = channels.get("b", null)
	if not _is_number(r) or not _is_number(g) or not _is_number(b):
		return NO_TINT

	return Color(
		clampf(float(r), 0.0, 1.0),
		clampf(float(g), 0.0, 1.0),
		clampf(float(b), 0.0, 1.0),
		1.0)


## "outer_core" etc. — same layer-key convention DepthHazard uses for its data lookups.
func _layer_key(layer: int) -> String:
	return (Constants.LAYER_NAMES.get(layer, "") as String).to_lower().replace(" ", "_")


func _read_transition_seconds() -> float:
	var root: Dictionary = _root()
	var secs: Variant = root.get("transition_seconds", null)
	if not _is_number(secs):
		return _DEFAULT_TRANSITION_SECONDS
	return maxf(0.0, float(secs))


func _root() -> Dictionary:
	var root: Variant = GameManager.data.get(_DATA_KEY, null)
	if root == null or typeof(root) != TYPE_DICTIONARY:
		return {}
	var dict: Dictionary = root
	return dict


func _section(key: String) -> Dictionary:
	var sub: Variant = _root().get(key, null)
	if sub == null or typeof(sub) != TYPE_DICTIONARY:
		return {}
	var dict: Dictionary = sub
	return dict


func _is_number(value: Variant) -> bool:
	var t: int = typeof(value)
	return t == TYPE_FLOAT or t == TYPE_INT
