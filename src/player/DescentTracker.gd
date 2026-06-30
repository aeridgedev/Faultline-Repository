## Faultline — monitors player Y to detect layer transitions and enforces the kill gate.
##
## Kill gate: player cannot descend into the next layer until they have accumulated
## the required kill count for the current layer (Constants.LAYER_KILL_REQUIREMENTS).
## When blocked: player position is clamped to the layer boundary and downward velocity
## is zeroed so gravity cannot push them through. A cooldown prevents the HUD message
## from firing every frame.
##
## Execution order: DescentTracker is a child of PlayerController, so its
## _physics_process runs AFTER the parent (Godot processes parent before child).
## This means the position clamp always overrides move_and_slide() for the same frame.
class_name DescentTracker
extends Node

signal layer_changed(new_layer: int)
signal descent_blocked(required_kills: int)
signal kill_progress_changed(current_kills: int, required_kills: int, next_layer_name: String)

@onready var _stats: PlayerStats = $"../PlayerStats"

var _layer_manager: LayerManager
var _block_cooldown: float = 0.0
var _last_kill_count: int = -1  # -1 forces an emit on the first physics frame


func _ready() -> void:
	_stats.layer_changed.connect(_on_layer_changed)


func init(lm: LayerManager) -> void:
	_layer_manager = lm


func _physics_process(delta: float) -> void:
	if _stats.is_dead:
		return

	# Detect kill count changes; runs before the layer_manager guard so the
	# initial emit fires on the very first frame even during world setup.
	if _stats.kill_count != _last_kill_count:
		_last_kill_count = _stats.kill_count
		_emit_kill_progress()

	if _layer_manager == null:
		return

	_block_cooldown = maxf(0.0, _block_cooldown - delta)

	var y: float = (get_parent() as Node2D).global_position.y
	var new_layer: int = int(_layer_manager.layer_at_y(y))

	if new_layer <= _stats.get_layer():
		return

	# Player has physically crossed into the next layer — check the kill gate.
	var required: int = Constants.LAYER_KILL_REQUIREMENTS.get(_stats.get_layer(), 0)
	if required > 0 and _stats.kill_count < required:
		_clamp_to_boundary()
		if _block_cooldown <= 0.0:
			descent_blocked.emit(required)
			_block_cooldown = 2.0
		return

	_stats.set_layer(new_layer)


func _clamp_to_boundary() -> void:
	var boundary_y: Variant = _layer_manager.get_layer_bottom_y(_stats.get_layer())
	if boundary_y == null:
		return
	var player_node := get_parent() as CharacterBody2D
	if player_node == null:
		return
	# Push player back to just above the layer boundary.
	if player_node.global_position.y >= float(boundary_y):
		player_node.global_position.y = float(boundary_y) - 1.0
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
