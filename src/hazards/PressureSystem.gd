## Faultline — pressure damage scaling with depth factor + zero-gravity flag for Core Hollow.
## Damage formula: pressure_dps_base * depth_factor — deeper = more pressure.
## Damage is reduced by an active Thermal Capsule (PlayerStats.hazard_resist()).
## Core Hollow zero-gravity is flagged here; PlayerController.set_zero_gravity() (connected
## in Main.gd) applies the actual physics: gravity off, free movement on every axis.
class_name PressureSystem
extends Node

signal pressure_tick(damage: float)
signal zero_gravity_changed(enabled: bool)

var _stats: PlayerStats = null
var _tick_timer: float = 0.0
var _zero_gravity_active: bool = false
const _TICK_INTERVAL := 1.0


func init(stats: PlayerStats) -> void:
	_stats = stats


func _physics_process(delta: float) -> void:
	if _stats == null or _stats.is_dead or _stats.max_health <= 0.0:
		return
	_update_zero_gravity()
	_tick_timer += delta
	if _tick_timer < _TICK_INTERVAL:
		return
	_tick_timer = 0.0
	_apply_tick()


func _update_zero_gravity() -> void:
	var in_hollow: bool = _stats.get_layer() == Constants.Layer.CORE_HOLLOW
	if in_hollow != _zero_gravity_active:
		_zero_gravity_active = in_hollow
		zero_gravity_changed.emit(_zero_gravity_active)


func _apply_tick() -> void:
	var depth_factor: float = Constants.LAYER_DEPTH_FACTOR.get(_stats.get_layer(), 0.0)
	if depth_factor <= 0.0:
		return  # Crust has no pressure hazard
	var base_dps: Variant = GameManager.data.get("pressure_dps_base", null)
	if base_dps == null:
		return  # TBD: no values until balance pass
	var dmg := float(base_dps) * depth_factor * _TICK_INTERVAL
	# Thermal Capsule resistance (0.0–1.0) reduces pressure damage; full resist skips
	# damage + signal via the check below.
	dmg *= (1.0 - _stats.hazard_resist())
	if dmg <= 0.0:
		return
	_stats.take_damage(dmg)
	pressure_tick.emit(dmg)


func is_zero_gravity() -> bool:
	return _zero_gravity_active
