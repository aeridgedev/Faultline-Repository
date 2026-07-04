## Faultline — Paralysis Bomb throwable. On impact, every target in the blast
## radius is frozen in place: the "Paralyzed" status carries `frozen: true`,
## which PlayerStats/PlayerController already honor (blocks movement + actions).
## A frozen indicator (icy tint + ice-crystal pixels) is attached to each TARGET
## body — never to this projectile, which frees itself right after impact.
## TBD: radius/duration live in data/world_config.json "throwables"
## (paralysis_radius, paralysis_duration) — dev placeholders pending balance pass.
class_name ParalysisBomb
extends ThrowableBase


func _on_impact(_impact_point: Vector2, _hit_body: Node) -> void:
	var radius := float(_data("paralysis_radius", 44.0))     # TBD: paralysis_radius
	var duration := float(_data("paralysis_duration", 1.5))  # TBD: paralysis_duration
	for target: Dictionary in targets_in_radius(radius):
		var stats := target["stats"] as PlayerStats
		stats.apply_status("Paralyzed", duration, false, {"frozen": true})
		_attach_indicator(target["body"] as Node2D, duration)


func _dev_tint() -> Color:
	return Color(0.55, 0.80, 1.0)   # ice blue


# One indicator per body: re-hits refresh the existing timer instead of stacking
# a second tint/restore pair (a stacked pair would restore modulate too early).
func _attach_indicator(body: Node2D, duration: float) -> void:
	var existing := body.get_node_or_null("FrozenIndicator") as FrozenIndicator
	if existing != null:
		existing.refresh(duration)
		return
	var indicator := FrozenIndicator.new()
	indicator.name = "FrozenIndicator"
	indicator.duration = duration
	body.add_child(indicator)


## Icy-blue tint on the frozen body + small ice-crystal diamonds above the head.
## Child of the target body so it survives the projectile freeing itself; restores
## the body's modulate and frees itself when the paralysis expires.
class FrozenIndicator extends Node2D:
	var duration: float = 1.5
	var _elapsed: float = 0.0

	const TINT := Color(0.55, 0.80, 1.0)
	const CRYSTAL := Color(0.80, 0.93, 1.0)
	const CRYSTAL_DIM := Color(0.62, 0.82, 0.98)

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
		if _elapsed >= duration:
			var parent := get_parent() as Node2D
			if is_instance_valid(parent):
				parent.modulate = Color.WHITE
			queue_free()

	func _draw() -> void:
		# Three small diamond "crystals" floating above the head (~y −22).
		_draw_crystal(Vector2(-6.0, -21.0), 1.5, CRYSTAL_DIM)
		_draw_crystal(Vector2(0.0, -24.0), 2.0, CRYSTAL)
		_draw_crystal(Vector2(6.0, -22.0), 1.5, CRYSTAL_DIM)

	func _draw_crystal(center: Vector2, size: float, color: Color) -> void:
		var points := PackedVector2Array([
			center + Vector2(0.0, -size),
			center + Vector2(size, 0.0),
			center + Vector2(0.0, size),
			center + Vector2(-size, 0.0),
		])
		draw_colored_polygon(points, color)
