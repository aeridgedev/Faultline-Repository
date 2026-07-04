## Faultline — Bloodstim: a short combat stim. On use it applies the "Bloodstim" buff,
## boosting both move speed and outgoing melee damage for a duration. The buff carries
## `move_speed_mult` / `damage_output_mult`, which PlayerController reads for movement
## and swing damage, and the HUD buff panel shows it automatically — no extra wiring.
## TBD: use time / duration / strengths live in data/world_config.json "consumables"
## (bloodstim_use_time, bloodstim_duration, bloodstim_speed_mult, bloodstim_damage_mult).
class_name Bloodstim
extends ConsumableBase

signal bloodstim_active(duration: float)


func _init() -> void:
	use_time = GameManager.data.get("consumables", {}).get("bloodstim_use_time", null)


func _on_use_complete(stats: PlayerStats) -> void:
	var c: Dictionary = GameManager.data.get("consumables", {})
	var dur_v: Variant = c.get("bloodstim_duration", null)
	var spd_v: Variant = c.get("bloodstim_speed_mult", null)
	var dmg_v: Variant = c.get("bloodstim_damage_mult", null)
	var duration := float(dur_v) if dur_v != null else 6.0     # TBD: bloodstim_duration
	var speed_mult := float(spd_v) if spd_v != null else 1.30  # TBD: bloodstim_speed_mult
	var damage_mult := float(dmg_v) if dmg_v != null else 1.30 # TBD: bloodstim_damage_mult
	stats.apply_status("Bloodstim", duration, true, {
		"move_speed_mult": speed_mult,
		"damage_output_mult": damage_mult,
	})
	bloodstim_active.emit(duration)
