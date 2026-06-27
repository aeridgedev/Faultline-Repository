## Faultline — passive ambient hazards for being in deep layers.
## Tick-based: checks once per second so stats.take_damage() isn't called every frame.
##
## Two effects scale with depth:
##   Oxygen instability → stamina drain (Mantle and below)
##   Pressure distortion → screen darkening vignette (Mantle and below)
class_name DepthHazard
extends Node

signal depth_hazard_tick(damage: float)
signal oxygen_drained(amount: float)

var _stats: PlayerStats = null
var _stamina: Stamina = null
var _tick_timer: float = 0.0
const _TICK_INTERVAL := 1.0

var _vignette_layer: CanvasLayer = null
var _vignette_rect: ColorRect = null

# Per-layer vignette colors (pressure distortion visual): dark with subtle hue shift.
const _LAYER_VIGNETTE_COLOR := {
	Constants.Layer.CRUST:       Color(0.00, 0.00, 0.00, 0.00),
	Constants.Layer.MANTLE:      Color(0.04, 0.08, 0.04, 0.08),
	Constants.Layer.OUTER_CORE:  Color(0.10, 0.04, 0.02, 0.18),
	Constants.Layer.INNER_CORE:  Color(0.16, 0.03, 0.02, 0.30),
	Constants.Layer.CORE_HOLLOW: Color(0.02, 0.02, 0.04, 0.05),
}


func init(stats: PlayerStats, stamina: Stamina = null) -> void:
	_stats = stats
	_stamina = stamina
	_build_vignette()


func _build_vignette() -> void:
	_vignette_layer = CanvasLayer.new()
	_vignette_layer.name = "DepthVignetteLayer"
	_vignette_layer.layer = 0
	add_child(_vignette_layer)

	_vignette_rect = ColorRect.new()
	_vignette_rect.name = "DepthVignette"
	_vignette_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_layer.add_child(_vignette_rect)


func _physics_process(delta: float) -> void:
	if _stats == null or _stats.is_dead or _stats.max_health <= 0.0:
		_set_vignette(Color(0.0, 0.0, 0.0, 0.0))
		return

	_update_vignette()

	_tick_timer += delta
	if _tick_timer < _TICK_INTERVAL:
		return
	_tick_timer = 0.0
	_apply_tick()


func _update_vignette() -> void:
	if _vignette_rect == null:
		return
	var layer := _stats.get_layer()
	var target := _LAYER_VIGNETTE_COLOR.get(layer, Color(0.0, 0.0, 0.0, 0.0)) as Color
	# Override alpha with the tunable data value if present.
	var layer_key: String = (Constants.LAYER_NAMES[layer] as String).to_lower().replace(" ", "_")
	var hazard := GameManager.data.get("depth_hazard", {}) as Dictionary
	var alpha_override: Variant = hazard.get(layer_key + "_visibility_alpha", null)
	if alpha_override != null:
		target.a = float(alpha_override)
	_set_vignette(target)


func _set_vignette(color: Color) -> void:
	if _vignette_rect != null:
		_vignette_rect.color = color


func _apply_tick() -> void:
	var layer: int = _stats.get_layer()
	_apply_damage(layer)
	_apply_oxygen_drain(layer)


func _apply_damage(layer: int) -> void:
	var dps: Variant = _layer_dps(layer)
	if dps == null:
		return
	var dmg := float(dps) * _TICK_INTERVAL
	if dmg <= 0.0:
		return
	_stats.take_damage(dmg)
	depth_hazard_tick.emit(dmg)


func _apply_oxygen_drain(layer: int) -> void:
	if _stamina == null:
		return
	var drain: Variant = _layer_oxygen_drain(layer)
	if drain == null:
		return
	var amount := float(drain) * _TICK_INTERVAL
	if amount <= 0.0:
		return
	_stamina.drain(amount)
	oxygen_drained.emit(amount)


func _layer_dps(layer: int) -> Variant:
	var key: String = (Constants.LAYER_NAMES[layer] as String).to_lower().replace(" ", "_") + "_dps"
	return (GameManager.data.get("depth_hazard", {}) as Dictionary).get(key, null)


func _layer_oxygen_drain(layer: int) -> Variant:
	var key: String = (Constants.LAYER_NAMES[layer] as String).to_lower().replace(" ", "_") + "_oxygen_drain"
	return (GameManager.data.get("depth_hazard", {}) as Dictionary).get(key, null)
