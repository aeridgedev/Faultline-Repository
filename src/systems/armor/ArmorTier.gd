## Faultline — armor class × tier stat accessors (flat/percent reduction, durability).
##
## 4 tiers — Common (baseline) → Rare → Epic → Legendary (ceiling).
## Placeholder values in armor_stats.json; pending final balance pass.
## Every tier of every class provides all three stats; higher tier is strictly
## better on all three. Class passives live on the class block, not per tier —
## see ArmorClassData / ArmorBase.
class_name ArmorTier
extends RefCounted


static func _entry(ac: Constants.ArmorClass, tier: Constants.Tier) -> Dictionary:
	var class_key: String = Constants.ARMOR_CLASS_NAMES[ac]
	var tier_key: String  = Constants.TIER_NAMES[tier]
	var armor    := GameManager.data.get("armor", {}) as Dictionary
	var classes  := armor.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_key, {}) as Dictionary
	var tiers    := cls_data.get("tiers", {}) as Dictionary
	return tiers.get(tier_key, {}) as Dictionary


# Flat damage subtracted before percent reduction. Null until balance pass finalizes.
static func flat_reduction(ac: Constants.ArmorClass, tier: Constants.Tier) -> Variant:
	return _entry(ac, tier).get("flat_reduction", null)


# Fraction (0.0–1.0) of remaining damage ignored. Null until balance pass finalizes.
static func percent_reduction(ac: Constants.ArmorClass, tier: Constants.Tier) -> Variant:
	return _entry(ac, tier).get("percent_reduction", null)


# Hits absorbed before the armor breaks. Null until balance pass finalizes.
static func max_durability(ac: Constants.ArmorClass, tier: Constants.Tier) -> Variant:
	return _entry(ac, tier).get("durability", null)


# Returns true when every class × tier cell has data in armor_stats.json.
# Call during startup to catch missing JSON entries early.
static func validate_matrix() -> bool:
	var ok := true
	var all_classes := [
		Constants.ArmorClass.TITAN,   Constants.ArmorClass.HELLFORGE,
		Constants.ArmorClass.TEMPEST, Constants.ArmorClass.ECHO,
		Constants.ArmorClass.EXPEDITION,
	]
	var all_tiers := [
		Constants.Tier.COMMON, Constants.Tier.RARE,
		Constants.Tier.EPIC,   Constants.Tier.LEGENDARY,
	]
	for ac in all_classes:
		for t in all_tiers:
			if _entry(ac, t).is_empty():
				push_warning("ArmorTier: missing data for %s %s" % [
					Constants.ARMOR_CLASS_NAMES[ac], Constants.TIER_NAMES[t]])
				ok = false
	return ok


# Human-readable tier summary for tooltips / debug output.
static func tier_description(tier: Constants.Tier) -> String:
	match tier:
		Constants.Tier.COMMON:    return "Common — baseline protection"
		Constants.Tier.RARE:      return "Rare — improved reduction and durability"
		Constants.Tier.EPIC:      return "Epic — strong reduction and durability"
		Constants.Tier.LEGENDARY: return "Legendary — best-in-slot protection"
	return ""
