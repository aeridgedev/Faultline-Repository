## Faultline — drill class+tier stat accessors (dig time multiplier, durability).
class_name DrillTier
extends RefCounted


static func _entry(dc: Constants.DrillClass, tier: Constants.Tier) -> Dictionary:
	var class_key: String = Constants.DRILL_CLASS_NAMES[dc]
	var tier_key: String  = Constants.TIER_NAMES[tier]
	var drills   := GameManager.data.get("drills", {}) as Dictionary
	var classes  := drills.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_key, {}) as Dictionary
	var tiers    := cls_data.get("tiers", {}) as Dictionary
	return tiers.get(tier_key, {}) as Dictionary


# Multiplier on base terrain dig time (lower = faster). TBD: null until balance pass.
static func dig_time_mult(dc: Constants.DrillClass, tier: Constants.Tier) -> Variant:
	return _entry(dc, tier).get("dig_time_mult", null)


# Tile-breaks before the drill is exhausted. TBD: null until balance pass.
static func max_durability(dc: Constants.DrillClass, tier: Constants.Tier) -> Variant:
	return _entry(dc, tier).get("durability", null)
