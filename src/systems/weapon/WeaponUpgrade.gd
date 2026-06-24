## Faultline — Upgrade Template application for weapons: raises tier, restores durability.
## Mirrors DrillUpgrade exactly; ceiling is Constants.TIER_CEILING (Legendary).
class_name WeaponUpgrade
extends RefCounted


static func can_upgrade(weapon: WeaponBase) -> bool:
	return weapon.tier < Constants.TIER_CEILING


static func apply(weapon: WeaponBase) -> void:
	if not can_upgrade(weapon):
		return
	weapon.tier = weapon.tier + 1
	weapon.init_from_data()   # reload scaled stats for new tier
	weapon.restore_durability()
