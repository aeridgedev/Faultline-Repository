## Faultline — Upgrade Template application for drills: raises tier, restores durability.
class_name DrillUpgrade
extends RefCounted


static func can_upgrade(drill: DrillBase) -> bool:
	return drill.tier < Constants.TIER_CEILING


static func apply(drill: DrillBase) -> void:
	if not can_upgrade(drill):
		return
	drill.tier = drill.tier + 1
	drill.init_from_data()   # reload max_durability for the new tier
	drill.restore_durability()
