## Faultline — drill class × tier stat accessors (dig time multiplier, durability).
##
## 4 tiers — Common (baseline) → Rare → Epic → Legendary (ceiling).
## Placeholder values in drill_stats.json; pending final balance pass.
##
## Approximate per-tier scaling (Precision as reference):
##   Common    1.00× dig  |  200 tile-breaks
##   Rare     ~0.85× dig  |  ~310-320 tile-breaks  (~15% faster, ~60% more durable)
##   Epic     ~0.70× dig  |  ~460-480 tile-breaks  (~30% faster, ~140% more durable)
##   Legendary ~0.55× dig |  ~760-800 tile-breaks  (~45% faster, ~300% more durable)
##
## All four classes follow the same tier curve; exact numbers differ slightly
## per class — see drill_stats.json.
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


# Multiplier on base terrain dig time (lower = faster). Null until balance pass.
static func dig_time_mult(dc: Constants.DrillClass, tier: Constants.Tier) -> Variant:
	return _entry(dc, tier).get("dig_time_mult", null)


# Tile-breaks before the drill is exhausted / needs an Upgrade Template. Null until balance pass.
static func max_durability(dc: Constants.DrillClass, tier: Constants.Tier) -> Variant:
	return _entry(dc, tier).get("durability", null)


# Returns true when every class × tier cell has data in drill_stats.json.
# Call during startup to catch missing JSON entries early.
static func validate_matrix() -> bool:
	var ok := true
	var all_classes := [
		Constants.DrillClass.PRECISION, Constants.DrillClass.BURST,
		Constants.DrillClass.THERMAL,   Constants.DrillClass.RESONANCE,
	]
	var all_tiers := [
		Constants.Tier.COMMON, Constants.Tier.RARE,
		Constants.Tier.EPIC,   Constants.Tier.LEGENDARY,
	]
	for dc in all_classes:
		for t in all_tiers:
			if _entry(dc, t).is_empty():
				push_warning("DrillTier: missing data for %s %s" % [
					Constants.DRILL_CLASS_NAMES[dc], Constants.TIER_NAMES[t]])
				ok = false
	return ok


# Human-readable tier summary for tooltips / debug output.
static func tier_description(tier: Constants.Tier) -> String:
	match tier:
		Constants.Tier.COMMON:    return "Common — baseline stats"
		Constants.Tier.RARE:      return "Rare — ~15% faster, ~60% more durable"
		Constants.Tier.EPIC:      return "Epic — ~30% faster, ~140% more durable"
		Constants.Tier.LEGENDARY: return "Legendary — ~45% faster, ~300% more durable"
	return ""
