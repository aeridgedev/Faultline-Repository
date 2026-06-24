## Faultline — DeepRadar: longer-range scanner; same 8s duration (LOCKED) as BasicScanner
## but with a larger detection radius (TBD). Uses deep_radar_range key from data.
class_name DeepRadar
extends Resource

signal scan_started(scanner_pos: Vector2, radius: float)
signal scan_ended

const DURATION := 8.0  # SCANNER_DURATION_SECONDS (locked)

var _active: bool = false
var _time_remaining: float = 0.0


func activate(world_pos: Vector2) -> bool:
	if _active:
		return false
	var radius: Variant = GameManager.data.get("deep_radar_range", null)
	_active = true
	_time_remaining = DURATION
	scan_started.emit(world_pos, float(radius) if radius != null else 0.0)
	return true


func tick(delta: float) -> void:
	if not _active:
		return
	_time_remaining -= delta
	if _time_remaining <= 0.0:
		_active = false
		scan_ended.emit()


func is_active() -> bool:
	return _active
