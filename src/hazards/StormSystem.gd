## Faultline — descending storm that consumes layers every ~3.5 min.
##
## Storm front moves continuously through each layer, interpolated between the
## layer's top and bottom over the phase duration. Position-based check:
##   player is in storm zone  ↔  player.Y < storm_front_Y
## (Godot Y increases downward; the storm descends from above.)
##
## Visible effects when inside the storm zone:
##   • Passive DPS (storm_dps from data)
##   • Reduced drill efficiency (storm_drill_efficiency_mult)
##   • Reduced healing (storm_heal_mult)
##   • Red screen-space overlay
##
## World-space visual: a Polygon2D descending from off-screen top to the storm
## front, gradient from solid red (deep in storm) to nearly transparent at front.
class_name StormSystem
extends Node

signal storm_advanced(region_name: String)
signal storm_deadline_reached

var _stats: PlayerStats = null
var _layer_manager: LayerManager = null

var _phase_idx: int = 0
var _deadline_fired: bool = false
var _running: bool = false

# World-space storm zone polygon (visible in the game world)
var _storm_poly: Polygon2D = null
# Bright leading-edge strip that makes the approaching wall clearly visible.
var _wall_strip: Polygon2D = null

# Screen-space tint overlay (CanvasLayer above world, below HUD)
var _screen_layer: CanvasLayer = null
var _screen_overlay: ColorRect = null


func init(stats: PlayerStats, layer_manager: LayerManager) -> void:
	_stats = stats
	_layer_manager = layer_manager
	_build_visuals()


func _build_visuals() -> void:
	# World-space polygon: sits in World's coordinate space via the Node ancestor
	_storm_poly = Polygon2D.new()
	_storm_poly.name = "StormZonePoly"
	_storm_poly.z_index = -1
	_storm_poly.z_as_relative = true
	add_child(_storm_poly)

	# Bright leading-edge strip — a thin band just at the storm front so the
	# approaching wall is unmistakable even when the player is far below it.
	_wall_strip = Polygon2D.new()
	_wall_strip.name = "StormWallStrip"
	_wall_strip.z_index = 0
	_wall_strip.z_as_relative = true
	add_child(_wall_strip)

	# Screen-space red tint when inside storm
	_screen_layer = CanvasLayer.new()
	_screen_layer.name = "StormScreenLayer"
	_screen_layer.layer = 1
	add_child(_screen_layer)

	_screen_overlay = ColorRect.new()
	_screen_overlay.name = "StormOverlay"
	_screen_overlay.color = Color(0.70, 0.08, 0.04, 0.0)
	_screen_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_layer.add_child(_screen_overlay)


func start() -> void:
	_running = true
	_phase_idx = 0
	_deadline_fired = false


func _process(_delta: float) -> void:
	if not _running:
		return
	_advance_phase_if_needed()
	_check_deadline()
	_update_visuals()


func _physics_process(delta: float) -> void:
	if not _running or _stats == null or _stats.is_dead or _stats.max_health <= 0.0:
		return
	if not _is_player_in_storm():
		return
	var dps := _current_storm_dps()
	if dps <= 0.0:
		return
	_stats.take_damage(dps * delta, "The Storm")


## Per-phase storm damage-per-second (2026-07-06). Previously the storm applied a
## single flat `storm_dps` (world_config.json) at every depth, so it was neither
## forgiving early nor dangerous late. It now reads the escalating per-phase curve
## from storm_timings.json (`data["storm"]["phases"][idx].damage_per_second`),
## indexed by the SAME authoritative elapsed-time phase index the UI/region use, so
## damage scales: ignorable in the Crust, lethal in the Core Hollow. Falls back to
## the legacy flat `storm_dps` only if the per-phase data is missing (null-safety).
func _current_storm_dps() -> float:
	var storm_data: Variant = GameManager.data.get("storm", null)
	if storm_data is Dictionary:
		var phases: Variant = storm_data.get("phases", null)
		if phases is Array:
			var idx := _compute_phase_idx(GameManager.match_elapsed)
			if idx >= 0 and idx < phases.size():
				var pd: Variant = phases[idx]
				if pd is Dictionary and pd.get("damage_per_second", null) != null:
					return float(pd["damage_per_second"])
	var flat: Variant = GameManager.data.get("storm_dps", null)
	return float(flat) if flat != null else 0.0


# --- Visuals ---------------------------------------------------------------

func _update_visuals() -> void:
	var front_y := get_storm_front_y()
	_update_storm_poly(front_y)
	_update_screen_overlay()


func _update_storm_poly(front_y: float) -> void:
	if _storm_poly == null or _layer_manager == null:
		return
	if front_y < -500.0:
		_storm_poly.polygon = PackedVector2Array()
		if _wall_strip != null:
			_wall_strip.polygon = PackedVector2Array()
		return

	var world_w_var = _layer_manager.world_width_px()
	if world_w_var == null:
		return
	var w := float(world_w_var) + 200.0

	# Storm body: nearly transparent far above, building to semi-opaque at front.
	# Players see the wall COMING rather than a solid block overhead.
	_storm_poly.polygon = PackedVector2Array([
		Vector2(-100.0, -5000.0),
		Vector2(w,      -5000.0),
		Vector2(w,       front_y),
		Vector2(-100.0,  front_y),
	])
	_storm_poly.vertex_colors = PackedColorArray([
		Color(0.70, 0.08, 0.04, 0.08),   # top-left  — barely visible far above
		Color(0.70, 0.08, 0.04, 0.08),   # top-right — barely visible far above
		Color(0.80, 0.18, 0.04, 0.48),   # front-right — thick red at leading edge
		Color(0.80, 0.18, 0.04, 0.48),   # front-left  — thick red at leading edge
	])

	# Wall strip: a narrow bright band (3 tiles) just below the front so the
	# exact storm boundary is obvious even through terrain.
	if _wall_strip != null:
		var strip_h := float(Constants.TILE_SIZE * 3)
		_wall_strip.polygon = PackedVector2Array([
			Vector2(-100.0, front_y),
			Vector2(w,      front_y),
			Vector2(w,      front_y + strip_h),
			Vector2(-100.0, front_y + strip_h),
		])
		_wall_strip.vertex_colors = PackedColorArray([
			Color(0.98, 0.55, 0.10, 0.88),   # top-left  — bright orange leading edge
			Color(0.98, 0.55, 0.10, 0.88),   # top-right
			Color(0.80, 0.15, 0.04, 0.00),   # bottom-right — fades to transparent
			Color(0.80, 0.15, 0.04, 0.00),   # bottom-left
		])


func _update_screen_overlay() -> void:
	if _screen_overlay == null:
		return
	if _is_player_in_storm():
		var alpha: Variant = GameManager.data.get("storm_overlay_alpha", 0.35)
		_screen_overlay.color.a = float(alpha)
	else:
		_screen_overlay.color.a = 0.0


# --- Phase advancement -----------------------------------------------------

func _advance_phase_if_needed() -> void:
	var elapsed := GameManager.match_elapsed
	var phases := Constants.STORM_PHASES
	while _phase_idx < phases.size() - 1:
		var next: Dictionary = phases[_phase_idx + 1]
		if elapsed >= float(next["start"]):
			_phase_idx += 1
			storm_advanced.emit(phases[_phase_idx]["region"])
		else:
			break


func _check_deadline() -> void:
	if _deadline_fired:
		return
	if GameManager.match_elapsed < Constants.CORE_HOLLOW_DEADLINE_SECONDS:
		return
	_deadline_fired = true
	storm_deadline_reached.emit()
	if _stats == null or _stats.is_dead:
		return
	if _stats.get_layer() != Constants.Layer.CORE_HOLLOW:
		_stats.take_damage(_stats.max_health + 1.0, "The Storm")


# --- Storm front position --------------------------------------------------

## World-space Y of the descending storm front.
## Returns a large negative number (< -500) when the storm has not yet entered
## the playfield (Atmosphere phase). Increases as the storm descends.
func get_storm_front_y() -> float:
	var phases := Constants.STORM_PHASES
	var current: Dictionary = phases[_phase_idx]
	var region: String = current["region"]

	if region == "Atmosphere":
		return -9999.0

	if region == "Core Hollow (final)":
		if _layer_manager == null:
			return 99999.0
		var bottom = _layer_manager.world_height_px()
		return float(bottom) if bottom != null else 99999.0

	var layer := _region_to_layer_int(region)
	if layer < 0 or _layer_manager == null:
		return -9999.0

	var layer_top = _layer_manager.get_layer_top_y(layer)
	var layer_bottom = _layer_manager.get_layer_bottom_y(layer)
	if layer_top == null or layer_bottom == null:
		return -9999.0

	var phase_start := float(current["start"])
	var phase_end_var = current["end"]
	var phase_end := float(phase_end_var) if phase_end_var != -1 else float(phase_start + 210.0)
	var t := clampf((GameManager.match_elapsed - phase_start) / (phase_end - phase_start), 0.0, 1.0)
	return lerpf(float(layer_top), float(layer_bottom), t)


# --- Storm zone check (position-based) ------------------------------------

func _is_player_in_storm() -> bool:
	if _stats == null:
		return false
	var front_y := get_storm_front_y()
	if front_y < -500.0:
		return false   # Atmosphere phase — no storm zone yet
	var player := _stats.get_parent() as Node2D
	if player == null:
		return false
	return player.global_position.y < front_y


# --- Public modifier API (queried by PlayerController + PlayerStats) -------

## Returns the drill dig-time multiplier. Drill takes longer in the storm.
## Callers divide dig_duration by this: lower value → slower drilling.
func get_drill_efficiency_mult() -> float:
	if not _is_player_in_storm():
		return 1.0
	var mult: Variant = GameManager.data.get("storm_drill_efficiency_mult", null)
	return float(mult) if mult != null else 0.5


## Returns the heal effectiveness multiplier. Healing is reduced in the storm.
func get_heal_mult() -> float:
	if not _is_player_in_storm():
		return 1.0
	var mult: Variant = GameManager.data.get("storm_heal_mult", null)
	return float(mult) if mult != null else 0.5


## True while the storm front is anywhere inside the playfield.
func is_storm_active() -> bool:
	return _running and get_storm_front_y() >= -500.0


# --- Public query API (used by StormTimer UI) ------------------------------

func get_elapsed() -> float:
	return GameManager.match_elapsed


## Compute the current phase index directly from elapsed time.
## This is the authoritative source for UI queries — it does NOT rely on
## _phase_idx being up to date, so it is safe to call from any node's _process
## regardless of execution order.
func _compute_phase_idx(elapsed: float) -> int:
	var phases := Constants.STORM_PHASES
	for i in range(phases.size() - 1, -1, -1):
		if elapsed >= float(phases[i]["start"]):
			return i
	return 0


func get_current_region() -> String:
	var idx := _compute_phase_idx(GameManager.match_elapsed)
	return Constants.STORM_PHASES[idx]["region"]


func get_phase_end_seconds() -> float:
	var idx := _compute_phase_idx(GameManager.match_elapsed)
	var end_val = Constants.STORM_PHASES[idx]["end"]
	return float(end_val) if end_val != -1 else -1.0


# --- Helpers ---------------------------------------------------------------

func _region_to_layer_int(region: String) -> int:
	match region:
		"Crust":               return Constants.Layer.CRUST
		"Mantle":              return Constants.Layer.MANTLE
		"Outer Core":          return Constants.Layer.OUTER_CORE
		"Inner Core":          return Constants.Layer.INNER_CORE
		"Core Hollow (final)": return Constants.Layer.CORE_HOLLOW
		_:                     return -1
