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
# weapon_stats.json stores these as "minor_passive" (Epic) / "unique_passive"
# (Legendary) strings per class — matches Constants.WEAPON_TIER_SCALING's
# "minor"/"unique" passive markers. Common/Rare have no passive.
static func passive_description(wc: Constants.WeaponClass, tier: Constants.Tier) -> String:
	var class_key: String = Constants.WEAPON_CLASS_NAMES[wc]
	var weapons  := GameManager.data.get("weapons", {}) as Dictionary
	var classes  := weapons.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_key, {}) as Dictionary
	match tier:
		Constants.Tier.EPIC:      return str(cls_data.get("minor_passive", ""))
		Constants.Tier.LEGENDARY: return str(cls_data.get("unique_passive", ""))
		_:                        return ""
