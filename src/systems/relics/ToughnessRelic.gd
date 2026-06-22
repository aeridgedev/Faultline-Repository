## Faultline — permanent Toughness relic state for one player.
## Applies a damage reduction multiplier to PlayerStats once activated.
## Permanent means it does NOT expire during the match.
class_name ToughnessRelic
extends RefCounted

var is_active: bool = false


func activate(stats: PlayerStats) -> void:
	if is_active:
		return
	is_active = true
	var reduction: Variant = GameManager.data.get("relic_strength", {}).get("toughness_reduction", null)
	# TBD: reduction null → 0.0 (no change) until balance pass.
	stats.damage_reduction = float(reduction) if reduction != null else 0.0


# Toughness is permanent — deactivate is provided only for edge-case tests; never called during play.
func deactivate(stats: PlayerStats) -> void:
	is_active = false
	stats.damage_reduction = 0.0
