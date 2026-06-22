class_name LootRestriction
extends RefCounted
## Faultline — gates when a player is allowed to pick up / loot items.
##
## STUB — to be implemented in build step 4 (Inventory + loot).
## Do not implement ahead of schedule; ask before building.
##
## Locked rule: a player CANNOT loot while any of these are active:
##   - taking damage
##   - attacking
##   - drilling
##
## Implementation note: this is a pure predicate/guard the loot pickup flow
## checks before collecting. Exact timing windows (e.g. how long after taking
## damage looting stays blocked) are TBD — never invent them.

# TODO(step 4): expose something like
#   static func can_loot(player_state) -> bool
# returning false while taking_damage / attacking / drilling.
