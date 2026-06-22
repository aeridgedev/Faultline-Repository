## Faultline — weapon class static accessors (spawn weight, passive description).
## class_name WeaponClassData to avoid shadowing Constants.WeaponClass enum.
class_name WeaponClassData
extends RefCounted


static func spawn_weight(wc: Constants.WeaponClass) -> Variant:
	var class_key := Constants.WEAPON_CLASS_NAMES[wc]
	return (
		GameManager.data
		.get("weapons", {})
		.get("classes", {})
		.get(class_key, {})
		.get("spawn_weight", null)  # TBD: balance pass
	)


# Returns the passive description string for Epic/Legendary tiers, or "" if none.
static func passive_description(wc: Constants.WeaponClass, tier: Constants.Tier) -> String:
	var class_key := Constants.WEAPON_CLASS_NAMES[wc]
	var tier_key  := Constants.TIER_NAMES[tier].to_lower()
	return (
		GameManager.data
		.get("weapons", {})
		.get("classes", {})
		.get(class_key, {})
		.get("passives", {})
		.get(tier_key, "")
	)
