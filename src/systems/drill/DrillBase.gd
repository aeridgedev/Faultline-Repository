## Faultline — drill item instance: class, tier, durability state.
class_name DrillBase
extends Resource

signal durability_changed(current: float, max_dur: float)
signal drill_broken

@export var drill_class: Constants.DrillClass = Constants.DrillClass.PRECISION
@export var tier: Constants.Tier = Constants.Tier.COMMON

var max_durability: Variant  # TBD: int tile-breaks, loaded from data
var current_durability: float = 0.0
var is_broken: bool = false


func init_from_data() -> void:
	var class_name_key: String = Constants.DRILL_CLASS_NAMES[drill_class]
	var tier_name_key: String = Constants.TIER_NAMES[tier]
	var drills   := GameManager.data.get("drills", {}) as Dictionary
	var classes  := drills.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_name_key, {}) as Dictionary
	var tiers    := cls_data.get("tiers", {}) as Dictionary
	var entry    := tiers.get(tier_name_key, {}) as Dictionary
	max_durability = entry.get("durability", null)  # TBD: balance pass
	current_durability = float(max_durability) if max_durability != null else 0.0


func consume_durability(amount: float) -> void:
	if is_broken:
		return
	current_durability = maxf(current_durability - amount, 0.0)
	var _max := float(max_durability) if max_durability != null else 0.0
	durability_changed.emit(current_durability, _max)
	if current_durability == 0.0:
		is_broken = true
		drill_broken.emit()


func restore_durability() -> void:
	is_broken = false
	var _max := float(max_durability) if max_durability != null else 0.0
	current_durability = _max
	durability_changed.emit(current_durability, _max)
