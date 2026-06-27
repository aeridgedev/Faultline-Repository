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
	get_tree().create_timer(10.0).timeout.connect(func(): if is_instance_valid(self): queue_free())
	_build_dev_sprite()


func _build_dev_sprite() -> void:
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		return
	# 8×8 grenade silhouette: dark oval body, bright band, pin pixel
	const S := 8
	var K  := Color(0.06, 0.06, 0.07)   # body
	var B  := Color(0.22, 0.22, 0.24)   # body lit
	var BD := Color(0.12, 0.12, 0.14)   # body shadow
	var BN := Color(0.72, 0.68, 0.22)   # safety band
	var PN := Color(0.60, 0.62, 0.65)   # pin metal
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Oval body: fill pixels where (dx/3)^2 + (dy/3)^2 < 1 roughly
	for y in S:
		for x in S:
			var cx := float(x) - 3.5; var cy := float(y) - 4.0
			if (cx * cx / 9.0 + cy * cy / 12.0) < 1.0:
				if y == 2:
					img.set_pixel(x, y, BN)   # safety band
				elif x <= 2 and y <= 3:
					img.set_pixel(x, y, B)    # lit upper-left
				elif x >= 5 or y >= 6:
					img.set_pixel(x, y, BD)   # shadow
				else:
					img.set_pixel(x, y, K)
	# Pin — single pixel above body
	img.set_pixel(4, 0, PN)
	img.set_pixel(5, 0, PN)
	spr.texture = ImageTexture.create_from_image(img)


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
