## Faultline — weapon tier stat accessors.
## Scaling multipliers are LOCKED in Constants.WEAPON_TIER_SCALING;
## Common base values are TBD in data["weapons"]["classes"][...]["base"].
class_name WeaponTier
extends RefCounted


static func damage_mult(tier: Constants.Tier) -> float:
	return Constants.WEAPON_TIER_SCALING[tier]["damage"]


static func swing_mult(tier: Constants.Tier) -> float:
	return Constants.WEAPON_TIER_SCALING[tier]["swing"]


static func durability_mult(tier: Constants.Tier) -> float:
	return Constants.WEAPON_TIER_SCALING[tier]["durability"]


static func has_passive(tier: Constants.Tier) -> bool:
	return Constants.WEAPON_TIER_SCALING[tier]["passive"] != ""


static func passive_type(tier: Constants.Tier) -> String:
	return Constants.WEAPON_TIER_SCALING[tier]["passive"]  # "" / "minor" / "unique"
