## Faultline — armor item instance: class, tier, damage reduction, passive, durability.
##
## One armor piece occupies the single armor sidebar slot. Every class × tier
## provides flat_reduction (subtracted first), percent_reduction (applied after),
## and durability (degrades 1 per hit received — PlayerStats calls register_hit()).
## At 0 durability the armor breaks: all reductions and passives go neutral.
## Class passives (strengths TBD — null in armor_stats.json until balance pass):
##   Titan      — bonus_flat_reduction added on top of tier flat reduction
##   Hellforge  — burn_resist (0–1 fraction of burn damage ignored)
##   Tempest    — move_speed_mult while worn
##   Echo       — debuff_duration_mult (<1 shortens incoming debuffs)
##   Expedition — durability_mult (>1: more max durability)
class_name ArmorBase
extends Resource

signal durability_changed(current: float, max: float)
signal armor_broken

@export var armor_class: int = Constants.ArmorClass.TITAN
@export var tier: int = Constants.Tier.COMMON

var max_durability: Variant = null   # int hits, loaded from data (TBD placeholder values)
var current_durability: float = 0.0
var is_broken: bool = false
var is_equipped: bool = false

# Per-tier reductions (null = missing data / TBD)
var _flat_reduction: Variant = null
var _percent_reduction: Variant = null

# Class passive values (null = TBD in armor_stats.json — do not invent numbers)
var _passive: Dictionary = {}


func init_from_data() -> void:
	var class_key: String = Constants.ARMOR_CLASS_NAMES[armor_class]
	var tier_key: String  = Constants.TIER_NAMES[tier]
	var armor    := GameManager.data.get("armor", {}) as Dictionary
	var classes  := armor.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_key, {}) as Dictionary
	var tiers    := cls_data.get("tiers", {}) as Dictionary
	var entry    := tiers.get(tier_key, {}) as Dictionary

	_flat_reduction    = entry.get("flat_reduction", null)
	_percent_reduction = entry.get("percent_reduction", null)
	max_durability     = entry.get("durability", null)
	_passive           = cls_data.get("passive", {}) as Dictionary

	# Expedition passive — more max durability. Scaffold: null durability_mult
	# in JSON (TBD) makes this a no-op until the balance pass fills it in.
	if armor_class == Constants.ArmorClass.EXPEDITION and max_durability != null:
		var dur_mult = _passive.get("durability_mult", null)
		if dur_mult != null:
			max_durability = float(max_durability) * float(dur_mult)

	current_durability = float(max_durability) if max_durability != null else 0.0
	is_broken = false


# Called by PlayerStats each time the wearer takes a hit. 1 hit = 1 durability.
func register_hit() -> void:
	if is_broken:
		return
	current_durability = maxf(current_durability - 1.0, 0.0)
	var _max := float(max_durability) if max_durability != null else 0.0
	durability_changed.emit(current_durability, _max)
	if current_durability <= 0.0 and max_durability != null:
		is_broken = true
		armor_broken.emit()


# Flat damage subtracted before percent_reduction is applied. 0.0 when broken
# or data missing. Titan passive adds bonus_flat_reduction on top (scaffold:
# null in JSON = no bonus until balance pass).
func flat_reduction() -> float:
	if is_broken or _flat_reduction == null:
		return 0.0
	var flat := float(_flat_reduction)
	if armor_class == Constants.ArmorClass.TITAN:
		var bonus = _passive.get("bonus_flat_reduction", null)
		if bonus != null:
			flat += float(bonus)
	return flat


# Fraction of remaining damage ignored (0.0–1.0). 0.0 when broken or missing.
func percent_reduction() -> float:
	if is_broken or _percent_reduction == null:
		return 0.0
	return clampf(float(_percent_reduction), 0.0, 1.0)


# Tempest passive — movement multiplier while worn. 1.0 (neutral) when broken,
# not Tempest, or value null (TBD).
func move_speed_mult() -> float:
	if is_broken or armor_class != Constants.ArmorClass.TEMPEST:
		return 1.0
	var mult = _passive.get("move_speed_mult", null)
	return float(mult) if mult != null else 1.0


# Echo passive — multiplier on incoming debuff durations (<1 shortens them).
# 1.0 (neutral) when broken, not Echo, or value null (TBD).
func debuff_duration_mult() -> float:
	if is_broken or armor_class != Constants.ArmorClass.ECHO:
		return 1.0
	var mult = _passive.get("debuff_duration_mult", null)
	return float(mult) if mult != null else 1.0


# Hellforge passive — fraction of burn damage ignored (0.0–1.0). 0.0 (neutral)
# when broken, not Hellforge, or value null (TBD).
func burn_resist() -> float:
	if is_broken or armor_class != Constants.ArmorClass.HELLFORGE:
		return 0.0
	var resist = _passive.get("burn_resist", null)
	if resist == null:
		return 0.0
	return clampf(float(resist), 0.0, 1.0)


# Upgrade Template parity with drills/weapons: full repair, un-break.
func restore_durability() -> void:
	is_broken = false
	var _max := float(max_durability) if max_durability != null else 0.0
	current_durability = _max
	durability_changed.emit(current_durability, _max)


func get_display_name() -> String:
	var tier_name: String      = Constants.TIER_NAMES.get(tier, "?")
	var class_name_str: String = Constants.ARMOR_CLASS_NAMES.get(armor_class, "?")
	return "%s %s Armor" % [tier_name, class_name_str]
