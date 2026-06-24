## Faultline — weapon class static accessors (spawn weight, passive description).
## class_name WeaponClassData to avoid shadowing Constants.WeaponClass enum.
class_name WeaponClassData
extends RefCounted


static func spawn_weight(wc: Constants.WeaponClass) -> Variant:
	var class_key: String = Constants.WEAPON_CLASS_NAMES[wc]
	var weapons := GameManager.data.get("weapons", {}) as Dictionary
	var classes := weapons.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_key, {}) as Dictionary
	return cls_data.get("spawn_weight", null)  # TBD: balance pass


# Returns the passive description string for Epic/Legendary tiers, or "" if none.
static func passive_description(wc: Constants.WeaponClass, tier: Constants.Tier) -> String:
	var class_key: String = Constants.WEAPON_CLASS_NAMES[wc]
	var tier_key: String  = Constants.TIER_NAMES[tier].to_lower()
	var weapons  := GameManager.data.get("weapons", {}) as Dictionary
	var classes  := weapons.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_key, {}) as Dictionary
	var passives := cls_data.get("passives", {}) as Dictionary
	return passives.get(tier_key, "")
