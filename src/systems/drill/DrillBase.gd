## Faultline — drill item instance: class, tier, durability state, equip lifecycle.
class_name DrillBase
extends Resource

signal durability_changed(current: float, max_dur: float)
signal drill_broken
signal equipped
signal unequipped

@export var drill_class: Constants.DrillClass = Constants.DrillClass.PRECISION
@export var tier: Constants.Tier = Constants.Tier.COMMON

var max_durability: Variant  # int tile-breaks, loaded from data
var current_durability: float = 0.0
var is_broken: bool = false
var is_equipped: bool = false


func init_from_data() -> void:
	var class_name_key: String = Constants.DRILL_CLASS_NAMES[drill_class]
	var tier_name_key: String = Constants.TIER_NAMES[tier]
	var drills   := GameManager.data.get("drills", {}) as Dictionary
	var classes  := drills.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_name_key, {}) as Dictionary
	var tiers    := cls_data.get("tiers", {}) as Dictionary
	var entry    := tiers.get(tier_name_key, {}) as Dictionary
	max_durability = entry.get("durability", null)
	current_durability = float(max_durability) if max_durability != null else 0.0


func equip() -> void:
	is_equipped = true
	equipped.emit()


func unequip() -> void:
	is_equipped = false
	unequipped.emit()


func consume_durability(amount: float) -> void:
	if is_broken:
		return
	current_durability = maxf(current_durability - amount, 0.0)
	var _max := float(max_durability) if max_durability != null else 0.0
	durability_changed.emit(current_durability, _max)
	if current_durability == 0.0 and max_durability != null:
		is_broken = true
		drill_broken.emit()


func restore_durability() -> void:
	is_broken = false
	var _max := float(max_durability) if max_durability != null else 0.0
	current_durability = _max
	durability_changed.emit(current_durability, _max)


func get_display_name() -> String:
	var tier_name: String      = Constants.TIER_NAMES.get(tier, "?")
	var class_name_str: String = Constants.DRILL_CLASS_NAMES.get(drill_class, "?")
	return "%s %s Drill" % [tier_name, class_name_str]
