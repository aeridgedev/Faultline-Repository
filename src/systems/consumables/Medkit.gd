## Faultline — Medkit: slow channel that heals a large amount on completion.
##
## Contrast with Lytes: Lytes is the fast, small heal (0.8s / 25 HP), Medkit is the slow,
## large one (2.0s / 60 HP). Both apply their heal at completion.
##
## HEALING APPLIES ON COMPLETION, NEVER PER TICK (changed 2026-07-31). The original version
## healed incrementally inside tick_use() — `medkit_heal_total * (0.5 / use_time)` every
## 0.5s of channel — while the item is only consumed from the hotbar when the channel
## COMPLETES (ConsumableBase emits use_completed -> PlayerController._on_consumable_completed
## -> InventoryManager.remove_item). Those two facts together made one Medkit an infinite
## healing source: hold G for ~0.5s to bank a 15 HP tick, release before the 2.0s channel
## finishes so interrupt_use() resets the progress, and repeat forever — the item never
## reaches completion, so it is never consumed. It was made worse by Medkit not overriding
## interrupt_use(), so `_last_tick` kept accumulating across separate attempts and even
## short taps eventually crossed the tick threshold.
##
## Applying at completion makes the cost real: the full 2.0s channel must finish to get any
## healing, and finishing it consumes the item. This also makes Medkit consistent with every
## other consumable — Lytes, Bloodstim, ThermalCapsule and FaultBeacon all act in
## _on_use_complete(). Do not move a consumable's effect back into tick_use() unless
## partial-use consumption is solved first.
##
## Balance values are unchanged: still medkit_heal_total (60) over medkit_use_time (2.0).
class_name Medkit
extends ConsumableBase


func _init() -> void:
	use_time = GameManager.data.get("consumables", {}).get("medkit_use_time", null)


func _on_use_complete(stats: PlayerStats) -> void:
	var total: Variant = GameManager.data.get("consumables", {}).get("medkit_heal_total", null)
	if total == null:
		return  # TBD: no heal value configured
	# heal() applies the storm heal-reduction multiplier and clamps to max_health.
	stats.heal(float(total))
