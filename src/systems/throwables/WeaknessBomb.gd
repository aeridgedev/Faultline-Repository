## Faultline — Weakness Bomb throwable. On impact, every target in the blast radius
## has its outgoing melee damage reduced: the "Weakened" status carries
## `damage_output_mult` (< 1.0), which PlayerController applies to swing damage and the
## HUD debuff panel shows automatically. A brief purple ring marks the blast.
## TBD: radius/duration/strength live in data/world_config.json "throwables"
## (weakness_radius, weakness_duration, weakness_damage_mult) — dev placeholders.
class_name WeaknessBomb
extends ThrowableBase


func _on_impact(impact_point: Vector2, _hit_body: Node) -> void:
	var radius := float(_data("weakness_radius", 48.0))            # TBD: weakness_radius
	var duration := float(_data("weakness_duration", 6.0))         # TBD: weakness_duration
	var mult := float(_data("weakness_damage_mult", 0.60))         # TBD: weakness_damage_mult
	for target: Dictionary in targets_in_radius(radius):
		var stats := target["stats"] as PlayerStats
		stats.apply_status("Weakened", duration, false, {"damage_output_mult": mult})
	var ring := ImpactRing.new()
	ring.max_radius = radius
	ring.ring_color = Color(0.68, 0.32, 0.92)   # purple
	effect_parent().add_child(ring)
	ring.global_position = impact_point


func _dev_tint() -> Color:
	return Color(0.68, 0.32, 0.92)   # purple


## One-shot expanding hollow ring: grows from a point out to max_radius over ~0.4s
## while fading, then frees itself. Lives in the world (never a child of the freed
## projectile). Reused visual — same shape as Heat Charge's flash.
class ImpactRing extends Node2D:
	var max_radius: float = 48.0
	var ring_color: Color = Color(0.68, 0.32, 0.92)
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
