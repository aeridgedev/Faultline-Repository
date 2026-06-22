## Faultline — LifeCapsule: one-use item that prevents the next lethal hit,
## leaving the player at 1 HP. Sets life_capsule_active on PlayerStats;
## PlayerStats.take_damage() consumes the flag when a lethal hit lands.
## Spawn rate TBD.
class_name LifeCapsule
extends Resource


func activate(stats: PlayerStats) -> void:
	stats.life_capsule_active = true


func deactivate(stats: PlayerStats) -> void:
	stats.life_capsule_active = false
