## Faultline — base weapon Resource: class, tier, derived stats, durability.
## All Common base stats (damage, swing_speed, durability, range) are TBD — loaded
## from data["weapons"]["classes"][class_name]["base"] and scaled by WEAPON_TIER_SCALING.
class_name WeaponBase
extends Resource

signal durability_changed(current: float, max_val: float)
signal weapon_broken

@export var weapon_class: Constants.WeaponClass = Constants.WeaponClass.SWORDS
@export var tier: Constants.Tier = Constants.Tier.COMMON

var max_durability: Variant = null   # TBD: null until balance pass
var current_durability: float = 0.0

# Derived stats (computed by init_from_data; null = TBD)
var damage: Variant       = null
var swing_speed: Variant  = null
var attack_range: Variant = null

var is_broken: bool = false


func init_from_data() -> void:
	var class_key: String = Constants.WEAPON_CLASS_NAMES[weapon_class]
	var weapons  := GameManager.data.get("weapons", {}) as Dictionary
	var classes  := weapons.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_key, {}) as Dictionary
	var base     := cls_data.get("base", {}) as Dictionary
	var scaling: Dictionary = Constants.WEAPON_TIER_SCALING[tier]

	var base_dmg    = base.get("damage",      null)
	var base_swing  = base.get("swing_speed", null)
	var base_dur    = base.get("durability",  null)
	var base_range  = base.get("range",       null)

	damage       = float(base_dmg)   * scaling["damage"]      if base_dmg   != null else null
	swing_speed  = float(base_swing) * scaling["swing"]       if base_swing != null else null
	max_durability = float(base_dur) * scaling["durability"]  if base_dur   != null else null
	if base_range != null:
		attack_range = float(base_range)

	current_durability = float(max_durability) if max_durability != null else 0.0
	is_broken = false


func consume_durability(amount: float) -> void:
	if is_broken:
		return
	current_durability = maxf(current_durability - amount, 0.0)
	durability_changed.emit(current_durability, float(max_durability) if max_durability != null else 0.0)
	if current_durability == 0.0 and max_durability != null:
		is_broken = true
		weapon_broken.emit()


func restore_durability() -> void:
	if max_durability == null:
		return
	current_durability = float(max_durability)
	is_broken = false
	durability_changed.emit(current_durability, float(max_durability))
