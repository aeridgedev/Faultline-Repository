## Faultline — predicate guard: blocks looting while drilling or attacking.
## "Taking damage" window is TBD (no duration value yet); omitted until balance pass.
class_name LootRestriction
extends RefCounted


static func can_loot(drilling: bool, attacking: bool) -> bool:
	return not (drilling or attacking)
