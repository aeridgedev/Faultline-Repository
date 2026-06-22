## Faultline — player stamina resource; drain/regen logic.
class_name Stamina
extends Node

signal stamina_changed(current: float, max_val: float)
signal stamina_depleted
signal stamina_recovered

var max_stamina: Variant  # TBD: set from GameManager.data["stamina_max"]
var current_stamina: float = 0.0
var is_depleted: bool = false

var _regen_delay_remaining: float = 0.0


func _ready() -> void:
	max_stamina = GameManager.data.get("stamina_max", null)  # TBD: max stamina
	current_stamina = float(max_stamina) if max_stamina != null else 0.0


func _process(delta: float) -> void:
	var _max := float(max_stamina) if max_stamina != null else 0.0
	if current_stamina >= _max:
		return

	if is_depleted and _regen_delay_remaining > 0.0:
		_regen_delay_remaining -= delta
		return

	var regen_rate: Variant = GameManager.data.get("stamina_regen_rate", null)  # TBD: regen rate per second
	if regen_rate == null:
		return

	current_stamina = minf(current_stamina + float(regen_rate) * delta, _max)
	stamina_changed.emit(current_stamina, _max)

	if is_depleted:
		var threshold: Variant = GameManager.data.get("stamina_recovery_threshold", null)  # TBD: recovery threshold
		if threshold != null and current_stamina >= float(threshold):
			is_depleted = false
			stamina_recovered.emit()


func drain(amount: float) -> bool:
	var had_enough: bool = current_stamina >= amount
	current_stamina = maxf(current_stamina - amount, 0.0)
	var _max := float(max_stamina) if max_stamina != null else 0.0
	stamina_changed.emit(current_stamina, _max)

	if current_stamina == 0.0 and not is_depleted:
		is_depleted = true
		var delay: Variant = GameManager.data.get("stamina_regen_delay", null)  # TBD: delay before regen after depletion
		_regen_delay_remaining = float(delay) if delay != null else 0.0
		stamina_depleted.emit()

	return had_enough
