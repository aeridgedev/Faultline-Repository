class_name TerrainTypes
extends RefCounted
## Faultline — per-terrain-type definitions and lookup helpers.
##
## STUB — to be implemented in build step 1 (Player movement + terrain).
## Do not implement ahead of schedule; ask before building.
##
## The canonical type list (the enum) lives in Constants.TerrainType so there is
## one source of truth for ids. THIS file owns the richer per-type data and
## behaviour: hardness ordering, movement-speed modifiers, dig-time handling,
## and per-drill-class effectiveness — all read from data/terrain_stats.json
## (currently null placeholders pending the balance pass).
##
## Locked: types are Soil / Rock / Dense Rock / Crystal / Bedrock; Bedrock is the
## hardest and bounds the playfield. All numeric values are TBD — never invent them.

# TODO(step 1): load data/terrain_stats.json and expose typed accessors, e.g.
#   static func base_dig_time(type: Constants.TerrainType) -> float
#   static func move_speed_mod(type: Constants.TerrainType) -> float
#   static func class_effectiveness(type, drill_class) -> float
