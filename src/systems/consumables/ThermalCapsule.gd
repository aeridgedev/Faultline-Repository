## Faultline — ThermalCapsule: on use it applies the "Thermal Shield" buff, granting
## temporary resistance to depth/pressure hazard damage. The buff carries
## `hazard_resist` (0.0–1.0); DepthHazard and PressureSystem multiply their tick damage
## by (1 - PlayerStats.hazard_resist()), and the HUD buff panel shows it automatically.
## TBD: use time / duration / resist live in data/world_config.json "consumables"
## (thermal_capsule_use_time, thermal_capsule_duration, thermal_capsule_resist).
class_name ThermalCapsule
extends ConsumableBase

signal thermal_active(duration: float)


func _init() -> void:
	use_time = GameManager.data.get("consumables", {}).get("thermal_capsule_use_time", null)


func _on_use_complete(stats: PlayerStats) -> void:
	var c: Dictionary = GameManager.data.get("consumables", {})
	var dur_v: Variant = c.get("thermal_capsule_duration", null)
	var res_v: Variant = c.get("thermal_capsule_resist", null)
	var duration := float(dur_v) if dur_v != null else 20.0  # TBD: thermal_capsule_duration
	var resist := float(res_v) if res_v != null else 0.75    # TBD: thermal_capsule_resist
	stats.apply_status("Thermal Shield", duration, true, {"hazard_resist": resist})
	thermal_active.emit(duration)
