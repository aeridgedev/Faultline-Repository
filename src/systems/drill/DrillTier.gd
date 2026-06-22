## Faultline — drill class+tier stat accessors (dig time multiplier, durability).
class_name DrillTier
extends RefCounted


static func _entry(dc: Constants.DrillClass, tier: Constants.Tier) -> Dictionary:
	return (
		GameManager.data
		.get("drills", {})
		.get("classes", {})
		.get(Constants.DRILL_CLASS_NAMES[dc], {})
		.get("tiers", {})
		.get(Constants.TIER_NAMES[tier], {})
	)


# Multiplier on base terrain dig time (lower = faster). TBD: null until balance pass.
static func dig_time_mult(dc: Constants.DrillClass, tier: Constants.Tier) -> Variant:
	return _entry(dc, tier).get("dig_time_mult", null)


# Tile-breaks before the drill is exhausted. TBD: null until balance pass.
static func max_durability(dc: Constants.DrillClass, tier: Constants.Tier) -> Variant:
	return _entry(dc, tier).get("durability", null)
