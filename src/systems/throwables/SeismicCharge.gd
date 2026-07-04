## Faultline — Seismic Charge throwable. On impact, destroys every DESTRUCTIBLE
## terrain tile within a small radius. Deals NO player damage — terrain destruction
## is the entire effect (by design). A one-shot shockwave marks the blast.
## LOCKED design rule: the Core Hollow shell may ONLY be breached by drilling, so
## CORE_HOLLOW_SHELL is excluded here alongside indestructible BEDROCK.
## TBD: radius lives in data/world_config.json "throwables" (seismic_radius_tiles,
## in TILES) — a dev placeholder pending balance pass.
class_name SeismicCharge
extends ThrowableBase


func _on_impact(impact_point: Vector2, _hit_body: Node) -> void:
	if _terrain_manager == null:
		return   # no terrain to affect (defensive: should always be set on throw)
	var r := int(_data("seismic_radius_tiles", 3))   # TBD: seismic_radius_tiles (TILES)
	var center := _terrain_manager.world_to_cell(impact_point)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue   # circular blast, not a square
			var cell := center + Vector2i(dx, dy)
			var type: Variant = _terrain_manager.get_tile_type(cell)
			if type == null:
				continue
			# Never destroy the playfield bound or the Core Hollow wall (drill-only rule).
			if type == Constants.TerrainType.BEDROCK or type == Constants.TerrainType.CORE_HOLLOW_SHELL:
				continue
			_terrain_manager.destroy_tile(cell)
	var wave := Shockwave.new()
	wave.max_radius = float(r) * float(Constants.TILE_SIZE)
	effect_parent().add_child(wave)
	wave.global_position = impact_point


func _dev_tint() -> Color:
	return Color(1.0, 0.90, 0.20)   # bright yellow


## One-shot expanding shockwave: two concentric rings (yellow-orange outer, white-hot
## inner) grow from the impact and fade, then free themselves.
class Shockwave extends Node2D:
	var max_radius: float = 48.0
	const LIFETIME := 0.35
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
		var outer_r := lerpf(4.0, max_radius, t)
		var inner_r := outer_r * 0.6
		var fade := 1.0 - t
		draw_arc(Vector2.ZERO, outer_r, 0.0, TAU, 48, Color(1.0, 0.66, 0.16, fade), 3.0, true)
		draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, 40, Color(1.0, 0.96, 0.82, fade), 2.0, true)
