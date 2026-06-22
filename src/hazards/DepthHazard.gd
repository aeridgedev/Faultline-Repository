## Faultline — passive ambient damage for being in deep layers.
## Tick-based: checks once per second so stats.take_damage() isn't called every frame.
class_name DepthHazard
extends Node

signal depth_hazard_tick(damage: float)

var _stats: PlayerStats = null
var _tick_timer: float = 0.0
const _TICK_INTERVAL := 1.0


func init(stats: PlayerStats) -> void:
	_stats = stats


func _physics_process(delta: float) -> void:
	if _stats == null or _stats.is_dead or _stats.max_health <= 0.0:
		return
	_tick_timer += delta
	if _tick_timer < _TICK_INTERVAL:
		return
	_tick_timer = 0.0
	_apply_tick()


func _apply_tick() -> void:
	var layer := _stats.get_layer() as Constants.Layer
	var dps: Variant = _layer_dps(layer)
	if dps == null:
		return  # TBD: no values until balance pass
	var dmg := float(dps) * _TICK_INTERVAL
	if dmg <= 0.0:
		return
	_stats.take_damage(dmg)
	depth_hazard_tick.emit(dmg)


# Data key format: data["depth_hazard"]["crust_dps"], ["outer_core_dps"], etc.
func _layer_dps(layer: Constants.Layer) -> Variant:
	var layer_key := Constants.LAYER_NAMES[layer].to_lower().replace(" ", "_")
	return GameManager.data.get("depth_hazard", {}).get(layer_key + "_dps", null)
