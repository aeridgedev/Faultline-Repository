## Faultline — Smoke Bomb throwable. On impact, spawns a lingering dark cloud that
## visually obscures players and terrain beneath it. Pure occlusion — no status
## effect is applied; hiding is the entire mechanic.
## TBD: radius/duration live in data/world_config.json "throwables"
## (smoke_radius, smoke_duration) — dev placeholders pending balance pass.
class_name SmokeBomb
extends ThrowableBase


func _on_impact(impact_point: Vector2, _hit_body: Node) -> void:
	var radius := float(_data("smoke_radius", 56.0))     # TBD: smoke_radius
	var duration := float(_data("smoke_duration", 6.0))  # TBD: smoke_duration
	var cloud := SmokeCloud.new()
	cloud.radius = radius
	cloud.duration = duration
	# Parented to the world, never to this projectile — the projectile frees
	# itself right after impact and would take the cloud with it.
	effect_parent().add_child(cloud)
	cloud.global_position = impact_point


func _dev_tint() -> Color:
	return Color(0.62, 0.62, 0.64)   # neutral gray


## The vision obscurer: layered filled circles drawn OVER players and terrain
## (high z_index), gently pulsing, self-freeing after `duration`.
class SmokeCloud extends Node2D:
	var radius: float = 56.0
	var duration: float = 6.0
	var _elapsed: float = 0.0

	const FADE_IN := 0.2    # avoid pop-in
	const FADE_OUT := 0.5   # avoid pop-out at expiry

	func _ready() -> void:
		z_index = 100   # draw above players and the terrain TileMap

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= duration:
			queue_free()
			return
		queue_redraw()   # alpha pulse + fade envelope are time-driven

	func _draw() -> void:
		var fade := minf(_elapsed / FADE_IN, 1.0)
		fade = minf(fade, maxf(duration - _elapsed, 0.0) / FADE_OUT)
		fade = clampf(fade, 0.0, 1.0)
		var pulse := 1.0 + 0.06 * sin(_elapsed * 2.4)   # subtle breathing, not a strobe
		# Soft wide edge under a darker core: two layers read as volume without shaders.
		draw_circle(Vector2.ZERO, radius * pulse, Color(0.13, 0.13, 0.15, 0.55 * fade))
		draw_circle(Vector2.ZERO, radius * 0.62 * pulse, Color(0.08, 0.08, 0.10, 0.85 * fade))
