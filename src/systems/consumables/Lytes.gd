## Faultline — Lytes: fast, small health restore. Use time TBD.
class_name Lytes
extends ConsumableBase


func _init() -> void:
	use_time = GameManager.data.get("consumables", {}).get("lytes_use_time", null)


func _on_use_complete(stats: PlayerStats) -> void:
	var amount: Variant = GameManager.data.get("consumables", {}).get("lytes_heal", null)
	if amount == null:
		return  # TBD: no value until balance pass
	stats.heal(float(amount))
