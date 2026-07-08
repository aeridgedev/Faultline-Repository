## Faultline — per-layer ambient lighting (Part A visual polish).
##
## "Simpler lighting", per the brief: NO per-tile Light2D / shadows. A single
## world-space CanvasModulate is tweened between each layer's approved ambient
## tint as the player descends. Because a CanvasModulate multiplies EVERY canvas
## item on the world layer — including the z=-100 backdrop gradient — the
## background and the terrain/player retint together in one cheap operation.
##
## Core Hollow slow-pulses its tint (sine, ±5% opacity) to sell the alien
## semi-fluid interior. Values come from data/layer_visuals.json (FINAL art
## direction, not TBD balance); FALLBACK below mirrors them so it works headless.
class_name LayerVisuals
extends Node

const TRANSITION_TIME := 1.5     # seconds to tween between layer tints
const PULSE_SPEED := 1.2         # radians/sec of the Core Hollow sine
const PULSE_AMPLITUDE := 0.05    # ±opacity while pulsing

# FINAL approved palette (hex without '#'): ambient hue + opacity (how far the
# white world tint pulls toward the hue) + whether the layer slow-pulses.
const FALLBACK := {
	Constants.Layer.CRUST:       {"ambient": "e8dcc0", "opacity": 0.15, "pulse": false},
	Constants.Layer.MANTLE:      {"ambient": "ffcf8a", "opacity": 0.20, "pulse": false},
	Constants.Layer.OUTER_CORE:  {"ambient": "ff7a3d", "opacity": 0.28, "pulse": false},
	Constants.Layer.INNER_CORE:  {"ambient": "ff2e2e", "opacity": 0.35, "pulse": false},
	Constants.Layer.CORE_HOLLOW: {"ambient": "8a5cff", "opacity": 0.30, "pulse": true},
}

const LAYER_KEYS := {
	Constants.Layer.CRUST: "crust",
	Constants.Layer.MANTLE: "mantle",
	Constants.Layer.OUTER_CORE: "outer_core",
	Constants.Layer.INNER_CORE: "inner_core",
	Constants.Layer.CORE_HOLLOW: "core_hollow",
}

var _modulate: CanvasModulate = null
var _current_layer: int = -1
var _pulsing: bool = false
var _pulse_time: float = 0.0
var _base_ambient: Color = Color.WHITE
var _base_opacity: float = 0.0
var _tween: Tween = null


## Adds the CanvasModulate under `ambient_parent` (must be a world Node2D so the
## tint lands on canvas layer 0, not the HUD) and follows the player's layer.
func init(stats: PlayerStats, ambient_parent: Node) -> void:
	_modulate = CanvasModulate.new()
	_modulate.name = "LayerAmbient"
	ambient_parent.add_child(_modulate)
	_apply_layer_instant(Constants.Layer.CRUST)
	if stats != null:
		stats.layer_changed.connect(_on_layer_changed)


func _process(delta: float) -> void:
	if not _pulsing or _modulate == null:
		return
	_pulse_time += delta
	var op: float = clampf(_base_opacity + sin(_pulse_time * PULSE_SPEED) * PULSE_AMPLITUDE, 0.0, 1.0)
	_modulate.color = Color.WHITE.lerp(_base_ambient, op)


func _on_layer_changed(new_layer: int) -> void:
	if new_layer == _current_layer or _modulate == null:
		return
	_current_layer = new_layer
	var info := _layer_info(new_layer)
	var ambient := _hex(String(info.get("ambient", "ffffff")))
	var opacity := float(info.get("opacity", 0.0))
	var target := Color.WHITE.lerp(ambient, opacity)
	_pulsing = false                       # hold the pulse during the transition
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_modulate, "color", target, TRANSITION_TIME)
	if bool(info.get("pulse", false)):
		_base_ambient = ambient
		_base_opacity = opacity
		_pulse_time = 0.0
		_tween.tween_callback(func() -> void: _pulsing = true)


func _apply_layer_instant(layer: int) -> void:
	_current_layer = layer
	var info := _layer_info(layer)
	_base_ambient = _hex(String(info.get("ambient", "ffffff")))
	_base_opacity = float(info.get("opacity", 0.0))
	_pulse_time = 0.0
	_pulsing = bool(info.get("pulse", false))
	_modulate.color = Color.WHITE.lerp(_base_ambient, _base_opacity)


# data/layer_visuals.json entry for a layer, or the hardcoded FALLBACK.
func _layer_info(layer: int) -> Dictionary:
	var data: Dictionary = GameManager.data.get("layer_visuals", {}) if GameManager.data else {}
	var layers: Dictionary = data.get("layers", {}) if data is Dictionary else {}
	var key: String = LAYER_KEYS.get(layer, "crust")
	if layers is Dictionary and layers.has(key):
		return layers[key]
	return FALLBACK.get(layer, FALLBACK[Constants.Layer.CRUST])


func _hex(s: String) -> Color:
	return Color(s)
