## Faultline — monitors player Y to detect layer transitions and enforces the kill gate.
##
## Kill gate: the player cannot descend into the next layer until they have accumulated
## the required kill count for the current layer (Constants.LAYER_KILL_REQUIREMENTS).
##
## HOW THE GATE BLOCKS (2026-07-31 rewrite): while the requirement is unmet, a real
## StaticBody2D floor ("KillGateFloor") is placed across the current layer's bottom edge
## and removed the instant the requirement is met. The gate is NOT a per-frame position
## write any more.
##
## Why that matters — the previous implementation set the player's `global_position.y`
## directly every frame (`_clamp_to_boundary`). A direct position write is invisible to
## the physics engine, and it produced two separate bugs at every locked gate:
##
##   1. The write targeted the body ORIGIN (`boundary_y - 1.0`), but the player's
##      collision box is a 14x28 rectangle CENTRED on that origin (Player.tscn). So the
##      feet landed 13px BELOW the boundary — buried in the tile row the player was
##      being blocked from entering. move_and_slide() cannot walk a body that already
##      overlaps solid geometry, so horizontal input died too: fully stuck.
##
##   2. Even with nothing embedded (the common case — the player has just drilled the
##      trench they are standing in, so there is air below), the player was held up by
##      the position write rather than by resting on a collider. move_and_slide()
##      therefore reported NO floor contact, `is_on_floor()` stayed false, and that
##      silently disabled PlayerController._try_step_up() at its very first guard. The
##      player could still walk left/right (velocity.x through air) but could never step
##      up a 1-tile ledge — and ONLY inside the gate trench. Meeting the kill
##      requirement "fixed" it because the clamp then simply stopped running.
##
## A StaticBody2D fixes both by construction: the player rests on the gate exactly like
## any other floor, so `is_on_floor()` is true, step-up behaves identically to everywhere
## else in the world, and nothing is ever teleported into terrain. Descent stays blocked
## just as hard — harder, in fact, since it is now real collision rather than a
## crossing-detected-after-the-fact correction.
##
## Execution order: DescentTracker is a child of PlayerController, so its
## _physics_process runs AFTER the parent (Godot processes parent before child).
class_name DescentTracker
extends Node

signal layer_changed(new_layer: int)
signal descent_blocked(required_kills: int)
signal kill_progress_changed(current_kills: int, required_kills: int, next_layer_name: String)

## Dedicated physics layer bit for the gate floor (bit 4 -> value 8).
## Bits already in use in this project: 1 = terrain TileMap + player/dummy bodies,
## 2 = chest areas, 3 = player (so chest areas can filter down to just the player).
## Bit 4 is free, and the ONLY mask that ever gets it is the local player's, OR-ed in by
## _init_gate(). A player's gate floor is therefore invisible to TestDummies, chests,
## throwables and loot drops — it can only ever stop the player who owns it.
const GATE_COLLISION_LAYER := 8

## The gate floor extends this far DOWN from the boundary line. Only its top edge is ever
## touched (the player rests on it); the depth is anti-tunnelling headroom for a fast fall.
const GATE_THICKNESS_PX := 64.0

## Horizontal overhang past each end of the world, so the cylindrical wrap
## (PlayerController._wrap_horizontal) can never place the player past the gate's end.
const GATE_WIDTH_MARGIN_PX := 512.0

## Feet within this distance of the gate's top edge count as "pressed against the gate"
## for the descent_blocked HUD message.
const GATE_CONTACT_EPSILON_PX := 3.0

@onready var _stats: PlayerStats = $"../PlayerStats"

var _layer_manager: LayerManager
var _block_cooldown: float = 0.0
var _last_kill_count: int = -1  # -1 forces an emit on the first physics frame

var _gate_body: StaticBody2D = null
var _gate_shape: CollisionShape2D = null
var _gate_rect: RectangleShape2D = null
var _gate_active: bool = false
# Half the player's collision-box HEIGHT. Read from the real CollisionShape2D so the
# origin-vs-box mistake that caused bug 1 above cannot be reintroduced by hardcoding.
var _player_half_height: float = 14.0


func _ready() -> void:
	_stats.layer_changed.connect(_on_layer_changed)
	_cache_player_half_height()


func init(lm: LayerManager) -> void:
	_layer_manager = lm
	_init_gate()


func _physics_process(delta: float) -> void:
	if _stats.is_dead:
		_set_gate_enabled(false)
		return

	# Detect kill count changes; runs before the layer_manager guard so the
	# initial emit fires on the very first frame even during world setup.
	if _stats.kill_count != _last_kill_count:
		_last_kill_count = _stats.kill_count
		_emit_kill_progress()

	if _layer_manager == null:
		return

	_block_cooldown = maxf(0.0, _block_cooldown - delta)

	# Position/enable the gate floor for the layer the player is currently in. This is
	# what actually blocks descent; everything below is bookkeeping.
	_update_gate()

	var y: float = (get_parent() as Node2D).global_position.y
	var new_layer: int = int(_layer_manager.layer_at_y(y))

	if new_layer <= _stats.get_layer():
		return

	# Player is physically inside the next layer. With the gate floor in place this is
	# only reachable when the gate is open, but keep the check as the authority.
	var required: int = Constants.LAYER_KILL_REQUIREMENTS.get(_stats.get_layer(), 0)
	if required > 0 and _stats.kill_count < required:
		# The gate floor should have stopped this. Getting here means the player slipped
		# past it — the gate is built in init() and enabled on the first physics frame, so
		# a body already below the boundary at startup (or moved by some future teleport
		# effect) is the realistic case. Recover, then let the gate hold them from now on.
		_recover_above_boundary()
		_notify_blocked(required)
		return

	_stats.set_layer(new_layer)


# --- Gate floor ------------------------------------------------------------

func _init_gate() -> void:
	var player := get_parent() as CharacterBody2D
	if player == null:
		return

	# The local player is the only body that may see the gate's dedicated layer.
	# OR-ed in (never assigned) so the existing bit-1 terrain mask is preserved.
	player.collision_mask |= GATE_COLLISION_LAYER

	_gate_rect = RectangleShape2D.new()
	_gate_rect.size = Vector2(_gate_width(), GATE_THICKNESS_PX)

	_gate_shape = CollisionShape2D.new()
	_gate_shape.shape = _gate_rect
	_gate_shape.disabled = true   # enabled by _update_gate() only while the gate is locked

	_gate_body = StaticBody2D.new()
	_gate_body.name = "KillGateFloor"
	# World space. DescentTracker is a plain Node, which already detaches the transform
	# chain, but set this explicitly so the gate can never inherit the player's transform
	# and slide around with them if the node is ever reparented.
	_gate_body.top_level = true
	_gate_body.collision_layer = GATE_COLLISION_LAYER
	_gate_body.collision_mask = 0   # the gate detects nothing; the player's mask finds it
	_gate_body.add_child(_gate_shape)
	add_child(_gate_body)


func _update_gate() -> void:
	var current_layer := _stats.get_layer()
	var required: int = Constants.LAYER_KILL_REQUIREMENTS.get(current_layer, 0)
	var boundary_y: Variant = _layer_manager.get_layer_bottom_y(current_layer)

	# No requirement (Core Hollow), requirement already met, or heights are TBD/null:
	# the layer floor is open, so the gate must not exist.
	if required <= 0 or _stats.kill_count >= required or boundary_y == null:
		_set_gate_enabled(false)
		return

	var top_y := float(boundary_y)
	if _gate_body != null:
		# RectangleShape2D is centred on its owner, so push the body down half the
		# thickness to put the TOP edge exactly on the boundary line. The player then
		# rests with their feet at boundary_y — inside their current layer, on a real
		# floor, with is_on_floor() true and step-up fully functional.
		_gate_body.global_position = Vector2(_gate_center_x(), top_y + GATE_THICKNESS_PX * 0.5)
	_refresh_gate_width()
	_set_gate_enabled(true)

	# "Need N kills to descend" fires while the player is actually standing on / pushing
	# into the gate. Normal terrain fills the layer's last tile row, so this only triggers
	# once the player has drilled their trench all the way down to the boundary.
	var feet_y: float = (get_parent() as Node2D).global_position.y + _player_half_height
	if feet_y >= top_y - GATE_CONTACT_EPSILON_PX:
		_notify_blocked(required)


func _set_gate_enabled(enabled: bool) -> void:
	if _gate_shape == null or _gate_active == enabled:
		return
	_gate_active = enabled
	# Deferred: a collision shape must not be toggled while the physics server is stepping.
	_gate_shape.set_deferred("disabled", not enabled)


## World width can be null at init() time if world_width_tiles is TBD, so re-check it
## rather than trusting the size computed once during _init_gate().
func _refresh_gate_width() -> void:
	if _gate_rect == null:
		return
	var want := _gate_width()
	if not is_equal_approx(_gate_rect.size.x, want):
		_gate_rect.size = Vector2(want, GATE_THICKNESS_PX)


func _gate_width() -> float:
	var w: Variant = _layer_manager.world_width_px() if _layer_manager != null else null
	if w == null:
		return 100000.0   # world_width_tiles TBD: span far enough to be unreachable
	return float(w) + GATE_WIDTH_MARGIN_PX * 2.0


func _gate_center_x() -> float:
	# The world spans x = 0 .. world_width_px (PlayerController._wrap_horizontal).
	var w: Variant = _layer_manager.world_width_px() if _layer_manager != null else null
	return float(w) * 0.5 if w != null else 0.0


func _notify_blocked(required: int) -> void:
	if _block_cooldown > 0.0:
		return
	descent_blocked.emit(required)
	_block_cooldown = 2.0


func _cache_player_half_height() -> void:
	var shape_node := get_parent().get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		_player_half_height = (shape_node.shape as RectangleShape2D).size.y * 0.5


## Safety net only — the gate floor is the real mechanism. Placed the player's FEET on
## the boundary line, never the origin: writing `origin = boundary_y - 1.0` (the old
## _clamp_to_boundary) buried the lower 13px of the 14x28 box in the tile row below and
## made the body immovable. Because the gate floor is active whenever this can run, the
## player lands on top of it on the next frame, so is_on_floor() — and therefore step-up —
## recovers by itself instead of staying dead for as long as the gate is locked.
func _recover_above_boundary() -> void:
	var boundary_y: Variant = _layer_manager.get_layer_bottom_y(_stats.get_layer())
	if boundary_y == null:
		return
	var player_node := get_parent() as CharacterBody2D
	if player_node == null:
		return
	var feet_target := float(boundary_y) - _player_half_height
	if player_node.global_position.y > feet_target:
		player_node.global_position.y = feet_target
	# Zero downward velocity so gravity doesn't immediately re-cross the boundary.
	if player_node.velocity.y > 0.0:
		player_node.velocity.y = 0.0


func _emit_kill_progress() -> void:
	var current_layer := _stats.get_layer()
	var required: int = Constants.LAYER_KILL_REQUIREMENTS.get(current_layer, 0)
	if required == 0:
		kill_progress_changed.emit(_stats.kill_count, 0, "")
		return
	var next_name: String = Constants.LAYER_NAMES.get(current_layer + 1, "")
	kill_progress_changed.emit(_stats.kill_count, required, next_name)


func _on_layer_changed(new_layer: int) -> void:
	layer_changed.emit(new_layer)
	_emit_kill_progress()
