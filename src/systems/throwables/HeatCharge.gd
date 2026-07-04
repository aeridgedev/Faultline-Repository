## Faultline — Heat Charge throwable. On impact, every target in the blast radius
## catches fire: the "Burning" status carries `dot_dps`/`dot_interval`, and
## PlayerStats ticks the damage itself each interval. A flame indicator is attached
## to each TARGET body; a brief orange flash marks the blast point.
## TBD: radius/duration/dps live in data/world_config.json "throwables"
## (heat_radius, heat_duration, heat_dps) — dev placeholders pending balance pass.
class_name HeatCharge
extends ThrowableBase


func _on_impact(impact_point: Vector2, _hit_body: Node) -> void:
	var radius := float(_data("heat_radius", 48.0))       # TBD: heat_radius
	var duration := float(_data("heat_duration", 5.0))    # TBD: heat_duration
	var dps := float(_data("heat_dps", 4.0))              # TBD: heat_dps
	for target: Dictionary in targets_in_radius(radius):
		var stats := target["stats"] as PlayerStats
		# PlayerStats._tick_dot applies dps in dot_interval chunks; no wiring here.
		stats.apply_status("Burning", duration, false, {"dot_dps": dps, "dot_interval": 1.0})
		_attach_indicator(target["body"] as Node2D, duration)
	var flash := ImpactRing.new()
	flash.max_radius = radius
	flash.ring_color = Color(1.0, 0.52, 0.14)   # orange
	effect_parent().add_child(flash)
	flash.global_position = impact_point


func _dev_tint() -> Color:
	return Color(1.0, 0.42, 0.20)   # orange-red


# One indicator per body: re-hits refresh the existing timer instead of stacking a
# second tint/restore pair (which would clear the warm tint too early).
func _attach_indicator(body: Node2D, duration: float) -> void:
	var existing := body.get_node_or_null("BurnIndicator") as BurnIndicator
	if existing != null:
		existing.refresh(duration)
		return
	var indicator := BurnIndicator.new()
	indicator.name = "BurnIndicator"
	indicator.duration = duration
	body.add_child(indicator)


## Warm tint on the burning body + small flickering flame pixels above the head.
## Child of the target body so it survives the projectile freeing itself; restores
## the body's modulate and frees itself when the burn expires.
class BurnIndicator extends Node2D:
	var duration: float = 5.0
	var _elapsed: float = 0.0
	var _flip_timer: float = 0.0
	var _flip: bool = false

	const TINT := Color(1.0, 0.62, 0.45)
	const FLAME_HOT := Color(1.0, 0.86, 0.30)
	const FLAME_MID := Color(1.0, 0.48, 0.12)
	const FLIP_INTERVAL := 0.12

	func _ready() -> void:
		z_index = 50   # above the body sprite
		var parent := get_parent() as Node2D
		if is_instance_valid(parent):
			parent.modulate = TINT

	func refresh(new_duration: float) -> void:
		duration = new_duration
		_elapsed = 0.0

	func _process(delta: float) -> void:
		_elapsed += delta
		_flip_timer += delta
		if _flip_timer >= FLIP_INTERVAL:
			_flip_timer = 0.0
			_flip = not _flip
			queue_redraw()
		if _elapsed >= duration:
			var parent := get_parent() as Node2D
			if is_instance_valid(parent):
				parent.modulate = Color.WHITE
			queue_free()

	func _draw() -> void:
		# Three tiny flames above the head (~y −22); the middle one flickers height.
		var mid_h := 5.0 if _flip else 3.5
		_draw_flame(Vector2(-5.0, -20.0), 3.0, FLAME_MID)
		_draw_flame(Vector2(0.0, -22.0), mid_h, FLAME_HOT)
		_draw_flame(Vector2(5.0, -20.0), 3.0, FLAME_MID)

	func _draw_flame(base: Vector2, height: float, color: Color) -> void:
		# Simple teardrop: a triangle tapering upward.
		var points := PackedVector2Array([
			base + Vector2(-1.5, 0.0),
			base + Vector2(1.5, 0.0),
			base + Vector2(0.0, -height),
		])
		draw_colored_polygon(points, color)


## One-shot expanding hollow ring (same shape as Weakness Bomb's ring).
class ImpactRing extends Node2D:
	var max_radius: float = 48.0
	var ring_color: Color = Color(1.0, 0.52, 0.14)
	const LIFETIME := 0.4
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
		var col := ring_color
		col.a = 1.0 - t
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, 2.0, true)
