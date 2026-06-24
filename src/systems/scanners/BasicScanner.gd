## Faultline — BasicScanner: reveals all players within range for 8s (LOCKED).
## Scanned players are NOT notified (LOCKED). Range TBD.
class_name BasicScanner
extends Resource

signal scan_started(scanner_pos: Vector2, radius: float)
signal scan_ended

const DURATION := 8.0  # SCANNER_DURATION_SECONDS (locked)

var _active: bool = false
var _time_remaining: float = 0.0


## Begin a scan from world_pos. Returns false if already active.
func activate(world_pos: Vector2) -> bool:
	if _active:
		return false
	var radius: Variant = GameManager.data.get("basic_scanner_range", null)
	# TBD: range null → print warning; scan still "succeeds" (future UI will show 0 radius).
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
