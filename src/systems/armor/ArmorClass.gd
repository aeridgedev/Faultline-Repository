## Faultline — armor class data accessors and class-passive queries.
##
## Exactly 5 classes (Constants.ArmorClass), each with ONE unique passive:
##   Titan      — Bulwark: bonus flat damage reduction on top of tier stats.
##   Hellforge  — Heat Ward: ignores a fraction of burn damage (burn_resist).
##   Tempest    — Slipstream: movement speed multiplier while worn.
##   Echo       — Dampening: incoming debuffs run out faster (duration mult <1).
##   Expedition — Reinforced Plating: bonus max durability (durability_mult >1).
## All passive strengths are TBD (null in armor_stats.json) — do not invent them.
class_name ArmorClassData
extends RefCounted


static func _class_data(ac: Constants.ArmorClass) -> Dictionary:
	var key: String  = Constants.ARMOR_CLASS_NAMES[ac]
	var armor    := GameManager.data.get("armor", {}) as Dictionary
	var classes  := armor.get("classes", {}) as Dictionary
	return classes.get(key, {}) as Dictionary


# Relative class spawn weight out of 100 (TBD placeholders in armor_stats.json).
static func spawn_weight(ac: Constants.ArmorClass) -> Variant:
	return _class_data(ac).get("spawn_weight", null)


# The class's passive block from armor_stats.json ({"name": ..., "<param>": null, "_tbd": true}).
static func passive_data(ac: Constants.ArmorClass) -> Dictionary:
	return _class_data(ac).get("passive", {}) as Dictionary


static func passive_name(ac: Constants.ArmorClass) -> String:
	return str(passive_data(ac).get("name", ""))


static func passive_description(ac: Constants.ArmorClass) -> String:
	match ac:
		Constants.ArmorClass.TITAN:      return "Bulwark — extra flat damage reduction"
		Constants.ArmorClass.HELLFORGE:  return "Heat Ward — resists burn damage"
		Constants.ArmorClass.TEMPEST:    return "Slipstream — move faster while worn"
		Constants.ArmorClass.ECHO:       return "Dampening — debuffs wear off sooner"
		Constants.ArmorClass.EXPEDITION: return "Reinforced Plating — bonus durability"
	return ""


static func get_role_description(ac: Constants.ArmorClass) -> String:
	match ac:
		Constants.ArmorClass.TITAN:      return "Heavy physical protection"
		Constants.ArmorClass.HELLFORGE:  return "Thermal/heat resistance"
		Constants.ArmorClass.TEMPEST:    return "Speed and mobility"
		Constants.ArmorClass.ECHO:       return "Debuff resistance"
		Constants.ArmorClass.EXPEDITION: return "Endurance and survival"
	return ""
