## Faultline — world-space vertical boundaries for the 5 layers.
class_name LayerManager
extends Node

var _layer_heights: Dictionary = {}

func _ready() -> void:
	var keys := {
		Constants.Layer.CRUST:       "layer_height_crust",
		Constants.Layer.MANTLE:      "layer_height_mantle",
		Constants.Layer.OUTER_CORE:  "layer_height_outer_core",
		Constants.Layer.INNER_CORE:  "layer_height_inner_core",
		Constants.Layer.CORE_HOLLOW: "layer_height_core_hollow",
	}
	for layer in keys:
		var key: String = keys[layer]
		var value = GameManager.data.get(key, null)
		_layer_heights[layer] = value if value != null else null


func get_layer_top_y(layer: Constants.Layer) -> Variant:
	var sum := 0
	for l in range(layer):
		var h = _layer_heights.get(l, null)
		if h == null:
			return null
		sum += h
	return sum * Constants.TILE_SIZE


func get_layer_bottom_y(layer: Constants.Layer) -> Variant:
	var top = get_layer_top_y(layer)
	if top == null:
		return null
	var h = _layer_heights.get(layer, null)
	if h == null:
		return null
	return top + h * Constants.TILE_SIZE


func layer_at_y(world_y: float) -> Constants.Layer:
	var accumulated_px := 0
	for l in range(Constants.Layer.size()):
		var layer: int = l
		var h = _layer_heights.get(layer, null)
		# Heights TBD: return CRUST to avoid null-dereference crashes in callers.
		if h == null:
			return Constants.Layer.CRUST
		var _layer_top_px: int = accumulated_px
		var layer_bottom_px: int = accumulated_px + h * Constants.TILE_SIZE
		if world_y < layer_bottom_px:
			return layer as Constants.Layer
		accumulated_px = layer_bottom_px
	return Constants.Layer.CORE_HOLLOW


func layer_height_px(layer: Constants.Layer) -> Variant:
	var h = _layer_heights.get(layer, null)
	if h == null:
		return null
	return h * Constants.TILE_SIZE


func world_height_px() -> Variant:
	var total := 0
	for layer in _layer_heights:
		var h = _layer_heights[layer]
		if h == null:
			return null
		total += h * Constants.TILE_SIZE
	return total


func world_width_px() -> Variant:
	var w: Variant = GameManager.data.get("world_width_tiles", null)
	if w == null:
		return null
	return int(w) * Constants.TILE_SIZE
