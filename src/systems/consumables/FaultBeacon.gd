## Faultline — FaultBeacon: on use it drops a visible, pulsing marker at the player's
## current world position for a duration (callouts / orientation in deep layers).
## Only the player controller knows the placement position, so it calls place_beacon()
## right after the channel completes — _on_use_complete itself does no placement.
## TBD: use time / duration live in data/world_config.json "consumables"
## (fault_beacon_use_time, fault_beacon_duration) — dev placeholders.
class_name FaultBeacon
extends ConsumableBase

signal beacon_placed(world_position: Vector2)


func _init() -> void:
	use_time = GameManager.data.get("consumables", {}).get("fault_beacon_use_time", null)


func _on_use_complete(_stats: PlayerStats) -> void:
	# Intentionally empty: placement needs the player's world position, which only the
	# controller has, so PlayerController calls place_beacon() on completion instead.
	pass


## Spawns the world marker at `pos` and emits beacon_placed with the real position.
## Called by PlayerController._on_consumable_completed once the channel finishes.
func place_beacon(world: Node, pos: Vector2) -> void:
	if world == null:
		return
	var dur_v: Variant = GameManager.data.get("consumables", {}).get("fault_beacon_duration", null)
	var duration := float(dur_v) if dur_v != null else 30.0  # TBD: fault_beacon_duration
	var marker := BeaconMarker.new()
	marker.duration = duration
	world.add_child(marker)
	marker.global_position = pos
	beacon_placed.emit(pos)


## A distinct amber beacon pylon drawn over terrain (z_index 150), with an expanding
## pulse ring that repeats until the beacon expires, then frees itself.
class BeaconMarker extends Node2D:
	var duration: float = 30.0
	var _elapsed: float = 0.0
	var _pulse: float = 0.0

	const AMBER := Color(1.0, 0.74, 0.18)
	const AMBER_HEAD := Color(1.0, 0.90, 0.42)
	const PULSE_PERIOD := 1.2
	const PULSE_MAX := 40.0

	func _ready() -> void:
		z_index = 150   # reads over terrain

	func _process(delta: float) -> void:
		_elapsed += delta
		_pulse += delta
		if _pulse >= PULSE_PERIOD:
			_pulse -= PULSE_PERIOD
		if _elapsed >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		# Expanding pulse ring (restarts each PULSE_PERIOD).
		var t := _pulse / PULSE_PERIOD
		var ring := AMBER
		ring.a = 1.0 - t
		draw_arc(Vector2.ZERO, lerpf(4.0, PULSE_MAX, t), 0.0, TAU, 40, ring, 2.0, true)
		# Pylon: a 3px-wide vertical bar ~12px tall rising from the ground point.
		draw_rect(Rect2(-1.5, -12.0, 3.0, 12.0), AMBER)
		# Bright diamond head at the top.
		var head := Vector2(0.0, -14.0)
		var d := 3.0
		draw_colored_polygon(PackedVector2Array([
			head + Vector2(0.0, -d), head + Vector2(d, 0.0),
			head + Vector2(0.0, d), head + Vector2(-d, 0.0),
		]), AMBER_HEAD)
