## Faultline — Bloodstim: short burst that boosts move speed and damage output.
## Uses RelicManager-style multipliers stored in player stats. TBD values.
class_name Bloodstim
extends ConsumableBase

signal bloodstim_active(duration: float)


func _init() -> void:
	use_time = GameManager.data.get("consumables", {}).get("bloodstim_use_time", null)


func _on_use_complete(stats: PlayerStats) -> void:
	var duration: Variant = GameManager.data.get("consumables", {}).get("bloodstim_duration", null)
	# TBD: boost speed + damage for duration. Signal lets PlayerController respond.
	# TODO(step 6 balance): apply multipliers similar to Haste + Strength relics.
	bloodstim_active.emit(float(duration) if duration != null else 0.0)
