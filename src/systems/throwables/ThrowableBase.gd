## Faultline — base for all 7 throwables. Each type is set via throwable_type.
## Effect strengths, durations, and radii are TBD — stubbed in _apply_effect().
## Physics: RigidBody2D so gravity handles the arc automatically.
class_name ThrowableBase
extends RigidBody2D

var throwable_type: Constants.Throwable = Constants.Throwable.SMOKE_BOMB
var _owner_id: int = -1   # player_id that threw this; used to skip self-damage checks


func setup(type: Constants.Throwable, owner_id: int) -> void:
	throwable_type = type
	_owner_id = owner_id


## Call to launch the throwable in a direction with a given speed.
func throw(origin: Vector2, direction: Vector2, speed: float) -> void:
	global_position = origin
	linear_velocity = direction.normalized() * speed


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Self-destruct after 10s if it never hits anything (TBD: per-type fuse durations).
	get_tree().create_timer(10.0).timeout.connect(queue_free)


func _on_body_entered(body: Node) -> void:
	_apply_effect(body)
	queue_free()


func _apply_effect(hit_body: Node) -> void:
	# All effect values are TBD. Stubs emit prints so behavior can be verified in logs.
	match throwable_type:
		Constants.Throwable.SMOKE_BOMB:
			# TODO(step 6 balance): obscure vision in radius for TBD seconds.
			print("[Throwable] Smoke Bomb detonated")
		Constants.Throwable.PARALYSIS_BOMB:
			# TODO(step 6 balance): freeze hit player's input for TBD seconds.
			_try_apply_to_stats(hit_body, func(s): print("[Throwable] Paralysis on player"))
		Constants.Throwable.WEAKNESS_BOMB:
			# TODO(step 6 balance): reduce hit player's damage dealt for TBD seconds.
			_try_apply_to_stats(hit_body, func(s): print("[Throwable] Weakness on player"))
		Constants.Throwable.HEAT_CHARGE:
			# TODO(step 6 balance): deal fire damage over TBD seconds in radius.
			_try_apply_to_stats(hit_body, func(s): print("[Throwable] Heat Charge on player"))
		Constants.Throwable.DUST_CAPSULE:
			# TODO(step 6 balance): obscure drill targeting in radius for TBD seconds.
			print("[Throwable] Dust Capsule detonated")
		Constants.Throwable.ECHO_CHARGE:
			# TODO(step 6 balance): reveal all players in radius for TBD seconds.
			print("[Throwable] Echo Charge detonated")
		Constants.Throwable.SEISMIC_CHARGE:
			# TODO(step 6 balance): destroy terrain tiles in radius.
			print("[Throwable] Seismic Charge detonated")


func _try_apply_to_stats(body: Node, callback: Callable) -> void:
	# FFA: no friendly fire concept (CLAUDE.md); skip if same player.
	var target_ctrl = body as PlayerController
	if target_ctrl == null:
		return
	if target_ctrl.player_id == _owner_id:
		return
	callback.call(target_ctrl.stats)
