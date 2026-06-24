## Faultline — weighted loot roll for a given layer.
## Returns a Dictionary {type, item_class, tier} describing the drop.
## All weights are TBD; falls back to uniform random when data is absent.
class_name LootTable
extends RefCounted

# Item categories available per chest. Relics/throwables/consumables added in step 6.
const _CATEGORIES := ["drill", "weapon", "armor"]


## Returns a Dictionary: {type: String, item_class: int, tier: int}
## or {} if the roll somehow produces nothing (shouldn't happen).
static func roll(layer: int) -> Dictionary:
	# Arrays must be local vars — autoload enum values cannot be used in const.
	var drill_classes  := [Constants.DrillClass.PRECISION, Constants.DrillClass.BURST,
						   Constants.DrillClass.THERMAL,  Constants.DrillClass.RESONANCE]
	var weapon_classes := [Constants.WeaponClass.DAGGERS, Constants.WeaponClass.SWORDS,
						   Constants.WeaponClass.HAMMERS, Constants.WeaponClass.SPEARS,
						   Constants.WeaponClass.AXES]
	var armor_classes  := [Constants.ArmorClass.TITAN,    Constants.ArmorClass.HELLFORGE,
						   Constants.ArmorClass.TEMPEST,  Constants.ArmorClass.ECHO,
						   Constants.ArmorClass.EXPEDITION]

	var layer_key: String = Constants.LAYER_NAMES[layer].to_lower().replace(" ", "_")
	var table: Dictionary = GameManager.data.get("loot_tables", {}).get(layer_key, {})

	var category := _weighted_pick(_CATEGORIES, table.get("category_weights", {}))
	var tier     := _roll_tier(table.get("rarity_weights", {}))

	match category:
		"drill":
			return {
				"type": "drill",
				"item_class": drill_classes[randi() % drill_classes.size()],
				"tier": tier,
			}
		"weapon":
			return {
				"type": "weapon",
				"item_class": weapon_classes[randi() % weapon_classes.size()],
				"tier": tier,
			}
		"armor":
			return {
				"type": "armor",
				"item_class": armor_classes[randi() % armor_classes.size()],
				"tier": tier,
			}
	return {}


static func _roll_tier(rarity_weights: Dictionary) -> int:
	var weight_map := {
		"common":    rarity_weights.get("common",    1.0),
		"rare":      rarity_weights.get("rare",      0.0),
		"epic":      rarity_weights.get("epic",      0.0),
		"legendary": rarity_weights.get("legendary", 0.0),
	}
	var picked := _weighted_pick(weight_map.keys(), weight_map)
	match picked:
		"rare":      return Constants.Tier.RARE
		"epic":      return Constants.Tier.EPIC
		"legendary": return Constants.Tier.LEGENDARY
		_:           return Constants.Tier.COMMON


# Picks a key from `keys` using float weights from `weight_dict`.
# Falls back to uniform if all weights are 0 or dict is empty.
static func _weighted_pick(keys: Array, weight_dict: Dictionary) -> String:
	var total := 0.0
	for k in keys:
		total += float(weight_dict.get(k, 1.0))
	var pick_val := randf() * total
	var acc := 0.0
	for k in keys:
		acc += float(weight_dict.get(k, 1.0))
		if pick_val < acc:
			return k
	return keys[keys.size() - 1]
