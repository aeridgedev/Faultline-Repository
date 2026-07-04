## Faultline — Dust Capsule throwable. On impact, spawns a sandy dust cloud (partial
## visual obscuring, lighter than smoke) and slows every player caught in the radius
## via the "Dusted" status — PlayerController and the HUD debuff panel pick that up
## automatically through PlayerStats.status_move_speed_mult().
## TBD: radius/duration/slow live in data/world_config.json "throwables"
## (dust_radius, dust_duration, dust_slow_mult) — dev placeholders pending balance pass.
class_name DustCapsule
extends ThrowableBase


func _on_impact(impact_point: Vector2, _hit_body: Node) -> void:
	var radius := float(_data("dust_radius", 56.0))        # TBD: dust_radius
	var duration := float(_data("dust_duration", 5.0))     # TBD: dust_duration
	var slow_mult := float(_data("dust_slow_mult", 0.65))  # TBD: dust_slow_mult
	var cloud := DustCloud.new()
	cloud.radius = radius
	cloud.duration = duration
	# Parented to the world, never to this projectile — the projectile frees
	# itself right after impact and would take the cloud with it.
	effect_parent().add_child(cloud)
	cloud.global_position = impact_point
	for entry: Dictionary in targets_in_radius(radius):
		(entry["stats"] as PlayerStats).apply_status(
			"Dusted", duration, false, {"move_speed_mult": slow_mult})


func _dev_tint() -> Color:
	return Color(0.82, 0.70, 0.48)   # sandy tan


## Sandy-brown visual companion to the slow. Lower alpha than SmokeCloud — dust
## obscures less than smoke; the mechanical effect is the "Dusted" slow, not hiding.
class DustCloud extends Node2D:
	var radius: float = 56.0
	var duration: float = 5.0
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
		draw_circle(Vector2.ZERO, radius * pulse, Color(0.72, 0.58, 0.36, 0.35 * fade))
		draw_circle(Vector2.ZERO, radius * 0.62 * pulse, Color(0.60, 0.46, 0.26, 0.55 * fade))
