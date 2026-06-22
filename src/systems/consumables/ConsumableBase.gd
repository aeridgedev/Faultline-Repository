## Faultline — base consumable Resource. Subclasses override _on_use_complete().
## use_time (seconds to hold to consume) is TBD — null until balance pass.
class_name ConsumableBase
extends Resource

signal use_completed
signal use_interrupted

var use_time: Variant = null   # TBD: null until balance pass; 1.0s fallback at runtime
var _use_progress: float = 0.0
var _using: bool = false


## Call each physics frame while the player holds the use key.
func tick_use(delta: float, stats: PlayerStats) -> void:
	if not _using:
		_using = true
		_use_progress = 0.0
	_use_progress += delta
	var required := float(use_time) if use_time != null else 1.0
	if _use_progress >= required:
		_using = false
		_use_progress = 0.0
		_on_use_complete(stats)
		use_completed.emit()


## Call when the player releases the use key before finishing.
func interrupt_use() -> void:
	_using = false
	_use_progress = 0.0
	use_interrupted.emit()


## Progress from 0.0 to 1.0 — drives the use-progress bar in the HUD (step 8).
func use_progress() -> float:
	if not _using:
		return 0.0
	var required := float(use_time) if use_time != null else 1.0
	return clampf(_use_progress / required, 0.0, 1.0)


func _on_use_complete(stats: PlayerStats) -> void:
	pass  # override in subclasses
