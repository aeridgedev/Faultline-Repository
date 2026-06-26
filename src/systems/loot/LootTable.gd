## Faultline — weighted loot roll for a given layer.
## Returns a Dictionary {type, item_class, tier} describing the drop.
## All weights are TBD; falls back to uniform random when data is absent.
class_name LootTable
extends RefCounted

const _CATEGORIES := ["drill", "weapon", "armor", "relic", "throwable", "consumable"]

# Consumable item_class indices (IDs are stable even though values are TBD).
const _CONSUMABLE_TYPES := [0, 1, 2, 3, 4]  # Lytes / Medkit / ThermalCapsule / Bloodstim / FaultBeacon


## Returns a Dictionary: {type: String, item_class: int, tier: int}
## or {} if the roll somehow produces nothing (shouldn't happen).
static func roll(layer: int) -> Dictionary:
	# Arrays must be local vars — autoload enum values cannot be used in const.
	var drill_classes     := [Constants.DrillClass.PRECISION, Constants.DrillClass.BURST,
							  Constants.DrillClass.THERMAL,  Constants.DrillClass.RESONANCE]
	var weapon_classes    := [Constants.WeaponClass.DAGGERS, Constants.WeaponClass.SWORDS,
							  Constants.WeaponClass.HAMMERS, Constants.WeaponClass.SPEARS,
							  Constants.WeaponClass.AXES]
	var armor_classes     := [Constants.ArmorClass.TITAN,    Constants.ArmorClass.HELLFORGE,
							  Constants.ArmorClass.TEMPEST,  Constants.ArmorClass.ECHO,
							  Constants.ArmorClass.EXPEDITION]
	var relic_classes     := [Constants.Relic.HASTE, Constants.Relic.SPEED,
							  Constants.Relic.STRENGTH, Constants.Relic.TOUGHNESS]
	var throwable_classes := [Constants.Throwable.SMOKE_BOMB,    Constants.Throwable.PARALYSIS_BOMB,
							  Constants.Throwable.WEAKNESS_BOMB, Constants.Throwable.HEAT_CHARGE,
							  Constants.Throwable.DUST_CAPSULE,  Constants.Throwable.ECHO_CHARGE,
							  Constants.Throwable.SEISMIC_CHARGE]

	var layer_key: String = Constants.LAYER_NAMES[layer]
	var loot := GameManager.data.get("loot_tables", {}) as Dictionary
	var layers := loot.get("layers", {}) as Dictionary
	var table: Dictionary = layers.get(layer_key, {})

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
		"relic":
			return {
				"type": "relic",
				"item_class": relic_classes[randi() % relic_classes.size()],
				"tier": Constants.Tier.COMMON,  # relics have no tier progression
			}
		"throwable":
			return {
				"type": "throwable",
				"item_class": throwable_classes[randi() % throwable_classes.size()],
				"tier": tier,
			}
		"consumable":
			return {
				"type": "consumable",
				"item_class": _CONSUMABLE_TYPES[randi() % _CONSUMABLE_TYPES.size()],
				"tier": Constants.Tier.COMMON,  # consumables have no tier progression
			}
	return {}


static func _roll_tier(rarity_weights: Dictionary) -> int:
	# Keys match loot_tables.json ("Common"/"Rare"/...). Values are still null
	# until the balance pass, so coerce: default to a Common-only distribution
	# (1/0/0/0) rather than uniform — uniform would hand out 25% Legendaries.
	var weight_map := {
		"Common":    _num(rarity_weights.get("Common"),    1.0),
		"Rare":      _num(rarity_weights.get("Rare"),      0.0),
		"Epic":      _num(rarity_weights.get("Epic"),      0.0),
		"Legendary": _num(rarity_weights.get("Legendary"), 0.0),
	}
	var picked := _weighted_pick(weight_map.keys(), weight_map)
	match picked:
		"Rare":      return Constants.Tier.RARE
		"Epic":      return Constants.Tier.EPIC
		"Legendary": return Constants.Tier.LEGENDARY
		_:           return Constants.Tier.COMMON


# Coerce a possibly-null/absent JSON weight to a float, using `fallback` for both.
static func _num(value: Variant, fallback: float) -> float:
	return float(value) if value != null else fallback


# Picks a key from `keys` using float weights from `weight_dict`.
# Absent OR null weights count as 1.0, so uniform is the fallback when a layer's
# weights aren't tuned yet (keeps category rolls working with all-null data).
static func _weighted_pick(keys: Array, weight_dict: Dictionary) -> String:
	var total := 0.0
	for k in keys:
		total += _num(weight_dict.get(k), 1.0)
	if total <= 0.0:
		return keys[keys.size() - 1]  # all weights zero — pick the last deterministically
	var pick_val := randf() * total
	var acc := 0.0
	for k in keys:
		acc += _num(weight_dict.get(k), 1.0)
		if pick_val < acc:
			return k
	return keys[keys.size() - 1]
