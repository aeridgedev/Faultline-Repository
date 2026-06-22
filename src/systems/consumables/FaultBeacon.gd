## Faultline — FaultBeacon: places a visible marker at the player's location.
## Primarily for callouts / orientation in deep layers.
## Duration and visibility range TBD.
class_name FaultBeacon
extends ConsumableBase

signal beacon_placed(world_position: Vector2)


func _init() -> void:
	use_time = GameManager.data.get("consumables", {}).get("fault_beacon_use_time", null)


func _on_use_complete(stats: PlayerStats) -> void:
	# Beacon position must come from the player's world position.
	# The node that owns this Resource should connect beacon_placed and pass its position.
	# TODO(step 8): render beacon marker in HUD / world layer.
	beacon_placed.emit(Vector2.ZERO)  # caller must override or connect to set real position
