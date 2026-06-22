## Faultline — match-time storm that descends through layers every ~3.5 min.
## Phase timings and layer order are LOCKED in Constants.STORM_PHASES.
## Applies storm_dps (TBD) each frame to any player whose layer is at or above
## the current storm layer. At CORE_HOLLOW_DEADLINE_SECONDS, any player not in
## Core Hollow is instantly killed.
class_name StormSystem
extends Node

signal storm_advanced(region_name: String)
signal storm_deadline_reached

var _stats: PlayerStats = null

var _elapsed: float = 0.0
var _phase_idx: int = 0
var _deadline_fired: bool = false
var _running: bool = false


func init(stats: PlayerStats) -> void:
	_stats = stats


func start() -> void:
	_running = true
	_elapsed = 0.0
	_phase_idx = 0
	_deadline_fired = false


# --- Time tracking and phase advancement (normal _process, not physics-rate) ---

func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_advance_phase_if_needed()
	_check_deadline()


# --- Damage application (physics-rate for smooth DPS) ---

func _physics_process(delta: float) -> void:
	if not _running or _stats == null or _stats.is_dead or _stats.max_health <= 0.0:
		return
	if not _is_player_in_storm():
		return
	var dps: Variant = GameManager.data.get("storm_dps", null)
	if dps == null:
		return  # TBD: no values until balance pass
	_stats.take_damage(float(dps) * delta)


# --- Phase logic ---

func _advance_phase_if_needed() -> void:
	var phases := Constants.STORM_PHASES
	while _phase_idx < phases.size() - 1:
		var next: Dictionary = phases[_phase_idx + 1]
		if _elapsed >= float(next["start"]):
			_phase_idx += 1
			storm_advanced.emit(phases[_phase_idx]["region"])
		else:
			break


func _check_deadline() -> void:
	if _deadline_fired:
		return
	if _elapsed < Constants.CORE_HOLLOW_DEADLINE_SECONDS:
		return
	_deadline_fired = true
	storm_deadline_reached.emit()
	if _stats == null or _stats.is_dead:
		return
	if _stats.get_layer() != Constants.Layer.CORE_HOLLOW:
		# Kill instantly: deal more than any possible max_health.
		_stats.take_damage(_stats.max_health + 1.0)


func _is_player_in_storm() -> bool:
	if _stats == null:
		return false
	var storm_layer_int := _region_to_layer_int(get_current_region())
	if storm_layer_int < 0:
		return false  # "Atmosphere" phase — no player areas are stormed yet
	# Player is in storm if they haven't descended past the currently stormed layer.
	return _stats.get_layer() <= storm_layer_int


func _region_to_layer_int(region: String) -> int:
	match region:
		"Crust":               return Constants.Layer.CRUST
		"Mantle":              return Constants.Layer.MANTLE
		"Outer Core":          return Constants.Layer.OUTER_CORE
		"Inner Core":          return Constants.Layer.INNER_CORE
		"Core Hollow (final)": return Constants.Layer.CORE_HOLLOW
		_:                     return -1  # "Atmosphere" or unknown


# --- Public query API (used by UI in step 8) ---

func get_elapsed() -> float:
	return _elapsed


func get_current_region() -> String:
	return Constants.STORM_PHASES[_phase_idx]["region"]


func get_phase_end_seconds() -> float:
	var end_val = Constants.STORM_PHASES[_phase_idx]["end"]
	return float(end_val) if end_val != -1 else -1.0
