## Faultline — ThermalCapsule: grants temporary heat resistance in extreme layers.
## Effect TBD (reduces DepthHazard damage while active). Duration TBD.
class_name ThermalCapsule
extends ConsumableBase

signal thermal_active(duration: float)


func _init() -> void:
	use_time = GameManager.data.get("consumables", {}).get("thermal_capsule_use_time", null)


func _on_use_complete(stats: PlayerStats) -> void:
	var duration: Variant = GameManager.data.get("consumables", {}).get("thermal_capsule_duration", null)
	# TBD: apply heat resistance modifier. Emitting signal so DepthHazard can listen.
	# TODO(step 6 balance): connect thermal_active in DepthHazard to suppress damage.
	thermal_active.emit(float(duration) if duration != null else 0.0)
