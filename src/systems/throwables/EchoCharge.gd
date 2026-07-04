## Faultline — Echo Charge throwable. On impact, every player in a large radius is
## revealed for the duration: the "Revealed" status shows on the victim's HUD debuff
## panel, and a bright magenta marker follows each revealed body drawn ABOVE all
## terrain (top_level + high z_index) — that is the "visible through terrain" mechanic.
## A one-shot ping ring shows the thrower the scanned area.
## TBD: radius/duration live in data/world_config.json "throwables"
## (echo_radius, echo_duration) — dev placeholders pending balance pass.
class_name EchoCharge
extends ThrowableBase


func _on_impact(impact_point: Vector2, _hit_body: Node) -> void:
	var radius := float(_data("echo_radius", 220.0))      # TBD: echo_radius (deliberately large)
	var duration := float(_data("echo_duration", 8.0))    # TBD: echo_duration
	for target: Dictionary in targets_in_radius(radius):
		var stats := target["stats"] as PlayerStats
		stats.apply_status("Revealed", duration, false, {"revealed": true})
		var marker := RevealMarker.new()
		marker.target = target["body"] as Node2D
		marker.duration = duration
		effect_parent().add_child(marker)
	var ping := PingRing.new()
	ping.max_radius = radius
	effect_parent().add_child(ping)
	ping.global_position = impact_point


func _dev_tint() -> Color:
	return Color(0.95, 0.30, 0.90)   # magenta


## Follows one revealed body, drawn over ALL terrain (top_level + z_index 200) so the
## target is visible even through solid tiles. Frees itself when the reveal expires or
## the target dies / is freed.
class RevealMarker extends Node2D:
	var target: Node2D = null
	var duration: float = 8.0
	var _elapsed: float = 0.0
	var _pulse: float = 0.0

	const MARK := Color(0.98, 0.36, 0.92)

	func _ready() -> void:
		top_level = true   # ignore parent transform; we set global_position directly
		z_index = 200      # over players and terrain

	func _process(delta: float) -> void:
		if not is_instance_valid(target):
			queue_free()
			return
		var stats := target.get_node_or_null("PlayerStats") as PlayerStats
		if stats != null and stats.is_dead:
			queue_free()
			return
		global_position = target.global_position
		_elapsed += delta
		_pulse += delta
		if _elapsed >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		# Pulsing hollow ring + a small filled diamond pinned to the body center.
		var pulse := 0.5 + 0.5 * sin(_pulse * 6.0)
		var r := 12.0 + pulse * 4.0
		var col := MARK
		col.a = 0.55 + 0.35 * pulse
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 2.0, true)
		var d := 3.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, -d), Vector2(d, 0.0), Vector2(0.0, d), Vector2(-d, 0.0),
		]), MARK)


## One-shot expanding magenta ping showing the scanned radius, then frees itself.
class PingRing extends Node2D:
	var max_radius: float = 220.0
	const LIFETIME := 0.5
	var _elapsed: float = 0.0

	func _ready() -> void:
		z_index = 90

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= LIFETIME:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := clampf(_elapsed / LIFETIME, 0.0, 1.0)
		var r := lerpf(6.0, max_radius, t)
		var col := Color(0.95, 0.30, 0.90, 1.0 - t)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col, 2.0, true)
