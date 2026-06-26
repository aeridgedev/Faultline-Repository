## Faultline — timed buff state for one non-permanent relic (Haste / Speed / Strength).
## Duration TBD; ~3–4s is the only locked constraint (from CLAUDE.md).
class_name BuffRelic
extends RefCounted

var relic_type: Constants.Relic = Constants.Relic.HASTE
var is_active: bool = false
var _expires_at: float = 0.0   # in seconds, on the Time.get_ticks_msec() / 1000.0 clock


func activate(current_time: float) -> void:
	var dur: Variant = GameManager.data.get("relic_duration", {}).get(
		Constants.RELIC_NAMES[relic_type].to_lower(), null
	)
	# TBD: duration null → use 3.5s midpoint of the ~3–4s window.
	_expires_at = current_time + (float(dur) if dur != null else 3.5)
	is_active = true


func tick(current_time: float) -> bool:
	if not is_active:
		return false
	if current_time >= _expires_at:
		is_active = false
		return true  # just expired
	return false


# Multiplier accessors — 1.0 = no effect (TBD: balance pass sets actual values).
func move_speed_mult() -> float:
	if not is_active:
		return 1.0
	var val: Variant = GameManager.data.get("relic_strength", {}).get(
		Constants.RELIC_NAMES[relic_type].to_lower() + "_mult", null
	)
	return float(val) if val != null else 1.0


func damage_mult() -> float:
	return move_speed_mult()   # reuses same pattern; each relic has its own key in data
